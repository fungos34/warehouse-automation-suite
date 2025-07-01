from fastapi import APIRouter, Depends
from database import get_conn
from models import PartnerCreate
from auth import get_current_username

router = APIRouter()


@router.post("/partners", tags=["Partners"])
def create_partner(partner: PartnerCreate, username: str = Depends(get_current_username)):
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
