# PulseTrack Enterprise Data Platform & Warehouse

End-to-End Analytical Data Platform Capstone Solution for **PulseTrack** (Performance-Marketing Network).

---

## 📁 Repository Structure

```text
pulsetrack_platform/
├── sql/                                # Database definitions & transformations
│   ├── 01_bronze/                      # Untyped staging DDLs and ingestion metadata
│   ├── 02_silver/                      # Cleansing, deduplication, standardisation views/tables
│   ├── 03_gold/                        # Enterprise Star Schema (Dims, Facts, Bridges, SCD Type 2)
│   ├── 04_marts/                       # Aggregated Departmental Data Marts
│   └── 05_analytics/                   # 10 Executive Business Queries & OLAP operations
│
├── src/                                # Production Python ETL/ELT pipelines
│   ├── config.py                       # Database connection parameters & project paths
│   ├── ingest_bronze.py                # Bronze loader (CSV, MongoDB JSONL, Kafka log)
│   ├── build_silver.py                 # Silver cleansing, regex parsing, key reconciliation
│   ├── build_gold.py                   # Gold Star Schema & SCD-2 dimensional loader
│   ├── build_marts.py                  # Mart aggregations & OLAP views
│   ├── late_adjustments.py             # Incremental processing, idempotency & late revenue
│   └── data_quality.py                 # Automated DQ test gates & Source-to-Gold ledger
│
├── docs/                               # Assessment Deliverables (Questions 1 - 10)
│   ├── Q1_Requirements_and_KPIs.md     # Business KPIs, grain specs, freshness SLAs
│   ├── Q2_Source_Forensics_and_EDW.md  # Forensic report, Star Schema, SCD-2 specs
│   ├── Q3_Technology_Decision_Record.md# Architecture evaluation & tool selection
│   ├── Q6_Audit_and_Reconciliation.md  # Quality gates, audit schema, reconciliation proof
│   ├── Q8_OLAP_Semantic_Model.md       # Cube definitions, hierarchies, measures
│   ├── Q9_Business_Analytics.md        # Answers to 10 executive business questions
│   └── Q10_Production_Defense.md       # Lead Data Engineer architectural defense
│
├── tests/                              # Automated tests (idempotency, DQ, reconciliation)
└── requirements.txt                    # Project Python dependencies
```

---

## 🛠 Technology Stack
* **Warehouse Engine:** PostgreSQL 18
* **Database IDE:** DataGrip
* **Processing & Ingestion:** Python 3.11 (`pandas`, `duckdb`, `psycopg2`, `sqlalchemy`)
* **Target Architecture:** Medallion Pattern (Bronze → Silver → Gold EDW → Data Mart → OLAP)
