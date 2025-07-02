from fastapi import APIRouter
from database import get_conn
from models import ReturnOrderCreate
from fastapi import Depends, HTTPException
from datetime import datetime
from io import BytesIO
from reportlab.lib.pagesizes import A4, A7
from reportlab.pdfgen import canvas
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.lib import colors
from reportlab.lib.utils import ImageReader
import qrcode
import uuid
from fastapi.responses import Response
from utils import add_page_number_and_qr
from auth import get_current_username


router = APIRouter()

@router.get("/return-orders/", tags=["Returns"])
def list_return_orders(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("""
            SELECT ro.*, p.name as partner_name
            FROM return_order ro
            JOIN partner p ON ro.partner_id = p.id
            ORDER BY ro.id DESC
        """).fetchall()
        return [dict(row) for row in result]

@router.post("/return-orders/{return_order_id}/confirm", tags=["Returns"])
def confirm_return_order(return_order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        conn.execute("UPDATE return_order SET status = 'confirmed' WHERE id = ?", (return_order_id,))
        conn.commit()
    return {"message": "Return order confirmed"}

@router.post("/return-orders/{return_order_id}/cancel", tags=["Returns"])
def cancel_return_order(return_order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        conn.execute("UPDATE return_order SET status = 'cancelled' WHERE id = ?", (return_order_id,))
        conn.commit()
    return {"message": "Return order cancelled"}

@router.get("/return-orders/{return_order_id}/lines", tags=["Returns"])
def get_return_order_lines(return_order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute(
            "SELECT * FROM return_line WHERE return_order_id = ? ORDER BY id", (return_order_id,)
        ).fetchall()
        return [dict(row) for row in result]


@router.post("/return-orders/", tags=["Returns"])
def create_return_order(data: ReturnOrderCreate, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        # 1. Find the origin order by code and model, and check status
        if data.origin_model not in ("sale_order", "purchase_order"):
            raise HTTPException(400, "Invalid origin_model")
        origin = conn.execute(
            f"SELECT * FROM {data.origin_model} WHERE code = ? AND status = 'confirmed'",
            (data.origin_code,)
        ).fetchone()
        if not origin:
            raise HTTPException(404, f"{data.origin_model.replace('_', ' ').title()} not found or not confirmed")
        origin_id = origin["id"]

        # 2. Get all lines for the origin order, including price/currency
        if data.origin_model == "sale_order":
            lines = conn.execute(
                "SELECT id, item_id, lot_id, quantity, price, currency_id FROM order_line WHERE order_id = ?", (origin_id,)
            ).fetchall()
        else:
            lines = conn.execute(
                "SELECT id, item_id, lot_id, quantity, price, currency_id FROM purchase_order_line WHERE purchase_order_id = ?", (origin_id,)
            ).fetchall()
        allowed_lines = {(l["item_id"], l["lot_id"]): dict(l) for l in lines}

        # 3. Calculate already returned quantities for each (item_id, lot_id)
        already_returned = {}
        for row in conn.execute(
            "SELECT rl.item_id, rl.lot_id, SUM(rl.quantity) as qty FROM return_line rl "
            "JOIN return_order ro ON ro.id = rl.return_order_id "
            "WHERE ro.origin_model = ? AND ro.origin_id = ? GROUP BY rl.item_id, rl.lot_id",
            (data.origin_model, origin_id)
        ):
            already_returned[(row["item_id"], row["lot_id"])] = row["qty"]

        # 4. Validate each return line
        for line in data.lines:
            key = (line.item_id, line.lot_id)
            if key not in allowed_lines:
                raise HTTPException(400, f"Item/Lot not in original order: {key}")
            max_qty = allowed_lines[key]["quantity"] - already_returned.get(key, 0)
            if line.quantity < 1 or line.quantity > max_qty:
                raise HTTPException(400, f"Invalid quantity for item {line.item_id}, lot {line.lot_id}: max {max_qty}")

        # 5. Calculate per-unit tax/discount for proportional refund
        order_discount_id = origin["discount_id"] if "discount_id" in origin.keys() else None
        order_tax_id = origin["tax_id"] if "tax_id" in origin.keys() else None
        order_discount = float(origin["discount"]) if "discount" in origin.keys() and origin["discount"] else 0.0
        order_tax_percent = float(origin["tax_percent"]) if "tax_percent" in origin.keys() and origin["tax_percent"] else 0.0
        total_qty = sum(l["quantity"] for l in lines)
        discount_per_unit = order_discount / total_qty if total_qty > 0 else 0.0

        code = f"RET-{uuid.uuid4().hex[:8].upper()}"
        cur = conn.execute(
            "INSERT INTO return_order (code, origin_model, origin_id, partner_id, status) VALUES (?, ?, ?, ?, 'draft')",
            (code, data.origin_model, origin_id, origin["partner_id"])
        )
        return_order_id = cur.lastrowid

        for line in data.lines:
            key = (line.item_id, line.lot_id)
            src_line = allowed_lines[key]
            unit_price = float(src_line["price"]) if src_line["price"] is not None else 0.0
            refund_currency_id = src_line["currency_id"] if "currency_id" in src_line.keys() else None

            # Proportional discount and tax
            line_discount = discount_per_unit * line.quantity
            base_refund = unit_price * line.quantity - line_discount
            line_tax = base_refund * (order_tax_percent / 100.0)
            total_refund = base_refund + line_tax

            conn.execute(
                "INSERT INTO return_line (return_order_id, item_id, lot_id, quantity, reason, refund_amount, refund_currency_id, refund_tax_id, refund_discount_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (return_order_id, line.item_id, line.lot_id, line.quantity, line.reason, total_refund, refund_currency_id, order_tax_id, order_discount_id)
            )
        conn.commit()
        return {"return_order_id": return_order_id}
    

@router.get("/return-orders/{return_order_id}/print-order", tags=["Returns"])
def print_return_order(return_order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        order = conn.execute("SELECT * FROM return_order WHERE id = ?", (return_order_id,)).fetchone()
        if not order:
            raise HTTPException(status_code=404, detail="Return order not found")
        partner = conn.execute("SELECT * FROM partner WHERE id = ?", (order["partner_id"],)).fetchone()
        lines = conn.execute("""
            SELECT rl.quantity, i.name as item_name, i.sku as item_sku, rl.lot_id, l.lot_number as lot_code, rl.reason
            FROM return_line rl
            JOIN item i ON rl.item_id = i.id
            LEFT JOIN lot l ON rl.lot_id = l.id
            WHERE rl.return_order_id = ?
        """, (return_order_id,)).fetchall()
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

    # Partner (customer/vendor) info
    partner_lines = [
        "<b>Return From:</b>",
        partner["name"] if partner else "",
        partner["street"] if partner and "street" in partner.keys() else "",
        f"{partner['zip']} {partner['city']}, {partner['country']}" if partner and "zip" in partner.keys() else "",
        f"Phone: {partner['phone']}" if partner and "phone" in partner.keys() and partner["phone"] else "",
        f"Email: {partner['email']}" if partner and "email" in partner.keys() and partner["email"] else "",
    ]
    elements.append(Paragraph("<br/>".join(filter(None, partner_lines)), styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Date and Return Order Info
    elements.append(Paragraph(f"Date: {datetime.now().strftime('%Y-%m-%d')}", styles["Normal"]))
    elements.append(Paragraph(f"<b>Return Order {order['code']}</b>", styles["Title"]))
    elements.append(Paragraph(f"Origin: {order['origin_model']} #{order['origin_id']}", styles["Normal"]))
    elements.append(Paragraph(f"Status: {order['status']}", styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Table for items
    data = [["Item", "SKU", "Lot", "Quantity", "Reason"]]
    for line in lines:
        lot_code = line["lot_code"] or ""
        data.append([
            line["item_name"],
            line["item_sku"],
            lot_code,
            str(line["quantity"]),
            line["reason"] or ""
        ])
    table = Table(data, colWidths=[120, 60, 90, 60, 120])
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
    elements.append(Paragraph("<font size='9' color='gray'>This document is for return processing purposes only.</font>", styles["Normal"]))
    elements.append(Spacer(1, 24))
    elements.append(Paragraph("Received by: ____________________________", styles["Normal"]))

    doc.build(elements, onFirstPage=lambda c, d: add_page_number_and_qr(c, d, order['code']),
          onLaterPages=lambda c, d: add_page_number_and_qr(c, d, order['code']))
    buffer.seek(0)
    return Response(
        buffer.read(),
        media_type="application/pdf",
        headers = {
            "Content-Disposition": "attachment; filename=\"return_order_" + order['code'] + ".pdf\""
        }
    )

@router.get("/return-orders/{return_order_id}/print-bill", tags=["Returns"])
def print_return_bill(return_order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        order = conn.execute("SELECT * FROM return_order WHERE id = ?", (return_order_id,)).fetchone()
        if not order:
            raise HTTPException(status_code=404, detail="Return order not found")

        partner = conn.execute("SELECT * FROM partner WHERE id = ?", (order["partner_id"],)).fetchone()

        lines = conn.execute("""
            SELECT rl.quantity, i.name as item_name, i.sku as item_sku, rl.lot_id, 
                   l.lot_number as lot_code, rl.reason, rl.refund_amount
            FROM return_line rl
            JOIN item i ON rl.item_id = i.id
            LEFT JOIN lot l ON rl.lot_id = l.id
            WHERE rl.return_order_id = ?
        """, (return_order_id,)).fetchall()

        company = conn.execute("""
            SELECT c.name, p.street, p.city, p.country, p.zip, p.phone, p.email
            FROM company c
            JOIN partner p ON c.partner_id = p.id
            LIMIT 1
        """).fetchone()

        origin_model = order["origin_model"]
        origin_id = order["origin_id"]

        if origin_model == "sale_order":
            orig = conn.execute("SELECT * FROM sale_order WHERE id = ?", (origin_id,)).fetchone()
        else:
            orig = conn.execute("SELECT * FROM purchase_order WHERE id = ?", (origin_id,)).fetchone()

        currency_symbol = "€"
        if orig and "currency_id" in orig.keys() and orig["currency_id"]:
            currency = conn.execute("SELECT * FROM currency WHERE id = ?", (orig["currency_id"],)).fetchone()
            if currency:
                currency_symbol = currency["symbol"]

        tax_percent = float(orig["tax_percent"]) if orig and "tax_percent" in orig.keys() and orig["tax_percent"] is not None else 19.0
        discount = float(orig["discount"]) if orig and "discount" in orig.keys() and orig["discount"] is not None else 0.0

    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, rightMargin=30, leftMargin=30, topMargin=30, bottomMargin=18)
    elements = []
    styles = getSampleStyleSheet()

    # Company Info
    company_lines = [
        f"<b>{company['name'] if company else 'Warehouse Company'}</b>",
        f"{company['street']}, {company['zip']} {company['city']}, {company['country']}" if company else "",
        f"Phone: {company['phone']}" if company and company["phone"] else "",
        f"Email: {company['email']}" if company and company["email"] else "",
    ]
    elements.append(Paragraph("<br/>".join(filter(None, company_lines)), styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Customer Info
    partner_lines = [
        "<b>Customer:</b>",
        partner["name"] if partner else "",
        partner["street"] if partner else "",
        f"{partner['zip']} {partner['city']}, {partner['country']}" if partner else "",
        f"Phone: {partner['phone']}" if partner and "phone" in partner.keys() and partner["phone"] else "",
        f"Email: {partner['email']}" if partner and "email" in partner.keys() and partner["email"] else "",
    ]
    elements.append(Paragraph("<br/>".join(filter(None, partner_lines)), styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Header Info
    elements.append(Paragraph(f"Date: {datetime.now().strftime('%Y-%m-%d')}", styles["Normal"]))
    elements.append(Paragraph(f"<b>Return Bill for {order['code']}</b>", styles["Title"]))
    elements.append(Spacer(1, 12))

    # Items Table
    data = [["Item", "SKU", "Lot", "Qty", f"Unit ({currency_symbol})", f"Total ({currency_symbol})"]]
    subtotal = 0.0
    for line in lines:
        qty = float(line["quantity"])
        refund = float(line["refund_amount"])
        line_total = qty * refund
        subtotal += line_total
        lot_code = line["lot_code"] or ""
        data.append([
            line["item_name"],
            line["item_sku"],
            lot_code,
            str(qty),
            f"{refund:.2f}",
            f"{line_total:.2f}"
        ])

    table = Table(data, colWidths=[120, 45, 90, 35, 55, 55])
    table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.lightgrey),
        ('TEXTCOLOR', (0,0), (-1,0), colors.black),
        ('ALIGN', (1,1), (-1,-1), 'CENTER'),
        ('ALIGN', (3,1), (-1,-1), 'RIGHT'),
        ('GRID', (0,0), (-1,-1), 0.5, colors.black),
        ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
        ('FONTNAME', (0,1), (-1,-1), 'Helvetica'),
        ('FONTSIZE', (0,0), (-1,-1), 9),
        ('BOTTOMPADDING', (0,0), (-1,0), 6),
        ('TOPPADDING', (0,0), (-1,0), 6),
    ]))
    elements.append(table)
    elements.append(Spacer(1, 18))

    # Financial Summary
    elements.append(Paragraph(f"Subtotal: {subtotal:.2f} {currency_symbol}", styles["Normal"]))
    if discount:
        elements.append(Paragraph(f"Discount: -{discount:.2f} {currency_symbol}", styles["Normal"]))
    taxed_base = subtotal - discount
    tax_amount = taxed_base * (tax_percent / 100)
    elements.append(Paragraph(f"Tax ({tax_percent:.2f}%): {tax_amount:.2f} {currency_symbol}", styles["Normal"]))
    total = taxed_base + tax_amount
    elements.append(Paragraph(f"<b>Total Refund: {total:.2f} {currency_symbol}</b>", styles["Title"]))
    elements.append(Spacer(1, 18))
    elements.append(Paragraph("<font size='9' color='gray'>This document serves as a refund bill for your return.</font>", styles["Normal"]))

    doc.build(elements, onFirstPage=lambda c, d: add_page_number_and_qr(c, d, order['code']),
              onLaterPages=lambda c, d: add_page_number_and_qr(c, d, order['code']))
    buffer.seek(0)

    return Response(
        buffer.read(),
        media_type="application/pdf",
        headers={
            "Content-Disposition": "attachment; filename=\"return_bill_" + order["code"] + ".pdf\""
        }
    )

@router.get("/return-orders/{return_order_id}/print-label", tags=["Returns"])
def print_return_label(return_order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        order = conn.execute("SELECT * FROM return_order WHERE id = ?", (return_order_id,)).fetchone()
        if not order:
            raise HTTPException(status_code=404, detail="Return order not found")
        partner = conn.execute("SELECT * FROM partner WHERE id = ?", (order["partner_id"],)).fetchone()
        company = conn.execute("""
            SELECT c.name, p.street, p.city, p.country, p.zip
            FROM company c
            JOIN partner p ON c.partner_id = p.id
            LIMIT 1
        """).fetchone()

    return_code = order["code"] if "code" in order.keys() and order["code"] else f"RET-{order['id']}"

    # Generate QR code
    qr = qrcode.QRCode(box_size=4, border=1)
    qr.add_data(return_code)
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

    draw_line("Return Parcel Label", size=11, bold=True, dy=14)
    draw_line(f"Return Order: {return_code}", size=9, dy=12)

    # --- QR SECTION ---
    qr_size = 100
    qr_x = (width - qr_size) / 2
    qr_y = y - qr_size

    # Draw visual box for QR code
    c.rect(qr_x - 6, qr_y - 6, qr_size + 12, qr_size + 12, stroke=1, fill=0)
    c.drawImage(qr_img, qr_x, qr_y, width=qr_size, height=qr_size)
    c.setFont("Helvetica", 7)
    c.drawCentredString(width / 2, qr_y - 15, "Scan for return info")
    y = qr_y - 25

    # --- Address Section ---
    draw_line("Sender:", bold=True)
    if partner:
        draw_line(partner["name"])
        if "street" in partner.keys() and partner["street"]:
            draw_line(partner["street"])
        city_line = f"{partner['zip']} {partner['city']}".strip()
        draw_line(city_line)
        if "country" in partner.keys() and partner["country"]:
            draw_line(partner["country"])
    else:
        draw_line("(Unknown sender)")

    y -= 6

    draw_line("Receiver:", bold=True)
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
    c.drawCentredString(width / 2, final_y, "Stick this label on your return parcel.")

    c.showPage()
    c.save()

    buffer.seek(0)
    return Response(
        buffer.read(),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="return_label_{return_code}.pdf"'}
    )
