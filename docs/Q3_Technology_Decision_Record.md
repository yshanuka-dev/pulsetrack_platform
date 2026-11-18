# PulseTrack Technology Decision Record (TDR) & Platform Architecture
**Document Code:** PT-ARCH-003  
**Project:** PulseTrack Data Warehousing Capstone  
**Assessment Phase:** Question 3 (15 Marks)  
**Author:** Lead Data Engineer / Enterprise Data Architect  
**Status:** Approved & Baselined  

---

## 1. Executive Summary

This Technology Decision Record (TDR) establishes the official technology selection and end-to-end data platform architecture for PulseTrack. To fulfill the Lead Data Engineer assessment requirements, we systematically evaluate **three distinct candidate architectural stacks** across **14 weighted criteria**. 

The evaluation formally justifies the selection of **Candidate Stack 2: The Modern Data Stack (Python Ingestion + dbt Transformation + PostgreSQL EDW + Modular Task Orchestration)** as the optimal, production-grade architecture balancing processing speed, developer ergonomics, automated data testing, native SCD Type 2 handling, and zero unnecessary infrastructure overhead.

---

## 2. Evaluation Methodology & The 14 Required Criteria

Each candidate stack is evaluated on a **1 to 5 scale** across the 14 criteria specified in the project charter:
* **Score 5:** Exceptional native support, zero friction, enterprise-grade capability.
* **Score 3:** Adequate support, requires moderate boilerplate or configuration.
* **Score 1:** Poor fit, severe operational overhead, or lacks native capabilities.

Each criterion is assigned a **Weight (1x to 3x)** based on PulseTrack's specific business challenges (e.g., handling messy JSON/stream logs, duplicate delivery, SCD-2 history, and automated quality testing):

| # | Evaluation Criterion | Weight | PulseTrack Context & Criticality |
| :-: | :--- | :-: | :--- |
| **C1** | **CSV Ingestion** | 2x | High-throughput bulk ingest of 11 relational files (~775k rows). |
| **C2** | **JSON Ingestion** | 3x | Semi-structured MongoDB `partner_profiles` & `advertiser_accounts` with nested arrays. |
| **C3** | **PostgreSQL Extraction** | 2x | Native ability to extract from and load to relational PostgreSQL instances. |
| **C4** | **Transformation Capability** | 3x | Normalization, regex currency cleaning, complex window functions, and business logic. |
| **C5** | **Large-Volume Processing** | 2x | Sub-second execution on million-row datasets without cluster latency. |
| **C6** | **Scheduling** | 2x | Batch scheduling (cron/interval triggers) and dependency chain execution. |
| **C7** | **Dependency Management** | 3x | Directed Acyclic Graph (DAG) resolution between Bronze, Silver, Gold, and Mart layers. |
| **C8** | **Incremental Processing** | 3x | Watermarking via `updated_at`, handling late-arriving records without full table reloads. |
| **C9** | **Retry & Recovery** | 3x | Atomic transactions, checkpoint restarts, and idempotent retry upon mid-run failures. |
| **C10**| **Backfill Capability** | 2x | Replaying historical batches and re-generating historical dimension snapshots. |
| **C11**| **Data Quality & Testing** | 3x | Automated schema assertions, null checks, referential integrity, and reconciliation tests. |
| **C12**| **Maintainability** | 2x | Modular code structure, version control (Git), and SQL readability. |
| **C13**| **Scalability** | 2x | Capacity to scale from current volumes to 10x traffic spikes. |
| **C14**| **Monitoring & Lineage** | 3x | Audit logging, run execution metrics, and visual data lineage graphs. |

---

## 3. Candidate Architectural Stacks Evaluated

### Option 1: Legacy ETL / Script-Heavy (Python + Raw SQL + Cron)
* **Ingestion:** Python scripts (`pandas` / `psycopg2`)
* **Transformation:** Python procedural scripts pushing raw SQL commands directly into PostgreSQL
* **Orchestration:** Standalone Python script runner triggered via Windows Task Scheduler / Cron
* **Quality & Lineage:** Ad-hoc custom SQL assertions; manual spreadsheet documentation

### Option 2: The Modern Data Stack (Python Ingestion + dbt + PostgreSQL + Task Orchestrator) — [SELECTED]
* **Ingestion:** Python 3.11 extractors with DuckDB/Pandas high-speed loaders into Bronze staging
* **Transformation:** **dbt Core (data build tool)** with `dbt-postgres` adapter for Silver/Gold modeling
* **Warehouse:** PostgreSQL 18 with isolated Medallion schemas (`raw`, `silver`, `gold`, `mart`)
* **Orchestration:** Modular Python Pipeline Orchestrator with DAG execution and Airflow compatibility
* **Quality & Lineage:** Built-in dbt assertions (`unique`, `not_null`, `relationships`), custom tests, and auto-generated interactive DAG lineage graphs

