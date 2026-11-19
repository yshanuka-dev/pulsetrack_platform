-- ============================================================================
-- PulseTrack Gold Layer: Dimensional Star Schema Population
-- Schema: pulsetrack_gold
-- Populates Conformed Dims, SCD-2 History, Facts, and Attribution Bridge
-- ============================================================================

SET search_path TO pulsetrack_gold, pulsetrack_silver;

-- ----------------------------------------------------------------------------
-- 1. POPULATE CONFORMED DIMENSIONS
-- ----------------------------------------------------------------------------

-- A. Date Dimension (2024-01-01 to 2027-12-31 + Unknown Record 19000101)
TRUNCATE TABLE dim_date CASCADE;

-- Insert Unknown/Default Row
INSERT INTO dim_date (
    date_key, calendar_date, year, quarter, quarter_name, 
    month, month_name, month_year, day_of_month, day_of_week, day_name, is_weekend
) VALUES (
    19000101, '1900-01-01'::DATE, 1900, 'Q0', 'Unknown', 0, 'Unknown', 'Unknown', 0, 0, 'Unknown', FALSE
);

INSERT INTO dim_date (
    date_key, calendar_date, year, quarter, quarter_name, 
    month, month_name, month_year, day_of_month, day_of_week, day_name, is_weekend
)
SELECT 
    to_char(d, 'YYYYMMDD')::INT AS date_key,
    d::DATE AS calendar_date,
    EXTRACT(YEAR FROM d)::INT AS year,
    'Q' || EXTRACT(QUARTER FROM d)::TEXT AS quarter,
    EXTRACT(YEAR FROM d)::TEXT || '-Q' || EXTRACT(QUARTER FROM d)::TEXT AS quarter_name,
    EXTRACT(MONTH FROM d)::INT AS month,
    to_char(d, 'FMMonth') AS month_name,
    to_char(d, 'YYYY-MM') AS month_year,
    EXTRACT(DAY FROM d)::INT AS day_of_month,
    EXTRACT(ISODOW FROM d)::INT AS day_of_week,
    to_char(d, 'FMDay') AS day_name,
    CASE WHEN EXTRACT(ISODOW FROM d) IN (6, 7) THEN TRUE ELSE FALSE END AS is_weekend
FROM generate_series('2024-01-01'::DATE, '2027-12-31'::DATE, '1 day'::INTERVAL) d;

-- B. Advertiser Dimension (SCD Type 2)
-- Built from MongoDB account_manager_history ground truth + relational metadata
-- First interval starts at '1900-01-01' to cover initial launch period
TRUNCATE TABLE dim_advertiser CASCADE;

WITH ranked_history AS (
    SELECT 
        h.advertiser_id,
        COALESCE(a.advertiser_name, h.advertiser_name) AS advertiser_name,
        COALESCE(a.vertical, 'General') AS vertical,
        COALESCE(a.billing_country, 'US') AS billing_country,
        h.am_id,
        COALESCE(m.am_name, h.am_name) AS am_name,
        COALESCE(m.team, 'UNASSIGNED') AS am_team,
        COALESCE(m.region, 'GLOBAL') AS am_region,
        h.valid_from,
        h.valid_to,
        h.is_current,
        ROW_NUMBER() OVER (PARTITION BY h.advertiser_id ORDER BY h.valid_from ASC) AS rn
    FROM pulsetrack_silver.stg_advertiser_am_history h
    LEFT JOIN pulsetrack_silver.stg_advertisers a ON h.advertiser_id = a.advertiser_id
    LEFT JOIN pulsetrack_silver.stg_account_managers m ON h.am_id = m.am_id
)
INSERT INTO dim_advertiser (
    advertiser_id, advertiser_name, vertical, billing_country,
    am_id, am_name, am_team, am_region, valid_from, valid_to, is_current
)
SELECT 
    advertiser_id,
    advertiser_name,
    vertical,
    billing_country,
    am_id,
    am_name,
    am_team,
    am_region,
    CASE WHEN rn = 1 THEN '1900-01-01 00:00:00+00'::TIMESTAMPTZ ELSE valid_from END AS valid_from,
    valid_to,
    is_current
FROM ranked_history
ORDER BY advertiser_id, valid_from;

-- C. Partner Dimension (Conformed 640 partners)
TRUNCATE TABLE dim_partner CASCADE;
INSERT INTO dim_partner (
    partner_id, partner_name, channel, media_buyer, payment_terms, source_system
)
SELECT 
    partner_id,
    partner_name,
    channel,
    media_buyer,
    payment_terms,
    source_system
