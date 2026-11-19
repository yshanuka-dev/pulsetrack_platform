import psycopg2
from config import get_admin_connection, get_connection, DB_NAME

def init_db():
    print(f"Ensuring database '{DB_NAME}' exists...")
    admin_conn = get_admin_connection()
    cur = admin_conn.cursor()
    cur.execute(f"SELECT 1 FROM pg_database WHERE datname = '{DB_NAME}';")
    exists = cur.fetchone()
    if not exists:
        cur.execute(f"CREATE DATABASE {DB_NAME};")
        print(f"Created database '{DB_NAME}'.")
    else:
        print(f"Database '{DB_NAME}' already exists.")
    cur.close()
    admin_conn.close()

    print("Initializing schemas and audit infrastructure...")
    conn = get_connection()
    cur = conn.cursor()
    
    # Create schemas
    schemas = ["pulsetrack_raw", "pulsetrack_silver", "pulsetrack_gold", "pulsetrack_mart", "pulsetrack_audit"]
    for s in schemas:
        cur.execute(f"CREATE SCHEMA IF NOT EXISTS {s};")
        print(f"  Schema '{s}' verified.")

    # Audit tables
    cur.execute("""
        CREATE TABLE IF NOT EXISTS pulsetrack_audit.pipeline_execution_log (
            log_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            batch_id VARCHAR(64) NOT NULL,
            pipeline_name VARCHAR(128) NOT NULL,
            layer VARCHAR(32) NOT NULL,
            source_row_count BIGINT DEFAULT 0,
            inserted_count BIGINT DEFAULT 0,
            updated_count BIGINT DEFAULT 0,
            rejected_count BIGINT DEFAULT 0,
            status VARCHAR(32) NOT NULL,
            start_time TIMESTAMPTZ NOT NULL,
            end_time TIMESTAMPTZ,
            error_message TEXT
        );

        CREATE TABLE IF NOT EXISTS pulsetrack_audit.quarantine_stream_lines (
            quarantine_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            line_number BIGINT NOT NULL,
            raw_text TEXT NOT NULL,
            reason VARCHAR(255) NOT NULL,
            quarantined_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
        );
    """)
    conn.commit()
    cur.close()
    conn.close()
    print("Database & audit tables initialized successfully!")

if __name__ == "__main__":
    init_db()
