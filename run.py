import os
from urllib.parse import urlparse
from dotenv import load_dotenv

load_dotenv()
stripe_api_key = os.environ.get("STRIPE_API_KEY")
endpoint_secret = os.environ.get("ENDPOINT_SECRET")
base_url = os.environ.get("BASE_URL")
parsed = urlparse(base_url)
host = parsed.hostname or "0.0.0.0"
port = parsed.port or 8000

import uvicorn

if __name__ == "__main__":
    uvicorn.run("main:app", host=host, port=port, reload=True)