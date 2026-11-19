import os
import psycopg2
from sqlalchemy import create_engine

# Database Connection Settings
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = int(os.getenv("DB_PORT", 5432))
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")
DB_NAME = os.getenv("DB_NAME", "pulsetrack_dw")

# Project Directories
BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW_DATA_DIR = os.path.join(BASE_DIR, "DE01Capstone", "data")
MONGO_DATA_DIR = os.path.join(BASE_DIR, "DE01Capstone", "mongo")
STREAM_DATA_DIR = os.path.join(BASE_DIR, "DE01Capstone", "stream")

def get_admin_connection():
    """Connect to default postgres database to manage databases."""
    conn = psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        dbname="postgres"
    )
    conn.autocommit = True
    return conn

def get_connection():
    """Connect to the pulsetrack_dw database."""
    conn = psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        dbname=DB_NAME
    )
    conn.autocommit = False
    return conn

def get_engine():
    """Get SQLAlchemy Engine for pulsetrack_dw."""
    url = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
    return create_engine(url)
