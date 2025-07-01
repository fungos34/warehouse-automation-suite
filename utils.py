import qrcode
from reportlab.lib.utils import ImageReader
from io import BytesIO
from reportlab.lib.units import mm
from reportlab.lib.pagesizes import A4

def draw_qr_code(canvas, code, page_width, page_height, qr_size=60, margin=20):
    # Generate QR code image
    qr = qrcode.QRCode(box_size=2, border=1)
    qr.add_data(code)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    qr_buffer = BytesIO()
    img.save(qr_buffer, format="PNG")
    qr_buffer.seek(0)
    qr_img = ImageReader(qr_buffer)
    # Position: right upper corner, with margin
    x = page_width - qr_size - margin
    y = page_height - qr_size - margin
    # Draw solid box
    canvas.setLineWidth(1.5)
    canvas.rect(x - 4, y - 4, qr_size + 8, qr_size + 8, stroke=1, fill=0)
    # Draw QR code
    canvas.drawImage(qr_img, x, y, width=qr_size, height=qr_size)

def add_page_number(canvas, doc):
    canvas.setFont("Helvetica", 8)
    page_num = canvas.getPageNumber()
    canvas.drawRightString(200 * mm, 10 * mm, f"Page {page_num}")

def add_page_number_and_qr(canvas, doc, code):
    add_page_number(canvas, doc)
    page_width, page_height = A4
    draw_qr_code(canvas, code, page_width, page_height)