### Option 3: Distributed Big Data Lakehouse (PySpark + Delta Lake + Apache Airflow)
* **Ingestion:** PySpark structured streaming and batch readers
* **Transformation:** PySpark DataFrame API / Spark SQL writing to Parquet/Delta Lake tables
* **Orchestration:** Apache Airflow cluster (Webserver, Scheduler, Celery Workers)
* **Quality & Lineage:** Great Expectations + OpenLineage / Marquez

---

## 4. Weighted Scoring Matrix

| Criterion (Weight) | Option 1: Python + Raw SQL | Option 2: Python + dbt + Postgres | Option 3: PySpark + Delta + Airflow |
| :--- | :---: | :---: | :---: |
| **C1: CSV Ingestion (2x)** | 4 (8) | 5 (10) | 4 (8) |
| **C2: JSON Ingestion (3x)** | 5 (15) | 5 (15) | 5 (15) |
| **C3: PostgreSQL Extraction (2x)** | 4 (8) | 5 (10) | 4 (8) |
| **C4: Transformation (3x)** | 3 (9) | 5 (15) | 5 (15) |
| **C5: Large-Volume Processing (2x)** | 3 (6) | 4 (8) | 5 (10) |
| **C6: Scheduling (2x)** | 2 (4) | 4 (8) | 5 (10) |
| **C7: Dependency Mgmt (3x)** | 2 (6) | 5 (15) | 5 (15) |
| **C8: Incremental Processing (3x)** | 3 (9) | 5 (15) | 4 (12) |
| **C9: Retry & Recovery (3x)** | 3 (9) | 5 (15) | 4 (12) |
| **C10: Backfill Capability (2x)** | 3 (6) | 5 (10) | 4 (8) |
| **C11: Data Quality & Testing (3x)** | 2 (6) | 5 (15) | 4 (12) |
| **C12: Maintainability (2x)** | 2 (4) | 5 (10) | 3 (6) |
| **C13: Scalability (2x)** | 3 (6) | 4 (8) | 5 (10) |
| **C14: Monitoring & Lineage (3x)** | 2 (6) | 5 (15) | 5 (15) |
| **TOTAL WEIGHTED SCORE (Max 175)** | **102 / 175** | **166 / 175** | **146 / 175** |
| **RANKING** | **Rank 3** | **Rank 1 (Selected)** | **Rank 2** |

---

## 5. Technology Selection Justification

### Why Option 2 (Python + dbt + PostgreSQL) Won:
1. **First-Class Dependency Management & Lineage:**  
   dbt automatically compiles the dependency graph (`ref('stg_conversions')`), ensuring Silver models never build before Bronze is populated, and Gold facts never run before dimensions exist.
2. **Built-in Quality Assurance as Code:**  
   Rather than writing hundreds of lines of fragile manual test scripts, dbt enables declarative YAML assertions (`not_null`, `unique`, `relationships`) that halt downstream builds if referential integrity is violated.
3. **Native Incremental & SCD Type 2 Snapshots:**  
   dbt provides out-of-the-box incremental strategies (`merge`, `delete+insert`) and snapshot capabilities that perfectly solve the Account Manager SCD-2 requirement and 50,000 duplicate idempotency test.
4. **Developer Ergonomics & Local Performance:**  
   Option 3 (PySpark + Delta Lake) introduces immense JVM overhead, complex local cluster setup, and slow bootstrap latency for sub-million row tables. Option 2 runs natively on PostgreSQL 18 with sub-second response times and zero cloud infrastructure bills.

---

## 6. End-to-End Target Platform Architecture

```
====================================================================================================
                                PULSETRACK DATA PLATFORM LIFECYCLE
====================================================================================================

 [SOURCE TIER]
   +--------------------+     +--------------------+     +--------------------+
   |  11 Relational CSVs |     | MongoDB JSONL CRM  |     | Kafka Stream Log   |
   |  (Funnel & Dims)   |     | (Partners & AMs)   |     | (Real-time Events) |
   +---------+----------+     +---------+----------+     +---------+----------+
             |                          |                          |
             +--------------------------+--------------------------+
                                        |
                                        v
 [INGESTION TIER]             Python 3.11 Extractors (Pandas & DuckDB High-Speed Ingestion)
                                        | (Appends Ingestion Metadata: batch_id, source_file, ingested_at)
                                        v
 [BRONZE LAYER]               Schema: pulsetrack_raw (PostgreSQL 18)
                              - Untyped text staging tables (Exact replica of sources)
                              - Ingestion quarantine tables for malformed stream lines
                                        |
                                        v
 [TRANSFORMATION TIER]        dbt Core 1.12 / PostgreSQL Engine
                                        |
                                        +---> [SILVER LAYER] Schema: pulsetrack_silver
                                        |     - Deduplication: MAX(updated_at) on conversion_id
                                        |     - Cleansing: Currency regex ($ -> numeric), UTC time normalization
                                        |     - Identity Resolution: 5-digit partner prefix + Mongo merge
                                        |     - Filter is_test = TRUE records
                                        |
                                        +---> [GOLD LAYER] Schema: pulsetrack_gold (EDW Star Schema)
                                              - Conformed Dimensions (dim_date, dim_partner, dim_campaign, etc.)
                                              - SCD Type 2 History (dim_advertiser: valid_from, valid_to, is_current)
                                              - Fact Tables (fact_conversion, fact_click, fact_impression, fact_adjustment)
                                              - Multi-Touch Attribution Bridge (bridge_conversion_touchpoint)
                                        |
                                        v
 [SERVING TIER]               Schema: pulsetrack_mart (Departmental Data Marts)
                              - Pre-aggregated snapshot tables (mart_campaign_daily, mart_partner_performance)
                                        |
                                        v
 [OLAP & SEMANTIC TIER]       PostgreSQL Multi-Dimensional Views & Grouping Sets
                              - Slice, Dice, Roll-up, Drill-down, YoY, MoM, QoQ
                                        |
                                        v
 [ANALYTICS & BI TIER]        DataGrip / Power BI / Executive SQL Reporting
                              - 10 Automated Business Decision Queries (Q9)
====================================================================================================
```

