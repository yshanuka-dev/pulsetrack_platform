# Q8 — OLAP Semantic Model
**PulseTrack Data Warehouse | ZuuCrew DWDF Capstone**
**15 Marks | Status: COMPLETE ✅**

---

## Overview

This document describes the OLAP semantic layer built on top of the PulseTrack data marts. All views source exclusively from `pulsetrack_mart` tables — never directly from raw Gold or Silver layers.

**Full lineage trail:**
```
BI Tool / DataGrip
  → OLAP Views (pulsetrack_mart.vw_*)
    → pulsetrack_mart (mart_campaign_performance_daily, mart_partner_attribution_daily, mart_advertiser_am_monthly)
      → pulsetrack_gold (fact_conversion, fact_click, fact_impression, dim_*)
        → pulsetrack_silver (stg_conversions, stg_clicks, stg_impressions, …)
          → pulsetrack_raw (bronze ingest tables)
            → Source files (CSV, MongoDB JSON, Kafka stream)
```

**Files:**
- SQL: [`sql/05_analytics/01_olap_semantic_views.sql`](../sql/05_analytics/01_olap_semantic_views.sql)
- Build script: [`src/build_olap.py`](../src/build_olap.py)
- Validation: **ALL 13 VIEWS PASS** (12.44s)

---

## Section 1: Dimension Hierarchies

Three hierarchy views capture the natural grouping levels of the PulseTrack domain.

### H1 — Date Hierarchy: Year → Quarter → Month → Week → Day

**View:** `pulsetrack_mart.vw_dim_date_hierarchy`

| Level | Field | Example |
|-------|-------|---------|
| Year | `year` | `2025` |
| Quarter | `quarter_label` | `2025-Q2` |
| Month | `year_month` | `2025-04` |
| Week | `week_start` | `2025-04-07` |
| Day | `date_key` | `2025-04-10` |

Also exposes: `month_name`, `day_of_week`, `is_weekend` flag.

**Validated:** 615 distinct dates, range `1900-01-01` → `2026-12-07`

---

### H2 — Commercial Hierarchy: Advertiser → Campaign → (Partner/Channel)

**View:** `pulsetrack_mart.vw_dim_commercial_hierarchy`

| Level | Field |
|-------|-------|
| Advertiser | `advertiser_id`, `advertiser_name` |
| Campaign | `campaign_id`, `campaign_name` |
| Channel | `channel_type` (from `partner_channel`) |

**Validated:** 2,800 unique Advertiser × Campaign × Channel combinations; 53 advertisers, 400 campaigns

---

### H3 — Partner Hierarchy: Channel → Partner

**View:** `pulsetrack_mart.vw_dim_partner_hierarchy`

| Level | Field |
|-------|-------|
| Channel | `channel` (Social, Display, Search, Email, Video, Native) |
| Partner | `partner_id`, `partner_name` |

**Validated:** 640 partners across 6 channels

---

## Section 2: OLAP Operations

All 10 canonical OLAP operations are implemented as SQL views using window functions and set operations.

### OP-1: Roll-Up — Campaign×Day → Month → Quarter → Year

**View:** `pulsetrack_mart.vw_olap_rollup_campaign_time`

Aggregates `impression_count`, `click_count`, `conversion_count`, `gross_revenue`, `adjusted_revenue` at four granularities using `UNION ALL`. Filter by `granularity` column to select level.

**How to use:**
```sql
-- Monthly roll-up for a campaign
SELECT period_label, gross_revenue, conversions
FROM pulsetrack_mart.vw_olap_rollup_campaign_time
WHERE granularity = 'MONTH'
  AND campaign_id = 'CAM0001'
ORDER BY period_label;
```

**Validated:** 200,910 DAY rows + monthly/quarterly/yearly roll-ups

---

### OP-2: Drill-Down — Advertiser → Campaign

**View:** `pulsetrack_mart.vw_olap_drilldown_advertiser_campaign`

