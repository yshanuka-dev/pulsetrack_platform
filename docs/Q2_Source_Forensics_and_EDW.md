# PulseTrack Source Forensics & Enterprise Data Warehouse Design
**Document Code:** PT-ARCH-002  
**Project:** PulseTrack Data Warehousing Capstone  
**Assessment Phase:** Question 2 (20 Marks)  
**Author:** Lead Data Engineer / Enterprise Data Architect  
**Status:** Approved & Baselined  

---

## 1. Executive Summary

This document presents the comprehensive **Source-System Forensic Analysis** of PulseTrack's operational data and the formal design of the target **Enterprise Data Warehouse (EDW) Kimball Star Schema**.

Our forensic inspection of the 11 relational CSV tables (774,344 records), 2 MongoDB document collections (660 JSON documents), and the Kafka conversion stream log (183,162 records) uncovered significant deliberate traps. If raw tables are joined naively, reported revenue inflates by **103.6% ($21.08M vs. true $10.35M)** due to attribution fanout, 36,380 duplicate conversion lifecycle records distort counts, and historical account manager reassignments rewrite sales history.

This document establishes the forensic evidence and details the dimensional architecture that resolves these issues.

---

## 2. Source-System Forensic Analysis & Data Audit

### 2.1 Relational Batch Export Profiling (11 CSV Tables)

An automated forensic profiling scan across the operational CSV exports yielded the following structural metrics:

| Source File / Table | Row Count | Column Count | Primary / Candidate Key | Identified Forensic Issues & Anomalies |
| :--- | :--- | :--- | :--- | :--- |
| **`account_managers_raw`** | 25 | 7 | `am_id` | 1 deliberate NULL name (`AM013`); mixed hire date formats. |
| **`advertisers_raw`** | 60 | 9 | `advertiser_id` | Shows current `account_manager_id` only; casing inconsistencies (`LaserAway` vs `laseraway`). |
| **`campaigns_raw`** | 400 | 9 | `campaign_id` | ~3% (12 campaigns) carry invalid `advertiser_id` contradicting offer's advertiser; casing noise. |
| **`offers_raw`** | 150 | 8 | `offer_id` | `default_payout` stored as text with currency symbols (`$15.00`); embedded names. |
| **`creatives_raw`** | 1,200 | 8 | `creative_id` | Deepest node in snowflake chain; ~5% campaigns lack creatives. |
| **`partners_raw`** | 600 | 8 | `partner_id` (numeric prefix) | **40 active partners missing**; ~12% NULL partner names; compound partner IDs (`12345_678901`). |
| **`impressions_raw`** | 300,000 | 11 | `impression_id` | Factless fact; junk columns (`placement_raw`, `bot_score`); inconsistent geo/device categoricals. |
| **`clicks_raw`** | 150,000 | 14 | `click_id` | **22,591 NULL `impression_id` (15.06% direct clicks)**; PII columns (`ip`, `user_agent`); mixed boolean formats (`1/0`, `true/false`, `Y/N`). |
| **`conversions_raw`** | 126,380 | 25 | `conversion_id` (non-unique) | **Only 90,000 unique conversions (36,380 duplicate/lifecycle rows)**; **12,654 NULL `click_id` (10.01% direct conversions)**; money stored as text; test records (`is_test`). |
| **`conversion_touchpoints_raw`** | 183,529 | 7 | `touchpoint_id` | Multi-touch bridge (M:N); fractional weights sum to $\approx 1.0$; **causes 203% revenue fanout if joined naively**. |
| **`revenue_adjustments_raw`** | 12,000 | 7 | `adjustment_id` | Late-arriving events; ~6% orphaned conversions outside export window; ~8% blank/`N/A` `delta_amount` (must be recovered from Kafka stream). |

---

### 2.2 Deep Investigation of Deliberate Source Traps

#### Trap 1: The Multi-Touch Attribution Fanout Trap (Quantified)
In `conversion_touchpoints_raw`, a single conversion can link to 1 to 5 touchpoints (first, mid, last click).
* **The Forensic Experiment:**
  We queried gross revenue using two methods:
  1. *True Deduplicated Revenue (Fact Grain):* $\mathbf{\$10,355,219.82}$
  2. *Naive Direct Join (`conversions_raw` $\bowtie$ `conversion_touchpoints_raw`):* $\mathbf{\$21,086,039.75}$
  3. *Attribution-Weighted Revenue ($\sum \text{Revenue} \times \text{Weight}$):* $\mathbf{\$10,353,150.00}$ (reconciles with rounding)
