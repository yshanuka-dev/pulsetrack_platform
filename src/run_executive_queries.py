"""
run_executive_queries.py — Q9: Business Analytics & Executive Queries
Runs all 10 executive queries and prints tabulated results.
"""
import os, sys, time, json
import psycopg2
from tabulate import tabulate

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'src'))
import config

DB_CONFIG = {
    'host': config.DB_HOST, 'port': config.DB_PORT,
    'dbname': config.DB_NAME, 'user': config.DB_USER, 'password': config.DB_PASSWORD,
}

QUERIES = {
    "EQ-1": {
        "title": "Top Advertisers by Quarterly Revenue",
        "sql": """
            WITH quarterly_adv AS (
                SELECT quarter_name, advertiser_name,
                    ROUND(SUM(campaign_revenue)::NUMERIC, 2)  AS total_revenue,
                    SUM(conversions)                           AS total_conversions,
                    DENSE_RANK() OVER (PARTITION BY quarter_name ORDER BY SUM(campaign_revenue) DESC) AS revenue_rank
                FROM pulsetrack_mart.vw_olap_campaign_revenue_contribution
                GROUP BY quarter_name, advertiser_name
            )
            SELECT quarter_name, revenue_rank, advertiser_name, total_revenue, total_conversions
            FROM quarterly_adv WHERE revenue_rank <= 3
            ORDER BY quarter_name, revenue_rank
        """,
        "headers": ["Quarter","Rank","Advertiser","Revenue","Conversions"]
    },
    "EQ-2": {
        "title": "Campaigns: High CTR but Low CVR (Funnel Drop-off)",
        "sql": """
            WITH campaign_funnel AS (
                SELECT campaign_id, campaign_name, advertiser_name,
                    SUM(impression_count) AS imps, SUM(click_count) AS clicks,
                    SUM(conversion_count) AS convs,
                    ROUND(CASE WHEN SUM(impression_count)>0 THEN SUM(click_count)::NUMERIC/SUM(impression_count)*100 ELSE 0 END,4) AS ctr_pct,
                    ROUND(CASE WHEN SUM(click_count)>0 THEN SUM(conversion_count)::NUMERIC/SUM(click_count)*100 ELSE 0 END,4) AS cvr_pct
                FROM pulsetrack_mart.mart_campaign_performance_daily
                GROUP BY campaign_id, campaign_name, advertiser_name
            ),
            ranked AS (
                SELECT *, PERCENT_RANK() OVER (ORDER BY ctr_pct DESC) AS ctr_prank,
                           PERCENT_RANK() OVER (ORDER BY cvr_pct ASC)  AS cvr_low_prank
                FROM campaign_funnel WHERE imps > 500
            )
            SELECT campaign_name, advertiser_name, ctr_pct, cvr_pct,
                   ROUND((ctr_pct - cvr_pct)::NUMERIC,4) AS funnel_gap
            FROM ranked WHERE ctr_prank<=0.20 AND cvr_low_prank<=0.20
            ORDER BY funnel_gap DESC LIMIT 10
        """,
        "headers": ["Campaign","Advertiser","CTR%","CVR%","Funnel Gap"]
    },
    "EQ-3": {
        "title": "Top 15 Partners by Attributed Revenue (Affiliate ROI)",
        "sql": """
            SELECT partner_name, partner_channel,
                   ROUND(SUM(attributed_revenue)::NUMERIC,2) AS total_attr_revenue,
                   ROUND(SUM(attributed_conversions)::NUMERIC,2) AS attr_conversions,
                   ROUND(SUM(attributed_revenue)::NUMERIC/NULLIF(SUM(attributed_conversions),0),2) AS rev_per_conv,
                   COUNT(DISTINCT month_year) AS active_months
            FROM pulsetrack_mart.vw_olap_topn_partner_monthly
            GROUP BY partner_name, partner_channel
            ORDER BY total_attr_revenue DESC LIMIT 15
        """,
        "headers": ["Partner","Channel","Attr.Revenue","Attr.Convs","Rev/Conv","Months"]
    },
    "EQ-4": {
        "title": "Portfolio MoM Revenue Change",
        "sql": """
            WITH pm AS (
                SELECT month_year, ROUND(SUM(adjusted_revenue)::NUMERIC,2) AS revenue
                FROM pulsetrack_mart.vw_olap_mom_revenue_growth
                GROUP BY month_year
            )
            SELECT month_year, revenue,
                   LAG(revenue) OVER (ORDER BY month_year) AS prev_revenue,
                   ROUND((revenue - LAG(revenue) OVER (ORDER BY month_year))::NUMERIC,2) AS mom_delta,
                   ROUND(CASE WHEN LAG(revenue) OVER (ORDER BY month_year) <> 0
                         THEN (revenue-LAG(revenue) OVER (ORDER BY month_year))/ABS(LAG(revenue) OVER (ORDER BY month_year))*100
                         ELSE NULL END::NUMERIC,2) AS mom_pct
            FROM pm ORDER BY month_year
        """,
        "headers": ["Month","Revenue","Prev Revenue","MoM Delta","MoM%"]
    },
    "EQ-5": {
        "title": "Campaigns Exceeding 10% of Advertiser Revenue",
        "sql": """
            WITH adv_total AS (
                SELECT advertiser_id, SUM(adjusted_revenue) AS adv_rev
                FROM pulsetrack_mart.mart_campaign_performance_daily
                GROUP BY advertiser_id
            ),
            camp_total AS (
                SELECT campaign_id, campaign_name, advertiser_id, advertiser_name,
                       SUM(adjusted_revenue) AS camp_rev,
                       SUM(conversion_count) AS convs
                FROM pulsetrack_mart.mart_campaign_performance_daily
                GROUP BY campaign_id, campaign_name, advertiser_id, advertiser_name
            )
            SELECT c.advertiser_name, c.campaign_name,
                   ROUND(c.camp_rev::NUMERIC,2) AS campaign_revenue,
                   ROUND(a.adv_rev::NUMERIC,2) AS advertiser_revenue,
                   ROUND(c.camp_rev/NULLIF(a.adv_rev,0)*100::NUMERIC,2) AS pct_of_adv
            FROM camp_total c JOIN adv_total a USING(advertiser_id)
            WHERE c.camp_rev/NULLIF(a.adv_rev,0) > 0.10
            ORDER BY pct_of_adv DESC
        """,
        "headers": ["Advertiser","Campaign","Camp.Revenue","Adv.Revenue","% of Adv"]
    },
    "EQ-6": {
        "title": "Underperforming Campaigns (CVR > 1 StdDev Below Average)",
        "sql": """
            WITH camp_avg AS (
                SELECT campaign_id, campaign_name, advertiser_name,
                       AVG(cvr_pct) AS avg_cvr, STDDEV(cvr_pct) AS std_cvr,
                       COUNT(*) AS day_cnt
                FROM pulsetrack_mart.mart_campaign_performance_daily
                WHERE impression_count>0
                GROUP BY campaign_id, campaign_name, advertiser_name HAVING COUNT(*)>=10
            ),
            actual AS (
                SELECT m.campaign_id, m.campaign_name, m.advertiser_name,
                       ROUND(ca.avg_cvr::NUMERIC,4) AS avg_cvr,
                       ROUND(SUM(m.conversion_count)::NUMERIC/NULLIF(SUM(m.click_count),0)*100,4) AS actual_cvr,
                       ROUND((ca.avg_cvr - SUM(m.conversion_count)::NUMERIC/NULLIF(SUM(m.click_count),0)*100)::NUMERIC,4) AS cvr_deficit,
                       SUM(m.impression_count) AS impressions
                FROM pulsetrack_mart.mart_campaign_performance_daily m
                JOIN camp_avg ca USING(campaign_id)
                WHERE m.impression_count>100
                GROUP BY m.campaign_id, m.campaign_name, m.advertiser_name, ca.avg_cvr, ca.std_cvr
                HAVING SUM(m.conversion_count)::NUMERIC/NULLIF(SUM(m.click_count),0)*100 < ca.avg_cvr - ca.std_cvr
            )
            SELECT campaign_name, advertiser_name, avg_cvr, actual_cvr, cvr_deficit, impressions
            FROM actual ORDER BY cvr_deficit DESC LIMIT 10
        """,
        "headers": ["Campaign","Advertiser","Avg CVR","Actual CVR","CVR Deficit","Impressions"]
    },
    "EQ-7": {
        "title": "Advertiser Performance Before/After AM Reassignment (SCD-2)",
        "sql": """
            WITH am_periods AS (
                SELECT advertiser_id, advertiser_name, am_name, is_current_am_assignment,
                       ROUND(SUM(monthly_gross_revenue)::NUMERIC,2) AS gross_rev,
                       ROUND(SUM(monthly_adjusted_revenue)::NUMERIC,2) AS adj_rev,
                       SUM(monthly_conversions) AS conversions,
                       COUNT(DISTINCT month_year) AS months,
                       MIN(month_year) AS from_month, MAX(month_year) AS to_month
                FROM pulsetrack_mart.mart_advertiser_am_monthly
                GROUP BY advertiser_id, advertiser_name, am_name, is_current_am_assignment
            ),
            reassigned AS (
                SELECT advertiser_id FROM am_periods GROUP BY advertiser_id HAVING COUNT(DISTINCT am_name)>1
            )
            SELECT a.advertiser_name,
                   CASE WHEN a.is_current_am_assignment THEN 'CURRENT' ELSE 'PREVIOUS' END AS am_period,
                   a.am_name, a.from_month, a.to_month, a.months,
                   a.gross_rev, a.conversions,
                   ROUND(a.gross_rev/NULLIF(a.months,0)::NUMERIC,2) AS avg_monthly_rev
            FROM am_periods a JOIN reassigned r USING(advertiser_id)
            ORDER BY a.advertiser_name, a.is_current_am_assignment
        """,
        "headers": ["Advertiser","Period","AM Name","From","To","Months","Gross Rev","Convs","Avg/Month"]
    },
    "EQ-8": {
        "title": "Attribution % Per Partner (Weighted Multi-Touch)",
        "sql": """
            WITH pt AS (
                SELECT partner_name, partner_channel,
                       SUM(total_touchpoints) AS touchpoints,
                       ROUND(SUM(attributed_conversions)::NUMERIC,2) AS attr_convs,
                       ROUND(SUM(attributed_revenue)::NUMERIC,2) AS attr_rev,
                       SUM(first_touch_count) AS first_touch,
                       SUM(last_touch_count) AS last_touch
                FROM pulsetrack_mart.mart_partner_attribution_daily GROUP BY partner_name, partner_channel
            ),
            gt AS (SELECT SUM(attr_rev) AS total FROM pt)
            SELECT p.partner_name, p.partner_channel, p.attr_rev,
                   ROUND(p.attr_rev/NULLIF(g.total,0)*100::NUMERIC,4) AS attribution_pct,
                   ROUND(p.first_touch::NUMERIC/NULLIF(p.touchpoints,0)*100,2) AS first_touch_pct,
                   ROUND(p.last_touch::NUMERIC/NULLIF(p.touchpoints,0)*100,2) AS last_touch_pct,
                   DENSE_RANK() OVER (ORDER BY p.attr_rev DESC) AS rank
            FROM pt p CROSS JOIN gt g ORDER BY p.attr_rev DESC LIMIT 15
        """,
        "headers": ["Partner","Channel","Attr.Rev","Attr%","1st Touch%","Last Touch%","Rank"]
    },
    "EQ-9": {
        "title": "Campaigns: Impressions Rising, Conversions Declining (Creative Fatigue)",
        "sql": """
            WITH monthly_camp AS (
                SELECT campaign_id, campaign_name, advertiser_name, period_label AS month_year,
                       impressions, conversions,
                       ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY period_label) AS rn,
                       COUNT(*) OVER (PARTITION BY campaign_id) AS month_cnt
                FROM pulsetrack_mart.vw_olap_rollup_campaign_time
                WHERE granularity='MONTH'
            ),
            slopes AS (
                SELECT campaign_id, campaign_name, advertiser_name, month_cnt,
                       SUM(impressions) AS total_imps, SUM(conversions) AS total_convs,
                       REGR_SLOPE(impressions::FLOAT, rn::FLOAT) AS imp_slope,
                       REGR_SLOPE(conversions::FLOAT, rn::FLOAT) AS conv_slope
                FROM monthly_camp WHERE month_cnt>=3
                GROUP BY campaign_id, campaign_name, advertiser_name, month_cnt
            )
            SELECT campaign_name, advertiser_name,
                   ROUND(imp_slope::NUMERIC,2) AS impression_trend,
                   ROUND(conv_slope::NUMERIC,4) AS conversion_trend,
                   month_cnt, total_imps, total_convs
            FROM slopes WHERE imp_slope>0 AND conv_slope<0
            ORDER BY ABS(conv_slope) DESC LIMIT 10
        """,
        "headers": ["Campaign","Advertiser","Imp Trend","Conv Trend","Months","Total Imps","Total Convs"]
    },
    "EQ-10": {
        "title": "Financial Impact of Late Adjustments (Gross vs Net Reconciliation)",
        "sql": """
            SELECT month_year,
                   ROUND(SUM(gross_revenue)::NUMERIC,2) AS gross_revenue,
                   ROUND(SUM(payout_amount)::NUMERIC,2) AS total_payout,
                   ROUND(SUM(net_margin)::NUMERIC,2) AS net_margin,
                   ROUND(SUM(adjustment_delta)::NUMERIC,2) AS adj_delta,
                   ROUND(SUM(adjusted_revenue)::NUMERIC,2) AS adj_revenue,
                   SUM(conversion_count) AS conversions,
                   ROUND(SUM(adjustment_delta)/NULLIF(SUM(gross_revenue),0)*100::NUMERIC,4) AS adj_pct_of_gross
            FROM pulsetrack_mart.mart_campaign_performance_daily
            WHERE calendar_date IS NOT NULL
            GROUP BY month_year
            ORDER BY month_year
        """,
        "headers": ["Month","Gross Rev","Payout","Net Margin","Adj Delta","Adj Revenue","Convs","Adj%"]
    },
}


