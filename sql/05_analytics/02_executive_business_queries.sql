-- =============================================================================
-- Q9: Business Analytics & Executive Queries
-- PulseTrack Data Warehouse | pulsetrack_dw
-- =============================================================================
-- ALL queries source exclusively from pulsetrack_mart or pulsetrack_mart OLAP views.
-- Lineage: BI Tool → OLAP Views / pulsetrack_mart → pulsetrack_gold → pulsetrack_silver → pulsetrack_raw → Source
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- EQ-1: Which advertisers generated the highest revenue each quarter?
--       (Quarterly Top-N)
-- Source: pulsetrack_mart.vw_olap_campaign_revenue_contribution (OP-10)
-- ─────────────────────────────────────────────────────────────────────────────
WITH quarterly_adv AS (
    SELECT
        quarter_name,
        advertiser_name,
        SUM(campaign_revenue)                               AS total_revenue,
        SUM(conversions)                                    AS total_conversions,
        ROUND(SUM(revenue_contribution_pct)::NUMERIC, 4)   AS portfolio_share_pct,
        DENSE_RANK() OVER (
            PARTITION BY quarter_name
            ORDER BY SUM(campaign_revenue) DESC
        )                                                   AS revenue_rank
    FROM pulsetrack_mart.vw_olap_campaign_revenue_contribution
    GROUP BY quarter_name, advertiser_name
)
SELECT
    quarter_name,
    revenue_rank,
    advertiser_name,
    ROUND(total_revenue::NUMERIC, 2)        AS total_revenue,
    total_conversions,
    ROUND(portfolio_share_pct::NUMERIC, 2)  AS portfolio_pct
FROM quarterly_adv
WHERE revenue_rank <= 5
ORDER BY quarter_name, revenue_rank;


-- ─────────────────────────────────────────────────────────────────────────────
-- EQ-2: Which campaigns have highest CTR but lowest CVR? (Funnel drop-off)
-- Source: pulsetrack_mart.mart_campaign_performance_daily
-- ─────────────────────────────────────────────────────────────────────────────
WITH campaign_funnel AS (
    SELECT
        campaign_id,
        campaign_name,
        advertiser_name,
        SUM(impression_count)                   AS total_impressions,
        SUM(click_count)                        AS total_clicks,
        SUM(conversion_count)                   AS total_conversions,
        ROUND(
            CASE WHEN SUM(impression_count) > 0
                 THEN SUM(click_count)::NUMERIC / SUM(impression_count) * 100
                 ELSE 0 END, 4)                 AS ctr_pct,
        ROUND(
            CASE WHEN SUM(click_count) > 0
                 THEN SUM(conversion_count)::NUMERIC / SUM(click_count) * 100
                 ELSE 0 END, 4)                 AS cvr_pct
    FROM pulsetrack_mart.mart_campaign_performance_daily
    GROUP BY campaign_id, campaign_name, advertiser_name
),
ranked AS (
    SELECT *,
        PERCENT_RANK() OVER (ORDER BY ctr_pct DESC) AS ctr_prank,
        PERCENT_RANK() OVER (ORDER BY cvr_pct ASC)  AS cvr_low_prank
    FROM campaign_funnel
    WHERE total_impressions > 500
)
SELECT
    campaign_name,
    advertiser_name,
    total_impressions,
    total_clicks,
    total_conversions,
    ctr_pct,
    cvr_pct,
    ROUND((ctr_pct - cvr_pct)::NUMERIC, 4)  AS funnel_gap
FROM ranked
WHERE ctr_prank <= 0.20   -- top 20% CTR
  AND cvr_low_prank <= 0.20  -- bottom 20% CVR
ORDER BY funnel_gap DESC
LIMIT 15;


-- ─────────────────────────────────────────────────────────────────────────────
-- EQ-3: Which partners generated the highest attributed revenue? (Affiliate ROI)
-- Source: pulsetrack_mart.vw_olap_topn_partner_monthly (OP-6)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    partner_id,
    partner_name,
    partner_channel,
    SUM(attributed_conversions)                        AS total_attributed_conversions,
    ROUND(SUM(attributed_revenue)::NUMERIC, 2)         AS total_attributed_revenue,
    ROUND(
        SUM(attributed_revenue)::NUMERIC
        / NULLIF(SUM(attributed_conversions), 0), 2)   AS revenue_per_conversion,
    COUNT(DISTINCT month_year)                         AS active_months,
    DENSE_RANK() OVER (
        ORDER BY SUM(attributed_revenue) DESC
    )                                                  AS overall_rank
FROM pulsetrack_mart.vw_olap_topn_partner_monthly
GROUP BY partner_id, partner_name, partner_channel
ORDER BY total_attributed_revenue DESC
LIMIT 20;


