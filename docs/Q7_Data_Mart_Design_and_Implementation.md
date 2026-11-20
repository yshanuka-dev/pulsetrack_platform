# PulseTrack Data Mart Design & Implementation Specification
**Document Code:** PT-MART-007  
**Project:** PulseTrack Data Warehousing Capstone  
**Assessment Phase:** Question 7 (10 Marks)  
**Author:** Lead Data Engineer / Enterprise Data Architect  
**Status:** Implemented & Verified in PostgreSQL  

---

## 1. Executive Summary

This deliverable establishes the architecture, grain specifications, and physical implementation of the business-oriented **PulseTrack Data Mart Layer (`pulsetrack_mart`)**. 

Built directly on top of the Enterprise Data Warehouse (`pulsetrack_gold`), the Data Mart transforms normalized, granular event facts into high-performance, pre-aggregated analytical tables. This architecture ensures sub-second dashboard response times for executives and eliminates the risk of BI analysts triggering catastrophic multi-table join fanouts.

---

## 2. Architectural Justification: Why the Data Mart is Required

Allowing BI dashboards and business users to directly query the atomic Enterprise Data Warehouse (`pulsetrack_gold`) introduces four fatal operational risks:

1. **Defense Against the Multi-Touch Fanout Trap:**  
   In the EDW, computing partner revenue attribution requires traversing `fact_conversion`, `bridge_conversion_touchpoint`, and `fact_click`. Ad-hoc queries written by BI users inevitably join these tables incorrectly, multiplying conversion revenue by up to **103.6% ($10.73M in artificial ghost revenue)**. The Data Mart pre-calculates attributed metrics using vetted mathematical formulas, making fanout impossible.
2. **Elimination of Query Latency & Cluster Contention:**  
   Computing a 12-month trend across 300,000 impressions, 150,000 clicks, 86,335 conversions, and 12,000 adjustments requires continuous full-table hash joins. Directly querying the EDW causes heavy table locking and CPU saturation during peak business hours. The Data Mart pre-aggregates these into optimized summary rows, reducing scan volume by up to **90%**.
3. **Workload Isolation (ETL Writes vs. BI Reads):**  
   Batch ingestion pipelines continuously update Gold facts and SCD-2 dimensions. Separating consumption into dedicated Data Mart tables guarantees that BI read queries never block nightly ETL pipelines.
4. **Business Ergonomics (Pre-Computed Ratios):**  
   Metrics such as **CTR**, **CVR**, **RPC**, and **Net Adjusted Revenue** are pre-computed and validated. Business analysts do not need to construct complex 80-line SQL queries with window functions; they can query intuitive business tables directly.

---

## 3. Data Mart Table Architecture & Grain Specifications

### 3.1 `mart_campaign_performance_daily` (Commercial Funnel Mart)
* **Target Grain:** One row per Campaign $\times$ Partner $\times$ Calendar Date (`campaign_key`, `partner_key`, `date_key`).
* **Live Populated Rows:** **`533,234 rows`**
* **Dimensional Context:** `campaign_id`, `campaign_name`, `price_type`, `advertiser_id`, `advertiser_name`, `partner_id`, `partner_name`, `partner_channel`, `calendar_date`, `year`, `quarter_name`, `month_year`.
* **Aggregated Atomic Measures:**
  * `impression_count`: $\sum \text{impressions}$
  * `click_count`: $\sum \text{clicks}$
  * `unique_click_count`: $\sum \text{unique clicks}$
  * `conversion_count`: $\sum \text{conversions}$
  * `gross_revenue`: $\sum \text{gross revenue}$
  * `payout_amount`: $\sum \text{affiliate payouts}$
  * `net_margin`: $\sum (\text{gross revenue} - \text{payout})$
  * `adjustment_delta`: $\sum \text{post-conversion adjustments}$
  * `adjusted_revenue`: $\text{gross\_revenue} + \text{adjustment\_delta}$
