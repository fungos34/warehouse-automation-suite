
PRAGMA recursive_triggers = ON;

-- Create Bill of Material
CREATE TABLE IF NOT EXISTS bom (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file BLOB,
    instructions TEXT NOT NULL
);


-- Create bom_line
CREATE TABLE IF NOT EXISTS bom_line (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bom_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    quantity REAL DEFAULT 1,
    FOREIGN KEY(bom_id) REFERENCES bom(id),
    FOREIGN KEY(item_id) REFERENCES item(id)
);

-- Currency Table
CREATE TABLE IF NOT EXISTS currency (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,         -- e.g. 'EUR', 'USD'
    symbol TEXT NOT NULL,              -- e.g. '€', '$'
    name TEXT NOT NULL                 -- e.g. 'Euro', 'US Dollar'
);

-- Tax Table
CREATE TABLE IF NOT EXISTS tax (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    percent REAL NOT NULL,         -- e.g. 19.0 for 19%
    description TEXT
);

-- Discount Table
CREATE TABLE IF NOT EXISTS discount (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    percent REAL,                  -- e.g. 10.0 for 10% discount
    amount REAL,                   -- fixed amount discount (optional)
    description TEXT
);

-- Price List Table
CREATE TABLE IF NOT EXISTS price_list (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    currency_id INTEGER NOT NULL,
    valid_from DATE,
    valid_to DATE,
    FOREIGN KEY(currency_id) REFERENCES currency(id)
);

-- Price List Item Table
CREATE TABLE IF NOT EXISTS price_list_item (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    price_list_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    price REAL NOT NULL,
    FOREIGN KEY(price_list_id) REFERENCES price_list(id),
    FOREIGN KEY(item_id) REFERENCES item(id)
);

-- Create item
CREATE TABLE IF NOT EXISTS item (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK(type in ('product','digital','service')) DEFAULT 'product',
    sku TEXT UNIQUE NOT NULL,
    barcode TEXT UNIQUE NOT NULL,
    size TEXT CHECK (size IN ('small','big')),
    description TEXT,
    route_id INTEGER,
    vendor_id INTEGER,
    cost REAL,                        -- NEW: default cost (purchase/manufacture)
    cost_currency_id INTEGER,         -- NEW: currency for cost
    purchase_price REAL,              -- Optional: last purchase price
    purchase_currency_id INTEGER,     -- Optional: currency for purchase price
    FOREIGN KEY(route_id) REFERENCES route(id),
    FOREIGN KEY(vendor_id) REFERENCES partner(id),
    FOREIGN KEY(cost_currency_id) REFERENCES currency(id),
    FOREIGN KEY(purchase_currency_id) REFERENCES currency(id)
);

-- Create lot
CREATE TABLE IF NOT EXISTS lot (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL,
    lot_number TEXT UNIQUE, -- serial or batch number
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    origin_model TEXT, -- e.g. 'purchase_order', 'return_order', 'stock_adjustment'
    origin_id INTEGER,
    quality_control_status TEXT CHECK(quality_control_status IN ('pending','accepted','rejected')) DEFAULT 'pending',
    notes TEXT,
    FOREIGN KEY(item_id) REFERENCES item(id)
);

-- Create partner
CREATE TABLE IF NOT EXISTS partner (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    street TEXT NOT NULL,           -- delivery street
    city TEXT NOT NULL,             -- delivery city
    country TEXT NOT NULL,          -- delivery country
    zip TEXT NOT NULL,              -- delivery zip
    billing_street TEXT,            -- billing street
    billing_city TEXT,              -- billing city
    billing_country TEXT,           -- billing country
    billing_zip TEXT,               -- billing zip
    email TEXT,
    phone TEXT,
    partner_type TEXT CHECK (partner_type IN ('vendor','customer','employee')) NOT NULL DEFAULT 'customer'
);

-- Create company
CREATE TABLE IF NOT EXISTS company (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    partner_id INTEGER,
    FOREIGN KEY (partner_id) REFERENCES partner(id)
);

-- Create employees
CREATE TABLE IF NOT EXISTS user (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    partner_id INTEGER,
    company_id INTEGER,
    username TEXT UNIQUE,
    password_hash TEXT,
    FOREIGN KEY(partner_id) REFERENCES partner(id),
    FOREIGN KEY(company_id) REFERENCES company(id)
);

-- CReate Warehouse
CREATE TABLE IF NOT EXISTS warehouse (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    company_id INTEGER,
    FOREIGN KEY(company_id) REFERENCES company(id)
);

-- Create location: real world physical locations
CREATE TABLE IF NOT EXISTS location (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,
    x REAL,
    y REAL,
    z REAL,
    dx REAL DEFAULT 1, -- width
    dy REAL DEFAULT 1, -- depth
    dz REAL DEFAULT 1, -- height
    warehouse_id INTEGER NOT NULL,
    partner_id INTEGER,
    description TEXT,
    FOREIGN KEY(warehouse_id) REFERENCES warehouse(id),
    FOREIGN KEY(partner_id) REFERENCES partner(id)
);

-- Create zone: abstract grouping of locations within a warehouse
CREATE TABLE IF NOT EXISTS zone (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT NOT NULL,
    description TEXT,
    route_id INTEGER,
    FOREIGN KEY(route_id) REFERENCES route(id)
);

-- create location_zone
CREATE TABLE IF NOT EXISTS location_zone (
    location_id INTEGER NOT NULL,
    zone_id INTEGER NOT NULL,
    PRIMARY KEY (zone_id, location_id),
    FOREIGN KEY(location_id) REFERENCES location(id),
    FOREIGN KEY(zone_id) REFERENCES zone(id)
);

-- create stock
CREATE TABLE IF NOT EXISTS stock (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL,
    location_id INTEGER NOT NULL,
    lot_id INTEGER, -- nullable for non-lot-tracked items
    quantity INTEGER NOT NULL DEFAULT 0,
    reserved_quantity INTEGER NOT NULL DEFAULT 0,
    target_quantity INTEGER NOT NULL DEFAULT 100,
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(location_id) REFERENCES location(id),
    FOREIGN KEY(lot_id) REFERENCES lot(id)
);

-- Create stock adjustment
CREATE TABLE IF NOT EXISTS stock_adjustment (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL,
    location_id INTEGER NOT NULL,
    lot_id INTEGER,
    delta REAL NOT NULL, -- change in available quantity
    reserved_delta REAL DEFAULT 0, -- change in reserved quantity
    reason TEXT,
    partner_id INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(location_id) REFERENCES location(id),
    FOREIGN KEY(lot_id) REFERENCES lot(id),
    FOREIGN KEY(partner_id) REFERENCES partner(id)
);

-- Create picking
CREATE TABLE IF NOT EXISTS picking (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    origin TEXT,
    type TEXT NOT NULL CHECK (type IN ('inbound', 'internal', 'outbound')),
    source_id INTEGER NOT NULL,
    target_id INTEGER NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('draft','confirmed','assigned','done','cancelled')) DEFAULT 'draft',
    priority TEXT CHECK(priority IN (0,1,2,3)),
    is_blocked BOOLEAN DEFAULT 0,
    scheduled_at DATETIME,
    partner_id INTEGER,
    trigger_id INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(source_id) REFERENCES zone(id),
    FOREIGN KEY(target_id) REFERENCES zone(id),
    FOREIGN KEY(partner_id) REFERENCES partner(id),
    FOREIGN KEY(trigger_id) REFERENCES trigger(id)
);

--Create move
CREATE TABLE IF NOT EXISTS move (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL,
    lot_id INTEGER, -- nullable for non-lot-tracked items
    source_id INTEGER NOT NULL,
    target_id INTEGER NOT NULL,
    trigger_id INTEGER,
    picking_id INTEGER,
    quantity REAL DEFAULT 0,
    reserved_quantity REAL DEFAULT 0,
    route_id INTEGER,
    rule_id INTEGER,
    is_terminal BOOLEAN DEFAULT 0,
    type TEXT CHECK (type IN ('internal','outbound','inbound')) DEFAULT 'internal',
    status TEXT NOT NULL CHECK (status IN ('draft','waiting','confirmed','assigned','done','intervene')) DEFAULT 'draft',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(picking_id) REFERENCES picking(id),
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(lot_id) REFERENCES lot(id),
    FOREIGN KEY(source_id) REFERENCES zone(id),
    FOREIGN KEY(target_id) REFERENCES zone(id),
    FOREIGN KEY(route_id) REFERENCES route(id),
    FOREIGN KEY(trigger_id) REFERENCES trigger(id),
    FOREIGN KEY(rule_id) REFERENCES rule(id)
);

CREATE TABLE IF NOT EXISTS move_line (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    move_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    source_id INTEGER NOT NULL,
    target_id INTEGER NOT NULL,
    lot_id INTEGER,
    quantity REAL NOT NULL,
    reserved_quantity REAL DEFAULT 0,
    done_quantity REAL DEFAULT 0,
    reserved BOOLEAN DEFAULT 0,
    status TEXT NOT NULL CHECK (status IN ('draft','confirmed','assigned','done')) DEFAULT 'draft',
    FOREIGN KEY(move_id) REFERENCES move(id),
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(source_id) REFERENCES location(id),
    FOREIGN KEY(target_id) REFERENCES location(id),
    FOREIGN KEY(lot_id) REFERENCES lot(id)
);

-- Create order
CREATE TABLE IF NOT EXISTS sale_order (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,
    partner_id INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    status TEXT NOT NULL CHECK (status IN ('draft','confirmed','done', 'cancelled')) DEFAULT 'draft',
    currency_id INTEGER,              -- NEW: currency for this order
    tax_id INTEGER,                   -- NEW: tax for this order
    discount_id INTEGER,              -- NEW: discount for this order
    price_list_id INTEGER,            -- NEW: price list for this order
    FOREIGN KEY(partner_id) REFERENCES partner(id),
    FOREIGN KEY(currency_id) REFERENCES currency(id),
    FOREIGN KEY(tax_id) REFERENCES tax(id),
    FOREIGN KEY(discount_id) REFERENCES discount(id),
    FOREIGN KEY(price_list_id) REFERENCES price_list(id)
);

-- Create order_line
CREATE TABLE IF NOT EXISTS order_line (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    quantity INTEGER,
    item_id INTEGER,
    lot_id INTEGER,                  -- nullable for non-lot-tracked items
    order_id INTEGER,
    route_id INTEGER,
    price REAL,                       -- NEW: unit price for this line
    currency_id INTEGER,              -- NEW: currency for this line
    price_list_id INTEGER,            -- NEW: price list for this line
    cost REAL,                        -- NEW: cost for this line (manufacture/purchase)
    cost_currency_id INTEGER,         -- NEW: currency for cost
    FOREIGN KEY(order_id) REFERENCES sale_order(id),
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(route_id) REFERENCES route(id),
    FOREIGN KEY(currency_id) REFERENCES currency(id),
    FOREIGN KEY(cost_currency_id) REFERENCES currency(id),
    FOREIGN KEY(lot_id) REFERENCES lot(id),
    FOREIGN KEY(price_list_id) REFERENCES price_list(id)
);

-- Purchase Order Table (adapted)
CREATE TABLE IF NOT EXISTS purchase_order (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    status TEXT NOT NULL CHECK (status IN ('draft','confirmed','done','cancelled')) DEFAULT 'draft',
    origin TEXT,
    code TEXT UNIQUE NOT NULL,
    partner_id INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    currency_id INTEGER,              -- NEW: currency for this order
    tax_id INTEGER,                   -- NEW: tax for this order
    discount_id INTEGER,              -- NEW: discount for this order
    FOREIGN KEY(partner_id) REFERENCES partner(id),
    FOREIGN KEY(currency_id) REFERENCES currency(id),
    FOREIGN KEY(tax_id) REFERENCES tax(id),
    FOREIGN KEY(discount_id) REFERENCES discount(id)
);

-- Purchase Order Line Table (adapted)
CREATE TABLE IF NOT EXISTS purchase_order_line (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    purchase_order_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    lot_id INTEGER,                  -- nullable for non-lot-tracked items
    quantity REAL NOT NULL,
    route_id INTEGER NOT NULL DEFAULT 1,
    price REAL,                       -- NEW: unit price for this line
    currency_id INTEGER,              -- NEW: currency for this line
    cost REAL,                        -- NEW: cost for this line (if different from price)
    cost_currency_id INTEGER,         -- NEW: currency for cost
    FOREIGN KEY(purchase_order_id) REFERENCES purchase_order(id),
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(route_id) REFERENCES route(id),
    FOREIGN KEY(currency_id) REFERENCES currency(id),
    FOREIGN KEY(cost_currency_id) REFERENCES currency(id),
    FOREIGN KEY(lot_id) REFERENCES lot(id),
    UNIQUE(purchase_order_id, item_id, lot_id)
);