-- ─────────────────────────────────────────────────────────────────────────────
-- EQ-4: What is the MoM revenue change? (Window function LAG)
-- Source: pulsetrack_mart.vw_olap_mom_revenue_growth (OP-7)
-- ─────────────────────────────────────────────────────────────────────────────
-- Portfolio-level MoM (all advertisers combined)
WITH portfolio_monthly AS (
    SELECT
        month_year,
        ROUND(SUM(adjusted_revenue)::NUMERIC, 2)      AS portfolio_revenue,
        SUM(conversions)                               AS portfolio_conversions
    FROM pulsetrack_mart.vw_olap_mom_revenue_growth
    GROUP BY month_year
)
SELECT
    month_year,
    portfolio_revenue,
    portfolio_conversions,
    LAG(portfolio_revenue) OVER (ORDER BY month_year)  AS prev_month_revenue,
    ROUND(
        (portfolio_revenue - LAG(portfolio_revenue) OVER (ORDER BY month_year))::NUMERIC
    , 2)                                               AS mom_delta,
    ROUND(
        CASE WHEN LAG(portfolio_revenue) OVER (ORDER BY month_year) <> 0
             THEN (portfolio_revenue - LAG(portfolio_revenue) OVER (ORDER BY month_year))
                  / ABS(LAG(portfolio_revenue) OVER (ORDER BY month_year)) * 100
             ELSE NULL END::NUMERIC
    , 2)                                               AS mom_growth_pct
FROM portfolio_monthly
ORDER BY month_year;


-- ─────────────────────────────────────────────────────────────────────────────
-- EQ-5: Which campaigns contributed > 10% of their advertiser's total revenue?
-- Source: pulsetrack_mart.mart_campaign_performance_daily
-- ─────────────────────────────────────────────────────────────────────────────
WITH advertiser_total AS (
    SELECT
        advertiser_id,
        advertiser_name,
        SUM(adjusted_revenue) AS adv_total_revenue
    FROM pulsetrack_mart.mart_campaign_performance_daily
    GROUP BY advertiser_id, advertiser_name
),
campaign_total AS (
    SELECT
        campaign_id,
        campaign_name,
        advertiser_id,
        advertiser_name,
        SUM(impression_count)             AS impressions,
        SUM(click_count)                  AS clicks,
        SUM(conversion_count)             AS conversions,
        SUM(adjusted_revenue)             AS campaign_revenue
    FROM pulsetrack_mart.mart_campaign_performance_daily
    GROUP BY campaign_id, campaign_name, advertiser_id, advertiser_name
)
SELECT
    c.advertiser_name,
    c.campaign_name,
    ROUND(c.campaign_revenue::NUMERIC, 2)        AS campaign_revenue,
    ROUND(a.adv_total_revenue::NUMERIC, 2)       AS advertiser_total_revenue,
    ROUND(
        c.campaign_revenue / NULLIF(a.adv_total_revenue, 0) * 100
    ::NUMERIC, 2)                                AS pct_of_advertiser_revenue,
    c.impressions,
    c.clicks,
    c.conversions
FROM campaign_total c
JOIN advertiser_total a USING (advertiser_id)
WHERE c.campaign_revenue / NULLIF(a.adv_total_revenue, 0) > 0.10
ORDER BY pct_of_advertiser_revenue DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- EQ-6: Which creatives/campaigns underperformed vs their campaign average?
--       (Anomaly detection: partner-day rows below campaign CVR average)
-- Source: pulsetrack_mart.mart_campaign_performance_daily
-- ─────────────────────────────────────────────────────────────────────────────
WITH campaign_avg AS (
    SELECT
        campaign_id,
        campaign_name,
        advertiser_name,
        AVG(cvr_pct)                            AS avg_cvr,
        STDDEV(cvr_pct)                         AS stddev_cvr,
        AVG(ctr_pct)                            AS avg_ctr,
        SUM(impression_count)                   AS total_impressions,
        COUNT(*)                                AS day_count
    FROM pulsetrack_mart.mart_campaign_performance_daily
    WHERE impression_count > 0
    GROUP BY campaign_id, campaign_name, advertiser_name
    HAVING COUNT(*) >= 10   -- at least 10 active days
),
underperformers AS (
    SELECT
        m.campaign_id,
        m.campaign_name,
        m.advertiser_name,
        ROUND(ca.avg_cvr::NUMERIC, 4)           AS campaign_avg_cvr,
        ROUND(ca.avg_ctr::NUMERIC, 4)           AS campaign_avg_ctr,
        ROUND(
            SUM(m.conversion_count)::NUMERIC
            / NULLIF(SUM(m.click_count), 0) * 100
        , 4)                                    AS actual_cvr,
        ROUND(
            SUM(m.click_count)::NUMERIC
            / NULLIF(SUM(m.impression_count), 0) * 100
        , 4)                                    AS actual_ctr,
        SUM(m.impression_count)                 AS impressions,
        SUM(m.adjusted_revenue)                 AS revenue,
        ROUND((ca.avg_cvr - SUM(m.conversion_count)::NUMERIC
              / NULLIF(SUM(m.click_count), 0) * 100)::NUMERIC, 4) AS cvr_deficit
    FROM pulsetrack_mart.mart_campaign_performance_daily m
    JOIN campaign_avg ca USING (campaign_id)
    WHERE m.impression_count > 100
    GROUP BY m.campaign_id, m.campaign_name, m.advertiser_name,
             ca.avg_cvr, ca.avg_ctr, ca.stddev_cvr
    HAVING SUM(m.conversion_count)::NUMERIC / NULLIF(SUM(m.click_count), 0) * 100
           < ca.avg_cvr - ca.stddev_cvr   -- more than 1 stddev below mean
)
SELECT *
FROM underperformers
ORDER BY cvr_deficit DESC
LIMIT 15;


