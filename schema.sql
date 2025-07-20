PRAGMA recursive_triggers = ON;

-- Create Bill of Material
CREATE TABLE IF NOT EXISTS bom (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file BLOB,
    file_name TEXT,
    file_type TEXT,
    instructions TEXT NOT NULL
);


-- Create bom_line
CREATE TABLE IF NOT EXISTS bom_line (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bom_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    lot_id INTEGER, -- optional: specific lot for this bom line
    quantity REAL DEFAULT 1,
    FOREIGN KEY(bom_id) REFERENCES bom(id),
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(lot_id) REFERENCES lot(id)
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
    bom_id INTEGER,
    FOREIGN KEY(route_id) REFERENCES route(id),
    FOREIGN KEY(vendor_id) REFERENCES partner(id),
    FOREIGN KEY(cost_currency_id) REFERENCES currency(id),
    FOREIGN KEY(purchase_currency_id) REFERENCES currency(id),
    FOREIGN KEY(bom_id) REFERENCES bom(id)
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
    partner_type TEXT CHECK (partner_type IN ('vendor','customer','employee','carrier')) NOT NULL DEFAULT 'customer'
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
    route_id INTEGER, -- optional route for this adjustment
    partner_id INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(location_id) REFERENCES location(id),
    FOREIGN KEY(lot_id) REFERENCES lot(id),
    FOREIGN KEY(partner_id) REFERENCES partner(id),
    FOREIGN KEY(route_id) REFERENCES route(id)
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
    returned_quantity REAL DEFAULT 0,
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
    returned_quantity REAL DEFAULT 0, -- <--- add this line
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

-- Manufacturing Order
CREATE TABLE IF NOT EXISTS manufacturing_order (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,
    partner_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,         -- The finished product to manufacture
    quantity REAL NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('draft','confirmed','done','cancelled')) DEFAULT 'draft',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    planned_start DATETIME,
    planned_end DATETIME,
    origin TEXT,
    trigger_id INTEGER,               -- Link to the trigger that caused this MO
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(trigger_id) REFERENCES trigger(id),
    FOREIGN KEY(partner_id) REFERENCES partner(id)
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
    
    origin_model TEXT CHECK(origin_model IN ('sale_order', 'transfer_order', 'purchase_order', 'stock', 'return_order', 'manufacturing_order')) NOT NULL,
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
    -- 1. Create a new lot for this return line
    INSERT INTO lot (item_id, lot_number, origin_model, origin_id, quality_control_status, notes)
    VALUES (
        NEW.item_id,
        'RET-' || hex(randomblob(4)),
        'return_order',
        NEW.return_order_id,
        'pending',
        'Return from customer'
    );

    -- 2. Get the new lot id (most recent for this item/return)
    -- Use a subquery for all subsequent operations
    -- This is the lot that was just created
    -- (If you expect multiple lots per return_line, adapt accordingly)
    -- We'll use this subquery repeatedly:
    --   (SELECT id FROM lot WHERE origin_model = 'return_order' AND origin_id = NEW.return_order_id AND item_id = NEW.item_id ORDER BY id DESC LIMIT 1)

    -- 3. Assign the lot to the return line
    UPDATE return_line
    SET lot_id = (
        SELECT id FROM lot
        WHERE origin_model = 'return_order'
          AND origin_id = NEW.return_order_id
          AND item_id = NEW.item_id
        ORDER BY id DESC LIMIT 1
    )
    WHERE id = NEW.id;

    -- 4. Find the customer location for this return
    -- (Assumes one location per customer)
    -- Use this subquery for location:
    --   (SELECT l.id FROM location l JOIN return_order ro ON ro.id = NEW.return_order_id WHERE l.partner_id = ro.partner_id LIMIT 1)

    -- 5. Ensure stock record for item with lot_id IS NULL exists
    INSERT INTO stock (item_id, location_id, lot_id, quantity, reserved_quantity)
    SELECT NEW.item_id,
           (SELECT l.id FROM location l JOIN return_order ro ON ro.id = NEW.return_order_id WHERE l.partner_id = ro.partner_id LIMIT 1),
           NULL,
           0,
           0
    WHERE NOT EXISTS (
        SELECT 1 FROM stock
        WHERE item_id = NEW.item_id
          AND location_id = (SELECT l.id FROM location l JOIN return_order ro ON ro.id = NEW.return_order_id WHERE l.partner_id = ro.partner_id LIMIT 1)
          AND lot_id IS NULL
    );

    -- 6. Decrease stock for the item (without lot) at the customer's location
    UPDATE stock
    SET quantity = quantity - NEW.quantity
    WHERE item_id = NEW.item_id
      AND location_id = (SELECT l.id FROM location l JOIN return_order ro ON ro.id = NEW.return_order_id WHERE l.partner_id = ro.partner_id LIMIT 1)
      AND lot_id IS NULL;

    -- 7. Ensure stock record for the returned lot exists
    INSERT INTO stock (item_id, location_id, lot_id, quantity, reserved_quantity)
    SELECT NEW.item_id,
           (SELECT l.id FROM location l JOIN return_order ro ON ro.id = NEW.return_order_id WHERE l.partner_id = ro.partner_id LIMIT 1),
           (SELECT id FROM lot WHERE origin_model = 'return_order' AND origin_id = NEW.return_order_id AND item_id = NEW.item_id ORDER BY id DESC LIMIT 1),
           0,
           0
    WHERE NOT EXISTS (
        SELECT 1 FROM stock
        WHERE item_id = NEW.item_id
          AND location_id = (SELECT l.id FROM location l JOIN return_order ro ON ro.id = NEW.return_order_id WHERE l.partner_id = ro.partner_id LIMIT 1)
          AND lot_id = (SELECT id FROM lot WHERE origin_model = 'return_order' AND origin_id = NEW.return_order_id AND item_id = NEW.item_id ORDER BY id DESC LIMIT 1)
    );

    -- 8. Increase stock for the returned lot
    UPDATE stock
    SET quantity = quantity + NEW.quantity
    WHERE item_id = NEW.item_id
      AND location_id = (SELECT l.id FROM location l JOIN return_order ro ON ro.id = NEW.return_order_id WHERE l.partner_id = ro.partner_id LIMIT 1)
      AND lot_id = (SELECT id FROM lot WHERE origin_model = 'return_order' AND origin_id = NEW.return_order_id AND item_id = NEW.item_id ORDER BY id DESC LIMIT 1);

    -- 9. Create the supply trigger for the return, with the correct lot_id
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
        NEW.quantity,
        (SELECT id FROM lot WHERE origin_model = 'return_order' AND origin_id = NEW.return_order_id AND item_id = NEW.item_id ORDER BY id DESC LIMIT 1),
        'inbound',
        'draft'
    WHERE NEW.quantity > 0;
END;


DROP TRIGGER IF EXISTS trg_manufacturing_order_done_consume_and_produce;
CREATE TRIGGER trg_manufacturing_order_done_consume_and_produce
AFTER UPDATE OF status ON manufacturing_order
WHEN NEW.status = 'done' AND OLD.status != 'done'
BEGIN
    -- 1. Consume BOM components
    INSERT INTO stock_adjustment (item_id, location_id, lot_id, delta, reason)
    SELECT
        bl.item_id,
        (SELECT lz.location_id FROM location_zone lz WHERE lz.zone_id = (SELECT id FROM zone WHERE code = 'ZON_PROD') LIMIT 1),
        NULL,
        -1 * bl.quantity * NEW.quantity,
        'Consumed for MO ' || NEW.code
    FROM bom_line bl
    JOIN item i ON i.bom_id = bl.bom_id
    WHERE i.id = NEW.item_id;

    -- 2. Create a new lot for the finished product
    INSERT INTO lot (item_id, lot_number, origin_model, origin_id, quality_control_status, notes)
    VALUES (
        NEW.item_id,
        NEW.code || '-' || hex(randomblob(4)),
        'manufacturing_order',
        NEW.id,
        'pending',
        'Produced by MO ' || NEW.code
    );

    -- 3. Stock adjustment for finished product at production location with new lot and route_id
    INSERT INTO stock_adjustment (item_id, location_id, lot_id, delta, reason, route_id)
    VALUES (
        NEW.item_id,
        (SELECT lz.location_id FROM location_zone lz WHERE lz.zone_id = (SELECT id FROM zone WHERE code = 'ZON_PROD') LIMIT 1),
        (SELECT id FROM lot WHERE origin_model = 'manufacturing_order' AND origin_id = NEW.id ORDER BY id DESC LIMIT 1),
        NEW.quantity,
        'Produced by MO ' || NEW.code,
        (SELECT id FROM route WHERE name = 'Manufacturing Output')
    );
END;


-- Update returned_quantity on order_line when a return_order is confirmed
DROP TRIGGER IF EXISTS trg_confirm_return_order_update_returned_quantity;
CREATE TRIGGER trg_confirm_return_order_update_returned_quantity
AFTER UPDATE OF status ON return_order
WHEN NEW.status = 'confirmed' AND OLD.status != 'confirmed' AND NEW.origin_model = 'sale_order'
BEGIN
    UPDATE order_line
    SET returned_quantity = returned_quantity + (
        SELECT IFNULL(SUM(rl.quantity), 0)
        FROM return_line rl
        WHERE rl.return_order_id = NEW.id
          AND rl.item_id = order_line.item_id
          AND (rl.lot_id = order_line.lot_id OR (rl.lot_id IS NULL AND order_line.lot_id IS NULL))
    )
    WHERE order_line.order_id = NEW.origin_id
      AND EXISTS (
        SELECT 1 FROM return_line rl
        WHERE rl.return_order_id = NEW.id
          AND rl.item_id = order_line.item_id
          AND (rl.lot_id = order_line.lot_id OR (rl.lot_id IS NULL AND order_line.lot_id IS NULL))
    );
END;

-- Update returned_quantity on purchase_order_line when a return_order is confirmed
DROP TRIGGER IF EXISTS trg_confirm_return_po_update_returned_quantity;
CREATE TRIGGER trg_confirm_return_po_update_returned_quantity
AFTER UPDATE OF status ON return_order
WHEN NEW.status = 'confirmed' AND OLD.status != 'confirmed' AND NEW.origin_model = 'purchase_order'
BEGIN
    UPDATE purchase_order_line
    SET returned_quantity = returned_quantity + (
        SELECT IFNULL(SUM(rl.quantity), 0)
        FROM return_line rl
        WHERE rl.return_order_id = NEW.id
          AND rl.item_id = purchase_order_line.item_id
          AND (rl.lot_id = purchase_order_line.lot_id OR (rl.lot_id IS NULL AND purchase_order_line.lot_id IS NULL))
    )
    WHERE purchase_order_line.purchase_order_id = NEW.origin_id
      AND EXISTS (
        SELECT 1 FROM return_line rl
        WHERE rl.return_order_id = NEW.id
          AND rl.item_id = purchase_order_line.item_id
          AND (rl.lot_id = purchase_order_line.lot_id OR (rl.lot_id IS NULL AND purchase_order_line.lot_id IS NULL))
    );
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
        SELECT 1 FROM stock WHERE item_id = NEW.item_id AND location_id = NEW.location_id AND (
            NEW.lot_id IS NULL
            OR lot_id = NEW.lot_id
        )
    );

    -- Update both available and reserved quantities
    UPDATE stock
    SET quantity = quantity + NEW.delta,
        reserved_quantity = reserved_quantity + NEW.reserved_delta
    WHERE item_id = NEW.item_id AND location_id = NEW.location_id AND (
        NEW.lot_id IS NULL
        OR lot_id = NEW.lot_id
    );

    -- Only create a supply trigger if available stock increased
    INSERT INTO trigger (
        origin_model,
        origin_id,
        trigger_type,
        trigger_item_id,
        trigger_route_id,
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
        NEW.route_id,
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
WHEN NEW.quantity - NEW.reserved_quantity > 0
BEGIN
    -- Find the highest priority unresolved intervention for this location and item
    UPDATE move
    SET status = 'confirmed'
    WHERE id = (
        SELECT i.move_id
        FROM intervention i
        JOIN move m ON m.id = i.move_id
        WHERE m.source_id IN (SELECT zone_id FROM location_zone WHERE location_id = NEW.location_id)
            AND m.item_id = NEW.item_id
            AND (
                m.lot_id = NEW.lot_id
                OR (m.lot_id IS NULL)
            )
            AND i.resolved = 0
            -- AND m.quantity <= NEW.quantity - NEW.reserved_quantity
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
        WHERE m.source_id IN (SELECT zone_id FROM location_zone WHERE location_id = NEW.location_id)
            AND m.item_id = NEW.item_id
            AND (
                m.lot_id = NEW.lot_id
                OR (m.lot_id IS NULL)
            )
            AND i.resolved = 0
            AND (
                (SELECT IFNULL(SUM(quantity), 0) FROM move_line WHERE move_id = m.id) = m.quantity
            )
        ORDER BY i.priority DESC, i.created_at ASC
        LIMIT 1
    );
    -- Only create a supply trigger if there is no unresolved intervention for this item/zone/lot
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
    AND (NEW.quantity - NEW.reserved_quantity) > 0
    AND NOT EXISTS (
        SELECT 1 FROM intervention i
        JOIN move m ON m.id = i.move_id
        WHERE m.source_id IN (SELECT zone_id FROM location_zone WHERE location_id = NEW.location_id)
        AND m.item_id = NEW.item_id
        AND (
            m.lot_id = NEW.lot_id
            OR (m.lot_id IS NULL)
        )
        AND i.resolved = 0
    )
    AND NOT EXISTS (
        SELECT 1 FROM move m
        WHERE m.source_id IN (SELECT zone_id FROM location_zone WHERE location_id = NEW.location_id)
        AND m.item_id = NEW.item_id
        AND (
            m.lot_id = NEW.lot_id
            OR (m.lot_id IS NULL)
        )
        AND m.status IN ('waiting')
    );
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
        WHERE m.source_id IN (SELECT zone_id FROM location_zone WHERE location_id = NEW.location_id)
            AND m.item_id = NEW.item_id
            AND (
                m.lot_id = NEW.lot_id
                OR (m.lot_id IS NULL)
            )
            AND i.resolved = 0
            -- AND m.quantity <= NEW.quantity - NEW.reserved_quantity
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
        WHERE m.source_id IN (SELECT zone_id FROM location_zone WHERE location_id = NEW.location_id)
            AND m.item_id = NEW.item_id
            AND (
                m.lot_id = NEW.lot_id
                OR (m.lot_id IS NULL)
            )
            AND i.resolved = 0
            AND (SELECT IFNULL(SUM(quantity), 0) FROM move_line WHERE move_id = m.id) = m.quantity
        ORDER BY i.priority DESC, i.created_at ASC
        LIMIT 1
    );

    -- Only create a supply trigger if there is no unresolved intervention for this item/zone/lot
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
    AND (NEW.quantity - NEW.reserved_quantity) > 0
    AND NOT EXISTS (
        SELECT 1 FROM intervention i
        JOIN move m ON m.id = i.move_id
        WHERE m.source_id IN (SELECT zone_id FROM location_zone WHERE location_id = NEW.location_id)
        AND m.item_id = NEW.item_id
        AND (
            m.lot_id = NEW.lot_id
            OR (m.lot_id IS NULL)
        )
        AND i.resolved = 0

    )
    AND NOT EXISTS (
        SELECT 1 FROM move m
        WHERE m.source_id IN (SELECT zone_id FROM location_zone WHERE location_id = NEW.location_id)
        AND m.item_id = NEW.item_id
        AND (
            m.lot_id = NEW.lot_id
            OR (m.lot_id IS NULL)
        )
        AND m.status IN ('waiting')
    );
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
        WHERE m.source_id = NEW.trigger_zone_id
            AND m.item_id = NEW.trigger_item_id
            AND (m.lot_id = NEW.trigger_lot_id OR m.lot_id IS NULL)
            AND i.resolved = 0
            -- AND m.quantity <= (
            --     SELECT IFNULL(SUM(quantity - reserved_quantity), 0)
            --     FROM stock
            --     WHERE item_id = m.item_id
            --     AND location_id IN (
            --         SELECT location_id FROM location_zone WHERE zone_id = NEW.trigger_zone_id
            --     )
            --     AND (m.lot_id = NEW.trigger_lot_id OR m.lot_id IS NULL)
            -- )
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
        WHERE m.source_id = NEW.trigger_zone_id
            AND m.item_id = NEW.trigger_item_id
            AND (m.lot_id = NEW.trigger_lot_id OR m.lot_id IS NULL)
            AND i.resolved = 0
            -- AND m.quantity <= (
            --     SELECT IFNULL(SUM(quantity - reserved_quantity), 0)
            --     FROM stock
            --     WHERE item_id = m.item_id
            --     AND location_id IN (
            --         SELECT location_id FROM location_zone WHERE zone_id = NEW.trigger_zone_id
            --     )
            --     AND (m.lot_id = NEW.trigger_lot_id OR m.lot_id IS NULL)
            -- )
        ORDER BY i.priority DESC, i.created_at ASC
        LIMIT 1
    );