-- Create transfer_order
CREATE TABLE IF NOT EXISTS transfer_order (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    status TEXT NOT NULL CHECK (status IN ('draft','confirmed','done','cancelled')) DEFAULT 'draft',
    origin TEXT,
    partner_id INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    code TEXT UNIQUE NOT NULL,
    FOREIGN KEY(partner_id) REFERENCES partner(id)
);

-- Create transfer_order_line
CREATE TABLE IF NOT EXISTS transfer_order_line (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    transfer_order_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    lot_id INTEGER,                  -- nullable for non-lot-tracked items
    quantity REAL NOT NULL,
    target_zone_id INTEGER NOT NULL,
    route_id INTEGER NOT NULL DEFAULT 1,
    FOREIGN KEY(transfer_order_id) REFERENCES transfer_order(id),
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(target_zone_id) REFERENCES zone(id),
    FOREIGN KEY(route_id) REFERENCES route(id),
    FOREIGN KEY(lot_id) REFERENCES lot(id)
);

-- return_order 
CREATE TABLE IF NOT EXISTS return_order (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,
    origin_model TEXT NOT NULL,
    origin_id INTEGER NOT NULL,
    partner_id INTEGER NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('draft','confirmed','done','cancelled')) DEFAULT 'draft',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(partner_id) REFERENCES partner(id)
);

-- return_line
CREATE TABLE IF NOT EXISTS return_line (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    return_order_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    lot_id INTEGER,
    quantity INTEGER NOT NULL,
    reason TEXT,
    refund_amount REAL DEFAULT 0,
    refund_currency_id INTEGER,
    refund_tax_id INTEGER,
    refund_discount_id INTEGER,
    FOREIGN KEY(return_order_id) REFERENCES return_order(id),
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(lot_id) REFERENCES lot(id),
    FOREIGN KEY(refund_currency_id) REFERENCES currency(id),
    FOREIGN KEY(refund_tax_id) REFERENCES tax(id),
    FOREIGN KEY(refund_discount_id) REFERENCES discount(id)
);

-- Rules
CREATE TABLE IF NOT EXISTS rule (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    route_id INTEGER NOT NULL,
    action TEXT CHECK(action IN ('pull', 'push', 'pull_or_buy')) NOT NULL,
    operation_type TEXT,
    source_id INTEGER,
    target_id INTEGER,
    delay INTEGER DEFAULT 0,
    active BOOLEAN DEFAULT 1,
    FOREIGN KEY(route_id) REFERENCES route(id),
    FOREIGN KEY(source_id) REFERENCES zone(id),
    FOREIGN KEY(target_id) REFERENCES zone(id)
);

-- Routes
CREATE TABLE IF NOT EXISTS route (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    active BOOLEAN DEFAULT 1,
    description TEXT
);

CREATE TABLE IF NOT EXISTS trigger (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    
    origin_model TEXT CHECK(origin_model IN ('sale_order', 'transfer_order', 'purchase_order', 'stock', 'return_order')) NOT NULL,
    origin_id INTEGER,

    trigger_type TEXT NOT NULL CHECK (trigger_type IN ('demand','supply')),
    trigger_route_id INTEGER,
    trigger_item_id INTEGER NOT NULL,
    trigger_lot_id INTEGER,
    trigger_zone_id INTEGER NOT NULL,
    trigger_item_quantity REAL NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('draft','handled','intervene')) DEFAULT 'draft',
    type TEXT NOT NULL CHECK (type IN ('inbound','outbound','internal')),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(trigger_item_id) REFERENCES item(id),
    FOREIGN KEY(trigger_zone_id) REFERENCES zone(id),
    FOREIGN KEY(trigger_route_id) REFERENCES route(id),
    FOREIGN KEY(trigger_lot_id) REFERENCES lot(id)
);


CREATE TABLE IF NOT EXISTS rule_trigger (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id INTEGER NOT NULL,
    trigger_id INTEGER NOT NULL,
    -- Track the move created from this rule_trigger (if any)
    move_id INTEGER,
    FOREIGN KEY(rule_id) REFERENCES rule(id),
    FOREIGN KEY(trigger_id) REFERENCES trigger(id),
    FOREIGN KEY(move_id) REFERENCES move(id)
);


-- intervention table for unresolved moves
CREATE TABLE IF NOT EXISTS intervention (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    move_id INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    priority INTEGER DEFAULT 0,
    reason TEXT,
    resolved BOOLEAN DEFAULT 0,
    FOREIGN KEY(move_id) REFERENCES move(id)
);

-- Debug log table for tracking events
CREATE TABLE IF NOT EXISTS debug_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event TEXT,
    move_id INTEGER,
    info TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- trigger trg_return_line_split_and_lot
DROP TRIGGER IF EXISTS trg_return_line_split_and_lot;
CREATE TRIGGER trg_return_line_split_and_lot
AFTER INSERT ON return_line
BEGIN
    -- For each new return_line (quantity=1), create a lot and assign it
    INSERT INTO lot (item_id, lot_number, origin_model, origin_id, quality_control_status, notes)
    VALUES (
        NEW.item_id,
        'RET-' || hex(randomblob(4)),  -- Short, unique lot number -- 'RET-' || NEW.return_order_id || '-' || NEW.id || '-' || strftime('%Y%m%d%H%M%f','now'),
        'return_order',
        NEW.return_order_id,
        'pending',
        'Return from customer'
    );

    UPDATE return_line
    SET lot_id = (SELECT id FROM lot WHERE origin_model = 'return_order' AND origin_id = NEW.return_order_id AND item_id = NEW.item_id ORDER BY id DESC LIMIT 1)
    WHERE id = NEW.id;
END;

-- Trigger: on return order creation, create supply trigger
DROP TRIGGER IF EXISTS trg_return_line_create_supply_trigger;
CREATE TRIGGER trg_return_line_create_supply_trigger
AFTER INSERT ON return_line
BEGIN
    INSERT INTO trigger (
        origin_model,
        origin_id,
        trigger_type,
        trigger_route_id,
        trigger_item_id,
        trigger_zone_id,
        trigger_item_quantity,
        trigger_lot_id,
        type,
        status
    )
    SELECT
        'return_order',
        NEW.return_order_id,
        'supply',
        (SELECT id FROM route WHERE name = 'Return Route'),
        NEW.item_id,
        (SELECT id FROM zone WHERE code = 'ZON09'), -- Customer Area
        1,
        NEW.lot_id,
        'inbound',
        'draft'
    WHERE NEW.quantity = 1;
END;

-- Trigger: on stock adjustment, update stock
DROP TRIGGER IF EXISTS trg_stock_adjustment_update_stock;
CREATE TRIGGER trg_stock_adjustment_update_stock
AFTER INSERT ON stock_adjustment
BEGIN
    -- Ensure stock record exists
    INSERT INTO stock (item_id, location_id, lot_id, quantity, reserved_quantity)
    SELECT NEW.item_id, NEW.location_id, NEW.lot_id, 0, 0
    WHERE NOT EXISTS (
        SELECT 1 FROM stock WHERE item_id = NEW.item_id AND location_id = NEW.location_id AND (lot_id = NEW.lot_id OR (lot_id IS NULL AND NEW.lot_id IS NULL))
    );

    -- Update both available and reserved quantities
    UPDATE stock
    SET quantity = quantity + NEW.delta,
        reserved_quantity = reserved_quantity + NEW.reserved_delta
    WHERE item_id = NEW.item_id AND location_id = NEW.location_id AND (lot_id = NEW.lot_id OR (lot_id IS NULL AND NEW.lot_id IS NULL));

    -- Only create a supply trigger if available stock increased
    INSERT INTO trigger (
        origin_model,
        origin_id,
        trigger_type,
        trigger_item_id,
        trigger_zone_id,
        trigger_item_quantity,
        trigger_lot_id,
        type,
        status
    )
    SELECT
        'stock',
        NEW.id,
        'supply',
        NEW.item_id,
        lz.zone_id,
        NEW.delta,
        NEW.lot_id,
        'internal',
        'draft'
    FROM location_zone lz
    WHERE lz.location_id = NEW.location_id
      AND NEW.delta > 0;
END;


-- Trigger: On unreserved stock quantity increase, resolve intervention if applicable
CREATE TRIGGER trg_resolve_intervention_on_stock
AFTER UPDATE OF quantity ON stock
WHEN NEW.quantity - NEW.reserved_quantity > OLD.quantity - OLD.reserved_quantity
BEGIN
    -- Find the highest priority unresolved intervention for this location and item
    UPDATE move
    SET status = 'confirmed'
    WHERE id = (
        SELECT i.move_id
        FROM intervention i
        JOIN move m ON m.id = i.move_id
        WHERE m.source_id = NEW.location_id
          AND m.item_id = NEW.item_id
          AND (m.lot_id = NEW.lot_id OR (m.lot_id IS NULL AND NEW.lot_id IS NULL))
          AND i.resolved = 0
        ORDER BY i.priority DESC, i.created_at ASC
        LIMIT 1
    );

    -- Mark the intervention as resolved
    UPDATE intervention
    SET resolved = 1
    WHERE move_id = (
        SELECT i.move_id
        FROM intervention i
        JOIN move m ON m.id = i.move_id
        WHERE m.source_id = NEW.location_id
          AND m.item_id = NEW.item_id
          AND (m.lot_id = NEW.lot_id OR (m.lot_id IS NULL AND NEW.lot_id IS NULL))
          AND i.resolved = 0
        ORDER BY i.priority DESC, i.created_at ASC
        LIMIT 1
    );

    -- After resolving interventions, also create a supply trigger for push chains

    INSERT INTO trigger (
        origin_model,
        origin_id,
        trigger_type,
        trigger_item_id,
        trigger_zone_id,
        trigger_item_quantity,
        trigger_lot_id,
        type,
        status
    )
    SELECT
        'stock',
        NEW.id,
        'supply',
        NEW.item_id,
        lz.zone_id,
        NEW.quantity - NEW.reserved_quantity,
        NEW.lot_id,
        'internal',
        'draft'
    FROM location_zone lz
    WHERE lz.location_id = NEW.location_id
    AND (NEW.quantity - NEW.reserved_quantity) > 0;
END;


CREATE TRIGGER trg_resolve_intervention_on_stock_insert
AFTER INSERT ON stock
WHEN NEW.quantity - NEW.reserved_quantity > 0
BEGIN
    -- Find the highest priority unresolved intervention for this location and item
    UPDATE move
    SET status = 'confirmed'
    WHERE id = (
        SELECT i.move_id
        FROM intervention i
        JOIN move m ON m.id = i.move_id
        WHERE m.source_id = NEW.location_id
          AND m.item_id = NEW.item_id
          AND (m.lot_id = NEW.lot_id OR (m.lot_id IS NULL AND NEW.lot_id IS NULL))
          AND i.resolved = 0
        ORDER BY i.priority DESC, i.created_at ASC
        LIMIT 1
    );

    -- Mark the intervention as resolved
    UPDATE intervention
    SET resolved = 1
    WHERE move_id = (
        SELECT i.move_id
        FROM intervention i
        JOIN move m ON m.id = i.move_id
        WHERE m.source_id = NEW.location_id
          AND m.item_id = NEW.item_id
          AND (m.lot_id = NEW.lot_id OR (m.lot_id IS NULL AND NEW.lot_id IS NULL))
          AND i.resolved = 0
        ORDER BY i.priority DESC, i.created_at ASC
        LIMIT 1
    );

    -- After resolving interventions, also create a supply trigger for push chains
    INSERT INTO trigger (
        origin_model,
        origin_id,
        trigger_type,
        trigger_item_id,
        trigger_zone_id,
        trigger_item_quantity,
        trigger_lot_id,
        type,
        status
    )
    SELECT
        'stock',
        NEW.id,
        'supply',
        NEW.item_id,
        lz.zone_id,
        NEW.quantity - NEW.reserved_quantity,
        NEW.lot_id,
        'internal',
        'draft'
    FROM location_zone lz
    WHERE lz.location_id = NEW.location_id
    AND (NEW.quantity - NEW.reserved_quantity) > 0;
END;


