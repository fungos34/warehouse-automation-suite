import os
import logging
from dotenv import load_dotenv

# ensure .env is loaded very early so other modules can read env vars
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(PROJECT_ROOT, ".env"))

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from api import (
    sales_router,
    purchase_router,
    returns_router,
    warehouse_router,
    users_router,
    partners_router,
    frontend_router,
)

# import DB helpers for diagnostics only; avoid initializing DB automatically on import
from database import DB_PATH, initialize_database

app = FastAPI(title="Warehouse Management API")

# Mount static files using an absolute path (works both locally and on PythonAnywhere)
STATIC_DIR = os.path.join(PROJECT_ROOT, "static")
if os.path.isdir(STATIC_DIR):
    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

# Include routers (order: frontend first so root routes resolve)
app.include_router(frontend_router)
app.include_router(sales_router)
app.include_router(purchase_router)
app.include_router(returns_router)
app.include_router(warehouse_router)
app.include_router(users_router)
app.include_router(partners_router)


@app.on_event("startup")
def _on_startup():
    """
    Run lightweight startup tasks.

    IMPORTANT:
    - We deliberately do NOT initialize the full DB schema here by default,
      because creating the schema at import/startup can delay the first request
      and may cause permission/locking issues under WSGI environments.
    - If you want the process to create the DB automatically on startup, set
      environment variable INIT_DB_ON_STARTUP=true in your PythonAnywhere Web tab
      or your local environment. Otherwise run scripts/init_db.py once manually.
    """
    logging.info("Application startup. DB_PATH=%s", DB_PATH)
    if os.environ.get("INIT_DB_ON_STARTUP", "false").lower() in ("1", "true", "yes"):
        logging.info("INIT_DB_ON_STARTUP is set — initializing database from schema.sql")
        initialize_database()
    else:
        logging.info("Skipping automatic DB initialization on startup")