from fastapi import APIRouter, Depends
from database import get_conn
from models import (
    TransferOrderCreate, TransferOrderLineIn,
    ActionEnum, OperationTypeEnum, 
)
from auth import get_current_username
from typing import List
import uuid


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
def add_stock_adjustment(item_id: int, location_id: int, delta: int, reason: str, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        conn.execute("""
            INSERT INTO stock_adjustment (item_id, location_id, delta, reason)
            VALUES (?, ?, ?, ?)
        """, (item_id, location_id, delta, reason))
        conn.commit()
    return {"message": "Stock adjusted"}


@router.get("/stock/{item_id}", tags=["Warehouse"])
def get_stock_by_item(item_id: int, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        result = conn.execute("""
            SELECT * FROM stock_by_location WHERE item_id = ?
        """, (item_id,))
        return [dict(row) for row in result]

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

@router.get("/items", tags=["Catalog"])
def get_items(): # username: str = Depends(get_current_username)
    with get_conn() as conn:
        # Get the current price list (for sales price)
        price_list = conn.execute("""
            SELECT id, currency_id FROM price_list
            WHERE date('now') BETWEEN IFNULL(valid_from, date('now')) AND IFNULL(valid_to, date('now'))
            ORDER BY valid_from DESC LIMIT 1
        """).fetchone()
        price_list_id = price_list["id"] if price_list else None

        result = conn.execute(f"""
            SELECT 
                i.id, 
                i.name, 
                i.sku, 
                i.vendor_id,
                i.cost,
                cost_cur.code AS cost_currency_code,
                i.cost_currency_id,
                pli.price AS sales_price,
                sales_cur.code AS sales_currency_code
            FROM item i
            LEFT JOIN currency cost_cur ON i.cost_currency_id = cost_cur.id
            LEFT JOIN price_list_item pli ON pli.item_id = i.id {"AND pli.price_list_id = ?" if price_list_id else ""}
            LEFT JOIN price_list pl ON pli.price_list_id = pl.id
            LEFT JOIN currency sales_cur ON pl.currency_id = sales_cur.id
            ORDER BY i.id
        """, (price_list_id,) if price_list_id else ()).fetchall()
        return [dict(row) for row in result]



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

@router.post("/stock-adjustments/", tags=["Warehouse"])
def add_stock_adjustment(item_id: int, location_id: int, delta: int, reason: str, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        conn.execute("""
            INSERT INTO stock_adjustment (item_id, location_id, delta, reason)
            VALUES (?, ?, ?, ?)
        """, (item_id, location_id, delta, reason))
        conn.commit()
    return {"message": "Stock adjusted"}
