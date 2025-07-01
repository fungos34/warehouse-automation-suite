from fastapi import APIRouter
import os
from fastapi.responses import HTMLResponse

router = APIRouter()

# Serve index.html at the root URL
@router.get("/", response_class=HTMLResponse, tags=["Frontend"])
def serve_index():
    static_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "static"))
    with open(os.path.join(static_dir, "index.html"), encoding="utf-8") as f:
        return f.read()