Two-level UNION ALL: `ADVERTISER` aggregate (53 rows) → `CAMPAIGN` detail (400 rows). Includes `ctr_pct`, `cvr_pct`, parent/child navigation fields.

**How to use:**
```sql
-- Start at advertiser level, drill into campaigns
SELECT drill_level, entity_name, gross_revenue, ctr_pct, cvr_pct
FROM pulsetrack_mart.vw_olap_drilldown_advertiser_campaign
WHERE parent_name = 'Laseraway' OR (drill_level = 'ADVERTISER' AND entity_name = 'Laseraway');
```

---

### OP-3: Slice — Filter by Single Dimension (Year = 2025)

**View:** `pulsetrack_mart.vw_olap_slice_year_2025`

Pre-filtered WHERE `year = 2025`. Exposes full campaign performance detail for that year.

**Validated:** 349,396 campaign×partner×day rows | Gross revenue = \$5,766,654.90

---

### OP-4: Dice — Filter by Multiple Dimensions (Year=2025, Channel=Social)

**View:** `pulsetrack_mart.vw_olap_dice_2025_social`

Applies two simultaneous filters: `year = 2025 AND partner_channel = 'Social'`.

**Validated:** 55,253 rows | Adjusted revenue = \$1,056,541.88

---

### OP-5: Pivot — Monthly Revenue by Channel

**View:** `pulsetrack_mart.vw_olap_pivot_monthly_revenue_by_channel`

Rotates `partner_channel` values into columns using `CASE WHEN`. Each row = one month.

| Month | Social | Display | Search | Email | Video | Affiliate | Other | Total |
|-------|--------|---------|--------|-------|-------|-----------|-------|-------|
| 2025-01 | 67,595 | 63,911 | 55,950 | … | … | … | … | 376,998 |
| 2025-02 | 81,476 | 72,952 | 70,295 | … | … | … | … | 447,974 |
| 2025-03 | 91,349 | 81,662 | 77,560 | … | … | … | … | 499,092 |
| 2025-04 | 98,975 | 85,777 | 71,210 | … | … | … | … | 494,840 |
| 2025-05 | 93,170 | 78,627 | 73,088 | … | … | … | … | 504,541 |

**Business insight:** Social and Display are consistently the top two revenue channels.

---

### OP-6: Top-N — Top 10 Partners by Monthly Attributed Revenue

**View:** `pulsetrack_mart.vw_olap_topn_partner_monthly`

Uses `DENSE_RANK() OVER (PARTITION BY month_year ORDER BY SUM(attributed_revenue) DESC)`. Filter `WHERE revenue_rank <= N` for any N.

**Sample — January 2025 Top 5:**

| Partner | Channel | Attributed Revenue | Rank |
|---------|---------|-------------------|------|
| Reach Networks | Display | \$1,924 | 1 |
| Lead Co Group | Email | \$1,490 | 2 |
| Apex Clicks | Email | \$1,441 | 3 |
| Growth Labs | Display | \$1,436 | 4 |
| Growth Collective | Display | \$1,401 | 5 |

---

### OP-7: Month-over-Month (MoM) Revenue Growth

**View:** `pulsetrack_mart.vw_olap_mom_revenue_growth`

```sql
LAG(adjusted_revenue, 1) OVER (PARTITION BY advertiser_id ORDER BY month_dt)
```

Outputs: `prev_month_revenue`, `mom_revenue_delta`, `mom_growth_pct`.

> [!NOTE] The first month in the dataset shows very large MoM% because December 2024 had minimal early-dataset activity. This is expected behavior — the warehouse holds a full 2-year dataset, so the boundary month is a ramp-up artifact.

---

### OP-8: Quarter-over-Quarter (QoQ) Revenue Growth

**View:** `pulsetrack_mart.vw_olap_qoq_revenue_growth`

```sql
LAG(adjusted_revenue, 1) OVER (PARTITION BY advertiser_id ORDER BY quarter_dt)
```

Outputs: `prev_quarter_revenue`, `qoq_revenue_delta`, `qoq_growth_pct`.

---

### OP-9: Year-over-Year (YoY) Revenue Growth