-- Trigger: On supply trigger intervention, resolve the highest priority intervention
CREATE TRIGGER trg_supply_trigger_intervene_resolve
AFTER UPDATE OF status ON trigger
WHEN NEW.status = 'intervene' AND NEW.trigger_type = 'supply'
BEGIN
    -- Find the highest priority unresolved intervention for this zone/item
    UPDATE move
    SET status = 'confirmed'
    WHERE id = (
        SELECT i.move_id
        FROM intervention i
        JOIN move m ON m.id = i.move_id
        WHERE m.source_id IN (
            SELECT location_id FROM location_zone WHERE zone_id = NEW.trigger_zone_id
        )
          AND m.item_id = NEW.trigger_item_id
          AND m.lot_id = NEW.trigger_lot_id
          AND i.resolved = 0
        ORDER BY i.priority DESC, i.created_at ASC
        LIMIT 1
    );

    -- Mark the intervention as resolved
    UPDATE intervention
    SET resolved = 1
    WHERE move_id = (
        SELECT i.move_id
        FROM intervention i
        JOIN move m ON m.id = i.move_id
        WHERE m.source_id IN (
            SELECT location_id FROM location_zone WHERE zone_id = NEW.trigger_zone_id
        )
          AND m.item_id = NEW.trigger_item_id
          AND m.lot_id = NEW.trigger_lot_id
          AND i.resolved = 0
        ORDER BY i.priority DESC, i.created_at ASC
        LIMIT 1
    );
END;


-- Trigger: On partner creation, create a location and assign to customer zone
DROP TRIGGER IF EXISTS trg_partner_create_location;
CREATE TRIGGER trg_partner_create_location
AFTER INSERT ON partner
BEGIN
    INSERT INTO location (code, x, y, z, dx, dy, dz, warehouse_id, partner_id, description)
    VALUES (
        'LOC_PARTNER_' || NEW.id,
        0, 0, 0,
        1, 1, 1,
        1,
        NEW.id,
        NEW.name
    );

    INSERT INTO location_zone (location_id, zone_id)
    VALUES (
        (SELECT id FROM location WHERE partner_id = NEW.id ORDER BY id DESC LIMIT 1),
        CASE
            WHEN NEW.partner_type = 'vendor' THEN (SELECT id FROM zone WHERE code = 'ZON08')
            WHEN NEW.partner_type = 'customer' THEN (SELECT id FROM zone WHERE code = 'ZON09')
            WHEN NEW.partner_type = 'employee' THEN (SELECT id FROM zone WHERE code = 'ZON10')
        END
    );
END;

-- Trigger: transfer order status change to 'confirmed', create demand triggers for each order line
DROP TRIGGER IF EXISTS trg_transfer_order_confirmed;
CREATE TRIGGER trg_transfer_order_confirmed
AFTER UPDATE ON transfer_order
WHEN NEW.status = 'confirmed' AND OLD.status != 'confirmed'
BEGIN
    INSERT INTO trigger (
        origin_model,
        origin_id,
        trigger_type,
        trigger_route_id,
        trigger_item_id,
        trigger_zone_id,
        trigger_item_quantity,
        trigger_lot_id,
        type
    )
    SELECT
        'transfer_order',
        NEW.id,
        'demand',
        tol.route_id,
        tol.item_id,
        tol.target_zone_id,
        tol.quantity,
        tol.lot_id,
        'internal'
    FROM transfer_order_line tol
    WHERE tol.transfer_order_id = NEW.id;
END;


-- Trigger: On sale_order status change to 'confirmed', create demand triggers for each order line
DROP TRIGGER IF EXISTS trg_sale_order_confirmed;
CREATE TRIGGER trg_sale_order_confirmed
AFTER UPDATE ON sale_order
WHEN NEW.status = 'confirmed' AND OLD.status != 'confirmed'
BEGIN
    INSERT INTO trigger (
        origin_model,
        origin_id,
        trigger_type,
        trigger_route_id,
        trigger_item_id,
        trigger_zone_id,
        trigger_item_quantity,
        trigger_lot_id,
        type
    )
    SELECT
        'sale_order',
        NEW.id,
        'demand',
        ol.route_id,
        ol.item_id,
        (
            SELECT lz.zone_id
            FROM location l
            JOIN location_zone lz ON l.id = lz.location_id
            WHERE l.partner_id = NEW.partner_id
            LIMIT 1
        ),
        ol.quantity,
        ol.lot_id,
        'outbound'
    FROM order_line ol
    WHERE ol.order_id = NEW.id;
END;


DROP TRIGGER IF EXISTS trg_purchase_order_confirmed;
CREATE TRIGGER trg_purchase_order_confirmed
AFTER UPDATE ON purchase_order
WHEN NEW.status = 'confirmed' AND OLD.status != 'confirmed'
BEGIN
    INSERT INTO trigger (
        origin_model,
        origin_id,
        trigger_type,
        trigger_route_id,
        trigger_item_id,
        trigger_zone_id,
        trigger_item_quantity,
        trigger_lot_id,
        type
    )
    SELECT
        'purchase_order',
        NEW.id,
        'supply',
        pol.route_id,
        pol.item_id,
        (SELECT id FROM zone WHERE code = 'ZON08'), -- Vendor Area
        pol.quantity,
        pol.lot_id,
        'inbound'
    FROM purchase_order_line pol
    WHERE pol.purchase_order_id = NEW.id;
END;


-- Trigger: On trigger creation, evaluate and link applicable rules or set to intervene
CREATE TRIGGER trg_trigger_evaluate_rules
AFTER INSERT ON trigger
BEGIN
    -- 1. Find the most specific active route_id (trigger, item, zone)
    -- 2. If no active route found, set status to 'intervene'
    UPDATE trigger
    SET status = 'intervene'
    WHERE id = NEW.id
      AND (
        (NEW.trigger_route_id IS NULL OR (SELECT active FROM route WHERE id = NEW.trigger_route_id) != 1)
        AND ((SELECT route_id FROM item WHERE id = NEW.trigger_item_id) IS NULL OR (SELECT active FROM route WHERE id = (SELECT route_id FROM item WHERE id = NEW.trigger_item_id)) != 1)
        AND ((SELECT route_id FROM zone WHERE id = NEW.trigger_zone_id) IS NULL OR (SELECT active FROM route WHERE id = (SELECT route_id FROM zone WHERE id = NEW.trigger_zone_id)) != 1)
      );

    -- 3. If an active route is found, link all applicable active rules
    INSERT INTO rule_trigger (rule_id, trigger_id)
    SELECT r.id, NEW.id
    FROM rule r
    WHERE r.active = 1
      AND (
        r.route_id =
          CASE
            WHEN NEW.trigger_route_id IS NOT NULL AND (SELECT active FROM route WHERE id = NEW.trigger_route_id) = 1 THEN NEW.trigger_route_id
            WHEN (SELECT route_id FROM item WHERE id = NEW.trigger_item_id) IS NOT NULL AND (SELECT active FROM route WHERE id = (SELECT route_id FROM item WHERE id = NEW.trigger_item_id)) = 1
              THEN (SELECT route_id FROM item WHERE id = NEW.trigger_item_id)
            WHEN (SELECT route_id FROM zone WHERE id = NEW.trigger_zone_id) IS NOT NULL AND (SELECT active FROM route WHERE id = (SELECT route_id FROM zone WHERE id = NEW.trigger_zone_id)) = 1
              THEN (SELECT route_id FROM zone WHERE id = NEW.trigger_zone_id)
            ELSE NULL
          END
      )
      AND (
        (NEW.trigger_type = 'demand'
          AND r.action IN ('pull','pull_or_buy')
          AND r.target_id = NEW.trigger_zone_id)
        OR
        (NEW.trigger_type = 'supply'
          AND r.action = 'push'
          AND r.source_id = NEW.trigger_zone_id)
      );
END;


-- Trigger: On rule_trigger insert, create a move
DROP TRIGGER IF EXISTS trg_rule_trigger_create_move;
CREATE TRIGGER trg_rule_trigger_create_move
AFTER INSERT ON rule_trigger
BEGIN
    -- PUSH: move from trigger zone (supply) to rule's target
    INSERT INTO move (
        item_id,
        lot_id,
        source_id,
        target_id,
        quantity,
        route_id,
        trigger_id,
        rule_id,
        is_terminal,
        type,
        status
    )
    SELECT
        t.trigger_item_id,
        t.trigger_lot_id,
        t.trigger_zone_id,      -- source: trigger zone (supply)
        r.target_id,            -- target: rule's target
        t.trigger_item_quantity,
        r.route_id,
        t.id,
        r.id,
        0,
        COALESCE(r.operation_type, t.type, 'internal'),
        'draft'
    FROM rule r
    JOIN trigger t ON t.id = NEW.trigger_id
    WHERE r.id = NEW.rule_id
      AND r.action = 'push';

    -- PULL and PULL_OR_BUY: move from rule's source to trigger zone (demand)
    INSERT INTO move (
        item_id,
        lot_id,
        source_id,
        target_id,
        quantity,
        route_id,
        trigger_id,
        rule_id,
        is_terminal,
        type,
        status
    )
    SELECT
        t.trigger_item_id,
        t.trigger_lot_id,
        r.source_id,            -- source: rule's source
        t.trigger_zone_id,      -- target: trigger zone (demand)
        t.trigger_item_quantity,
        r.route_id,
        t.id,
        r.id,
        0,
        COALESCE(r.operation_type, t.type, 'internal'),
        'draft'
    FROM rule r
    JOIN trigger t ON t.id = NEW.trigger_id
    WHERE r.id = NEW.rule_id
      AND r.action IN ('pull', 'pull_or_buy');

    -- Update rule_trigger with the move_id of the move just created
    UPDATE rule_trigger
    SET move_id = (SELECT id FROM move WHERE trigger_id = NEW.trigger_id AND rule_id = NEW.rule_id ORDER BY id DESC LIMIT 1)
    WHERE id = NEW.id;
END;

DROP TRIGGER IF EXISTS trg_rule_trigger_create_po_on_buy;
CREATE TRIGGER trg_rule_trigger_create_po_on_buy
AFTER INSERT ON rule_trigger
WHEN (SELECT action FROM rule WHERE id = NEW.rule_id) = 'pull_or_buy'
BEGIN
    -- 1. Find or create a draft purchase order for this vendor
    INSERT INTO purchase_order (status, origin, partner_id, code)
    SELECT
        'draft',
        'Auto-created for pull_or_buy trigger (vendor_id=' || (SELECT vendor_id FROM item WHERE id = (SELECT trigger_item_id FROM "trigger" WHERE id = NEW.trigger_id)) || ')',
        (SELECT vendor_id FROM item WHERE id = (SELECT trigger_item_id FROM "trigger" WHERE id = NEW.trigger_id)),
        'PO_AUTO_' || (SELECT vendor_id FROM item WHERE id = (SELECT trigger_item_id FROM "trigger" WHERE id = NEW.trigger_id)) || '_' || strftime('%Y%m%d%H%M%f','now')
    WHERE NOT EXISTS (
        SELECT 1 FROM purchase_order po
        WHERE po.status = 'draft'
        AND po.partner_id = (SELECT vendor_id FROM item WHERE id = (SELECT trigger_item_id FROM "trigger" WHERE id = NEW.trigger_id))
    );

    -- 2. Insert or update the purchase order line for the missing quantity
    -- First, try to update an existing line
    UPDATE purchase_order_line
    SET quantity = quantity + (SELECT trigger_item_quantity FROM "trigger" WHERE id = NEW.trigger_id)
    WHERE purchase_order_id = (
            SELECT id FROM purchase_order
            WHERE status = 'draft'
            AND partner_id = (SELECT vendor_id FROM item WHERE id = (SELECT trigger_item_id FROM "trigger" WHERE id = NEW.trigger_id))
            ORDER BY id DESC LIMIT 1
        )
      AND item_id = (SELECT trigger_item_id FROM "trigger" WHERE id = NEW.trigger_id)
      AND IFNULL(lot_id, -1) = IFNULL((SELECT trigger_lot_id FROM "trigger" WHERE id = NEW.trigger_id), -1)
      AND route_id = (SELECT trigger_route_id FROM "trigger" WHERE id = NEW.trigger_id);

    -- Then, if no line was updated, insert a new one
    INSERT INTO purchase_order_line (
        purchase_order_id, item_id, lot_id, quantity, route_id, price, currency_id, cost, cost_currency_id
    )
    SELECT
        (SELECT id FROM purchase_order
         WHERE status = 'draft'
         AND partner_id = (SELECT vendor_id FROM item WHERE id = (SELECT trigger_item_id FROM "trigger" WHERE id = NEW.trigger_id))
         ORDER BY id DESC LIMIT 1),
        t.trigger_item_id,
        t.trigger_lot_id,
        t.trigger_item_quantity,
        t.trigger_route_id,
        i.cost,
        i.cost_currency_id,
        i.cost,
        i.cost_currency_id
    FROM "trigger" t
    JOIN item i ON i.id = t.trigger_item_id
    WHERE t.id = NEW.trigger_id
      AND NOT EXISTS (
        SELECT 1 FROM purchase_order_line pol
        WHERE pol.purchase_order_id = (
                SELECT id FROM purchase_order
                WHERE status = 'draft'
                AND partner_id = (SELECT vendor_id FROM item WHERE id = t.trigger_item_id)
                ORDER BY id DESC LIMIT 1
            )
          AND pol.item_id = t.trigger_item_id
          AND IFNULL(pol.lot_id, -1) = IFNULL(t.trigger_lot_id, -1)
          AND pol.route_id = t.trigger_route_id
    );
