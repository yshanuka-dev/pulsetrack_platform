# PulseTrack Apache Airflow Orchestration Suite

This directory contains the production **Apache Airflow** orchestration DAGs for the PulseTrack Enterprise Data Warehouse.

---

## 🏗 Architecture & DAG Lineage

The master orchestration DAG [`pulsetrack_medallion_pipeline_dag.py`](./dags/pulsetrack_medallion_pipeline_dag.py) enforces strict linear Medallion dependency:

```text
[start_pipeline]
       │
       ▼
[init_warehouse_schemas]
       │
       ▼
[ingest_bronze_raw]               (CSV, MongoDB JSONL, Kafka log)
       │
       ▼
[cleanse_silver_staging]          (Deduplication ROW_NUMBER()=1, currency parsing)
       │
       ▼
[build_gold_star_schema]          (SCD Type 2 dim_advertiser, fact tables, attribution bridge)
       │
       ▼
[build_departmental_marts]        (mart_campaign_performance_daily, mart_partner_attribution)
       │
       ▼
[verify_data_quality_and_reconciliation] (Automated DQ gates & Cross-Layer Ledger)
       │
       ▼
[end_pipeline]
```

---

## 🚀 How to Run in Airflow

### Option 1: Running in Local Airflow
If you have Apache Airflow installed locally:
```bash
# Point Airflow to this DAGs folder
export AIRFLOW__CORE__DAGS_FOLDER=$(pwd)/airflow/dags

# Initialize Airflow DB (if not already done)
airflow db init

# Unpause and trigger the DAG
airflow dags unpause pulsetrack_medallion_pipeline
airflow dags trigger pulsetrack_medallion_pipeline
```

### Option 2: Running via Docker Compose (Same as Week 08 / 09)
Mount this repository into the Airflow container:
```yaml
volumes:
  - ./airflow/dags:/opt/airflow/dags
  - ./src:/opt/airflow/src
  - ./sql:/opt/airflow/sql
```
And trigger `pulsetrack_medallion_pipeline` from the Airflow Web UI at `http://localhost:8080`.
