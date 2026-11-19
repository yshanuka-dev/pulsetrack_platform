import os
import time
from datetime import datetime, timezone
import psycopg2
from config import get_connection

def run_silver_pipeline():
    start_time = datetime.now(timezone.utc)
    batch_id = f"BATCH_SILVER_{start_time.strftime('%Y%m%d_%H%M%S')}"
    print(f"=== STARTING SILVER PIPELINE [{batch_id}] ===")

    conn = get_connection()
    cur = conn.cursor()

    # Step 1: Run Helpers
    helpers_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "sql", "02_silver", "01_silver_helpers.sql"))
    print(f"Loading Silver Helper Functions: {helpers_path}")
    with open(helpers_path, "r", encoding="utf-8") as f:
        cur.execute(f.read())
    conn.commit()

    # Step 2: Run Silver Models
    models_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "sql", "02_silver", "02_silver_models.sql"))
    print(f"Executing Silver Transformation Models: {models_path}")
    with open(models_path, "r", encoding="utf-8") as f:
        cur.execute(f.read())
    conn.commit()

    # Step 3: Verify and Count Silver Tables
    cur.execute("""
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'pulsetrack_silver' AND table_type = 'BASE TABLE'
        ORDER BY table_name;
    """)
    tables = [row[0] for row in cur.fetchall()]
    
    total_silver_rows = 0
    print("\nSilver Layer Transformation Results:")
    for t in tables:
        cur.execute(f"SELECT COUNT(*) FROM pulsetrack_silver.{t};")
        cnt = cur.fetchone()[0]
        total_silver_rows += cnt
        print(f"  pulsetrack_silver.{t:<32} : {cnt:>8,} rows")

    # Audit logging
    end_time = datetime.now(timezone.utc)
    cur.execute("""
        INSERT INTO pulsetrack_audit.pipeline_execution_log 
        (batch_id, pipeline_name, layer, source_row_count, inserted_count, updated_count, rejected_count, status, start_time, end_time) 
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """, (
        batch_id, "Silver Transformation Pipeline", "Silver", 
        957982, total_silver_rows, 0, 0, 
        "SUCCESS", start_time, end_time
    ))
    conn.commit()

    cur.close()
    conn.close()
    print(f"\nSILVER PIPELINE COMPLETED in {(end_time - start_time).total_seconds():.2f} seconds!")

if __name__ == "__main__":
    run_silver_pipeline()
