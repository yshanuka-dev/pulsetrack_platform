-- =============================================================================
-- Q8: OLAP Semantic Model — Dimension Hierarchies & OLAP Operations
-- PulseTrack Data Warehouse | pulsetrack_dw
-- =============================================================================
-- All views source exclusively from pulsetrack_mart (not raw Gold facts).
-- Lineage: BI Tool → OLAP Views → pulsetrack_mart → pulsetrack_gold → pulsetrack_silver → pulsetrack_raw → Source
--
-- Column mapping from mart tables:
--   mart_campaign_performance_daily:
--     calendar_date, year, quarter_name, month_year, month_name
--     campaign_id, campaign_name, advertiser_id, advertiser_name
--     partner_id, partner_name, partner_channel
--     impression_count, click_count, unique_click_count, conversion_count
--     gross_revenue, payout_amount, net_margin, adjusted_revenue
--     ctr_pct, cvr_pct, revenue_per_click, revenue_per_conversion
--   mart_partner_attribution_daily:
--     calendar_date, year, quarter_name, month_year
--     partner_id, partner_name, partner_channel
--     campaign_id, campaign_name
--     total_touchpoints, attributed_conversions, attributed_revenue
--     first_touch_count, mid_touch_count, last_touch_count
--   mart_advertiser_am_monthly:
--     year, quarter_name, month_year, month_name
--     advertiser_id, advertiser_name, vertical
--     am_id, am_name, am_team, am_region, is_current_am_assignment
--     monthly_conversions, monthly_gross_revenue, monthly_payout_amount
--     monthly_margin, monthly_adjustment_delta, monthly_adjusted_revenue
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 1: DIMENSION HIERARCHIES
-- ─────────────────────────────────────────────────────────────────────────────

-- H1: Date Hierarchy — Year → Quarter → Month → Day
CREATE OR REPLACE VIEW pulsetrack_mart.vw_dim_date_hierarchy AS
SELECT
    calendar_date                                        AS date_key,
    TO_CHAR(calendar_date, 'YYYY-MM-DD')                AS full_date,
    DATE_TRUNC('week',  calendar_date)::DATE             AS week_start,
    DATE_TRUNC('month', calendar_date)::DATE             AS month_start,
    month_year                                           AS year_month,
    DATE_TRUNC('quarter', calendar_date)::DATE           AS quarter_start,
    quarter_name                                         AS quarter_label,
    DATE_TRUNC('year', calendar_date)::DATE              AS year_start,
    year,
    EXTRACT(QUARTER FROM calendar_date)::INT             AS quarter_num,
    EXTRACT(MONTH FROM calendar_date)::INT               AS month_num,
    month_name,
    EXTRACT(DOW FROM calendar_date)::INT                 AS day_of_week,
    CASE WHEN EXTRACT(DOW FROM calendar_date) IN (0,6) THEN TRUE ELSE FALSE END AS is_weekend
FROM (
    SELECT DISTINCT calendar_date, month_year, quarter_name, year, month_name
    FROM pulsetrack_mart.mart_campaign_performance_daily
    WHERE calendar_date IS NOT NULL
) dates;

-- H2: Commercial Hierarchy — Advertiser → Campaign (with channel context)
CREATE OR REPLACE VIEW pulsetrack_mart.vw_dim_commercial_hierarchy AS
SELECT DISTINCT
    m.advertiser_id,
    m.advertiser_name,
    m.campaign_id,
    m.campaign_name,
    m.partner_channel                   AS channel_type
FROM pulsetrack_mart.mart_campaign_performance_daily m
WHERE m.advertiser_id IS NOT NULL
  AND m.campaign_id IS NOT NULL;

-- H3: Partner Hierarchy — Channel → Partner
CREATE OR REPLACE VIEW pulsetrack_mart.vw_dim_partner_hierarchy AS
SELECT DISTINCT
    p.partner_channel                   AS channel,
    p.partner_id,
    p.partner_name
FROM pulsetrack_mart.mart_partner_attribution_daily p
WHERE p.partner_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 2: OLAP OPERATIONS
-- ─────────────────────────────────────────────────────────────────────────────

