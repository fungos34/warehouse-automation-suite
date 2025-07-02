# main.py
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from api import sales_router, purchase_router, returns_router, warehouse_router, users_router, partners_router, frontend_router
from contextlib import asynccontextmanager
from database import initialize_database
from dotenv import load_dotenv

load_dotenv()  # loads environmental variables from .env file

@asynccontextmanager
async def lifespan(app: FastAPI):
    initialize_database()
    yield

app = FastAPI(
    lifespan=lifespan,
    )

# Serve static files (css, js, images, etc.)
app.mount("/static", StaticFiles(directory="static"), name="static")


app.include_router(sales_router)
app.include_router(purchase_router)
app.include_router(returns_router)
app.include_router(warehouse_router)
app.include_router(users_router)
app.include_router(partners_router)
app.include_router(frontend_router)