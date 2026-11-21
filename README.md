# PulseTrack Enterprise Data Platform & Warehouse

> **End-to-End Medallion Analytical Data Platform & Kimball Enterprise Data Warehouse Capstone Solution**  
> **Domain:** Digital Performance-Marketing & Multi-Touch Attribution Network  
> **Platform Engine:** PostgreSQL 18 & Apache Airflow  
> **Language & Tooling:** Python 3.11 (`psycopg2`, `sqlalchemy`, `duckdb`, `pandas`, `tabulate`, `pytest`)

---

## 🌟 Executive Summary

**PulseTrack** is a high-throughput digital performance-marketing platform connecting **Advertisers** (clients funding campaigns), **Creatives** (ad banners/assets), **Marketing Partners / Affiliates** (publishers driving traffic), **Internal Account Managers** (managing client portfolios), and **End-Users** (generating conversion funnel activity).

This repository contains the complete, production-grade implementation of the **PulseTrack Enterprise Data Platform & Warehouse (EDW)**. Built on a 5-tier **Medallion Architecture** (`pulsetrack_raw` → `pulsetrack_silver` → `pulsetrack_gold` → `pulsetrack_mart` → `pulsetrack_audit`), it ingests heterogeneous source systems (relational CSVs, semi-structured MongoDB JSONL documents, and streaming Kafka log files), transforms them through deterministic deduplication and standardisation engines, populates a dimensional **Kimball Star Schema** with **Slowly Changing Dimensions (SCD Type 2)** and **Multi-Touch Attribution Bridges**, materializes high-performance **Departmental Data Marts**, provides a 13-view **OLAP Semantic Layer**, and enforces an automated **Data Quality & 7-Layer Financial Reconciliation Ledger**.

---

## 🏗 End-to-End Architecture Lineage

```text
+---------------------------------------------------------------------------------------------------------+
|                                           SOURCE SYSTEMS                                                |
|   • Relational CSV Exports: Conversions, Revenue Adjustments, Offers, Creatives, Tracking Links        |
|   • MongoDB Document Store: Advertiser Accounts, Account Managers, Dynamic Custom Fields (JSONL)        |
|   • Event Streaming Logs: Kafka Click Logs, Kafka Ad Impression Feeds (JSON Stream)                    |
+---------------------------------------------------------------------------------------------------------+
                                                     │
                                                     ▼
+---------------------------------------------------------------------------------------------------------+
|                                    1. BRONZE LAYER (`pulsetrack_raw`)                                   |
|   • Verbatim raw landing with zero data loss (untyped TEXT columns + native JSONB payloads)             |
|   • Ingestion metadata injection: `_ingested_at`, `_batch_id`, `_source_file`                           |
+---------------------------------------------------------------------------------------------------------+
                                                     │
                                                     ▼
+---------------------------------------------------------------------------------------------------------+
|                                   2. SILVER LAYER (`pulsetrack_silver`)                                 |
|   • Deterministic deduplication via `ROW_NUMBER() OVER (...) = 1` across business keys                  |
|   • Robust standardisation: Regex currency cleansing, ISO UTC timestamp normalization, Geo/IP parsing   |
|   • Referential reconciliation & JSON flattening of nested MongoDB AM assignment histories              |
+---------------------------------------------------------------------------------------------------------+
                                                     │
                                                     ▼
+---------------------------------------------------------------------------------------------------------+
|                                     3. GOLD LAYER (`pulsetrack_gold`)                                   |
|   • Kimball Enterprise Star Schema with Surrogate Keys & Declared Referential Foreign Keys              |
|   • Slowly Changing Dimension (SCD Type 2): `dim_advertiser` with temporal tracking (`valid_from/to`)   |
|   • Conformed Dimensions: `dim_date`, `dim_partner`, `dim_campaign`, `dim_offer`, `dim_creative`, etc.   |
|   • Fact Tables: `fact_conversion`, `fact_click`, `fact_impression`, `fact_revenue_adjustment`           |
|   • Attribution Bridge: `bridge_conversion_touchpoint` (isolates M:N multi-touch from fact grain)       |
+---------------------------------------------------------------------------------------------------------+
                                                     │
                                                     ▼
+---------------------------------------------------------------------------------------------------------+
|                                    4. DATA MART LAYER (`pulsetrack_mart`)                               |
|   • Departmental Aggregations: `mart_campaign_performance_daily`, `mart_partner_attribution_daily`,     |
|     `mart_advertiser_am_monthly`                                                                        |
|   • Performance Indexing (B-Tree composite indexes for sub-second executive BI query execution)         |
+---------------------------------------------------------------------------------------------------------+
                                                     │
                                                     ▼
+---------------------------------------------------------------------------------------------------------+
|                                  5. SEMANTIC OLAP & ANALYTICS LAYER                                     |
|   • 13 Semantic Views: Dimension Hierarchies (Date H1, Commercial H2, Partner H3)                       |
|   • Core OLAP Operations: Roll-Up, Drill-Down, Slicing, Dicing, Pivoting, Window Lead/Lag Metrics        |
|   • 10 Executive Business Queries (EQ-1 through EQ-10) powering strategic marketing decisions          |
+---------------------------------------------------------------------------------------------------------+
                                                     │
                                                     ▼
+---------------------------------------------------------------------------------------------------------+
|                                    6. AUDIT & QUALITY GATE LAYER (`pulsetrack_audit`)                   |
|   • Pipeline Execution Ledger: Execution logs, row counts, and status tracking                          |
|   • Stream Quarantine: Captures malformed records with failure reasons                                  |
|   • Automated Quality Gates: PK Uniqueness, FK Referential Integrity, Nullability, Value Ranges        |
|   • Penny-Perfect 7-Layer Financial Reconciliation: Validates Raw → Silver → Gold → Mart revenue        |
+---------------------------------------------------------------------------------------------------------+
```