-- ─────────────────────────────────────────────────────────────────────────────
-- EQ-7: How did advertiser performance change before/after AM reassignment?
--       (SCD-2 comparison using mart_advertiser_am_monthly)
-- Source: pulsetrack_mart.mart_advertiser_am_monthly
-- ─────────────────────────────────────────────────────────────────────────────
WITH am_periods AS (
    SELECT
        advertiser_id,
        advertiser_name,
        am_name,
        am_team,
        is_current_am_assignment,
        SUM(monthly_conversions)         AS total_conversions,
        ROUND(SUM(monthly_gross_revenue)::NUMERIC, 2)   AS total_gross_revenue,
        ROUND(SUM(monthly_adjusted_revenue)::NUMERIC, 2) AS total_adjusted_revenue,
        ROUND(AVG(monthly_margin)::NUMERIC, 2)           AS avg_monthly_margin,
        COUNT(DISTINCT month_year)       AS months_active,
        MIN(month_year)                  AS period_start,
        MAX(month_year)                  AS period_end
    FROM pulsetrack_mart.mart_advertiser_am_monthly
    GROUP BY advertiser_id, advertiser_name, am_name, am_team, is_current_am_assignment
),
-- Advertisers with more than one AM (i.e., had a reassignment)
reassigned AS (
    SELECT advertiser_id
    FROM am_periods
    GROUP BY advertiser_id
    HAVING COUNT(DISTINCT am_name) > 1
),
comparison AS (
    SELECT
        a.advertiser_name,
        a.am_name,
        a.is_current_am_assignment,
        a.period_start,
        a.period_end,
        a.months_active,
        a.total_conversions,
        a.total_gross_revenue,
        a.total_adjusted_revenue,
        a.avg_monthly_margin,
        ROUND(a.total_gross_revenue::NUMERIC / NULLIF(a.months_active, 0), 2) AS avg_monthly_revenue
    FROM am_periods a
    JOIN reassigned r USING (advertiser_id)
)
SELECT *
FROM comparison
ORDER BY advertiser_name, is_current_am_assignment;


-- ─────────────────────────────────────────────────────────────────────────────
-- EQ-8: Attribution % per partner — weighted multi-touch breakdown
-- Source: pulsetrack_mart.mart_partner_attribution_daily
-- ─────────────────────────────────────────────────────────────────────────────
WITH partner_totals AS (
    SELECT
        partner_id,
        partner_name,
        partner_channel,
        SUM(total_touchpoints)                              AS total_touchpoints,
        ROUND(SUM(attributed_conversions)::NUMERIC, 2)     AS attributed_conversions,
        ROUND(SUM(attributed_revenue)::NUMERIC, 2)         AS attributed_revenue,
        SUM(first_touch_count)                             AS first_touch_count,
        SUM(mid_touch_count)                               AS mid_touch_count,
        SUM(last_touch_count)                              AS last_touch_count
    FROM pulsetrack_mart.mart_partner_attribution_daily
    GROUP BY partner_id, partner_name, partner_channel
),
grand_totals AS (
    SELECT
        SUM(attributed_revenue) AS total_attributed_revenue,
        SUM(attributed_conversions) AS total_attributed_conversions
    FROM partner_totals
)
SELECT
    p.partner_name,
    p.partner_channel,
    p.total_touchpoints,
    p.attributed_conversions,
    p.attributed_revenue,
    ROUND(
        p.attributed_revenue / NULLIF(g.total_attributed_revenue, 0) * 100
    ::NUMERIC, 4)                                          AS pct_of_total_attribution,
    ROUND(
        p.first_touch_count::NUMERIC / NULLIF(p.total_touchpoints, 0) * 100
    , 2)                                                   AS first_touch_pct,
    ROUND(
        p.mid_touch_count::NUMERIC / NULLIF(p.total_touchpoints, 0) * 100
    , 2)                                                   AS mid_touch_pct,
    ROUND(
        p.last_touch_count::NUMERIC / NULLIF(p.total_touchpoints, 0) * 100
    , 2)                                                   AS last_touch_pct,
    DENSE_RANK() OVER (ORDER BY p.attributed_revenue DESC) AS attribution_rank