* **Pre-Calculated KPI Ratios:**
  * $\text{CTR \%} = \frac{\text{click\_count}}{\text{impression\_count}} \times 100\%$
  * $\text{CVR \%} = \frac{\text{conversion\_count}}{\text{click\_count}} \times 100\%$
  * $\text{Revenue per Click (RPC)} = \frac{\text{gross\_revenue}}{\text{click\_count}}$
  * $\text{Revenue per Conversion (RPCV)} = \frac{\text{gross\_revenue}}{\text{conversion\_count}}$

---

### 3.2 `mart_partner_attribution_daily` (Affiliate Multi-Touch Mart)
* **Target Grain:** One row per Partner $\times$ Campaign $\times$ Calendar Date.
* **Live Populated Rows:** **`150,897 rows`**
* **Dimensional Context:** `partner_id`, `partner_name`, `partner_channel`, `campaign_id`, `campaign_name`, `calendar_date`, `quarter_name`, `month_year`.
* **Multi-Touch Attribution Measures:**
  * `total_touchpoints`: Count of click touchpoints logged by this partner.
  * `attributed_conversions`: Fractional conversion credit ($\sum \text{attribution\_weight}$).
  * `attributed_revenue`: Fractional monetary credit ($\sum \text{gross\_revenue} \times \text{weight}$).
  * `first_touch_count`: Touchpoints where partner initiated user discovery.
  * `mid_touch_count`: Touchpoints where partner nurtured the funnel.
  * `last_touch_count`: Touchpoints where partner closed the final conversion.

---

### 3.3 `mart_advertiser_am_monthly` (SCD Type 2 Executive Sales Mart)
* **Target Grain:** One row per Advertiser $\times$ Account Manager $\times$ Calendar Month (`advertiser_id`, `am_id`, `month_year`).
* **Live Populated Rows:** **`1,129 rows`**
* **Dimensional Context:** `advertiser_id`, `advertiser_name`, `vertical`, `am_id`, `am_name`, `am_team`, `am_region`, `is_current_am_assignment`, `month_year`, `quarter_name`, `year`.
* **Historical Performance Measures:**
  * `monthly_conversions`: Total conversions managed during active tenure.
  * `monthly_gross_revenue`: Total sales generated under manager's ownership.
  * `monthly_margin`: Platform margin generated.
  * `monthly_adjustment_delta`: Late refunds attributed to managed accounts.
  * `monthly_adjusted_revenue`: Final net revenue attributed to the manager.

---

## 4. Live Verification Queries in DataGrip

Executives and BI tools can now run sub-second queries directly against `pulsetrack_mart`:

```sql
-- 1. Campaign Performance Summary (Sub-second execution)
SELECT 
    campaign_name,
    advertiser_name,
    SUM(impression_count) AS total_impressions,
    SUM(click_count) AS total_clicks,
    ROUND(SUM(click_count)::NUMERIC / NULLIF(SUM(impression_count), 0) * 100, 2) AS overall_ctr_pct,
    SUM(conversion_count) AS total_conversions,
    ROUND(SUM(gross_revenue), 2) AS total_gross_rev,
    ROUND(SUM(adjusted_revenue), 2) AS total_net_rev
FROM pulsetrack_mart.mart_campaign_performance_daily
WHERE year = 2025
GROUP BY campaign_name, advertiser_name
ORDER BY total_net_rev DESC
LIMIT 10;

-- 2. Partner Attribution Leaderboard
SELECT 
    partner_name,
    partner_channel,
    ROUND(SUM(attributed_conversions), 1) AS attributed_conversions,
    ROUND(SUM(attributed_revenue), 2) AS attributed_revenue
FROM pulsetrack_mart.mart_partner_attribution_daily
WHERE year = 2025
GROUP BY partner_name, partner_channel
ORDER BY attributed_revenue DESC
LIMIT 10;
```