---

## 📁 Repository Structure

```text
pulsetrack_platform/
├── airflow/                                    # Apache Airflow Orchestration Suite
│   ├── dags/
│   │   └── pulsetrack_medallion_pipeline_dag.py # Master Medallion Pipeline DAG
│   └── README.md                               # Airflow deployment & execution instructions
│
├── docs/                                       # Assessment Technical Deliverables (Questions 1 - 10)
│   ├── Q1_Requirements_and_KPIs.md             # Q1: Business KPIs, grain specs, freshness SLAs (15 Marks)
│   ├── Q2_Source_Forensics_and_EDW.md          # Q2: Forensic report, Star Schema, SCD-2 specs (20 Marks)
│   ├── Q3_Technology_Decision_Record.md        # Q3: Architecture evaluation & tool selection (15 Marks)
│   ├── Q4_Pipeline_Implementation_Report.md    # Q4: Pipeline implementation & Medallion ETL (20 Marks)
│   ├── Q5_Incremental_and_Idempotency.md       # Q5: Idempotency, late data & recovery tests (10 Marks)
│   ├── Q6_Data_Quality_and_Audit.md            # Q6: Quality gates, audit schema, reconciliation (10 Marks)
│   ├── Q7_Data_Mart_Design_and_Implementation.md # Q7: Departmental marts & performance (10 Marks)
│   ├── Q8_OLAP_Semantic_Model.md               # Q8: Cube definitions, hierarchies, measures (15 Marks)
│   ├── Q9_Business_Analytics.md                # Q9: Answers to 10 executive business questions (10 Marks)
│   ├── Q10_Production_Defense.md               # Q10: Lead Data Engineer architectural defense (5 Marks)
│   └── q9_results.json                         # Serialized JSON outputs for all 10 executive queries
│
├── sql/                                        # Database DDLs, transformations & views
│   ├── 01_bronze/
│   │   └── 01_bronze_ddl.sql                   # Raw landing schema DDLs & ingestion metadata
│   ├── 02_silver/
│   │   ├── 01_silver_helpers.sql               # Cleansing UDFs (regex currency parser, timestamp parser)
│   │   └── 02_silver_models.sql                # Deduplicated, cleansed views & staging tables
│   ├── 03_gold/
│   │   ├── 01_gold_star_schema_ddl.sql         # Kimball Star Schema DDLs (dims, facts, bridge, constraints)
│   │   └── 02_load_gold_star_schema.sql        # Gold loading logic (SCD-2 historical loader, facts load)
│   ├── 04_marts/
│   │   └── 01_data_marts_ddl_and_load.sql      # Departmental mart DDLs, aggregations & indexes
│   └── 05_analytics/
│       ├── 01_olap_semantic_views.sql          # 13 Semantic OLAP Views (Hierarchies & Cubes)
│       └── 02_executive_business_queries.sql   # SQL implementation of the 10 Executive Business Queries
│
├── src/                                        # Production Python ETL/ELT pipelines & runners
│   ├── config.py                               # Database settings, credentials & path resolution
│   ├── init_database.py                        # Database & schema initializer (`pulsetrack_raw/silver/gold/mart/audit`)
│   ├── ingest_bronze.py                        # Bronze ingestion engine (CSV, Mongo JSONL, Kafka log)
│   ├── build_silver.py                         # Silver cleansing, deduplication & standardisation runner
│   ├── build_gold.py                           # Gold Star Schema & SCD Type 2 loader runner
│   ├── build_marts.py                          # Mart aggregation runner & performance indexer
│   ├── build_olap.py                           # OLAP semantic view compiler & validator
│   ├── run_pipeline.py                         # Master orchestration script (Bronze → Silver → Gold)
│   ├── data_quality.py                         # Automated DQ test gates & Cross-Layer Financial Reconciliation
│   ├── run_executive_queries.py                # Executive queries runner & ASCII table formatter
│   ├── check_db.py                             # Local PostgreSQL connectivity checker
│   └── inspect_dates.py                        # Data profile & date boundary inspector
│
├── tests/                                      # Automated testing & recovery simulations
│   └── test_question_5_scenarios.py            # Idempotency, duplicate delivery, backfill & recovery tests
│
├── requirements.txt                            # Python dependencies
└── README.md                                   # Main Project Documentation
```