FROM partner_totals p
CROSS JOIN grand_totals g
ORDER BY p.attributed_revenue DESC
LIMIT 20;


-- ─────────────────────────────────────────────────────────────────────────────
-- EQ-9: Campaigns with increasing impressions but declining conversions
--       (Trend divergence — creative fatigue signal)
-- Source: pulsetrack_mart.vw_olap_rollup_campaign_time (OP-1, MONTH grain)
-- ─────────────────────────────────────────────────────────────────────────────
WITH monthly_trends AS (
    SELECT
        campaign_id,
        campaign_name,
        advertiser_name,
        period_label          AS month_year,
        impressions,
        conversions,
        gross_revenue,
        -- Linear regression slope via correlation
        REGR_SLOPE(impressions, ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY period_label))
            OVER (PARTITION BY campaign_id)  AS impression_slope,
        REGR_SLOPE(conversions, ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY period_label))
            OVER (PARTITION BY campaign_id)  AS conversion_slope,
        COUNT(*) OVER (PARTITION BY campaign_id) AS month_count
    FROM pulsetrack_mart.vw_olap_rollup_campaign_time
    WHERE granularity = 'MONTH'
),
diverging AS (
    SELECT DISTINCT
        campaign_id,
        campaign_name,
        advertiser_name,
        ROUND(impression_slope::NUMERIC, 2)  AS impression_trend,
        ROUND(conversion_slope::NUMERIC, 4)  AS conversion_trend,
        month_count,
        SUM(impressions) OVER (PARTITION BY campaign_id)  AS total_impressions,
        SUM(conversions) OVER (PARTITION BY campaign_id)  AS total_conversions
    FROM monthly_trends
    WHERE month_count >= 3   -- at least 3 months of data
)
SELECT
    campaign_name,
    advertiser_name,
    impression_trend,
    conversion_trend,
    month_count,
    total_impressions,
    total_conversions,
    ROUND(total_conversions::NUMERIC / NULLIF(total_impressions, 0) * 100, 4) AS overall_cvr
FROM diverging
WHERE impression_trend > 0   -- impressions growing
  AND conversion_trend < 0   -- conversions declining
ORDER BY ABS(conversion_trend) DESC
LIMIT 15;


-- ─────────────────────────────────────────────────────────────────────────────
-- EQ-10: Financial impact of late adjustments
--        (Gross vs Net revenue reconciliation)
-- Source: pulsetrack_mart.mart_campaign_performance_daily
-- ─────────────────────────────────────────────────────────────────────────────
-- Monthly reconciliation: gross_revenue vs adjusted_revenue (post-adjustment)
WITH monthly_recon AS (
    SELECT
        month_year,
        ROUND(SUM(gross_revenue)::NUMERIC, 2)        AS gross_revenue,
        ROUND(SUM(payout_amount)::NUMERIC, 2)        AS total_payout,
        ROUND(SUM(net_margin)::NUMERIC, 2)           AS net_margin,
        ROUND(SUM(adjustment_delta)::NUMERIC, 2)     AS total_adjustment_delta,
        ROUND(SUM(adjusted_revenue)::NUMERIC, 2)     AS adjusted_revenue,
        SUM(conversion_count)                        AS conversions
    FROM pulsetrack_mart.mart_campaign_performance_daily
    WHERE calendar_date IS NOT NULL
    GROUP BY month_year
)
SELECT
    month_year,
    gross_revenue,
    total_payout,
    net_margin,
    total_adjustment_delta,
    adjusted_revenue,
    conversions,
    -- Adjustment as % of gross revenue
    ROUND(
        total_adjustment_delta / NULLIF(gross_revenue, 0) * 100
    ::NUMERIC, 4)                                   AS adjustment_pct_of_gross,
    -- Cumulative adjustment impact
    ROUND(SUM(total_adjustment_delta) OVER (ORDER BY month_year)::NUMERIC, 2) AS cumulative_adj_impact
FROM monthly_recon
ORDER BY month_year;
