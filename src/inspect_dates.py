import duckdb

con = duckdb.connect()
res = con.execute("""
    SELECT click_id, click_time 
    FROM read_csv('DE01Capstone/data/clicks_raw.csv', all_varchar=True) 
    WHERE click_id IN ('CLK00000018', 'CLK00000001', 'CLK00000002')
""").fetchall()
print("Sample click_times:", res)

# Check all distinct formats of click_time in clicks_raw
formats = con.execute("""
    SELECT 
        CASE 
            WHEN click_time IS NULL OR click_time = '' THEN 'NULL/EMPTY'
            WHEN click_time ~ '^[0-9]{10}$' THEN '10-digit epoch'
            WHEN click_time ~ '^[0-9]{13}$' THEN '13-digit epoch'
            WHEN click_time ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}' THEN 'YYYY-MM-DD...'
            WHEN click_time ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}' THEN 'MM/DD/YYYY...'
            WHEN click_time ~ '^[0-9]{2}-[0-9]{2}-[0-9]{4}' THEN 'DD-MM-YYYY...'
            ELSE 'OTHER: ' || SUBSTRING(click_time, 1, 20)
        END as fmt,
        COUNT(*) as cnt,
        MIN(click_time) as sample
    FROM read_csv('DE01Capstone/data/clicks_raw.csv', all_varchar=True)
    GROUP BY 1
    ORDER BY cnt DESC
""").fetchall()
print("\nClick time formats:")
for f in formats:
    print(f"  {f[0]:<25} : {f[1]:>8} rows (Sample: {f[2]})")
