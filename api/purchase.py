from fastapi import APIRouter, Depends, HTTPException
from database import get_conn
from auth import get_current_username
from models import PurchaseOrderCreate, PurchaseOrderLineIn
from typing import List
from datetime import datetime
import uuid
from io import BytesIO
from reportlab.lib.pagesizes import A4, A7
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader
import qrcode
from utils import add_page_number_and_qr
from fastapi.responses import Response


router = APIRouter()

#--- PURCHASE ORDER ENDPOINTS --- 


@router.get("/purchase-orders/draft", tags=["Purchasing"])
def get_draft_purchase_orders(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("""
            SELECT po.id, po.code, po.partner_id, po.status, p.name as vendor_name
            FROM purchase_order po
            JOIN partner p ON po.partner_id = p.id
            WHERE po.status NOT IN ('confirmed', 'cancelled')
            ORDER BY po.id
        """)
        return [dict(row) for row in result]

@router.post("/purchase-orders/{order_id}/confirm", tags=["Purchasing"])
def confirm_purchase_order(order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        conn.execute("UPDATE purchase_order SET status = 'confirmed' WHERE id = ?", (order_id,))
        conn.commit()
    return {"message": "Purchase order confirmed"}

@router.post("/purchase-orders/{order_id}/lines", tags=["Purchasing"])
def add_purchase_order_lines(order_id: int, lines: List[PurchaseOrderLineIn], username: str = Depends(get_current_username)):
    with get_conn() as conn:
        for line in lines:
            conn.execute(
                """INSERT INTO purchase_order_line
                (purchase_order_id, item_id, quantity, route_id, price, currency_id, cost, cost_currency_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                (order_id, line.item_id, line.quantity, line.route_id, line.price, line.currency_id, line.cost, line.cost_currency_id)
            )
        conn.commit()
    return {"message": "Purchase order lines added"}


@router.get("/purchase-orders/", tags=["Purchasing"])
def get_purchase_orders(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("SELECT * FROM purchase_order ORDER BY id").fetchall()
        return [dict(row) for row in result]
    

@router.post("/purchase-orders/", tags=["Purchasing"])
def create_purchase_order(order: PurchaseOrderCreate, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        code = order.code
        if not code:
            code = f"PO-{uuid.uuid4().hex[:8].upper()}"
        code = order.code.strip() or f"PO-{uuid.uuid4().hex[:8].upper()}"
        cur = conn.execute(
            "INSERT INTO purchase_order (code, partner_id, status) VALUES (?, ?, 'draft')",
            (code, order.partner_id)
        )
        conn.commit()
        return {"purchase_order_id": cur.lastrowid, "code": code}

@router.post("/purchase-orders/{order_id}/cancel", tags=["Purchasing"])
def cancel_purchase_order(order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        conn.execute("UPDATE purchase_order SET status = 'cancelled' WHERE id = ?", (order_id,))
        conn.commit()
    return {"message": "Purchase order cancelled"}

@router.get("/purchase-orders/{order_id}/lines", tags=["Purchasing"])
def get_purchase_order_lines(order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute(
            "SELECT * FROM purchase_order_line WHERE purchase_order_id = ? ORDER BY id", (order_id,)
        ).fetchall()
        return [dict(row) for row in result]


@router.get("/purchase-orders/{order_id}", tags=["Purchasing"])
def get_purchase_order(order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        order = conn.execute("SELECT * FROM purchase_order WHERE id = ?", (order_id,)).fetchone()
        if not order:
            raise HTTPException(status_code=404, detail="Purchase order not found")
        return dict(order)


@router.get("/purchase-orders/{order_id}/print-order", tags=["Documents"])
def purchase_order_pdf(order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        order = conn.execute("SELECT * FROM purchase_order WHERE id = ?", (order_id,)).fetchone()
        if not order:
            raise HTTPException(status_code=404, detail="Purchase order not found")
        vendor = conn.execute("SELECT * FROM partner WHERE id = ?", (order["partner_id"],)).fetchone()
        lines = conn.execute("""
            SELECT pol.quantity, pol.price, pol.cost, i.name as item_name, i.sku as item_sku, pol.lot_id, l.lot_number as lot_code
            FROM purchase_order_line pol
            JOIN item i ON pol.item_id = i.id
            LEFT JOIN lot l ON pol.lot_id = l.id
            WHERE pol.purchase_order_id = ?
        """, (order_id,)).fetchall()
        company = conn.execute("""
            SELECT c.name, p.street, p.city, p.country, p.zip, p.phone, p.email
            FROM company c
            JOIN partner p ON c.partner_id = p.id
            LIMIT 1
        """).fetchone()
    # Fallbacks for tax if not present in DB
    tax_percent = float(order["tax_percent"]) if "tax_percent" in order.keys() else 19.0

    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, rightMargin=30, leftMargin=30, topMargin=30, bottomMargin=18)
    elements = []
    styles = getSampleStyleSheet()

    # Vendor info
    vendor_lines = [
        "<b>Vendor:</b>",
        vendor["name"] if vendor else "",
        vendor["street"] if vendor else "",
        f"{vendor['zip']} {vendor['city']}, {vendor['country']}" if vendor else "",
        f"Phone: {vendor['phone']}" if vendor and "phone" in vendor.keys() and vendor["phone"] else "",
        f"Email: {vendor['email']}" if vendor and "email" in vendor.keys() and vendor["email"] else "",
    ]
    elements.append(Paragraph("<br/>".join(filter(None, vendor_lines)), styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Company Billing Address (as buyer)
    company_billing_lines = [
        f"<b>{company['name'] if company else 'Warehouse Company'}</b>",
        company["billing_street"] if company and "billing_street" in company.keys() and company["billing_street"] else company["street"] if company else "",
        f"{company['billing_zip']} {company['billing_city']}, {company['billing_country']}" if company and "billing_zip" in company.keys() else
            f"{company['zip']} {company['city']}, {company['country']}" if company else "",
        f"Phone: {company['phone']}" if company and company['phone'] else "",
        f"Email: {company['email']}" if company and company['email'] else "",
    ]
    elements.append(Paragraph("<br/>".join(filter(None, company_billing_lines)), styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Date and Order Info
    elements.append(Paragraph(f"Date: {datetime.now().strftime('%Y-%m-%d')}", styles["Normal"]))
    elements.append(Paragraph(f"<b>Purchase Order Number {order['code']}</b>", styles["Title"]))
    elements.append(Paragraph(f"Status: {order['status']}", styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Table for items
    data = [["Item", "SKU", "Lot", "Quantity", "Unit Price", "Line Total"]]
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
            str(qty),
            f"{price:.2f} €",
            f"{line_total:.2f} €",
        ])

    table = Table(data, colWidths=[140, 70, 90, 70, 70, 70])
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

    # Summary
    elements.append(Paragraph(f"Subtotal: {subtotal:.2f} €", styles["Normal"]))
    tax_amount = subtotal * (tax_percent / 100)
    elements.append(Paragraph(f"Tax ({tax_percent:.2f}%): {tax_amount:.2f} €", styles["Normal"]))
    total = subtotal + tax_amount
    elements.append(Paragraph(f"<b>Total: {total:.2f} €</b>", styles["Title"]))

    # doc.build(elements, canvasmaker=NumberedCanvas)
    doc.build(elements, onFirstPage=lambda c, d: add_page_number_and_qr(c, d, order['code']),
          onLaterPages=lambda c, d: add_page_number_and_qr(c, d, order['code']))
    buffer.seek(0)
    return Response(
        buffer.read(),
        media_type="application/pdf",
        headers = {
            "Content-Disposition": "attachment; filename=\"purchase_order_" + order['code'] + ".pdf\""
        }
    )


@router.get("/purchase-orders/{order_id}/print-shipment", tags=["Documents"])
def purchase_order_delivery_pdf(order_id: int):
    with get_conn() as conn:
        order = conn.execute("SELECT * FROM purchase_order WHERE id = ?", (order_id,)).fetchone()
        if not order:
            raise HTTPException(status_code=404, detail="Purchase order not found")
        vendor = conn.execute("SELECT * FROM partner WHERE id = ?", (order["partner_id"],)).fetchone()
        lines = conn.execute("""
            SELECT pol.quantity, i.name as item_name, i.sku as item_sku, l.lot_number as lot_code
            FROM purchase_order_line pol
            JOIN item i ON pol.item_id = i.id
            LEFT JOIN lot l ON pol.lot_id = l.id
            WHERE pol.purchase_order_id = ?
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

    # Vendor info
    vendor_lines = [
        "<b>Vendor:</b>",
        vendor["name"] if vendor else "",
        vendor["street"] if vendor else "",
        f"{vendor['zip']} {vendor['city']}, {vendor['country']}" if vendor else "",
        f"Phone: {vendor['phone']}" if vendor and "phone" in vendor.keys() and vendor["phone"] else "",
        f"Email: {vendor['email']}" if vendor and "email" in vendor.keys() and vendor["email"] else "",
    ]
    elements.append(Paragraph("<br/>".join(filter(None, vendor_lines)), styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Company Shipping Address (as delivery address)
    company_shipping_lines = [
        f"<b>{company['name'] if company else 'Warehouse Company'}</b>",
        company["street"] if company else "",
        f"{company['zip']} {company['city']}, {company['country']}" if company else "",
        f"Phone: {company['phone']}" if company and company['phone'] else "",
        f"Email: {company['email']}" if company and company['email'] else "",
    ]
    elements.append(Paragraph("<br/>".join(filter(None, company_shipping_lines)), styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Date and Order Info
    elements.append(Paragraph(f"Date: {datetime.now().strftime('%Y-%m-%d')}", styles["Normal"]))
    elements.append(Paragraph(f"<b>Delivery Note for Purchase Order {order['code']}</b>", styles["Title"]))
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
            "Content-Disposition": "attachment; filename=\"purchase_delivery_note_" + order['code'] + ".pdf\""
        }
    )


@router.get("/purchase-orders/{purchase_order_id}/print-label", tags=["Purchasing"])
def print_purchase_order_label(purchase_order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        order = conn.execute("SELECT * FROM purchase_order WHERE id = ?", (purchase_order_id,)).fetchone()
        if not order:
            raise HTTPException(status_code=404, detail="Purchase order not found")
        vendor = conn.execute("SELECT * FROM partner WHERE id = ?", (order["partner_id"],)).fetchone()
        company = conn.execute("""
            SELECT c.name, p.street, p.city, p.country, p.zip
            FROM company c
            JOIN partner p ON c.partner_id = p.id
            LIMIT 1
        """).fetchone()

    po_code = order["code"] if "code" in order.keys() and order["code"] else f"PO-{order['id']}"

    # Generate QR code
    qr = qrcode.QRCode(box_size=4, border=1)
    qr.add_data(po_code)
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

    draw_line("Inbound Carrier Label", size=11, bold=True, dy=14)
    draw_line(f"Purchase Order: {po_code}", size=9, dy=12)

    # --- QR SECTION ---
    qr_size = 100
    qr_x = (width - qr_size) / 2
    qr_y = y - qr_size

    # Draw visual box for QR code
    c.rect(qr_x - 6, qr_y - 6, qr_size + 12, qr_size + 12, stroke=1, fill=0)
    c.drawImage(qr_img, qr_x, qr_y, width=qr_size, height=qr_size)
    c.setFont("Helvetica", 7)
    c.drawCentredString(width / 2, qr_y - 15, "Scan for PO info")
    y = qr_y - 25

    # --- Address Section ---
    draw_line("Sender (Vendor):", bold=True)
    if vendor:
        draw_line(vendor["name"])
        if "street" in vendor.keys() and vendor["street"]:
            draw_line(vendor["street"])
        city_line = f"{vendor['zip']} {vendor['city']}".strip()
        draw_line(city_line)
        if "country" in vendor.keys() and vendor["country"]:
            draw_line(vendor["country"])
    else:
        draw_line("(Unknown sender)")

    y -= 6

    draw_line("Receiver (Warehouse):", bold=True)
    if company:
        draw_line(company["name"])
        if "street" in company.keys() and company["street"]:
            draw_line(company["street"])
        city_line = f"{company['zip']} {company['city']}".strip()
        draw_line(city_line)
        if "country" in company.keys() and company["country"]:
            draw_line(company["country"])
    else:
        draw_line("(Unknown receiver)")

    # Draw final sentence near bottom, centered, but inside the dashed border
    final_y = 10  # Inside bottom border (5px border + ~5px padding)
    c.setFont("Helvetica-Oblique", 6)
    c.drawCentredString(width / 2, final_y, "Stick this label on your inbound parcel.")

    c.showPage()
    c.save()

    buffer.seek(0)
    return Response(
        buffer.read(),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename=\"purchase_label_{po_code}.pdf\"'}
    )