---

## 🛠 Technology Stack & Design Decisions

| Category | Component / Tool | Role in Architecture |
| :--- | :--- | :--- |
| **Warehouse Engine** | **PostgreSQL 18** | High-performance relational analytical store with JSONB document support, partition capabilities, window functions, and strict ACID guarantees. |
| **Pipeline Language** | **Python 3.11** | Orchestrates ELT/ETL jobs, file stream parsing, database bulk loading, and automated testing suites. |
| **Database Drivers** | **`psycopg2` & `sqlalchemy`** | High-performance PostgreSQL adapters using bulk operations and native SQL connection pooling. |
| **Analytical Engine** | **DuckDB & Pandas** | High-efficiency embedded analytical processing and tabular transformations for source forensics and data staging. |
| **Orchestration** | **Apache Airflow** | Scheduled linear DAG pipeline (`pulsetrack_medallion_pipeline`) with automated retries, dependency enforcement, and alert hooks. |
| **Testing & Quality** | **PyTest & Custom DQ Suite** | Pre-load and post-load quality gates verifying PK uniqueness, referential integrity, nullability, and penny-perfect audit reconciliation. |
| **Warehouse Modeling** | **Kimball Star Schema & SCD-2** | Conformed dimensions, grain separation, surrogate keys, and temporal interval tracking (`valid_from` / `valid_to`). |

---

## 🗄 Database Schemas & Data Modeling

The platform isolates processing stages into 5 distinct PostgreSQL schemas:

### 1. `pulsetrack_raw` (Bronze Layer)
* **Design:** Untyped staging tables storing verbatim incoming raw strings and raw JSONB payloads.
* **Audit Metadata:** Injects `_ingested_at`, `_batch_id`, and `_source_file` onto every record for complete lineage tracking.
* **Key Tables:** `conversions_raw`, `revenue_adjustments_raw`, `raw_mongo_advertiser_accounts`, `account_managers_raw`, `partners_raw`, `campaigns_raw`, `offers_raw`, `creatives_raw`, `tracking_links_raw`, `stream_impressions_raw`, `stream_clicks_raw`.

### 2. `pulsetrack_silver` (Silver Layer)
* **Design:** Cleaned, typed, deduplicated, and validated relational models.
* **Deduplication:** Implements `ROW_NUMBER() OVER (PARTITION BY business_key ORDER BY updated_at DESC, _ingested_at DESC) = 1` to guarantee exactly-once processing.
* **Standardisation:** Regex cleansing of dirty currency strings (stripping symbols, handling negative balances and trailing indicators), ISO-8601 UTC timestamp alignment, IP address validation, and Geo-country normalisation.
* **Key Tables/Views:** `stg_conversions`, `stg_revenue_adjustments`, `stg_advertiser_am_history`, `stg_account_managers`, `stg_partners`, `stg_campaigns`, `stg_offers`, `stg_creatives`, `stg_impressions`, `stg_clicks`.