-- OP-1: ROLL-UP — Campaign×Day → Campaign×Month → Campaign×Quarter → Campaign×Year
CREATE OR REPLACE VIEW pulsetrack_mart.vw_olap_rollup_campaign_time AS
WITH base AS (
    SELECT
        campaign_id,
        campaign_name,
        advertiser_name,
        calendar_date,
        month_year,
        quarter_name,
        year,
        impression_count,
        click_count,
        conversion_count,
        gross_revenue,
        adjusted_revenue
    FROM pulsetrack_mart.mart_campaign_performance_daily
    WHERE calendar_date IS NOT NULL
),
daily AS (
    SELECT
        'DAY'                                              AS granularity,
        campaign_id,
        campaign_name,
        advertiser_name,
        TO_CHAR(calendar_date, 'YYYY-MM-DD')             AS period_label,
        SUM(impression_count)                             AS impressions,
        SUM(click_count)                                  AS clicks,
        SUM(conversion_count)                             AS conversions,
        ROUND(SUM(gross_revenue)::NUMERIC, 2)            AS gross_revenue,
        ROUND(SUM(adjusted_revenue)::NUMERIC, 2)         AS adjusted_revenue
    FROM base
    GROUP BY 1,2,3,4,5
),
monthly AS (
    SELECT
        'MONTH'                                            AS granularity,
        campaign_id,
        campaign_name,
        advertiser_name,
        month_year                                         AS period_label,
        SUM(impression_count)                             AS impressions,
        SUM(click_count)                                  AS clicks,
        SUM(conversion_count)                             AS conversions,
        ROUND(SUM(gross_revenue)::NUMERIC, 2)            AS gross_revenue,
        ROUND(SUM(adjusted_revenue)::NUMERIC, 2)         AS adjusted_revenue
    FROM base
    GROUP BY 1,2,3,4,5
),
quarterly AS (
    SELECT
        'QUARTER'                                          AS granularity,
        campaign_id,
        campaign_name,
        advertiser_name,
        quarter_name                                       AS period_label,
        SUM(impression_count)                             AS impressions,
        SUM(click_count)                                  AS clicks,
        SUM(conversion_count)                             AS conversions,
        ROUND(SUM(gross_revenue)::NUMERIC, 2)            AS gross_revenue,
        ROUND(SUM(adjusted_revenue)::NUMERIC, 2)         AS adjusted_revenue
    FROM base
    GROUP BY 1,2,3,4,5
),
yearly AS (
    SELECT
        'YEAR'                                             AS granularity,
        campaign_id,
        campaign_name,
        advertiser_name,
        year::TEXT                                         AS period_label,
        SUM(impression_count)                             AS impressions,
        SUM(click_count)                                  AS clicks,
        SUM(conversion_count)                             AS conversions,
        ROUND(SUM(gross_revenue)::NUMERIC, 2)            AS gross_revenue,
        ROUND(SUM(adjusted_revenue)::NUMERIC, 2)         AS adjusted_revenue
    FROM base
    GROUP BY 1,2,3,4,5
)
SELECT * FROM daily
UNION ALL SELECT * FROM monthly
UNION ALL SELECT * FROM quarterly
UNION ALL SELECT * FROM yearly;

-- OP-2: DRILL-DOWN — Advertiser Total → Campaign Detail
CREATE OR REPLACE VIEW pulsetrack_mart.vw_olap_drilldown_advertiser_campaign AS
WITH adv_total AS (
    SELECT
        'ADVERTISER'                                AS drill_level,
        advertiser_id::TEXT                         AS entity_id,
        advertiser_name                             AS entity_name,
        NULL::TEXT                                  AS parent_id,
        NULL::TEXT                                  AS parent_name,
        SUM(impression_count)                       AS impressions,
        SUM(click_count)                            AS clicks,
        SUM(conversion_count)                       AS conversions,
        ROUND(SUM(gross_revenue)::NUMERIC, 2)       AS gross_revenue,
        ROUND(SUM(adjusted_revenue)::NUMERIC, 2)    AS adjusted_revenue,
        ROUND(AVG(ctr_pct)::NUMERIC, 4)             AS ctr_pct,
        ROUND(AVG(cvr_pct)::NUMERIC, 4)             AS cvr_pct
    FROM pulsetrack_mart.mart_campaign_performance_daily
    GROUP BY advertiser_id, advertiser_name
),
camp_detail AS (
    SELECT
        'CAMPAIGN'                                  AS drill_level,
        campaign_id::TEXT                           AS entity_id,
        campaign_name                               AS entity_name,
        advertiser_id::TEXT                         AS parent_id,
        advertiser_name                             AS parent_name,
        SUM(impression_count)                       AS impressions,
        SUM(click_count)                            AS clicks,
        SUM(conversion_count)                       AS conversions,
        ROUND(SUM(gross_revenue)::NUMERIC, 2)       AS gross_revenue,
        ROUND(SUM(adjusted_revenue)::NUMERIC, 2)    AS adjusted_revenue,
        ROUND(AVG(ctr_pct)::NUMERIC, 4)             AS ctr_pct,
        ROUND(AVG(cvr_pct)::NUMERIC, 4)             AS cvr_pct
    FROM pulsetrack_mart.mart_campaign_performance_daily
    GROUP BY campaign_id, campaign_name, advertiser_id, advertiser_name
)
SELECT * FROM adv_total
UNION ALL
SELECT * FROM camp_detail;

