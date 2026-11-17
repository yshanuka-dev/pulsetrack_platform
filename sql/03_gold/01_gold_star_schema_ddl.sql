-- ============================================================================
-- PulseTrack Enterprise Data Warehouse (Gold Layer)
-- Target Kimball Star Schema DDL (PostgreSQL)
-- Specification: Question 2 (20 Marks)
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS pulsetrack_gold;
SET search_path TO pulsetrack_gold;

-- ----------------------------------------------------------------------------
-- 1. CONFORMED DIMENSIONS
-- ----------------------------------------------------------------------------

-- A. Date Dimension (Role-Playing for Impressions, Clicks, Conversions, Adjustments)
CREATE TABLE IF NOT EXISTS dim_date (
    date_key            INT PRIMARY KEY,              -- YYYYMMDD
    calendar_date       DATE NOT NULL UNIQUE,
    year                INT NOT NULL,
    quarter             VARCHAR(2) NOT NULL,          -- Q1, Q2, Q3, Q4
    quarter_name        VARCHAR(10) NOT NULL,         -- 2025-Q1
    month               INT NOT NULL,
    month_name          VARCHAR(20) NOT NULL,         -- January
    month_year          VARCHAR(10) NOT NULL,         -- 2025-01
    day_of_month        INT NOT NULL,
    day_of_week         INT NOT NULL,                 -- 1 = Monday, 7 = Sunday
    day_name            VARCHAR(20) NOT NULL,
    is_weekend          BOOLEAN NOT NULL
);

