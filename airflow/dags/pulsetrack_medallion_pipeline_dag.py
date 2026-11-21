"""
pulsetrack_medallion_pipeline_dag.py
====================================
PulseTrack Enterprise Data Warehouse — Master Medallion Orchestration DAG
Author: Lead Data Engineer / ZuuCrew DWDF Capstone
Schedule: Daily @ 02:00 UTC (0 2 * * *)

This DAG orchestrates the end-to-end Medallion analytical pipeline:
  [Source Data: CSV, Mongo JSONL, Kafka log]
         │
         ▼
  1. Bronze Ingestion (Raw landing + metadata)
         │
         ▼
  2. Silver Cleansing & Deduplication (Regex parsing, currency strip, ROW_NUMBER() = 1)
         │
         ▼
  3. Gold Enterprise Data Warehouse (SCD Type 2 Dim_Advertiser, Kimball Star Schema, Attribution Bridge)
         │
         ▼
  4. Departmental Data Marts & Semantic OLAP Views (Aggregated campaign, partner & AM performance)
         │
         ▼
  5. Automated Data Quality Gate & Cross-Layer Reconciliation Ledger
"""

import sys
import os
from datetime import datetime, timedelta

# Ensure src/ directory is accessible to Airflow workers
SRC_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src"))
if SRC_PATH not in sys.path:
    sys.path.insert(0, SRC_PATH)

try:
    from airflow import DAG
    from airflow.operators.empty import EmptyOperator
    from airflow.operators.python import PythonOperator
except ImportError:
    # Fallback for environments running standalone Python without Airflow runtime loaded
    class EmptyOperator:
        def __init__(self, task_id, **kwargs):
            self.task_id = task_id
    class PythonOperator:
        def __init__(self, task_id, python_callable, **kwargs):
            self.task_id = task_id
            self.python_callable = python_callable
    class DAG:
        def __init__(self, dag_id, **kwargs):
            self.dag_id = dag_id

# ── Pipeline Task Callables ──────────────────────────────────────────────────

def task_init_db():
    from init_database import init_db
    print("Executing Task: Database Schema Initialization...")
    init_db()

def task_bronze_ingestion():
    from ingest_bronze import run_bronze_ingestion
    print("Executing Task: Bronze Raw Ingestion (CSV, Mongo JSONL, Kafka)...")
    run_bronze_ingestion()

def task_silver_cleansing():
    from build_silver import run_silver_pipeline
    print("Executing Task: Silver Cleansing, Deduplication & Type Casting...")
    run_silver_pipeline()

def task_gold_star_schema():
    from build_gold import run_gold_pipeline
    print("Executing Task: Gold Star Schema & SCD-2 Dimensional Population...")
    run_gold_pipeline()

def task_build_marts():
    from build_marts import run_marts_pipeline
    print("Executing Task: Departmental Data Mart Aggregation...")
    run_marts_pipeline()

def task_data_quality_gates():
    from data_quality import run_data_quality_suite
    print("Executing Task: Automated Data Quality Gates & Reconciliation Ledger...")
    run_data_quality_suite()


# ── DAG Default Arguments ────────────────────────────────────────────────────

default_args = {
    'owner': 'zuucrew_de_lead',
    'depends_on_past': False,
    'email': ['alerts@pulsetrack.io'],
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

# ── DAG Definition ───────────────────────────────────────────────────────────

dag = DAG(
    dag_id='pulsetrack_medallion_pipeline',
    default_args=default_args,
    description='PulseTrack End-to-End Medallion Pipeline (Bronze -> Silver -> Gold -> Marts -> DQ)',
    schedule_interval='0 2 * * *',  # Daily @ 02:00 UTC
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=['pulsetrack', 'capstone', 'medallion', 'scd2', 'gold', 'marts'],
)

# ── Task Definitions ─────────────────────────────────────────────────────────

start_node = EmptyOperator(
    task_id='start_pipeline',
    dag=dag,
)

init_schemas_task = PythonOperator(
    task_id='init_warehouse_schemas',
    python_callable=task_init_db,
    dag=dag,
)

bronze_ingest_task = PythonOperator(
    task_id='ingest_bronze_raw',
    python_callable=task_bronze_ingestion,
    dag=dag,
)

silver_cleanse_task = PythonOperator(
    task_id='cleanse_silver_staging',
    python_callable=task_silver_cleansing,
    dag=dag,
)

gold_edw_task = PythonOperator(
    task_id='build_gold_star_schema',
    python_callable=task_gold_star_schema,
    dag=dag,
)

marts_aggregate_task = PythonOperator(
    task_id='build_departmental_marts',
    python_callable=task_build_marts,
    dag=dag,
)

quality_reconcile_task = PythonOperator(
    task_id='verify_data_quality_and_reconciliation',
    python_callable=task_data_quality_gates,
    dag=dag,
)

end_node = EmptyOperator(
    task_id='end_pipeline',
    dag=dag,
)

# ── Task Dependencies (Strict Medallion Lineage) ─────────────────────────────

start_node >> init_schemas_task >> bronze_ingest_task >> silver_cleanse_task >> gold_edw_task >> marts_aggregate_task >> quality_reconcile_task >> end_node