END;

-- Trigger: Assign or create picking for move
CREATE TRIGGER trg_move_assign_picking
AFTER INSERT ON move
BEGIN
    -- Try to assign an existing picking
    UPDATE move
    SET picking_id = (
        SELECT id FROM picking
        WHERE source_id = NEW.source_id
          AND target_id = NEW.target_id
          AND type = NEW.type
          AND status NOT IN ('done', 'cancelled')
        LIMIT 1
    )
    WHERE id = NEW.id
      AND picking_id IS NULL
      AND EXISTS (
        SELECT 1 FROM picking
        WHERE source_id = NEW.source_id
          AND target_id = NEW.target_id
          AND type = NEW.type
          AND status NOT IN ('done', 'cancelled')
      );

    -- If no picking was assigned, create a new one and assign it
    INSERT INTO picking (origin, type, source_id, target_id, status, trigger_id)
    SELECT
        NULL,
        NEW.type,
        NEW.source_id,
        NEW.target_id,
        'draft',
        NEW.trigger_id
    WHERE NOT EXISTS (
        SELECT 1 FROM picking
        WHERE source_id = NEW.source_id
          AND target_id = NEW.target_id
          AND type = NEW.type
          AND status NOT IN ('done', 'cancelled')
    );

    UPDATE move
    SET picking_id = (
        SELECT id FROM picking
        WHERE source_id = NEW.source_id
          AND target_id = NEW.target_id
          AND type = NEW.type
          AND status NOT IN ('done', 'cancelled')
        ORDER BY id DESC
        LIMIT 1
    )
    WHERE id = NEW.id AND picking_id IS NULL;
END;


-- Trigger: On move_line done, update move status
CREATE TRIGGER trg_move_line_reserve_stock
AFTER INSERT ON move_line
BEGIN
    UPDATE stock
    SET reserved_quantity = reserved_quantity + NEW.quantity
    WHERE item_id = NEW.item_id
      AND location_id = NEW.source_id
      AND (lot_id = NEW.lot_id OR (lot_id IS NULL AND NEW.lot_id IS NULL));
END;


-- Trigger: On move_line done, update stock and move status
DROP TRIGGER IF EXISTS trg_move_line_done_update_stock;
CREATE TRIGGER trg_move_line_done_update_stock
AFTER UPDATE OF status ON move_line
WHEN NEW.status = 'done' AND OLD.status != 'done'
BEGIN
    -- Ensure stock records exist
    INSERT INTO stock (item_id, location_id, lot_id, quantity)
    SELECT NEW.item_id, NEW.source_id, NEW.lot_id, 0
    WHERE NOT EXISTS (
        SELECT 1 FROM stock WHERE item_id = NEW.item_id AND location_id = NEW.source_id AND (lot_id = NEW.lot_id OR (lot_id IS NULL AND NEW.lot_id IS NULL))
    );

    INSERT INTO stock (item_id, location_id, lot_id, quantity)
    SELECT NEW.item_id, NEW.target_id, NEW.lot_id, 0
    WHERE NOT EXISTS (
        SELECT 1 FROM stock WHERE item_id = NEW.item_id AND location_id = NEW.target_id AND (lot_id = NEW.lot_id OR (lot_id IS NULL AND NEW.lot_id IS NULL))
    );

    -- Subtract from source location (quantity and reserved_quantity)
    UPDATE stock
    SET quantity = quantity - NEW.done_quantity,
        reserved_quantity = reserved_quantity - NEW.done_quantity
    WHERE item_id = NEW.item_id AND location_id = NEW.source_id AND (lot_id = NEW.lot_id OR (lot_id IS NULL AND NEW.lot_id IS NULL));

    -- Add to target location
    UPDATE stock
    SET quantity = quantity + NEW.done_quantity
    WHERE item_id = NEW.item_id AND location_id = NEW.target_id AND (lot_id = NEW.lot_id OR (lot_id IS NULL AND NEW.lot_id IS NULL));


    INSERT INTO debug_log (event, move_id, info)
    VALUES ('move_line_done_update_stock', NEW.move_id, 'Stock updated: item_id=' || NEW.item_id || ', from location_id=' || NEW.source_id || ' to location_id=' || NEW.target_id || ', qty=' || NEW.done_quantity);

    
    INSERT INTO debug_log (event, move_id, info)
    VALUES ('move_auto_done', NEW.move_id, 'All move lines done, setting move to done');

    UPDATE move
    SET status = 'done'
    WHERE id = NEW.move_id
      AND (
        SELECT COUNT(*) FROM move_line WHERE move_id = NEW.move_id AND status != 'done'
      ) = 0
      AND (
        SELECT IFNULL(SUM(done_quantity), 0) FROM move_line WHERE move_id = NEW.move_id
      ) = (
        SELECT quantity FROM move WHERE id = NEW.move_id
      );
END;


-- Trigger: On move inserted, update move status
CREATE TRIGGER trg_move_auto_confirm
AFTER INSERT ON move
BEGIN
    UPDATE move
    SET status = 'confirmed'
    WHERE id = NEW.id
      AND status = 'draft';
END;



CREATE TRIGGER trg_move_chain_progress
AFTER UPDATE OF status ON move
WHEN NEW.status = 'done' AND OLD.status != 'done'
BEGIN
    INSERT INTO debug_log (event, move_id, info)
    VALUES ('move_chain_progress', NEW.id, 'Move set to done, attempting to confirm next move');
    
    UPDATE move
    SET status = 'confirmed'
    WHERE status = 'waiting'
      AND item_id = NEW.item_id
      AND source_id = NEW.target_id
      AND (lot_id = NEW.lot_id OR (lot_id IS NULL AND NEW.lot_id IS NULL));
    --   AND reserved_quantity = 0; -- Only progress moves that haven't reserved stock yet

    INSERT INTO debug_log (event, move_id, info)
    VALUES (
        'move_chain_progress',
        (SELECT id FROM move WHERE item_id = NEW.item_id AND lot_id = NEW.lot_id AND source_id = NEW.target_id ORDER BY id LIMIT 1),
        'Next move status: ' || IFNULL((SELECT status FROM move WHERE item_id = NEW.item_id AND lot_id = NEW.lot_id AND source_id = NEW.target_id ORDER BY id LIMIT 1), 'none')
    );
END;


