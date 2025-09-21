import os
import sqlite3
from dotenv import load_dotenv

# Resolve project root and load .env early so WAREHOUSE_DB_PATH is available
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(PROJECT_ROOT, ".env"))

def _resolve_path(path_or_none, default_relative):
    if path_or_none:
        path = os.path.expanduser(path_or_none)
    else:
        path = os.path.join(PROJECT_ROOT, default_relative)
    if not os.path.isabs(path):
        path = os.path.join(PROJECT_ROOT, path)
    return os.path.abspath(path)

# DB and schema paths (can be overridden via environment variables)
DB_PATH = _resolve_path(os.environ.get("WAREHOUSE_DB_PATH"), os.path.join("data", "warehouse.db"))
SCHEMA_PATH = _resolve_path(os.environ.get("SCHEMA_PATH"), "schema.sql")

def initialize_database():
    if not os.path.exists(DB_PATH):
        print("Creating new SQLite database from schema.sql...")
        os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
        with sqlite3.connect(DB_PATH) as conn, open(SCHEMA_PATH, "r", encoding="utf-8") as f:
            conn.executescript(f.read())
        print("Database initialized at:", DB_PATH)

def get_conn():
    # Use check_same_thread=False for web servers that may use threads;
    # set row_factory and useful pragmas.
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON;")
    conn.execute("PRAGMA recursive_triggers = ON;")
    return conn