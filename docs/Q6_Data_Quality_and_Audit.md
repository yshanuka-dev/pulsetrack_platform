# PulseTrack Data Quality, Reconciliation & Audit Framework
**Document Code:** PT-GOV-006  
**Project:** PulseTrack Data Warehousing Capstone  
**Assessment Phase:** Question 6 (10 Marks)  
**Author:** Lead Data Engineer / Enterprise Data Architect  
**Status:** Executed & Verified in PostgreSQL  

---

## 1. Executive Summary

This deliverable establishes the formal **Data Quality, Reconciliation, and Operational Audit Framework** that transforms the PulseTrack Enterprise Data Warehouse into a trusted analytical platform. 

Every record transitioning through the Medallion layers (**Source $\longrightarrow$ Bronze $\longrightarrow$ Silver $\longrightarrow$ Gold**) is validated against strict quality gates covering schema consistency, domain boundaries, referential integrity across 10 business entities, multi-touch attribution weight constraints, and quarantine tracking. All assertions passed with a **100% success rate**.

---

## 2. Automated Data Quality Gate Verification

All quality assertions were executed programmatically against live tables in `pulsetrack_dw` via `src/data_quality.py`.

```
===================================================================================================================
                                      DATA QUALITY GATES VERIFICATION LEDGER
===================================================================================================================
```

| Quality Dimension / Check | Target / Requirement | Observed Result in Gold | Status |
| :--- | :--- | :---: | :---: |
| **Uniqueness: `dim_date.date_key`** | 1,462 unique calendar dates | **0 duplicates** | **PASS** |
| **Uniqueness: `dim_advertiser.advertiser_sk`** | 74 SCD-2 version rows | **0 duplicates** | **PASS** |
| **Uniqueness: `dim_partner.partner_key`** | 640 unique partners | **0 duplicates** | **PASS** |
| **Uniqueness: `dim_campaign.campaign_key`** | 400 marketing campaigns | **0 duplicates** | **PASS** |
| **Uniqueness: `dim_offer.offer_key`** | 150 promoted offers | **0 duplicates** | **PASS** |
| **Uniqueness: `dim_creative.creative_key`** | 1,200 ad assets | **0 duplicates** | **PASS** |
| **Uniqueness: `dim_device_geo.device_geo_key`** | 40 discrete device $\times$ geo pairs | **0 duplicates** | **PASS** |
| **Uniqueness: `dim_junk_conversion.junk_key`**| 3 conversion states $\times$ USD | **0 duplicates** | **PASS** |
| **Uniqueness: `fact_conversion.conversion_key`**| 86,335 deduplicated transactions | **0 duplicates** | **PASS** |
| **Uniqueness: `fact_click.click_key`** | 150,000 ad clicks | **0 duplicates** | **PASS** |
| **Uniqueness: `fact_impression.impression_key`**| 300,000 ad impressions | **0 duplicates** | **PASS** |
| **Uniqueness: `fact_revenue_adjustment.adj_key`**| 12,000 late adjustments | **0 duplicates** | **PASS** |
| **Uniqueness: `bridge_touchpoint.touchpoint_key`**| 176,009 attribution links | **0 duplicates** | **PASS** |
| **Referential: `fact_conversion -> dim_date`** | 100% valid date keys | **0 orphans** | **PASS** |
| **Referential: `fact_conversion -> dim_advertiser`** | 100% valid SCD-2 keys at event time | **0 orphans** | **PASS** |
| **Referential: `fact_conversion -> dim_campaign`** | 100% valid campaigns | **0 orphans** | **PASS** |
| **Referential: `fact_conversion -> dim_partner`** | 100% valid partners (inc. 40 resolved)| **0 orphans** | **PASS** |
| **Referential: `fact_click -> dim_date`** | 100% valid click date keys | **0 orphans** | **PASS** |
| **Referential: `fact_click -> dim_campaign`** | 100% valid campaigns | **0 orphans** | **PASS** |
| **Referential: `fact_impression -> dim_date`** | 100% valid impression date keys | **0 orphans** | **PASS** |
| **Referential: `fact_adjustment -> fact_conversion`**| Adjustments link to conversions | **0 orphans** | **PASS** |
| **Referential: `bridge_touchpoint -> fact_conversion`**| Touchpoints link to conversions | **0 orphans** | **PASS** |
| **Domain: Conversion Status Categoricals** | Only `approved`, `pending`, `reversed` | **0 invalid** | **PASS** |
| **Domain: Standardized Device Types** | Only `desktop`, `mobile`, `tablet`, `other` | **0 invalid** | **PASS** |
| **Financial: Negative Revenue Anomalies** | ~3% expected per Data Guide §9 | **2,439 tracked (2.83%)** | **PASS** |
| **Attribution: Touchpoint Weights Sum** | $\sum w \approx 1.0$ per conversion | **0 violations** | **PASS** |
| **Stream Quarantine: Broken Lines** | Exactly 184 truncated lines | **184 quarantined** | **PASS** |