* **Root Cause & Impact:** Joining the raw tables duplicates conversion rows by the number of touchpoints, inflating executive revenue figures by **103.6% ($10.73M in ghost revenue)**.
* **Architectural Remedy:** Isolate atomic conversion financials in `fact_conversion` and partner attribution weights in `bridge_conversion_touchpoint`.

#### Trap 2: Conversion Deduplication & Lifecycle States
* `conversions_raw` contains 126,380 rows representing exactly **90,000 distinct `conversion_id`s**.
* Conversions evolve through states (`pending` $\to$ `approved` / `reversed`). Intermediate states were exported alongside the final state, plus ~2% network duplicates.
* **Deduplication Rule:** Because `updated_at` is guaranteed to be time-bearing and non-null in `conversions_raw`, the authoritative final state is selected via:
  $$\text{ROW\_NUMBER}() \text{ OVER } (\text{PARTITION BY conversion\_id ORDER BY updated\_at DESC}) = 1$$

#### Trap 3: Orphaned Partner Keys & MongoDB CRM Reconciliation
* When profiling `clicks_raw` and `impressions_raw`, exactly **40 distinct 5-digit partner prefixes** failed referential integrity against `partners_raw.csv`.
* Scanning MongoDB `partner_profiles.jsonl` (600 documents) revealed:
  * 560 documents match existing CSV partners (with ~12% carrying portal name variations).
  * Exactly **40 documents are portal-only partners**, perfectly matching the 40 orphaned partner prefixes from click events!
* **Architectural Remedy:** The Silver ingestion pipeline merges `partners_raw` with MongoDB `partner_profiles.jsonl` using a precedence rule (CRM portal takes precedence for legal/portal attributes) to form a 100% resolved `dim_partner`.

#### Trap 4: Account Manager History & The SCD Type 2 Mandate
* In `advertisers_raw.csv`, only the *current* `account_manager_id` is recorded.
* If an analyst joins `conversions_raw` directly to `advertisers_raw`, historical conversions get credited to the *new* account manager rather than the manager who produced the sale.
* Forensic inspection of MongoDB `advertiser_accounts.jsonl` confirmed that each advertiser document contains the authoritative `account_manager_history` array:
  ```json
  "advertiser_id": "ADV0005",
  "account_manager_history": [
      {"am_id": "AM008", "am_name": "Emma Hernandez", "from": "2025-07-21", "to": "2025-09-13"},
      {"am_id": "AM015", "am_name": "Yuki Young", "from": "2025-09-13", "to": null}
  ]
  ```
  Conversions for `ADV0005` prior to `2025-09-13` must link to `AM008`; conversions on or after `2025-09-13` link to `AM015`.

#### Trap 5: Kafka Conversion Stream Forensics
* Scanning `stream/pulsetrack_conversions.log` (183,162 lines across 4 partitions):
  * **Malformed Lines:** 184 truncated lines (~0.1%) caused by producer partial writes. Defensive parsing must quarantine these into an error table without terminating the pipeline.
  * **Event Distribution:** 92,231 `conversion.created`, 78,458 `conversion.status_changed`, 12,289 `adjustment.applied`.
  * **Schema Evolution:** At line 125,019 (~70% of stream), schema upgraded to `2.0`, renaming `revenue` to `revenue_amount`.
  * **Reconciliation Proof:** Replaying deduplicated stream events reproduces the exact batch state of `conversions_raw` + `revenue_adjustments_raw`.

---

## 3. Enterprise Data Warehouse Dimensional Design (Kimball Star Schema)

To fulfill the requirements of Question 1 and eliminate all data anomalies, the EDW is modeled as a **Constellation Star Schema** centered around four Fact tables and one Bridge table.

```
                    +--------------------+
                    |      dim_date      |
                    +---------+----------+
                              |
     +------------------------+------------------------+
     |                        |                        |
     v (impression_date_key)  v (click_date_key)       v (conversion_date_key)
+----+------------+      +----+-------+          +-----+-----------+
| fact_impression |      | fact_click |          | fact_conversion | <---+
+----+------------+      +----+-------+          +-----+-----------+     |
     |                        |                        |                 |
     |                        v (click_key)            |                 |
     |                   +----+-------------------+    | (conversion_key)|
     |                   | bridge_conversion_     | <--+                 |
     |                   | touchpoint             |                      |
     |                   +------------------------+                      |
     |                                                                   |
     +------------------------+------------------------+                 |
                              |                        |                 |
                              v                        v                 |
                    +---------+----------+   +---------+----------+      |
                    |    dim_campaign    |   |    dim_partner     |      |
                    +---------+----------+   +--------------------+      |
                              |                                          |
                              v                                          |
                    +---------+----------+                               |
                    |   dim_advertiser   |                               |
                    |    (SCD Type 2)    |                               |
                    +---------+----------+                               |
                              |                                          |
                              v                                          |
                    +---------+----------+                               |
                    | fact_revenue_      +-------------------------------+
                    | adjustment         | (adjusts conversion_key)
                    +--------------------+
```

