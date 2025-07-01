import os
import sqlite3

DB_PATH = "warehouse.db"
SCHEMA_PATH = "schema.sql"

def initialize_database():
    if not os.path.exists(DB_PATH):
        print("Creating new SQLite database from schema.sql...")
        with sqlite3.connect(DB_PATH) as conn:
            with open(SCHEMA_PATH, 'r') as f:
                conn.executescript(f.read())
        print("Database initialized.")

def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA recursive_triggers = ON;")
    return conn