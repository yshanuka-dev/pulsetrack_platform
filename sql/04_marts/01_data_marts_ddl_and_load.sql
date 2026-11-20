-- ============================================================================
-- PulseTrack Data Mart Layer
-- Schema: pulsetrack_mart
-- Specification: Question 7 (10 Marks)
-- High-Performance Aggregated Business Data Marts
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS pulsetrack_mart;
SET search_path TO pulsetrack_mart, pulsetrack_gold;

-- ----------------------------------------------------------------------------
-- 1. MART: CAMPAIGN PERFORMANCE DAILY
-- Grain: One row per Campaign x Partner x Date (campaign_key, partner_key, date_key)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mart_campaign_performance_daily CASCADE;
CREATE TABLE mart_campaign_performance_daily AS
WITH daily_impressions AS (
    SELECT 
        fi.campaign_key,
        fi.partner_key,
        fi.impression_date_key AS date_key,
        SUM(fi.impression_count) AS impression_count
    FROM pulsetrack_gold.fact_impression fi
    GROUP BY fi.campaign_key, fi.partner_key, fi.impression_date_key
),
daily_clicks AS (
    SELECT 
        fc.campaign_key,
        fc.partner_key,
        fc.click_date_key AS date_key,
        SUM(fc.click_count) AS click_count,
        SUM(fc.is_unique) AS unique_click_count
    FROM pulsetrack_gold.fact_click fc
    GROUP BY fc.campaign_key, fc.partner_key, fc.click_date_key
),
daily_conversions AS (
    SELECT 
        fc.campaign_key,
        fc.partner_key,
        fc.conversion_date_key AS date_key,
        SUM(fc.conversion_count) AS conversion_count,
        SUM(fc.gross_revenue) AS gross_revenue,
        SUM(fc.payout_amount) AS payout_amount,
        SUM(fc.net_margin) AS net_margin
    FROM pulsetrack_gold.fact_conversion fc
    GROUP BY fc.campaign_key, fc.partner_key, fc.conversion_date_key
),
daily_adjustments AS (
    SELECT 
        fc.campaign_key,
        fc.partner_key,
        fa.adjustment_date_key AS date_key,
        SUM(fa.delta_amount) AS adjustment_delta
    FROM pulsetrack_gold.fact_revenue_adjustment fa
    JOIN pulsetrack_gold.fact_conversion fc ON fa.conversion_key = fc.conversion_key
    GROUP BY fc.campaign_key, fc.partner_key, fa.adjustment_date_key
),
all_keys AS (
    SELECT campaign_key, partner_key, date_key FROM daily_impressions
    UNION
    SELECT campaign_key, partner_key, date_key FROM daily_clicks
    UNION
    SELECT campaign_key, partner_key, date_key FROM daily_conversions
    UNION
    SELECT campaign_key, partner_key, date_key FROM daily_adjustments
)
SELECT 
    -- Dimensional Attributes
    ak.date_key,
    d.calendar_date,
    d.year,
    d.quarter_name,
    d.month_year,
    d.month_name,
    c.campaign_key,
    c.campaign_id,
    c.campaign_name,
    c.price_type,
    a.advertiser_id,
    a.advertiser_name,
    p.partner_key,
    p.partner_id,
    p.partner_name,
    p.channel AS partner_channel,

    -- Atomic Aggregated Measures
    COALESCE(i.impression_count, 0) AS impression_count,
    COALESCE(k.click_count, 0) AS click_count,
    COALESCE(k.unique_click_count, 0) AS unique_click_count,
    COALESCE(v.conversion_count, 0) AS conversion_count,
    COALESCE(v.gross_revenue, 0.0000) AS gross_revenue,
    COALESCE(v.payout_amount, 0.0000) AS payout_amount,
    COALESCE(v.net_margin, 0.0000) AS net_margin,
    COALESCE(adj.adjustment_delta, 0.0000) AS adjustment_delta,
    (COALESCE(v.gross_revenue, 0.0000) + COALESCE(adj.adjustment_delta, 0.0000)) AS adjusted_revenue,

    -- Pre-Calculated KPI Ratios
    CASE 
        WHEN COALESCE(i.impression_count, 0) > 0 
        THEN ROUND((COALESCE(k.click_count, 0)::NUMERIC / i.impression_count) * 100.0, 4)
        ELSE 0.0000 
    END AS ctr_pct,

    CASE 
        WHEN COALESCE(k.click_count, 0) > 0 
        THEN ROUND((COALESCE(v.conversion_count, 0)::NUMERIC / k.click_count) * 100.0, 4)
        ELSE 0.0000 
    END AS cvr_pct,

    CASE 
        WHEN COALESCE(k.click_count, 0) > 0 
        THEN ROUND(COALESCE(v.gross_revenue, 0.0000) / k.click_count, 4)
        ELSE 0.0000 
    END AS revenue_per_click,

    CASE 
        WHEN COALESCE(v.conversion_count, 0) > 0 
        THEN ROUND(COALESCE(v.gross_revenue, 0.0000) / v.conversion_count, 4)
        ELSE 0.0000 
    END AS revenue_per_conversion

