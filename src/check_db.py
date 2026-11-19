import psycopg2
import subprocess

print("Checking PostgreSQL service status...")
try:
    res = subprocess.run(["sc", "query", "postgresql-x64-18"], capture_output=True, text=True)
    if "RUNNING" in res.stdout:
        print("PostgreSQL 18 service is RUNNING!")
    else:
        print("PostgreSQL service output:\n", res.stdout)
except Exception as e:
    print("Could not query sc:", e)

passwords_to_try = ['', 'postgres', 'admin', 'root', '1234', 'password', '123456']
connected = False
for pwd in passwords_to_try:
    try:
        conn = psycopg2.connect(host='localhost', port=5432, user='postgres', password=pwd, connect_timeout=3)
        print(f"SUCCESS: Connected to PostgreSQL with password: '{pwd}'")
        conn.close()
        connected = True
        break
    except Exception as e:
        last_error = e

if not connected:
    print("Could not connect with tested passwords. Last error:", last_error)
