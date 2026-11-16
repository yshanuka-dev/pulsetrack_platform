# PulseTrack Analytical Requirements & KPI Specification
**Document Code:** PT-SPEC-001  
**Project:** PulseTrack Data Warehousing Capstone  
**Assessment Phase:** Question 1 (15 Marks)  
**Author:** Lead Data Engineer / Enterprise Data Architect  
**Status:** Approved & Baselined  

---

## 1. Executive Summary & Business Context

PulseTrack is a high-throughput digital performance-marketing platform connecting **Advertisers** (clients funding campaigns), **Creatives** (ad banners/assets), **Marketing Partners / Affiliates** (publishers driving traffic), **Internal Account Managers** (managing client relationships), and **End-Users** (generating funnel activity).

Management has commissioned the design and implementation of an Enterprise Data Warehouse (EDW) and OLAP Semantic Layer. This specification establishes the business metrics, mathematical formulas, dimensional grain, and data freshness requirements that serve as the contract for all subsequent data platform engineering phases.

---

## 2. Business Processes Represented

The performance-marketing lifecycle at PulseTrack comprises six distinct business processes across the operational funnel:

```
+-------------------+      +-------------------+      +---------------------+
| 1. Ad Impression  | ---> |   2. Ad Click     | ---> |  3. Ad Conversion   |
| (Top of Funnel)   |      | (Middle of Funnel)|      |  (Bottom of Funnel) |
+-------------------+      +-------------------+      +---------------------+
                                                                 |
                                                                 v
+-------------------+      +-------------------+      +---------------------+
| 6. Account Mgmt   | <--- | 5. Partner Attrib | <--- | 4. Revenue Adjust   |
| (SCD-2 Alignment) |      | (Multi-Touch M:N) |      | (Post-Event Delta)  |
+-------------------+      +-------------------+      +---------------------+
```

1. **Ad Impression Delivery (Top of Funnel):** Delivery and viewing of an ad creative by an end-user on a partner platform. Measures reach and exposure. Factless at the atomic event level.
2. **Ad Click Engagement (Middle of Funnel):** Explicit interaction where a user clicks an impression or lands directly via a partner tracking link.
3. **Conversion Transaction (Bottom of Funnel):** Successful target action (e-commerce purchase, subscription, lead generation) that generates gross revenue for the advertiser and triggers an affiliate payout.
4. **Financial Revenue Adjustment (Post-Conversion Reconciliation):** Retroactive monetary edits (refunds, chargebacks, fraud clawbacks, bonus tiers) applied days after conversion.
5. **Multi-Touch Partner Attribution (Channel Credit Distribution):** Allocation of conversion credit across multiple partner touchpoints based on interaction sequence and weighting models.
6. **Account Management & Client Servicing:** Internal operational assignment of PulseTrack account managers to advertisers, tracking performance and portfolio growth across time.

---

## 3. Formal KPI & Measure Definitions

Measures must be strictly classified by their mathematical additivity (Additive, Semi-Additive, Non-Additive) to prevent fanout errors and invalid aggregations in BI tools.

### 3.1 Base Atomic Measures

| Measure Name | Description | Data Type | Additivity | Source Entity |
| :--- | :--- | :--- | :--- | :--- |
| **`impression_count`** | Count of ad impressions delivered | `BIGINT` | Additive across all dims | `impressions_raw` |
| **`click_count`** | Count of user click events | `BIGINT` | Additive across all dims | `clicks_raw` |
| **`conversion_count`** | Count of unique approved/valid conversions | `BIGINT` | Additive across all dims | `conversions_raw` |
| **`gross_revenue`** | Baseline monetary amount earned at conversion | `NUMERIC(14,4)` | Additive across dims (except multi-touch joins) | `conversions_raw` |
| **`payout_amount`** | Commission paid to affiliate partner | `NUMERIC(14,4)` | Additive across dims | `conversions_raw` |
| **`adjustment_delta`** | Post-conversion adjustment (positive/negative) | `NUMERIC(14,4)` | Additive across dims | `revenue_adjustments_raw` |
| **`touchpoint_weight`** | Fractional attribution weight assigned to a click ($0 \le w \le 1$) | `NUMERIC(6,4)` | Non-Additive ($\sum w \approx 1.0$ per conversion) | `conversion_touchpoints_raw` |

---

### 3.2 Derived Performance KPIs & Mathematical Formulas

#### A. Advertiser Performance KPIs
* **Click-Through Rate (CTR):**
  $$\text{CTR} = \frac{\sum \text{click\_count}}{\sum \text{impression\_count}} \times 100\%$$
* **Conversion Rate (CVR):**
  $$\text{CVR} = \frac{\sum \text{conversion\_count}}{\sum \text{click\_count}} \times 100\%$$