-- OP-3: SLICE — Single dimension filter: Year 2025
CREATE OR REPLACE VIEW pulsetrack_mart.vw_olap_slice_year_2025 AS
SELECT
    campaign_id,
    campaign_name,
    advertiser_name,
    partner_channel                     AS channel_type,
    calendar_date,
    impression_count,
    click_count,
    conversion_count,
    ROUND(gross_revenue::NUMERIC, 2)    AS gross_revenue,
    ROUND(adjusted_revenue::NUMERIC, 2) AS adjusted_revenue,
    ROUND(ctr_pct::NUMERIC, 4)          AS ctr_pct,
    ROUND(cvr_pct::NUMERIC, 4)          AS cvr_pct
FROM pulsetrack_mart.mart_campaign_performance_daily
WHERE year = 2025;

-- OP-4: DICE — Multi-dimension filter: Year 2025 AND Channel = 'Social'
CREATE OR REPLACE VIEW pulsetrack_mart.vw_olap_dice_2025_social AS
SELECT
    campaign_id,
    campaign_name,
    advertiser_name,
    partner_channel                     AS channel_type,
    calendar_date,
    impression_count,
    click_count,
    conversion_count,
    ROUND(gross_revenue::NUMERIC, 2)    AS gross_revenue,
    ROUND(adjusted_revenue::NUMERIC, 2) AS adjusted_revenue,
    ROUND(ctr_pct::NUMERIC, 4)          AS ctr_pct,
    ROUND(cvr_pct::NUMERIC, 4)          AS cvr_pct
FROM pulsetrack_mart.mart_campaign_performance_daily
WHERE year = 2025
  AND partner_channel = 'Social';

-- OP-5: PIVOT — Monthly net revenue per channel (crosstab via CASE WHEN)
CREATE OR REPLACE VIEW pulsetrack_mart.vw_olap_pivot_monthly_revenue_by_channel AS
SELECT
    month_year,
    ROUND(SUM(CASE WHEN partner_channel = 'Social'    THEN adjusted_revenue ELSE 0 END)::NUMERIC, 2) AS social_revenue,
    ROUND(SUM(CASE WHEN partner_channel = 'Display'   THEN adjusted_revenue ELSE 0 END)::NUMERIC, 2) AS display_revenue,
    ROUND(SUM(CASE WHEN partner_channel = 'Search'    THEN adjusted_revenue ELSE 0 END)::NUMERIC, 2) AS search_revenue,
    ROUND(SUM(CASE WHEN partner_channel = 'Email'     THEN adjusted_revenue ELSE 0 END)::NUMERIC, 2) AS email_revenue,
    ROUND(SUM(CASE WHEN partner_channel = 'Video'     THEN adjusted_revenue ELSE 0 END)::NUMERIC, 2) AS video_revenue,
    ROUND(SUM(CASE WHEN partner_channel = 'Affiliate' THEN adjusted_revenue ELSE 0 END)::NUMERIC, 2) AS affiliate_revenue,
    ROUND(SUM(CASE WHEN partner_channel NOT IN ('Social','Display','Search','Email','Video','Affiliate')
                   THEN adjusted_revenue ELSE 0 END)::NUMERIC, 2)                                     AS other_revenue,
    ROUND(SUM(adjusted_revenue)::NUMERIC, 2)                                                           AS total_revenue