-- Trigger: Check and allocate stock on move status change
CREATE TRIGGER trg_move_fulfillment_check
AFTER UPDATE OF status ON move
WHEN (NEW.status = 'assigned' OR NEW.status = 'confirmed') AND OLD.status != NEW.status
BEGIN
    -- Guard: Only proceed if move is not already fully fulfilled
    -- (Prevents duplicate move lines)
    -- If fulfilled, do nothing
    -- (SELECT IFNULL(SUM(quantity),0) FROM move_line WHERE move_id = NEW.id) < NEW.quantity

    INSERT INTO debug_log (event, move_id, info)
    VALUES ('move_fulfillment_check', NEW.id, 'Move status changed to ' || NEW.status || ', attempting to allocate stock and create move lines');

    -- 1. Try to allocate stock from all locations in the source zone
    INSERT INTO move_line (
        move_id, item_id, source_id, target_id, lot_id, quantity, reserved_quantity, status
    )
    SELECT
        NEW.id,
        NEW.item_id,
        s.location_id,
    COALESCE(
        -- Prefer the location linked to the customer (partner)
        (SELECT l.id
         FROM location l
         JOIN location_zone lz ON l.id = lz.location_id
         WHERE lz.zone_id = NEW.target_id
           AND l.partner_id = (SELECT partner_id FROM sale_order WHERE id = (SELECT origin_id FROM trigger WHERE id = NEW.trigger_id))
         LIMIT 1),
        -- Fallbacks as before, but now lot-aware
        (SELECT tgt_lz.location_id
         FROM location_zone tgt_lz
         JOIN stock s ON s.location_id = tgt_lz.location_id AND s.item_id = NEW.item_id
         WHERE tgt_lz.zone_id = NEW.target_id
           AND (s.lot_id = NEW.lot_id OR (NEW.lot_id IS NULL AND s.lot_id IS NULL))
         ORDER BY s.quantity DESC
         LIMIT 1),
        (SELECT tgt_lz.location_id
         FROM location_zone tgt_lz
         LEFT JOIN stock s ON s.location_id = tgt_lz.location_id AND s.item_id = NEW.item_id
         WHERE tgt_lz.zone_id = NEW.target_id
           AND (s.lot_id = NEW.lot_id OR (NEW.lot_id IS NULL AND s.lot_id IS NULL))
           AND (s.quantity IS NULL OR s.quantity = 0)
         LIMIT 1),
        (SELECT tgt_lz.location_id
         FROM location_zone tgt_lz
         LEFT JOIN (
             SELECT location_id, SUM(quantity) AS total_qty
             FROM stock
             WHERE (lot_id = NEW.lot_id OR (NEW.lot_id IS NULL AND lot_id IS NULL))
             GROUP BY location_id
         ) st ON st.location_id = tgt_lz.location_id
         WHERE tgt_lz.zone_id = NEW.target_id
         ORDER BY IFNULL(st.total_qty, 0) ASC
         LIMIT 1)
    ),
    s.lot_id,
    MIN(
        s.quantity - s.reserved_quantity,
        NEW.quantity - IFNULL((SELECT SUM(quantity) FROM move_line WHERE move_id = NEW.id), 0)
    ),
    MIN(
        s.quantity - s.reserved_quantity,
        NEW.quantity - IFNULL((SELECT SUM(quantity) FROM move_line WHERE move_id = NEW.id), 0)
    ),
    'assigned'
    FROM stock s
    JOIN location_zone lz ON lz.location_id = s.location_id
    WHERE lz.zone_id = NEW.source_id
      AND s.item_id = NEW.item_id
      AND (s.quantity - s.reserved_quantity) > 0
      AND (NEW.quantity - IFNULL((SELECT SUM(quantity) FROM move_line WHERE move_id = NEW.id), 0)) > 0
      AND (NEW.lot_id IS NULL OR s.lot_id = NEW.lot_id) -- <--- Only allocate from the move's lot if set
    ORDER BY s.lot_id -- FIFO or your preferred lot picking logic
    ;

    -- Otherwise, fallback to the original logic for 'pull'
    INSERT INTO trigger (
        origin_model,
        origin_id,
        trigger_type,
        trigger_route_id,
        trigger_item_id,
        trigger_zone_id,
        trigger_item_quantity,
        trigger_lot_id,
        type,
        status
    )
    SELECT
        (SELECT origin_model FROM trigger WHERE id = NEW.trigger_id),
        (SELECT origin_id FROM trigger WHERE id = NEW.trigger_id),
        'demand',
        NEW.route_id,
        NEW.item_id,
        NEW.source_id,
        NEW.quantity - IFNULL((SELECT SUM(quantity) FROM move_line WHERE move_id = NEW.id), 0),
        NEW.lot_id,
        'internal',
        'draft'
    WHERE (NEW.quantity - IFNULL((SELECT SUM(quantity) FROM move_line WHERE move_id = NEW.id), 0)) > 0
    AND (SELECT action FROM rule WHERE id = NEW.rule_id) != 'pull_or_buy'
    AND NOT EXISTS (
        SELECT 1 FROM trigger t
        WHERE t.trigger_type = 'demand'
            AND t.trigger_route_id = NEW.route_id
            AND t.trigger_item_id = NEW.item_id
            AND t.trigger_zone_id = NEW.source_id
            AND t.trigger_item_quantity = (NEW.quantity - IFNULL((SELECT SUM(quantity) FROM move_line WHERE move_id = NEW.id), 0))
            AND (t.trigger_lot_id = NEW.lot_id OR (t.trigger_lot_id IS NULL AND NEW.lot_id IS NULL))
            AND t.status = 'draft'
    );
        

    -- -- If rule is 'pull_or_buy' and not enough stock, create or update a purchase order and line for the missing quantity

    -- INSERT INTO purchase_order (status, origin, partner_id, code, currency_id, tax_id, discount_id)
    -- SELECT
    --     'draft',
    --     'Auto-created for pull_or_buy (vendor_id=' || (SELECT vendor_id FROM item WHERE id = NEW.item_id) || ')',
    --     (SELECT vendor_id FROM item WHERE id = NEW.item_id),
    --     'PO_AUTO_' || (SELECT vendor_id FROM item WHERE id = NEW.item_id) || '_' || strftime('%Y%m%d%H%M%f','now'),
    --     NULL, NULL, NULL
    -- WHERE (SELECT action FROM rule WHERE id = NEW.rule_id) = 'pull_or_buy'
    -- AND NOT EXISTS (
    --     SELECT 1 FROM purchase_order po
    --     WHERE po.status = 'draft'
    --     AND po.partner_id = (SELECT vendor_id FROM item WHERE id = NEW.item_id)
    -- );

    -- -- Insert or update purchase order line for the missing quantity
    -- INSERT INTO purchase_order_line (purchase_order_id, item_id, quantity, route_id)
    -- SELECT
    --     (SELECT id FROM purchase_order
    --     WHERE status = 'draft'
    --     AND partner_id = (SELECT vendor_id FROM item WHERE id = NEW.item_id)
    --     ORDER BY id DESC LIMIT 1),
    --     NEW.item_id,
    --     NEW.quantity - IFNULL((SELECT SUM(quantity) FROM move_line WHERE move_id = NEW.id), 0),
    --     NEW.route_id
    -- WHERE (NEW.quantity - IFNULL((SELECT SUM(quantity) FROM move_line WHERE move_id = NEW.id), 0)) > 0
    -- AND (SELECT action FROM rule WHERE id = NEW.rule_id) = 'pull_or_buy';

    -- -- Optionally, if you want to update an existing PO line instead of inserting a new one for the same item:
    -- UPDATE purchase_order_line
    -- SET quantity = quantity + (NEW.quantity - IFNULL((SELECT SUM(quantity) FROM move_line WHERE move_id = NEW.id), 0))
    -- WHERE purchase_order_id = (
    --         SELECT id FROM purchase_order
    --         WHERE status = 'draft'
    --         AND partner_id = (SELECT vendor_id FROM item WHERE id = NEW.item_id)
    --         ORDER BY id DESC LIMIT 1
    --     )
    -- AND item_id = NEW.item_id
    -- AND (SELECT action FROM rule WHERE id = NEW.rule_id) = 'pull_or_buy'
    -- AND EXISTS (
    --     SELECT 1 FROM purchase_order_line
    --     WHERE purchase_order_id = (
    --         SELECT id FROM purchase_order
    --         WHERE status = 'draft'
    --             AND partner_id = (SELECT vendor_id FROM item WHERE id = NEW.item_id)
    --         ORDER BY id DESC LIMIT 1
    --     )
    --     AND item_id = NEW.item_id
    -- );

    -- 2a. If a new trigger was created and it has a rule_trigger, set move to 'waiting'
    UPDATE move
    SET status = 'waiting'
    WHERE id = NEW.id
      AND (SELECT IFNULL(SUM(quantity),0) FROM move_line WHERE move_id = NEW.id) < NEW.quantity
      AND EXISTS (
            SELECT 1 FROM trigger t
            JOIN rule_trigger rt ON rt.trigger_id = t.id
            WHERE t.trigger_item_id = NEW.item_id
              AND t.trigger_zone_id = NEW.source_id
              AND t.status = 'draft'
              AND t.trigger_item_quantity = (NEW.quantity - IFNULL((SELECT SUM(quantity) FROM move_line WHERE move_id = NEW.id), 0))
              AND (t.trigger_lot_id = NEW.lot_id OR (t.trigger_lot_id IS NULL AND NEW.lot_id IS NULL))
      );


    -- Log all available stock for the demanded item in the source zone
    INSERT INTO debug_log (event, move_id, info)
    SELECT
        'move_fulfillment_check',
        NEW.id,
        'Stock at location_id=' || s.location_id || ' for item_id=' || s.item_id ||
        ': quantity=' || s.quantity || ', reserved=' || s.reserved_quantity
    FROM stock s
    JOIN location_zone lz ON lz.location_id = s.location_id
    WHERE lz.zone_id = NEW.source_id
    AND s.item_id = NEW.item_id;


    INSERT INTO debug_log (event, move_id, info)
    SELECT 'move_fulfillment_check', NEW.id, 'No stock record found for item_id=' || NEW.item_id || ' in zone_id=' || NEW.source_id
    WHERE NOT EXISTS (
        SELECT 1
        FROM stock s
        JOIN location_zone lz ON lz.location_id = s.location_id
        WHERE lz.zone_id = NEW.source_id
        AND s.item_id = NEW.item_id
        AND (s.lot_id = NEW.lot_id OR (s.lot_id IS NULL AND NEW.lot_id IS NULL))
    );

    
    INSERT INTO debug_log (event, move_id, info)
    SELECT 'move_fulfillment_check', NEW.id, 'Move set to waiting after allocation attempt'
    WHERE (SELECT status FROM move WHERE id = NEW.id) = 'waiting';

    -- 2b. If a new trigger was created, but it has no rule_trigger, mark this move as terminal
    UPDATE move
    SET is_terminal = 1,
        status = 'intervene'
    WHERE id = NEW.id
      AND (SELECT IFNULL(SUM(quantity),0) FROM move_line WHERE move_id = NEW.id) < NEW.quantity
      AND NOT EXISTS (
            SELECT 1 FROM trigger t
            WHERE t.trigger_item_id = NEW.item_id
              AND t.trigger_zone_id = NEW.source_id
              AND t.status = 'draft'
              AND t.trigger_item_quantity = (NEW.quantity - IFNULL((SELECT SUM(quantity) FROM move_line WHERE move_id = NEW.id), 0))
              AND (t.trigger_lot_id = NEW.lot_id OR (t.trigger_lot_id IS NULL AND NEW.lot_id IS NULL))
              AND EXISTS (
                  SELECT 1 FROM rule_trigger rt
                  WHERE rt.trigger_id = t.id
              )
      );

    INSERT INTO debug_log (event, move_id, info)
    SELECT 'move_fulfillment_check', NEW.id, 'Move set to intervene after allocation attempt'
    WHERE (SELECT status FROM move WHERE id = NEW.id) = 'intervene';

    -- 3. If move is not fully fulfilled and is_terminal, create intervention
    INSERT INTO intervention (move_id, priority, reason, resolved)
    SELECT
        NEW.id,
        0,
        CASE
            WHEN (SELECT action FROM rule WHERE id = NEW.rule_id) = 'pull_or_buy'
            THEN 'Not enough stock. Purchase order created and waiting for confirmation: ' ||
                (SELECT code FROM purchase_order
                WHERE status = 'draft'
                AND partner_id = (SELECT vendor_id FROM item WHERE id = NEW.item_id)
                ORDER BY id DESC LIMIT 1)
            WHEN (SELECT action FROM rule WHERE id = NEW.rule_id) = 'push'
            THEN 'Supply not further handled: no push rule applies for this zone. Interventions will be resolved at the target location when stock is available.'
            ELSE 'Not enough stock and no further rules to handle demand. Internal move, purchase order, or stock adjustment is expected to resolve this issue.'
        END,
        CASE
            WHEN (SELECT action FROM rule WHERE id = NEW.rule_id) = 'push' THEN 1
            ELSE 0
        END
    WHERE
        (SELECT IFNULL(SUM(quantity),0) FROM move_line WHERE move_id = NEW.id) < NEW.quantity
        AND NOT EXISTS (
            SELECT 1 FROM trigger t
            JOIN rule_trigger rt ON rt.trigger_id = t.id
            WHERE t.trigger_item_id = NEW.item_id
            AND t.trigger_zone_id = NEW.source_id
            AND t.status = 'draft'
            AND t.trigger_item_quantity = (NEW.quantity - IFNULL((SELECT SUM(quantity) FROM move_line WHERE move_id = NEW.id), 0))
            AND (t.trigger_lot_id = NEW.lot_id OR (t.trigger_lot_id IS NULL AND NEW.lot_id IS NULL))
        );
END;



CREATE TRIGGER trg_move_cascade_done
AFTER UPDATE OF status ON move
WHEN NEW.status = 'done' AND OLD.status != 'done'
BEGIN
    INSERT INTO debug_log (event, move_id, info)
    VALUES ('move_cascade_done', NEW.id, 'Move set to done, attempting to fulfill next move');

    UPDATE move
    SET status = 'done'
    WHERE status = 'confirmed'
      AND item_id = NEW.item_id
      AND (lot_id = NEW.lot_id OR (lot_id IS NULL AND NEW.lot_id IS NULL))
      AND source_id = NEW.target_id
      AND (
        SELECT COUNT(*) FROM move_line WHERE move_id = id AND status != 'done'
      ) = 0
      AND (
        SELECT IFNULL(SUM(done_quantity), 0) FROM move_line WHERE move_id = id
      ) = quantity;

    INSERT INTO debug_log (event, move_id, info)
    VALUES (
        'move_cascade_done',
        (SELECT id FROM move WHERE item_id = NEW.item_id AND source_id = NEW.target_id AND status = 'done' ORDER BY id LIMIT 1),
        'Next move status: ' || IFNULL((SELECT status FROM move WHERE item_id = NEW.item_id AND source_id = NEW.target_id ORDER BY id LIMIT 1), 'none')
    );
END;





-- VIEWS
-- empty locations view
CREATE VIEW IF NOT EXISTS empty_locations AS
SELECT l.*
FROM location l
LEFT JOIN stock s ON l.id = s.location_id
GROUP BY l.id
HAVING SUM(CASE WHEN s.quantity IS NOT NULL THEN s.quantity ELSE 0 END) = 0;

-- move_lines_by_picking view
CREATE VIEW IF NOT EXISTS move_lines_by_picking AS
SELECT
    ml.*,
    m.picking_id,
    m.source_id,
    m.target_id,
    m.item_id,
    m.quantity AS move_quantity
FROM move_line ml
JOIN move m ON ml.move_id = m.id;

-- move_lines_by_move view
CREATE VIEW IF NOT EXISTS move_and_lines_by_origin AS
SELECT
    m.id            AS move_id,
    m.status        AS move_status,
    m.item_id,
    m.source_id,
    m.target_id,
    m.quantity      AS move_quantity,
    ml.id           AS move_line_id,
    ml.status       AS move_line_status,
    ml.quantity     AS move_line_quantity,
    ml.done_quantity,
    ml.source_id    AS move_line_source_id,
    ml.target_id    AS move_line_target_id,
    t.origin_model,
    t.origin_id
FROM move m
JOIN rule_trigger rt ON rt.move_id = m.id
JOIN trigger t ON t.id = rt.trigger_id
LEFT JOIN move_line ml ON ml.move_id = m.id;

-- stock_by_location view
DROP VIEW IF EXISTS stock_by_location;
CREATE VIEW stock_by_location AS
SELECT
    s.item_id,
    s.location_id,
    s.lot_id,
    l.code AS location_code,
    s.quantity,
    s.reserved_quantity
FROM stock s
JOIN location l ON s.location_id = l.id;


-- location_zone_view
CREATE VIEW location_zone_view AS
SELECT
    l.description AS location_description,
    l.code AS location_code,
    l.id AS location_id,
    z.id AS zone_id,
    z.code AS zone_code,
    z.description AS zone_description
FROM location l
JOIN location_zone lz ON l.id = lz.location_id
JOIN zone z ON z.id = lz.zone_id
ORDER BY l.id, z.id;


-- WAREHOUSE STOCK VIEW
DROP VIEW IF EXISTS warehouse_stock_view;
CREATE VIEW warehouse_stock_view AS
SELECT
    i.id AS item_id,
    i.name AS item_name,
    s.quantity AS stock_quantity,    
    l.id AS location_id,
    l.code AS location_code,
    s.lot_id,
    w.id AS warehouse_id,
    w.name AS warehouse_name
FROM
    warehouse w
JOIN
    location l ON l.warehouse_id = w.id
LEFT JOIN
    stock s ON s.location_id = l.id
LEFT JOIN
    item i ON i.id = s.item_id
;

