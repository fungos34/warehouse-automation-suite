from fastapi import APIRouter, Depends, HTTPException, Response
from typing import List
from database import get_conn
from models import SaleOrderCreate, OrderLineIn
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


router = APIRouter()


# --- SALE ORDER ITEMS VIEW ---
@router.get("/sale-order-items", tags=["Sales"])
def get_sale_order_item_view(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("SELECT * FROM sale_order_item_view")
        return [dict(row) for row in result]
    
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
def get_sale_order_lines(order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute(
            "SELECT * FROM order_line WHERE order_id = ? ORDER BY id", (order_id,)
        ).fetchall()
        return [dict(row) for row in result]



@router.get("/sale-orders/{order_id}/print-order", tags=["Documents"])
def sale_order_pdf(order_id: int):
    with get_conn() as conn:
        order = conn.execute("SELECT * FROM sale_order WHERE id = ?", (order_id,)).fetchone()
        if not order:
            raise HTTPException(status_code=404, detail="Order not found")
        buyer = conn.execute("SELECT * FROM partner WHERE id = ?", (order["partner_id"],)).fetchone()
        lines = conn.execute("""
            SELECT ol.quantity, ol.price, i.name as item_name, i.sku as item_sku, ol.lot_id, l.lot_number as lot_code
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
    # Fallbacks for discount/tax if not present in DB
    discount = float(order["discount"]) if "discount" in order.keys() else 0.0
    tax_percent = float(order["tax_percent"]) if "tax_percent" in order.keys() else 19.0  # e.g. 19% VAT

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
        # Add a more decent, smaller, gray note below the status
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
        line_total = qty * price
        lot_code = line["lot_code"] or ""
        subtotal += line_total
        data.append([
            line["item_name"],
            line["item_sku"],
            lot_code,
            str(int(qty)) if qty == int(qty) else f"{qty:.2f}",
            f"{price:.2f}",
            f"{line_total:.2f}"
        ])

    # Adjusted, more compact column widths (in points)
    table = Table(data, colWidths=[120, 45, 45, 35, 45, 55])
    table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.lightgrey),
        ('TEXTCOLOR', (0,0), (-1,0), colors.black),
        ('ALIGN', (1,1), (-1,-1), 'CENTER'),
        ('ALIGN', (3,1), (-1,-1), 'RIGHT'),  # Right-align Qty, Unit, Total
        ('GRID', (0,0), (-1,-1), 0.5, colors.black),
        ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
        ('FONTNAME', (0,1), (-1,-1), 'Helvetica'),
        ('FONTSIZE', (0,0), (-1,-1), 8),  # Smaller font
        ('BOTTOMPADDING', (0,0), (-1,0), 6),
        ('TOPPADDING', (0,0), (-1,0), 6),
    ]))
    elements.append(table)
    elements.append(Spacer(1, 18))

    # Summary
    elements.append(Paragraph(f"Subtotal: {subtotal:.2f} €", styles["Normal"]))
    if discount:
        elements.append(Paragraph(f"Discount: -{discount:.2f} €", styles["Normal"]))
    taxed_base = subtotal - discount
    tax_amount = taxed_base * (tax_percent / 100)
    elements.append(Paragraph(f"Tax ({tax_percent:.2f}%): {tax_amount:.2f} €", styles["Normal"]))
    total = taxed_base + tax_amount
    elements.append(Paragraph(f"<b>Total: {total:.2f} €</b>", styles["Title"]))

    # doc.build(elements, canvasmaker=NumberedCanvas)
    doc.build(elements, onFirstPage=lambda c, d: add_page_number_and_qr(c, d, order['code']),
          onLaterPages=lambda c, d: add_page_number_and_qr(c, d, order['code']))
    buffer.seek(0)
    return Response(
        buffer.read(),
        media_type="application/pdf",
        headers = {"Content-Disposition": "attachment; filename=sales_order_" + order['code'] + ".pdf"}
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

    table = Table(data, colWidths=[150, 60, 60, 60])
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