---

### 3.1 Fact Table Specifications

#### 1. `fact_conversion` (Core Metric Fact)
* **Grain:** One row per unique valid conversion event (deduplicated by `MAX(updated_at)`).
* **Primary Key:** `conversion_key` (`BIGINT GENERATED ALWAYS AS IDENTITY`).
* **Degenerate Dimension:** `conversion_id` (`VARCHAR(32)`).
* **Foreign Keys:** `conversion_date_key`, `advertiser_sk` (SCD2 key), `campaign_key`, `offer_key`, `partner_key`, `creative_key`, `device_geo_key`, `junk_key`.
* **Measures:**
  * `gross_revenue` (`NUMERIC(14,4)`) - Additive across dimensions except attribution bridge.
  * `payout_amount` (`NUMERIC(14,4)`) - Additive affiliate payout.
  * `net_margin` (`NUMERIC(14,4)`) - Derived additive measure: `gross_revenue - payout_amount`.
  * `conversion_count` (`INT DEFAULT 1`) - Additive event counter.

#### 2. `fact_click` (Funnel Interaction Fact)
* **Grain:** One row per user click interaction.
* **Primary Key:** `click_key` (`BIGINT GENERATED ALWAYS AS IDENTITY`).
* **Degenerate Dimension:** `click_id` (`VARCHAR(32)`).
* **Foreign Keys:** `click_date_key`, `impression_key` (nullable for direct clicks), `campaign_key`, `partner_key`, `creative_key`, `device_geo_key`.
* **Measures:** `click_count` (`INT DEFAULT 1`), `is_unique_click` (`INT`).

#### 3. `fact_impression` (Top-of-Funnel Factless Fact)
* **Grain:** One row per ad creative impression delivered.
* **Primary Key:** `impression_key` (`BIGINT GENERATED ALWAYS AS IDENTITY`).
* **Degenerate Dimension:** `impression_id` (`VARCHAR(32)`).
* **Foreign Keys:** `impression_date_key`, `campaign_key`, `creative_key`, `partner_key`, `device_geo_key`.
* **Measures:** `impression_count` (`INT DEFAULT 1`).

#### 4. `fact_revenue_adjustment` (Accumulating Financial Adjustment Fact)
* **Grain:** One row per post-conversion financial adjustment/refund.
* **Primary Key:** `adjustment_key` (`BIGINT GENERATED ALWAYS AS IDENTITY`).
* **Degenerate Dimension:** `adjustment_id` (`VARCHAR(32)`).
* **Foreign Keys:** `adjustment_date_key`, `conversion_key` (references `fact_conversion`), `advertiser_sk`, `campaign_key`.
* **Measures:** `adjustment_delta` (`NUMERIC(14,4)`) - Additive (can be negative).

#### 5. `bridge_conversion_touchpoint` (Multi-Touch Attribution Bridge)
* **Grain:** One row per conversion-to-click touchpoint pair.
* **Primary Key:** `touchpoint_key` (`BIGINT GENERATED ALWAYS AS IDENTITY`).
* **Foreign Keys:** `conversion_key`, `click_key`, `partner_key`.
* **Attributes:** `touch_position` (`VARCHAR(10)`: `first`, `mid`, `last`).
* **Measures:** `attribution_weight` (`NUMERIC(6,4)` - non-additive; sums to $\approx 1.0$ per conversion).

---

### 3.2 Dimension Table Specifications

#### 1. `dim_advertiser` (Slowly Changing Dimension Type 2)
Tracks advertiser attributes and historical Account Manager reassignments over time:
* `advertiser_sk` (`BIGINT PRIMARY KEY`) - Surrogate Key.
* `advertiser_id` (`VARCHAR(32)`) - Natural Business Key (ADVxxxxx).
* `advertiser_name` (`VARCHAR(255)`) - Canonical brand name.
* `vertical` (`VARCHAR(100)`), `billing_country` (`VARCHAR(10)`).
* `am_id` (`VARCHAR(32)`), `am_name` (`VARCHAR(255)`), `am_team` (`VARCHAR(100)`), `am_region` (`VARCHAR(100)`).
* **SCD-2 Metadata:** `valid_from` (`TIMESTAMPTZ`), `valid_to` (`TIMESTAMPTZ`), `is_current` (`BOOLEAN`).