* **Gross Revenue:**
  $$\text{Gross Revenue} = \sum \text{gross\_revenue}$$
* **Revenue per Click (RPC):**
  $$\text{RPC} = \frac{\sum \text{gross\_revenue}}{\sum \text{click\_count}}$$
* **Revenue per Conversion (Average Order Value / RPCV):**
  $$\text{RPCV} = \frac{\sum \text{gross\_revenue}}{\sum \text{conversion\_count}}$$

#### B. Campaign Performance KPIs
* **Net Adjusted Revenue:**
  $$\text{Adjusted Revenue} = \sum \text{gross\_revenue} + \sum \text{adjustment\_delta}$$
* **Campaign Margin:**
  $$\text{Campaign Margin} = \text{Adjusted Revenue} - \sum \text{payout\_amount}$$
* **Campaign Ranking:** Dense ranking of campaigns by Net Adjusted Revenue within a given time window:
  $$\text{Campaign Rank} = \text{DENSE\_RANK}() \text{ OVER } (\text{PARTITION BY date\_trunc}('month', \text{date}) \text{ ORDER BY Adjusted Revenue DESC})$$

#### C. Creative Performance KPIs
* **Creative CTR & CVR:** CTR and CVR calculated at the granular `creative_id` level to evaluate visual ad engagement and conversion efficiency.
* **Creative Underperformance Delta:**
  $$\Delta_{\text{Creative}} = \text{CVR}_{\text{Creative}} - \text{CVR}_{\text{Campaign Average}}$$

#### D. Partner & Attribution KPIs
* **Attributed Conversions (Fractional):**
  $$\text{Attributed Conversions} = \sum (\text{conversion\_count} \times \text{touchpoint\_weight})$$
* **Attributed Revenue:**
  $$\text{Attributed Revenue} = \sum (\text{gross\_revenue} \times \text{touchpoint\_weight})$$
* **Attribution Percentage:**
  $$\text{Attribution \%} = \frac{\text{Attributed Revenue}_{\text{Partner}}}{\text{Total Attributed Revenue}_{\text{All Partners}}} \times 100\%$$

#### E. Account Manager Performance KPIs
* **Managed Revenue:** Total Net Adjusted Revenue generated by advertisers managed by the Account Manager during their active assignment tenure.
* **Managed Conversions:** Total conversions occurring under the manager's active tenure.
* **Before / After Reassignment Growth:**
  $$\text{Growth}_{\text{AM}} = \frac{\text{Rev}_{\text{Post-Reassignment}} - \text{Rev}_{\text{Pre-Reassignment}}}{\text{Rev}_{\text{Pre-Reassignment}}} \times 100\%$$

---

## 4. Required Dimensions & Hierarchies

To support slice, dice, roll-up, and drill-down operations in OLAP cubes, the following conformed dimensions and natural hierarchies are established:

```
[Date Hierarchy]
Year (YYYY) -> Quarter (Q1-Q4) -> Month (YYYY-MM) -> Day (YYYY-MM-DD)

[Commercial Hierarchy]
Advertiser -> Campaign -> Offer

[Creative Hierarchy]
Campaign -> Creative (Size, Format, Landing Page)

[Partner Hierarchy]
Media Buyer / Channel -> Partner Organization -> Canonical Partner ID (5-digit prefix)

[Organizational Hierarchy]
Region -> Team -> Account Manager
```

### Conformed Dimensions Specification:
1. **`Dim_Date`:** Role-playing dimension for `impression_date`, `click_date`, `conversion_date`, and `adjustment_date`.
2. **`Dim_Advertiser`:** Natural key `advertiser_id` (ADVxxxxx). Tracks historical Account Manager assignments via **SCD Type 2**.
3. **`Dim_Campaign`:** Natural key `campaign_id` (CMPxxxxx), linked to offer and advertiser with price model (`price_type`: CPA, CPC, CPM).
4. **`Dim_Offer`:** Natural key `offer_id` (OFFxxxxx), default payout terms.
5. **`Dim_Creative`:** Natural key `creative_id` (CRExxxxx), format, dimensions, landing URL.
6. **`Dim_Partner`:** Canonical 5-digit partner key. Reconciles relational `partners_raw` with MongoDB `partner_profiles.jsonl`.
7. **`Dim_Account_Manager`:** Natural key `am_id` (AMxxx), employee name, regional team.
8. **`Dim_Device_Geo` (Junk/Outrigger):** Cleaned device categories (Mobile, Desktop, Tablet) and ISO country codes.

---

## 5. Granularity (Grain) Specification

Explicit grain definition is vital to prevent join fanout. Each business process requires its own Fact table at an atomic grain:

| Fact Table / Model | Explicit Grain Description | Primary Natural / Composite Key | Target Fact Type |
| :--- | :--- | :--- | :--- |
| **`Fact_Impression`** | One row per individual ad display event | `impression_id` | Factless Fact |
| **`Fact_Click`** | One row per individual ad click interaction | `click_id` | Transactional Event Fact |
| **`Fact_Conversion`** | One row per unique valid conversion event (deduplicated at `MAX(updated_at)`) | `conversion_id` | Transactional Metric Fact |
| **`Fact_Revenue_Adjustment`** | One row per individual adjustment/refund transaction | `adjustment_id` | Accumulating / Transactional Fact |
| **`Bridge_Conversion_Touchpoint`** | One row per conversion-to-click attribution pair | `conversion_id` + `click_id` | Fact / Bridge Table |
| **`Mart_Campaign_Daily`** | One row per Campaign per Partner per Day | `campaign_key` + `partner_key` + `date_key` | Periodic Snapshot Summary Mart |

> **Critical Grain Defense:**  
> Joining `Fact_Conversion` directly with `conversion_touchpoints_raw` multiplies conversion rows by the number of touchpoints (up to 5x fanout). In all analytical queries, gross metrics **must** be aggregated from `Fact_Conversion`, and partner-credited metrics must use the fractional weights in `Bridge_Conversion_Touchpoint`.

---

## 6. Historical Requirements & SCD Strategy

### The Business Mandate:
> *"All historical reports must represent the business context that was valid when the event occurred. For example, if an advertiser changes account manager, historical conversions must remain associated with the account manager responsible at the time of the conversion."*

### Engineering Strategy (SCD Type 2):
* **Source of Truth:** MongoDB collection `advertiser_accounts.jsonl` contains the authoritative `account_manager_history` array with effective date intervals:
  ```json
  "account_manager_history": [
    {"am_id": "AM002", "from": "2025-01-01T00:00:00Z", "to": "2025-08-31T23:59:59Z"},
    {"am_id": "AM007", "from": "2025-09-01T00:00:00Z", "to": null}
  ]
  ```
* **Dimension Design (`Dim_Advertiser`):**
  * Uses a surrogate primary key: `advertiser_sk` (`BIGINT IDENTITY`).
  * Natural key: `advertiser_id` (`VARCHAR`).
  * Tracking attributes: `am_id`, `am_name`.
  * Validity metadata: `valid_from (TIMESTAMPTZ)`, `valid_to (TIMESTAMPTZ)`, `is_current (BOOLEAN)`.
* **Fact Table Association:**
  When loading `Fact_Conversion`, the conversion timestamp (`conversion_time`) is matched to `Dim_Advertiser` via:
  $$\text{Dim\_Advertiser.advertiser\_id} = \text{conversion.advertiser\_id}$$
  $$\text{AND } \text{conversion.conversion\_time} \ge \text{Dim\_Advertiser.valid\_from}$$
  $$\text{AND } (\text{conversion.conversion\_time} < \text{Dim\_Advertiser.valid\_to} \text{ OR } \text{Dim\_Advertiser.valid\_to IS NULL})$$
* **Result:** A conversion occurring in July 2025 links to `AM002`, while a conversion occurring in October 2025 links to `AM007`, even if queried today.

---

## 7. Core Analytical Business Questions to Answer

The platform must provide automated, traceable answers to the 10 executive business questions (Question 9):

1. **Q9.1:** Which advertisers generated the highest revenue each quarter? (Quarterly Top-N ranking).
2. **Q9.2:** Which campaigns have the highest CTR but the lowest conversion rate? (Funnel drop-off analysis).
3. **Q9.3:** Which partners generated the highest attributed revenue? (Affiliate ROI ranking).
4. **Q9.4:** How did revenue change compared with the previous month? (Month-over-Month MoM growth % and delta).
5. **Q9.5:** Which campaigns contributed more than 10% of total revenue? (Pareto percentage contribution analysis).
6. **Q9.6:** Which creatives underperformed relative to their campaign average? (Creative anomaly detection).
7. **Q9.7:** How did an advertiser's performance change before and after an account manager change? (SCD-2 historical impact analysis).
8. **Q9.8:** What percentage of total revenue is attributable to each partner? (Attribution share distribution).
9. **Q9.9:** Which campaigns show increasing impressions but declining conversions? (Ad fatigue / banner blindness indicator).
10. **Q9.10:** What is the financial revenue impact of late adjustments? (Reconciliation variance between gross and net adjusted revenue).

---

## 8. Data Freshness (SLAs), Latency & Retention Policies