---

## 3. Cross-Layer Mathematical Reconciliation Ledger

The following ledger establishes the complete, unbroken mathematical accounting of all records as they flow from the operational source systems through Bronze, Silver, and into Gold. 

This ledger is permanently recorded in PostgreSQL: `pulsetrack_audit.cross_layer_reconciliation_ledger`.

| Entity | Source Raw | Bronze Staged | Silver Cleansed | Gold Loaded | Rejected / Quarantine | Duplicate / Lifecycle Snapshot | Reconciliation Status |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: | :--- |
| **Conversions** | 126,380 | 126,380 | 86,335 | 86,335 | 3,665 (test records) | 36,380 (snapshots/retries) | **RECONCILED** |
| **Touchpoints** | 183,529 | 183,529 | 183,529 | 176,009 | 7,520 (orphaned clicks) | 0 | **RECONCILED** |
| **Clicks** | 150,000 | 150,000 | 150,000 | 150,000 | 0 | 0 | **RECONCILED** |
| **Impressions** | 300,000 | 300,000 | 300,000 | 300,000 | 0 | 0 | **RECONCILED** |
| **Adjustments** | 12,000 | 12,000 | 12,000 | 12,000 | 0 | 0 | **RECONCILED** |
| **Partners** | 640 | 640 | 640 | 640 | 0 | 0 | **RECONCILED (40 Resolved)**|
| **Advertisers** | 60 | 60 | 60 | 74 | 0 | 0 | **RECONCILED (SCD-2 Split)**|
| **Campaigns** | 400 | 400 | 400 | 400 | 0 | 0 | **RECONCILED (12 Healed)** |
| **Creatives** | 1,200 | 1,200 | 1,200 | 1,200 | 0 | 0 | **RECONCILED** |
| **Offers** | 150 | 150 | 150 | 150 | 0 | 0 | **RECONCILED** |
| **Kafka Stream**| 183,162 | 182,978 | 182,978 | 182,978 | 184 (truncated lines)| 4,579 (re-emitted events) | **RECONCILED** |

---

## 4. Operational Audit Mechanism

PulseTrack implements an automated, centralized operational audit ledger in `pulsetrack_audit.pipeline_execution_log`. Every pipeline run generates an immutable audit record tracking:
* `batch_id`: Unique execution identifier (e.g., `BATCH_GOLD_20261118_073337`)
* `pipeline_name`: Ingestion, Cleansing, Dimensional Loader, or Audit Suite
* `layer`: Target Medallion layer (`Bronze`, `Silver`, `Gold`, `Mart`, `Audit`)
* `source_row_count`: Input records read
* `inserted_count`: Successfully written records
* `updated_count`: Existing records modified
* `rejected_count`: Quarantined or filtered anomaly rows
* `status`: `SUCCESS` or `FAILED`
* `start_time` / `end_time`: Microsecond-accurate UTC run interval
* `error_message`: Stack trace or exception message (populated upon failure)

### Live Query in DataGrip:
```sql
SELECT 
    log_id,
    batch_id,
    pipeline_name,
    layer,
    source_row_count,
    inserted_count,
    rejected_count,
    status,
    ROUND(EXTRACT(EPOCH FROM (end_time - start_time))::NUMERIC, 2) AS duration_seconds
FROM pulsetrack_audit.pipeline_execution_log
ORDER BY log_id DESC;
```
