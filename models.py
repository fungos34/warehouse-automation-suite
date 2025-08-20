from pydantic import BaseModel, Field
from enum import Enum
from typing import List, Literal, Optional


class LoginRequest(BaseModel):
    username: str
    password: str

class ActionEnum(str, Enum):
    pull = "pull"
    push = "push"
    buy = "buy"

class OperationTypeEnum(str, Enum):
    inbound = "inbound"
    outbound = "outbound"
    internal = "internal"

class OrderLineIn(BaseModel):
    quantity: int = Field(..., example=10)
    item_id: int = Field(..., example=1)
    lot_id: Optional[int] = Field(None, example=1)
    price: float = Field(..., example=12.50)
    currency_id: int = Field(..., example=1)
    cost: float = Field(..., example=7.00)
    cost_currency_id: int = Field(..., example=1)

class TransferOrderLineIn(BaseModel):
    item_id: int
    quantity: int
    target_zone_id: int

class PurchaseOrderLineIn(BaseModel):
    item_id: int = Field(..., example=1)
    quantity: float = Field(..., example=100)
    route_id: int = Field(..., example=1)
    price: float = Field(..., example=7.50)
    currency_id: int = Field(..., example=1)
    cost: float = Field(..., example=7.00)
    cost_currency_id: int = Field(..., example=1)

class PartnerCreate(BaseModel):
    name: str
    email: str
    phone: str
    street: str
    city: str
    zip: str
    country: str
    billing_street: str
    billing_city: str
    billing_zip: str
    billing_country: str
    partner_type: str

class SaleOrderCreate(BaseModel):
    code: str = ""
    partner_id: int

class PurchaseOrderCreate(BaseModel):
    partner_id: int
    code: str = ""

class TransferOrderCreate(BaseModel):
    partner_id: int

class QuotationCreate(BaseModel):
    code: str = ""
    partner_id: int
    currency_id: Optional[int] = None
    tax_id: Optional[int] = None
    discount_id: Optional[int] = None
    price_list_id: Optional[int] = None
    split_parcel: Optional[bool] = False
    pick_pack: Optional[bool] = True
    ship: Optional[bool] = True
    carrier_id: Optional[int] = None
    notes: Optional[str] = ""
    priority: Optional[int] = 0

class ReturnLineIn(BaseModel):
    item_id: int
    lot_id: Optional[int] = None
    quantity: int
    reason: str = ""
    price: float = 0.0

class ReturnOrderCreate(BaseModel):
    origin_model: Literal["sale_order", "purchase_order"]
    origin_code: str
    lines: List[ReturnLineIn]
    ship: int

class CreateSessionRequest(BaseModel):
    email: str
    order_number: Optional[str] = None

class StockAdjustmentIn(BaseModel):
    item_id: int
    location_id: int
    delta: int
    reason: str

class ManufacturingOrderCreate(BaseModel):
    item_id: int
    quantity: int
    planned_start: Optional[str] = None
    planned_end: Optional[str] = None

class LotCreate(BaseModel):
    item_id: int
    lot_number: str
    notes: str = ""

class PurchaseLabelRequest(BaseModel):
    rate_id: str

class CompanyCreate(BaseModel):
    name: str
    vat_number: str = ""
    logo_url: str = ""
    website: str = ""
    partner_id: int = None  # Optional, if you want to link to a partner

class BookingRequest(BaseModel):
    partner_id: int

class ServiceBookingCreate(BaseModel):
    item_id: int
    partner_id: int
    service_window_id: int
    start_datetime: Optional[str] = None

class SubscriptionCreate(BaseModel):
    item_id: int
    partner_id: int
    service_window_id: int
    start_date: Optional[str] = None