FROM pulsetrack_silver.stg_partners
ORDER BY partner_id;

-- D. Campaign Dimension
TRUNCATE TABLE dim_campaign CASCADE;
INSERT INTO dim_campaign (
    campaign_id, campaign_name, price_type, start_date, end_date, advertiser_id, offer_id
)
SELECT 
    sc.campaign_id,
    sc.campaign_name,
    sc.price_type,
    sc.start_date,
    sc.end_date,
    -- Heal corrupted advertiser_id from offer
    CASE 
        WHEN EXISTS (SELECT 1 FROM pulsetrack_silver.stg_advertisers sa WHERE sa.advertiser_id = sc.advertiser_id) 
        THEN sc.advertiser_id 
        ELSE so.advertiser_id 
    END AS advertiser_id,
    sc.offer_id
FROM pulsetrack_silver.stg_campaigns sc
LEFT JOIN pulsetrack_silver.stg_offers so ON sc.offer_id = so.offer_id;

-- E. Offer Dimension
TRUNCATE TABLE dim_offer CASCADE;
INSERT INTO dim_offer (
    offer_id, advertiser_id, offer_name, payout_type, default_payout
)
SELECT 
    offer_id,
    advertiser_id,
    offer_name,
    payout_type,
    default_payout
FROM pulsetrack_silver.stg_offers;

-- F. Creative Dimension
TRUNCATE TABLE dim_creative CASCADE;
INSERT INTO dim_creative (
    creative_id, campaign_id, creative_name, format, dimensions, landing_url
)
SELECT 
    creative_id,
    campaign_id,
    creative_name,
    format,
    dimensions,
    landing_url
FROM pulsetrack_silver.stg_creatives;

-- G. Device & Geo Junk Dimension
TRUNCATE TABLE dim_device_geo CASCADE;
INSERT INTO dim_device_geo (device_type, country_code)
SELECT DISTINCT device_type, country_code FROM pulsetrack_silver.stg_impressions
UNION
SELECT DISTINCT device_type, country_code FROM pulsetrack_silver.stg_clicks
UNION
SELECT DISTINCT device_type, country_code FROM pulsetrack_silver.stg_conversions;

-- H. Conversion Junk Dimension
TRUNCATE TABLE dim_junk_conversion CASCADE;
INSERT INTO dim_junk_conversion (status, currency)
SELECT DISTINCT status, 'USD' FROM pulsetrack_silver.stg_conversions;

-- ----------------------------------------------------------------------------
-- 2. POPULATE FACT & BRIDGE TABLES
-- ----------------------------------------------------------------------------

-- A. Fact Conversions (with SCD-2 Point-in-Time Join & Healed Relationships)
TRUNCATE TABLE fact_conversion CASCADE;
INSERT INTO fact_conversion (
    conversion_id, conversion_time, conversion_date_key,
    advertiser_sk, campaign_key, offer_key, partner_key,
    device_geo_key, junk_conversion_key,
    gross_revenue, payout_amount, net_margin, conversion_count
)
SELECT 
    c.conversion_id,
    COALESCE(c.conversion_time, c.updated_at) AS conversion_time,
    COALESCE(to_char(COALESCE(c.conversion_time, c.updated_at), 'YYYYMMDD')::INT, 19000101) AS conversion_date_key,
    da.advertiser_sk,
    dc.campaign_key,
    dof.offer_key,
    dp.partner_key,
    dg.device_geo_key,
    dj.junk_conversion_key,
    c.gross_revenue,
    c.payout_amount,
    c.net_margin,
    1 AS conversion_count
FROM pulsetrack_silver.stg_conversions c
JOIN pulsetrack_silver.stg_campaigns sc ON c.campaign_id = sc.campaign_id
LEFT JOIN pulsetrack_silver.stg_offers so ON sc.offer_id = so.offer_id
-- SCD Type 2 Point-in-Time Match on healed advertiser_id
JOIN pulsetrack_gold.dim_advertiser da 
  ON (CASE 
        WHEN EXISTS (SELECT 1 FROM pulsetrack_silver.stg_advertisers sa WHERE sa.advertiser_id = sc.advertiser_id) 
        THEN sc.advertiser_id 
        ELSE so.advertiser_id 
      END) = da.advertiser_id
 AND COALESCE(c.conversion_time, c.updated_at) >= da.valid_from 
 AND (COALESCE(c.conversion_time, c.updated_at) < da.valid_to OR da.valid_to IS NULL)