### 3. `pulsetrack_gold` (Gold Enterprise Data Warehouse)
* **Design:** Dimensional Kimball Star Schema enforcing grain separation, surrogate keys (`BIGINT GENERATED ALWAYS AS IDENTITY`), and strict referential foreign keys.
* **SCD Type 2 Dimension (`dim_advertiser`):** Tracks historical changes to advertiser account manager assignments with `valid_from`, `valid_to`, and `is_current` boolean flags.
* **Conformed Dimensions:** `dim_date`, `dim_partner`, `dim_campaign`, `dim_offer`, `dim_creative`, `dim_device_geo`, `dim_junk_conversion`.
* **Fact Tables:**
  * `fact_conversion`: Atomic transaction conversions with financial metrics (`gross_revenue`, `payout_amount`, `net_margin`).
  * `fact_click`: Ad click engagements with unique click flags and IP/User-Agent tracking.
  * `fact_impression`: Ad impression deliveries measuring reach and top-of-funnel exposure.
  * `fact_revenue_adjustment`: Retroactive post-conversion adjustments (chargebacks, bonuses, refunds) preserving historical non-destructive audit trails.
* **Attribution Bridge:** `bridge_conversion_touchpoint`: Isolates multi-touch partner attribution ($M:N$ relationship) from conversion accounting, assigning touch sequence, channel role (First, Mid, Last), and attribution weight percentages without duplicating financial facts.

### 4. `pulsetrack_mart` (Departmental Data Marts & OLAP)
* **Design:** Pre-aggregated, indexed departmental marts eliminating join complexity and enabling sub-second analytical reporting.
* **Key Marts:**
  * `mart_campaign_performance_daily`: Grain: Campaign $\times$ Partner $\times$ Date. Aggregates impressions, clicks, conversions, gross revenue, payout, net margin, adjusted revenue, CTR, CVR, and EPC.
  * `mart_partner_attribution_daily`: Grain: Partner $\times$ Campaign $\times$ Date. Tracks multi-touch contributions (first touch, middle touch, last touch) and attributed revenue.
  * `mart_advertiser_am_monthly`: Grain: Advertiser $\times$ Account Manager $\times$ Month. Evaluates AM portfolio performance, net margin, and adjustment ratios across SCD-2 tenure.
* **13 OLAP Semantic Views:** Supports Date (H1), Commercial (H2), and Partner (H3) hierarchies alongside Roll-Up, Drill-Down, Slice, Dice, Pivot, and Window functions.

### 5. `pulsetrack_audit` (Audit, Lineage & Quality)
* **`pipeline_execution_log`:** Execution telemetry recording batch ID, layer, row counts (source, inserted, updated, rejected), duration, and status.
* **`quarantine_stream_lines`:** Captures corrupt stream lines, malformed JSON, and contract violations with error descriptions for reprocessing.

---

## 🚀 Quick Start & Step-by-Step Execution Guide

### Prerequisites
* **Operating System:** Windows, macOS, or Linux
* **PostgreSQL:** Version 18 (or 14+) running locally or in Docker
* **Python:** Version 3.11+
* **Database IDE (Optional):** DataGrip, DBeaver, or pgAdmin 4

---

### Step 1: Clone Repository & Set Up Virtual Environment

```bash
# Clone the repository
git clone https://github.com/zuucrew/pulsetrack_platform.git
cd pulsetrack_platform

# Create and activate Python virtual environment
python -m venv venv

# Windows (PowerShell):
.\venv\Scripts\Activate.ps1

# macOS / Linux:
source venv/bin/activate

# Install required Python packages
pip install -r requirements.txt
```

---

### Step 2: Configure Database Connection

Create or edit your environment variables, or update [`src/config.py`](src/config.py) directly:

```bash
export DB_HOST="localhost"
export DB_PORT="5432"
export DB_USER="postgres"
export DB_PASSWORD="your_postgres_password"
export DB_NAME="pulsetrack_dw"
```