| Data Layer | Target Latency / Refresh Frequency | Ingestion SLA | Retention Policy | Archive Strategy |
| :--- | :--- | :--- | :--- | :--- |
| **Bronze (Raw Ingest)** | Daily batch (02:00 UTC) + Micro-batch stream | Loaded within 30 mins of file landing | Indefinite (Immutable Raw Store) | Cold cloud storage (gzip/zstd compressed) |
| **Silver (Cleansed)** | Daily batch (03:00 UTC) | Processing complete by 03:45 UTC | 3 Years Online | Partitioned by year/month |
| **Gold (EDW Star)** | Daily batch (04:30 UTC) | EDW refreshed by 05:00 UTC | 5 Years Online | Partitioned by transaction date (`conversion_date`) |
| **Data Marts / OLAP** | Daily batch (05:30 UTC) | Available to BI tools by 06:00 UTC | 5 Years Pre-aggregated | Hot in-memory / materialized cache |

* **Watermarking & Incremental SLA:**  
  Pipelines extract data based on `updated_at > MAX(last_watermark)`. Ingestion pipelines must withstand late-arriving revenue adjustments arriving up to 14 days post-event without dropping records.

---

## 9. Comprehensive KPI-to-Source Mapping Matrix

This matrix establishes the lineage contract from Business KPI down to atomic source fields:

| Business KPI | Target Measure(s) | Required Dimensions | Fact Table Grain | Upstream Source Tables & Fields | Cleansing / Transformation Logic |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Advertiser CTR** | `clicks`, `impressions` | `Dim_Advertiser`, `Dim_Date`, `Dim_Campaign` | Event Grain (`click_id`, `impression_id`) | `impressions_raw.impression_id`, `clicks_raw.click_id` | Clean junk impressions; count distinct clicks / impressions |
| **Advertiser CVR** | `conversions`, `clicks` | `Dim_Advertiser`, `Dim_Date`, `Dim_Campaign` | Deduplicated Conversion (`conversion_id`) | `conversions_raw.conversion_id`, `clicks_raw.click_id` | Deduplicate conversions by `MAX(updated_at)`; filter `is_test = true` |
| **Revenue per Click (RPC)** | `gross_revenue`, `clicks` | `Dim_Advertiser`, `Dim_Campaign`, `Dim_Date` | `click_id` & `conversion_id` | `conversions_raw.revenue`, `clicks_raw.click_id` | Parse currency strings (strip `$`, `USD`); divide total revenue by clicks |
| **Net Adjusted Revenue** | `gross_revenue`, `adjustment_delta` | `Dim_Campaign`, `Dim_Advertiser`, `Dim_Date` | `conversion_id` + `adjustment_id` | `conversions_raw.revenue`, `revenue_adjustments_raw.delta_amount` | Reconcile missing batch deltas via Kafka `adjustment.applied` stream; sum deltas |
| **Campaign Margin** | `net_revenue`, `payout` | `Dim_Campaign`, `Dim_Date` | `conversion_id` | `conversions_raw.revenue`, `conversions_raw.payout` | Parse payout strings; subtract total payouts from adjusted revenue |
| **Attributed Partner Rev** | `attributed_revenue` | `Dim_Partner`, `Dim_Campaign`, `Dim_Date` | `conversion_id` $\times$ `click_id` | `conversions_raw.revenue`, `conversion_touchpoints_raw.weight`, `partners_raw.partner_id` | Extract 5-digit partner prefix; multiply conversion revenue by touchpoint weight |
| **AM Managed Revenue** | `adjusted_revenue` | `Dim_Account_Manager`, `Dim_Advertiser`, `Dim_Date` | Conversion Event linked to SCD-2 Dim | `conversions_raw.revenue`, `advertiser_accounts.jsonl (am_history)` | Join conversion on `advertiser_id` and effective date interval (`valid_from` to `valid_to`) |
| **MoM Revenue Growth** | `monthly_adjusted_revenue` | `Dim_Date (Month)`, `Dim_Advertiser` | Monthly Aggregated Mart | Aggregated `Fact_Conversion` + `Fact_Revenue_Adjustment` | Window function: `(Rev - LAG(Rev, 1) OVER (PARTITION BY adv ORDER BY month)) / LAG(...)` |
| **Late Adjustment Impact** | `gross_rev`, `net_adjusted_rev` | `Dim_Date`, `Dim_Advertiser` | `conversion_id` + `adjustment_id` | `revenue_adjustments_raw.delta_amount`, `conversions_raw.revenue` | Net impact = $\sum \text{delta\_amount}$; Variance % = $\frac{\sum \text{delta}}{\text{Gross Rev}}$ |

---

## 10. Approval & Sign-Off

This document serves as the foundational contract for Question 1. All architectural decisions, pipeline models in Question 2 & Question 4, and verification checks in Question 5 & Question 6 will strictly conform to the grain and metric definitions established herein.
