from a2wsgi import ASGIMiddleware
from main import app  # FastAPI app

# adapter wraps the ASGI app into a WSGI callable
application = ASGIMiddleware(app)