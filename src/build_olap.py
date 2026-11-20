"""
build_olap.py — Q8: OLAP Semantic Model
Executes 01_olap_semantic_views.sql and validates all 13 views.
"""

import os
import sys
import time
import psycopg2
from tabulate import tabulate

# ── Path resolution ──────────────────────────────────────────────────────────
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'src'))
import config
DB_CONFIG = {
    'host': config.DB_HOST,
    'port': config.DB_PORT,
    'dbname': config.DB_NAME,
    'user': config.DB_USER,
    'password': config.DB_PASSWORD,
}

SQL_FILE = os.path.join(ROOT, 'sql', '05_analytics', '01_olap_semantic_views.sql')

# ── Views to validate after creation ─────────────────────────────────────────
VIEWS = [
    # (view_name, description, sample_query)
    ("pulsetrack_mart.vw_dim_date_hierarchy",
     "H1: Date Hierarchy",
     "SELECT COUNT(*) AS date_count, MIN(date_key) AS earliest, MAX(date_key) AS latest FROM pulsetrack_mart.vw_dim_date_hierarchy"),

    ("pulsetrack_mart.vw_dim_commercial_hierarchy",
     "H2: Commercial Hierarchy",
     "SELECT COUNT(*) AS combo_count, COUNT(DISTINCT advertiser_id) AS advertisers, COUNT(DISTINCT campaign_id) AS campaigns FROM pulsetrack_mart.vw_dim_commercial_hierarchy"),

    ("pulsetrack_mart.vw_dim_partner_hierarchy",
     "H3: Partner Hierarchy",
     "SELECT COUNT(*) AS partner_count, COUNT(DISTINCT channel) AS channels FROM pulsetrack_mart.vw_dim_partner_hierarchy"),

    ("pulsetrack_mart.vw_olap_rollup_campaign_time",
     "OP-1: Roll-Up (DAY/MONTH/QUARTER/YEAR)",
     "SELECT granularity, COUNT(*) AS rows FROM pulsetrack_mart.vw_olap_rollup_campaign_time GROUP BY granularity ORDER BY granularity"),

    ("pulsetrack_mart.vw_olap_drilldown_advertiser_campaign",
     "OP-2: Drill-Down (ADVERTISER/CAMPAIGN)",
     "SELECT drill_level, COUNT(*) AS rows FROM pulsetrack_mart.vw_olap_drilldown_advertiser_campaign GROUP BY drill_level ORDER BY drill_level"),

    ("pulsetrack_mart.vw_olap_slice_year_2025",
     "OP-3: Slice (Year=2025)",
     "SELECT COUNT(*) AS rows, ROUND(SUM(gross_revenue)::NUMERIC,2) AS total_gross_revenue FROM pulsetrack_mart.vw_olap_slice_year_2025"),

    ("pulsetrack_mart.vw_olap_dice_2025_social",
     "OP-4: Dice (Year=2025, Channel=Social)",
     "SELECT COUNT(*) AS rows, ROUND(SUM(adjusted_revenue)::NUMERIC,2) AS total_adj_revenue FROM pulsetrack_mart.vw_olap_dice_2025_social"),

    ("pulsetrack_mart.vw_olap_pivot_monthly_revenue_by_channel",
     "OP-5: Pivot (Monthly Revenue by Channel)",
     "SELECT month_year, total_revenue FROM pulsetrack_mart.vw_olap_pivot_monthly_revenue_by_channel ORDER BY month_year LIMIT 5"),

    ("pulsetrack_mart.vw_olap_topn_partner_monthly",
     "OP-6: Top-N Partners (Monthly, Top 10)",
     "SELECT month_year, COUNT(*) AS partners_ranked FROM pulsetrack_mart.vw_olap_topn_partner_monthly GROUP BY month_year ORDER BY month_year LIMIT 5"),

    ("pulsetrack_mart.vw_olap_mom_revenue_growth",
     "OP-7: MoM Revenue Growth",
     "SELECT advertiser_name, month_year, adjusted_revenue, mom_growth_pct FROM pulsetrack_mart.vw_olap_mom_revenue_growth WHERE mom_growth_pct IS NOT NULL ORDER BY ABS(mom_growth_pct) DESC LIMIT 5"),

    ("pulsetrack_mart.vw_olap_qoq_revenue_growth",
     "OP-8: QoQ Revenue Growth",
     "SELECT advertiser_name, quarter_name, adjusted_revenue, qoq_growth_pct FROM pulsetrack_mart.vw_olap_qoq_revenue_growth WHERE qoq_growth_pct IS NOT NULL ORDER BY ABS(qoq_growth_pct) DESC LIMIT 5"),

    ("pulsetrack_mart.vw_olap_yoy_revenue_growth",
     "OP-9: YoY Revenue Growth",
     "SELECT advertiser_name, year, adjusted_revenue, yoy_growth_pct FROM pulsetrack_mart.vw_olap_yoy_revenue_growth WHERE yoy_growth_pct IS NOT NULL ORDER BY ABS(yoy_growth_pct) DESC LIMIT 5"),

    ("pulsetrack_mart.vw_olap_campaign_revenue_contribution",
     "OP-10: Campaign Revenue Contribution %",
     "SELECT quarter_name, campaign_name, revenue_contribution_pct, revenue_rank_in_quarter FROM pulsetrack_mart.vw_olap_campaign_revenue_contribution ORDER BY quarter_name, revenue_rank_in_quarter LIMIT 5"),
]