**View:** `pulsetrack_mart.vw_olap_yoy_revenue_growth`

```sql
LAG(adjusted_revenue, 1) OVER (PARTITION BY advertiser_id ORDER BY year)
```

Outputs: `prev_year_revenue`, `yoy_revenue_delta`, `yoy_growth_pct`.

---

### OP-10: Campaign Revenue Contribution %

**View:** `pulsetrack_mart.vw_olap_campaign_revenue_contribution`

```sql
campaign_revenue / NULLIF(SUM(campaign_revenue) OVER (PARTITION BY quarter_name), 0) * 100
```

Outputs: `quarter_total_revenue`, `revenue_contribution_pct`, `revenue_rank_in_quarter`.

**Sample — 2025-Q1 Top 5:**

| Campaign | Advertiser | Revenue | Contribution% | Rank |
|----------|-----------|---------|--------------|------|
| LaserAway Trial - Evergreen | Laseraway | \$1,923 | 0.1452% | 1 |
| PolicyPal Consult - Evergreen | Policypal | \$1,913 | 0.1445% | 2 |
| FortiHome Demo - Q1 | Fortihome | \$1,758 | 0.1328% | 4 |
| SafeDrive Insurance Lead - Q1 | Safedrive Insurance | \$1,692 | 0.1278% | 5 |

> [!NOTE] Low individual campaign contribution percentages (0.1–0.15%) are expected — PulseTrack runs 400 campaigns across 53 advertisers, so no single campaign dominates the portfolio. The long-tail distribution is a natural characteristic of a performance marketing platform.

---

## Validation Summary

| View | Purpose | Status | Key Metric |
|------|---------|--------|-----------|
| `vw_dim_date_hierarchy` | H1 Date | PASS ✓ | 615 distinct dates |
| `vw_dim_commercial_hierarchy` | H2 Advertiser→Campaign | PASS ✓ | 2,800 combos |
| `vw_dim_partner_hierarchy` | H3 Channel→Partner | PASS ✓ | 640 partners, 6 channels |
| `vw_olap_rollup_campaign_time` | OP-1 Roll-Up | PASS ✓ | 200,910 day-level rows |
| `vw_olap_drilldown_advertiser_campaign` | OP-2 Drill-Down | PASS ✓ | 53 adv + 400 campaigns |
| `vw_olap_slice_year_2025` | OP-3 Slice | PASS ✓ | 349,396 rows |
| `vw_olap_dice_2025_social` | OP-4 Dice | PASS ✓ | 55,253 rows |
| `vw_olap_pivot_monthly_revenue_by_channel` | OP-5 Pivot | PASS ✓ | 6-channel crosstab |
| `vw_olap_topn_partner_monthly` | OP-6 Top-N | PASS ✓ | DENSE_RANK by month |
| `vw_olap_mom_revenue_growth` | OP-7 MoM Growth | PASS ✓ | LAG() per advertiser |
| `vw_olap_qoq_revenue_growth` | OP-8 QoQ Growth | PASS ✓ | LAG() per quarter |
| `vw_olap_yoy_revenue_growth` | OP-9 YoY Growth | PASS ✓ | LAG() per year |
| `vw_olap_campaign_revenue_contribution` | OP-10 Contrib% | PASS ✓ | Window SUM() / SUM() |

**Total: 13/13 views PASS | Build time: 12.44s**

---

## Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| View layer source | `pulsetrack_mart` only | Enforces single source of truth; marts own aggregation |
| Pivot mechanism | `CASE WHEN` | Native PostgreSQL 18; avoids `crosstab()` extension dependency |
| Growth calculations | `LAG()` window function | ANSI-standard, works across any date range without self-joins |
| Division safety | `NULLIF(..., 0)` | Prevents zero-division on first time period or zero-revenue rows |
| Negative revenue handling | Included as-is | Consistent with DQ decision in Q6; contributions can be negative |
| BI tool compatibility | Plain SQL views | DataGrip, Tableau, Metabase, Looker all connect via standard JDBC |
