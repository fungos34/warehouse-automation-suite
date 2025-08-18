# For shipping item lookup by SKU, see /items/by-sku/{sku} in warehouse.py
from fastapi import APIRouter, Depends, HTTPException, Response, Request, Body
import stripe
import shippo
import random
from shippo.models import components
from typing import List
from database import get_conn
from models import SaleOrderCreate, OrderLineIn, CreateSessionRequest, QuotationCreate, PurchaseLabelRequest
from auth import get_current_username
from reportlab.lib.pagesizes import A4, A7
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader
import qrcode
from io import BytesIO
import uuid
from datetime import datetime
from utils import add_page_number_and_qr
from run import base_url, endpoint_secret, stripe_api_key, shippo_api_key
import asyncio

stripe.api_key = stripe_api_key
shippo_sdk = shippo.Shippo(api_key_header=shippo_api_key)

router = APIRouter()


# --- SALE ORDER ITEMS VIEW ---
@router.get("/sale-order-items", tags=["Sales"])
def get_sale_order_item_view(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("SELECT * FROM sale_order_item_view")
        return [dict(row) for row in result]

# --- QUOTATION ENDPOINTS ---

@router.post("/quotations/", tags=["Sales"])
def create_quotation(data: QuotationCreate):
    with get_conn() as conn:
        code = data.code.strip() or f"Q-{uuid.uuid4().hex[:8].upper()}"
        cur = conn.execute(
            """
            INSERT INTO quotation (
                code, partner_id, currency_id, tax_id, discount_id, price_list_id,
                split_parcel, pick_pack, ship, carrier_id, notes, priority, status
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'draft')
            """,
            (
                code,
                data.partner_id,
                data.currency_id,
                data.tax_id,
                data.discount_id,
                data.price_list_id,
                int(data.split_parcel) if data.split_parcel is not None else 0,
                int(data.pick_pack) if data.pick_pack is not None else 1,
                int(data.ship) if data.ship is not None else 1,
                data.carrier_id,
                data.notes,
                data.priority or 0
            )
        )
        conn.commit()
        return {"quotation_id": cur.lastrowid, "code": code}
    
@router.post("/quotations/{quotation_id}/lines", tags=["Sales"])
def add_quotation_lines(quotation_id: int, lines: List[OrderLineIn]):
    with get_conn() as conn:
        for line in lines:
            conn.execute(
                "INSERT INTO quotation_line (quantity, item_id, lot_id, quotation_id, price, currency_id, cost, cost_currency_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (line.quantity, line.item_id, line.lot_id, quotation_id, line.price, line.currency_id, line.cost, line.cost_currency_id)
            )
        conn.commit()
    return {"message": "Lines added"}

@router.get("/quotations/", tags=["Sales"])
def get_quotations(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("SELECT * FROM quotation ORDER BY id")
        return [dict(row) for row in result]

@router.get("/quotations/draft", tags=["Sales"])
def get_draft_quotations(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("SELECT * FROM quotation WHERE status = 'draft' ORDER BY id")
        return [dict(row) for row in result]

@router.post("/quotations/{quotation_id}/confirm", tags=["Sales"])
def confirm_quotation(quotation_id: int):  # username: str = Depends(get_current_username)
    with get_conn() as conn:
        # Set quotation to confirmed (trigger will create sale order)
        conn.execute("UPDATE quotation SET status = 'confirmed' WHERE id = ?", (quotation_id,))
        conn.commit()
        # Fetch the sale order created by the trigger
        sale_order = conn.execute(
            "SELECT id, code FROM sale_order WHERE quotation_id = ? ORDER BY id DESC LIMIT 1",
            (quotation_id,)
        ).fetchone()
        if not sale_order:
            raise HTTPException(status_code=500, detail="Sale order not created by trigger")
        return {"sale_order_code": sale_order["code"]}

# --- SALE ORDER ENDPOINTS ---
@router.post("/sale-orders/", tags=["Sales"])
def create_sale_order(order: SaleOrderCreate):
    with get_conn() as conn:
        code = order.code.strip() or f"SO-{uuid.uuid4().hex[:8].upper()}"
        cur = conn.execute(
            "INSERT INTO sale_order (code, partner_id, status) VALUES (?, ?, 'draft')",
            (code, order.partner_id)
        )
        conn.commit()
        return {"order_id": cur.lastrowid, "code": code}

@router.get("/sale-orders/by-code/{order_number}", tags=["Sales"])
def get_sale_order_by_code(order_number: str):
    with get_conn() as conn:
        order = conn.execute(
            "SELECT so.*, p.name as partner_name FROM sale_order so LEFT JOIN partner p ON so.partner_id = p.id WHERE so.code = ?",
            (order_number,)
        ).fetchone()
        if not order:
            raise HTTPException(status_code=404, detail="Order not found")
        lines = conn.execute(
            "SELECT ol.*, i.name as item_name, c.code as currency_code FROM order_line ol JOIN item i ON ol.item_id = i.id LEFT JOIN currency c ON ol.currency_id = c.id WHERE ol.order_id = ?",
            (order["id"],)
        ).fetchall()
        return {
            "id": order["id"],
            "code": order["code"],
            "status": order["status"],
            "partner_name": order["partner_name"],
            "lines": [dict(line) for line in lines]
        }
    

@router.get("/sale-orders/by-quotation/{quotation_code}", tags=["Sales"])
def get_sale_order_by_quotation(quotation_code: str):
    with get_conn() as conn:
        quotation = conn.execute(
            "SELECT id FROM quotation WHERE code = ?",
            (quotation_code,)
        ).fetchone()
        if not quotation:
            raise HTTPException(status_code=404, detail="Quotation not found")
        order = conn.execute(
            "SELECT so.*, p.name as partner_name FROM sale_order so LEFT JOIN partner p ON so.partner_id = p.id WHERE so.quotation_id = ?",
            (quotation["id"],)
        ).fetchone()
        if not order:
            raise HTTPException(status_code=404, detail="Order not found")
        lines = conn.execute(
            "SELECT ol.*, i.name as item_name, c.code as currency_code FROM order_line ol JOIN item i ON ol.item_id = i.id LEFT JOIN currency c ON ol.currency_id = c.id WHERE ol.order_id = ?",
            (order["id"],)
        ).fetchall()
        return {
            "id": order["id"],
            "code": order["code"],
            "status": order["status"],
            "partner_name": order["partner_name"],
            "lines": [dict(line) for line in lines]
        }


@router.post("/sale-orders/{order_id}/lines", tags=["Sales"])
def add_order_lines(order_id: int, lines: List[OrderLineIn]):
    with get_conn() as conn:
        for line in lines:
            conn.execute(
                "INSERT INTO order_line (quantity, item_id, order_id, price, currency_id, cost, cost_currency_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (line.quantity, line.item_id, order_id, line.price, line.currency_id, line.cost, line.cost_currency_id)
            )
        conn.commit()
    return {"message": "Lines added"}


@router.post("/sale-orders/{order_id}/confirm", tags=["Sales"])
def confirm_sale_order(order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        conn.execute("UPDATE sale_order SET status = 'confirmed' WHERE id = ?", (order_id,))
        conn.commit()
    return {"message": "Order confirmed"}

@router.get("/sale-orders/", tags=["Sales"])
def get_sale_orders(customer_id: int = None, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        if customer_id:
            result = conn.execute(
                "SELECT * FROM sale_order WHERE partner_id = ? ORDER BY id",
                (customer_id,)
            )
        else:
            result = conn.execute(
                "SELECT * FROM sale_order ORDER BY id"
            )
        return [dict(row) for row in result]
        
@router.get("/sale-orders/draft", tags=["Sales"])
def get_draft_sale_orders(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("""
            SELECT so.id, so.code, so.partner_id, so.status, p.name as customer_name
            FROM sale_order so
            JOIN partner p ON so.partner_id = p.id
            WHERE so.status NOT IN ('confirmed', 'cancelled')
            ORDER BY so.id
        """)
        return [dict(row) for row in result]



@router.post("/sale-orders/{order_id}/cancel", tags=["Sales"])
def cancel_sale_order(order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        conn.execute("UPDATE sale_order SET status = 'cancelled' WHERE id = ?", (order_id,))
        conn.commit()
    return {"message": "Sale order cancelled"}


@router.get("/sale-orders/{order_id}/lines", tags=["Sales"])
def get_sale_order_lines(order_id: int):  #  username: str = Depends(get_current_username)
    with get_conn() as conn:
        result = conn.execute(
            "SELECT * FROM order_line WHERE order_id = ? ORDER BY id", (order_id,)
        ).fetchall()
        return [dict(row) for row in result]


@router.post("/create-checkout-session", tags=["Payments"])
def create_checkout_session(data: CreateSessionRequest):
    with get_conn() as conn:
        order = conn.execute("SELECT * FROM sale_order WHERE quotation_id = (SELECT id FROM quotation WHERE code=? LIMIT 1)", (data.order_number,)).fetchone()
        if not order:
            raise HTTPException(status_code=404, detail="Order not found")
        order_id = order["id"]
        lines = conn.execute(
            "SELECT ol.quantity, i.name, i.sku, ol.price, c.code as currency_code "
            "FROM order_line ol "
            "JOIN item i ON ol.item_id = i.id "
            "LEFT JOIN currency c ON ol.currency_id = c.id "
            "WHERE ol.order_id = ?",
            (order_id,)
        ).fetchall()
        if not lines:
            raise HTTPException(status_code=400, detail="No order lines found")

        # Calculate subtotal
        subtotal = sum(float(line["price"] or 0) * float(line["quantity"] or 0) for line in lines)
        discount = float(order["discount"]) if "discount" in order.keys() and order["discount"] else 0.0
        tax_percent = float(order["tax_percent"]) if "tax_percent" in order.keys() and order["tax_percent"] else 19.0
        taxed_base = subtotal - discount
        tax_amount = taxed_base * (tax_percent / 100)
        total = taxed_base + tax_amount

        # Use the currency of the first line, or fallback
        currency = (lines[0]["currency_code"] or "eur").lower()

    # Stripe expects cents
    stripe_line_items = [{
        "price_data": {
            "currency": currency,
            "product_data": {
                "name": f"Order {order['code']}"
            },
            "unit_amount": int(round(total * 100)),
        },
        "quantity": 1,
    }]

    session = stripe.checkout.Session.create(
        payment_method_types=["card"],
        line_items=stripe_line_items,
        mode='payment',
        customer_email=data.email,
        success_url=f"{base_url}shop/{order['code']}/success?session_id={{CHECKOUT_SESSION_ID}}",
        cancel_url=f"{base_url}shop/{order['code']}/cancel",
        metadata={"order_number": order['code']},
        payment_intent_data={
            "description": f"{order['code']}"
        }
    )
    return {"checkout_url": session.url}


@router.post("/stripe/webhook", tags=["Payments"])
async def stripe_webhook(request: Request):
    payload = await request.body()
    sig_header = request.headers.get("stripe-signature")
    try:
        event = stripe.Webhook.construct_event(
            payload, sig_header, endpoint_secret
        )
    except ValueError:
        return Response(status_code=400)
    except stripe.error.SignatureVerificationError:
        return Response(status_code=400)

    if event["type"] == "checkout.session.completed":
        session = event["data"]["object"]
        order_number = session["metadata"].get("order_number")
        if order_number:
            with get_conn() as conn:
                conn.execute("UPDATE sale_order SET status = 'confirmed' WHERE code = ?", (order_number,))
                conn.commit()
                print("✅ Payment success:", session["id"])

    return {"status": "ok"}



# Endpoint 1: Get available carriers and rates for static addresses
@router.post("/shippo/rates", tags=["Shipping"])
async def get_shippo_rates(
    from_address: dict = Body(None),
    to_address: dict = Body(None)
):
    # from_address = {"TODO": "Provide from address or use static one"}
    print("Faking Shippo rates for addresses:", from_address, to_address)
    # Use provided or fallback to static addresses
    address_from_data = {
        "name": "Shawn Ippotle",
        "street1": "215 Clayton St.",
        "city": "San Francisco",
        "state": "CA",
        "zip": "94117",
        "country": "US",
        "email": "shippotle@shippo.com",
        "phone": "+1 555 341 9393"
    }
    address_to_data =  {
        "name": "Mr Hippo Pippo",
        "street1": "1 Broadway",
        "city": "New York",
        "state": "NY",
        "zip": "10004",
        "country": "US",
        "email": "hippopippo@example.com",
        "phone": "+1 555 351 9097"
    }
    address_from, address_to = await asyncio.gather(
        create_shippo_address_async(address_from_data),
        create_shippo_address_async(address_to_data),
    )
    parcel = components.ParcelCreateRequest(
        length="5",
        width="5",
        height="5",
        distance_unit=components.DistanceUnitEnum.CM,
        weight="2",
        mass_unit=components.WeightUnitEnum.KG
    )
    shipment = shippo_sdk.shipments.create(
        components.ShipmentCreateRequest(
            address_from=address_from,
            address_to=address_to,
            parcels=[parcel],
            async_=False
        )
    )
    # print(shipment.rates[0])
    
    rates = [
        {
            "provider": r.provider,
            "servicelevel": r.servicelevel.name,
            "amount": r.amount,
            "currency": r.currency,
            "object_id": r.object_id
        }
        for r in shipment.rates
    ]
    print("rates:", rates)
    return {"rates": rates}


# Endpoint 2: Purchase label for selected rate
@router.post("/shippo/purchase-label", tags=["Shipping"])
async def purchase_shippo_label(request: PurchaseLabelRequest):
    rate_id = request.rate_id
    print("Purchasing label with rate_id:", rate_id)
    transaction = shippo_sdk.transactions.create(
        components.TransactionCreateRequest(
            rate=rate_id,
            label_file_type=components.LabelFileTypeEnum.PDF,
            async_=False
        )
    )
    if transaction.status == "SUCCESS":
        print("✅ Label purchased successfully:", transaction.label_url)
        return {
            "label_url": transaction.label_url,
            "tracking_number": transaction.tracking_number,
            # "amount": transaction.amount,
            # "currency": transaction.currency,
            # "provider": transaction.provider,
            # "servicelevel": transaction.servicelevel.name
        }
    else:
        print("❌ Error purchasing label:", transaction.messages)
        return {"error": transaction.messages}

async def create_shippo_address_async(address):
    return components.AddressCreateRequest(
        name=address["name"],
        street1=address["street1"],
        city=address["city"],
        state=address["state"],
        zip=address["zip"],
        country=address["country"],
        email=address["email"],
        phone=address["phone"]
    )

def extract_shipping_lot_code(lot_code):
    if lot_code and lot_code.startswith("SHIP-"):
        # Remove "SHIP-" prefix and split by "-"
        parts = lot_code[5:].split("-")
        # Remove the last two parts (date and random number)
        if len(parts) > 2:
            return "-".join(parts[:-2])
        else:
            return lot_code[5:]
    return lot_code or ""

@router.get("/sale-orders/{order_id}/print-order", tags=["Documents"])
def sale_order_pdf(order_id: int):
    from reportlab.lib.pagesizes import A4
    from reportlab.lib import colors
    from reportlab.lib.styles import getSampleStyleSheet
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
    from io import BytesIO
    from datetime import datetime
    from utils import add_page_number_and_qr

    with get_conn() as conn:
        order = conn.execute("SELECT * FROM sale_order WHERE id = ?", (order_id,)).fetchone()
        if not order:
            raise HTTPException(status_code=404, detail="Order not found")
        buyer = conn.execute("SELECT * FROM partner WHERE id = ?", (order["partner_id"],)).fetchone()
        lines = conn.execute("""
            SELECT ol.quantity, ol.returned_quantity, ol.price, i.name as item_name, i.sku as item_sku, ol.lot_id, l.lot_number as lot_code
            FROM order_line ol
            JOIN item i ON ol.item_id = i.id
            LEFT JOIN lot l ON ol.lot_id = l.id
            WHERE ol.order_id = ?
        """, (order_id,)).fetchall()
        # Get tax percent from sale order's tax_id
        tax_percent = 19.0
        if "tax_id" in order.keys() and order["tax_id"]:
            tax_row = conn.execute("SELECT percent FROM tax WHERE id = ?", (order["tax_id"],)).fetchone()
            if tax_row:
                tax_percent = float(tax_row["percent"])
        # Get discount if present
        discount = float(order["discount"]) if "discount" in order.keys() and order["discount"] else 0.0

        return_lines = conn.execute("""
            SELECT ro.code as return_order_code, rl.quantity, rl.refund_amount, i.name as item_name, i.sku as item_sku, rl.lot_id, l.lot_number as lot_code
            FROM return_order ro
            JOIN return_line rl ON rl.return_order_id = ro.id
            JOIN item i ON rl.item_id = i.id
            LEFT JOIN lot l ON rl.lot_id = l.id
            WHERE ro.origin_model = 'sale_order' AND ro.origin_id = ? AND ro.status = 'done'
        """, (order_id,)).fetchall()
        company = conn.execute("""
            SELECT c.name, p.street, p.city, p.country, p.zip, p.phone, p.email
            FROM company c
            JOIN partner p ON c.partner_id = p.id
            LIMIT 1
        """).fetchone()

    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, rightMargin=30, leftMargin=30, topMargin=30, bottomMargin=18)
    elements = []
    styles = getSampleStyleSheet()

    # Company info
    company_lines = [
        f"<b>{company['name'] if company else 'Warehouse Company'}</b>",
        f"{company['street']}, {company['zip']} {company['city']}, {company['country']}" if company else "",
        f"Phone: {company['phone']}" if company and company['phone'] else "",
        f"Email: {company['email']}" if company and company['email'] else "",
    ]
    elements.append(Paragraph("<br/>".join(filter(None, company_lines)), styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Billing Address (Buyer)
    billing_lines = [
        "<b>Billing Address:</b>",
        buyer["name"] if buyer else "",
        buyer["billing_street"] if buyer and "billing_street" in buyer.keys() and buyer["billing_street"] else "",
        f"{buyer['billing_zip']} {buyer['billing_city']}, {buyer['billing_country']}" if buyer and "billing_zip" in buyer.keys() else "",
        f"Phone: {buyer['phone']}" if buyer and "phone" in buyer.keys() and buyer["phone"] else "",
        f"Email: {buyer['email']}" if buyer and "email" in buyer.keys() and buyer["email"] else "",
    ]
    elements.append(Paragraph("<br/>".join(filter(None, billing_lines)), styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Date and Order Info
    elements.append(Paragraph(f"Date: {datetime.now().strftime('%Y-%m-%d')}", styles["Normal"]))
    elements.append(Paragraph(f"<b>Order Number {order['code']}</b>", styles["Title"]))
    elements.append(Paragraph(f"Status: {order['status']}", styles["Normal"]))
    if order["status"] != "confirmed":
        elements.append(Paragraph(
            "<font size='8' color='gray'>Note: This document is not a valid bill, but a non-binding offer.</font>",
            styles["Normal"]
        ))
    elements.append(Spacer(1, 12))

    # Table for items (only non-returned quantity)
    data = [["Item", "SKU", "Lot", "Qty", "Unit €", "Total €"]]
    subtotal = 0.0

    for line in lines:
        qty = float(line["quantity"])
        returned_qty = float(line["returned_quantity"] or 0)
        qty_to_bill = qty - returned_qty
        price = float(line["price"]) if "price" in line.keys() and line["price"] is not None else 0.0
        lot_code = line["lot_code"] or ""
        if qty_to_bill > 0:
            line_total = qty_to_bill * price
            subtotal += line_total
            data.append([
                line["item_name"],
                line["item_sku"],
                extract_shipping_lot_code(lot_code),
                str(int(qty_to_bill)) if qty_to_bill == int(qty_to_bill) else f"{qty_to_bill:.2f}",
                f"{price:.2f}",
                f"{line_total:.2f}"
            ])

    table = Table(data, colWidths=[120, 45, 120, 35, 45, 55])
    table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.lightgrey),
        ('TEXTCOLOR', (0,0), (-1,0), colors.black),
        ('ALIGN', (1,1), (-1,-1), 'CENTER'),
        ('ALIGN', (3,1), (-1,-1), 'RIGHT'),
        ('GRID', (0,0), (-1,-1), 0.5, colors.black),
        ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
        ('FONTNAME', (0,1), (-1,-1), 'Helvetica'),
        ('FONTSIZE', (0,0), (-1,-1), 8),
        ('BOTTOMPADDING', (0,0), (-1,0), 6),
        ('TOPPADDING', (0,0), (-1,0), 6),
    ]))
    elements.append(table)
    elements.append(Spacer(1, 18))

    # Table for done returns (negative prices)
    refund_total_net = 0.0
    refund_total_tax = 0.0
    refund_total_gross = 0.0
    if return_lines:
        elements.append(Paragraph("<b>Done Returns</b>", styles["Heading3"]))
        ret_data = [["Return#", "Item", "SKU", "Lot", "Qty", "Unit €", "Total €", "Tax €"]]
        for rl in return_lines:
            qty = float(rl["quantity"])
            refund_net = float(rl["refund_amount"]) if rl["refund_amount"] is not None else 0.0
            refund_tax = refund_net * (tax_percent / 100)
            refund_gross = refund_net + refund_tax
            unit_price = refund_net / qty if qty else 0.0
            refund_total_net += refund_net
            refund_total_tax += refund_tax
            refund_total_gross += refund_gross
            ret_data.append([
                rl["return_order_code"],
                rl["item_name"],
                rl["item_sku"],
                rl["lot_code"] or "",
                str(int(qty)) if qty == int(qty) else f"{qty:.2f}",
                f"{-unit_price:.2f}",
                f"{-refund_net:.2f}",
                f"{-refund_tax:.2f}"
            ])
        ret_table = Table(ret_data, colWidths=[65, 90, 45, 60, 35, 45, 55, 45])
        ret_table.setStyle(TableStyle([
            ('BACKGROUND', (0,0), (-1,0), colors.lightgrey),
            ('TEXTCOLOR', (0,0), (-1,0), colors.black),
            ('ALIGN', (1,1), (-1,-1), 'CENTER'),
            ('ALIGN', (4,1), (-1,-1), 'RIGHT'),
            ('GRID', (0,0), (-1,-1), 0.5, colors.black),
            ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
            ('FONTNAME', (0,1), (-1,-1), 'Helvetica'),
            ('FONTSIZE', (0,0), (-1,-1), 8),
            ('BOTTOMPADDING', (0,0), (-1,0), 6),
            ('TOPPADDING', (0,0), (-1,0), 6),
        ]))
        elements.append(ret_table)
        elements.append(Spacer(1, 12))

    # Summary
    elements.append(Paragraph(f"Subtotal: {subtotal:.2f} €", styles["Normal"]))
    if discount:
        elements.append(Paragraph(f"Discount: -{discount:.2f} €", styles["Normal"]))
    taxed_base = subtotal - discount
    tax_amount = taxed_base * (tax_percent / 100)
    elements.append(Paragraph(f"Tax ({tax_percent:.2f}%): {tax_amount:.2f} €", styles["Normal"]))
    total = taxed_base + tax_amount
    elements.append(Paragraph(f"Total before returns: {total:.2f} €", styles["Normal"]))
    if refund_total_gross:
        elements.append(Paragraph(f"Refunded (returns, net): { -refund_total_net:.2f} €", styles["Normal"]))
        elements.append(Paragraph(f"Refunded tax: { -refund_total_tax:.2f} €", styles["Normal"]))
        elements.append(Paragraph(f"Total refund (gross): { -refund_total_gross:.2f} €", styles["Normal"]))
    elements.append(Paragraph(f"<b>Final Total: {total - refund_total_gross:.2f} €</b>", styles["Title"]))

    doc.build(elements, onFirstPage=lambda c, d: add_page_number_and_qr(c, d, order['code']),
          onLaterPages=lambda c, d: add_page_number_and_qr(c, d, order['code']))
    buffer.seek(0)
    return Response(
        buffer.read(),
        media_type="application/pdf",
        headers = {"Content-Disposition": "inline; filename=sales_order_" + order['code'] + ".pdf"}
    )


@router.get("/sale-orders/{order_id}/print-shipment", tags=["Documents"])
def sale_order_delivery_pdf(order_id: int):
    with get_conn() as conn:
        order = conn.execute("SELECT * FROM sale_order WHERE id = ?", (order_id,)).fetchone()
        if not order:
            raise HTTPException(status_code=404, detail="Order not found")
        buyer = conn.execute("SELECT * FROM partner WHERE id = ?", (order["partner_id"],)).fetchone()
        lines = conn.execute("""
            SELECT ol.quantity, i.name as item_name, i.sku as item_sku, l.lot_number as lot_code
            FROM order_line ol
            JOIN item i ON ol.item_id = i.id
            LEFT JOIN lot l ON ol.lot_id = l.id
            WHERE ol.order_id = ?
        """, (order_id,)).fetchall()
        company = conn.execute("""
            SELECT c.name, p.street, p.city, p.country, p.zip, p.phone, p.email
            FROM company c
            JOIN partner p ON c.partner_id = p.id
            LIMIT 1
        """).fetchone()

    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, rightMargin=30, leftMargin=30, topMargin=30, bottomMargin=18)
    elements = []
    styles = getSampleStyleSheet()

    # Company info (sender)
    company_lines = [
        f"<b>{company['name'] if company else 'Warehouse Company'}</b>",
        f"{company['street']}, {company['zip']} {company['city']}, {company['country']}" if company else "",
        f"Phone: {company['phone']}" if company and company['phone'] else "",
        f"Email: {company['email']}" if company and company['email'] else "",
    ]
    elements.append(Paragraph("<br/>".join(filter(None, company_lines)), styles["Normal"]))
    elements.append(Spacer(1, 12))


    # Shipping Address (Buyer)
    shipping_lines = [
        "<b>Shipping Address:</b>",
        buyer["name"] if buyer else "",
        buyer["street"] if buyer else "",
        f"{buyer['zip']} {buyer['city']}, {buyer['country']}" if buyer else "",
        f"Phone: {buyer['phone']}" if buyer and "phone" in buyer.keys() and buyer["phone"] else "",
        f"Email: {buyer['email']}" if buyer and "email" in buyer.keys() and buyer["email"] else "",
    ]
    elements.append(Paragraph("<br/>".join(filter(None, shipping_lines)), styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Date and Order Info
    elements.append(Paragraph(f"Date: {datetime.now().strftime('%Y-%m-%d')}", styles["Normal"]))
    elements.append(Paragraph(f"<b>Delivery Note for Order {order['code']}</b>", styles["Title"]))
    elements.append(Spacer(1, 12))

    # Table for items (no prices)
    data = [["Item", "SKU", "Lot", "Quantity"]]
    for line in lines:
        qty = float(line["quantity"])
        lot_code = line["lot_code"] or ""
        data.append([
            line["item_name"],
            line["item_sku"],
            lot_code,
            str(qty)
        ])

    table = Table(data, colWidths=[150, 60, 90, 60])
    table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.lightgrey),
        ('TEXTCOLOR', (0,0), (-1,0), colors.black),
        ('ALIGN', (1,1), (-1,-1), 'CENTER'),
        ('GRID', (0,0), (-1,-1), 1, colors.black),
        ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
        ('FONTNAME', (0,1), (-1,-1), 'Helvetica'),
        ('FONTSIZE', (0,0), (-1,-1), 10),
        ('BOTTOMPADDING', (0,0), (-1,0), 8),
    ]))
    elements.append(table)
    elements.append(Spacer(1, 18))

    # Optional: Add a note or signature line
    elements.append(Paragraph("<font size='9' color='gray'>This document is for delivery purposes only and contains no pricing information.</font>", styles["Normal"]))
    elements.append(Spacer(1, 24))
    elements.append(Paragraph("Received by: ____________________________", styles["Normal"]))

    # doc.build(elements, canvasmaker=NumberedCanvas)
    doc.build(elements, onFirstPage=lambda c, d: add_page_number_and_qr(c, d, order['code']),
          onLaterPages=lambda c, d: add_page_number_and_qr(c, d, order['code']))
    buffer.seek(0)
    return Response(
        buffer.read(),
        media_type="application/pdf",
        headers = {
            "Content-Disposition": "attachment; filename=\"delivery_note_" + order['code'] + ".pdf\""
        }
    )


@router.get("/sale-orders/{sale_order_id}/print-label", tags=["Sales"])
def print_sale_order_label(sale_order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        order = conn.execute("SELECT * FROM sale_order WHERE id = ?", (sale_order_id,)).fetchone()
        if not order:
            raise HTTPException(status_code=404, detail="Sale order not found")
        customer = conn.execute("SELECT * FROM partner WHERE id = ?", (order["partner_id"],)).fetchone()
        company = conn.execute("""
            SELECT c.name, p.street, p.city, p.country, p.zip
            FROM company c
            JOIN partner p ON c.partner_id = p.id
            LIMIT 1
        """).fetchone()

    sale_code = order["code"] if "code" in order.keys() and order["code"] else f"SO-{order['id']}"

    # Generate QR code
    qr = qrcode.QRCode(box_size=4, border=1)
    qr.add_data(sale_code)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    qr_buffer = BytesIO()
    img.save(qr_buffer, format="PNG")
    qr_buffer.seek(0)
    qr_img = ImageReader(qr_buffer)

    # Generate PDF
    buffer = BytesIO()
    c = canvas.Canvas(buffer, pagesize=A7)
    width, height = A7

    # Draw dashed cut-out border
    c.setDash(3, 3)
    c.rect(5, 5, width - 10, height - 10, stroke=1, fill=0)
    c.setDash()  # Reset to solid

    y = height - 20  # Start from near top inside border

    def draw_line(text, font="Helvetica", size=8, dy=10, bold=False, center=False):
        nonlocal y
        c.setFont(f"{font}-Bold" if bold else font, size)
        if center:
            c.drawCentredString(width / 2, y, text)
        else:
            c.drawString(10, y, text)
        y -= dy

    draw_line("Shipping Label", size=11, bold=True, dy=14)
    draw_line(f"Sale Order: {sale_code}", size=9, dy=12)

    # --- QR SECTION ---
    qr_size = 100
    qr_x = (width - qr_size) / 2
    qr_y = y - qr_size

    # Draw visual box for QR code
    c.rect(qr_x - 6, qr_y - 6, qr_size + 12, qr_size + 12, stroke=1, fill=0)
    c.drawImage(qr_img, qr_x, qr_y, width=qr_size, height=qr_size)
    c.setFont("Helvetica", 7)
    c.drawCentredString(width / 2, qr_y - 15, "Scan for order info")
    y = qr_y - 25

    # --- Address Section ---
    draw_line("Sender:", bold=True)
    if company:
        draw_line(company["name"])
        if "street" in company.keys() and company["street"]:
            draw_line(company["street"])
        city_line = f"{company['zip']} {company['city']}".strip()
        draw_line(city_line)
        if "country" in company.keys() and company["country"]:
            draw_line(company["country"])
    else:
        draw_line("(Unknown sender)")

    y -= 6

    draw_line("Receiver:", bold=True)
    if customer:
        draw_line(customer["name"])
        if "street" in customer.keys() and customer["street"]:
            draw_line(customer["street"])
        city_line = f"{customer['zip']} {customer['city']}".strip()
        draw_line(city_line)
        if "country" in customer.keys() and customer["country"]:
            draw_line(customer["country"])
    else:
        draw_line("(Unknown receiver)")

    # Draw final sentence near bottom, centered, but inside the dashed border
    final_y = 10  # Inside bottom border (5px border + ~5px padding)
    c.setFont("Helvetica-Oblique", 6)
    c.drawCentredString(width / 2, final_y, "Stick this label on your parcel.")

    c.showPage()
    c.save()

    buffer.seek(0)
    return Response(
        buffer.read(),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename=\"sale_label_{sale_code}.pdf\"'}
    )


@router.get("/quotations/{quotation_id}/print", tags=["Documents"])
def print_quotation_pdf(quotation_id: int):
    from reportlab.lib.pagesizes import A4
    from reportlab.lib import colors
    from reportlab.lib.styles import getSampleStyleSheet
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
    from io import BytesIO
    from datetime import datetime
    from utils import add_page_number_and_qr

    with get_conn() as conn:
        quotation = conn.execute("SELECT * FROM quotation WHERE id = ?", (quotation_id,)).fetchone()
        if not quotation:
            raise HTTPException(status_code=404, detail="Quotation not found")
        buyer = conn.execute("SELECT * FROM partner WHERE id = ?", (quotation["partner_id"],)).fetchone()
        lines = conn.execute("""
            SELECT ql.quantity, ql.price, i.name as item_name, i.sku as item_sku, ql.lot_id, l.lot_number as lot_code
            FROM quotation_line ql
            JOIN item i ON ql.item_id = i.id
            LEFT JOIN lot l ON ql.lot_id = l.id
            WHERE ql.quotation_id = ?
        """, (quotation_id,)).fetchall()
        company = conn.execute("""
            SELECT c.name, p.street, p.city, p.country, p.zip, p.phone, p.email
            FROM company c
            JOIN partner p ON c.partner_id = p.id
            LIMIT 1
        """).fetchone()

    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, rightMargin=30, leftMargin=30, topMargin=30, bottomMargin=18)
    elements = []
    styles = getSampleStyleSheet()

    # Company info
    company_lines = [
        f"<b>{company['name'] if company else 'Warehouse Company'}</b>",
        f"{company['street']}, {company['zip']} {company['city']}, {company['country']}" if company else "",
        f"Phone: {company['phone']}" if company and company['phone'] else "",
        f"Email: {company['email']}" if company and company['email'] else "",
    ]
    elements.append(Paragraph("<br/>".join(filter(None, company_lines)), styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Billing Address (Buyer)
    billing_lines = [
        "<b>Billing Address:</b>",
        buyer["name"] if buyer else "",
        buyer["billing_street"] if buyer and "billing_street" in buyer.keys() and buyer["billing_street"] else "",
        f"{buyer['billing_zip']} {buyer['billing_city']}, {buyer['billing_country']}" if buyer and "billing_zip" in buyer.keys() else "",
        f"Phone: {buyer['phone']}" if buyer and "phone" in buyer.keys() and buyer["phone"] else "",
        f"Email: {buyer['email']}" if buyer and "email" in buyer.keys() and buyer["email"] else "",
    ]
    elements.append(Paragraph("<br/>".join(filter(None, billing_lines)), styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Date and Quotation Info
    elements.append(Paragraph(f"Date: {datetime.now().strftime('%Y-%m-%d')}", styles["Normal"]))
    elements.append(Paragraph(f"<b>Quotation Number {quotation['code']}</b>", styles["Title"]))
    elements.append(Paragraph(f"Status: {quotation['status']}", styles["Normal"]))
    elements.append(Paragraph(
        "<font size='8' color='gray'>Note: This document is not a valid bill, but a non-binding offer.</font>",
        styles["Normal"]
    ))
    elements.append(Spacer(1, 12))

    # Table for items
    data = [["Item", "SKU", "Lot", "Qty", "Unit €", "Total €"]]
    subtotal = 0.0

    for line in lines:
        qty = float(line["quantity"])
        price = float(line["price"]) if "price" in line.keys() and line["price"] is not None else 0.0
        lot_code = line["lot_code"] or ""
        line_total = qty * price
        subtotal += line_total
        data.append([
            line["item_name"],
            line["item_sku"],
            extract_shipping_lot_code(lot_code),
            str(int(qty)) if qty == int(qty) else f"{qty:.2f}",
            f"{price:.2f}",
            f"{line_total:.2f}"
        ])

    table = Table(data, colWidths=[120, 45, 120, 35, 45, 55])
    table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.lightgrey),
        ('TEXTCOLOR', (0,0), (-1,0), colors.black),
        ('ALIGN', (1,1), (-1,-1), 'CENTER'),
        ('ALIGN', (3,1), (-1,-1), 'RIGHT'),
        ('GRID', (0,0), (-1,-1), 0.5, colors.black),
        ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
        ('FONTNAME', (0,1), (-1,-1), 'Helvetica'),
        ('FONTSIZE', (0,0), (-1,-1), 8),
        ('BOTTOMPADDING', (0,0), (-1,0), 6),
        ('TOPPADDING', (0,0), (-1,0), 6),
    ]))
    elements.append(table)
    elements.append(Spacer(1, 18))

    # Summary
    elements.append(Paragraph(f"Subtotal: {subtotal:.2f} €", styles["Normal"]))
    elements.append(Paragraph(f"<b>Total: {subtotal:.2f} €</b>", styles["Title"]))

    doc.build(elements, onFirstPage=lambda c, d: add_page_number_and_qr(c, d, quotation['code']),
          onLaterPages=lambda c, d: add_page_number_and_qr(c, d, quotation['code']))
    buffer.seek(0)
    return Response(
        buffer.read(),
        media_type="application/pdf",
        headers = {"Content-Disposition": "inline; filename=quotation_" + quotation['code'] + ".pdf"}
    )