FROM pulsetrack_mart.mart_campaign_performance_daily
WHERE calendar_date IS NOT NULL
GROUP BY month_year
ORDER BY month_year;

-- OP-6: TOP-N — Top 10 partners by attributed revenue per month
CREATE OR REPLACE VIEW pulsetrack_mart.vw_olap_topn_partner_monthly AS
WITH ranked AS (
    SELECT
        month_year,
        partner_id,
        partner_name,
        partner_channel,
        SUM(attributed_conversions)                      AS attributed_conversions,
        ROUND(SUM(attributed_revenue)::NUMERIC, 2)      AS attributed_revenue,
        DENSE_RANK() OVER (
            PARTITION BY month_year
            ORDER BY SUM(attributed_revenue) DESC
        )                                                AS revenue_rank
    FROM pulsetrack_mart.mart_partner_attribution_daily
    WHERE calendar_date IS NOT NULL
    GROUP BY month_year, partner_id, partner_name, partner_channel
)
SELECT *
FROM ranked
WHERE revenue_rank <= 10;

-- OP-7: MoM GROWTH — Month-over-Month adjusted revenue per advertiser
CREATE OR REPLACE VIEW pulsetrack_mart.vw_olap_mom_revenue_growth AS
WITH monthly_adv AS (
    SELECT
        advertiser_id,
        advertiser_name,
        month_year,
        DATE_TRUNC('month', calendar_date)::DATE         AS month_dt,
        ROUND(SUM(adjusted_revenue)::NUMERIC, 2)        AS adjusted_revenue,
        SUM(conversion_count)                            AS conversions
    FROM pulsetrack_mart.mart_campaign_performance_daily
    WHERE calendar_date IS NOT NULL
    GROUP BY advertiser_id, advertiser_name, month_year, DATE_TRUNC('month', calendar_date)
)
SELECT
    advertiser_id,
    advertiser_name,
    month_year,
    adjusted_revenue,
    conversions,
    LAG(adjusted_revenue, 1) OVER (
        PARTITION BY advertiser_id
        ORDER BY month_dt
    )                                                                            AS prev_month_revenue,
    ROUND(
        (adjusted_revenue - LAG(adjusted_revenue, 1) OVER (
            PARTITION BY advertiser_id ORDER BY month_dt)
        )::NUMERIC, 2
    )                                                                            AS mom_revenue_delta,
    ROUND(
        CASE
            WHEN LAG(adjusted_revenue, 1) OVER (PARTITION BY advertiser_id ORDER BY month_dt) <> 0
            THEN (adjusted_revenue - LAG(adjusted_revenue, 1) OVER (PARTITION BY advertiser_id ORDER BY month_dt))
                 / ABS(LAG(adjusted_revenue, 1) OVER (PARTITION BY advertiser_id ORDER BY month_dt)) * 100
            ELSE NULL
        END::NUMERIC, 2
    )                                                                            AS mom_growth_pct
FROM monthly_adv;

-- OP-8: QoQ GROWTH — Quarter-over-Quarter adjusted revenue per advertiser
CREATE OR REPLACE VIEW pulsetrack_mart.vw_olap_qoq_revenue_growth AS
WITH quarterly_adv AS (
    SELECT
        advertiser_id,
        advertiser_name,
        quarter_name,
        DATE_TRUNC('quarter', calendar_date)::DATE       AS quarter_dt,
        ROUND(SUM(adjusted_revenue)::NUMERIC, 2)        AS adjusted_revenue,
        SUM(conversion_count)                            AS conversions
    FROM pulsetrack_mart.mart_campaign_performance_daily
    WHERE calendar_date IS NOT NULL
    GROUP BY advertiser_id, advertiser_name, quarter_name, DATE_TRUNC('quarter', calendar_date)
)
SELECT
    advertiser_id,
    advertiser_name,
    quarter_name,
    adjusted_revenue,
    conversions,
    LAG(adjusted_revenue, 1) OVER (
        PARTITION BY advertiser_id
        ORDER BY quarter_dt
    )                                                                           AS prev_quarter_revenue,
    ROUND(
        (adjusted_revenue - LAG(adjusted_revenue, 1) OVER (
            PARTITION BY advertiser_id ORDER BY quarter_dt)
        )::NUMERIC, 2
    )                                                                           AS qoq_revenue_delta,
    ROUND(
        CASE
            WHEN LAG(adjusted_revenue, 1) OVER (PARTITION BY advertiser_id ORDER BY quarter_dt) <> 0
            THEN (adjusted_revenue - LAG(adjusted_revenue, 1) OVER (PARTITION BY advertiser_id ORDER BY quarter_dt))
                 / ABS(LAG(adjusted_revenue, 1) OVER (PARTITION BY advertiser_id ORDER BY quarter_dt)) * 100
            ELSE NULL
        END::NUMERIC, 2
    )                                                                           AS qoq_growth_pct
