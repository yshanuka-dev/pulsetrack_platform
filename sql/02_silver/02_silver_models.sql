-- ============================================================================
-- PulseTrack Silver Layer: Cleansing, Deduplication & Standardisation
-- Schema: pulsetrack_silver
-- ============================================================================

SET search_path TO pulsetrack_silver, pulsetrack_raw;

-- 1. Cleansed Account Managers
DROP TABLE IF EXISTS stg_account_managers CASCADE;
CREATE TABLE stg_account_managers AS
SELECT 
    am_id,
    COALESCE(NULLIF(TRIM(am_name), ''), 'Unknown AM') AS am_name,
    UPPER(TRIM(team)) AS team,
    UPPER(TRIM(region)) AS region,
    pulsetrack_silver.parse_timestamp_utc(hire_date)::DATE AS hire_date,
    _batch_id
FROM pulsetrack_raw.account_managers_raw;

-- 2. Flattened Advertiser AM History (SCD Type 2 Ground Truth from MongoDB)
DROP TABLE IF EXISTS stg_advertiser_am_history CASCADE;
CREATE TABLE stg_advertiser_am_history AS
WITH parsed_json AS (
    SELECT 
        advertiser_id,
        COALESCE(legal_name, display_name) AS advertiser_name,
        doc_json::JSONB AS doc
    FROM pulsetrack_raw.raw_mongo_advertiser_accounts
),
flattened AS (
    SELECT 
        advertiser_id,
        advertiser_name,
        elem->>'am_id' AS am_id,
        elem->>'am_name' AS am_name,
        pulsetrack_silver.parse_timestamp_utc(elem->>'from') AS valid_from,
        pulsetrack_silver.parse_timestamp_utc(elem->>'to') AS valid_to
    FROM parsed_json,
    LATERAL jsonb_array_elements(doc->'account_manager_history') AS elem
)
SELECT 
    advertiser_id,
    advertiser_name,
    am_id,
    am_name,
    valid_from,
    valid_to,
    CASE WHEN valid_to IS NULL THEN TRUE ELSE FALSE END AS is_current
FROM flattened;

-- 3. Cleansed Advertisers (Base Reference)
DROP TABLE IF EXISTS stg_advertisers CASCADE;
CREATE TABLE stg_advertisers AS
SELECT 
    advertiser_id,
    INITCAP(TRIM(advertiser_name)) AS advertiser_name,
    INITCAP(TRIM(vertical)) AS vertical,
    LOWER(TRIM(status)) AS status,
    account_manager_id AS current_am_id,
    pulsetrack_silver.parse_timestamp_utc(signup_date)::DATE AS signup_date,
    UPPER(TRIM(billing_country)) AS billing_country,
    _batch_id
FROM pulsetrack_raw.advertisers_raw;

-- 4. Conformed Partners (Resolving the 40 missing partners from MongoDB)
DROP TABLE IF EXISTS stg_partners CASCADE;
CREATE TABLE stg_partners AS
WITH raw_relational AS (
    SELECT 
        REGEXP_SUBSTR(TRIM(partner_id), '^[0-9]{5}') AS canonical_partner_id,
        INITCAP(TRIM(partner_name)) AS partner_name,
        INITCAP(TRIM(channel)) AS channel,
        INITCAP(TRIM(media_buyer)) AS media_buyer,
        UPPER(TRIM(payment_terms)) AS payment_terms,
        'relational' AS source_system
    FROM pulsetrack_raw.partners_raw
    WHERE partner_id ~ '^[0-9]{5}'
),
mongo_parsed AS (
    SELECT 
        REGEXP_SUBSTR(TRIM(partner_id), '^[0-9]{5}') AS canonical_partner_id,
        INITCAP(TRIM(partner_name)) AS partner_name,
        doc_json::JSONB AS doc
    FROM pulsetrack_raw.raw_mongo_partner_profiles
    WHERE partner_id ~ '^[0-9]{5}'
),
mongo_flattened AS (
    SELECT 
        canonical_partner_id,
        partner_name,
        INITCAP(TRIM(doc->'channels'->>0)) AS channel,
        INITCAP(TRIM(doc->'contact'->>'person')) AS media_buyer,
        UPPER(TRIM(doc->'payment'->>'terms')) AS payment_terms,
        'mongo_crm' AS source_system
    FROM mongo_parsed
),
all_partners AS (
    -- CRM portal details take precedence for name if available
    SELECT 
        COALESCE(m.canonical_partner_id, r.canonical_partner_id) AS partner_id,
        COALESCE(m.partner_name, r.partner_name, 'Unknown Partner') AS partner_name,
        COALESCE(r.channel, m.channel, 'Other') AS channel,
        COALESCE(r.media_buyer, m.media_buyer, 'Unassigned') AS media_buyer,
        COALESCE(r.payment_terms, m.payment_terms, 'NET30') AS payment_terms,
        CASE 
            WHEN r.canonical_partner_id IS NOT NULL AND m.canonical_partner_id IS NOT NULL THEN 'hybrid'
            WHEN m.canonical_partner_id IS NOT NULL THEN 'mongo_crm'
            ELSE 'relational'
        END AS source_system
    FROM raw_relational r
    FULL OUTER JOIN mongo_flattened m ON r.canonical_partner_id = m.canonical_partner_id
)
SELECT DISTINCT ON (partner_id) * FROM all_partners WHERE partner_id IS NOT NULL;