def main():
    t0 = time.time()
    print("=" * 70)
    print("Q8: OLAP Semantic Model — Build & Validate")
    print("=" * 70)

    conn = psycopg2.connect(**DB_CONFIG)
    conn.autocommit = True
    cur = conn.cursor()

    # ── Step 1: Execute the SQL file via psql ────────────────────────────────
    print("\n[1/2] Creating OLAP views from SQL file...")
    import subprocess
    env = os.environ.copy()
    env['PGPASSWORD'] = DB_CONFIG['password']
    result = subprocess.run(
        ['psql',
         '-h', str(DB_CONFIG['host']),
         '-p', str(DB_CONFIG['port']),
         '-U', DB_CONFIG['user'],
         '-d', DB_CONFIG['dbname'],
         '-f', SQL_FILE,
         '-v', 'ON_ERROR_STOP=1'],
        capture_output=True, text=True, env=env
    )
    if result.returncode != 0:
        print("PSQL ERROR:", result.stderr)
        sys.exit(1)
    view_count = result.stdout.count('CREATE VIEW')
    print(f"    ✓ {view_count} views created successfully")
    if result.stdout.strip():
        print("    psql output:", result.stdout.strip()[:200])

    # ── Step 2: Validate each view ────────────────────────────────────────────
    print("\n[2/2] Validating views...")
    results = []
    all_pass = True

    for view_name, description, sample_sql in VIEWS:
        try:
            cur.execute(sample_sql)
            rows = cur.fetchall()
            col_names = [desc[0] for desc in cur.description]
            status = "PASS ✓"
            # Format first result row for display
            first = rows[0] if rows else ("(empty)",)
            detail = " | ".join(f"{col_names[i]}={first[i]}" for i in range(min(3, len(col_names))))
        except Exception as e:
            status = "FAIL ✗"
            detail = str(e)[:80]
            all_pass = False

        results.append([description, status, detail])
        print(f"    {status} {description}")

    print("\n" + "─" * 70)
    print(tabulate(results, headers=["View", "Status", "Sample Output"], tablefmt="simple"))

    elapsed = time.time() - t0
    print(f"\n{'─' * 70}")
    if all_pass:
        print(f"✅  ALL {len(VIEWS)} OLAP VIEWS VALIDATED  ({elapsed:.2f}s)")
    else:
        print(f"⚠️  SOME VIEWS FAILED — review output above  ({elapsed:.2f}s)")
    print("─" * 70)

    # ── Step 3: Print sample OLAP query results ───────────────────────────────
    print("\n📊 SAMPLE RESULTS")
    print("\n── OP-5 Pivot: Monthly Revenue by Channel (first 5 months) ─────────")
    cur.execute("SELECT month_year, social_revenue, display_revenue, search_revenue, total_revenue FROM pulsetrack_mart.vw_olap_pivot_monthly_revenue_by_channel ORDER BY month_year LIMIT 5")
    rows = cur.fetchall()
    print(tabulate(rows, headers=["Month","Social","Display","Search","Total"], tablefmt="simple"))

    print("\n── OP-6 Top-N Partners (first available month, rank 1–5) ───────────")
    cur.execute("SELECT month_year, partner_name, partner_channel, attributed_revenue, revenue_rank FROM pulsetrack_mart.vw_olap_topn_partner_monthly WHERE revenue_rank <= 5 ORDER BY month_year, revenue_rank LIMIT 15")
    rows = cur.fetchall()
    print(tabulate(rows, headers=["Month","Partner","Channel","Attr.Revenue","Rank"], tablefmt="simple"))

    print("\n── OP-7 MoM Growth: Top 5 Swings ───────────────────────────────────")
    cur.execute("SELECT advertiser_name, month_year, adjusted_revenue, prev_month_revenue, mom_growth_pct FROM pulsetrack_mart.vw_olap_mom_revenue_growth WHERE mom_growth_pct IS NOT NULL ORDER BY ABS(mom_growth_pct) DESC LIMIT 5")
    rows = cur.fetchall()
    print(tabulate(rows, headers=["Advertiser","Month","Revenue","Prev Month","MoM%"], tablefmt="simple"))

    print("\n── OP-10 Revenue Contribution %: Top 5 campaigns in first quarter ──")
    cur.execute("""
        SELECT quarter_name, campaign_name, advertiser_name, campaign_revenue, revenue_contribution_pct
        FROM pulsetrack_mart.vw_olap_campaign_revenue_contribution
        WHERE revenue_rank_in_quarter <= 5
        ORDER BY quarter_name, revenue_rank_in_quarter LIMIT 10
    """)
    rows = cur.fetchall()
    print(tabulate(rows, headers=["Quarter","Campaign","Advertiser","Revenue","Contrib%"], tablefmt="simple"))

    conn.close()


if __name__ == '__main__':
    main()
