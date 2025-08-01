from fastapi import APIRouter, Depends, HTTPException
from database import get_conn
from models import PartnerCreate
from auth import get_current_username

router = APIRouter()


@router.post("/partners", tags=["Partners"])
def create_partner(partner: PartnerCreate):  # username: str = Depends(get_current_username)
    with get_conn() as conn:
        cur = conn.execute("""
            INSERT INTO partner 
            (name, street, city, country, zip, billing_street, billing_city, billing_country, billing_zip, email, phone, partner_type)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            partner.name, partner.street, partner.city, partner.country, partner.zip,
            partner.billing_street, partner.billing_city, partner.billing_country, partner.billing_zip,
            partner.email, partner.phone, partner.partner_type
        ))
        partner_id = cur.lastrowid
        conn.commit()
        return {"id": partner_id}
    
@router.get("/partners", tags=["Partners"])
def get_partners(vendor: int = None, username: str = Depends(get_current_username)):
    with get_conn() as conn:
        if vendor:
            result = conn.execute("SELECT * FROM partner WHERE partner_type = 'vendor'")
        else:
            result = conn.execute("SELECT * FROM partner")
        return [dict(row) for row in result]

@router.get("/partners/warehouse", tags=["Partners"])
def get_warehouse_partner():
    with get_conn() as conn:
        # 1. Get the warehouse (assuming only one for now)
        warehouse = conn.execute("SELECT * FROM warehouse LIMIT 1").fetchone()
        if not warehouse or not warehouse["company_id"]:
            raise HTTPException(status_code=404, detail="Warehouse or company not found")
        # 2. Get the company
        company = conn.execute("SELECT * FROM company WHERE id = ?", (warehouse["company_id"],)).fetchone()
        if not company or not company["partner_id"]:
            raise HTTPException(status_code=404, detail="Company or partner not found")
        # 3. Get the partner
        partner = conn.execute("SELECT * FROM partner WHERE id = ?", (company["partner_id"],)).fetchone()
        if not partner:
            raise HTTPException(status_code=404, detail="Partner not found")
        return dict(partner)

@router.get("/partners/{partner_id}", tags=["Partners"])
def get_partner(partner_id: int):
    with get_conn() as conn:
        row = conn.execute("SELECT * FROM partner WHERE id = ?", (partner_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Partner not found")
        return dict(row)