-- B. Advertiser Dimension (Slowly Changing Dimension - SCD Type 2)
-- Preserves historical Account Manager assignments over time
CREATE TABLE IF NOT EXISTS dim_advertiser (
    advertiser_sk       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    advertiser_id       VARCHAR(32) NOT NULL,         -- Natural Key (ADVxxxxx)
    advertiser_name     VARCHAR(255) NOT NULL,
    vertical            VARCHAR(100),
    billing_country     VARCHAR(10),
    am_id               VARCHAR(32),                  -- Account Manager Natural Key
    am_name             VARCHAR(255),
    am_team             VARCHAR(100),
    am_region           VARCHAR(100),
    valid_from          TIMESTAMPTZ NOT NULL,
    valid_to            TIMESTAMPTZ,                  -- NULL = Current record
    is_current          BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE INDEX IF NOT EXISTS idx_dim_adv_lookup
ON dim_advertiser (advertiser_id, valid_from, valid_to);

-- C. Partner Dimension (Conformed across partners_raw + MongoDB partner_profiles)
CREATE TABLE IF NOT EXISTS dim_partner (
    partner_key         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    partner_id          VARCHAR(16) NOT NULL UNIQUE,  -- Canonical 5-digit prefix (e.g. 42266)
    partner_name        VARCHAR(255) NOT NULL,
    channel             VARCHAR(100),
    media_buyer         VARCHAR(100),
    payment_terms       VARCHAR(50),
    source_system       VARCHAR(50) NOT NULL          -- 'relational', 'mongo_crm', or 'hybrid'
);
CREATE INDEX IF NOT EXISTS idx_dim_partner_id ON dim_partner (partner_id);

-- D. Campaign Dimension
CREATE TABLE IF NOT EXISTS dim_campaign (
    campaign_key        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    campaign_id         VARCHAR(32) NOT NULL UNIQUE,  -- CMPxxxxx
    campaign_name       VARCHAR(255) NOT NULL,
    price_type          VARCHAR(20),                  -- CPA, CPC, CPM, Fixed
    start_date          DATE,
    end_date            DATE,
    advertiser_id       VARCHAR(32),
    offer_id            VARCHAR(32)
);
CREATE INDEX IF NOT EXISTS idx_dim_campaign_id ON dim_campaign (campaign_id);

-- E. Offer Dimension
CREATE TABLE IF NOT EXISTS dim_offer (
    offer_key           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    offer_id            VARCHAR(32) NOT NULL UNIQUE,  -- OFFxxxxx
    advertiser_id       VARCHAR(32),
    offer_name          VARCHAR(255) NOT NULL,
    payout_type         VARCHAR(50),
    default_payout      NUMERIC(14,4)
);
CREATE INDEX IF NOT EXISTS idx_dim_offer_id ON dim_offer (offer_id);

-- F. Creative Dimension
CREATE TABLE IF NOT EXISTS dim_creative (
    creative_key        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    creative_id         VARCHAR(32) NOT NULL UNIQUE,  -- CRExxxxx
    campaign_id         VARCHAR(32),
    creative_name       VARCHAR(255) NOT NULL,
    format              VARCHAR(50),
    dimensions          VARCHAR(50),
    landing_url         TEXT
);
CREATE INDEX IF NOT EXISTS idx_dim_creative_id ON dim_creative (creative_id);

-- G. Device & Geography Junk Dimension
CREATE TABLE IF NOT EXISTS dim_device_geo (
    device_geo_key      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    device_type         VARCHAR(50) NOT NULL,         -- desktop, mobile, tablet, other
    country_code        VARCHAR(10) NOT NULL,         -- US, GB, CA, etc.
    CONSTRAINT uq_device_geo UNIQUE (device_type, country_code)
);

-- H. Conversion Junk Dimension (Flags & Categoricals)
CREATE TABLE IF NOT EXISTS dim_junk_conversion (
    junk_conversion_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    status              VARCHAR(20) NOT NULL,         -- approved, pending, reversed
    currency            VARCHAR(10) NOT NULL,         -- USD
    CONSTRAINT uq_junk_conversion UNIQUE (status, currency)
);

-- ----------------------------------------------------------------------------
-- 2. FACT & BRIDGE TABLES
-- ----------------------------------------------------------------------------

-- A. Fact Conversions (Transactional Core Metric Fact)
-- Grain: One row per unique valid conversion event (deduplicated at MAX(updated_at))
CREATE TABLE IF NOT EXISTS fact_conversion (
    conversion_key      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    conversion_id       VARCHAR(32) NOT NULL UNIQUE,  -- Degenerate Dimension
    conversion_time     TIMESTAMPTZ NOT NULL,
    conversion_date_key INT NOT NULL REFERENCES dim_date(date_key),
    
    -- Dimensional Foreign Keys
    advertiser_sk       BIGINT NOT NULL REFERENCES dim_advertiser(advertiser_sk),
    campaign_key        BIGINT REFERENCES dim_campaign(campaign_key),
    offer_key           BIGINT REFERENCES dim_offer(offer_key),
    partner_key         BIGINT REFERENCES dim_partner(partner_key),
    device_geo_key      BIGINT REFERENCES dim_device_geo(device_geo_key),
    junk_conversion_key BIGINT REFERENCES dim_junk_conversion(junk_conversion_key),
    
    -- Measures
    gross_revenue       NUMERIC(14,4) NOT NULL DEFAULT 0.0000,
    payout_amount       NUMERIC(14,4) NOT NULL DEFAULT 0.0000,
    net_margin          NUMERIC(14,4) NOT NULL DEFAULT 0.0000,
    conversion_count    INT NOT NULL DEFAULT 1,
    
    -- Audit Metadata
    silver_ingest_time  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_fconv_date ON fact_conversion (conversion_date_key);
CREATE INDEX IF NOT EXISTS idx_fconv_adv ON fact_conversion (advertiser_sk);
CREATE INDEX IF NOT EXISTS idx_fconv_camp ON fact_conversion (campaign_key);
CREATE INDEX IF NOT EXISTS idx_fconv_partner ON fact_conversion (partner_key);

-- B. Fact Clicks (Funnel Interaction Fact)
-- Grain: One row per user click interaction
CREATE TABLE IF NOT EXISTS fact_click (
    click_key           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    click_id            VARCHAR(32) NOT NULL UNIQUE,  -- Degenerate Dimension
    click_time          TIMESTAMPTZ NOT NULL,
    click_date_key      INT NOT NULL REFERENCES dim_date(date_key),
    
    -- Dimensional Foreign Keys
    campaign_key        BIGINT REFERENCES dim_campaign(campaign_key),
    partner_key         BIGINT REFERENCES dim_partner(partner_key),
    creative_key        BIGINT REFERENCES dim_creative(creative_key),
    device_geo_key      BIGINT REFERENCES dim_device_geo(device_geo_key),
    
    -- Associated Top-of-Funnel link (nullable for direct clicks)
    impression_id       VARCHAR(32),
    
    -- Measures
    click_count         INT NOT NULL DEFAULT 1,
    is_unique           INT NOT NULL DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_fclick_date ON fact_click (click_date_key);
CREATE INDEX IF NOT EXISTS idx_fclick_camp ON fact_click (campaign_key);
CREATE INDEX IF NOT EXISTS idx_fclick_partner ON fact_click (partner_key);

-- C. Fact Impressions (Funnel Reach Factless Fact)
-- Grain: One row per ad creative impression view
CREATE TABLE IF NOT EXISTS fact_impression (
    impression_key      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    impression_id       VARCHAR(32) NOT NULL UNIQUE,  -- Degenerate Dimension
    impression_time     TIMESTAMPTZ NOT NULL,
    impression_date_key INT NOT NULL REFERENCES dim_date(date_key),
    
    -- Dimensional Foreign Keys
    campaign_key        BIGINT REFERENCES dim_campaign(campaign_key),
    creative_key        BIGINT REFERENCES dim_creative(creative_key),
    partner_key         BIGINT REFERENCES dim_partner(partner_key),
    device_geo_key      BIGINT REFERENCES dim_device_geo(device_geo_key),
    
    -- Measures
    impression_count    INT NOT NULL DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_fimp_date ON fact_impression (impression_date_key);
CREATE INDEX IF NOT EXISTS idx_fimp_camp ON fact_impression (campaign_key);

-- D. Fact Revenue Adjustments (Accumulating / Late-Arriving Fact)
-- Grain: One row per late adjustment transaction
CREATE TABLE IF NOT EXISTS fact_revenue_adjustment (
    adjustment_key      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    adjustment_id       VARCHAR(32) NOT NULL UNIQUE,  -- Degenerate Dimension
    conversion_key      BIGINT REFERENCES fact_conversion(conversion_key),
    conversion_id       VARCHAR(32) NOT NULL,
    adjustment_time     TIMESTAMPTZ NOT NULL,
    adjustment_date_key INT NOT NULL REFERENCES dim_date(date_key),
    
    -- Measures
    delta_amount        NUMERIC(14,4) NOT NULL,       -- Positive or negative adjustment
    reason              TEXT
);
CREATE INDEX IF NOT EXISTS idx_fadj_conv ON fact_revenue_adjustment (conversion_key);
CREATE INDEX IF NOT EXISTS idx_fadj_date ON fact_revenue_adjustment (adjustment_date_key);

-- E. Bridge Conversion Touchpoint (Multi-Touch Attribution Bridge)
-- Grain: One row per conversion-to-click touchpoint pair
CREATE TABLE IF NOT EXISTS bridge_conversion_touchpoint (
    touchpoint_key      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    touchpoint_id       VARCHAR(32) NOT NULL UNIQUE,
    conversion_key      BIGINT NOT NULL REFERENCES fact_conversion(conversion_key) ON DELETE CASCADE,
    click_id            VARCHAR(32) NOT NULL,
    partner_key         BIGINT REFERENCES dim_partner(partner_key),
    touch_position      VARCHAR(10) NOT NULL,         -- first, mid, last
    attribution_weight  NUMERIC(6,4) NOT NULL         -- Non-additive; fractional weight (sums to ~1.0)
);
CREATE INDEX IF NOT EXISTS idx_bridge_conv ON bridge_conversion_touchpoint (conversion_key);
CREATE INDEX IF NOT EXISTS idx_bridge_partner ON bridge_conversion_touchpoint (partner_key);
