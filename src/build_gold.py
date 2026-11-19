import os
import time
from datetime import datetime, timezone
import psycopg2
from config import get_connection

def run_gold_pipeline():
    start_time = datetime.now(timezone.utc)
    batch_id = f"BATCH_GOLD_{start_time.strftime('%Y%m%d_%H%M%S')}"
    print(f"=== STARTING GOLD DIMENSIONAL PIPELINE [{batch_id}] ===")

    conn = get_connection()
    cur = conn.cursor()

    # Step 1: Ensure DDL exists
    ddl_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "sql", "03_gold", "01_gold_star_schema_ddl.sql"))
    print(f"Verifying Gold DDL: {ddl_path}")
    with open(ddl_path, "r", encoding="utf-8") as f:
        cur.execute(f.read())
    conn.commit()

    # Step 2: Populate Gold Star Schema
    load_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "sql", "03_gold", "02_load_gold_star_schema.sql"))
    print(f"Executing Gold Dimensional Loader: {load_path}")
    with open(load_path, "r", encoding="utf-8") as f:
        cur.execute(f.read())
    conn.commit()

    # Step 3: Check Gold Layer Table Counts
    cur.execute("""
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'pulsetrack_gold' AND table_type = 'BASE TABLE'
        ORDER BY table_name;
    """)
    tables = [row[0] for row in cur.fetchall()]
    
    total_gold_rows = 0
    print("\nGold Layer Population Results:")
    for t in tables:
        cur.execute(f"SELECT COUNT(*) FROM pulsetrack_gold.{t};")
        cnt = cur.fetchone()[0]
        total_gold_rows += cnt
        print(f"  pulsetrack_gold.{t:<32} : {cnt:>8,} rows")

    # Audit logging
    end_time = datetime.now(timezone.utc)
    cur.execute("""
        INSERT INTO pulsetrack_audit.pipeline_execution_log 
        (batch_id, pipeline_name, layer, source_row_count, inserted_count, updated_count, rejected_count, status, start_time, end_time) 
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """, (
        batch_id, "Gold Star Schema Pipeline", "Gold", 
        total_gold_rows, total_gold_rows, 0, 0, 
        "SUCCESS", start_time, end_time
    ))
    conn.commit()

    cur.close()
    conn.close()
    print(f"\nGOLD PIPELINE COMPLETED in {(end_time - start_time).total_seconds():.2f} seconds!")

if __name__ == "__main__":
    run_gold_pipeline()