LEFT JOIN pulsetrack_gold.dim_campaign dc ON c.campaign_id = dc.campaign_id
LEFT JOIN pulsetrack_gold.dim_offer dof ON sc.offer_id = dof.offer_id
LEFT JOIN pulsetrack_gold.dim_partner dp ON c.partner_id = dp.partner_id
LEFT JOIN pulsetrack_gold.dim_device_geo dg ON c.device_type = dg.device_type AND c.country_code = dg.country_code
LEFT JOIN pulsetrack_gold.dim_junk_conversion dj ON c.status = dj.status;

-- B. Fact Clicks
TRUNCATE TABLE fact_click CASCADE;
INSERT INTO fact_click (
    click_id, click_time, click_date_key,
    campaign_key, partner_key, creative_key, device_geo_key,
    impression_id, click_count, is_unique
)
SELECT 
    k.click_id,
    k.click_time,
    COALESCE(to_char(k.click_time, 'YYYYMMDD')::INT, 19000101) AS click_date_key,
    dc.campaign_key,
    dp.partner_key,
    dcr.creative_key,
    dg.device_geo_key,
    k.impression_id,
    1 AS click_count,
    k.is_unique
FROM pulsetrack_silver.stg_clicks k
LEFT JOIN pulsetrack_gold.dim_campaign dc ON k.campaign_id = dc.campaign_id
LEFT JOIN pulsetrack_gold.dim_partner dp ON k.partner_id = dp.partner_id
LEFT JOIN pulsetrack_gold.dim_creative dcr ON k.creative_id = dcr.creative_id
LEFT JOIN pulsetrack_gold.dim_device_geo dg ON k.device_type = dg.device_type AND k.country_code = dg.country_code;

-- C. Fact Impressions
TRUNCATE TABLE fact_impression CASCADE;
INSERT INTO fact_impression (
    impression_id, impression_time, impression_date_key,
    campaign_key, creative_key, partner_key, device_geo_key, impression_count
)
SELECT 
    i.impression_id,
    i.impression_time,
    COALESCE(to_char(i.impression_time, 'YYYYMMDD')::INT, 19000101) AS impression_date_key,
    dc.campaign_key,
    dcr.creative_key,
    dp.partner_key,
    dg.device_geo_key,
    1 AS impression_count
FROM pulsetrack_silver.stg_impressions i
LEFT JOIN pulsetrack_gold.dim_campaign dc ON i.campaign_id = dc.campaign_id
LEFT JOIN pulsetrack_gold.dim_creative dcr ON i.creative_id = dcr.creative_id
LEFT JOIN pulsetrack_gold.dim_partner dp ON i.partner_id = dp.partner_id
LEFT JOIN pulsetrack_gold.dim_device_geo dg ON i.device_type = dg.device_type AND i.country_code = dg.country_code;

-- D. Fact Revenue Adjustments
TRUNCATE TABLE fact_revenue_adjustment CASCADE;
INSERT INTO fact_revenue_adjustment (
    adjustment_id, conversion_key, conversion_id,
    adjustment_time, adjustment_date_key, delta_amount, reason
)
SELECT 
    r.adjustment_id,
    fc.conversion_key,
    r.conversion_id,
    r.adjusted_at AS adjustment_time,
    COALESCE(to_char(r.adjusted_at, 'YYYYMMDD')::INT, 19000101) AS adjustment_date_key,
    r.delta_amount,
    r.reason
FROM pulsetrack_silver.stg_revenue_adjustments r
LEFT JOIN pulsetrack_gold.fact_conversion fc ON r.conversion_id = fc.conversion_id;

-- E. Bridge Conversion Touchpoints (Multi-Touch Attribution)
TRUNCATE TABLE bridge_conversion_touchpoint CASCADE;
INSERT INTO bridge_conversion_touchpoint (
    touchpoint_id, conversion_key, click_id, partner_key, touch_position, attribution_weight
)
SELECT 
    t.touchpoint_id,
    fc.conversion_key,
    t.click_id,
    dp.partner_key,
    t.touch_position,
    t.attribution_weight
FROM pulsetrack_silver.stg_conversion_touchpoints t
JOIN pulsetrack_gold.fact_conversion fc ON t.conversion_id = fc.conversion_id
LEFT JOIN pulsetrack_silver.stg_clicks sc ON t.click_id = sc.click_id
LEFT JOIN pulsetrack_gold.dim_partner dp ON sc.partner_id = dp.partner_id;