def main():
    t0 = time.time()
    print("=" * 80)
    print("Q9: Business Analytics & Executive Queries")
    print("=" * 80)

    conn = psycopg2.connect(**DB_CONFIG)
    conn.autocommit = True
    cur = conn.cursor()

    all_results = {}

    for eq_id, q in QUERIES.items():
        print(f"\n{'─'*80}")
        print(f"  {eq_id}: {q['title']}")
        print(f"{'─'*80}")
        try:
            cur.execute(q["sql"])
            rows = cur.fetchall()
            all_results[eq_id] = {"title": q["title"], "rows": rows, "headers": q["headers"]}
            print(tabulate(rows, headers=q["headers"], tablefmt="simple", floatfmt=".2f"))
            print(f"  → {len(rows)} rows returned")
        except Exception as e:
            print(f"  ERROR: {e}")
            all_results[eq_id] = {"title": q["title"], "error": str(e)}

    elapsed = time.time() - t0
    print(f"\n{'='*80}")
    print(f"All 10 queries executed in {elapsed:.2f}s")
    print(f"{'='*80}")

    # Save results as JSON for doc generation
    out_path = os.path.join(ROOT, 'docs', 'q9_results.json')
    # Convert non-serializable types
    def convert(obj):
        import decimal
        if isinstance(obj, decimal.Decimal): return float(obj)
        if isinstance(obj, (bytes,)): return str(obj)
        raise TypeError(f"Type {type(obj)} not serializable")
    with open(out_path, 'w') as f:
        json.dump({k: {kk: vv for kk, vv in v.items() if kk != 'rows'} for k, v in all_results.items()}, f, indent=2, default=convert)
    print(f"Results summary saved to {out_path}")

    conn.close()

if __name__ == '__main__':
    main()
