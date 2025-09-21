import os
from urllib.parse import urlparse
from dotenv import load_dotenv

load_dotenv()
stripe_api_key = os.environ.get("STRIPE_API_KEY")
endpoint_secret = os.environ.get("ENDPOINT_SECRET")
shippo_api_key = os.environ.get("SHIPPO_API_KEY")
base_url = os.environ.get("BASE_URL")
parsed = urlparse(base_url)
host = parsed.hostname or "0.0.0.0"
port = parsed.port or 8000

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host=host, port=port, reload=True)