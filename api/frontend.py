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
    html = f"""
    <html>
    <head>
        <title>Payment Success</title>
        <link rel="stylesheet" href="/static/css/style.css">
        <script src="https://kit.fontawesome.com/7e2c6b8e7e.js" crossorigin="anonymous"></script>
    </head>
    <body class="shop-bg">
        <div class="shop-main-card" style="max-width:420px;">
            <div class="shop-header">
                <span class="shop-icon" style="color:#2e7d32;"><i class="fas fa-check-circle"></i></span>
                <h2 style="color:#2e7d32;">Thank you for your purchase!</h2>
            </div>
            <div style="margin-bottom:18px;">
                <p>Your order <b>{order_number}</b> has been <span style="color:#2e7d32;font-weight:500;">paid successfully</span>.</p>
            </div>
            <a href="/shop/{order_number}/" class="shop-back-link"><i class="fas fa-box"></i> See Order Details</a>
            <a href="/shop/" class="shop-back-link"><i class="fas fa-arrow-left"></i> Back to Shop</a>
        </div>
    </body>
    </html>
    """
    return HTMLResponse(content=html)

@router.get("/shop/{order_number}/cancel", response_class=HTMLResponse)
async def shop_cancel(order_number: str):
    html = f"""
    <html>
    <head>
        <title>Payment Cancelled</title>
        <link rel="stylesheet" href="/static/css/style.css">
        <script src="https://kit.fontawesome.com/7e2c6b8e7e.js" crossorigin="anonymous"></script>
    </head>
    <body class="shop-bg">
        <div class="shop-main-card" style="max-width:420px;">
            <div class="shop-header">
                <span class="shop-icon" style="color:#d32f2f;"><i class="fas fa-times-circle"></i></span>
                <h2 style="color:#d32f2f;">Payment Cancelled</h2>
            </div>
            <div style="margin-bottom:18px;">
                <p>Your payment for order <b>{order_number}</b> was <span style="color:#d32f2f;font-weight:500;">cancelled</span>.</p>
            </div>
            <a href="/shop/{order_number}/" class="shop-back-link"><i class="fas fa-box"></i> See Order Details</a>
            <a href="/shop/" class="shop-back-link"><i class="fas fa-arrow-left"></i> Back to Shop</a>
        </div>
    </body>
    </html>
    """
    return HTMLResponse(content=html)

@router.get("/shop/{order_number}/", response_class=HTMLResponse)
async def shop_order_page(order_number: str):
    html = f"""
    <html>
    <head>
        <title>Order {order_number}</title>
        <link rel="stylesheet" href="/static/css/style.css">
        <script src="https://kit.fontawesome.com/7e2c6b8e7e.js" crossorigin="anonymous"></script>
        <script src="/static/js/returns.js"></script>
    </head>
    <body class="shop-bg">
        <div class="shop-order-card">
            <div class="shop-order-header">
                <span class="shop-order-icon"><i class="fas fa-box"></i></span>
                <h2>Order <span id="order-number">{order_number}</span></h2>
            </div>
            <div id="order-details" class="shop-order-details">Loading...</div>
            <div class="shop-order-actions">
                <button id="download-bill-btn"><i class="fas fa-file-download"></i> Download Bill</button>
                <button id="create-return-btn"><i class="fas fa-undo"></i> Create Return Order</button>
                <button id="confirm-receipt-btn" class="pending"><i class="fas fa-check-circle"></i> Confirm Receipt</button>
            </div>
            <div id="confirm-receipt-result"></div>
            <div id="return-result"></div>
            <a href="/shop/" class="shop-back-link"><i class="fas fa-arrow-left"></i> Back to Shop</a>
        </div>
    </body>
    </html>
    """
    return HTMLResponse(content=html)