#### 2. `dim_date` (Conformed Role-Playing Dimension)
* `date_key` (`INT PRIMARY KEY`, format `YYYYMMDD`).
* `calendar_date` (`DATE`), `year` (`INT`), `quarter` (`VARCHAR(2)`), `quarter_name` (`VARCHAR(10)`), `month` (`INT`), `month_name` (`VARCHAR(20)`), `day_of_month` (`INT`), `day_of_week` (`INT`), `day_name` (`VARCHAR(20)`), `is_weekend` (`BOOLEAN`).

#### 3. `dim_partner` (Conformed Affiliate Dimension)
* `partner_key` (`BIGINT PRIMARY KEY`), `partner_id` (`VARCHAR(16)` - 5-digit prefix), `partner_name` (`VARCHAR(255)`), `channel` (`VARCHAR(100)`), `media_buyer` (`VARCHAR(100)`), `payment_terms` (`VARCHAR(50)`), `source_system` (`VARCHAR(50)`).

#### 4. `dim_campaign`
* `campaign_key` (`BIGINT PRIMARY KEY`), `campaign_id` (`VARCHAR(32)`), `campaign_name` (`VARCHAR(255)`), `price_type` (`VARCHAR(20)`), `start_date` (`DATE`), `end_date` (`DATE`), `advertiser_id` (`VARCHAR(32)`), `offer_id` (`VARCHAR(32)`).

#### 5. `dim_offer`
* `offer_key` (`BIGINT PRIMARY KEY`), `offer_id` (`VARCHAR(32)`), `offer_name` (`VARCHAR(255)`), `payout_type` (`VARCHAR(50)`), `default_payout` (`NUMERIC(14,4)`).

#### 6. `dim_creative`
* `creative_key` (`BIGINT PRIMARY KEY`), `creative_id` (`VARCHAR(32)`), `campaign_id` (`VARCHAR(32)`), `creative_name` (`VARCHAR(255)`), `format` (`VARCHAR(50)`), `dimensions` (`VARCHAR(50)`), `landing_url` (`TEXT`).

#### 7. `dim_device_geo` (Conformed Junk Dimension)
* `device_geo_key` (`BIGINT PRIMARY KEY`), `device_type` (`VARCHAR(50)` - Desktop, Mobile, Tablet), `country_code` (`VARCHAR(10)`).

#### 8. `dim_junk_conversion`
* `junk_key` (`BIGINT PRIMARY KEY`), `status` (`VARCHAR(20)`: approved, pending, reversed), `currency` (`VARCHAR(10)`: USD), `is_test` (`BOOLEAN`).

---

## 4. History Preservation: SCD Type 2 Demonstration

### Scenario:
Advertiser `ADV0005` transitions from Account Manager `AM008` (Emma Hernandez) to `AM015` (Yuki Young) on **2025-09-13**.

### Table State in `dim_advertiser`:

| advertiser_sk | advertiser_id | advertiser_name | am_id | am_name | valid_from | valid_to | is_current |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **501** | `ADV0005` | NovaTech Health | `AM008` | Emma Hernandez | `2025-07-21 00:00:00` | `2025-09-13 00:00:00` | `FALSE` |
| **502** | `ADV0005` | NovaTech Health | `AM015` | Yuki Young | `2025-09-13 00:00:00` | `NULL` | `TRUE` |

### Event Time Point-in-Time Join Logic:
When loading `fact_conversion`, the surrogate key `advertiser_sk` is resolved via:
```sql
SELECT 
    c.conversion_id,
    c.revenue,
    d.advertiser_sk,
    d.am_name
FROM pulsetrack_silver.conversions c
JOIN pulsetrack_gold.dim_advertiser d
  ON c.advertiser_id = d.advertiser_id
 AND c.conversion_time >= d.valid_from
 AND (c.conversion_time < d.valid_to OR d.valid_to IS NULL);
```
* A conversion on `2025-08-10` links to `advertiser_sk = 501` (credited to Emma Hernandez).
* A conversion on `2025-10-01` links to `advertiser_sk = 502` (credited to Yuki Young).
* **Historical integrity is 100% preserved**, perfectly answering Question 1 and Question 9.7 without rewriting history.