END;


-- Trigger: On partner creation, create a location and assign to the correct zone with proper naming
DROP TRIGGER IF EXISTS trg_partner_create_location;
CREATE TRIGGER trg_partner_create_location
AFTER INSERT ON partner
BEGIN
    INSERT INTO location (code, x, y, z, dx, dy, dz, warehouse_id, partner_id, description)
    VALUES (
        CASE
            WHEN NEW.partner_type = 'vendor' THEN 'LOC_VENDOR_' || NEW.id
            WHEN NEW.partner_type = 'customer' THEN 'LOC_CUSTOMER_' || NEW.id
            WHEN NEW.partner_type = 'employee' THEN 'LOC_EMPLOYEE_' || NEW.id
            WHEN NEW.partner_type = 'carrier' THEN 'LOC_CARRIER_' || NEW.id
            ELSE 'LOC_PARTNER_' || NEW.id
        END,
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
            WHEN NEW.partner_type = 'carrier' THEN (SELECT id FROM zone WHERE code = 'ZON11')
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
        'demand',
        pol.route_id,
        pol.item_id,
        (SELECT id FROM zone WHERE code = 'ZON01'), -- Inbound Area
        pol.quantity,
        pol.lot_id,
        'inbound'
    FROM purchase_order_line pol
    WHERE pol.purchase_order_id = NEW.id;
END;

DROP TRIGGER IF EXISTS trg_manufacturing_order_confirmed_create_component_triggers;
CREATE TRIGGER trg_manufacturing_order_confirmed_create_component_triggers
AFTER UPDATE OF status ON manufacturing_order
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
        type,
        status
    )
    SELECT
        'manufacturing_order',
        NEW.id,
        'demand',
        (SELECT id FROM route WHERE name = 'Manufacturing Supply'),
        bl.item_id,
        (SELECT id FROM zone WHERE code = 'ZON_PROD'),
        bl.quantity * NEW.quantity,
        NULL,
        'internal',
        'draft'
    FROM item i
    JOIN bom_line bl ON bl.bom_id = i.bom_id
    WHERE i.id = NEW.item_id
      AND i.bom_id IS NOT NULL;
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
    -- 1. If item has a BOM, create a manufacturing order and demand triggers for BOM components
    INSERT INTO manufacturing_order (code, partner_id, item_id, quantity, status, origin, trigger_id)
    SELECT
        'MO_' || hex(randomblob(4)),
        -- Use the partner_id from the trigger's origin
        CASE
            WHEN t.origin_model = 'sale_order' THEN (SELECT partner_id FROM sale_order WHERE id = t.origin_id)
            WHEN t.origin_model = 'transfer_order' THEN (SELECT partner_id FROM transfer_order WHERE id = t.origin_id)
            WHEN t.origin_model = 'purchase_order' THEN (SELECT partner_id FROM purchase_order WHERE id = t.origin_id)
            WHEN t.origin_model = 'return_order' THEN (SELECT partner_id FROM return_order WHERE id = t.origin_id)
            ELSE (SELECT id FROM partner WHERE name = 'Owner A' LIMIT 1) -- fallback to company/owner
        END,
        t.trigger_item_id,
        t.trigger_item_quantity,
        'draft',
        'Auto-created for ' || t.origin_model || '_id=' || t.origin_id || ' (MO, item_id=' || t.trigger_item_id || ')',
        t.id
    FROM "trigger" t
    JOIN item i ON i.id = t.trigger_item_id
    WHERE t.id = NEW.trigger_id
      AND i.bom_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM manufacturing_order mo
          WHERE mo.status = 'draft'
            AND mo.item_id = t.trigger_item_id
            AND mo.trigger_id = t.id
      );

    -- 2. If item does NOT have a BOM, fallback to purchase order logic (as before)
    INSERT INTO purchase_order (status, origin, partner_id, code)
    SELECT
        'draft',
        'Auto-created for ' || (SELECT origin_model FROM "trigger" WHERE id = NEW.trigger_id)
        || '_id=' || (SELECT origin_id FROM "trigger" WHERE id = NEW.trigger_id)
        || ' (vendor_id=' || (SELECT vendor_id FROM item WHERE id = (SELECT trigger_item_id FROM "trigger" WHERE id = NEW.trigger_id)) || ')',
        (SELECT vendor_id FROM item WHERE id = (SELECT trigger_item_id FROM "trigger" WHERE id = NEW.trigger_id)),
        'PO_AUTO_' || (SELECT vendor_id FROM item WHERE id = (SELECT trigger_item_id FROM "trigger" WHERE id = NEW.trigger_id)) || '_' || strftime('%Y%m%d%H%M%f','now')
    WHERE NOT EXISTS (
        SELECT 1 FROM purchase_order po
        WHERE po.status = 'draft'
        AND po.partner_id = (SELECT vendor_id FROM item WHERE id = (SELECT trigger_item_id FROM "trigger" WHERE id = NEW.trigger_id))
    )
    AND (SELECT bom_id FROM item WHERE id = (SELECT trigger_item_id FROM "trigger" WHERE id = NEW.trigger_id)) IS NULL;

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
      AND route_id = (SELECT trigger_route_id FROM "trigger" WHERE id = NEW.trigger_id)
      AND (SELECT bom_id FROM item WHERE id = (SELECT trigger_item_id FROM "trigger" WHERE id = NEW.trigger_id)) IS NULL;

    INSERT INTO purchase_order_line (
        purchase_order_id, item_id, lot_id, quantity, route_id, price, currency_id, cost, cost_currency_id
    )
    SELECT
        (SELECT id FROM purchase_order
         WHERE status = 'draft'
         AND partner_id = (SELECT vendor_id FROM item WHERE id = t.trigger_item_id)
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
      )
      AND i.bom_id IS NULL;
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
        AND (
            NEW.lot_id IS NULL
            OR lot_id = NEW.lot_id
        );
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
        SELECT 1 FROM stock WHERE item_id = NEW.item_id AND location_id = NEW.source_id AND (
            NEW.lot_id IS NULL
            OR lot_id = NEW.lot_id
        )
    );

    INSERT INTO stock (item_id, location_id, lot_id, quantity)
    SELECT NEW.item_id, NEW.target_id, NEW.lot_id, 0
    WHERE NOT EXISTS (
        SELECT 1 FROM stock WHERE item_id = NEW.item_id AND location_id = NEW.target_id AND (
            NEW.lot_id IS NULL
            OR lot_id = NEW.lot_id
        )
    );

    -- Subtract from source location (quantity and reserved_quantity)
    UPDATE stock
    SET quantity = quantity - NEW.done_quantity,
        reserved_quantity = reserved_quantity - NEW.done_quantity
    WHERE item_id = NEW.item_id AND location_id = NEW.source_id AND (
        NEW.lot_id IS NULL
        OR lot_id = NEW.lot_id
    );

    -- Add to target location
    UPDATE stock
    SET quantity = quantity + NEW.done_quantity
    WHERE item_id = NEW.item_id AND location_id = NEW.target_id AND (
        NEW.lot_id IS NULL
        OR lot_id = NEW.lot_id
    );


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
    AND (
        NEW.lot_id IS NULL
        OR lot_id = NEW.lot_id
    );
    -- AND trigger_id IN (
    --     SELECT id FROM trigger
    --     WHERE origin_model = (SELECT origin_model FROM trigger WHERE id = NEW.trigger_id)
    --         AND origin_id = (SELECT origin_id FROM trigger WHERE id = NEW.trigger_id)
    -- );

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
WHEN (NEW.status = 'waiting' OR NEW.status = 'confirmed') AND OLD.status != NEW.status
BEGIN
    -- Guard: Only proceed if move is not already fully fulfilled
    -- (Prevents duplicate move lines)
    -- If fulfilled, do nothing
    -- (SELECT IFNULL(SUM(done_quantity),0) FROM move_line WHERE move_id = NEW.id) < NEW.quantity

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
            -- Fallback: pick a random location with stock of the item/lot
            (SELECT tgt_lz.location_id
            FROM location_zone tgt_lz
            JOIN stock s ON s.location_id = tgt_lz.location_id AND s.item_id = NEW.item_id
            WHERE tgt_lz.zone_id = NEW.target_id
            AND (
                    (NEW.lot_id IS NULL)
                    OR (s.lot_id = NEW.lot_id)
                )
            ORDER BY RANDOM()
            LIMIT 1),
            -- Fallback: pick a random empty location
            (SELECT tgt_lz.location_id
            FROM location_zone tgt_lz
            LEFT JOIN stock s ON s.location_id = tgt_lz.location_id AND s.item_id = NEW.item_id
            WHERE tgt_lz.zone_id = NEW.target_id
            AND (
                    (NEW.lot_id IS NULL)
                    OR (s.lot_id = NEW.lot_id)
                )
            AND (s.quantity IS NULL OR s.quantity = 0)
            ORDER BY RANDOM()
            LIMIT 1),
            -- Fallback: pick any random location in the zone
            (SELECT tgt_lz.location_id
            FROM location_zone tgt_lz
            WHERE tgt_lz.zone_id = NEW.target_id
            ORDER BY RANDOM()
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
      AND (
            (NEW.lot_id IS NULL)
            OR (s.lot_id = NEW.lot_id)
        )
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
        AND t.origin_id = (SELECT origin_id FROM trigger WHERE id = NEW.trigger_id)
        AND t.origin_model = (SELECT origin_model FROM trigger WHERE id = NEW.trigger_id)
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
      AND (SELECT IFNULL(SUM(done_quantity),0) FROM move_line WHERE move_id = NEW.id) < NEW.quantity
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
        AND (
            (NEW.lot_id IS NULL)
            OR (s.lot_id = NEW.lot_id)
        )
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
            AND t.origin_id = (SELECT origin_id FROM trigger WHERE id = NEW.trigger_id)
            AND t.origin_model = (SELECT origin_model FROM trigger WHERE id = NEW.trigger_id)
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
            THEN
                CASE
                    WHEN (SELECT bom_id FROM item WHERE id = NEW.item_id) IS NOT NULL
                    THEN 'Not enough stock. Manufacturing order created and waiting for confirmation.'
                    ELSE 'Not enough stock. Purchase order created and waiting for confirmation: ' ||
                        (SELECT code FROM purchase_order
                        WHERE status = 'draft'
                        AND partner_id = (SELECT vendor_id FROM item WHERE id = NEW.item_id)
                        ORDER BY id DESC LIMIT 1)
                END
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
            AND t.origin_id = (SELECT origin_id FROM trigger WHERE id = NEW.trigger_id)
            AND t.origin_model = (SELECT origin_model FROM trigger WHERE id = NEW.trigger_id)
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
        AND (
            NEW.lot_id IS NULL
            OR lot_id = NEW.lot_id
        )
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


-- Prevent a BOM line from referencing its own parent item
DROP TRIGGER IF EXISTS trg_bom_line_no_self_reference;
CREATE TRIGGER trg_bom_line_no_self_reference
BEFORE INSERT ON bom_line
BEGIN
    SELECT
        CASE
            WHEN (SELECT id FROM item WHERE bom_id = NEW.bom_id) = NEW.item_id
            THEN RAISE(ABORT, 'A BOM line cannot reference its own parent item.')
        END;
END;

-- Also prevent on update
DROP TRIGGER IF EXISTS trg_bom_line_no_self_reference_update;
CREATE TRIGGER trg_bom_line_no_self_reference_update
BEFORE UPDATE ON bom_line
BEGIN
    SELECT
        CASE
            WHEN (SELECT id FROM item WHERE bom_id = NEW.bom_id) = NEW.item_id
            THEN RAISE(ABORT, 'A BOM line cannot reference its own parent item.')
        END;
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
('ZON10', 'Employee Area', 1),
('ZON_PROD', 'Production/Manufacturing Zone', 1),
('ZON11', 'Carrier Area', 1);


-- Locations
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


-- Add a production location (or more if needed)
('LOC_PROD_1', 0, 45, 0, 30, 7, 2, 1, NULL, 'Production Area 1');


-- stock locations
INSERT INTO location (code, x, y, z, dx, dy, dz, warehouse_id, partner_id, description) VALUES
('LOC_Q1_L1', 0.5, 0.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf Q1 Level L1'),
('LOC_Q1_L2', 0.5, 0.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf Q1 Level L2'),
('LOC_Q1_L3', 0.5, 0.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf Q1 Level L3'),
('LOC_Q1_L4', 0.5, 0.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf Q1 Level L4'),
('LOC_P1_L1', 0.5, 1.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf P1 Level L1'),
('LOC_P1_L2', 0.5, 1.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf P1 Level L2'),
('LOC_N1_L1', 0.5, 7.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf N1 Level L1'),
('LOC_N1_L2', 0.5, 7.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf N1 Level L2'),
('LOC_M1_L1', 0.5, 8.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf M1 Level L1'),
('LOC_M1_L2', 0.5, 8.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf M1 Level L2'),
('LOC_K1_L1', 0.5, 14.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf K1 Level L1'),
('LOC_K1_L2', 0.5, 14.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf K1 Level L2'),
('LOC_J1_L1', 0.5, 15.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf J1 Level L1'),
('LOC_J1_L2', 0.5, 15.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf J1 Level L2'),
('LOC_H1_L1', 0.5, 21.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf H1 Level L1'),
('LOC_H1_L2', 0.5, 21.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf H1 Level L2'),
('LOC_H1_L3', 0.5, 21.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf H1 Level L3'),
('LOC_H1_L4', 0.5, 21.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf H1 Level L4'),
('LOC_G1_L1', 0.5, 22.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf G1 Level L1'),
('LOC_G1_L2', 0.5, 22.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf G1 Level L2'),
('LOC_G1_L3', 0.5, 22.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf G1 Level L3'),
('LOC_G1_L4', 0.5, 22.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf G1 Level L4'),
('LOC_E1_L1', 0.5, 28.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf E1 Level L1'),
('LOC_E1_L2', 0.5, 28.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf E1 Level L2'),
('LOC_E1_L3', 0.5, 28.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf E1 Level L3'),
('LOC_E1_L4', 0.5, 28.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf E1 Level L4'),
('LOC_D1_L1', 0.5, 29.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf D1 Level L1'),
('LOC_D1_L2', 0.5, 29.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf D1 Level L2'),
('LOC_D1_L3', 0.5, 29.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf D1 Level L3'),
('LOC_D1_L4', 0.5, 29.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf D1 Level L4'),
('LOC_B1_L1', 0.5, 35.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf B1 Level L1'),
('LOC_B1_L2', 0.5, 35.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf B1 Level L2'),
('LOC_B1_L3', 0.5, 35.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf B1 Level L3'),
('LOC_B1_L4', 0.5, 35.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf B1 Level L4'),
('LOC_A1_L1', 0.5, 36.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf A1 Level L1'),
('LOC_A1_L2', 0.5, 36.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf A1 Level L2'),
('LOC_A1_L3', 0.5, 36.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf A1 Level L3'),
('LOC_A1_L4', 0.5, 36.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf A1 Level L4'),
('LOC_Q2_L1', 4.5, 0.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf Q2 Level L1'),
('LOC_Q2_L2', 4.5, 0.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf Q2 Level L2'),
('LOC_Q2_L3', 4.5, 0.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf Q2 Level L3'),
('LOC_Q2_L4', 4.5, 0.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf Q2 Level L4'),
('LOC_P2_L1', 4.5, 1.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf P2 Level L1'),
('LOC_P2_L2', 4.5, 1.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf P2 Level L2'),
('LOC_N2_L1', 4.5, 7.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf N2 Level L1'),
('LOC_N2_L2', 4.5, 7.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf N2 Level L2'),
('LOC_M2_L1', 4.5, 8.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf M2 Level L1'),
('LOC_M2_L2', 4.5, 8.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf M2 Level L2'),
('LOC_K2_L1', 4.5, 14.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf K2 Level L1'),
('LOC_K2_L2', 4.5, 14.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf K2 Level L2'),
('LOC_J2_L1', 4.5, 15.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf J2 Level L1'),
('LOC_J2_L2', 4.5, 15.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf J2 Level L2'),
('LOC_H2_L1', 4.5, 21.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf H2 Level L1'),
('LOC_H2_L2', 4.5, 21.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf H2 Level L2'),
('LOC_H2_L3', 4.5, 21.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf H2 Level L3'),
('LOC_H2_L4', 4.5, 21.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf H2 Level L4'),
('LOC_G2_L1', 4.5, 22.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf G2 Level L1'),
('LOC_G2_L2', 4.5, 22.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf G2 Level L2'),
('LOC_G2_L3', 4.5, 22.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf G2 Level L3'),
('LOC_G2_L4', 4.5, 22.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf G2 Level L4'),
('LOC_E2_L1', 4.5, 28.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf E2 Level L1'),
('LOC_E2_L2', 4.5, 28.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf E2 Level L2'),
('LOC_E2_L3', 4.5, 28.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf E2 Level L3'),
('LOC_E2_L4', 4.5, 28.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf E2 Level L4'),
('LOC_D2_L1', 4.5, 29.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf D2 Level L1'),
('LOC_D2_L2', 4.5, 29.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf D2 Level L2'),
('LOC_D2_L3', 4.5, 29.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf D2 Level L3'),
('LOC_D2_L4', 4.5, 29.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf D2 Level L4'),
('LOC_B2_L1', 4.5, 35.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf B2 Level L1'),
('LOC_B2_L2', 4.5, 35.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf B2 Level L2'),
('LOC_B2_L3', 4.5, 35.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf B2 Level L3'),
('LOC_B2_L4', 4.5, 35.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf B2 Level L4'),
('LOC_A2_L1', 4.5, 36.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf A2 Level L1'),
('LOC_A2_L2', 4.5, 36.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf A2 Level L2'),
('LOC_A2_L3', 4.5, 36.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf A2 Level L3'),
('LOC_A2_L4', 4.5, 36.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf A2 Level L4'),
('LOC_Q3_L1', 8.5, 0.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf Q3 Level L1'),
('LOC_Q3_L2', 8.5, 0.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf Q3 Level L2'),
('LOC_Q3_L3', 8.5, 0.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf Q3 Level L3'),
('LOC_Q3_L4', 8.5, 0.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf Q3 Level L4'),
('LOC_P3_L1', 8.5, 1.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf P3 Level L1'),
('LOC_P3_L2', 8.5, 1.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf P3 Level L2'),
('LOC_N3_L1', 8.5, 7.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf N3 Level L1'),
('LOC_N3_L2', 8.5, 7.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf N3 Level L2'),
('LOC_M3_L1', 8.5, 8.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf M3 Level L1'),
('LOC_M3_L2', 8.5, 8.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf M3 Level L2'),
('LOC_K3_L1', 8.5, 14.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf K3 Level L1'),
('LOC_K3_L2', 8.5, 14.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf K3 Level L2'),
('LOC_J3_L1', 8.5, 15.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf J3 Level L1'),
('LOC_J3_L2', 8.5, 15.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf J3 Level L2'),
('LOC_H3_L1', 8.5, 21.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf H3 Level L1'),
('LOC_H3_L2', 8.5, 21.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf H3 Level L2'),
('LOC_H3_L3', 8.5, 21.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf H3 Level L3'),
('LOC_H3_L4', 8.5, 21.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf H3 Level L4'),
('LOC_G3_L1', 8.5, 22.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf G3 Level L1'),
('LOC_G3_L2', 8.5, 22.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf G3 Level L2'),
('LOC_G3_L3', 8.5, 22.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf G3 Level L3'),
('LOC_G3_L4', 8.5, 22.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf G3 Level L4'),
('LOC_E3_L1', 8.5, 28.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf E3 Level L1'),
('LOC_E3_L2', 8.5, 28.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf E3 Level L2'),
('LOC_E3_L3', 8.5, 28.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf E3 Level L3'),
('LOC_E3_L4', 8.5, 28.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf E3 Level L4'),
('LOC_D3_L1', 8.5, 29.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf D3 Level L1'),
('LOC_D3_L2', 8.5, 29.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf D3 Level L2'),
('LOC_D3_L3', 8.5, 29.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf D3 Level L3'),
('LOC_D3_L4', 8.5, 29.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf D3 Level L4'),
('LOC_B3_L1', 8.5, 35.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf B3 Level L1'),
('LOC_B3_L2', 8.5, 35.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf B3 Level L2'),
('LOC_B3_L3', 8.5, 35.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf B3 Level L3'),
('LOC_B3_L4', 8.5, 35.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf B3 Level L4'),
('LOC_A3_L1', 8.5, 36.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf A3 Level L1'),
('LOC_A3_L2', 8.5, 36.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf A3 Level L2'),
('LOC_A3_L3', 8.5, 36.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf A3 Level L3'),
('LOC_A3_L4', 8.5, 36.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf A3 Level L4'),
('LOC_Q4_L1', 12.5, 0.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf Q4 Level L1'),
('LOC_Q4_L2', 12.5, 0.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf Q4 Level L2'),
('LOC_Q4_L3', 12.5, 0.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf Q4 Level L3'),
('LOC_Q4_L4', 12.5, 0.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf Q4 Level L4'),
('LOC_P4_L1', 12.5, 1.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf P4 Level L1'),
('LOC_P4_L2', 12.5, 1.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf P4 Level L2'),
('LOC_N4_L1', 12.5, 7.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf N4 Level L1'),
('LOC_N4_L2', 12.5, 7.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf N4 Level L2'),
('LOC_M4_L1', 12.5, 8.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf M4 Level L1'),
('LOC_M4_L2', 12.5, 8.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf M4 Level L2'),
('LOC_K4_L1', 12.5, 14.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf K4 Level L1'),
('LOC_K4_L2', 12.5, 14.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf K4 Level L2'),
('LOC_J4_L1', 12.5, 15.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf J4 Level L1'),
('LOC_J4_L2', 12.5, 15.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf J4 Level L2'),
('LOC_H4_L1', 12.5, 21.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf H4 Level L1'),
('LOC_H4_L2', 12.5, 21.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf H4 Level L2'),
('LOC_H4_L3', 12.5, 21.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf H4 Level L3'),
('LOC_H4_L4', 12.5, 21.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf H4 Level L4'),
('LOC_G4_L1', 12.5, 22.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf G4 Level L1'),
('LOC_G4_L2', 12.5, 22.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf G4 Level L2'),
('LOC_G4_L3', 12.5, 22.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf G4 Level L3'),
('LOC_G4_L4', 12.5, 22.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf G4 Level L4'),
('LOC_E4_L1', 12.5, 28.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf E4 Level L1'),
('LOC_E4_L2', 12.5, 28.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf E4 Level L2'),
('LOC_E4_L3', 12.5, 28.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf E4 Level L3'),
('LOC_E4_L4', 12.5, 28.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf E4 Level L4'),
('LOC_D4_L1', 12.5, 29.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf D4 Level L1'),
('LOC_D4_L2', 12.5, 29.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf D4 Level L2'),
('LOC_D4_L3', 12.5, 29.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf D4 Level L3'),
('LOC_D4_L4', 12.5, 29.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf D4 Level L4'),
('LOC_B4_L1', 12.5, 35.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf B4 Level L1'),
('LOC_B4_L2', 12.5, 35.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf B4 Level L2'),
('LOC_B4_L3', 12.5, 35.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf B4 Level L3'),
('LOC_B4_L4', 12.5, 35.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf B4 Level L4'),
('LOC_A4_L1', 12.5, 36.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf A4 Level L1'),
('LOC_A4_L2', 12.5, 36.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf A4 Level L2'),
('LOC_A4_L3', 12.5, 36.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf A4 Level L3'),
('LOC_A4_L4', 12.5, 36.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf A4 Level L4'),
('LOC_Q5_L1', 16.5, 0.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf Q5 Level L1'),
('LOC_Q5_L2', 16.5, 0.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf Q5 Level L2'),
('LOC_Q5_L3', 16.5, 0.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf Q5 Level L3'),
('LOC_Q5_L4', 16.5, 0.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf Q5 Level L4'),
('LOC_P5_L1', 16.5, 1.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf P5 Level L1'),
('LOC_P5_L2', 16.5, 1.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf P5 Level L2'),
('LOC_N5_L1', 16.5, 7.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf N5 Level L1'),
('LOC_N5_L2', 16.5, 7.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf N5 Level L2'),
('LOC_M5_L1', 16.5, 8.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf M5 Level L1'),
('LOC_M5_L2', 16.5, 8.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf M5 Level L2'),
('LOC_K5_L1', 16.5, 14.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf K5 Level L1'),
('LOC_K5_L2', 16.5, 14.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf K5 Level L2'),
('LOC_J5_L1', 16.5, 15.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf J5 Level L1'),
('LOC_J5_L2', 16.5, 15.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf J5 Level L2'),
('LOC_H5_L1', 16.5, 21.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf H5 Level L1'),
('LOC_H5_L2', 16.5, 21.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf H5 Level L2'),
('LOC_H5_L3', 16.5, 21.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf H5 Level L3'),
('LOC_H5_L4', 16.5, 21.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf H5 Level L4'),
('LOC_G5_L1', 16.5, 22.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf G5 Level L1'),
('LOC_G5_L2', 16.5, 22.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf G5 Level L2'),
('LOC_G5_L3', 16.5, 22.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf G5 Level L3'),
('LOC_G5_L4', 16.5, 22.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf G5 Level L4'),
('LOC_E5_L1', 16.5, 28.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf E5 Level L1'),
('LOC_E5_L2', 16.5, 28.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf E5 Level L2'),
('LOC_E5_L3', 16.5, 28.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf E5 Level L3'),
('LOC_E5_L4', 16.5, 28.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf E5 Level L4'),
('LOC_D5_L1', 16.5, 29.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf D5 Level L1'),
('LOC_D5_L2', 16.5, 29.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf D5 Level L2'),
('LOC_D5_L3', 16.5, 29.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf D5 Level L3'),
('LOC_D5_L4', 16.5, 29.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf D5 Level L4'),
('LOC_B5_L1', 16.5, 35.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf B5 Level L1'),
('LOC_B5_L2', 16.5, 35.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf B5 Level L2'),
('LOC_B5_L3', 16.5, 35.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf B5 Level L3'),
('LOC_B5_L4', 16.5, 35.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf B5 Level L4'),
('LOC_A5_L1', 16.5, 36.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf A5 Level L1'),
('LOC_A5_L2', 16.5, 36.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf A5 Level L2'),
('LOC_A5_L3', 16.5, 36.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf A5 Level L3'),
('LOC_A5_L4', 16.5, 36.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf A5 Level L4'),
('LOC_Q6_L1', 20.5, 0.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf Q6 Level L1'),
('LOC_Q6_L2', 20.5, 0.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf Q6 Level L2'),
('LOC_Q6_L3', 20.5, 0.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf Q6 Level L3'),
('LOC_Q6_L4', 20.5, 0.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf Q6 Level L4'),
('LOC_P6_L1', 20.5, 1.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf P6 Level L1'),
('LOC_P6_L2', 20.5, 1.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf P6 Level L2'),
('LOC_N6_L1', 20.5, 7.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf N6 Level L1'),
('LOC_N6_L2', 20.5, 7.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf N6 Level L2'),
('LOC_M6_L1', 20.5, 8.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf M6 Level L1'),
('LOC_M6_L2', 20.5, 8.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf M6 Level L2'),
('LOC_K6_L1', 20.5, 14.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf K6 Level L1'),
('LOC_K6_L2', 20.5, 14.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf K6 Level L2'),
('LOC_J6_L1', 20.5, 15.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf J6 Level L1'),
('LOC_J6_L2', 20.5, 15.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf J6 Level L2'),
('LOC_H6_L1', 20.5, 21.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf H6 Level L1'),
('LOC_H6_L2', 20.5, 21.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf H6 Level L2'),
('LOC_H6_L3', 20.5, 21.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf H6 Level L3'),
('LOC_H6_L4', 20.5, 21.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf H6 Level L4'),
('LOC_G6_L1', 20.5, 22.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf G6 Level L1'),
('LOC_G6_L2', 20.5, 22.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf G6 Level L2'),
('LOC_G6_L3', 20.5, 22.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf G6 Level L3'),
('LOC_G6_L4', 20.5, 22.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf G6 Level L4'),
('LOC_E6_L1', 20.5, 28.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf E6 Level L1'),
('LOC_E6_L2', 20.5, 28.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf E6 Level L2'),
('LOC_E6_L3', 20.5, 28.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf E6 Level L3'),
('LOC_E6_L4', 20.5, 28.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf E6 Level L4'),
('LOC_D6_L1', 20.5, 29.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf D6 Level L1'),
('LOC_D6_L2', 20.5, 29.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf D6 Level L2'),
('LOC_D6_L3', 20.5, 29.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf D6 Level L3'),
('LOC_D6_L4', 20.5, 29.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf D6 Level L4'),
('LOC_B6_L1', 20.5, 35.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf B6 Level L1'),
('LOC_B6_L2', 20.5, 35.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf B6 Level L2'),
('LOC_B6_L3', 20.5, 35.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf B6 Level L3'),
('LOC_B6_L4', 20.5, 35.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf B6 Level L4'),
('LOC_A6_L1', 20.5, 36.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf A6 Level L1'),
('LOC_A6_L2', 20.5, 36.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf A6 Level L2'),
('LOC_A6_L3', 20.5, 36.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf A6 Level L3'),
('LOC_A6_L4', 20.5, 36.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf A6 Level L4'),
('LOC_Q7_L1', 24.5, 0.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf Q7 Level L1'),
('LOC_Q7_L2', 24.5, 0.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf Q7 Level L2'),
('LOC_Q7_L3', 24.5, 0.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf Q7 Level L3'),
('LOC_Q7_L4', 24.5, 0.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf Q7 Level L4'),
('LOC_P7_L1', 24.5, 1.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf P7 Level L1'),
('LOC_P7_L2', 24.5, 1.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf P7 Level L2'),
('LOC_N7_L1', 24.5, 7.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf N7 Level L1'),
('LOC_N7_L2', 24.5, 7.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf N7 Level L2'),
('LOC_M7_L1', 24.5, 8.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf M7 Level L1'),
('LOC_M7_L2', 24.5, 8.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf M7 Level L2'),
('LOC_K7_L1', 24.5, 14.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf K7 Level L1'),
('LOC_K7_L2', 24.5, 14.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf K7 Level L2'),
('LOC_J7_L1', 24.5, 15.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf J7 Level L1'),
('LOC_J7_L2', 24.5, 15.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf J7 Level L2'),
('LOC_H7_L1', 24.5, 21.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf H7 Level L1'),
('LOC_H7_L2', 24.5, 21.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf H7 Level L2'),
('LOC_H7_L3', 24.5, 21.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf H7 Level L3'),
('LOC_H7_L4', 24.5, 21.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf H7 Level L4'),
('LOC_G7_L1', 24.5, 22.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf G7 Level L1'),
('LOC_G7_L2', 24.5, 22.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf G7 Level L2'),
('LOC_G7_L3', 24.5, 22.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf G7 Level L3'),
('LOC_G7_L4', 24.5, 22.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf G7 Level L4'),
('LOC_E7_L1', 24.5, 28.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf E7 Level L1'),
('LOC_E7_L2', 24.5, 28.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf E7 Level L2'),
('LOC_E7_L3', 24.5, 28.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf E7 Level L3'),
('LOC_E7_L4', 24.5, 28.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf E7 Level L4'),
('LOC_D7_L1', 24.5, 29.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf D7 Level L1'),
('LOC_D7_L2', 24.5, 29.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf D7 Level L2'),
('LOC_D7_L3', 24.5, 29.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf D7 Level L3'),
('LOC_D7_L4', 24.5, 29.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf D7 Level L4'),
('LOC_B7_L1', 24.5, 35.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf B7 Level L1'),
('LOC_B7_L2', 24.5, 35.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf B7 Level L2'),
('LOC_B7_L3', 24.5, 35.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf B7 Level L3'),
('LOC_B7_L4', 24.5, 35.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf B7 Level L4'),
('LOC_A7_L1', 24.5, 36.5, 0.0, 4, 1, 2.5, 1, NULL, 'Shelf A7 Level L1'),
('LOC_A7_L2', 24.5, 36.5, 2.5, 4, 1, 2.5, 1, NULL, 'Shelf A7 Level L2'),
('LOC_A7_L3', 24.5, 36.5, 5.0, 4, 1, 2.5, 1, NULL, 'Shelf A7 Level L3'),
('LOC_A7_L4', 24.5, 36.5, 7.5, 4, 1, 2.5, 1, NULL, 'Shelf A7 Level L4');

-- Location Zones
INSERT INTO location_zone (location_id, zone_id) VALUES
((SELECT id FROM location WHERE code = 'LOC01.1'), (SELECT id FROM zone WHERE code = 'ZON01')),
((SELECT id FROM location WHERE code = 'LOC01.2'), (SELECT id FROM zone WHERE code = 'ZON01')),
((SELECT id FROM location WHERE code = 'LOC05.1'), (SELECT id FROM zone WHERE code = 'ZON05')),
((SELECT id FROM location WHERE code = 'LOC05.2'), (SELECT id FROM zone WHERE code = 'ZON05')),
((SELECT id FROM location WHERE code = 'LOC03.1'), (SELECT id FROM zone WHERE code = 'ZON03')),
((SELECT id FROM location WHERE code = 'LOC04.1'), (SELECT id FROM zone WHERE code = 'ZON04')),
((SELECT id FROM location WHERE code = 'LOC04.2'), (SELECT id FROM zone WHERE code = 'ZON04'));

-- Assign all shelf locations to Stock Zone (ZON02)
INSERT INTO location_zone (location_id, zone_id)
SELECT id, (SELECT id FROM zone WHERE code = 'ZON02') FROM location
WHERE code GLOB 'LOC_A?_*' OR code GLOB 'LOC_B?_*' OR code GLOB 'LOC_D?_*' OR code GLOB 'LOC_E?_*' OR code GLOB 'LOC_G?_*' OR code GLOB 'LOC_H?_*' OR code GLOB 'LOC_Q?_*' OR code GLOB 'LOC_J?_*' OR code GLOB 'LOC_K?_*' OR code GLOB 'LOC_M?_*' OR code GLOB 'LOC_N?_*' OR code GLOB 'LOC_P?_*';

-- Assign A, B, E, F shelves to Hot Picking Zone (ZON07)
INSERT INTO location_zone (location_id, zone_id)
SELECT id, (SELECT id FROM zone WHERE code = 'ZON06') FROM location
WHERE code GLOB 'LOC_A?_*' OR code GLOB 'LOC_B?_*' OR code GLOB 'LOC_D?_*' OR code GLOB 'LOC_E?_*' OR code GLOB 'LOC_G?_*' OR code GLOB 'LOC_H?_*' OR code GLOB 'LOC_Q?_*';

-- Assign C, D shelves to Overstock Zone (ZON06)
INSERT INTO location_zone (location_id, zone_id)
SELECT id, (SELECT id FROM zone WHERE code = 'ZON07') FROM location
WHERE code GLOB 'LOC_J?_*' OR code GLOB 'LOC_K?_*' OR code GLOB 'LOC_M?_*' OR code GLOB 'LOC_N?_*' OR code GLOB 'LOC_P?_*';

-- Assign production locations to ZON_PROD
INSERT INTO location_zone (location_id, zone_id)
SELECT id, (SELECT id FROM zone WHERE code = 'ZON_PROD') FROM location WHERE code IN ('LOC_PROD_1');


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
    'carrier@example.com', '987654321', 'carrier'),
('Customer B', 'Customer Ave 5', 'Customer City', 'CountryX', '3000',
    'Customer Billing Ave 5', 'Customer Billing City', 'CountryX', '3001',
    'customer@example.com', '555555555', 'customer'),
('Owner A', 'Owner Rd 2', 'Owner City', 'CountryX', '1500',
    'Owner Billing Rd 2', 'Owner Billing City', 'CountryX', '1501',
    'owner@example.com', '111222333', 'employee'),
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

-- Seed a new item that is a kit/product with a BOM
INSERT INTO item (
    name, sku, barcode, size, description, route_id, vendor_id,
    cost, cost_currency_id, purchase_price, purchase_currency_id, bom_id
) VALUES (
    'Kit Alpha', 'KIT-ALPHA', 'KIT-ALPHA-BC', 'big', 'Kit consisting of Small A and Big B', NULL, NULL,
    20.00, (SELECT id FROM currency WHERE code='EUR'), NULL, (SELECT id FROM currency WHERE code='EUR'), NULL
);

-- Create a BOM for Kit Alpha
INSERT INTO bom (file, instructions) VALUES (NULL, 'Assemble 1x Small A and 2x Big B into Kit Alpha');

-- Link the BOM to Kit Alpha
UPDATE item SET bom_id = (SELECT id FROM bom WHERE instructions LIKE 'Assemble 1x Small A%') WHERE sku = 'KIT-ALPHA';

-- Add BOM lines: 1x Item Small A, 2x Item Big B
INSERT INTO bom_line (bom_id, item_id, quantity)
VALUES
((SELECT bom_id FROM item WHERE sku = 'KIT-ALPHA'), 1, 1),  -- 1x Small A (item_id=1)
((SELECT bom_id FROM item WHERE sku = 'KIT-ALPHA'), 2, 2);  -- 2x Big B (item_id=

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
((SELECT id FROM price_list WHERE name='Default EUR'), 2, 25.00),
((SELECT id FROM price_list WHERE name='Default EUR'), 3, 75.95);

-- -- Seed lots for each item
INSERT INTO lot (item_id, lot_number, origin_model, origin_id, quality_control_status, notes)
VALUES
(1, 'LOT-A-001', NULL, NULL, 'accepted', 'Seeded lot for Item Small A');


-- Stock for each vendor's item (assuming you have locations for each vendor)
INSERT INTO stock (item_id, location_id, lot_id, quantity, reserved_quantity, target_quantity)
SELECT i.id, l.id, (SELECT id FROM lot WHERE item_id=i.id), 1000, 0, 100
FROM item i
JOIN partner p ON i.vendor_id = p.id AND p.partner_type = 'vendor'
JOIN location l ON l.partner_id = p.id;


-- Routes (set active=1 for all initial routes)
INSERT INTO route (name, description, active) VALUES
('Default', 'Default route for receiving and shipping goods', 1),
('Return Route', 'Route for customer returns with quality check', 1),
('Manufacturing Output', 'Route for finished goods from production to stock', 1),
('Manufacturing Supply', 'Route for supplying components to production', 1);


-- Rules (set active=1 for all initial rules)
INSERT INTO rule (
    route_id, action, source_id, target_id, delay, active
) VALUES
((SELECT id FROM route WHERE name = 'Default'), 'pull', (SELECT id FROM zone WHERE code='ZON08'), (SELECT id FROM zone WHERE code='ZON01'), 0, 1),
((SELECT id FROM route WHERE name = 'Default'), 'push', (SELECT id FROM zone WHERE code='ZON01'), (SELECT id FROM zone WHERE code='ZON05'), 0, 1),
((SELECT id FROM route WHERE name = 'Default'), 'push', (SELECT id FROM zone WHERE code='ZON05'), (SELECT id FROM zone WHERE code='ZON06'), 0, 1),

((SELECT id FROM route WHERE name = 'Default'), 'pull', (SELECT id FROM zone WHERE code='ZON02'), (SELECT id FROM zone WHERE code='ZON_PROD'), 0, 1),

((SELECT id FROM route WHERE name = 'Default'), 'pull_or_buy', (SELECT id FROM zone WHERE code='ZON06'), (SELECT id FROM zone WHERE code='ZON07'), 0, 1),
((SELECT id FROM route WHERE name = 'Default'), 'pull', (SELECT id FROM zone WHERE code='ZON07'), (SELECT id FROM zone WHERE code='ZON03'), 0, 1),
((SELECT id FROM route WHERE name = 'Default'), 'pull', (SELECT id FROM zone WHERE code='ZON03'), (SELECT id FROM zone WHERE code='ZON04'), 0, 1),
((SELECT id FROM route WHERE name = 'Default'), 'pull', (SELECT id FROM zone WHERE code='ZON04'), (SELECT id FROM zone WHERE code='ZON09'), 0, 1);

-- Rules for the return route: Customer Area → Input → Quality → Stock
INSERT INTO rule (route_id, action, source_id, target_id, delay, active) VALUES
((SELECT id FROM route WHERE name = 'Return Route'), 'push', (SELECT id FROM zone WHERE code='ZON09'), (SELECT id FROM zone WHERE code='ZON01'), 0, 1),
((SELECT id FROM route WHERE name = 'Return Route'), 'push', (SELECT id FROM zone WHERE code='ZON01'), (SELECT id FROM zone WHERE code='ZON05'), 0, 1),
((SELECT id FROM route WHERE name = 'Return Route'), 'push', (SELECT id FROM zone WHERE code='ZON05'), (SELECT id FROM zone WHERE code='ZON02'), 0, 1);

-- RULES FOR MANUFACTURING OUTPUT (finished product leaves ZON_PROD to ZON02)
INSERT INTO rule (route_id, action, source_id, target_id, delay, active)
VALUES
((SELECT id FROM route WHERE name = 'Manufacturing Output'), 'push', (SELECT id FROM zone WHERE code = 'ZON_PROD'), (SELECT id FROM zone WHERE code = 'ZON06'), 0, 1),

-- RULES FOR MANUFACTURING SUPPLY (components flow to ZON_PROD)
((SELECT id FROM route WHERE name = 'Manufacturing Supply'), 'pull_or_buy', (SELECT id FROM zone WHERE code = 'ZON06'), (SELECT id FROM zone WHERE code = 'ZON_PROD'), 0, 1),
((SELECT id FROM route WHERE name = 'Manufacturing Supply'), 'pull', (SELECT id FROM zone WHERE code='ZON08'), (SELECT id FROM zone WHERE code='ZON01'), 0, 1),
((SELECT id FROM route WHERE name = 'Manufacturing Supply'), 'push', (SELECT id FROM zone WHERE code='ZON01'), (SELECT id FROM zone WHERE code='ZON05'), 0, 1),
((SELECT id FROM route WHERE name = 'Manufacturing Supply'), 'push', (SELECT id FROM zone WHERE code='ZON05'), (SELECT id FROM zone WHERE code='ZON06'), 0, 1);