FROM quarterly_adv;

-- OP-9: YoY GROWTH — Year-over-Year adjusted revenue per advertiser
CREATE OR REPLACE VIEW pulsetrack_mart.vw_olap_yoy_revenue_growth AS
WITH yearly_adv AS (
    SELECT
        advertiser_id,
        advertiser_name,
        year,
        ROUND(SUM(adjusted_revenue)::NUMERIC, 2)        AS adjusted_revenue,
        SUM(conversion_count)                            AS conversions
    FROM pulsetrack_mart.mart_campaign_performance_daily
    WHERE calendar_date IS NOT NULL
    GROUP BY advertiser_id, advertiser_name, year
)
SELECT
    advertiser_id,
    advertiser_name,
    year,
    adjusted_revenue,
    conversions,
    LAG(adjusted_revenue, 1) OVER (
        PARTITION BY advertiser_id
        ORDER BY year
    )                                                     AS prev_year_revenue,
    ROUND(
        (adjusted_revenue - LAG(adjusted_revenue, 1) OVER (
            PARTITION BY advertiser_id ORDER BY year)
        )::NUMERIC, 2
    )                                                     AS yoy_revenue_delta,
    ROUND(
        CASE
            WHEN LAG(adjusted_revenue, 1) OVER (PARTITION BY advertiser_id ORDER BY year) <> 0
            THEN (adjusted_revenue - LAG(adjusted_revenue, 1) OVER (PARTITION BY advertiser_id ORDER BY year))
                 / ABS(LAG(adjusted_revenue, 1) OVER (PARTITION BY advertiser_id ORDER BY year)) * 100
            ELSE NULL
        END::NUMERIC, 2
    )                                                     AS yoy_growth_pct
FROM yearly_adv;

-- OP-10: CONTRIBUTION % — Each campaign's share of total quarterly adjusted revenue
CREATE OR REPLACE VIEW pulsetrack_mart.vw_olap_campaign_revenue_contribution AS
WITH quarterly_camp AS (
    SELECT
        quarter_name,
        DATE_TRUNC('quarter', calendar_date)::DATE       AS quarter_dt,
        campaign_id,
        campaign_name,
        advertiser_name,
        partner_channel                                   AS channel_type,
        ROUND(SUM(adjusted_revenue)::NUMERIC, 2)        AS campaign_revenue,
        SUM(conversion_count)                            AS conversions
    FROM pulsetrack_mart.mart_campaign_performance_daily
    WHERE calendar_date IS NOT NULL
    GROUP BY quarter_name, DATE_TRUNC('quarter', calendar_date),
             campaign_id, campaign_name, advertiser_name, partner_channel
)
SELECT
    quarter_name,
    campaign_id,
    campaign_name,
    advertiser_name,
    channel_type,
    campaign_revenue,
    conversions,
    ROUND(SUM(campaign_revenue) OVER (PARTITION BY quarter_name)::NUMERIC, 2)  AS quarter_total_revenue,
    ROUND(
        campaign_revenue::NUMERIC
        / NULLIF(SUM(campaign_revenue) OVER (PARTITION BY quarter_name), 0)
        * 100, 4
    )                                                                            AS revenue_contribution_pct,
    DENSE_RANK() OVER (
        PARTITION BY quarter_name
        ORDER BY campaign_revenue DESC
    )                                                                            AS revenue_rank_in_quarter
FROM quarterly_camp;