-- ORDER ITEM VIEW
CREATE VIEW sale_order_item_view AS
SELECT
    so.id            AS sale_order_id,
    so.code          AS sale_order_code,
    so.status        AS sale_order_status,
    so.partner_id    AS customer_id,
    p.name           AS customer_name,
    so.created_at    AS order_created_at,
    ol.id            AS order_line_id,
    ol.quantity      AS item_quantity,
    i.id             AS item_id,
    i.name           AS item_name,
    i.sku            AS item_sku,
    i.size           AS item_size,
    i.description    AS item_description
FROM sale_order so
JOIN partner p ON so.partner_id = p.id
JOIN order_line ol ON ol.order_id = so.id
JOIN item i ON i.id = ol.item_id;

-- STOCK BY LOT VIEW
DROP VIEW IF EXISTS stock_by_lot;
CREATE VIEW IF NOT EXISTS stock_by_lot AS
SELECT
    s.item_id,
    s.location_id,
    s.lot_id,
    l.lot_number,
    s.quantity,
    s.reserved_quantity
FROM stock s
LEFT JOIN lot l ON s.lot_id = l.id;

-- AVAILABLE LOTS VIEW
DROP VIEW IF EXISTS available_lots;
CREATE VIEW IF NOT EXISTS available_lots AS
SELECT
    s.item_id,
    s.location_id,
    s.lot_id,
    l.lot_number,
    s.quantity - s.reserved_quantity AS available_quantity
FROM stock s
LEFT JOIN lot l ON s.lot_id = l.id
WHERE s.quantity - s.reserved_quantity > 0;

-- SEED DATA
-- Zones
INSERT INTO zone (code, description, route_id) VALUES
('ZON01', 'Incoming Zone', 1),
('ZON05', 'Quality Control Zone', 1),
('ZON02', 'Stock Zone', 1),
('ZON06', 'Overstock Zone', 1),
('ZON07', 'Hot Picking Zone', 1),
('ZON03', 'Packing Zone', 1),
('ZON04', 'Outgoing Zone', 1),
('ZON08', 'Vendor Area', 1),
('ZON09', 'Customer Area', 1),
('ZON10', 'Employee Area', 1);


-- -- Locations
INSERT INTO location (code, x, y, z, dx, dy, dz, warehouse_id, partner_id, description) VALUES
-- Input A/B (left side, away from shelves)
('LOC01.1', -10, 0, 0, 4.5, 4.5, 4.5, 1, NULL, 'Input A'),
('LOC01.2', -10, 10, 0, 4.5, 4.5, 4.5, 1, NULL, 'Input B'),

-- Quality Check A/B (far left, higher y)
('LOC05.1', -10, 20, 0, 4.5, 4.5, 4.5, 1, NULL, 'Quality Check A'),
('LOC05.2', -10, 30, 0, 4.5, 4.5, 4.5, 1, NULL, 'Quality Check B'),

-- Output (far right, higher y)
('LOC04.1', 40, 20, 0, 4.5, 4.5, 4.5, 1, NULL, 'Output A'),
('LOC04.2', 40, 30, 0, 4.5, 4.5, 4.5, 1, NULL, 'Output B'),

-- Packing (far right, away from shelves)
('LOC03.1', 40, 0, 0, 4.5, 4.5, 4.5, 1, NULL, 'Default Packing'),
('LOC03.2', 40, 10, 0, 4.5, 4.5, 4.5, 1, NULL, 'Priority Packing'),

-- ('LOC06.1', 10, 20, 0, 4.5, 4.5, 4.5, 1, NULL, 'Shelf 6A'),
-- ('LOC06.2', 10, 20, 5, 4.5, 4.5, 4.5, 1, NULL, 'Shelf 6B'),
-- ('LOC06.3', 10, 20, 10, 4.5, 4.5, 4.5, 1, NULL, 'Shelf 6C'),

-- ('LOC07.1', 15, 0, 0, 4.5, 4.5, 4.5, 1, NULL, 'Shelf 7A'),
-- ('LOC07.2', 15, 0, 5, 4.5, 4.5, 4.5, 1, NULL, 'Shelf 7B'),
-- ('LOC07.3', 15, 0, 10, 4.5, 4.5, 4.5, 1, NULL, 'Shelf 7C'),
-- Row A (y=0)
('LOC_A_1', 0, 0, 0.05,   4, 1, 2.5, 1, NULL, 'Shelf A Level 1'),
('LOC_A_2', 0, 0, 3,      4, 1, 2.5, 1, NULL, 'Shelf A Level 2'),
('LOC_A_3', 0, 0, 6,      4, 1, 2.5, 1, NULL, 'Shelf A Level 3'),
('LOC_A_4', 0, 0, 9,      4, 1, 2.5, 1, NULL, 'Shelf A Level 4'),

('LOC_B_1', 6, 0, 0,      4, 1, 2.5, 1, NULL, 'Shelf B Level 1'),
('LOC_B_2', 6, 0, 3,      4, 1, 2.5, 1, NULL, 'Shelf B Level 2'),
('LOC_B_3', 6, 0, 6,      4, 1, 2.5, 1, NULL, 'Shelf B Level 3'),
('LOC_B_4', 6, 0, 9,      4, 1, 2.5, 1, NULL, 'Shelf B Level 4'),

('LOC_C_1', 12, 0, 0,     4, 1, 2.5, 1, NULL, 'Shelf C Level 1'),
('LOC_C_2', 12, 0, 3,     4, 1, 2.5, 1, NULL, 'Shelf C Level 2'),
('LOC_C_3', 12, 0, 6,     4, 1, 2.5, 1, NULL, 'Shelf C Level 3'),
('LOC_C_4', 12, 0, 9,     4, 1, 2.5, 1, NULL, 'Shelf C Level 4'),

('LOC_D_1', 18, 0, 0,     4, 1, 2.5, 1, NULL, 'Shelf D Level 1'),
('LOC_D_2', 18, 0, 3,     4, 1, 2.5, 1, NULL, 'Shelf D Level 2'),
('LOC_D_3', 18, 0, 6,     4, 1, 2.5, 1, NULL, 'Shelf D Level 3'),
('LOC_D_4', 18, 0, 9,     4, 1, 2.5, 1, NULL, 'Shelf D Level 4'),

('LOC_E_1', 24, 0, 0,     4, 1, 2.5, 1, NULL, 'Shelf E Level 1'),
('LOC_E_2', 24, 0, 3,     4, 1, 2.5, 1, NULL, 'Shelf E Level 2'),
('LOC_E_3', 24, 0, 6,     4, 1, 2.5, 1, NULL, 'Shelf E Level 3'),
('LOC_E_4', 24, 0, 9,     4, 1, 2.5, 1, NULL, 'Shelf E Level 4'),

('LOC_F_1', 30, 0, 0,     4, 1, 2.5, 1, NULL, 'Shelf F Level 1'),
('LOC_F_2', 30, 0, 3,     4, 1, 2.5, 1, NULL, 'Shelf F Level 2'),
('LOC_F_3', 30, 0, 6,     4, 1, 2.5, 1, NULL, 'Shelf F Level 3'),
('LOC_F_4', 30, 0, 9,     4, 1, 2.5, 1, NULL, 'Shelf F Level 4'),

-- Row G (y=10)
('LOC_A2_1', 0, 10, 0,    4, 1, 2.5, 1, NULL, 'Shelf A2 Level 1'),
('LOC_A2_2', 0, 10, 3,    4, 1, 2.5, 1, NULL, 'Shelf A2 Level 2'),
('LOC_A2_3', 0, 10, 6,    4, 1, 2.5, 1, NULL, 'Shelf A2 Level 3'),
('LOC_A2_4', 0, 10, 9,    4, 1, 2.5, 1, NULL, 'Shelf A2 Level 4'),

('LOC_B2_1', 6, 10, 0,    4, 1, 2.5, 1, NULL, 'Shelf B2 Level 1'),
('LOC_B2_2', 6, 10, 3,    4, 1, 2.5, 1, NULL, 'Shelf B2 Level 2'),
('LOC_B2_3', 6, 10, 6,    4, 1, 2.5, 1, NULL, 'Shelf B2 Level 3'),
('LOC_B2_4', 6, 10, 9,    4, 1, 2.5, 1, NULL, 'Shelf B2 Level 4'),

('LOC_C2_1', 12, 10, 0,   4, 1, 2.5, 1, NULL, 'Shelf C2 Level 1'),
('LOC_C2_2', 12, 10, 3,   4, 1, 2.5, 1, NULL, 'Shelf C2 Level 2'),
('LOC_C2_3', 12, 10, 6,   4, 1, 2.5, 1, NULL, 'Shelf C2 Level 3'),
('LOC_C2_4', 12, 10, 9,   4, 1, 2.5, 1, NULL, 'Shelf C2 Level 4'),

('LOC_D2_1', 18, 10, 0,   4, 1, 2.5, 1, NULL, 'Shelf D2 Level 1'),
('LOC_D2_2', 18, 10, 3,   4, 1, 2.5, 1, NULL, 'Shelf D2 Level 2'),
('LOC_D2_3', 18, 10, 6,   4, 1, 2.5, 1, NULL, 'Shelf D2 Level 3'),
('LOC_D2_4', 18, 10, 9,   4, 1, 2.5, 1, NULL, 'Shelf D2 Level 4'),

('LOC_E2_1', 24, 10, 0,   4, 1, 2.5, 1, NULL, 'Shelf E2 Level 1'),
('LOC_E2_2', 24, 10, 3,   4, 1, 2.5, 1, NULL, 'Shelf E2 Level 2'),
('LOC_E2_3', 24, 10, 6,   4, 1, 2.5, 1, NULL, 'Shelf E2 Level 3'),
('LOC_E2_4', 24, 10, 9,   4, 1, 2.5, 1, NULL, 'Shelf E2 Level 4'),

('LOC_F2_1', 30, 10, 0,   4, 1, 2.5, 1, NULL, 'Shelf F2 Level 1'),
('LOC_F2_2', 30, 10, 3,   4, 1, 2.5, 1, NULL, 'Shelf F2 Level 2'),
('LOC_F2_3', 30, 10, 6,   4, 1, 2.5, 1, NULL, 'Shelf F2 Level 3'),
('LOC_F2_4', 30, 10, 9,   4, 1, 2.5, 1, NULL, 'Shelf F2 Level 4'),

-- Row H (y=20)
('LOC_A3_1', 0, 20, 0,    4, 1, 2.5, 1, NULL, 'Shelf A3 Level 1'),
('LOC_A3_2', 0, 20, 3,    4, 1, 2.5, 1, NULL, 'Shelf A3 Level 2'),
('LOC_A3_3', 0, 20, 6,    4, 1, 2.5, 1, NULL, 'Shelf A3 Level 3'),
('LOC_A3_4', 0, 20, 9,    4, 1, 2.5, 1, NULL, 'Shelf A3 Level 4'),

('LOC_B3_1', 6, 20, 0,    4, 1, 2.5, 1, NULL, 'Shelf B3 Level 1'),
('LOC_B3_2', 6, 20, 3,    4, 1, 2.5, 1, NULL, 'Shelf B3 Level 2'),
('LOC_B3_3', 6, 20, 6,    4, 1, 2.5, 1, NULL, 'Shelf B3 Level 3'),
('LOC_B3_4', 6, 20, 9,    4, 1, 2.5, 1, NULL, 'Shelf B3 Level 4'),

('LOC_C3_1', 12, 20, 0,   4, 1, 2.5, 1, NULL, 'Shelf C3 Level 1'),
('LOC_C3_2', 12, 20, 3,   4, 1, 2.5, 1, NULL, 'Shelf C3 Level 2'),
('LOC_C3_3', 12, 20, 6,   4, 1, 2.5, 1, NULL, 'Shelf C3 Level 3'),
('LOC_C3_4', 12, 20, 9,   4, 1, 2.5, 1, NULL, 'Shelf C3 Level 4'),

('LOC_D3_1', 18, 20, 0,   4, 1, 2.5, 1, NULL, 'Shelf D3 Level 1'),
('LOC_D3_2', 18, 20, 3,   4, 1, 2.5, 1, NULL, 'Shelf D3 Level 2'),
('LOC_D3_3', 18, 20, 6,   4, 1, 2.5, 1, NULL, 'Shelf D3 Level 3'),
('LOC_D3_4', 18, 20, 9,   4, 1, 2.5, 1, NULL, 'Shelf D3 Level 4'),