-- 5. Cleansed Offers
DROP TABLE IF EXISTS stg_offers CASCADE;
CREATE TABLE stg_offers AS
SELECT 
    offer_id,
    advertiser_id,
    TRIM(offer_name) AS offer_name,
    pulsetrack_silver.parse_money(default_payout) AS default_payout,
    INITCAP(TRIM(vertical)) AS vertical,
    UPPER(TRIM(payout_type)) AS payout_type,
    _batch_id
FROM pulsetrack_raw.offers_raw;

-- 6. Cleansed Campaigns
DROP TABLE IF EXISTS stg_campaigns CASCADE;
CREATE TABLE stg_campaigns AS
SELECT 
    campaign_id,
    offer_id,
    advertiser_id,
    TRIM(campaign_name) AS campaign_name,
    UPPER(TRIM(price_type)) AS price_type,
    pulsetrack_silver.parse_timestamp_utc(start_date)::DATE AS start_date,
    pulsetrack_silver.parse_timestamp_utc(end_date)::DATE AS end_date,
    _batch_id
FROM pulsetrack_raw.campaigns_raw;

-- 7. Cleansed Creatives
DROP TABLE IF EXISTS stg_creatives CASCADE;
CREATE TABLE stg_creatives AS
SELECT 
    creative_id,
    campaign_id,
    TRIM(creative_name) AS creative_name,
    LOWER(TRIM(format)) AS format,
    TRIM(size) AS dimensions,
    TRIM(landing_url) AS landing_url,
    _batch_id
FROM pulsetrack_raw.creatives_raw;

-- 8. Cleansed Impressions
DROP TABLE IF EXISTS stg_impressions CASCADE;
CREATE TABLE stg_impressions AS
SELECT 
    impression_id,
    campaign_id,
    NULLIF(TRIM(creative_id), '') AS creative_id,
    REGEXP_SUBSTR(TRIM(partner_id), '^[0-9]{5}') AS partner_id,
    pulsetrack_silver.parse_timestamp_utc(impression_time) AS impression_time,
    COALESCE(UPPER(TRIM(country)), 'UNKNOWN') AS country_code,
    CASE 
        WHEN LOWER(device) LIKE '%mobile%' OR LOWER(device) LIKE '%phone%' THEN 'mobile'
        WHEN LOWER(device) LIKE '%tablet%' OR LOWER(device) LIKE '%pad%' THEN 'tablet'
        WHEN LOWER(device) LIKE '%desktop%' OR LOWER(device) LIKE '%pc%' THEN 'desktop'
        ELSE 'other'
    END AS device_type,
    _batch_id
FROM pulsetrack_raw.impressions_raw;

-- 9. Cleansed Clicks
DROP TABLE IF EXISTS stg_clicks CASCADE;
CREATE TABLE stg_clicks AS
SELECT 
    click_id,
    NULLIF(TRIM(impression_id), '') AS impression_id,
    campaign_id,
    NULLIF(TRIM(creative_id), '') AS creative_id,
    REGEXP_SUBSTR(TRIM(partner_id), '^[0-9]{5}') AS partner_id,
    pulsetrack_silver.parse_timestamp_utc(click_time) AS click_time,
    CASE WHEN TRIM(is_unique) IN ('1', 'true', 'TRUE', 'Y', 'yes') THEN 1 ELSE 0 END AS is_unique,
    COALESCE(UPPER(TRIM(country)), 'UNKNOWN') AS country_code,
    CASE 
        WHEN LOWER(device) LIKE '%mobile%' OR LOWER(device) LIKE '%phone%' THEN 'mobile'
        WHEN LOWER(device) LIKE '%tablet%' OR LOWER(device) LIKE '%pad%' THEN 'tablet'
        WHEN LOWER(device) LIKE '%desktop%' OR LOWER(device) LIKE '%pc%' THEN 'desktop'
        ELSE 'other'
    END AS device_type,
    _batch_id