FROM all_keys ak
JOIN pulsetrack_gold.dim_date d ON ak.date_key = d.date_key
JOIN pulsetrack_gold.dim_campaign c ON ak.campaign_key = c.campaign_key
LEFT JOIN pulsetrack_gold.dim_partner p ON ak.partner_key = p.partner_key
LEFT JOIN pulsetrack_gold.dim_advertiser a ON c.advertiser_id = a.advertiser_id AND a.is_current = TRUE
LEFT JOIN daily_impressions i ON ak.campaign_key = i.campaign_key AND ak.partner_key = i.partner_key AND ak.date_key = i.date_key
LEFT JOIN daily_clicks k ON ak.campaign_key = k.campaign_key AND ak.partner_key = k.partner_key AND ak.date_key = k.date_key
LEFT JOIN daily_conversions v ON ak.campaign_key = v.campaign_key AND ak.partner_key = v.partner_key AND ak.date_key = v.date_key
LEFT JOIN daily_adjustments adj ON ak.campaign_key = adj.campaign_key AND ak.partner_key = adj.partner_key AND ak.date_key = adj.date_key;

CREATE INDEX IF NOT EXISTS idx_mart_camp_date ON mart_campaign_performance_daily (date_key);
CREATE INDEX IF NOT EXISTS idx_mart_camp_id ON mart_campaign_performance_daily (campaign_id);
CREATE INDEX IF NOT EXISTS idx_mart_camp_adv ON mart_campaign_performance_daily (advertiser_id);
CREATE INDEX IF NOT EXISTS idx_mart_camp_partner ON mart_campaign_performance_daily (partner_id);

-- ----------------------------------------------------------------------------
-- 2. MART: PARTNER ATTRIBUTION DAILY
-- Grain: One row per Partner x Campaign x Date (Multi-Touch Fractional Credit)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mart_partner_attribution_daily CASCADE;
CREATE TABLE mart_partner_attribution_daily AS
SELECT 
    d.date_key,
    d.calendar_date,
    d.year,
    d.quarter_name,
    d.month_year,
    dp.partner_key,
    dp.partner_id,
    dp.partner_name,
    dp.channel AS partner_channel,
    dc.campaign_key,
    dc.campaign_id,
    dc.campaign_name,
    
    -- Fractional & Position Measures
    COUNT(b.touchpoint_key) AS total_touchpoints,
    ROUND(SUM(b.attribution_weight), 4) AS attributed_conversions,
    ROUND(SUM(fc.gross_revenue * b.attribution_weight), 4) AS attributed_revenue,
    SUM(CASE WHEN b.touch_position = 'first' THEN 1 ELSE 0 END) AS first_touch_count,
    SUM(CASE WHEN b.touch_position = 'mid' THEN 1 ELSE 0 END) AS mid_touch_count,
    SUM(CASE WHEN b.touch_position = 'last' THEN 1 ELSE 0 END) AS last_touch_count

FROM pulsetrack_gold.bridge_conversion_touchpoint b
JOIN pulsetrack_gold.fact_conversion fc ON b.conversion_key = fc.conversion_key
JOIN pulsetrack_gold.dim_date d ON fc.conversion_date_key = d.date_key
JOIN pulsetrack_gold.dim_partner dp ON b.partner_key = dp.partner_key
JOIN pulsetrack_gold.dim_campaign dc ON fc.campaign_key = dc.campaign_key
GROUP BY 
    d.date_key, d.calendar_date, d.year, d.quarter_name, d.month_year,
    dp.partner_key, dp.partner_id, dp.partner_name, dp.channel,
    dc.campaign_key, dc.campaign_id, dc.campaign_name;

CREATE INDEX IF NOT EXISTS idx_mart_part_date ON mart_partner_attribution_daily (date_key);
CREATE INDEX IF NOT EXISTS idx_mart_part_id ON mart_partner_attribution_daily (partner_id);

-- ----------------------------------------------------------------------------
-- 3. MART: ADVERTISER ACCOUNT MANAGER MONTHLY (SCD-2 Historical Analytics)
-- Grain: One row per Advertiser x Account Manager x Month
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mart_advertiser_am_monthly CASCADE;
CREATE TABLE mart_advertiser_am_monthly AS
SELECT 
    d.year,
    d.quarter_name,
    d.month_year,
    d.month_name,
    da.advertiser_id,
    da.advertiser_name,
    da.vertical,
    da.am_id,
    da.am_name,
    da.am_team,
    da.am_region,
    da.is_current AS is_current_am_assignment,
    
    -- Monthly Measures
    COUNT(fc.conversion_key) AS monthly_conversions,
    ROUND(SUM(fc.gross_revenue), 4) AS monthly_gross_revenue,
    ROUND(SUM(fc.payout_amount), 4) AS monthly_payout_amount,
    ROUND(SUM(fc.net_margin), 4) AS monthly_margin,
    ROUND(COALESCE(SUM(fa.delta_amount), 0.0000), 4) AS monthly_adjustment_delta,
    ROUND(SUM(fc.gross_revenue) + COALESCE(SUM(fa.delta_amount), 0.0000), 4) AS monthly_adjusted_revenue

FROM pulsetrack_gold.fact_conversion fc
JOIN pulsetrack_gold.dim_date d ON fc.conversion_date_key = d.date_key
JOIN pulsetrack_gold.dim_advertiser da ON fc.advertiser_sk = da.advertiser_sk
LEFT JOIN pulsetrack_gold.fact_revenue_adjustment fa ON fc.conversion_key = fa.conversion_key
GROUP BY 
    d.year, d.quarter_name, d.month_year, d.month_name,
    da.advertiser_id, da.advertiser_name, da.vertical,
    da.am_id, da.am_name, da.am_team, da.am_region, da.is_current;

CREATE INDEX IF NOT EXISTS idx_mart_am_adv ON mart_advertiser_am_monthly (advertiser_id);
CREATE INDEX IF NOT EXISTS idx_mart_am_id ON mart_advertiser_am_monthly (am_id);
CREATE INDEX IF NOT EXISTS idx_mart_am_month ON mart_advertiser_am_monthly (month_year);
