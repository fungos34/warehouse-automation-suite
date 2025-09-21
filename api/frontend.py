from fastapi import APIRouter
import os
from fastapi.responses import FileResponse, HTMLResponse

router = APIRouter()

# resolve static directory from project root so paths are absolute and robust
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
STATIC_DIR = os.path.join(PROJECT_ROOT, "static")


@router.get("/", response_class=FileResponse, tags=["Frontend"])
def serve_index():
    """
    Serve the main index.html using a FileResponse (efficient, avoids loading file into memory).
    """
    index_path = os.path.join(STATIC_DIR, "index.html")
    return FileResponse(index_path, media_type="text/html")


@router.get("/shop", response_class=FileResponse)
async def shop_page():
    shop_path = os.path.join(STATIC_DIR, "shop.html")
    return FileResponse(shop_path, media_type="text/html")


@router.get("/shop/{order_number}/success", response_class=HTMLResponse)
async def shop_success(order_number: str, session_id: str = None):
    # small dynamic confirmation page; keep minimal server-side work
    html = f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
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
    <div style="display:flex;justify-content:space-between;gap:18px;margin-top:12px;">
      <a href="/shop/{order_number}/" class="shop-back-link"><i class="fas fa-box"></i> See Order Details</a>
      <a href="/shop/" class="shop-back-link"><i class="fas fa-arrow-left"></i> Back to Shop</a>
    </div>
  </div>
</body>
</html>"""
    return HTMLResponse(content=html)


@router.get("/shop/{order_number}/cancel", response_class=HTMLResponse)
async def shop_cancel(order_number: str):
    html = f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
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
    <div style="display:flex;justify-content:space-between;gap:18px;margin-top:12px;">
      <a href="/shop/{order_number}/" class="shop-back-link"><i class="fas fa-box"></i> See Order Details</a>
      <a href="/shop/" class="shop-back-link"><i class="fas fa-arrow-left"></i> Back to Shop</a>
    </div>
  </div>
</body>
</html>"""
    return HTMLResponse(content=html)


@router.get("/shop/{order_number}/", response_class=HTMLResponse)
async def shop_order_page(order_number: str):
    # This page loads JS which will fetch the order details from API endpoints.
    html = f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
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
    <div id="confirm-receipt-popup" style="display:none;">
      <span id="confirm-receipt-message"></span>
      <button id="confirm-receipt-close" style="margin-left:12px;">&times;</button>
    </div>
    <div id="return-result"></div>
    <div style="display:flex;justify-content:space-between;gap:18px;margin-top:12px;">
      <a href="/shop/" class="shop-back-link"><i class="fas fa-arrow-left"></i> Back to Shop</a>
    </div>
  </div>
  <script>
    // lightweight client-side bootstrap: replace with real fetches
    (function() {{
      // placeholder: client JS should fetch order details from /api/sale_order/{order_number} etc.
      const details = document.getElementById('order-details');
      details.textContent = 'Order details must be loaded by client JS via the API.';
    }});
  </script>
</body>
</html>"""
    return HTMLResponse(content=html)


@router.get("/privacy-policy", response_class=FileResponse)
async def privacy_policy():
    return FileResponse(os.path.join(STATIC_DIR, "privacy-policy.html"), media_type="text/html")


@router.get("/terms", response_class=FileResponse)
async def terms_page():
    return FileResponse(os.path.join(STATIC_DIR, "terms.html"), media_type="text/html")