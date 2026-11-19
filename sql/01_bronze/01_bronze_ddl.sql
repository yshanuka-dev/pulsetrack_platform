-- ============================================================================
-- PulseTrack Bronze Layer (Staging DDL)
-- Schema: pulsetrack_raw
-- Untyped text representation with ingestion audit metadata
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS pulsetrack_raw;
SET search_path TO pulsetrack_raw;

-- 1) account_managers_raw
DROP TABLE IF EXISTS account_managers_raw CASCADE;
CREATE TABLE account_managers_raw (
    am_id           TEXT,
    am_name         TEXT,
    team            TEXT,
    region          TEXT,
    hire_date       TEXT,
    created_at      TEXT,
    updated_at      TEXT,
    _batch_id       TEXT,
    _source_file    TEXT,
    _ingested_at    TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 2) advertisers_raw
DROP TABLE IF EXISTS advertisers_raw CASCADE;
CREATE TABLE advertisers_raw (
    advertiser_id       TEXT,
    advertiser_name     TEXT,
    vertical            TEXT,
    status              TEXT,
    account_manager_id  TEXT,
    signup_date         TEXT,
    billing_country     TEXT,
    created_at          TEXT,
    updated_at          TEXT,
    _batch_id           TEXT,
    _source_file        TEXT,
    _ingested_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 3) partners_raw
DROP TABLE IF EXISTS partners_raw CASCADE;
CREATE TABLE partners_raw (
    partner_id          TEXT,
    partner_name        TEXT,
    channel             TEXT,
    media_buyer         TEXT,
    payment_terms       TEXT,
    join_date           TEXT,
    created_at          TEXT,
    updated_at          TEXT,
    _batch_id           TEXT,
    _source_file        TEXT,
    _ingested_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 4) offers_raw
DROP TABLE IF EXISTS offers_raw CASCADE;
CREATE TABLE offers_raw (
    offer_id            TEXT,
    advertiser_id       TEXT,
    offer_name          TEXT,
    default_payout      TEXT,
    vertical            TEXT,
    payout_type         TEXT,
    created_at          TEXT,
    updated_at          TEXT,
    _batch_id           TEXT,
    _source_file        TEXT,
    _ingested_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 5) campaigns_raw
DROP TABLE IF EXISTS campaigns_raw CASCADE;
CREATE TABLE campaigns_raw (
    campaign_id         TEXT,
    offer_id            TEXT,
    advertiser_id       TEXT,
    campaign_name       TEXT,
    price_type          TEXT,
    start_date          TEXT,
    end_date            TEXT,
    created_at          TEXT,
    updated_at          TEXT,
    _batch_id           TEXT,
    _source_file        TEXT,
    _ingested_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 6) creatives_raw
DROP TABLE IF EXISTS creatives_raw CASCADE;
CREATE TABLE creatives_raw (
    creative_id         TEXT,
    campaign_id         TEXT,
    creative_name       TEXT,
    format              TEXT,
    size                TEXT,
    landing_url         TEXT,
    created_at          TEXT,
    updated_at          TEXT,
    _batch_id           TEXT,
    _source_file        TEXT,
    _ingested_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 7) impressions_raw
DROP TABLE IF EXISTS impressions_raw CASCADE;
CREATE TABLE impressions_raw (
    impression_id       TEXT,
    campaign_id         TEXT,
    creative_id         TEXT,
    partner_id          TEXT,
    impression_time     TEXT,
    placement_raw       TEXT,
    country             TEXT,
    device              TEXT,
    bot_score           TEXT,
    created_at          TEXT,
    updated_at          TEXT,
    _batch_id           TEXT,
    _source_file        TEXT,
    _ingested_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 8) clicks_raw
DROP TABLE IF EXISTS clicks_raw CASCADE;
CREATE TABLE clicks_raw (
    click_id            TEXT,
    impression_id       TEXT,
    campaign_id         TEXT,
    creative_id         TEXT,
    partner_id          TEXT,
    click_time          TEXT,
    is_unique           TEXT,
    ip                  TEXT,
    user_agent          TEXT,
    country             TEXT,
    device              TEXT,
    referrer_raw        TEXT,
    created_at          TEXT,
    updated_at          TEXT,
    _batch_id           TEXT,
    _source_file        TEXT,
    _ingested_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 9) conversions_raw
DROP TABLE IF EXISTS conversions_raw CASCADE;
CREATE TABLE conversions_raw (
    conversion_id       TEXT,
    click_id            TEXT,
    campaign_id         TEXT,
    partner_id          TEXT,
    advertiser_name     TEXT,
    campaign_name       TEXT,
    partner_name        TEXT,
    offer_name          TEXT,
    account_manager     TEXT,
    price_type          TEXT,
    conversion_time     TEXT,
    revenue             TEXT,
    payout              TEXT,
    currency            TEXT,
    status              TEXT,
    country             TEXT,
    device              TEXT,
    sub_id              TEXT,
    is_test             TEXT,
    legacy_flag         TEXT,
    pixel_fired         TEXT,
    internal_note       TEXT,
    reserved_1          TEXT,
    created_at          TEXT,
    updated_at          TEXT,
    _batch_id           TEXT,
    _source_file        TEXT,
    _ingested_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 10) conversion_touchpoints_raw
DROP TABLE IF EXISTS conversion_touchpoints_raw CASCADE;
CREATE TABLE conversion_touchpoints_raw (
    touchpoint_id       TEXT,
    conversion_id       TEXT,
    click_id            TEXT,
    touch_position      TEXT,
    weight              TEXT,
    created_at          TEXT,
    updated_at          TEXT,
    _batch_id           TEXT,
    _source_file        TEXT,
    _ingested_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 11) revenue_adjustments_raw
DROP TABLE IF EXISTS revenue_adjustments_raw CASCADE;
CREATE TABLE revenue_adjustments_raw (
    adjustment_id       TEXT,
    conversion_id       TEXT,
    delta_amount        TEXT,
    reason              TEXT,
    adjusted_at         TEXT,
    created_at          TEXT,
    updated_at          TEXT,
    _batch_id           TEXT,
    _source_file        TEXT,
    _ingested_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 12) MongoDB PartnerHub CRM
DROP TABLE IF EXISTS raw_mongo_partner_profiles CASCADE;
CREATE TABLE raw_mongo_partner_profiles (
    partner_id          TEXT,
    partner_name        TEXT,
    doc_json            TEXT,
    _batch_id           TEXT,
    _ingested_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 13) MongoDB Advertiser CRM
DROP TABLE IF EXISTS raw_mongo_advertiser_accounts CASCADE;
CREATE TABLE raw_mongo_advertiser_accounts (
    advertiser_id       TEXT,
    legal_name          TEXT,
    display_name        TEXT,
    doc_json            TEXT,
    _batch_id           TEXT,
    _ingested_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 14) Kafka Event Stream
DROP TABLE IF EXISTS raw_kafka_conversions_stream CASCADE;
CREATE TABLE raw_kafka_conversions_stream (
    topic               TEXT,
    partition           INT,
    offset_val          BIGINT,
    ts_epoch            BIGINT,
    event_key           TEXT,
    payload_json        TEXT,
    _batch_id           TEXT,
    _ingested_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
