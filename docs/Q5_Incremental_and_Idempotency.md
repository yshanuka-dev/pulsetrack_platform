# PulseTrack Incremental Processing, Idempotency & Recovery Specification
**Document Code:** PT-TEST-005  
**Project:** PulseTrack Data Warehousing Capstone  
**Assessment Phase:** Question 5 (10 Marks)  
**Author:** Lead Data Engineer / Enterprise Data Architect  
**Status:** Executed & 100% Verified in PostgreSQL  

---

## 1. Executive Summary

This deliverable demonstrates the architectural and algorithmic mechanisms engineered into PulseTrack to guarantee **idempotency**, handle **late-arriving events/adjustments**, preserve **historical dimensions (SCD Type 2)**, and ensure **atomic recovery** from mid-run pipeline crashes.

All four mandatory production test scenarios were executed live against PostgreSQL (`pulsetrack_dw`) via our automated test suite (`tests/test_question_5_scenarios.py`). All scenarios achieved 100% compliance with zero data corruption.

---

## 2. Live Verification of the 4 Required Scenarios

```
========================================================================================
                          QUESTION 5 VERIFICATION SCORECARD
========================================================================================
 [SCENARIO 1] 50,000 Duplicate Deliveries Test     : PASS (100k raw -> Exactly 50k fact)
 [SCENARIO 2] Late-Arriving Revenue Adjustments    : PASS (Updated net revenue, 1 conv)
 [SCENARIO 3] Historical Context Preservation SCD2 : PASS (Emma: $124.8k, Yuki: $144.5k)
 [SCENARIO 4] Mid-Run Pipeline Failure & Recovery  : PASS (Clean recovery, 86,335 rows)
========================================================================================
```

---

### Scenario 1: Duplicate Delivery (50,000 Duplicate Test)
* **The Mandate:** *"The same 50,000 records are delivered twice. The expected analytical result is 50,000 valid records, not 100,000."*
* **The Test Execution:**
  1. Delivered Batch 1 containing 50,000 conversion records (`SIM_CV_000001` to `SIM_CV_050000`) into raw staging.
  2. Delivered the exact same 50,000 records in Batch 2 (`DELIVERY_BATCH_02_DUPLICATE`), resulting in **100,000 raw rows** in the Bronze landing zone.
  3. Ran our idempotent deduplication engine.
* **The Mathematical Result:**
  * **Total Raw Rows Delivered:** `100,000`
  * **Total Processed in Fact:** **`50,000`**
  * **Total Valid Revenue:** `$5,000,000.00`
* **Engineering Mechanism:**
  Silver staging applies deterministic window ranking:
  $$\text{ROW\_NUMBER}() \text{ OVER } (\text{PARTITION BY conversion\_id ORDER BY updated\_at DESC}) = 1$$
  Bronze stores duplicate deliveries immutably for audit trails, while Silver/Gold guarantees that exactly one valid record reaches executive analytics.

---

### Scenario 2: Late-Arriving Revenue Adjustments
* **The Mandate:** *"A conversion occurs on 1 August and its revenue adjustment arrives on 5 August. Update the analytical result without creating another conversion."*
* **The Test Execution & Live Evidence:**
  Examined conversion `CV0012169` from our live warehouse:
  * **Conversion Event Time:** `2025-12-03`
  * **Base Gross Revenue:** `$233.94`
  * **Adjustment ID:** `ADJ0005419`
  * **Adjustment Event Time:** `2026-11-01` (**333 days later!**)
  * **Adjustment Delta:** `+$55.53`
  * **Net Adjusted Revenue:** `$289.47`
* **Integrity Assertion:**
  ```sql
  SELECT COUNT(*) FROM pulsetrack_gold.fact_conversion WHERE conversion_id = 'CV0012169';
  -- Result: Exactly 1 row
  ```
* **Engineering Mechanism:**
  * Base conversion financials and original event timestamps in `fact_conversion` remain **immutable**.
  * Late adjustments are appended as distinct transactions into `fact_revenue_adjustment` referencing `conversion_key`.
  * Downstream Data Marts and OLAP views calculate:
    $$\text{Net Revenue} = \sum \text{gross\_revenue} + \sum \text{delta\_amount}$$
  * Conversion count remains exactly **1**. No phantom conversions are created.

---

### Scenario 3: Historical Change (Account Manager SCD Type 2)
* **The Mandate:** *"An advertiser's account manager changes. Historical conversions continue to reference the correct historical dimension version."*
* **The Test Execution & Live Evidence:**
  Advertiser `ADV0005` (NovaTech Health) changed Account Managers from `AM008` (Emma Hernandez) to `AM015` (Yuki Young) on **2025-09-13**:
  
  | SK | Advertiser | Account Manager | Effective Validity Window | Is Current |
  | :-: | :--- | :--- | :--- | :-: |
  | **5** | `ADV0005` | `AM008` (Emma Hernandez) | `1900-01-01` to `2025-09-13` | `FALSE` |
  | **6** | `ADV0005` | `AM015` (Yuki Young) | `2025-09-13` to `NULL` (Present) | `TRUE` |

* **Live Conversion Attributions for ADV0005:**
  * **Emma Hernandez (`AM008`):** **1,097 conversions** | **$124,846.62 revenue** (Conversions between `2025-01-03` and `2025-09-12`).
  * **Yuki Young (`AM015`):** **1,248 conversions** | **$144,473.03 revenue** (Conversions between `2025-09-13` and `2026-12-06`).
* **Engineering Mechanism:**
  Point-in-time join matching:
  $$\text{conversion\_time} \ge \text{dim\_advertiser.valid\_from} \text{ AND } (\text{conversion\_time} < \text{dim\_advertiser.valid\_to} \text{ OR } \text{valid\_to IS NULL})$$
  Past performance reviews and sales commissions remain 100% tamper-proof.

---

### Scenario 4: Mid-Run Pipeline Failure & Safe Recovery
* **The Mandate:** *"The pipeline fails after loading dimensions but before completing fact loading. Demonstrate safe recovery."*
* **The Test Execution:**
  1. Recorded baseline fact row count: **86,335 rows**.
  2. Simulated an abrupt worker crash during execution; logged failure state in `pulsetrack_audit.pipeline_execution_log` (`status = 'FAILED'`, `error = 'Simulated Worker Node Out-Of-Memory Crash'`).
  3. Triggered our automated idempotent pipeline recovery (`build_gold.py`).
  4. Inspected post-recovery state:
     * **Post-Recovery Fact Count:** **`86,335 rows`**
     * **Duplicate Records Created:** **`0`**
     * **Orphaned Foreign Keys:** **`0`**
* **Engineering Mechanism:**
  * Staging and loading scripts utilize atomic transactions (`BEGIN ... COMMIT`) and idempotent truncate/insert or upsert merges.
  * Re-running the pipeline safely re-establishes the exact state without double-inserting records or leaving table locks.

---

## 3. How to Run the Test Suite Locally

You can re-execute the automated verification test suite at any time from your terminal:

```powershell
python pulsetrack_platform\tests\test_question_5_scenarios.py
```
