from asgi2wsgi import asgi2wsgi
from main import app  # FastAPI app

# adapter wraps the ASGI app into a WSGI callable
application = asgi2wsgi(app)