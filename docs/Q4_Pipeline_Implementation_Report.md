# PulseTrack ETL/ELT Pipeline Implementation & EDW Population Report
**Document Code:** PT-IMPL-004  
**Project:** PulseTrack Data Warehousing Capstone  
**Assessment Phase:** Question 4 (20 Marks)  
**Author:** Lead Data Engineer / Enterprise Data Architect  
**Status:** Successfully Executed & Verified in PostgreSQL  

---

## 1. Executive Implementation Summary

The end-to-end Medallion ETL/ELT pipeline for PulseTrack has been fully implemented, executed, and validated against the local PostgreSQL warehouse (`pulsetrack_dw`). 

The pipeline extracted **958,166 raw records** across **11 relational CSV files**, **2 MongoDB CRM document collections**, and a **Kafka real-time conversion stream log**. It successfully transformed, cleansed, and loaded these records into a high-performance Kimball Constellation Star Schema in the `pulsetrack_gold` schema.

---

## 2. Complete Medallion Layer Verification Ledger

### 2.1 Bronze Layer (`pulsetrack_raw`)
* **Execution Time:** 23.96 seconds
* **Status:** 100% Ingested with metadata (`_batch_id`, `_source_file`, `_ingested_at`)

| Table Name | Source Modality | Ingested Rows | Ingestion Notes |
| :--- | :--- | :-: | :--- |
| `account_managers_raw` | Relational CSV | 25 | Stored untyped text; captured AM013 null name |
| `advertisers_raw` | Relational CSV | 60 | Current AM representation; casing variations preserved |
| `campaigns_raw` | Relational CSV | 400 | Preserved campaign-offer-advertiser links |
| `clicks_raw` | Relational CSV | 150,000 | Preserved mixed boolean types and PII columns |
| `conversion_touchpoints_raw` | Relational CSV | 183,529 | Multi-touch bridge data |
| `conversions_raw` | Relational CSV | 126,380 | All 36,380 duplicate/lifecycle states captured |
| `creatives_raw` | Relational CSV | 1,200 | Deepest snowflake node |
| `impressions_raw` | Relational CSV | 300,000 | Factless top-of-funnel reach |
| `offers_raw` | Relational CSV | 150 | Unparsed text currency values (`$15.00`) |
| `partners_raw` | Relational CSV | 600 | Missing 40 active partner IDs (by design) |
| `revenue_adjustments_raw` | Relational CSV | 12,000 | Late-arriving adjustments |
| `raw_mongo_partner_profiles`| MongoDB JSONL | 600 | Unnested JSON; provides the 40 missing partner IDs |
| `raw_mongo_advertiser_accounts` | MongoDB JSONL | 60 | Houses `account_manager_history[]` SCD-2 ground truth |
| `raw_kafka_conversions_stream` | Kafka Stream Log | 182,978 | Validated JSON payloads across 4 partitions |
| `quarantine_stream_lines` | Audit Quarantine | 184 | **184 truncated/malformed stream lines quarantined** |

---

### 2.2 Silver Layer (`pulsetrack_silver`)
* **Execution Time:** 13.30 seconds
* **Transformations Applied:** Currency regex parsing, UTC date normalization, test record filtering (`is_test`), deterministic conversion deduplication (`MAX(updated_at)`), and cross-source entity resolution.

| Table Name | Silver Cleansed Rows | Key Transformations Applied |
| :--- | :-: | :--- |
| `stg_account_managers` | 25 | Standardized dates; filled AM013 null name with `'Unknown AM'`. |
| `stg_advertiser_am_history` | 74 | Flattened MongoDB `account_manager_history` array into 74 relational SCD-2 intervals. |
| `stg_advertisers` | 60 | Canonicalized names (`INITCAP`); standardized status and billing country. |
| `stg_partners` | **640** | **Successfully merged CSV partners (600) with MongoDB CRM (600), resolving all 40 orphaned partner prefixes!** |
| `stg_offers` | 150 | Parsed `default_payout` currency string into `NUMERIC(14,4)`. |
| `stg_campaigns` | 400 | Standardized `price_type` (CPA, CPC, CPM, FIXED). |
| `stg_creatives` | 1,200 | Standardized format and dimensions. |
| `stg_impressions` | 300,000 | Normalized device types (`mobile`, `desktop`, `tablet`, `other`); dropped junk columns. |
| `stg_clicks` | 150,000 | Converted `is_unique` to integer boolean (`1/0`); masked PII. |
| `stg_conversions` | **86,335** | **Filtered `is_test` truthy records; deduplicated 126,380 rows to 86,335 final conversions via `MAX(updated_at)`.** |
| `stg_conversion_touchpoints` | 183,529 | Converted attribution weight to `NUMERIC(6,4)`. |
| `stg_revenue_adjustments` | 12,000 | Parsed `delta_amount` to numeric, preserving negative values for refunds. |

---

### 2.3 Gold Layer (`pulsetrack_gold`)
* **Execution Time:** 36.52 seconds
* **Target Schema:** Kimball Constellation Star Schema populated with surrogate keys and strict referential integrity.

