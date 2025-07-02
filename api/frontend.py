from fastapi import APIRouter
import os
from fastapi.responses import HTMLResponse, FileResponse


router = APIRouter()

# Serve index.html at the root URL
@router.get("/", response_class=HTMLResponse, tags=["Frontend"])
def serve_index():
    static_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "static"))
    with open(os.path.join(static_dir, "index.html"), encoding="utf-8") as f:
        return f.read()
    

@router.get("/shop", response_class=HTMLResponse)
async def shop_page():
    return FileResponse("static/shop.html")
    
@router.get("/shop/{order_number}/success", response_class=HTMLResponse)
async def shop_success(order_number: str, session_id: str = None):
    # Optionally, you can verify payment/session here
    html = f"""
    <html>
    <head><title>Payment Success</title></head>
    <body>
        <h2>Thank you for your purchase!</h2>
        <p>Your order <b>{order_number}</b> has been paid successfully.</p>
        <a href="/shop/{order_number}/">Back to Shop</a>
    </body>
    </html>
    """
    return HTMLResponse(content=html)

@router.get("/shop/{order_number}/cancel", response_class=HTMLResponse)
async def shop_cancel(order_number: str):
    html = f"""
    <html>
    <head><title>Payment Cancelled</title></head>
    <body>
        <h2>Payment Cancelled</h2>
        <p>Your payment for order <b>{order_number}</b> was cancelled.</p>
        <a href="/shop/{order_number}/">Back to Shop</a>
    </body>
    </html>
    """
    return HTMLResponse(content=html)

from fastapi.responses import HTMLResponse

@router.get("/shop/{order_number}/", response_class=HTMLResponse)
async def shop_order_page(order_number: str):
    html = f"""
    <html>
    <head>
        <title>Order {order_number}</title>
        <script src="/static/js/shop_order.js"></script>
    </head>
    <body>
        <h2>Order <span id="order-number">{order_number}</span></h2>
        <div id="order-details">Loading...</div>
        <button id="download-bill-btn">Download Bill</button>
        <button id="create-return-btn">Create Return Order</button>
        <div id="return-result"></div>
    </body>
    </html>
    """
    return HTMLResponse(content=html)