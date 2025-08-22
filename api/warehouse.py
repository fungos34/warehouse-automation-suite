from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Response, Query, Body
from database import get_conn
from models import (
    TransferOrderCreate, TransferOrderLineIn,
    ActionEnum, OperationTypeEnum, StockAdjustmentIn, ManufacturingOrderCreate, LotCreate, CompanyCreate, BookingRequest, ServiceBookingCreate, SubscriptionCreate
)
from datetime import datetime, timedelta
from fastapi.responses import JSONResponse
import requests
from auth import get_current_username
from typing import List
import uuid
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image
from io import BytesIO
from PIL import Image as PILImage
from utils import add_page_number_and_qr
from run import base_url 

router = APIRouter()

# --- PICKING LIST ENDPOINT ---

@router.post("/move-lines/{move_line_id}/done", tags=["Warehouse"])
def set_move_line_done(move_line_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        conn.execute("""
            UPDATE move_line
            SET status = 'done', done_quantity = quantity
            WHERE id = ?
        """, (move_line_id,))
        conn.commit()
    return {"message": "Move line set to done"}


# --- TRANSFER ORDERS ---

@router.post("/transfer-orders/", tags=["Warehouse"])
def create_transfer_order(order: TransferOrderCreate, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        code = f"TRF-{uuid.uuid4().hex[:8].upper()}"
        cur = conn.execute(
            "INSERT INTO transfer_order (status, origin, partner_id, code) VALUES ('draft', 'Manual Transfer', ?, ?)",
            (order.partner_id, code)
        )
        conn.commit()
        return {"transfer_order_id": cur.lastrowid, "code": code}


@router.post("/transfer-orders/{transfer_order_id}/lines", tags=["Warehouse"])
def add_transfer_lines(transfer_order_id: int, lines: List[TransferOrderLineIn], username: str = Depends(get_current_username)):
    with get_conn() as conn:
        for line in lines:
            conn.execute("""
                INSERT INTO transfer_order_line (transfer_order_id, item_id, quantity, target_zone_id)
                VALUES (?, ?, ?, ?)
            """, (transfer_order_id, line.item_id, line.quantity, line.target_zone_id))
        conn.commit()
    return {"message": "Transfer lines added"}


@router.get("/transfer-orders/{transfer_order_id}/lines", tags=["Warehouse"])
def get_transfer_order_lines(transfer_order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("""
            SELECT *
            FROM transfer_order_line
            WHERE transfer_order_id = ?
            ORDER BY id
        """, (transfer_order_id,))
        return [dict(row) for row in result]

@router.get("/transfer-orders", tags=["Warehouse"])
def list_transfer_orders(status: str = None, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        query = "SELECT * FROM transfer_order"
        params = []
        if status:
            query += " WHERE status = ?"
            params.append(status)
        query += " ORDER BY id DESC"
        result = conn.execute(query, params).fetchall()
        return [dict(row) for row in result]

@router.post("/transfer-orders/{transfer_order_id}/confirm", tags=["Warehouse"])
def confirm_transfer_order(transfer_order_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        conn.execute("UPDATE transfer_order SET status = 'confirmed' WHERE id = ?", (transfer_order_id,))
        conn.commit()
    return {"message": "Transfer order confirmed"}

# --- STOCK ADJUSTMENTS ---

@router.post("/stock-adjustments/", tags=["Warehouse"])
def add_stock_adjustment(
    data: StockAdjustmentIn,
    username: str = Depends(get_current_username)
):
    with get_conn() as conn:
        conn.execute("""
            INSERT INTO stock_adjustment (item_id, location_id, delta, reason)
            VALUES (?, ?, ?, ?)
        """, (data.item_id, data.location_id, data.delta, data.reason))
        conn.commit()
    return {"message": "Stock adjusted"}


@router.get("/stock/{item_id}", tags=["Warehouse"])
def get_stock_by_item(item_id: int):  # username: str = Depends(get_current_username) # used during quotation and shipping cost calculation.
    with get_conn() as conn:
        result = conn.execute("""
            SELECT * FROM stock_by_location WHERE item_id = ?
        """, (item_id,))
        return [dict(row) for row in result]


@router.get("/dropshipping-decision", tags=["Warehouse"])
def get_dropshipping_decision(
    question_id: int = Query(None, description="If set, fetch answer for this question id"),
    item_id: int = Query(None),
    vendor_id: int = Query(None),
    customer_id: int = Query(None),
    carrier_id: int = Query(None),
    ordered_quantity: float = Query(None),
    vendor_accepts_dropship: bool = Query(None),
    warehouse_stock: float = Query(None),
    vendor_stock: float = Query(None),
    shipping_cost_vendor_customer: float = Query(None),
    shipping_cost_warehouse_customer: float = Query(None),
    # username: str = Depends(get_current_username)
):
    """
    Fetch dropshipping decision answer.
    If question_id is given, fetch by id.
    Otherwise, insert a new question and return the answer.
    """
    with get_conn() as conn:
        if question_id:
            row = conn.execute(
                "SELECT answer FROM dropshipping_question WHERE id = ?",
                (question_id,)
            ).fetchone()
            if not row or row["answer"] is None:
                raise HTTPException(status_code=404, detail="Question not found or answer not available yet")
            return {"answer": row["answer"], "question_id": question_id}
        # Validate required fields for new question (carrier_id is now optional)
        required = [item_id, vendor_id, customer_id, ordered_quantity]
        if any(v is None for v in required):
            raise HTTPException(status_code=400, detail="Missing required fields for dropshipping decision")
        try:
            cur = conn.execute(
                "INSERT INTO dropshipping_question (item_id, vendor_id, customer_id, carrier_id, ordered_quantity, vendor_accepts_dropship, warehouse_stock, vendor_stock, shipping_cost_vendor_customer, shipping_cost_warehouse_customer) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (item_id, vendor_id, customer_id, carrier_id, ordered_quantity, vendor_accepts_dropship, warehouse_stock, vendor_stock, shipping_cost_vendor_customer, shipping_cost_warehouse_customer)
            )
            question_id = cur.lastrowid
            # Wait for trigger to set the answer (should be immediate in SQLite)
            row = conn.execute(
                "SELECT answer FROM dropshipping_question WHERE id = ?",
                (question_id,)
            ).fetchone()
            if not row or row["answer"] is None:
                raise HTTPException(status_code=500, detail="Decision could not be determined")
            return {"answer": row["answer"], "question_id": question_id}
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Database error: {e}")
        

@router.get("/lots", tags=["Warehouse"])
def get_lots(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("""
            SELECT
                id,
                item_id,
                lot_number,
                origin_model,
                origin_id,
                quality_control_status,
                notes,
                created_at
            FROM lot
            ORDER BY id DESC
        """).fetchall()
        return [dict(row) for row in result]

@router.post("/lots", tags=["Warehouse"])
def create_lot(data: LotCreate):
    with get_conn() as conn:
        cur = conn.execute(
            "INSERT INTO lot (item_id, lot_number, notes) VALUES (?, ?, ?)",
            (data.item_id, data.lot_number, data.notes)
        )
        conn.commit()
        return {"id": cur.lastrowid}

# --- LOCATION ZONES ---
@router.get("/location-zones", tags=["Warehouse"])
def get_location_zones(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("""
            SELECT DISTINCT
                z.id AS zone_id,
                z.code AS zone_code,
                z.description AS zone_description
            FROM zone z
            JOIN location_zone lz ON z.id = lz.zone_id
            ORDER BY z.code
        """).fetchall()
        return [dict(row) for row in result]

# --- WAREHOUSE STOCK VIEW ---
@router.get("/warehouse-stock", tags=["Warehouse"])
def get_warehouse_stock_view(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("SELECT * FROM warehouse_stock_view")
        return [dict(row) for row in result]


# --- MOVE OVERVIEW FOR AN ORDER ---
@router.get("/origin/{origin_model}/{origin_id}/moves", tags=["Dashboard"])
def get_moves_for_origin(origin_model: str, origin_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("""
            SELECT * FROM move_and_lines_by_origin WHERE origin_model = ? AND origin_id = ? ORDER BY move_id, move_line_id
        """, (origin_model, origin_id))
        return [dict(row) for row in result]


# --- DEBUG / MONITORING ENDPOINTS ---

@router.get("/debug-log", tags=["Dashboard"])
def get_debug_log(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("SELECT * FROM debug_log ORDER BY created_at DESC")
        return [dict(row) for row in result]


@router.get("/interventions", tags=["Dashboard"])
def get_recent_interventions(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("SELECT * FROM intervention ORDER BY created_at DESC")
        return [dict(row) for row in result]


@router.get("/stock-adjustments", tags=["Dashboard"])
def get_all_stock_adjustments(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("SELECT * FROM stock_adjustment ORDER BY created_at DESC")
        return [dict(row) for row in result]
    

@router.get("/moves", tags=["Debug"])
def get_all_moves(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("""
            SELECT *
            FROM move
            ORDER BY id
        """)
        return [dict(row) for row in result]
    
@router.get("/pickings", tags=["Warehouse"])
def get_pickings(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("""
            SELECT id, status, type, origin, source_id, target_id FROM picking ORDER BY id DESC
        """).fetchall()
        return [dict(row) for row in result]
    
@router.get("/pickings/{picking_id}/move-lines", tags=["Warehouse"])
def get_move_lines_by_picking(picking_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("""
            SELECT ml.*
            FROM move_line ml
            JOIN move m ON ml.move_id = m.id
            WHERE m.picking_id = ?
            ORDER BY ml.id
        """, (picking_id,))
        return [dict(row) for row in result]
    
@router.get("/locations/empty", tags=["Warehouse"])
def get_empty_locations(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("""
            SELECT * FROM empty_locations
        """)
        return [dict(row) for row in result]
    
@router.post("/routes/", tags=["Warehouse"])
def create_route(name: str, active: bool = True, description: str = "", username: str = Depends(get_current_username)):
    with get_conn() as conn:
        conn.execute("""
            INSERT INTO route (name, active, description)
            VALUES (?, ?, ?)
        """, (name, int(active), description))
        conn.commit()
    return {"message": "Route created"}

@router.post("/rules/", tags=["Warehouse"])
def create_rule(
    name: str,
    route_id: int,
    action: ActionEnum,
    source_id: int = None,
    target_id: int = None,
    operation_type: OperationTypeEnum = OperationTypeEnum.internal,
    active: bool = True,
    description: str = "",
    username: str = Depends(get_current_username)
):
    with get_conn() as conn:
        conn.execute("""
            INSERT INTO rule (name, route_id, action, source_id, target_id, operation_type, active, description)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (name, route_id, action, source_id, target_id, operation_type, int(active), description))
        conn.commit()
    return {"message": "Rule created"}

@router.get("/move-lines", tags=["Debug"])
def get_all_move_lines(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("""
            SELECT *
            FROM move_line
            ORDER BY id
        """)
        return [dict(row) for row in result]
    
@router.get("/locations", tags=["Debug"])
def get_locations(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("""
            SELECT *
            FROM location
            ORDER BY id
        """)
        return [dict(row) for row in result]

@router.get("/zones", tags=["Warehouse"])
def get_zones(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("SELECT id, code, description FROM zone ORDER BY id").fetchall()
        return [dict(row) for row in result]

@router.get("/items/{item_id}/vendor", tags=["Catalog"])
def get_item_vendor(item_id: int):
    with get_conn() as conn:
        row = conn.execute("SELECT vendor_id FROM item WHERE id = ?", (item_id,)).fetchone()
        if not row or row["vendor_id"] is None:
            raise HTTPException(status_code=404, detail="Vendor not found for this item")
        return {"vendor_id": row["vendor_id"]}
    
    
@router.get("/items", tags=["Catalog"])
def get_items(country_code: str = None, currency_code: str = None):
    with get_conn() as conn:
        # Find the latest valid price list for the selected country/currency
        price_list_row = conn.execute("""
            SELECT pl.id, pl.currency_id, c.code as currency_code, co.id as country_id
            FROM price_list pl
            JOIN currency c ON pl.currency_id = c.id
            JOIN country co ON pl.country_id = co.id
            WHERE (? IS NULL OR co.code = ?)
              AND (? IS NULL OR c.code = ?)
              AND (pl.valid_from IS NULL OR pl.valid_from <= DATE('now'))
              AND (pl.valid_to IS NULL OR pl.valid_to >= DATE('now'))
            ORDER BY pl.valid_from DESC
            LIMIT 1
        """, (country_code, country_code, currency_code, currency_code)).fetchone()
        price_list_id = price_list_row["id"] if price_list_row else None
        country_id = price_list_row["country_id"] if price_list_row else None

        # Only fetch items from the selected price list
        result = conn.execute("""
            SELECT 
                i.id, 
                i.name, 
                i.sku, 
                i.vendor_id,
                i.cost,
                i.is_sellable,
                i.is_digital,
                i.is_assemblable,
                i.is_disassemblable,
                i.description,
                i.service_window_id,
                sw.timedelta AS window_period,
                sw.unit_time AS window_unit,
                cost_cur.code AS cost_currency_code,
                i.cost_currency_id,
                pli.price AS sales_price,
                sales_cur.code AS sales_currency_code,
                sales_cur.symbol AS sales_currency_symbol,
                i.image_url,
                t.percent AS tax_percent,
                t.label AS tax_label
            FROM price_list_item pli
            JOIN item i ON pli.item_id = i.id
            LEFT JOIN service_window sw ON i.service_window_id = sw.id
            LEFT JOIN currency cost_cur ON i.cost_currency_id = cost_cur.id
            JOIN price_list pl ON pli.price_list_id = pl.id
            JOIN currency sales_cur ON pl.currency_id = sales_cur.id
            LEFT JOIN item_hs_country ihc ON ihc.item_id = i.id AND ihc.country_id = ?
            LEFT JOIN hs_country_tax hct ON hct.hs_code_id = ihc.hs_code_id AND hct.country_id = ?
            LEFT JOIN tax t ON t.id = hct.tax_id
            WHERE pli.price_list_id = ?
            ORDER BY i.id
        """, (country_id, country_id, price_list_id)).fetchall()
        return [dict(row) for row in result]
    

@router.get("/items/by-sku/{sku}", tags=["Catalog"])
def get_item_by_sku(sku: str):
    with get_conn() as conn:
        cur = conn.execute("SELECT * FROM item WHERE sku = ?", (sku,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Item not found")
        # Convert row to dict
        columns = [col[0] for col in cur.description]
        item = dict(zip(columns, row))
        return item

@router.get("/warehouse-items", tags=["Warehouse"])
def get_warehouse_items(username: str = Depends(get_current_username)):
    """
    Return all items that currently have stock in any zone that is NOT a vendor or customer zone.
    """
    with get_conn() as conn:
        # Get all vendor and customer zone ids
        vendor_customer_zone_ids = [
            row["id"] for row in conn.execute(
                "SELECT id FROM zone WHERE code IN ('ZON08', 'ZON09')"
            )
        ]
        # Build exclusion string for SQL
        exclusion = ",".join("?" for _ in vendor_customer_zone_ids) if vendor_customer_zone_ids else "NULL"
        # Query items with stock in non-vendor/customer zones
        query = f"""
            SELECT 
                i.id, 
                i.name, 
                i.sku, 
                SUM(s.quantity) as total_quantity
            FROM stock s
            JOIN item i ON i.id = s.item_id
            JOIN location_zone lz ON lz.location_id = s.location_id
            WHERE s.quantity > 0
              AND lz.zone_id NOT IN ({exclusion})
            GROUP BY i.id, i.name, i.sku
            HAVING total_quantity > 0
            ORDER BY i.name
        """
        result = conn.execute(query, vendor_customer_zone_ids).fetchall()
        return [dict(row) for row in result]


@router.get("/items/{item_id}", tags=["Catalog"])
def get_item(item_id: int):
    with get_conn() as conn:
        result = conn.execute("SELECT * FROM item WHERE id = ?", (item_id,)).fetchone()
        if not result:
            raise HTTPException(status_code=404, detail="Item not found")
        return dict(result)
    

@router.get("/country-info", response_class=JSONResponse)
def get_country_info(country: str):
    with get_conn() as conn:
        row = conn.execute("""
            SELECT id, code, name, currency_id, language_id
            FROM country
            WHERE code = ?
            LIMIT 1
        """, (country,)).fetchone()
        if not row:
            return JSONResponse(status_code=404, content={"detail": "Country not found"})
        currency = conn.execute("SELECT code, symbol FROM currency WHERE id = ?", (row["currency_id"],)).fetchone()
        language = conn.execute("SELECT code FROM language WHERE id = ?", (row["language_id"],)).fetchone()
        return {
            "id": row["id"],  # <-- Add this line
            "code": row["code"],
            "name": row["name"],
            "currency_code": currency["code"] if currency else "EUR",
            "currency_symbol": currency["symbol"] if currency else "€",
            "language": language["code"] if language else "en"
        }


@router.get("/service-hours/{sku}", tags=["Service"])
def get_service_hours_by_sku(sku: str):
    with get_conn() as conn:
        item_row = conn.execute("SELECT id FROM item WHERE sku = ?", (sku,)).fetchone()
        if not item_row:
            raise HTTPException(status_code=404, detail="Item not found")
        item_id = item_row["id"]
        hours = conn.execute("""
            SELECT weekday, start_time, end_time
            FROM service_hours
            WHERE item_id = ?
            ORDER BY 
                CASE weekday
                    WHEN 'Monday' THEN 1
                    WHEN 'Tuesday' THEN 2
                    WHEN 'Wednesday' THEN 3
                    WHEN 'Thursday' THEN 4
                    WHEN 'Friday' THEN 5
                    WHEN 'Saturday' THEN 6
                    WHEN 'Sunday' THEN 7
                    ELSE 8
                END
        """, (item_id,)).fetchall()
        exceptions = conn.execute("""
            SELECT start_datetime, end_datetime, description
            FROM service_exception
            WHERE item_id = ?
            ORDER BY start_datetime
        """, (item_id,)).fetchall()
        return {
            "hours": [dict(row) for row in hours],
            "exceptions": [dict(row) for row in exceptions]
        }


@router.get("/service-bookings/{sku}/available", tags=["Service"])
def get_available_service_bookings(sku: str):
    with get_conn() as conn:
        item_row = conn.execute("SELECT id FROM item WHERE sku = ?", (sku,)).fetchone()
        if not item_row:
            raise HTTPException(status_code=404, detail="Item not found")
        item_id = item_row["id"]
        bookings = conn.execute("""
            SELECT id, start_datetime, end_datetime, status
            FROM service_booking
            WHERE item_id = ? AND status = 'pending'
            ORDER BY start_datetime
        """, (item_id,)).fetchall()
        return [dict(row) for row in bookings]


@router.post("/service-bookings/{booking_id}/book", tags=["Service"])
def book_service_booking(booking_id: int, req: BookingRequest):
    partner_id = req.partner_id
    with get_conn() as conn:
        # Only allow booking if still pending
        booking = conn.execute("SELECT status FROM service_booking WHERE id = ?", (booking_id,)).fetchone()
        if not booking or booking["status"] != "pending":
            raise HTTPException(status_code=400, detail="Booking not available")
        conn.execute("""
            UPDATE service_booking
            SET partner_id = ?, status = 'confirmed'
            WHERE id = ?
        """, (partner_id, booking_id))
        conn.commit()
        return {"message": "Booking confirmed"}



# @router.post("/service-bookings", tags=["Service"])
# def create_service_booking(data: ServiceBookingCreate):
#     with get_conn() as conn:
#         window = conn.execute(
#             "SELECT timedelta, unit_time FROM service_window WHERE id=?",
#             (data.service_window_id,)
#         ).fetchone()
#         if not window:
#             raise HTTPException(status_code=404, detail="Service window not found")
#         start = datetime.fromisoformat(data.start_datetime) if data.start_datetime else datetime.now()
#         if window["unit_time"] == "month":
#             end = start + timedelta(days=30)
#         elif window["unit_time"] == "year":
#             end = start + timedelta(days=365)
#         else:
#             # fallback: use timedelta as days
#             end = start + timedelta(**{window["unit_time"] + "s": window["timedelta"]})
#         cur = conn.execute(
#             "INSERT INTO service_booking (partner_id, item_id, service_window_id, start_datetime, end_datetime, status) VALUES (?, ?, ?, ?, ?, 'confirmed')",
#             (data.partner_id, data.item_id, data.service_window_id, start.isoformat(), end.isoformat())
#         )
#         conn.commit()
#         return {
#             "booking_id": cur.lastrowid,
#             "start_datetime": start.isoformat(),
#             "end_datetime": end.isoformat()
#         }

def parse_iso_datetime(dt_str):
    if dt_str.endswith('Z'):
        dt_str = dt_str[:-1]
    if '.' in dt_str:
        dt_str = dt_str.split('.')[0]
    return datetime.fromisoformat(dt_str)

@router.post("/subscriptions", tags=["Service"])
def create_subscription(data: SubscriptionCreate):
    with get_conn() as conn:
        window = conn.execute(
            "SELECT timedelta, unit_time FROM service_window WHERE id=?",
            (data.service_window_id,)
        ).fetchone()
        if not window:
            raise HTTPException(status_code=404, detail="Service window not found")
        start = parse_iso_datetime(data.start_date) if data.start_date else datetime.now()
        # Calculate end date based on window
        if window["unit_time"] == "month":
            end = start + timedelta(days=30 * window["timedelta"])
        elif window["unit_time"] == "year":
            end = start + timedelta(days=365 * window["timedelta"])
        elif window["unit_time"] == "day":
            end = start + timedelta(days=window["timedelta"])
        elif window["unit_time"] == "week":
            end = start + timedelta(weeks=window["timedelta"])
        else:
            end = start
        cur = conn.execute(
            "INSERT INTO subscription (item_id, partner_id, service_window_id, start_date, end_date, lot_id) VALUES (?, ?, ?, ?, ?, ?)",
            (data.item_id, data.partner_id, data.service_window_id, start.date().isoformat(), end.date().isoformat(), getattr(data, "lot_id", None))
        )
        conn.commit()
        return {
            "subscription_id": cur.lastrowid,
            "start_date": start.date().isoformat(),
            "end_date": end.date().isoformat()
        }

@router.post("/stock-adjustments/", tags=["Warehouse"])
def add_stock_adjustment(data: StockAdjustmentIn, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        conn.execute("""
            INSERT INTO stock_adjustment (item_id, location_id, delta, reason)
            VALUES (?, ?, ?, ?)
        """, (data.item_id, data.location_id, data.delta, data.reason))
        conn.commit()
    return {"message": "Stock adjusted"}


@router.get("/manufacturing-orders/", tags=["Warehouse"])
def list_manufacturing_orders(status: str = None, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        if status:
            result = conn.execute(
                "SELECT * FROM manufacturing_order WHERE status = ?", (status,)
            ).fetchall()
        else:
            result = conn.execute(
                "SELECT * FROM manufacturing_order"
            ).fetchall()
        return [dict(row) for row in result]
    

@router.post("/manufacturing-orders/{mo_id}/done", tags=["Warehouse"])
def set_manufacturing_order_done(mo_id: int, username: str = Depends(get_current_username)):
    print(f"Setting manufacturing order {mo_id} to done")
    with get_conn() as conn:
        updated = conn.execute(
            "UPDATE manufacturing_order SET status = 'done' WHERE id = ? AND status = 'confirmed'", (mo_id,)
        ).rowcount
        conn.commit()
        if not updated:
            raise HTTPException(status_code=404, detail="Manufacturing order not found or not in confirmed status")

        # --- Carrier label logic ---
        # 1. Find the SO via trigger
        mo = conn.execute("SELECT * FROM manufacturing_order WHERE id = ?", (mo_id,)).fetchone()
        if not mo or not mo["trigger_id"]:
            return {"message": "Manufacturing order set to done (no trigger, no label generated)"}
        trigger = conn.execute("SELECT * FROM trigger WHERE id = ?", (mo["trigger_id"],)).fetchone()
        if not trigger or trigger["origin_model"] != "unbuild_order":
            return {"message": "Manufacturing order set to done (no UO trigger, no label generated)"}
        uo = conn.execute("SELECT * FROM unbuild_order WHERE id = ?", (trigger["origin_id"],)).fetchone()
        if not uo:
            return {"message": "Manufacturing order set to done (no UO found, no label generated)"}
        
        # 2. Find the SO via UO
        if not uo["origin_id"] or not uo["origin_model"] or uo["origin_model"] != "sale_order":
            return {"message": "Manufacturing order set to done (no SO in UO, no label generated)"}
        so = conn.execute("SELECT * FROM sale_order WHERE id = ?", (uo["origin_id"],)).fetchone()
        if not so:
            return {"message": "Manufacturing order set to done (no SO found, no label generated)"}
        quotation = conn.execute("SELECT * FROM quotation WHERE id = ?", (so["quotation_id"],)).fetchone()
        if not quotation or not quotation["ship"]:
            return {"message": "Manufacturing order set to done (not a shipping order, no label generated)"}
        print("✅ Manufacturing order set to done, found SO and quotation:", so, quotation)
        # 2. Find the shipping quotation_line (with carrier_id) and its lot_id
        shipping_line = conn.execute("""
            SELECT lot_id
            FROM quotation_line
            WHERE quotation_id = ? AND lot_id IS NOT NULL
            ORDER BY id DESC LIMIT 1
        """, (quotation["id"],)).fetchone()
        print("✅ Shipping line found:", shipping_line)
        if not shipping_line or not shipping_line["lot_id"]:
            return {"message": "MO done, but no shipping lot_id found in quotation lines"}

        lot_id = shipping_line["lot_id"]

        # 3. Get the rate_id from the lot.note field
        lot = conn.execute("SELECT notes FROM lot WHERE id = ?", (lot_id,)).fetchone()
        if not lot or not lot["notes"]:
            return {"message": "MO done, but no Shippo rate_id found in lot notes"}
        rate_id = lot["notes"]

        # 4. Call Shippo label endpoint with rate_id
        try:
            print("rate id: ", rate_id.strip())
            shippo_resp = requests.post(
                f"{base_url}shippo/purchase-label",
                json={"rate_id": rate_id.strip()}
            )
            shippo_resp.raise_for_status()
            label_info = shippo_resp.json()
            if "label_url" not in label_info:
                return {"message": f"MO done, but label generation failed: {label_info.get('error', 'Unknown error')}"}
            label_url = label_info["label_url"]
            tracking_number = label_info.get("tracking_number", "N/A")
            print("✅ Carrier label generated:", label_url, tracking_number)
        except Exception as e:
            return {"message": f"MO done, but label generation failed: {e}"}

        # 5. Store label URL and lot_id in DB
        conn.execute(
            "INSERT INTO carrier_label (mo_id, lot_id, label_url, tracking_number) VALUES (?, ?, ?, ?)",
            (mo_id, lot_id, label_url, tracking_number)
        )
        conn.commit()
        return {
            "message": "Manufacturing order set to done, carrier label generated",
            "label_url": label_url,
            "lot_id": lot_id
        }


@router.get("/carrier-labels", tags=["Warehouse"])
def list_carrier_labels(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        rows = conn.execute("SELECT * FROM carrier_label").fetchall()
        return [dict(row) for row in rows]

# Endpoint to download or redirect to the label
@router.get("/manufacturing-orders/{mo_id}/carrier-label", tags=["Warehouse"])
def download_carrier_label(mo_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        row = conn.execute(
            "SELECT label_url FROM carrier_label WHERE mo_id = ? ORDER BY id DESC LIMIT 1", (mo_id,)
        ).fetchone()
        if not row or not row["label_url"]:
            raise HTTPException(status_code=404, detail="Carrier label not found")
        # Fetch the PDF and return as attachment
        resp = requests.get(row["label_url"])
        if resp.ok:
            return Response(
                resp.content,
                media_type="application/pdf",
                headers={"Content-Disposition": f"inline; filename=carrier_label_MO_{mo_id}.pdf"}
            )
        else:
            raise HTTPException(status_code=502, detail="Failed to fetch label from Shippo")

    
@router.post("/manufacturing-orders/{mo_id}/confirm", tags=["Warehouse"])
def confirm_manufacturing_order(mo_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        updated = conn.execute(
            "UPDATE manufacturing_order SET status = 'confirmed' WHERE id = ? AND status = 'draft'", (mo_id,)
        ).rowcount
        conn.commit()
        if not updated:
            raise HTTPException(status_code=404, detail="Manufacturing order not found or not in draft status")
    return {"message": "Manufacturing order confirmed"}

@router.post("/manufacturing-orders/{mo_id}/cancel", tags=["Warehouse"])
def cancel_manufacturing_order(mo_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        updated = conn.execute(
            "UPDATE manufacturing_order SET status = 'cancelled' WHERE id = ? AND status = 'draft'", (mo_id,)
        ).rowcount
        conn.commit()
        if not updated:
            raise HTTPException(status_code=404, detail="Manufacturing order not found or not in draft status")
    return {"message": "Manufacturing order cancelled"}


@router.get("/manufacturing-items", tags=["Warehouse"])
def get_manufacturing_items(username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("""
            SELECT id, name, sku
            FROM item
            WHERE bom_id IS NOT NULL
            ORDER BY name
        """).fetchall()
        return [dict(row) for row in result]
    

@router.post("/manufacturing-orders/", tags=["Warehouse"])
def create_manufacturing_order(
    data: ManufacturingOrderCreate,
    username: str = Depends(get_current_username)
):
    code = f"MO-{uuid.uuid4().hex[:8].upper()}"
    planned_start = data.planned_start or datetime.now().isoformat()
    planned_end = data.planned_end or (datetime.now() + datetime.timedelta(days=1)).isoformat()
    with get_conn() as conn:
        # Get partner_id for current user
        partner_row = conn.execute(
            "SELECT partner_id FROM user WHERE username = ?", (username,)
        ).fetchone()
        if not partner_row:
            raise HTTPException(status_code=404, detail="User not found")
        partner_id = partner_row["partner_id"]
        cur = conn.execute("""
            INSERT INTO manufacturing_order (code, partner_id, item_id, quantity, status, planned_start, planned_end, origin, manufacturing_location_id)
            VALUES (?, ?, ?, ?, 'draft', ?, ?, ?, (
                SELECT lz.location_id
                FROM location_zone lz
                JOIN zone z ON lz.zone_id = z.id
                WHERE z.production_area = 'primary'
                ORDER BY lz.location_id ASC
                LIMIT 1
            ))
        """, (code, partner_id, data.item_id, data.quantity, planned_start, planned_end, "Manual creation"))  # Assuming 11 is the default manufacturing location ID
        conn.commit()
        return {"manufacturing_order_id": cur.lastrowid, "code": code}


@router.post("/unbuild-orders/{order_code}/confirm-receipt", tags=["Sales"])
def confirm_unbuild_order_receipt(order_code: str):  # username: str = Depends(get_current_username)
    with get_conn() as conn:
        # Find the unbuild order by code
        uo = conn.execute(
            "SELECT id, status FROM unbuild_order WHERE code = ?",
            (order_code,)
        ).fetchone()
        if not uo:
            raise HTTPException(status_code=404, detail="Unbuild order not found")
        if uo["status"] == "done":
            return {"message": "Receipt already confirmed"}
        conn.execute(
            "UPDATE unbuild_order SET status = 'done' WHERE id = ?",
            (uo["id"],)
        )
        conn.commit()
        return {"message": "Receipt confirmed"}


@router.get("/company/name", response_class=JSONResponse)
async def get_company_name():
    with get_conn() as conn:
        row = conn.execute("SELECT name FROM company LIMIT 1").fetchone()
        return {"name": row["name"] if row else "Shop"}


@router.get("/company/address", response_class=JSONResponse)
async def get_company_address():
    with get_conn() as conn:
        row = conn.execute("""
            SELECT c.name AS company_name, c.logo_url, c.website,
                p.street, p.zip, p.city, co.name AS country, p.phone, p.email
            FROM company c
            JOIN partner p ON c.partner_id = p.id
            LEFT JOIN country co ON p.country_id = co.id
            LIMIT 1
        """).fetchone()
        return {
            "name": row["company_name"] if row else "",
            "logo_url": row["logo_url"] if row else "",
            "website": row["website"] if row else "",
            "street": row["street"] if row else "",
            "zip": row["zip"] if row else "",
            "city": row["city"] if row else "",
            "country": row["country"] if row else "",
            "phone": row["phone"] if row else "",
            "email": row["email"] if row else ""
        }
    
@router.post("/companies", tags=["Company"])
def create_company(data: CompanyCreate):
    with get_conn() as conn:
        cur = conn.execute("""
            INSERT INTO company (name, vat_number, logo_url, website, partner_id)
            VALUES (?, ?, ?, ?, ?)
        """, (data.name, data.vat_number, data.logo_url, data.website, data.partner_id))
        conn.commit()
        return {"id": cur.lastrowid}


@router.get("/company/{company_id}/opening-hours", tags=["Company"])
def get_opening_hours(company_id: int):
    with get_conn() as conn:
        rows = conn.execute("""
            SELECT day_of_week, open_time, close_time
            FROM opening_hours
            WHERE company_id = ?
            ORDER BY 
                CASE day_of_week
                    WHEN 'Monday' THEN 1
                    WHEN 'Tuesday' THEN 2
                    WHEN 'Wednesday' THEN 3
                    WHEN 'Thursday' THEN 4
                    WHEN 'Friday' THEN 5
                    WHEN 'Saturday' THEN 6
                    WHEN 'Sunday' THEN 7
                    ELSE 8
                END
        """, (company_id,)).fetchall()
        return [dict(row) for row in rows]


@router.post("/bom/{bom_id}/file", tags=["Warehouse"])
def upload_bom_file(
    bom_id: int,
    file: UploadFile = File(...),
    username: str = Depends(get_current_username)
):
    content = file.file.read()
    filename = file.filename
    mimetype = file.content_type
    with get_conn() as conn:
        conn.execute(
            "UPDATE bom SET file = ?, file_name = ?, file_type = ? WHERE id = ?",
            (content, filename, mimetype, bom_id)
        )
        conn.commit()
    return {"message": "BOM file uploaded"}


@router.get("/manufacturing-orders/{mo_id}/download", tags=["Warehouse"])
def download_manufacturing_order_pdf(mo_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        mo = conn.execute("""
            SELECT mo.*, i.name AS item_name, i.sku, p.name AS partner_name, p.street, p.city, p.country, p.zip,
                   c.name AS company_name, cp.street AS company_street, cp.city AS company_city, cp.country AS company_country, cp.zip AS company_zip
            FROM manufacturing_order mo
            JOIN item i ON mo.item_id = i.id
            JOIN partner p ON mo.partner_id = p.id
            JOIN company c ON c.id = 1
            JOIN partner cp ON c.partner_id = cp.id
            WHERE mo.id = ?
        """, (mo_id,)).fetchone()
        if not mo:
            raise HTTPException(status_code=404, detail="Manufacturing order not found")
        bom = conn.execute("SELECT * FROM bom WHERE id = (SELECT bom_id FROM item WHERE id = ?)", (mo["item_id"],)).fetchone()
        bom_lines = conn.execute("""
            SELECT bl.*, it.name AS component_name, it.sku AS component_sku, it.vendor_id, it.cost, cur.code AS cost_currency
            FROM bom_line bl
            JOIN item it ON bl.item_id = it.id
            LEFT JOIN currency cur ON it.cost_currency_id = cur.id
            WHERE bl.bom_id = ?
        """, (bom["id"],)).fetchall()

    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, rightMargin=30, leftMargin=30, topMargin=30, bottomMargin=18)
    elements = []
    styles = getSampleStyleSheet()

    # Company info
    company_lines = [
        f"<b>{mo['company_name']}</b>",
        f"{mo['company_street']}, {mo['company_zip']} {mo['company_city']}, {mo['company_country']}",
    ]
    elements.append(Paragraph("<br/>".join(filter(None, company_lines)), styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Contractor info
    contractor_lines = [
        "<b>Contractor:</b>",
        mo["partner_name"],
        mo["street"],
        f"{mo['zip']} {mo['city']}, {mo['country']}",
    ]
    elements.append(Paragraph("<br/>".join(filter(None, contractor_lines)), styles["Normal"]))
    elements.append(Spacer(1, 12))

    # MO Info
    elements.append(Paragraph(f"Date: {datetime.now().strftime('%Y-%m-%d')}", styles["Normal"]))
    elements.append(Paragraph(f"<b>Manufacturing Order {mo['code']}</b>", styles["Title"]))
    elements.append(Paragraph(f"Status: {mo['status']}", styles["Normal"]))
    elements.append(Paragraph(f"Product: {mo['item_name']} (SKU: {mo['sku']})", styles["Normal"]))
    elements.append(Paragraph(f"Quantity: {mo['quantity']}", styles["Normal"]))
    elements.append(Paragraph(f"Planned Start: {mo['planned_start']}", styles["Normal"]))
    elements.append(Paragraph(f"Planned End: {mo['planned_end']}", styles["Normal"]))
    elements.append(Spacer(1, 12))

    # BOM Table with costs
    elements.append(Paragraph("<b>Bill of Material (BOM)</b>", styles["Heading3"]))
    bom_data = [["Component", "SKU", "Lot Number", "Vendor", "Per Product", "Total for MO", "Unit Cost", "Total Cost"]]
    total_cost = 0.0
    for bl in bom_lines:
        vendor_name = ""
        if bl["vendor_id"]:
            vendor = conn.execute("SELECT name FROM partner WHERE id = ?", (bl["vendor_id"],)).fetchone()
            vendor_name = vendor["name"] if vendor else ""
        unit_cost = float(bl["cost"] or 0)
        total_qty = float(bl["quantity"]) * float(mo["quantity"])
        line_cost = unit_cost * total_qty
        total_cost += line_cost
        lot_number = "-"
        if "lot_id" in bl.keys() and bl["lot_id"]:
            lot_row = conn.execute("SELECT lot_number FROM lot WHERE id = ?", (bl["lot_id"],)).fetchone()
            lot_number = lot_row["lot_number"] if lot_row and lot_row["lot_number"] else "-"
        bom_data.append([
            bl["component_name"],
            bl["component_sku"],
            lot_number,
            vendor_name,
            str(bl["quantity"]),
            str(total_qty),
            f"{unit_cost:.2f} {bl['cost_currency'] or ''}",
            f"{line_cost:.2f} {bl['cost_currency'] or ''}"
        ])
    bom_table = Table(bom_data, colWidths=[90, 60, 110, 70, 50, 60, 50, 50])
    bom_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.lightgrey),
        ('TEXTCOLOR', (0,0), (-1,0), colors.black),
        ('ALIGN', (1,1), (-1,-1), 'CENTER'),
        ('GRID', (0,0), (-1,-1), 0.5, colors.black),
        ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
        ('FONTNAME', (0,1), (-1,-1), 'Helvetica'),
        ('FONTSIZE', (0,0), (-1,-1), 8),
        ('BOTTOMPADDING', (0,0), (-1,0), 6),
        ('TOPPADDING', (0,0), (-1,0), 6),
    ]))
    elements.append(bom_table)
    elements.append(Spacer(1, 12))
    elements.append(Paragraph(f"<b>Total BOM Cost: {total_cost:.2f} EUR</b>", styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Instructions
    elements.append(Paragraph("<b>Instructions:</b>", styles["Heading3"]))
    elements.append(Paragraph(bom["instructions"], styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Signatures header
    elements.append(Paragraph("<b>Signatures</b>", styles["Heading3"]))
    elements.append(Paragraph("Date and Place: ___________________________", styles["Normal"]))
    elements.append(Spacer(1, 12))
    elements.append(Paragraph("Manufacturer: ___________________________", styles["Normal"]))
    elements.append(Spacer(1, 12))
    elements.append(Paragraph("Contractor:   ___________________________", styles["Normal"]))
    elements.append(Spacer(1, 24))

    # BOM File (PDF or JPG) - always last
    if bom["file"]:
        file_type = bom["file_type"] if "file_type" in bom.keys() else ""
        file_name = bom["file_name"] if "file_name" in bom.keys() else "attachment"
        elements.append(Paragraph("<b>BOM Attachment</b>", styles["Heading3"]))
        elements.append(Paragraph(f"File: {file_name}", styles["Normal"]))
        elements.append(Paragraph(f"Type: {file_type}", styles["Normal"]))
        elements.append(Spacer(1, 12))
        if file_type == "application/pdf":
            elements.append(Paragraph("See attached PDF for full instructions.", styles["Normal"]))
            elements.append(Paragraph(f"Size: {len(bom['file'])} bytes", styles["Normal"]))
        elif file_type == "image/jpeg":
            try:
                img = PILImage.open(BytesIO(bom["file"]))
                img_width, img_height = img.size
                aspect = img_height / img_width
                display_width = 400
                display_height = int(display_width * aspect)
                img_buffer = BytesIO(bom["file"])
                elements.append(Image(img_buffer, width=display_width, height=display_height))
                elements.append(Spacer(1, 12))
            except Exception:
                elements.append(Paragraph("Error displaying image.", styles["Normal"]))
        else:
            elements.append(Paragraph("Unsupported file type.", styles["Normal"]))

    # Build PDF with page numbers
    doc.build(
        elements,
        onFirstPage=lambda c, d: add_page_number_and_qr(c, d, mo['code']),
        onLaterPages=lambda c, d: add_page_number_and_qr(c, d, mo['code'])
    )
    buffer.seek(0)
    return Response(
        buffer.read(),
        media_type="application/pdf",
        headers = {"Content-Disposition": f"inline; filename=manufacturing_order_{mo['code']}.pdf"}
    )


@router.get("/manufacturing-orders/{mo_id}/receipt", tags=["Warehouse"])
def download_manufacturing_receipt_pdf(mo_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        mo = conn.execute("""
            SELECT mo.*, i.name AS item_name, i.sku, p.name AS partner_name, p.street, p.city, p.country, p.zip,
                   c.name AS company_name, cp.street AS company_street, cp.city AS company_city, cp.country AS company_country, cp.zip AS company_zip
            FROM manufacturing_order mo
            JOIN item i ON mo.item_id = i.id
            JOIN partner p ON mo.partner_id = p.id
            JOIN company c ON c.id = 1
            JOIN partner cp ON c.partner_id = cp.id
            WHERE mo.id = ?
        """, (mo_id,)).fetchone()
        if not mo:
            raise HTTPException(status_code=404, detail="Manufacturing order not found")
        bom = conn.execute("SELECT * FROM bom WHERE id = (SELECT bom_id FROM item WHERE id = ?)", (mo["item_id"],)).fetchone()
        bom_lines = conn.execute("""
            SELECT bl.*, it.name AS component_name, it.sku AS component_sku, it.vendor_id, it.cost, cur.code AS cost_currency,
                   bl.lot_id
            FROM bom_line bl
            JOIN item it ON bl.item_id = it.id
            LEFT JOIN currency cur ON it.cost_currency_id = cur.id
            WHERE bl.bom_id = ?
        """, (bom["id"],)).fetchall()
        # Products created (lots)
        lots = conn.execute("""
            SELECT l.id, l.lot_number, l.created_at, l.quality_control_status
            FROM lot l
            WHERE l.origin_model = 'manufacturing_order' AND l.origin_id = ?
            ORDER BY l.id
        """, (mo_id,)).fetchall()

    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, rightMargin=30, leftMargin=30, topMargin=30, bottomMargin=18)
    elements = []
    styles = getSampleStyleSheet()

    # Header
    elements.append(Paragraph(f"<b>Manufacturing Report</b>", styles["Title"]))
    elements.append(Spacer(1, 12))

    # Company info
    company_lines = [
        f"<b>{mo['company_name']}</b>",
        f"{mo['company_street']}, {mo['company_zip']} {mo['company_city']}, {mo['company_country']}",
    ]
    elements.append(Paragraph("<br/>".join(filter(None, company_lines)), styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Contractor info
    contractor_lines = [
        "<b>Contractor:</b>",
        mo["partner_name"],
        mo["street"],
        f"{mo['zip']} {mo['city']}, {mo['country']}",
    ]
    elements.append(Paragraph("<br/>".join(filter(None, contractor_lines)), styles["Normal"]))
    elements.append(Spacer(1, 12))

    # MO Info
    elements.append(Paragraph(f"Date: {datetime.now().strftime('%Y-%m-%d')}", styles["Normal"]))
    elements.append(Paragraph(f"<b>Manufacturing Order {mo['code']}</b>", styles["Heading2"]))
    elements.append(Paragraph(f"Status: {mo['status']}", styles["Normal"]))
    elements.append(Paragraph(f"Product: {mo['item_name']} (SKU: {mo['sku']})", styles["Normal"]))
    elements.append(Paragraph(f"Quantity: {mo['quantity']}", styles["Normal"]))
    elements.append(Paragraph(f"Planned Start: {mo['planned_start']}", styles["Normal"]))
    elements.append(Paragraph(f"Planned End: {mo['planned_end']}", styles["Normal"]))
    elements.append(Spacer(1, 12))


    # BOM Table with costs and lot number (lot number after SKU)
    elements.append(Paragraph("<b>Bill of Material (BOM)</b>", styles["Heading3"]))
    bom_data = [["Component", "SKU", "Lot Number", "Vendor", "Per Product", "Total for MO", "Unit Cost", "Total Cost"]]
    total_cost = 0.0
    for bl in bom_lines:
        vendor_name = ""
        if bl["vendor_id"]:
            vendor = conn.execute("SELECT name FROM partner WHERE id = ?", (bl["vendor_id"],)).fetchone()
            vendor_name = vendor["name"] if vendor else ""
        unit_cost = float(bl["cost"] or 0)
        total_qty = float(bl["quantity"]) * float(mo["quantity"])
        line_cost = unit_cost * total_qty
        total_cost += line_cost
        # Get lot number if lot_id is present
        lot_number = "-"
        if "lot_id" in bl.keys() and bl["lot_id"]:
            lot_row = conn.execute("SELECT lot_number FROM lot WHERE id = ?", (bl["lot_id"],)).fetchone()
            lot_number = lot_row["lot_number"] if lot_row and lot_row["lot_number"] is not None else "-"
        bom_data.append([
            bl["component_name"],
            bl["component_sku"],
            lot_number,
            vendor_name,
            str(bl["quantity"]),
            str(total_qty),
            f"{unit_cost:.2f} {bl['cost_currency'] or ''}",
            f"{line_cost:.2f} {bl['cost_currency'] or ''}"
        ])
    bom_table = Table(bom_data, colWidths=[90, 60, 110, 70, 50, 60, 50, 50])
    bom_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.lightgrey),
        ('TEXTCOLOR', (0,0), (-1,0), colors.black),
        ('ALIGN', (0,0), (-1,-1), 'CENTER'),
        ('GRID', (0,0), (-1,-1), 0.5, colors.black),
        ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
        ('FONTNAME', (0,1), (-1,-1), 'Helvetica'),
        ('FONTSIZE', (0,0), (-1,-1), 8),  # smaller font
        ('BOTTOMPADDING', (0,0), (-1,0), 4),
        ('TOPPADDING', (0,0), (-1,0), 4),
    ]))
    elements.append(bom_table)
    elements.append(Spacer(1, 12))
    elements.append(Paragraph(f"<b>Total BOM Cost: {total_cost:.2f} EUR</b>", styles["Normal"]))
    elements.append(Spacer(1, 12))

    # Products created (lots) table: name, sku, lot number, batch size, created at, quality status
    elements.append(Paragraph("<b>Products Created</b>", styles["Heading3"]))
    lot_data = [["Name", "SKU", "Lot Number", "Batch Size", "Created At", "Quality Status"]]
    for l in lots:
        # Get item info for this lot
        item = conn.execute("SELECT name, sku FROM item WHERE id = (SELECT item_id FROM lot WHERE id = ?)", (l["id"],)).fetchone()
        # Get batch size (sum of stock for this lot)
        batch_size_row = conn.execute("SELECT SUM(quantity) as batch_size FROM stock WHERE lot_id = ?", (l["id"],)).fetchone()
        batch_size = batch_size_row["batch_size"] if batch_size_row and batch_size_row["batch_size"] is not None else "-"
        lot_data.append([
            item["name"] if item else "",
            item["sku"] if item else "",
            l["lot_number"],
            str(batch_size),
            l["created_at"],
            l["quality_control_status"]
        ])
    lot_table = Table(lot_data, colWidths=[80, 60, 110, 50, 80, 70])
    lot_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.lightgrey),
        ('TEXTCOLOR', (0,0), (-1,0), colors.black),
        ('ALIGN', (0,0), (-1,-1), 'CENTER'),
        ('GRID', (0,0), (-1,-1), 0.5, colors.black),
        ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
        ('FONTNAME', (0,1), (-1,-1), 'Helvetica'),
        ('FONTSIZE', (0,0), (-1,-1), 8),  # smaller font
        ('BOTTOMPADDING', (0,0), (-1,0), 4),
        ('TOPPADDING', (0,0), (-1,0), 4),
    ]))
    elements.append(lot_table)
    elements.append(Spacer(1, 12))

    # Signatures header
    elements.append(Paragraph("<b>Signatures</b>", styles["Heading3"]))
    elements.append(Paragraph("Date and Place: ___________________________", styles["Normal"]))
    elements.append(Spacer(1, 12))
    elements.append(Paragraph("Manufacturer: ___________________________", styles["Normal"]))
    elements.append(Spacer(1, 12))
    elements.append(Paragraph("Contractor:   ___________________________", styles["Normal"]))
    elements.append(Spacer(1, 24))

    # Build PDF with page numbers
    doc.build(
        elements,
        onFirstPage=lambda c, d: add_page_number_and_qr(c, d, mo['code']),
        onLaterPages=lambda c, d: add_page_number_and_qr(c, d, mo['code'])
    )
    buffer.seek(0)
    return Response(
        buffer.read(),
        media_type="application/pdf",
        headers = {"Content-Disposition": f"inline; filename=manufacturing_receipt_{mo['code']}.pdf"}
    )