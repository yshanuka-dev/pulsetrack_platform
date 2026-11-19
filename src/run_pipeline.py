import time
from datetime import datetime, timezone
from init_database import init_db
from ingest_bronze import run_bronze_ingestion
from build_silver import run_silver_pipeline
from build_gold import run_gold_pipeline

def run_full_pipeline():
    total_start = datetime.now(timezone.utc)
    print("====================================================================")
    print("      PULSETRACK ENTERPRISE DATA WAREHOUSE PIPELINE RUNNER          ")
    print(f"      Execution Started at: {total_start.strftime('%Y-%m-%d %H:%M:%S UTC')}")
    print("====================================================================\n")

    # Step 0: Ensure database & schemas exist
    init_db()

    # Step 1: Bronze Ingestion
    run_bronze_ingestion()

    # Step 2: Silver Cleansing & Deduplication
    run_silver_pipeline()

    # Step 3: Gold Star Schema Population (with SCD-2 & Bridge)
    run_gold_pipeline()

    total_end = datetime.now(timezone.utc)
    duration = (total_end - total_start).total_seconds()
    print("\n====================================================================")
    print(f"      FULL END-TO-END PIPELINE COMPLETED IN {duration:.2f} SECONDS!  ")
    print("====================================================================")

if __name__ == "__main__":
    run_full_pipeline()