FROM pulsetrack_raw.clicks_raw;

-- 10. Cleansed & Deduplicated Conversions (The Core Staging Table)
-- Filter is_test, Deduplicate via MAX(updated_at)
DROP TABLE IF EXISTS stg_conversions CASCADE;
CREATE TABLE stg_conversions AS
WITH raw_filtered AS (
    SELECT 
        conversion_id,
        NULLIF(TRIM(click_id), '') AS click_id,
        campaign_id,
        REGEXP_SUBSTR(TRIM(partner_id), '^[0-9]{5}') AS partner_id,
        pulsetrack_silver.parse_timestamp_utc(conversion_time) AS conversion_time,
        COALESCE(pulsetrack_silver.parse_money(revenue), 0.0000) AS gross_revenue,
        COALESCE(pulsetrack_silver.parse_money(payout), 0.0000) AS payout_amount,
        COALESCE(pulsetrack_silver.parse_money(revenue), 0.0000) - COALESCE(pulsetrack_silver.parse_money(payout), 0.0000) AS net_margin,
        CASE 
            WHEN LOWER(status) LIKE '%app%' OR status = '1' THEN 'approved'
            WHEN LOWER(status) LIKE '%rev%' OR LOWER(status) LIKE '%ret%' THEN 'reversed'
            ELSE 'pending'
        END AS status,
        COALESCE(UPPER(TRIM(country)), 'UNKNOWN') AS country_code,
        CASE 
            WHEN LOWER(device) LIKE '%mobile%' OR LOWER(device) LIKE '%phone%' THEN 'mobile'
            WHEN LOWER(device) LIKE '%tablet%' OR LOWER(device) LIKE '%pad%' THEN 'tablet'
            WHEN LOWER(device) LIKE '%desktop%' OR LOWER(device) LIKE '%pc%' THEN 'desktop'
            ELSE 'other'
        END AS device_type,
        pulsetrack_silver.parse_timestamp_utc(updated_at) AS updated_at,
        _batch_id,
        ROW_NUMBER() OVER (
            PARTITION BY conversion_id 
            ORDER BY pulsetrack_silver.parse_timestamp_utc(updated_at) DESC NULLS LAST
        ) AS rn
    FROM pulsetrack_raw.conversions_raw
    WHERE TRIM(COALESCE(is_test, '')) NOT IN ('test', '1', 'true', 'TRUE')
)
SELECT 
    conversion_id,
    click_id,
    campaign_id,
    partner_id,
    conversion_time,
    gross_revenue,
    payout_amount,
    net_margin,
    status,
    country_code,
    device_type,
    updated_at,
    _batch_id
FROM raw_filtered
WHERE rn = 1;

-- 11. Cleansed Conversion Touchpoints (Attribution Bridge Staging)
DROP TABLE IF EXISTS stg_conversion_touchpoints CASCADE;
CREATE TABLE stg_conversion_touchpoints AS
SELECT 
    touchpoint_id,
    conversion_id,
    click_id,
    LOWER(TRIM(touch_position)) AS touch_position,
    COALESCE(TRIM(weight)::NUMERIC, 0.0000) AS attribution_weight,
    _batch_id
FROM pulsetrack_raw.conversion_touchpoints_raw;

-- 12. Cleansed Revenue Adjustments
DROP TABLE IF EXISTS stg_revenue_adjustments CASCADE;
CREATE TABLE stg_revenue_adjustments AS
SELECT 
    adjustment_id,
    conversion_id,
    COALESCE(pulsetrack_silver.parse_money(delta_amount), 0.0000) AS delta_amount,
    TRIM(reason) AS reason,
    pulsetrack_silver.parse_timestamp_utc(adjusted_at) AS adjusted_at,
    _batch_id
FROM pulsetrack_raw.revenue_adjustments_raw;