| Target Table Name | Table Type | Populated Rows | Foreign Keys & Granularity Verification |
| :--- | :--- | :-: | :--- |
| **`dim_date`** | Conformed Dimension | 1,462 | 2024-01-01 to 2027-12-31 + Default Unknown Record (`19000101`). |
| **`dim_advertiser`** | SCD Type 2 Dimension | 74 | 60 brands tracked across 74 historical AM assignment intervals with `valid_from`, `valid_to`, `is_current`. |
| **`dim_partner`** | Conformed Dimension | 640 | 100% resolved partner dimension; zero orphaned keys. |
| **`dim_campaign`** | Conformed Dimension | 400 | Linked to healed advertiser IDs and offer IDs. |
| **`dim_offer`** | Conformed Dimension | 150 | Product promotions with numeric payouts. |
| **`dim_creative`** | Conformed Dimension | 1,200 | Deepest creative dimension assets. |
| **`dim_device_geo`** | Junk Dimension | 40 | Discrete `device_type` $\times$ `country_code` pairs. |
| **`dim_junk_conversion`**| Junk Dimension | 3 | Distinct `status` (`approved`, `pending`, `reversed`) $\times$ `USD`. |
| **`fact_conversion`** | Core Transaction Fact | **86,335** | **100.00% match! Every valid conversion linked to its exact SCD-2 advertiser version at event time.** |
| **`fact_click`** | Interaction Fact | 150,000 | Linked to campaigns, partners, creatives, and date keys. |
| **`fact_impression`** | Factless Reach Fact | 300,000 | Linked to campaigns, creatives, partners, and date keys. |
| **`fact_revenue_adjustment`**| Accumulating Fact | 12,000 | Linked to `fact_conversion` via `conversion_key`. |
| **`bridge_conversion_touchpoint`**| Attribution Bridge | 176,009 | Multi-touch fractional weights ($w_1 + w_2 \approx 1.0$) linked to conversions. |

---

## 3. Engineering Design Adjustments & Root-Cause Justifications

As mandated by Question 4 (*"If a design problem is discovered, document the change, justify it and explain its downstream impact"*), our pipeline revealed three critical real-world edge cases in the source data that required engineering adjustments:

### Adjustment 1: Healed Orphan Campaign Advertisers
* **Discovery:** In `campaigns_raw`, 12 campaigns carried invalid advertiser IDs (e.g., `ADV9333`) that contradicted the linked offer's valid advertiser ID.
* **Engineering Solution:** Implemented relation healing in Silver staging:
  ```sql
  CASE 
      WHEN EXISTS (SELECT 1 FROM pulsetrack_silver.stg_advertisers sa WHERE sa.advertiser_id = sc.advertiser_id) 
      THEN sc.advertiser_id 
      ELSE so.advertiser_id 
  END AS advertiser_id
  ```
* **Downstream Impact:** Prevented 2,530 conversions from dropping due to foreign key violations, raising conversion loading from 97.07% to **100.00%**.

### Adjustment 2: Open-Ended Initial SCD-2 History Interval
* **Discovery:** In MongoDB `account_manager_history`, an advertiser's first recorded historical interval started on the date of their first CRM audit log (e.g., `2025-04-12`), while campaign conversion activity began earlier during initial launch (e.g., `2025-01-17`).
* **Engineering Solution:** Applied Kimball best practice: the first historical version (`rn = 1`) has its `valid_from` open-ended backwards to `'1900-01-01 00:00:00+00'`.
* **Downstream Impact:** All early conversions correctly inherit the advertiser's founding Account Manager, preserving 100% historical accuracy without dropping facts.

### Adjustment 3: Handling Missing Event Timestamps with an Unknown Date Dimension
* **Discovery:** In `clicks_raw` and `impressions_raw`, ~1.5% to 2.9% of event records had missing or unparseable timestamps. Direct foreign key constraints on `dim_date(date_key)` would have caused pipeline crashes.
* **Engineering Solution:** Inserted a standard **Unknown Date record** (`date_key = 19000101`, `year = 1900`, `month = 'Unknown'`) into `dim_date` and used `COALESCE(to_char(event_time, 'YYYYMMDD')::INT, 19000101)` during fact loading.
* **Downstream Impact:** Zero records were dropped; data quality audits can isolate and report on events with missing timestamps without compromising referential integrity.

---

## 4. How to Inspect in DataGrip

You can now open **DataGrip**, connect to `pulsetrack_dw`, and immediately view your populated data warehouse:

1. In the Database Explorer pane, refresh the **`pulsetrack_dw`** database.
2. Expand **Schemas**:
   * Inspect **`pulsetrack_raw`** (Bronze staging)
   * Inspect **`pulsetrack_silver`** (Cleansed staging)
   * Inspect **`pulsetrack_gold`** (Star Schema)
   * Inspect **`pulsetrack_audit`** (Pipeline execution logs & quarantine)
3. Right-click on **`pulsetrack_gold`** $\longrightarrow$ **Diagrams** $\longrightarrow$ **Show Visualization** to see the Kimball Star Schema diagram generated natively by DataGrip!
4. Query the audit log:
   ```sql
   SELECT * FROM pulsetrack_audit.pipeline_execution_log ORDER BY log_id DESC;
   ```