('LOC_E3_1', 24, 20, 0,   4, 1, 2.5, 1, NULL, 'Shelf E3 Level 1'),
('LOC_E3_2', 24, 20, 3,   4, 1, 2.5, 1, NULL, 'Shelf E3 Level 2'),
('LOC_E3_3', 24, 20, 6,   4, 1, 2.5, 1, NULL, 'Shelf E3 Level 3'),
('LOC_E3_4', 24, 20, 9,   4, 1, 2.5, 1, NULL, 'Shelf E3 Level 4'),

('LOC_F3_1', 30, 20, 0,   4, 1, 2.5, 1, NULL, 'Shelf F3 Level 1'),
('LOC_F3_2', 30, 20, 3,   4, 1, 2.5, 1, NULL, 'Shelf F3 Level 2'),
('LOC_F3_3', 30, 20, 6,   4, 1, 2.5, 1, NULL, 'Shelf F3 Level 3'),
('LOC_F3_4', 30, 20, 9,   4, 1, 2.5, 1, NULL, 'Shelf F3 Level 4'),

-- Row I (y=30)
('LOC_A4_1', 0, 30, 0,    4, 1, 2.5, 1, NULL, 'Shelf A4 Level 1'),
('LOC_A4_2', 0, 30, 3,    4, 1, 2.5, 1, NULL, 'Shelf A4 Level 2'),
('LOC_A4_3', 0, 30, 6,    4, 1, 2.5, 1, NULL, 'Shelf A4 Level 3'),
('LOC_A4_4', 0, 30, 9,    4, 1, 2.5, 1, NULL, 'Shelf A4 Level 4'),

('LOC_B4_1', 6, 30, 0,    4, 1, 2.5, 1, NULL, 'Shelf B4 Level 1'),
('LOC_B4_2', 6, 30, 3,    4, 1, 2.5, 1, NULL, 'Shelf B4 Level 2'),
('LOC_B4_3', 6, 30, 6,    4, 1, 2.5, 1, NULL, 'Shelf B4 Level 3'),
('LOC_B4_4', 6, 30, 9,    4, 1, 2.5, 1, NULL, 'Shelf B4 Level 4'),

('LOC_C4_1', 12, 30, 0,   4, 1, 2.5, 1, NULL, 'Shelf C4 Level 1'),
('LOC_C4_2', 12, 30, 3,   4, 1, 2.5, 1, NULL, 'Shelf C4 Level 2'),
('LOC_C4_3', 12, 30, 6,   4, 1, 2.5, 1, NULL, 'Shelf C4 Level 3'),
('LOC_C4_4', 12, 30, 9,   4, 1, 2.5, 1, NULL, 'Shelf C4 Level 4'),

('LOC_D4_1', 18, 30, 0,   4, 1, 2.5, 1, NULL, 'Shelf D4 Level 1'),
('LOC_D4_2', 18, 30, 3,   4, 1, 2.5, 1, NULL, 'Shelf D4 Level 2'),
('LOC_D4_3', 18, 30, 6,   4, 1, 2.5, 1, NULL, 'Shelf D4 Level 3'),
('LOC_D4_4', 18, 30, 9,   4, 1, 2.5, 1, NULL, 'Shelf D4 Level 4'),

('LOC_E4_1', 24, 30, 0,   4, 1, 2.5, 1, NULL, 'Shelf E4 Level 1'),
('LOC_E4_2', 24, 30, 3,   4, 1, 2.5, 1, NULL, 'Shelf E4 Level 2'),
('LOC_E4_3', 24, 30, 6,   4, 1, 2.5, 1, NULL, 'Shelf E4 Level 3'),
('LOC_E4_4', 24, 30, 9,   4, 1, 2.5, 1, NULL, 'Shelf E4 Level 4'),

('LOC_F4_1', 30, 30, 0,   4, 1, 2.5, 1, NULL, 'Shelf F4 Level 1'),
('LOC_F4_2', 30, 30, 3,   4, 1, 2.5, 1, NULL, 'Shelf F4 Level 2'),
('LOC_F4_3', 30, 30, 6,   4, 1, 2.5, 1, NULL, 'Shelf F4 Level 3'),
('LOC_F4_4', 30, 30, 9,   4, 1, 2.5, 1, NULL, 'Shelf F4 Level 4');

-- -- ('Customer B', 0, 0, 0, 1, (SELECT id FROM partner WHERE name = 'Customer B'), 'Customer B'),
-- -- ('Vendor A', 0, 0, 0, 1, (SELECT id FROM partner WHERE name = 'Supplier A'), 'Vendor A');