Verify your database connectivity:
```bash
python src/check_db.py
```

---

### Step 3: Initialize Database & Schemas

Creates the `pulsetrack_dw` database (if not existing) and initializes all 5 schemas (`pulsetrack_raw`, `pulsetrack_silver`, `pulsetrack_gold`, `pulsetrack_mart`, `pulsetrack_audit`) and audit infrastructure:

```bash
python src/init_database.py
```

---

### Step 4: Run the Medallion Pipeline (Bronze → Silver → Gold)

Executes raw ingestion, silver standardisation/deduplication, and gold dimensional loading (with SCD-2 and attribution bridge):

```bash
python src/run_pipeline.py
```

*Or execute layers individually:*
```bash
# 1. Ingest Bronze layer
python src/ingest_bronze.py

# 2. Build Silver layer (cleansing & deduplication)
python src/build_silver.py

# 3. Build Gold layer (star schema & SCD Type 2 loader)
python src/build_gold.py
```

---

### Step 5: Build Departmental Data Marts & OLAP Views

Compile aggregated departmental marts and validate the 13 semantic OLAP views:

```bash
# Generate Departmental Data Marts
python src/build_marts.py

# Deploy & validate the 13 OLAP Semantic Views
python src/build_olap.py
```

---

### Step 6: Run Automated Data Quality & Financial Reconciliation Gates

Executes comprehensive quality gates (primary key uniqueness, referential foreign key integrity, nullability checks) and the **7-Layer Cross-Layer Financial Reconciliation Ledger**:

```bash
python src/data_quality.py
```

---

### Step 7: Execute the 10 Executive Business Queries (Q9)

Runs the executive business analytics suite answering management's 10 strategic questions, rendering tabulated results to console and updating [`docs/q9_results.json`](docs/q9_results.json):

```bash
python src/run_executive_queries.py
```

---

### Step 8: Run Automated Idempotency & Failure Recovery Tests (Q5)

Executes simulation tests for duplicate file ingestion (50,000 duplicate deliveries), out-of-order late-arriving revenue adjustments, and mid-pipeline failure rollbacks:

```bash
python tests/test_question_5_scenarios.py
```

---

## ⚡ Apache Airflow Orchestration

The pipeline is orchestrated end-to-end via Apache Airflow with the DAG [`pulsetrack_medallion_pipeline_dag.py`](airflow/dags/pulsetrack_medallion_pipeline_dag.py).

### Linear DAG Task Dependencies
```text
[start_pipeline]
       │
       ▼
[init_warehouse_schemas]
       │
       ▼
[ingest_bronze_raw]               (CSV, MongoDB JSONL, Kafka stream)
       │
       ▼
[cleanse_silver_staging]          (Deduplication ROW_NUMBER()=1, currency parsing)
       │
       ▼
[build_gold_star_schema]          (SCD Type 2 dim_advertiser, facts, bridge)
       │
       ▼
[build_departmental_marts]        (mart_campaign_performance_daily, attribution)
       │
       ▼
[verify_data_quality_and_reconciliation] (Automated DQ gates & Financial Ledger)
       │
       ▼
[end_pipeline]
```

### Running the DAG in Airflow
See the dedicated [Airflow Deployment Guide](airflow/README.md) for full setup instructions:

```bash
# Point Airflow to the DAGs directory
export AIRFLOW__CORE__DAGS_FOLDER=$(pwd)/airflow/dags

# Initialize Airflow DB (if not already done)
airflow db init

# Unpause and trigger the DAG
airflow dags unpause pulsetrack_medallion_pipeline
airflow dags trigger pulsetrack_medallion_pipeline
```

---

## 📑 Assessment Deliverables Matrix (Questions 1 - 10)

This platform provides exhaustive architectural, engineering, and analytical documentation across all 10 project deliverables (Total: 130 Marks):

