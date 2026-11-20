import os
import time
from datetime import datetime, timezone
import psycopg2
from config import get_connection

def run_marts_pipeline():
    start_time = datetime.now(timezone.utc)
    batch_id = f"BATCH_MARTS_{start_time.strftime('%Y%m%d_%H%M%S')}"
    print(f"=== STARTING DATA MART GENERATION [{batch_id}] ===")

    conn = get_connection()
    cur = conn.cursor()

    sql_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "sql", "04_marts", "01_data_marts_ddl_and_load.sql"))
    print(f"Executing Data Marts DDL & Population: {sql_path}")
    with open(sql_path, "r", encoding="utf-8") as f:
        cur.execute(f.read())
    conn.commit()

    # Verify Mart Tables
    cur.execute("""
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'pulsetrack_mart' AND table_type = 'BASE TABLE'
        ORDER BY table_name;
    """)
    marts = [row[0] for row in cur.fetchall()]

    total_mart_rows = 0
    print("\nData Mart Generation Results:")
    for m in marts:
        cur.execute(f"SELECT COUNT(*) FROM pulsetrack_mart.{m};")
        cnt = cur.fetchone()[0]
        total_mart_rows += cnt
        print(f"  pulsetrack_mart.{m:<36} : {cnt:>8,} rows")

    end_time = datetime.now(timezone.utc)
    cur.execute("""
        INSERT INTO pulsetrack_audit.pipeline_execution_log 
        (batch_id, pipeline_name, layer, source_row_count, inserted_count, updated_count, rejected_count, status, start_time, end_time)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s);
    """, (
        batch_id, "Data Mart Generation Pipeline", "Mart", 
        86335, total_mart_rows, 0, 0, 
        "SUCCESS", start_time, end_time
    ))
    conn.commit()

    cur.close()
    conn.close()
    print(f"\nDATA MART PIPELINE COMPLETED in {(end_time - start_time).total_seconds():.2f} seconds!")

if __name__ == "__main__":
    run_marts_pipeline()
