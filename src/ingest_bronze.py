import os
import glob
import json
import time
from datetime import datetime, timezone
import psycopg2
import duckdb
from config import get_connection, RAW_DATA_DIR, MONGO_DATA_DIR, STREAM_DATA_DIR, DB_NAME, DB_HOST, DB_PORT, DB_USER, DB_PASSWORD

def run_bronze_ingestion():
    batch_id = f"BATCH_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"
    start_time = datetime.now(timezone.utc)
    print(f"=== STARTING BRONZE INGESTION [{batch_id}] ===")
    
    conn = get_connection()
    cur = conn.cursor()

    # Step 1: Run DDL
    ddl_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "sql", "01_bronze", "01_bronze_ddl.sql"))
    print(f"Executing Bronze DDL: {ddl_path}")
    with open(ddl_path, "r", encoding="utf-8") as f:
        cur.execute(f.read())
    conn.commit()

    total_source_records = 0
    total_inserted = 0

    # Step 2: Load 11 Relational CSVs using PostgreSQL COPY
    csv_files = glob.glob(os.path.join(RAW_DATA_DIR, "*.csv"))
    print(f"Found {len(csv_files)} CSV files in {RAW_DATA_DIR}")

    # Use duckdb to export CSVs with metadata into temporary buffers or direct copy
    duck_con = duckdb.connect()

    for csv_file in sorted(csv_files):
        table_name = os.path.basename(csv_file).replace(".csv", "")
        file_name = os.path.basename(csv_file)
        
        # Read with duckdb to append batch_id and source_file cleanly
        df = duck_con.execute(f"""
            SELECT *, 
                   '{batch_id}' as _batch_id, 
                   '{file_name}' as _source_file, 
                   CURRENT_TIMESTAMP as _ingested_at
            FROM read_csv('{csv_file}', all_varchar=True, header=True)
        """).df()

        row_count = len(df)
        total_source_records += row_count

        # Write to in-memory CSV buffer for ultra-fast COPY
        import io
        buf = io.StringIO()
        df.to_csv(buf, index=False, header=False, sep='\t', na_rep='\\N')
        buf.seek(0)

        cols = [f'"{col}"' for col in df.columns]
        copy_sql = f"COPY pulsetrack_raw.{table_name} ({', '.join(cols)}) FROM STDIN WITH (FORMAT text, NULL '\\N')"
        cur.copy_expert(copy_sql, buf)
        conn.commit()

        total_inserted += row_count
        print(f"  -> Ingested {row_count:>7} rows into pulsetrack_raw.{table_name}")

    # Step 3: Load MongoDB JSONL files
    print("\nLoading MongoDB CRM collections...")
    
    # Partner Profiles
    partner_file = os.path.join(MONGO_DATA_DIR, "partner_profiles.jsonl")
    partner_rows = []
    with open(partner_file, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                doc = json.loads(line)
                partner_id = str(doc.get("partner_id", ""))
                name = doc.get("name", "")
                partner_rows.append((partner_id, name, line.strip(), batch_id))
    
    cur.executemany("""
        INSERT INTO pulsetrack_raw.raw_mongo_partner_profiles 
        (partner_id, partner_name, doc_json, _batch_id) 
        VALUES (%s, %s, %s, %s)
    """, partner_rows)
    conn.commit()
    total_source_records += len(partner_rows)
    total_inserted += len(partner_rows)
    print(f"  -> Ingested {len(partner_rows):>7} docs into pulsetrack_raw.raw_mongo_partner_profiles")

    # Advertiser Accounts
    adv_file = os.path.join(MONGO_DATA_DIR, "advertiser_accounts.jsonl")
    adv_rows = []
    with open(adv_file, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                doc = json.loads(line)
                adv_id = str(doc.get("advertiser_id", ""))
                legal_name = doc.get("legal_name", "")
                display_name = doc.get("display_name", "")
                adv_rows.append((adv_id, legal_name, display_name, line.strip(), batch_id))
    
    cur.executemany("""
        INSERT INTO pulsetrack_raw.raw_mongo_advertiser_accounts 
        (advertiser_id, legal_name, display_name, doc_json, _batch_id) 
        VALUES (%s, %s, %s, %s, %s)
    """, adv_rows)
    conn.commit()
    total_source_records += len(adv_rows)
    total_inserted += len(adv_rows)
    print(f"  -> Ingested {len(adv_rows):>7} docs into pulsetrack_raw.raw_mongo_advertiser_accounts")

    # Step 4: Load Kafka Stream Log & Quarantine Malformed Lines
    print("\nLoading Kafka Conversion Stream log & applying defensive quarantine...")
    stream_file = os.path.join(STREAM_DATA_DIR, "pulsetrack_conversions.log")
    
    valid_stream_records = []
    quarantined_records = []
    line_num = 0

    with open(stream_file, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line_num += 1
            raw_str = line.strip()
            if not raw_str:
                continue
            
            parts = raw_str.split("|")
            if len(parts) < 6:
                quarantined_records.append((line_num, raw_str, "Truncated/Malformed envelope parts < 6"))
                continue
            
            topic = parts[0]
            partition = int(parts[1].split("=")[1])
            offset_val = int(parts[2].split("=")[1])
            ts_epoch = int(parts[3].split("=")[1])
            event_key = parts[4].split("=")[1]
            payload_json = parts[5]

            # Validate json payload
            try:
                json.loads(payload_json)
                valid_stream_records.append((topic, partition, offset_val, ts_epoch, event_key, payload_json, batch_id))
            except Exception as e:
                quarantined_records.append((line_num, raw_str, f"Malformed JSON: {str(e)}"))

    # Bulk insert valid stream events using COPY
    import io
    stream_buf = io.StringIO()
    for rec in valid_stream_records:
        # topic \t partition \t offset \t ts \t key \t payload \t batch_id
        # Escape newlines or tabs in payload
        payload_clean = rec[5].replace('\t', ' ').replace('\n', ' ')
        stream_buf.write(f"{rec[0]}\t{rec[1]}\t{rec[2]}\t{rec[3]}\t{rec[4]}\t{payload_clean}\t{rec[6]}\n")
    stream_buf.seek(0)
    
    cur.copy_expert("""
        COPY pulsetrack_raw.raw_kafka_conversions_stream 
        (topic, partition, offset_val, ts_epoch, event_key, payload_json, _batch_id) 
        FROM STDIN WITH (FORMAT text, NULL '\\N')
    """, stream_buf)
    conn.commit()

    # Insert quarantined lines
    if quarantined_records:
        cur.executemany("""
            INSERT INTO pulsetrack_audit.quarantine_stream_lines 
            (line_number, raw_text, reason) 
            VALUES (%s, %s, %s)
        """, quarantined_records)
        conn.commit()

    total_source_records += line_num
    total_inserted += len(valid_stream_records)
    print(f"  -> Ingested {len(valid_stream_records):>7} valid events into pulsetrack_raw.raw_kafka_conversions_stream")
    print(f"  -> Quarantined {len(quarantined_records):>5} malformed lines into pulsetrack_audit.quarantine_stream_lines")

    # Step 5: Log to Audit Table
    end_time = datetime.now(timezone.utc)
    cur.execute("""
        INSERT INTO pulsetrack_audit.pipeline_execution_log 
        (batch_id, pipeline_name, layer, source_row_count, inserted_count, updated_count, rejected_count, status, start_time, end_time) 
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """, (
        batch_id, "Bronze Ingestion Pipeline", "Bronze", 
        total_source_records, total_inserted, 0, len(quarantined_records), 
        "SUCCESS", start_time, end_time
    ))
    conn.commit()

    cur.close()
    conn.close()
    print(f"\nBRONZE INGESTION COMPLETED in {(end_time - start_time).total_seconds():.2f} seconds!")
    print(f"Total Source Rows: {total_source_records:,} | Total Inserted: {total_inserted:,} | Quarantined: {len(quarantined_records)}")

if __name__ == "__main__":
    run_bronze_ingestion()