| Deliverable | Marks | Topic & Specification | Primary Deliverable File | Key Assets / Scripts |
| :--- | :---: | :--- | :--- | :--- |
| **Question 1** | **15** | **Analytical Requirements & KPIs** | [`docs/Q1_Requirements_and_KPIs.md`](docs/Q1_Requirements_and_KPIs.md) | KPI definitions, grain specs, additivity matrix, SLAs |
| **Question 2** | **20** | **Source Forensics & Kimball EDW** | [`docs/Q2_Source_Forensics_and_EDW.md`](docs/Q2_Source_Forensics_and_EDW.md) | Entity forensics, Star Schema DDLs, SCD-2 specs |
| **Question 3** | **15** | **Technology Decision Record (TDR)** | [`docs/Q3_Technology_Decision_Record.md`](docs/Q3_Technology_Decision_Record.md) | Multi-criteria scorecard, trade-off analysis, TCO |
| **Question 4** | **20** | **Pipeline Implementation Report** | [`docs/Q4_Pipeline_Implementation_Report.md`](docs/Q4_Pipeline_Implementation_Report.md) | Ingestion architecture, regex cleansing, SQL models |
| **Question 5** | **10** | **Incremental & Idempotency** | [`docs/Q5_Incremental_and_Idempotency.md`](docs/Q5_Incremental_and_Idempotency.md) | [`tests/test_question_5_scenarios.py`](tests/test_question_5_scenarios.py) (dedup, late data) |
| **Question 6** | **10** | **Data Quality & Audit Schema** | [`docs/Q6_Data_Quality_and_Audit.md`](docs/Q6_Data_Quality_and_Audit.md) | [`src/data_quality.py`](src/data_quality.py), 7-layer reconciliation ledger |
| **Question 7** | **10** | **Data Mart Design & Performance** | [`docs/Q7_Data_Mart_Design_and_Implementation.md`](docs/Q7_Data_Mart_Design_and_Implementation.md) | [`sql/04_marts/01_data_marts_ddl_and_load.sql`](sql/04_marts/01_data_marts_ddl_and_load.sql) |
| **Question 8** | **15** | **OLAP Semantic Model & Cubes** | [`docs/Q8_OLAP_Semantic_Model.md`](docs/Q8_OLAP_Semantic_Model.md) | [`src/build_olap.py`](src/build_olap.py), 13 semantic views |
| **Question 9** | **10** | **Executive Business Analytics** | [`docs/Q9_Business_Analytics.md`](docs/Q9_Business_Analytics.md) | [`src/run_executive_queries.py`](src/run_executive_queries.py), [`docs/q9_results.json`](docs/q9_results.json) |
| **Question 10** | **5** | **Production Architecture Defense** | [`docs/Q10_Production_Defense.md`](docs/Q10_Production_Defense.md) | Lead DE stress tests, schema drift, disaster recovery |

---

## 🛡 Key Engineering Highlights

1. **Slowly Changing Dimension (SCD Type 2):**  
   The `dim_advertiser` dimension maintains a complete audit trail of account manager reassignments across time using `valid_from`, `valid_to`, and `is_current` indicators. When joins occur with historical facts, conversions link to the exact account manager managing the advertiser at the transaction timestamp.
2. **Grain Separation & Multi-Touch Attribution Bridge:**  
   To prevent double-counting conversions and gross revenues across multi-touch partner journeys, the platform isolates attribution touchpoints into `bridge_conversion_touchpoint`. Financial figures remain purely atomic inside `fact_conversion`, while channel attribution weights ($W \in [0.0, 1.0]$) sum to 100% per conversion.
3. **Deterministic Idempotency:**  
   Every pipeline step is completely safe to rerun multiple times without duplicating data or creating orphan records. Silver window ranking (`ROW_NUMBER() = 1`) neutralizes duplicate source deliveries, and Gold staging swaps guarantee atomic updates.
4. **Penny-Perfect 7-Layer Financial Reconciliation:**  
   The audit engine reconciles gross transaction revenue, partner payouts, and net margins across all layers (Source CSV $\rightarrow$ Bronze $\rightarrow$ Silver $\rightarrow$ Gold Facts $\rightarrow$ Data Marts). Every cent is mathematically verified with zero discrepancy.

---

## 👥 Contributors & Authorship
* **Lead Data Engineer & Enterprise Data Architect:** ZuuCrew DWDF Capstone Team  
* **Academic & Project Context:** Data Warehousing & Data Flow (DWDF) Capstone Project  
* **License:** Proprietary / Educational Capstone Review