---

## 7. Cross-Cutting Enterprise Platform Governance

### 7.1 Orchestration, Scheduling & Dependency Management
* **Engine:** Modular Python Pipeline Orchestrator coordinating ingestion and invoking `dbt run` / `dbt test`.
* **Execution Flow:**
  1. `Extract & Load Bronze` $\to$ 2. `dbt run --select tag:silver` $\to$ 3. `dbt test --select tag:silver` $\to$ 4. `dbt run --select tag:gold` $\to$ 5. `dbt test --select tag:gold` $\to$ 6. `dbt run --select tag:mart`.
* **Failure Handling:** If any data quality test fails in Silver, downstream Gold fact loading is immediately blocked to prevent corrupted metrics from reaching executives.

### 7.2 Audit, Monitoring & Operational Metadata
* **Audit Schema:** `pulsetrack_audit.pipeline_execution_log`
* **Tracked Metrics:** `batch_id`, `pipeline_name`, `source_row_count`, `inserted_count`, `updated_count`, `rejected_count`, `start_time`, `end_time`, `status` (`SUCCESS` / `FAILED`), `error_message`.

### 7.3 Error Handling, Retry & Recovery
* **Idempotent Ingestion:** Raw loads use deterministic staging table replacement (`CREATE UNLOGGED TABLE ...`).
* **Safe Resumption:** If a pipeline fails mid-run after dimension loading, re-running the orchestrator uses `ON CONFLICT DO UPDATE` / dbt incremental merge to safely resume fact loading without duplicating historical records.

### 7.4 Security & Governance
* **PII Redaction / Masking:** Sensitive columns identified in source forensics (`clicks_raw.ip`, `clicks_raw.user_agent`, `partner_profiles.contact.email`) are masked or quarantined in Silver staging.
* **Role-Based Access Control (RBAC):**
  * `pulsetrack_etl`: Full DDL/DML access to Bronze, Silver, Gold, Mart.
  * `pulsetrack_bi`: Read-only `SELECT` access restricted strictly to `pulsetrack_mart` and `pulsetrack_gold` views. Prohibited from querying raw tables directly.

---

## 8. Technology Responsibility Matrix

| Technology Component | Assigned Tool | Specific Operational Responsibility |
| :--- | :--- | :--- |
| **Source File Parsing** | Python 3.11 (`json`, `duckdb`) | Streaming Kafka log parser, MongoDB JSONL flattener, CSV high-speed reader. |
| **Bronze Staging** | PostgreSQL 18 (`pulsetrack_raw`) | Immutable raw landing zone; preserves raw text values with audit columns. |
| **ELT Transformation** | dbt Core 1.12 (`dbt-postgres`) | SQL-based Silver cleaning, deduplication, Gold star schema loading, surrogate key hashing. |
| **SCD Type 2 Engine** | dbt Snapshots / SQL Procedures | Tracking Account Manager reassignments with `valid_from` and `valid_to` timestamps. |
| **Quality Verification** | dbt test + Pytest Suite | Schema assertions, null checks, unique constraints, referential integrity tests. |
| **Data Warehouse** | PostgreSQL 18 (`pulsetrack_gold`) | ACID-compliant Kimball Star Schema storage with B-tree indexes on foreign keys. |
| **Data Mart Serving** | PostgreSQL 18 (`pulsetrack_mart`) | Materialized summary tables optimized for sub-second executive BI queries. |
| **Semantic & OLAP Layer**| SQL Grouping Sets / Window Views | Cube hierarchies (Year $\to$ Month $\to$ Day), Slice & Dice, MoM / YoY calculations. |
| **Platform Exploration** | JetBrains DataGrip | Schema visualization, query execution plans, and interactive data profiling. |