-- Location Zones
INSERT INTO location_zone (location_id, zone_id) VALUES
((SELECT id FROM location WHERE code = 'LOC01.1'), (SELECT id FROM zone WHERE code = 'ZON01')),
((SELECT id FROM location WHERE code = 'LOC01.2'), (SELECT id FROM zone WHERE code = 'ZON01')),
((SELECT id FROM location WHERE code = 'LOC05.1'), (SELECT id FROM zone WHERE code = 'ZON05')),
((SELECT id FROM location WHERE code = 'LOC05.2'), (SELECT id FROM zone WHERE code = 'ZON05')),
-- ((SELECT id FROM location WHERE code = 'LOC06.1'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC06.2'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC06.3'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC06.1'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC06.2'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC06.3'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC07.1'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC07.2'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC07.3'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC07.1'), (SELECT id FROM zone WHERE code = 'ZON07')),
-- ((SELECT id FROM location WHERE code = 'LOC07.2'), (SELECT id FROM zone WHERE code = 'ZON07')),
-- ((SELECT id FROM location WHERE code = 'LOC07.3'), (SELECT id FROM zone WHERE code = 'ZON07')),

((SELECT id FROM location WHERE code = 'LOC03.1'), (SELECT id FROM zone WHERE code = 'ZON03')),
((SELECT id FROM location WHERE code = 'LOC03.2'), (SELECT id FROM zone WHERE code = 'ZON03')),
((SELECT id FROM location WHERE code = 'LOC04.1'), (SELECT id FROM zone WHERE code = 'ZON04')),
((SELECT id FROM location WHERE code = 'LOC04.2'), (SELECT id FROM zone WHERE code = 'ZON04'));

-- Assign all shelf locations to Stock Zone (ZON02)
INSERT INTO location_zone (location_id, zone_id)
SELECT id, (SELECT id FROM zone WHERE code = 'ZON02') FROM location
WHERE code LIKE 'LOC_A_%' OR code LIKE 'LOC_B_%' OR code LIKE 'LOC_C_%' OR code LIKE 'LOC_D_%' OR code LIKE 'LOC_E_%' OR code LIKE 'LOC_F_%';

-- Assign A, B, E, F shelves to Hot Picking Zone (ZON07)
INSERT INTO location_zone (location_id, zone_id)
SELECT id, (SELECT id FROM zone WHERE code = 'ZON07') FROM location
WHERE code LIKE 'LOC_A_%' OR code LIKE 'LOC_B_%' OR code LIKE 'LOC_E_%' OR code LIKE 'LOC_F_%';

-- Assign C, D shelves to Overstock Zone (ZON06)
INSERT INTO location_zone (location_id, zone_id)
SELECT id, (SELECT id FROM zone WHERE code = 'ZON06') FROM location
WHERE code LIKE 'LOC_C_%' OR code LIKE 'LOC_D_%';


-- -- Row A–F (y=0): ZON02 for A/B/E/F, ZON06 for C/D
-- ((SELECT id FROM location WHERE code = 'LOC_A_1'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_A_2'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_A_3'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_A_4'), (SELECT id FROM zone WHERE code = 'ZON02')),

-- ((SELECT id FROM location WHERE code = 'LOC_B_1'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_B_2'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_B_3'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_B_4'), (SELECT id FROM zone WHERE code = 'ZON02')),

-- ((SELECT id FROM location WHERE code = 'LOC_C_1'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_C_2'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_C_3'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_C_4'), (SELECT id FROM zone WHERE code = 'ZON06')),

-- ((SELECT id FROM location WHERE code = 'LOC_D_1'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_D_2'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_D_3'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_D_4'), (SELECT id FROM zone WHERE code = 'ZON06')),

-- ((SELECT id FROM location WHERE code = 'LOC_E_1'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_E_2'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_E_3'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_E_4'), (SELECT id FROM zone WHERE code = 'ZON02')),

-- ((SELECT id FROM location WHERE code = 'LOC_F_1'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_F_2'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_F_3'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_F_4'), (SELECT id FROM zone WHERE code = 'ZON02')),

-- -- Row A2–F2 (y=10): ZON06 for A/B/E/F, ZON02 for C/D
-- ((SELECT id FROM location WHERE code = 'LOC_A2_1'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_A2_2'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_A2_3'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_A2_4'), (SELECT id FROM zone WHERE code = 'ZON06')),

-- ((SELECT id FROM location WHERE code = 'LOC_B2_1'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_B2_2'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_B2_3'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_B2_4'), (SELECT id FROM zone WHERE code = 'ZON06')),

-- ((SELECT id FROM location WHERE code = 'LOC_C2_1'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_C2_2'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_C2_3'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_C2_4'), (SELECT id FROM zone WHERE code = 'ZON02')),

-- ((SELECT id FROM location WHERE code = 'LOC_D2_1'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_D2_2'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_D2_3'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_D2_4'), (SELECT id FROM zone WHERE code = 'ZON02')),

-- ((SELECT id FROM location WHERE code = 'LOC_E2_1'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_E2_2'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_E2_3'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_E2_4'), (SELECT id FROM zone WHERE code = 'ZON06')),

-- ((SELECT id FROM location WHERE code = 'LOC_F2_1'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_F2_2'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_F2_3'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_F2_4'), (SELECT id FROM zone WHERE code = 'ZON06')),

-- -- Row H (y=20): ZON02 for A/B/E/F, ZON06 for C/D
-- ((SELECT id FROM location WHERE code = 'LOC_A3_1'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_A3_2'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_A3_3'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_A3_4'), (SELECT id FROM zone WHERE code = 'ZON02')),

-- ((SELECT id FROM location WHERE code = 'LOC_B3_1'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_B3_2'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_B3_3'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_B3_4'), (SELECT id FROM zone WHERE code = 'ZON02')),

-- ((SELECT id FROM location WHERE code = 'LOC_C3_1'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_C3_2'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_C3_3'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_C3_4'), (SELECT id FROM zone WHERE code = 'ZON06')),

-- ((SELECT id FROM location WHERE code = 'LOC_D3_1'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_D3_2'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_D3_3'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_D3_4'), (SELECT id FROM zone WHERE code = 'ZON06')),

-- ((SELECT id FROM location WHERE code = 'LOC_E3_1'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_E3_2'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_E3_3'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_E3_4'), (SELECT id FROM zone WHERE code = 'ZON02')),

-- ((SELECT id FROM location WHERE code = 'LOC_F3_1'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_F3_2'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_F3_3'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_F3_4'), (SELECT id FROM zone WHERE code = 'ZON02')),

-- -- Row I (y=30): ZON06 for A/B/E/F, ZON02 for C/D
-- ((SELECT id FROM location WHERE code = 'LOC_A4_1'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_A4_2'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_A4_3'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_A4_4'), (SELECT id FROM zone WHERE code = 'ZON06')),

-- ((SELECT id FROM location WHERE code = 'LOC_B4_1'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_B4_2'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_B4_3'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_B4_4'), (SELECT id FROM zone WHERE code = 'ZON06')),

-- ((SELECT id FROM location WHERE code = 'LOC_C4_1'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_C4_2'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_C4_3'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_C4_4'), (SELECT id FROM zone WHERE code = 'ZON02')),

-- ((SELECT id FROM location WHERE code = 'LOC_D4_1'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_D4_2'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_D4_3'), (SELECT id FROM zone WHERE code = 'ZON02')),
-- ((SELECT id FROM location WHERE code = 'LOC_D4_4'), (SELECT id FROM zone WHERE code = 'ZON02')),

-- ((SELECT id FROM location WHERE code = 'LOC_E4_1'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_E4_2'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_E4_3'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_E4_4'), (SELECT id FROM zone WHERE code = 'ZON06')),

-- ((SELECT id FROM location WHERE code = 'LOC_F4_1'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_F4_2'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_F4_3'), (SELECT id FROM zone WHERE code = 'ZON06')),
-- ((SELECT id FROM location WHERE code = 'LOC_F4_4'), (SELECT id FROM zone WHERE code = 'ZON06'));

-- Partners (add more vendors)
INSERT INTO partner (
    name, street, city, country, zip,
    billing_street, billing_city, billing_country, billing_zip,
    email, phone, partner_type
) VALUES
('Supplier A', 'Supplier St 1', 'Supplier City', 'CountryX', '1000',
    'Supplier Billing St 1', 'Supplier Billing City', 'CountryX', '1001',
    'supplierA@example.com', '123456789', 'vendor'),
('Supplier B', 'Supplier St 2', 'Supplier City', 'CountryX', '1002',
    'Supplier Billing St 2', 'Supplier Billing City', 'CountryX', '1003',
    'supplierB@example.com', '223456789', 'vendor'),
('Carrier C', 'Carrier Rd 10', 'Carrier City', 'CountryX', '2000',
    'Carrier Billing Rd 10', 'Carrier Billing City', 'CountryX', '2001',
    'carrier@example.com', '987654321', 'employee'),
('Customer B', 'Customer Ave 5', 'Customer City', 'CountryX', '3000',
    'Customer Billing Ave 5', 'Customer Billing City', 'CountryX', '3001',
    'customer@example.com', '555555555', 'customer'),
('Owner A', 'Owner Rd 2', 'Owner City', 'CountryX', '1500',
    'Owner Billing Rd 2', 'Owner Billing City', 'CountryX', '1501',
    'owner@example.com', '111222333', 'customer'),
('Employee E', 'Employee St 3', 'Employee City', 'CountryX', '4000',
    'Employee Billing St 3', 'Employee Billing City', 'CountryX', '4001',
    'e@example.com', '444555666', 'employee');

-- Companies
INSERT INTO company (partner_id, name) VALUES
(5, "AlpWolf GmbH");

-- Users
INSERT INTO user (partner_id, company_id, username, password_hash)
VALUES (3, 1, 'admin', '$2b$12$lffwZ.0/JoHoDkBJc8WWQeOgTUvXCVYzUADAs4I/dJbMM0nn9Il0O'); -- Password: admin

-- Warehouse
INSERT INTO warehouse (name, company_id) VALUES
('Main Warehouse', 1);

-- Items with each having its own vendor
INSERT INTO item (
    name, sku, barcode, size, description, route_id, vendor_id,
    cost, cost_currency_id, purchase_price, purchase_currency_id
) VALUES
('Item Small A', 'SKU001', 'BAR001', 'small', 'Small item A', NULL, (SELECT id FROM partner WHERE name = 'Supplier A'),
    7.00, (SELECT id FROM currency WHERE code='EUR'), 7.50, (SELECT id FROM currency WHERE code='EUR')),
('Item Big B', 'SKU002', 'BAR002', 'big', 'Big item B', NULL, (SELECT id FROM partner WHERE name = 'Supplier B'),
    15.00, (SELECT id FROM currency WHERE code='EUR'), 16.00, (SELECT id FROM currency WHERE code='EUR'));


-- -- Seed currencies
INSERT INTO currency (code, symbol, name) VALUES
('EUR', '€', 'Euro'),
('USD', '$', 'US Dollar');

-- -- Seed taxes
INSERT INTO tax (name, percent, description) VALUES
('Standard VAT', 19.0, 'Standard German VAT'),
('Reduced VAT', 7.0, 'Reduced VAT for food/books');

-- -- Seed discounts
INSERT INTO discount (name, percent, amount, description) VALUES
('No Discount', NULL, 0.0, 'No discount'),
('Spring Sale', 10.0, NULL, '10% off for spring promotion'),
('Fixed 5 EUR', NULL, 5.0, '5 EUR off');

-- -- Seed price list
INSERT INTO price_list (name, currency_id, valid_from, valid_to) VALUES
('Default EUR', (SELECT id FROM currency WHERE code='EUR'), '2025-01-01', '2025-12-31');

-- -- Price list items
INSERT INTO price_list_item (price_list_id, item_id, price) VALUES
((SELECT id FROM price_list WHERE name='Default EUR'), 1, 12.50),
((SELECT id FROM price_list WHERE name='Default EUR'), 2, 25.00);



-- -- Purchase order for each vendor
-- INSERT INTO purchase_order (
--     status, origin, code, partner_id, currency_id, tax_id, discount_id
-- ) VALUES (
--     'draft',
--     'Seeded PO A',
--     'PO0001',
--     (SELECT id FROM partner WHERE name='Supplier A'),
--     (SELECT id FROM currency WHERE code='EUR'),
--     (SELECT id FROM tax WHERE name='Standard VAT'),
--     (SELECT id FROM discount WHERE name='No Discount')
-- ), (
--     'draft',
--     'Seeded PO B',
--     'PO0002',
--     (SELECT id FROM partner WHERE name='Supplier B'),
--     (SELECT id FROM currency WHERE code='EUR'),
--     (SELECT id FROM tax WHERE name='Standard VAT'),
--     (SELECT id FROM discount WHERE name='No Discount')
-- );


-- -- Seed lots for each item
INSERT INTO lot (item_id, lot_number, origin_model, origin_id, quality_control_status, notes)
VALUES
(1, 'LOT-A-001', NULL, NULL, 'accepted', 'Seeded lot for Item Small A'),
(1, 'LOT-A-002', NULL, NULL, 'accepted', 'Second lot for Item Small A'),
(2, 'LOT-B-001', NULL, NULL, 'accepted', 'Seeded lot for Item Big B');

-- -- -- Stock for each vendor's item, now lot-aware
-- INSERT INTO stock (item_id, location_id, lot_id, quantity, reserved_quantity)
-- VALUES
-- (1, (SELECT id FROM location WHERE code = 'LOC01.1'), (SELECT id FROM lot WHERE lot_number='LOT-A-001'), 500, 0),
-- (1, (SELECT id FROM location WHERE code = 'LOC01.2'), (SELECT id FROM lot WHERE lot_number='LOT-A-002'), 500, 0),
-- (2, (SELECT id FROM location WHERE code = 'LOC06.1'), (SELECT id FROM lot WHERE lot_number='LOT-B-001'), 1000, 0);


-- -- -- Stock levels (assuming items start in incoming location)
-- INSERT INTO stock (item_id, location_id, quantity) VALUES
-- (1, 12, 50),
-- (2, 11, 20);

-- Stock for each vendor's item (assuming you have locations for each vendor)
INSERT INTO stock (item_id, location_id, lot_id, quantity, reserved_quantity, target_quantity)
SELECT i.id, l.id, NULL, 1000, 0, 100
FROM item i
JOIN partner p ON i.vendor_id = p.id AND p.partner_type = 'vendor'
JOIN location l ON l.partner_id = p.id;




-- Routes (set active=1 for all initial routes)
INSERT INTO route (name, description, active) VALUES
('Default', 'Default route for receiving and shipping goods', 1),
('Return Route', 'Route for customer returns with quality check', 1);

-- Rules (set active=1 for all initial rules)
INSERT INTO rule (
    route_id, action, source_id, target_id, delay, active
) VALUES
((SELECT id FROM route WHERE name = 'Default'), 'push', (SELECT id FROM zone WHERE code='ZON08'), (SELECT id FROM zone WHERE code='ZON01'), 0, 1),
((SELECT id FROM route WHERE name = 'Default'), 'push', (SELECT id FROM zone WHERE code='ZON01'), (SELECT id FROM zone WHERE code='ZON05'), 0, 1),
((SELECT id FROM route WHERE name = 'Default'), 'push', (SELECT id FROM zone WHERE code='ZON05'), (SELECT id FROM zone WHERE code='ZON06'), 0, 1),

((SELECT id FROM route WHERE name = 'Default'), 'pull_or_buy', (SELECT id FROM zone WHERE code='ZON01'), (SELECT id FROM zone WHERE code='ZON05'), 0, 1),
((SELECT id FROM route WHERE name = 'Default'), 'pull', (SELECT id FROM zone WHERE code='ZON05'), (SELECT id FROM zone WHERE code='ZON06'), 0, 1),
((SELECT id FROM route WHERE name = 'Default'), 'pull', (SELECT id FROM zone WHERE code='ZON06'), (SELECT id FROM zone WHERE code='ZON07'), 0, 1),
((SELECT id FROM route WHERE name = 'Default'), 'pull', (SELECT id FROM zone WHERE code='ZON07'), (SELECT id FROM zone WHERE code='ZON03'), 0, 1),
((SELECT id FROM route WHERE name = 'Default'), 'pull', (SELECT id FROM zone WHERE code='ZON03'), (SELECT id FROM zone WHERE code='ZON04'), 0, 1),
((SELECT id FROM route WHERE name = 'Default'), 'pull', (SELECT id FROM zone WHERE code='ZON04'), (SELECT id FROM zone WHERE code='ZON09'), 0, 1);

-- Rules for the return route: Customer Area → Input → Quality → Stock
INSERT INTO rule (route_id, action, source_id, target_id, delay, active) VALUES
((SELECT id FROM route WHERE name = 'Return Route'), 'push', (SELECT id FROM zone WHERE code='ZON01'), (SELECT id FROM zone WHERE code='ZON05'), 0, 1),
((SELECT id FROM route WHERE name = 'Return Route'), 'push', (SELECT id FROM zone WHERE code='ZON05'), (SELECT id FROM zone WHERE code='ZON02'), 0, 1);

-- Sale order with currency, tax, and discount at creation
-- INSERT INTO sale_order (
--     code, partner_id, status, currency_id, tax_id, discount_id
-- ) VALUES (
--     'ORD0001',
--     (SELECT id FROM partner WHERE name = 'Customer B'),
--     'draft',
--     (SELECT id FROM currency WHERE code='EUR'),
--     (SELECT id FROM tax WHERE name='Standard VAT'),
--     (SELECT id FROM discount WHERE name='Spring Sale')
-- );

-- Order lines (provide price, currency_id, cost, and cost_currency_id)
-- INSERT INTO order_line (
--     quantity, item_id, lot_id, order_id, price, currency_id, cost, cost_currency_id
-- ) VALUES
-- (10, 1, NULL, 1, 12.50, (SELECT id FROM currency WHERE code='EUR'), 7.00, (SELECT id FROM currency WHERE code='EUR')),
-- (5, 2, NULL, 1, 25.00, (SELECT id FROM currency WHERE code='EUR'), 15.00, (SELECT id FROM currency WHERE code='EUR'));


-- Order lines referencing lots (simulate a customer requesting a specific lot)
-- INSERT INTO order_line (
--     quantity, item_id, lot_id, order_id, price, currency_id, cost, cost_currency_id
-- ) VALUES
-- (5, 1, (SELECT id FROM lot WHERE lot_number='LOT-A-001'), 1, 12.50, (SELECT id FROM currency WHERE code='EUR'), 7.00, (SELECT id FROM currency WHERE code='EUR')),
-- (5, 2, (SELECT id FROM lot WHERE lot_number='LOT-B-001'), 1, 25.00, (SELECT id FROM currency WHERE code='EUR'), 15.00, (SELECT id FROM currency WHERE code='EUR'));


-- Purchase order lines referencing lots
-- INSERT INTO purchase_order_line (
--     purchase_order_id, item_id, lot_id, quantity, route_id, price, currency_id, cost, cost_currency_id
-- ) VALUES
-- ((SELECT id FROM purchase_order WHERE origin='Seeded PO A'), 1, (SELECT id FROM lot WHERE lot_number='LOT-A-001'), 100, 1, 7.50, (SELECT id FROM currency WHERE code='EUR'), 7.00, (SELECT id FROM currency WHERE code='EUR')),
-- ((SELECT id FROM purchase_order WHERE origin='Seeded PO B'), 2, (SELECT id FROM lot WHERE lot_number='LOT-B-001'), 50, 1, 16.00, (SELECT id FROM currency WHERE code='EUR'), 15.00, (SELECT id FROM currency WHERE code='EUR'));

-- Return line referencing a lot
-- INSERT INTO return_order (code, origin_model, origin_id, partner_id, status)
-- VALUES (
--     'RET0001',
--     'sale_order',
--     1,
--     (SELECT id FROM partner WHERE name = 'Customer B'),
--     'confirmed'
-- );

-- INSERT INTO return_line (
--     return_order_id, item_id, lot_id, quantity, reason, refund_amount, refund_currency_id, refund_tax_id, refund_discount_id
-- ) VALUES (
--     (SELECT id FROM return_order WHERE origin_id = 1 AND origin_model = 'sale_order'),
--     1,
--     (SELECT id FROM lot WHERE lot_number='LOT-A-001'),
--     2,
--     'broken item',
--     12.50,
--     (SELECT currency_id FROM sale_order WHERE id = 1),
--     (SELECT tax_id FROM sale_order WHERE id = 1),
--     (SELECT discount_id FROM sale_order WHERE id = 1)
-- );
