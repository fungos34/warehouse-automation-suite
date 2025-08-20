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

CREATE TABLE IF NOT EXISTS hs_code (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,       -- e.g. '847130'
    description TEXT NOT NULL        -- e.g. 'Portable automatic data processing machines, computers'
);

CREATE TABLE IF NOT EXISTS item_hs_country (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL,
    hs_code_id INTEGER NOT NULL,
    country_id INTEGER NOT NULL, -- Herkunftsland
    UNIQUE(item_id, country_id),
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(hs_code_id) REFERENCES hs_code(id),
    FOREIGN KEY(country_id) REFERENCES country(id)
);

CREATE TABLE IF NOT EXISTS hs_country_tax (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    hs_code_id INTEGER NOT NULL,
    country_id INTEGER NOT NULL, -- Lieferland
    tax_id INTEGER NOT NULL,     -- jede Art von Steuer
    FOREIGN KEY(hs_code_id) REFERENCES hs_code(id),
    FOREIGN KEY(country_id) REFERENCES country(id),
    FOREIGN KEY(tax_id) REFERENCES tax(id)
);

-- Currency Table
CREATE TABLE IF NOT EXISTS currency (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,         -- e.g. 'EUR', 'USD'
    symbol TEXT NOT NULL,              -- e.g. '€', '$'
    name TEXT NOT NULL,                 -- e.g. 'Euro', 'US Dollar'
    rel_to_usd REAL NOT NULL            -- e.g. 1.0
);

-- Tax Table
CREATE TABLE IF NOT EXISTS tax (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    percent REAL NOT NULL,         -- e.g. 19.0 for 19%
    description TEXT,
    label TEXT
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
    country_id INTEGER,
    FOREIGN KEY(currency_id) REFERENCES currency(id),
    FOREIGN KEY(country_id) REFERENCES country(id)
);

-- Price List Item Table
CREATE TABLE IF NOT EXISTS price_list_item (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    price_list_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,
    price REAL NOT NULL, -- net price
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
    image_url TEXT, -- Optional: URL to an image of the item
    length REAL,                -- length in cm
    width REAL,                 -- width in cm  
    height REAL,                -- height in cm
    weight REAL,                -- weight in grams
    volume REAL,                -- volume in cm³
    description TEXT,
    route_id INTEGER,
    vendor_id INTEGER,
    cost REAL,                        -- NEW: default cost (purchase/manufacture)
    cost_currency_id INTEGER,         -- NEW: currency for cost
    purchase_price REAL,              -- Optional: last purchase price
    purchase_currency_id INTEGER,     -- Optional: currency for purchase price
    bom_id INTEGER,
    is_digital INTEGER DEFAULT 0 CHECK(is_digital IN (0,1)), -- whether this item is digital
    is_sellable INTEGER DEFAULT 1 CHECK(is_sellable IN (0,1)), -- whether this item is sold
    is_assemblable INTEGER DEFAULT 0 CHECK(is_assemblable IN (0,1)),
    is_disassemblable INTEGER DEFAULT 0 CHECK(is_disassemblable IN (0,1)),
    service_window_id INTEGER,
    FOREIGN KEY(route_id) REFERENCES route(id),
    FOREIGN KEY(vendor_id) REFERENCES partner(id),
    FOREIGN KEY(cost_currency_id) REFERENCES currency(id),
    FOREIGN KEY(purchase_currency_id) REFERENCES currency(id),
    FOREIGN KEY(bom_id) REFERENCES bom(id),
    FOREIGN KEY(service_window_id) REFERENCES service_window(id)
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

-- Add this to your schema.sql
CREATE TABLE IF NOT EXISTS carrier_label (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    mo_id INTEGER NOT NULL,
    lot_id INTEGER, -- lot linking quotation line to label
    label_pdf BLOB,
    label_url TEXT,
    tracking_number TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    carrier_id INTEGER,
    sender_id INTEGER,
    recipient_id INTEGER,
    FOREIGN KEY(carrier_id) REFERENCES partner(id),
    FOREIGN KEY(sender_id) REFERENCES partner(id),
    FOREIGN KEY(recipient_id) REFERENCES partner(id),
    FOREIGN KEY(mo_id) REFERENCES manufacturing_order(id),
    FOREIGN KEY(lot_id) REFERENCES lot(id)
);

CREATE TABLE IF NOT EXISTS country (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,       -- e.g. 'DE', 'AT', 'CH', 'BA'
    name TEXT NOT NULL,              -- e.g. 'Germany', 'Austria'
    official_name TEXT,              -- e.g. 'Federal Republic of Germany'
    eu_member INTEGER NOT NULL DEFAULT 0 CHECK(eu_member IN (0,1)), -- EU flag
    currency_id INTEGER,             -- default currency of the country
    vat_standard INTEGER,               -- optional default VAT %
    region TEXT,                     -- e.g. 'Europe', 'Asia'
    phone_code TEXT,                 -- e.g. '+49', '+43'
    language_id INTEGER,
    active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1)),
    FOREIGN KEY(currency_id) REFERENCES currency(id),
    FOREIGN KEY(vat_standard) REFERENCES tax(id),
    FOREIGN KEY(language_id) REFERENCES language(id)
);

CREATE TABLE IF NOT EXISTS language (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,       -- e.g. 'en', 'de', 'fr', 'bs'
    name TEXT NOT NULL,              -- e.g. 'English', 'German'
    native_name TEXT,                -- e.g. 'Deutsch', 'English'
    rtl INTEGER NOT NULL DEFAULT 0 CHECK(rtl IN (0,1))  -- Right-to-left flag (e.g. Arabic/Hebrew)
);

-- Create partner
CREATE TABLE IF NOT EXISTS partner (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    street TEXT NOT NULL,
    city TEXT NOT NULL,
    country_id INTEGER NOT NULL,
    zip TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    notes TEXT,
    billing_name TEXT,
    billing_street TEXT,
    billing_city TEXT,
    billing_country_id INTEGER,
    billing_zip TEXT,
    billing_email TEXT,
    billing_phone TEXT,
    billing_notes TEXT,
    partner_type TEXT CHECK (partner_type IN ('vendor','customer','employee','carrier')) NOT NULL DEFAULT 'customer',
    language_id INTEGER,
    FOREIGN KEY (country_id) REFERENCES country(id),
    FOREIGN KEY (billing_country_id) REFERENCES country(id),
    FOREIGN KEY (language_id) REFERENCES language(id)
);


CREATE TABLE IF NOT EXISTS service_hours (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL,
    lot_id INTEGER,
    weekday TEXT CHECK (weekday IN ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday', '24/7')) NOT NULL,
    start_time TIME DEFAULT '00:00:00',
    end_time TIME DEFAULT '23:59:59',
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(lot_id) REFERENCES lot(id)
);

CREATE TABLE service_exception (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL,
    lot_id INTEGER,
    start_datetime DATETIME,
    end_datetime DATETIME,
    description TEXT,
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(lot_id) REFERENCES lot(id)
);

CREATE TABLE IF NOT EXISTS service_window (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timedelta INTEGER NOT NULL,          -- Duration of the service window
    unit_time TEXT CHECK (unit_time IN ('second', 'minute', 'hour', 'day', 'week', 'month', 'year')) NOT NULL,
    max_bookings INTEGER DEFAULT NULL,      -- How many bookings allowed for this window
    current_bookings INTEGER DEFAULT 0,  -- Updated as bookings are made
    notes TEXT
);

CREATE TABLE IF NOT EXISTS service_booking (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    partner_id INTEGER,         -- Customer who booked
    item_id INTEGER NOT NULL,
    lot_id INTEGER,
    service_window_id INTEGER NOT NULL,       -- The booked window
    start_datetime DATETIME DEFAULT CURRENT_TIMESTAMP,
    end_datetime DATETIME, -- Nullable: can be calculated based on service_window
    status TEXT CHECK(status IN ('pending','confirmed','cancelled','done')) DEFAULT 'pending',
    notes TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(partner_id) REFERENCES partner(id),
    FOREIGN KEY(service_window_id) REFERENCES service_window(id)
);

CREATE TABLE IF NOT EXISTS payment (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    partner_id INTEGER NOT NULL,
    origin_model TEXT CHECK(origin_model IN (
        'sale_order', 'purchase_order', 'service_booking', 'subscription', 'return_order', 'other'
    )) NOT NULL,
    origin_id INTEGER NOT NULL,
    service_booking_id INTEGER,    -- direct link to service_booking if applicable
    amount REAL NOT NULL,
    currency_id INTEGER NOT NULL,
    payment_method TEXT,           -- e.g. 'stripe', 'paypal', 'bank_transfer'
    status TEXT CHECK(status IN ('pending','completed','failed','cancelled')) DEFAULT 'pending',
    transaction_reference TEXT,    -- e.g. Stripe session ID
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(partner_id) REFERENCES partner(id),
    FOREIGN KEY(service_booking_id) REFERENCES service_booking(id),
    FOREIGN KEY(currency_id) REFERENCES currency(id)
);


-- Create company
CREATE TABLE IF NOT EXISTS company (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    vat_number TEXT,
    logo_url TEXT,
    website TEXT,
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
    image_url TEXT,
    role TEXT CHECK(role IN ('admin','manager','employee','customer')) DEFAULT 'employee',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(partner_id) REFERENCES partner(id),
    FOREIGN KEY(company_id) REFERENCES company(id)
);

DROP TABLE IF EXISTS subscription;
CREATE TABLE IF NOT EXISTS subscription (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL,
    lot_id INTEGER,
    partner_id INTEGER NOT NULL,
    service_window_id INTEGER NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    terms_conditions BLOB,     -- terms and conditions as a BLOB (e.g. PDF)
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(partner_id) REFERENCES partner(id),
    FOREIGN KEY(lot_id) REFERENCES lot(id),
    FOREIGN KEY(service_window_id) REFERENCES service_window(id)
);


CREATE TABLE IF NOT EXISTS subscription_line (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    subscription_id INTEGER NOT NULL,
    sale_order_id INTEGER,
    FOREIGN KEY(subscription_id) REFERENCES subscription(id),
    FOREIGN KEY(sale_order_id) REFERENCES sale_order(id)
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
    priority INTEGER NOT NULL DEFAULT 0, -- priority treshold for this location, only higher priority demands will autoselect this location
    FOREIGN KEY(warehouse_id) REFERENCES warehouse(id),
    FOREIGN KEY(partner_id) REFERENCES partner(id)
);

-- Create zone: abstract grouping of locations within a warehouse
CREATE TABLE IF NOT EXISTS zone (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT NOT NULL,
    description TEXT,
    route_id INTEGER,
    production_area TEXT CHECK (production_area IN ('primary', 'yes', 'no')) DEFAULT 'no',
    vendor_area TEXT CHECK (vendor_area IN ('primary', 'yes', 'no')) DEFAULT 'no',
    customer_area TEXT CHECK (customer_area IN ('primary', 'yes', 'no')) DEFAULT 'no',
    carrier_area TEXT CHECK (carrier_area IN ('primary', 'yes', 'no')) DEFAULT 'no',
    employee_area TEXT CHECK (employee_area IN ('primary', 'yes', 'no')) DEFAULT 'no',
    warehouse_area TEXT CHECK (warehouse_area IN ('primary', 'yes', 'no')) DEFAULT 'no',
    inbound_area TEXT CHECK (inbound_area IN ('primary', 'yes', 'no')) DEFAULT 'no',
    outbound_area TEXT CHECK (outbound_area IN ('primary', 'yes', 'no')) DEFAULT 'no',
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
    priority INTEGER NOT NULL DEFAULT 0,
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
    source_location_id INTEGER, -- optional: source location for this move
    target_location_id INTEGER, -- optional: target location for this move
    trigger_id INTEGER,
    picking_id INTEGER,
    quantity REAL DEFAULT 0,
    reserved_quantity REAL DEFAULT 0,
    route_id INTEGER,
    rule_id INTEGER,
    is_terminal BOOLEAN DEFAULT 0,
    priority INTEGER NOT NULL DEFAULT 0,
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
    FOREIGN KEY(rule_id) REFERENCES rule(id),
    FOREIGN KEY(source_location_id) REFERENCES location(id),
    FOREIGN KEY(target_location_id) REFERENCES location(id)
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

CREATE TABLE IF NOT EXISTS quotation (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,
    partner_id INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    status TEXT CHECK(status IN ('draft','confirmed','done','cancelled')) DEFAULT 'draft',
    currency_id INTEGER,              -- NEW: currency for this order
    tax_id INTEGER,                   -- NEW: tax for this order
    discount_id INTEGER,              -- NEW: discount for this order
    price_list_id INTEGER,            -- NEW: price list for this order

    split_parcel BOOLEAN DEFAULT 0,  -- whether partial deliveries are allowed (in-stock items can be delivered earlier)
    pick_pack BOOLEAN DEFAULT 1,     -- whether the items should be picked and packed (or self collected)
    ship BOOLEAN DEFAULT 1,          -- whether the items should be shipped (or self pick-up)
    carrier_id INTEGER,              -- carrier for this order (if shipping is enabled)

    notes TEXT,
    priority INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY(partner_id) REFERENCES partner(id),
    FOREIGN KEY(currency_id) REFERENCES currency(id),
    FOREIGN KEY(tax_id) REFERENCES tax(id),
    FOREIGN KEY(discount_id) REFERENCES discount(id),
    FOREIGN KEY(price_list_id) REFERENCES price_list(id),
    FOREIGN KEY(partner_id) REFERENCES partner(id)
);


CREATE TABLE IF NOT EXISTS quotation_line (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    quantity REAL NOT NULL,
    item_id INTEGER NOT NULL,
    lot_id INTEGER,
    quotation_id INTEGER NOT NULL,
    route_id INTEGER,
    price REAL,                       -- NEW: unit price for this line
    currency_id INTEGER,              -- NEW: currency for this line
    price_list_id INTEGER,            -- NEW: price list for this line
    cost REAL,                        -- NEW: cost for this line (manufacture/purchase)
    cost_currency_id INTEGER,         -- NEW: currency for cost
    returned_quantity REAL DEFAULT 0,
    description TEXT,
    FOREIGN KEY(quotation_id) REFERENCES quotation(id),
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(route_id) REFERENCES route(id),
    FOREIGN KEY(currency_id) REFERENCES currency(id),
    FOREIGN KEY(cost_currency_id) REFERENCES currency(id),
    FOREIGN KEY(lot_id) REFERENCES lot(id),
    FOREIGN KEY(price_list_id) REFERENCES price_list(id)
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
    quotation_id INTEGER NOT NULL,
    priority INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY(partner_id) REFERENCES partner(id),
    FOREIGN KEY(currency_id) REFERENCES currency(id),
    FOREIGN KEY(tax_id) REFERENCES tax(id),
    FOREIGN KEY(discount_id) REFERENCES discount(id),
    FOREIGN KEY(price_list_id) REFERENCES price_list(id),
    FOREIGN KEY(quotation_id) REFERENCES quotation(id)
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
    description TEXT,
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
    priority INTEGER NOT NULL DEFAULT 0,
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
    priority INTEGER NOT NULL DEFAULT 0,
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
    priority INTEGER NOT NULL DEFAULT 0,

    ship BOOLEAN DEFAULT 1, -- whether the return should be shipped back
    carrier_id INTEGER, -- carrier for this return (if shipping is enabled)

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
    manufacturing_location_id INTEGER,     -- Location where the manufacturing takes place
    manufacturing_zone_id INTEGER,
    origin TEXT,
    trigger_id INTEGER,               -- Link to the trigger that caused this MO
    priority INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(trigger_id) REFERENCES trigger(id),
    FOREIGN KEY(partner_id) REFERENCES partner(id),
    FOREIGN KEY(manufacturing_location_id) REFERENCES location(id),
    FOREIGN KEY(manufacturing_zone_id) REFERENCES zone(id),
    CHECK (planned_start IS NULL OR planned_end IS NULL OR planned_start < planned_end),
    CHECK (
        (manufacturing_zone_id IS NOT NULL AND manufacturing_location_id IS NULL)
        OR 
        (manufacturing_location_id IS NOT NULL AND manufacturing_zone_id IS NULL)
        )
);

-- Unbuild Order
CREATE TABLE IF NOT EXISTS unbuild_order (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,
    partner_id INTEGER NOT NULL,
    item_id INTEGER NOT NULL,         -- The finished product to unbuild
    lot_id INTEGER,                  -- Nullable for non-lot-tracked items
    quantity REAL NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('draft','confirmed','done','cancelled')) DEFAULT 'draft',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    planned_start DATETIME,
    planned_end DATETIME,
    unbuild_location_id INTEGER,      -- Location where the unbuilding takes place
    unbuild_zone_id INTEGER,
    origin TEXT,
    origin_model TEXT CHECK(origin_model IN ('sale_order', 'transfer_order', 'purchase_order', 'stock', 'return_order', 'manufacturing_order', 'unbuild_order')) NOT NULL,
    origin_id INTEGER,                -- ID of the originating document
    trigger_id INTEGER,               -- Link to the trigger that caused this UO
    priority INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(lot_id) REFERENCES lot(id),
    FOREIGN KEY(trigger_id) REFERENCES trigger(id),
    FOREIGN KEY(partner_id) REFERENCES partner(id),
    FOREIGN KEY(unbuild_location_id) REFERENCES location(id),
    FOREIGN KEY(unbuild_zone_id) REFERENCES zone(id),
    CHECK (planned_start IS NULL OR planned_end IS NULL OR planned_start < planned_end),
    CHECK (
        (unbuild_zone_id IS NOT NULL AND unbuild_location_id IS NULL)
        OR 
        (unbuild_location_id IS NOT NULL AND unbuild_zone_id IS NULL)
        )
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
    
    origin_model TEXT CHECK(origin_model IN ('sale_order', 'transfer_order', 'purchase_order', 'stock', 'return_order', 'manufacturing_order', 'unbuild_order')) NOT NULL,
    origin_id INTEGER,

    trigger_type TEXT NOT NULL CHECK (trigger_type IN ('demand','supply')),
    trigger_route_id INTEGER,
    trigger_item_id INTEGER NOT NULL,
    trigger_lot_id INTEGER,
    trigger_zone_id INTEGER,
    trigger_item_quantity REAL NOT NULL,
    trigger_location_id INTEGER,
    priority INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL CHECK (status IN ('draft','handled','intervene')) DEFAULT 'draft',
    type TEXT NOT NULL CHECK (type IN ('inbound','outbound','internal')),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(trigger_item_id) REFERENCES item(id),
    FOREIGN KEY(trigger_zone_id) REFERENCES zone(id),
    FOREIGN KEY(trigger_route_id) REFERENCES route(id),
    FOREIGN KEY(trigger_lot_id) REFERENCES lot(id),
    FOREIGN KEY(trigger_location_id) REFERENCES location(id),
    CHECK (
        (trigger_zone_id IS NOT NULL AND trigger_location_id IS NULL)
        OR
        (trigger_zone_id IS NULL AND trigger_location_id IS NOT NULL)
    )
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


DROP TRIGGER IF EXISTS trg_service_booking_set_end_datetime;
CREATE TRIGGER trg_service_booking_set_end_datetime
AFTER INSERT ON service_booking
BEGIN
    UPDATE service_booking
    SET end_datetime = 
        CASE
            WHEN (SELECT unit_time FROM service_window WHERE id = NEW.service_window_id) = 'second'
                THEN datetime(NEW.start_datetime, '+' || (SELECT timedelta FROM service_window WHERE id = NEW.service_window_id) || ' seconds')
            WHEN (SELECT unit_time FROM service_window WHERE id = NEW.service_window_id) = 'minute'
                THEN datetime(NEW.start_datetime, '+' || (SELECT timedelta FROM service_window WHERE id = NEW.service_window_id) || ' minutes')
            WHEN (SELECT unit_time FROM service_window WHERE id = NEW.service_window_id) = 'hour'
                THEN datetime(NEW.start_datetime, '+' || (SELECT timedelta FROM service_window WHERE id = NEW.service_window_id) || ' hours')
            WHEN (SELECT unit_time FROM service_window WHERE id = NEW.service_window_id) = 'day'
                THEN datetime(NEW.start_datetime, '+' || (SELECT timedelta FROM service_window WHERE id = NEW.service_window_id) || ' days')
            WHEN (SELECT unit_time FROM service_window WHERE id = NEW.service_window_id) = 'week'
                THEN datetime(NEW.start_datetime, '+' || ((SELECT timedelta FROM service_window WHERE id = NEW.service_window_id) * 7) || ' days')
            WHEN (SELECT unit_time FROM service_window WHERE id = NEW.service_window_id) = 'month'
                THEN datetime(NEW.start_datetime, '+' || (SELECT timedelta FROM service_window WHERE id = NEW.service_window_id) || ' months')
            WHEN (SELECT unit_time FROM service_window WHERE id = NEW.service_window_id) = 'year'
                THEN datetime(NEW.start_datetime, '+' || (SELECT timedelta FROM service_window WHERE id = NEW.service_window_id) || ' years')
            ELSE NEW.start_datetime
        END
    WHERE id = NEW.id;
END;

CREATE TRIGGER trg_service_booking_validate
BEFORE INSERT ON service_booking
BEGIN
    -- 1. Calculate the intended end_datetime
    SELECT
        CASE
            WHEN (
                SELECT COUNT(*) FROM service_window WHERE id = NEW.service_window_id
            ) = 0
            THEN RAISE(ABORT, 'Invalid service_window_id')
        END;
    -- Get the window duration in minutes for the booking
    SELECT
        CASE
            WHEN (SELECT unit_time FROM service_window WHERE id = NEW.service_window_id) = 'minute'
                THEN (SELECT timedelta FROM service_window WHERE id = NEW.service_window_id)
            WHEN (SELECT unit_time FROM service_window WHERE id = NEW.service_window_id) = 'hour'
                THEN (SELECT timedelta FROM service_window WHERE id = NEW.service_window_id) * 60
            WHEN (SELECT unit_time FROM service_window WHERE id = NEW.service_window_id) = 'day'
                THEN (SELECT timedelta FROM service_window WHERE id = NEW.service_window_id) * 1440
            WHEN (SELECT unit_time FROM service_window WHERE id = NEW.service_window_id) = 'week'
                THEN (SELECT timedelta FROM service_window WHERE id = NEW.service_window_id) * 10080
            WHEN (SELECT unit_time FROM service_window WHERE id = NEW.service_window_id) = 'month'
                THEN (SELECT timedelta FROM service_window WHERE id = NEW.service_window_id) * 43200
            WHEN (SELECT unit_time FROM service_window WHERE id = NEW.service_window_id) = 'year'
                THEN (SELECT timedelta FROM service_window WHERE id = NEW.service_window_id) * 525600
            ELSE 0
        END AS window_duration_minutes;
    -- Abort if booking overlaps with a service exception
    SELECT CASE
        WHEN EXISTS (
            SELECT 1 FROM service_exception
            WHERE item_id = NEW.item_id
              AND (lot_id IS NULL OR lot_id = NEW.lot_id)
              AND (
                  (NEW.start_datetime < end_datetime AND NEW.end_datetime > start_datetime)
              )
        )
        THEN RAISE(ABORT, 'Booking overlaps with a service exception')
    END;

    -- Abort if booking is outside allowed service hours
    -- Calculate intended end_datetime
    SELECT
        CASE
            WHEN NOT EXISTS (
                SELECT 1 FROM service_hours
                WHERE item_id = NEW.item_id
                AND (lot_id IS NULL OR lot_id = NEW.lot_id)
                AND (
                    weekday = CASE strftime('%w', NEW.start_datetime)
                        WHEN '0' THEN 'Sunday'
                        WHEN '1' THEN 'Monday'
                        WHEN '2' THEN 'Tuesday'
                        WHEN '3' THEN 'Wednesday'
                        WHEN '4' THEN 'Thursday'
                        WHEN '5' THEN 'Friday'
                        WHEN '6' THEN 'Saturday'
                    END
                    OR weekday = '24/7'
                )
                AND (
                    (start_time IS NULL OR time(NEW.start_datetime) >= start_time)
                    AND (end_time IS NULL OR time(
                        datetime(NEW.start_datetime, '+' || (SELECT timedelta FROM service_window WHERE id = NEW.service_window_id) || ' minutes')
                    ) <= end_time)
                )
            )
            THEN RAISE(ABORT, 'Booking outside allowed service hours')
        END;
END;


CREATE TABLE IF NOT EXISTS packing_policy (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    origin_model TEXT CHECK(origin_model IN ('sale_order', 'return_order', 'purchase_order', 'vendor_return')) DEFAULT NULL,
    origin_id INTEGER DEFAULT NULL,
    action INTEGER NOT NULL,                -- Reference to carton/box type (item_id)
    min_cumulative_length REAL,
    max_cumulative_length REAL,
    min_cumulative_width REAL,
    max_cumulative_width REAL,
    min_cumulative_height REAL,
    max_cumulative_height REAL,
    min_cumulative_volume REAL,
    max_cumulative_volume REAL,
    min_cumulative_weight REAL,
    max_cumulative_weight REAL,
    min_cumulative_value REAL,
    max_cumulative_value REAL,
    contains_hazardous_type TEXT CHECK(contains_hazardous_type IN ('explosive', 'flammable', 'toxic', 'corrosive', 'radioactive', 'other')),
    carrier_id INTEGER,
    shipping_method TEXT,
    recipient_id INTEGER,
    sender_id INTEGER,
    temperature_control BOOLEAN,
    fragile BOOLEAN,
    insurance_required BOOLEAN,
    priority INTEGER DEFAULT 0,
    active BOOLEAN DEFAULT 1,
    notes TEXT,
    FOREIGN KEY(action) REFERENCES item(id), -- Reference to the carton/box type
    FOREIGN KEY(carrier_id) REFERENCES partner(id),
    FOREIGN KEY(recipient_id) REFERENCES partner(id),
    FOREIGN KEY(sender_id) REFERENCES partner(id)
);


CREATE TABLE IF NOT EXISTS packing_question (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    origin_model TEXT CHECK(origin_model IN ('sale_order', 'return_order', 'purchase_order', 'vendor_return')) DEFAULT NULL,
    origin_id INTEGER DEFAULT NULL,
    cumulative_length REAL,               -- Total length of items in source document
    cumulative_width REAL,                -- Total width of items in source document
    cumulative_height REAL,               -- Total height of items in source document
    cumulative_volume REAL,               -- Total volume of items in source document
    cumulative_weight REAL,               -- Total weight of items in source document
    cumulative_value REAL,                -- Total value of items in source document
    contains_hazardous BOOLEAN, -- Whether any item is hazardous
    contains_hazardous_type TEXT CHECK(contains_hazardous_type IN ('explosive', 'flammable', 'toxic', 'corrosive', 'radioactive', 'other')),                  -- Type of hazardous material (if applicable)
    carrier_id INTEGER,         -- Preferred carrier for this parcel
    shipping_method TEXT,       -- Preferred shipping method for this parcel
    recipient_id INTEGER,                 -- Preferred recipient for this parcel
    sender_id INTEGER,                    -- Preferred sender for this parcel
    temperature_control BOOLEAN,
    fragile BOOLEAN,
    insurance_required BOOLEAN,
    answer INTEGER,                          -- Will be set by the trigger
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY(carrier_id) REFERENCES partner(id),
    FOREIGN KEY(recipient_id) REFERENCES partner(id),
    FOREIGN KEY(sender_id) REFERENCES partner(id)
);


DROP TRIGGER IF EXISTS trg_packing_answer;
CREATE TRIGGER trg_packing_answer
AFTER INSERT ON packing_question
BEGIN
    UPDATE packing_question
    SET answer = (
        SELECT action
        FROM packing_policy
        WHERE
            (origin_model IS NULL OR origin_model = packing_question.origin_model)
            AND (origin_id IS NULL OR origin_id = packing_question.origin_id)
            AND (min_cumulative_length IS NULL OR cumulative_length >= min_cumulative_length)
            AND (max_cumulative_length IS NULL OR cumulative_length <= max_cumulative_length)
            AND (min_cumulative_width IS NULL OR cumulative_width >= min_cumulative_width)
            AND (max_cumulative_width IS NULL OR cumulative_width <= max_cumulative_width)
            AND (min_cumulative_height IS NULL OR cumulative_height >= min_cumulative_height)
            AND (max_cumulative_height IS NULL OR cumulative_height <= max_cumulative_height)
            AND (min_cumulative_volume IS NULL OR cumulative_volume >= min_cumulative_volume)
            AND (max_cumulative_volume IS NULL OR cumulative_volume <= max_cumulative_volume)
            AND (min_cumulative_weight IS NULL OR cumulative_weight >= min_cumulative_weight)
            AND (max_cumulative_weight IS NULL OR cumulative_weight <= max_cumulative_weight)
            AND (min_cumulative_value IS NULL OR cumulative_value >= min_cumulative_value)
            AND (max_cumulative_value IS NULL OR cumulative_value <= max_cumulative_value)
            AND (contains_hazardous_type IS NULL OR contains_hazardous_type = packing_question.contains_hazardous_type)
            AND (carrier_id IS NULL OR carrier_id = packing_question.carrier_id)
            AND (shipping_method IS NULL OR shipping_method = packing_question.shipping_method)
            AND (recipient_id IS NULL OR recipient_id = packing_question.recipient_id)
            AND (sender_id IS NULL OR sender_id = packing_question.sender_id)
            AND (temperature_control IS NULL OR temperature_control = packing_question.temperature_control)
            AND (fragile IS NULL OR fragile = fragile)
            AND (insurance_required IS NULL OR insurance_required = insurance_required)
            AND active = 1
        ORDER BY priority DESC, id DESC
        LIMIT 1
    )
    WHERE id = NEW.id;
END;


CREATE TABLE IF NOT EXISTS dropshipping_policy (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER DEFAULT NULL,                       -- NULL = applies to all items
    vendor_id INTEGER DEFAULT NULL,                     -- NULL = applies to all vendors
    customer_id INTEGER DEFAULT NULL,                   -- NULL = applies to all customers
    carrier_id INTEGER DEFAULT NULL,                    -- NULL = applies to all carriers
    vendor_accepts_dropship BOOLEAN DEFAULT NULL,       -- Vendor preference
    ordered_quantity_below REAL DEFAULT NULL,           -- NULL = no minimum
    ordered_quantity_above REAL DEFAULT NULL,           -- NULL = no maximum
    warehouse_stock_threshold REAL DEFAULT NULL,        -- If warehouse stock below this, prefer dropship
    vendor_stock_threshold REAL DEFAULT NULL,           -- If vendor stock above this, prefer dropship
    vendor_shipping_cost_lower BOOLEAN DEFAULT NULL,    -- If true, prefer dropship
    action TEXT CHECK(action IN ('dropship','warehouse','auto')) NOT NULL DEFAULT 'auto',
    priority INTEGER DEFAULT 0,                         -- Higher = higher priority
    active BOOLEAN DEFAULT 1,
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(vendor_id) REFERENCES partner(id),
    FOREIGN KEY(customer_id) REFERENCES partner(id),
    FOREIGN KEY(carrier_id) REFERENCES partner(id)
);

CREATE TABLE IF NOT EXISTS dropshipping_question (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER,
    vendor_id INTEGER,
    customer_id INTEGER,
    carrier_id INTEGER,
    ordered_quantity REAL NOT NULL,
    vendor_accepts_dropship BOOLEAN,
    warehouse_stock REAL,
    vendor_stock REAL,
    shipping_cost_vendor_customer REAL,
    shipping_cost_warehouse_customer REAL,
    answer TEXT, -- Will be set by the trigger
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(item_id) REFERENCES item(id),
    FOREIGN KEY(vendor_id) REFERENCES partner(id),
    FOREIGN KEY(customer_id) REFERENCES partner(id),
    FOREIGN KEY(carrier_id) REFERENCES partner(id)
);

DROP TRIGGER IF EXISTS trg_dropshipping_answer;
CREATE TRIGGER trg_dropshipping_answer
AFTER INSERT ON dropshipping_question
BEGIN
    UPDATE dropshipping_question
    SET answer = (
        SELECT action
        FROM dropshipping_policy
        WHERE
            (item_id IS NULL OR item_id = NEW.item_id)
            AND (vendor_id IS NULL OR vendor_id = NEW.vendor_id)
            AND (customer_id IS NULL OR customer_id = NEW.customer_id)
            AND (carrier_id IS NULL OR carrier_id = NEW.carrier_id)
            AND (ordered_quantity_below IS NULL OR NEW.ordered_quantity < ordered_quantity_below)
            AND (ordered_quantity_above IS NULL OR NEW.ordered_quantity > ordered_quantity_above)
            AND (vendor_accepts_dropship IS NULL OR vendor_accepts_dropship = NEW.vendor_accepts_dropship)
            AND (warehouse_stock_threshold IS NULL OR NEW.warehouse_stock <= warehouse_stock_threshold)
            AND (vendor_stock_threshold IS NULL OR NEW.vendor_stock >= vendor_stock_threshold)
            -- Remove or add shipping cost logic here if you add a column for it
            AND (vendor_shipping_cost_lower IS NULL OR vendor_shipping_cost_lower = shipping_cost_vendor_customer < shipping_cost_warehouse_customer)
            AND active = 1
        ORDER BY priority DESC, id DESC
        LIMIT 1
    )
    WHERE id = NEW.id;
END;

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
        status,
        priority
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
        'draft',
        COALESCE(
            (SELECT priority FROM trigger WHERE origin_model='return_order' AND origin_id=NEW.return_order_id ORDER BY id DESC LIMIT 1),
            0
        )
    FROM return_order ro
    WHERE ro.id = NEW.return_order_id AND ro.ship = 0 AND NEW.quantity > 0;
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
        NEW.manufacturing_location_id,
        bl.lot_id,
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
        NEW.manufacturing_location_id,
        (SELECT id FROM lot WHERE origin_model = 'manufacturing_order' AND origin_id = NEW.id ORDER BY id DESC LIMIT 1),
        NEW.quantity,
        'Produced by MO ' || NEW.code,
        (SELECT id FROM route WHERE name = 'Manufacturing Output')
    );
END;

DROP TRIGGER IF EXISTS trg_unbuild_order_done_consume_and_produce;
CREATE TRIGGER trg_unbuild_order_done_consume_and_produce
AFTER UPDATE OF status ON unbuild_order
WHEN NEW.status = 'done' AND OLD.status != 'done'
BEGIN
    -- 1. Consume the finished product (parcel) at the unbuild location
    INSERT INTO stock_adjustment (item_id, location_id, lot_id, delta, reason)
    VALUES (
        NEW.item_id,
        NEW.unbuild_location_id,
        NEW.lot_id,
        -1 * NEW.quantity,
        'Unbuilt by UO ' || NEW.code
    );

    -- 2. For each BOM line, produce the component at the unbuild location
    INSERT INTO stock_adjustment (item_id, location_id, lot_id, delta, reason)
    SELECT
        bl.item_id,
        NEW.unbuild_location_id,
        bl.lot_id,
        bl.quantity * NEW.quantity,
        'Unbuilt by UO ' || NEW.code
    FROM bom_line bl
    JOIN item i ON i.bom_id = bl.bom_id
    WHERE i.id = NEW.item_id;
END;


DROP TRIGGER IF EXISTS trg_return_order_confirmed_create_unbuild_or_trigger;
CREATE TRIGGER trg_return_order_confirmed_create_unbuild_or_trigger
AFTER UPDATE OF status ON return_order
WHEN NEW.status = 'confirmed' AND OLD.status != 'confirmed'
BEGIN
    -- If ship=1, create a parcel item (return parcel), BOM, BOM lines, and unbuild order at input zone
    INSERT INTO item (name, sku, barcode, description, is_sellable, is_assemblable, is_disassemblable, is_digital)
    SELECT
        'Return Parcel ' || NEW.code,
        'PKG-' || NEW.code,
        'PKG-' || NEW.code,
        'Auto-generated return parcel for RO ' || NEW.code,
        0, 1, 1, 0
    WHERE NEW.ship = 1;

    -- Create BOM for the parcel item
    INSERT INTO bom (instructions)
    SELECT 'Auto-generated BOM for return parcel ' || NEW.code
    WHERE NEW.ship = 1;

    -- Link BOM to parcel item
    UPDATE item
    SET bom_id = (SELECT id FROM bom WHERE instructions = 'Auto-generated BOM for return parcel ' || NEW.code)
    WHERE sku = 'PKG-' || NEW.code;

    -- Add BOM lines for each valid return line (exclude digital and non-sellable items)
    INSERT INTO bom_line (bom_id, item_id, lot_id, quantity)
    SELECT
        (SELECT bom_id FROM item WHERE sku = 'PKG-' || NEW.code),
        rl.item_id,
        rl.lot_id,
        rl.quantity
    FROM return_line rl
    JOIN item i ON i.id = rl.item_id
    WHERE rl.return_order_id = NEW.id
      AND i.is_digital = 0
      AND i.is_sellable = 1
      AND NEW.ship = 1;

    -- Create unbuild order at input zone and confirm it
    INSERT INTO unbuild_order (
        code, partner_id, item_id, quantity, status, unbuild_location_id, origin, origin_model, origin_id, trigger_id, priority
    )
    SELECT
        'UO_' || NEW.code,
        NEW.partner_id,
        (SELECT id FROM item WHERE sku = 'PKG-' || NEW.code),
        1,
        'draft',
        (SELECT l.id FROM location l JOIN location_zone lz ON l.id = lz.location_id JOIN zone z ON lz.zone_id = z.id WHERE z.code = 'ZON01' LIMIT 1),
        'Auto-created for RO ' || NEW.code,
        'return_order',
        NEW.id,
        NULL,
        NEW.priority
    WHERE NEW.ship = 1;

    -- Immediately confirm the unbuild order
    UPDATE unbuild_order
    SET status = 'confirmed'
    WHERE code = 'UO_' || NEW.code
      AND status = 'draft'
      AND origin = 'Auto-created for RO ' || NEW.code;

    -- If ship=0, only create a demand trigger at the input zone for each return line
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
        status,
        priority
    )
    SELECT
        'return_order',
        NEW.id,
        'demand',
        (SELECT id FROM route WHERE name = 'Return Route'),
        rl.item_id,
        (SELECT id FROM zone WHERE code = 'ZON01'), -- Input Zone
        rl.quantity,
        rl.lot_id,
        'inbound',
        'draft',
        NEW.priority
    FROM return_line rl
    WHERE rl.return_order_id = NEW.id
      AND NEW.ship = 0;
END;


-- Update returned_quantity on order_line when a return_order is confirmed
DROP TRIGGER IF EXISTS trg_return_order_done_update_returned_quantity;
CREATE TRIGGER trg_return_order_done_update_returned_quantity
AFTER UPDATE OF status ON return_order
WHEN NEW.status = 'done' AND OLD.status != 'done' AND NEW.origin_model = 'sale_order'
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
DROP TRIGGER IF EXISTS trg_return_order_done_update_returned_quantity;
CREATE TRIGGER trg_return_order_done_update_returned_quantity
AFTER UPDATE OF status ON return_order
WHEN NEW.status = 'done' AND OLD.status != 'done' AND NEW.origin_model = 'purchase_order'
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
        type,
        priority
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
        'internal',
        COALESCE(
            (SELECT priority FROM trigger WHERE origin_model='transfer_order' AND origin_id=NEW.id ORDER BY id DESC LIMIT 1),
            0
        )
    FROM transfer_order_line tol
    WHERE tol.transfer_order_id = NEW.id;
END;


DROP TRIGGER IF EXISTS trg_sale_order_confirmed_create_packing_question;
CREATE TRIGGER trg_sale_order_confirmed_create_packing_question
AFTER UPDATE OF status ON sale_order
WHEN NEW.status = 'confirmed' AND OLD.status != 'confirmed'
BEGIN
    -- Only if shipping is enabled in the linked quotation
    INSERT INTO packing_question (
        origin_model,
        origin_id,
        cumulative_length,
        cumulative_width,
        cumulative_height,
        cumulative_volume,
        cumulative_weight,
        cumulative_value,
        contains_hazardous,
        contains_hazardous_type,
        carrier_id,
        shipping_method,
        recipient_id,
        sender_id,
        temperature_control,
        fragile,
        insurance_required
    )
    SELECT
        'sale_order',
        NEW.id,
        SUM(i.length * ol.quantity),    -- cumulative_length
        SUM(i.width * ol.quantity),     -- cumulative_width
        SUM(i.height * ol.quantity),    -- cumulative_height
        SUM(i.volume * ol.quantity),    -- cumulative_volume
        SUM(i.weight * ol.quantity),    -- cumulative_weight
        SUM(ol.price * ol.quantity),    -- cumulative_value
        0,                             -- contains_hazardous (set to 0 or aggregate if needed)
        NULL,                          -- contains_hazardous_type (set to NULL or aggregate if needed)
        q.carrier_id,                  -- carrier_id
        q.pick_pack,                   -- shipping_method
        q.partner_id,                  -- recipient_id
        NULL,                          -- sender_id (set to NULL or fill as needed)
        0,                             -- temperature_control
        0,                             -- fragile
        0                              -- insurance_required
    FROM order_line ol
    JOIN item i ON i.id = ol.item_id
    JOIN quotation q ON q.id = NEW.quotation_id
    WHERE ol.order_id = NEW.id AND q.ship = 1;

    -- Only create demand triggers for each order line if ship=0 in the linked quotation
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
        priority
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
        'outbound',
        COALESCE(
            (SELECT priority FROM trigger WHERE origin_model='sale_order' AND origin_id=NEW.id ORDER BY id DESC LIMIT 1),
            0
        )
    FROM order_line ol
    JOIN quotation q ON q.id = NEW.quotation_id
    WHERE ol.order_id = NEW.id AND q.ship = 0;

END;



DROP TRIGGER IF EXISTS trg_packing_answer_create_parcel_item;
CREATE TRIGGER trg_packing_answer_create_parcel_item
AFTER UPDATE OF answer ON packing_question
WHEN NEW.answer IS NOT NULL
AND EXISTS (
    SELECT 1 FROM item
    WHERE id = NEW.answer
    AND name IS NOT NULL
    AND length IS NOT NULL
    AND width IS NOT NULL
    AND height IS NOT NULL
    AND volume IS NOT NULL
    AND weight IS NOT NULL
)
BEGIN
    -- Debug log: record the answer value before evaluating the item
    INSERT INTO debug_log (event, info, created_at)
    VALUES (
        'trg_packing_answer_create_parcel_item',
        'Evaluating trigger for packing_question.id=' || NEW.id || ', answer=' || NEW.answer,
        CURRENT_TIMESTAMP
    );

    -- Create parcel item for any origin_model
    INSERT INTO item (
        name, sku, barcode, description, is_sellable, is_assemblable, is_disassemblable, is_digital,
        length, width, height, volume, weight
    )
    SELECT
        'Parcel ' || NEW.origin_model || '-' || NEW.origin_id,
        'PKG-' || NEW.origin_model || '-' || NEW.origin_id,
        'PKG-' || NEW.origin_model || '-' || NEW.origin_id,
        'Auto-generated parcel for ' || NEW.origin_model || ' ' || NEW.origin_id,
        0, 1, 1, 0,
        carton.length,
        carton.width,
        carton.height,
        carton.volume,
        carton.weight + (
            SELECT IFNULL(SUM(i.weight * l.quantity), 0)
            FROM (
                SELECT item_id, quantity FROM order_line WHERE order_id = NEW.origin_id AND NEW.origin_model = 'sale_order'
                UNION ALL
                SELECT item_id, quantity FROM return_line WHERE return_order_id = NEW.origin_id AND NEW.origin_model = 'return_order'
                UNION ALL
                SELECT item_id, quantity FROM purchase_order_line WHERE purchase_order_id = NEW.origin_id AND NEW.origin_model = 'purchase_order'
                -- Add vendor_return_line when you implement vendor returns
            ) l
            JOIN item i ON i.id = l.item_id
            WHERE i.is_digital = 0
        )
    FROM item carton
    WHERE carton.id = NEW.answer AND carton.name IS NOT NULL;

    -- Create BOM for the parcel item
    INSERT INTO bom (instructions)
    SELECT 'Auto-generated BOM for parcel ' || NEW.origin_model || '-' || NEW.origin_id
    WHERE EXISTS (SELECT 1 FROM item WHERE sku = 'PKG-' || NEW.origin_model || '-' || NEW.origin_id);

    -- Link BOM to parcel item
    UPDATE item
    SET bom_id = (SELECT id FROM bom WHERE instructions = 'Auto-generated BOM for parcel ' || NEW.origin_model || '-' || NEW.origin_id)
    WHERE sku = 'PKG-' || NEW.origin_model || '-' || NEW.origin_id;

    -- Add BOM lines for each relevant line
    INSERT INTO bom_line (bom_id, item_id, quantity)
    SELECT
        (SELECT bom_id FROM item WHERE sku = 'PKG-' || NEW.origin_model || '-' || NEW.origin_id),
        l.item_id,
        l.quantity
    FROM (
        SELECT item_id, quantity FROM order_line WHERE order_id = NEW.origin_id AND NEW.origin_model = 'sale_order'
        UNION ALL
        SELECT item_id, quantity FROM return_line WHERE return_order_id = NEW.origin_id AND NEW.origin_model = 'return_order'
        UNION ALL
        SELECT item_id, quantity FROM purchase_order_line WHERE purchase_order_id = NEW.origin_id AND NEW.origin_model = 'purchase_order'
        -- Add vendor_return_line when you implement vendor returns
    ) l
    JOIN item i ON i.id = l.item_id
    WHERE i.is_digital = 0
      AND EXISTS (SELECT 1 FROM item WHERE sku = 'PKG-' || NEW.origin_model || '-' || NEW.origin_id);

    -- Add BOM line for the carton itself
    INSERT INTO bom_line (bom_id, item_id, quantity)
    SELECT
        (SELECT bom_id FROM item WHERE sku = 'PKG-' || NEW.origin_model || '-' || NEW.origin_id),
        NEW.answer,
        1
    WHERE EXISTS (SELECT 1 FROM item WHERE sku = 'PKG-' || NEW.origin_model || '-' || NEW.origin_id);
END;


DROP TRIGGER IF EXISTS trg_create_unbuild_order_on_parcel_item;
CREATE TRIGGER trg_create_unbuild_order_on_parcel_item
AFTER INSERT ON item
WHEN NEW.sku LIKE 'PKG-%-%'
BEGIN
    -- Debug log: record parsed origin_model, origin_id, and item id
    INSERT INTO debug_log (event, info, created_at)
    SELECT
        'trg_create_unbuild_order_on_parcel_item',
        'Parsed origin_model=' || substr(NEW.sku, 5, instr(substr(NEW.sku, 5), '-')-1) ||
        ', origin_id=' || CAST(substr(NEW.sku, 5 + length(substr(NEW.sku, 5, instr(substr(NEW.sku, 5), '-')-1)) + 1) AS INTEGER) ||
        ', item_id=' || NEW.id,
        CURRENT_TIMESTAMP;

    -- Parse origin_model and origin_id from SKU
    INSERT INTO unbuild_order (
        code, partner_id, item_id, quantity, status, unbuild_location_id, origin, origin_model, origin_id, trigger_id, priority
    )
    SELECT
        'UO_' || NEW.sku,
        CASE
            WHEN parsed.origin_model = 'sale_order' THEN (SELECT partner_id FROM sale_order WHERE id = parsed.origin_id)
            WHEN parsed.origin_model = 'return_order' THEN (SELECT partner_id FROM return_order WHERE id = parsed.origin_id)
            WHEN parsed.origin_model = 'purchase_order' THEN (SELECT partner_id FROM purchase_order WHERE id = parsed.origin_id)
            ELSE NULL
        END,
        NEW.id,
        1,
        'draft',
        (SELECT l.id FROM location l WHERE l.partner_id = (
            CASE
                WHEN parsed.origin_model = 'sale_order' THEN (SELECT partner_id FROM sale_order WHERE id = parsed.origin_id)
                WHEN parsed.origin_model = 'return_order' THEN (SELECT partner_id FROM return_order WHERE id = parsed.origin_id)
                WHEN parsed.origin_model = 'purchase_order' THEN (SELECT partner_id FROM purchase_order WHERE id = parsed.origin_id)
                ELSE NULL
            END
        ) LIMIT 1),
        'Auto-created for ' || parsed.origin_model || ' ' || parsed.origin_id,
        parsed.origin_model,
        parsed.origin_id,
        NULL,
        CASE
            WHEN parsed.origin_model = 'sale_order' THEN (SELECT priority FROM sale_order WHERE id = parsed.origin_id)
            WHEN parsed.origin_model = 'return_order' THEN (SELECT priority FROM return_order WHERE id = parsed.origin_id)
            WHEN parsed.origin_model = 'purchase_order' THEN (SELECT priority FROM purchase_order WHERE id = parsed.origin_id)
            ELSE 0
        END
    FROM (
        SELECT
            substr(NEW.sku, 5, instr(substr(NEW.sku, 5), '-')-1) AS origin_model,
            CAST(substr(NEW.sku, 5 + length(substr(NEW.sku, 5, instr(substr(NEW.sku, 5), '-')-1)) + 1) AS INTEGER) AS origin_id
    ) AS parsed
    WHERE parsed.origin_model IS NOT NULL AND parsed.origin_id IS NOT NULL
        AND EXISTS (
        SELECT 1 FROM packing_question
        WHERE origin_model = parsed.origin_model
          AND origin_id = parsed.origin_id
    );

    -- Debug log: record parsed origin_model, origin_id, and item id
    INSERT INTO debug_log (event, info, created_at)
    SELECT
        'trg_create_unbuild_order_on_parcel_item',
        'Parsed origin_model=' || substr(NEW.sku, 5, instr(substr(NEW.sku, 5), '-')-1) ||
        ', origin_id=' || CAST(substr(NEW.sku, 5 + length(substr(NEW.sku, 5, instr(substr(NEW.sku, 5), '-')-1)) + 1) AS INTEGER) ||
        ', item_id=' || NEW.id,
        CURRENT_TIMESTAMP;
END;

-- DROP TRIGGER IF EXISTS trg_auto_confirm_unbuild_order;
CREATE TRIGGER trg_auto_confirm_unbuild_order
AFTER INSERT ON unbuild_order
WHEN NEW.status = 'draft'
BEGIN
    UPDATE unbuild_order
    SET status = 'confirmed'
    WHERE id = NEW.id AND status = 'draft';
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
        type,
        priority
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
        'inbound',
        COALESCE(
            (SELECT priority FROM trigger WHERE origin_model='purchase_order' AND origin_id=NEW.id ORDER BY id DESC LIMIT 1),
            0
        )
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
        trigger_location_id,
        trigger_item_quantity,
        trigger_lot_id,
        type,
        status,
        priority
    )
    SELECT
        'manufacturing_order',
        NEW.id,
        'demand',
        COALESCE(
            (SELECT id FROM route WHERE name = 'Manufacturing Supply'
            AND EXISTS (
                SELECT 1
                FROM location_zone lz
                JOIN zone z ON lz.zone_id = z.id
                WHERE lz.location_id = NEW.manufacturing_location_id
                AND z.production_area = 'primary'
            )
            LIMIT 1
            ),
            (SELECT id FROM route WHERE name = 'Packing Supply'
            AND EXISTS (
                SELECT 1
                FROM location_zone lz
                JOIN zone z ON lz.zone_id = z.id
                WHERE lz.location_id = NEW.manufacturing_location_id
                AND z.production_area = 'yes'
            )
            LIMIT 1
            ),
            (SELECT id FROM route WHERE name = 'Default' LIMIT 1)
        ),
        bl.item_id,
        NEW.manufacturing_location_id,
        bl.quantity * NEW.quantity,
        NULL,
        'internal',
        'draft',
        COALESCE(
            (SELECT priority FROM trigger WHERE origin_model='manufacturing_order' AND origin_id=NEW.id ORDER BY id DESC LIMIT 1),
            0
        )
    FROM item i
    JOIN bom_line bl ON bl.bom_id = i.bom_id
    WHERE i.id = NEW.item_id
      AND i.bom_id IS NOT NULL;
END;


DROP TRIGGER IF EXISTS trg_unbuild_order_confirm_create_demand_triggers;
CREATE TRIGGER trg_unbuild_order_confirm_create_demand_triggers
AFTER UPDATE OF status ON unbuild_order
WHEN NEW.status = 'confirmed' AND OLD.status != 'confirmed'
BEGIN
    -- Log for debugging
    INSERT INTO debug_log (event, info)
    VALUES (
        'trg_unbuild_order_confirm_create_demand_triggers',
        'Fired for UO ' || NEW.code ||
        ', status=' || NEW.status ||
        ', item_id=' || NEW.item_id ||
        ', unbuild_location_id=' || NEW.unbuild_location_id ||
        ', trigger_route_id=' || COALESCE(
            (SELECT id FROM route WHERE name = 'Unbuilding Supply'
                AND EXISTS (
                    SELECT 1
                    FROM location_zone lz
                    JOIN zone z ON lz.zone_id = z.id
                    WHERE lz.location_id = NEW.unbuild_location_id
                    AND z.production_area = 'primary'
                )
                LIMIT 1
            ),
            (SELECT id FROM route WHERE name = 'Unpacking Supply'
                AND EXISTS (
                    SELECT 1
                    FROM location_zone lz
                    JOIN zone z ON lz.zone_id = z.id
                    WHERE lz.location_id = NEW.unbuild_location_id
                    AND z.production_area = 'yes'
                )
                LIMIT 1
            ),
            (SELECT id FROM route WHERE name = 'Default' LIMIT 1)
        )
    );

    -- Only create a demand trigger for the unbuild_order.item_id
    INSERT INTO trigger (
        origin_model,
        origin_id,
        trigger_type,
        trigger_route_id,
        trigger_item_id,
        trigger_location_id,
        trigger_item_quantity,
        trigger_lot_id,
        type,
        status,
        priority
    )
    VALUES (
        'unbuild_order',
        NEW.id,
        'demand',
        COALESCE(
            (SELECT id FROM route WHERE name = 'Unbuilding Supply'
                AND EXISTS (
                    SELECT 1
                    FROM location_zone lz
                    JOIN zone z ON lz.zone_id = z.id
                    WHERE lz.location_id = NEW.unbuild_location_id
                    AND z.production_area = 'primary'
                )
                LIMIT 1
            ),
            (SELECT id FROM route WHERE name = 'Unpacking Supply'
                AND EXISTS (
                    SELECT 1
                    FROM location_zone lz
                    JOIN zone z ON lz.zone_id = z.id
                    WHERE lz.location_id = NEW.unbuild_location_id
                    AND z.production_area = 'yes'
                )
                LIMIT 1
            ),
            (SELECT id FROM route WHERE name = 'Default' LIMIT 1)
        ),
        NEW.item_id,
        NEW.unbuild_location_id,
        NEW.quantity,
        NEW.lot_id,
        CASE
            WHEN (SELECT COUNT(*) FROM location_zone lz JOIN zone z ON lz.zone_id = z.id WHERE lz.location_id = NEW.unbuild_location_id AND z.code = 'ZON09') > 0 THEN 'outbound'
            WHEN (SELECT COUNT(*) FROM location_zone lz JOIN zone z ON lz.zone_id = z.id WHERE lz.location_id = NEW.unbuild_location_id AND z.code = 'ZON08') > 0 THEN 'inbound'
            WHEN (SELECT COUNT(*) FROM location_zone lz JOIN zone z ON lz.zone_id = z.id WHERE lz.location_id = NEW.unbuild_location_id AND (z.warehouse_area = 'yes' OR z.warehouse_area = 'primary')) > 0 THEN 'internal'
            ELSE 'internal'
        END,
        'draft',
        NEW.priority
    );
END;


DROP TRIGGER IF EXISTS trg_quotation_confirmed_create_sale_order_and_lines;
CREATE TRIGGER trg_quotation_confirmed_create_sale_order_and_lines
AFTER UPDATE OF status ON quotation
WHEN NEW.status = 'confirmed' AND OLD.status != 'confirmed'
BEGIN

    -- Log for debugging
    INSERT INTO debug_log (event, info)
    VALUES (
        'trg_quotation_confirmed_create_sale_order_and_lines',
        'Fired for quotation ' || NEW.code ||
        ', status=' || NEW.status ||
        ', partner_id=' || NEW.partner_id
    );
    INSERT INTO debug_log (event, info) VALUES ('TRIGGER_FIRED', 'trg_quotation_confirmed_create_sale_order_and_lines fired for quotation ' || NEW.id || ', code=' || NEW.code);

    -- 1. Create sale order
    INSERT INTO sale_order (
        code,
        partner_id,
        created_at,
        status,
        currency_id,
        tax_id,
        discount_id,
        price_list_id,
        quotation_id,
        priority
    ) VALUES (
        'SO-' || NEW.code,
        NEW.partner_id,
        CURRENT_TIMESTAMP,
        'draft',
        NEW.currency_id,
        NEW.tax_id,
        NEW.discount_id,
        NEW.price_list_id,
        NEW.id,
        NEW.priority
    );

    -- 2. Copy all quotation lines to order lines
    INSERT INTO order_line (
        quantity,
        item_id,
        lot_id,
        order_id,
        route_id,
        price,
        currency_id,
        price_list_id,
        cost,
        cost_currency_id,
        description
    )
    SELECT
        ql.quantity,
        ql.item_id,
        ql.lot_id,
        (SELECT id FROM sale_order WHERE code = 'SO-' || NEW.code),
        ql.route_id,
        ql.price,
        ql.currency_id,
        ql.price_list_id,
        ql.cost,
        ql.cost_currency_id,
        ql.description
    FROM quotation_line ql
    WHERE ql.quotation_id = NEW.id;
END;


-- Trigger: On trigger creation, evaluate and link applicable rules or set to intervene
DROP TRIGGER IF EXISTS trg_trigger_evaluate_rules;
CREATE TRIGGER trg_trigger_evaluate_rules
AFTER INSERT ON trigger
BEGIN
    -- Log for debugging: show all relevant context for this unbuild_order confirmation
    INSERT INTO debug_log (event, info)
    VALUES (
        'trg_trigger_evaluate_rules',
        ', status=' || COALESCE(NEW.status, 'NULL') ||
        ', trigger_item_id=' || COALESCE(NEW.trigger_item_id, 'NULL') ||
        ', trigger_lot_id=' || COALESCE(NEW.trigger_lot_id, 'NULL') ||
        ', trigger_item_quantity=' || NEW.trigger_item_quantity ||
        ', trigger_location_id=' || COALESCE(NEW.trigger_location_id, 'NULL')
    );

    -- 1. If trigger_zone_id is set, use as before
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
      )
      AND NEW.trigger_zone_id IS NOT NULL;

    -- 2. If trigger_location_id is set, evaluate for all zones of this location
    INSERT INTO rule_trigger (rule_id, trigger_id)
    SELECT r.id, NEW.id
    FROM rule r
    JOIN location_zone lz ON lz.location_id = NEW.trigger_location_id
    WHERE r.active = 1
      AND (
        r.route_id =
          CASE
            WHEN NEW.trigger_route_id IS NOT NULL AND (SELECT active FROM route WHERE id = NEW.trigger_route_id) = 1 THEN NEW.trigger_route_id
            WHEN (SELECT route_id FROM item WHERE id = NEW.trigger_item_id) IS NOT NULL AND (SELECT active FROM route WHERE id = (SELECT route_id FROM item WHERE id = NEW.trigger_item_id)) = 1
              THEN (SELECT route_id FROM item WHERE id = NEW.trigger_item_id)
            WHEN (SELECT route_id FROM zone WHERE id = lz.zone_id) IS NOT NULL AND (SELECT active FROM route WHERE id = (SELECT route_id FROM zone WHERE id = lz.zone_id)) = 1
              THEN (SELECT route_id FROM zone WHERE id = lz.zone_id)
            ELSE NULL
          END
      )
      AND (
        (NEW.trigger_type = 'demand'
          AND r.action IN ('pull','pull_or_buy')
          AND r.target_id = lz.zone_id)
        OR
        (NEW.trigger_type = 'supply'
          AND r.action = 'push'
          AND r.source_id = lz.zone_id)
      )
      AND NEW.trigger_location_id IS NOT NULL;

    -- 3. If no active route found, set status to 'intervene'
    UPDATE trigger
    SET status = 'intervene'
    WHERE id = NEW.id
      AND NOT EXISTS (
        SELECT 1 FROM rule_trigger WHERE trigger_id = NEW.id
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
        status,
        source_location_id,
        target_location_id,
        priority
    )
    SELECT
        t.trigger_item_id,
        t.trigger_lot_id,
        COALESCE(
            t.trigger_zone_id,
            (SELECT zone_id FROM location_zone WHERE location_id = t.trigger_location_id LIMIT 1)
        ),  -- source: rule's source or trigger zone -- source: trigger zone (supply)
        r.target_id,            -- target: rule's target
        t.trigger_item_quantity,
        r.route_id,
        t.id,
        r.id,
        0,
        COALESCE(r.operation_type, t.type, 'internal'),
        'draft',
        CASE
            WHEN t.trigger_type = 'demand' AND t.trigger_location_id IS NOT NULL THEN t.trigger_location_id
            ELSE NULL
        END,                     -- target_location_id: only set for supply triggers
        NULL,                    -- target_location_id (not used for supply)
            -- Set priority based on the trigger's origin_model and origin_id
        t.priority
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
        status,
        source_location_id,
        target_location_id,
        priority
    )
    SELECT
        t.trigger_item_id,
        t.trigger_lot_id,
        r.source_id,            -- source: rule's source
        COALESCE(
            t.trigger_zone_id,
            (SELECT zone_id FROM location_zone WHERE location_id = t.trigger_location_id LIMIT 1)
        ),      -- target: trigger zone (demand)
        t.trigger_item_quantity,
        r.route_id,
        t.id,
        r.id,
        0,
        COALESCE(r.operation_type, t.type, 'internal'),
        'draft',
        NULL,                   -- source_location_id (not used for demand)
        CASE
            WHEN t.trigger_type = 'demand' AND t.trigger_location_id IS NOT NULL THEN t.trigger_location_id
            ELSE NULL
        END,                     -- target_location_id: only set for demand triggers
        t.priority
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
    -- 1. If item is manufactured, create a manufacturing order and demand triggers for BOM components
    INSERT INTO manufacturing_order (
        code, partner_id, item_id, quantity, status, origin, trigger_id, manufacturing_location_id
    )
    SELECT
        'MO_' || hex(randomblob(4)),
        CASE
            WHEN t.origin_model = 'sale_order' THEN (SELECT partner_id FROM sale_order WHERE id = t.origin_id)
            WHEN t.origin_model = 'transfer_order' THEN (SELECT partner_id FROM transfer_order WHERE id = t.origin_id)
            WHEN t.origin_model = 'purchase_order' THEN (SELECT partner_id FROM purchase_order WHERE id = t.origin_id)
            WHEN t.origin_model = 'return_order' THEN (SELECT partner_id FROM return_order WHERE id = t.origin_id)
            ELSE (SELECT id FROM partner WHERE name = 'Owner A' LIMIT 1)
        END,
        t.trigger_item_id,
        t.trigger_item_quantity,
        'draft',
        'Auto-created for ' || t.origin_model || '_id=' || t.origin_id || ' (MO, item_id=' || t.trigger_item_id || ')',
        t.id,
        COALESCE(
            (
                -- 1. Prefer a location from the rule's source zone, matching production_area and priority
                SELECT lz.location_id
                FROM rule_trigger rt
                JOIN rule r ON r.id = rt.rule_id
                JOIN location_zone lz ON lz.zone_id = r.source_id
                JOIN zone z ON lz.zone_id = z.id
                JOIN location l ON lz.location_id = l.id
                WHERE rt.trigger_id = t.id
                AND z.production_area IN ('yes', 'primary')
                AND l.priority <= t.priority
                ORDER BY
                    l.priority ASC,
                    (SELECT IFNULL(SUM(s.quantity), 0) FROM stock s WHERE s.location_id = l.id) ASC,
                    lz.location_id ASC
                LIMIT 1
            ),
            (
                -- 2. Otherwise, pick a location from the primary production zone
                SELECT lz.location_id
                FROM zone z
                JOIN location_zone lz ON lz.zone_id = z.id
                JOIN location l ON lz.location_id = l.id
                WHERE z.production_area = 'primary'
                AND l.priority <= t.priority
                ORDER BY
                    l.priority ASC,
                    (SELECT IFNULL(SUM(s.quantity), 0) FROM stock s WHERE s.location_id = l.id) ASC,
                    lz.location_id ASC
                LIMIT 1
            ),
            (
                -- 3. Fallback: any location in any production area
                SELECT lz.location_id
                FROM zone z
                JOIN location_zone lz ON lz.zone_id = z.id
                WHERE z.production_area IN ('primary', 'yes')
                ORDER BY lz.location_id ASC
                LIMIT 1
            ),
            (
                -- 4. Fallback: pick any location in the rule's source zone, regardless of priority or production_area
                SELECT lz.location_id
                FROM rule_trigger rt
                JOIN rule r ON r.id = rt.rule_id
                JOIN location_zone lz ON lz.zone_id = r.source_id
                WHERE rt.trigger_id = t.id
                ORDER BY lz.location_id ASC
                LIMIT 1
            )
        )
    FROM "trigger" t
    JOIN item i ON i.id = t.trigger_item_id
    WHERE t.id = NEW.trigger_id
      AND i.is_assemblable = 1
      AND NOT EXISTS (
          SELECT 1 FROM manufacturing_order mo
          WHERE mo.status = 'draft'
            AND mo.item_id = t.trigger_item_id
            AND mo.trigger_id = t.id
      );

    -- 2. If item is NOT manufactured, fallback to purchase order logic (as before)
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
    AND (SELECT is_assemblable FROM item WHERE id = (SELECT trigger_item_id FROM "trigger" WHERE id = NEW.trigger_id)) = 0
    AND (SELECT vendor_id FROM item WHERE id = (SELECT trigger_item_id FROM "trigger" WHERE id = NEW.trigger_id)) IS NOT NULL;

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
      AND (SELECT is_assemblable FROM item WHERE id = (SELECT trigger_item_id FROM "trigger" WHERE id = NEW.trigger_id)) = 0;

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
        AND i.is_assemblable = 0
        AND (SELECT id FROM purchase_order
            WHERE status = 'draft'
            AND partner_id = (SELECT vendor_id FROM item WHERE id = t.trigger_item_id)
            ORDER BY id DESC LIMIT 1) IS NOT NULL;
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
        -- CHANGED: Prefer target_location_id if set, else fallback to existing logic
        COALESCE(
            -- 1. If the move has a target_location_id, use it
            (SELECT target_location_id FROM move WHERE id = NEW.id AND target_location_id IS NOT NULL),
            -- 2. Prefer the location linked to the customer (partner)
            (SELECT l.id
            FROM location l
            JOIN location_zone lz ON l.id = lz.location_id
            WHERE lz.zone_id = NEW.target_id
            AND l.partner_id = (SELECT partner_id FROM sale_order WHERE id = (SELECT origin_id FROM trigger WHERE id = NEW.trigger_id))
            LIMIT 1),
            -- 3. Fallback: pick a random location with stock of the item/lot
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
            -- 4. Fallback: pick a random empty location
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
            -- 5. Fallback: pick any random location in the zone
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
        status,
        priority
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
        'draft',
        COALESCE(
            (SELECT priority FROM trigger WHERE id = NEW.trigger_id),
            0
        )
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
        NEW.priority,
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
INSERT INTO zone (code, description, route_id, production_area, customer_area, inbound_area, outbound_area, vendor_area, carrier_area, employee_area, warehouse_area) VALUES
('ZON01', 'Incoming Zone', 1, 'no', 'no', 'primary', 'no', 'no', 'no', 'no', 'yes'),
('ZON05', 'Quality Control Zone', 1, 'no', 'no', 'no', 'no', 'no', 'no', 'no', 'yes'),
('ZON02', 'Stock Zone', 1, 'no', 'no', 'no', 'no', 'no', 'no', 'no', 'yes'),
('ZON06', 'Overstock Zone', 1, 'no', 'no', 'no', 'no', 'no', 'no', 'no', 'yes'),
('ZON07', 'Hot Picking Zone', 1, 'no', 'no', 'no', 'no', 'no', 'no', 'no', 'yes'),
('ZON03', 'Packing Zone', 1, 'yes', 'no', 'no', 'no', 'no', 'no', 'no', 'yes'),
('ZON04', 'Outgoing Zone', 1, 'no', 'no', 'no', 'primary', 'no', 'no', 'no', 'yes'),
('ZON08', 'Vendor Area', 1, 'yes', 'no', 'no', 'no', 'primary', 'no', 'no', 'no'),
('ZON09', 'Customer Area', 1, 'yes', 'primary', 'no', 'no', 'no', 'no', 'no', 'no'),
('ZON10', 'Employee Area', 1, 'no', 'no', 'no', 'no', 'no', 'no', 'primary', 'no'),
('ZON_PROD', 'Production/Manufacturing Zone', 1, 'primary', 'no', 'no', 'no', 'no', 'no', 'no', 'yes'),
('ZON11', 'Carrier Area', 1, 'no', 'no', 'no', 'no', 'no', 'primary', 'no', 'no');


-- Locations
INSERT INTO location (code, x, y, z, dx, dy, dz, warehouse_id, partner_id, description, priority) VALUES
-- Input A/B (left side, away from shelves)
('LOC01.1', -10.0, 0, 0, 4.5, 4.5, 4.5, 1, NULL, 'Input A', 0),
('LOC01.2', -10.0, 10, 0, 4.5, 4.5, 4.5, 1, NULL, 'Input B', 0),
('LOC01.3', -20.0, 10, 0, 4.5, 4.5, 4.5, 1, NULL, 'Input Priority', 0),

-- Quality Check A/B (far left, higher y)
('LOC05.1', -10.0, 20, 0, 4.5, 4.5, 4.5, 1, NULL, 'Quality Check A', 0),
('LOC05.2', -10.0, 30, 0, 4.5, 4.5, 4.5, 1, NULL, 'Quality Check B', 0),
('LOC05.3', -20.0, 30, 0, 4.5, 4.5, 4.5, 1, NULL, 'Quality Check Priority', 0),

-- Output (far right, higher y)
('LOC04.1', 40, 20, 0, 4.5, 4.5, 4.5, 1, NULL, 'Output A', 0),
('LOC04.2', 40, 30, 0, 4.5, 4.5, 4.5, 1, NULL, 'Output B', 0),
('LOC04.3', 40, 40, 0, 4.5, 4.5, 4.5, 1, NULL, 'Output Priority', 0),

-- Packing (far right, away from shelves)
('LOC03.1', 40, 0, 0, 4.5, 4.5, 4.5, 1, NULL, 'Default Packing', 0),
('LOC03.2', 40, 10, 0, 4.5, 4.5, 4.5, 1, NULL, 'Priority Packing', 0),

-- Add a production location (or more if needed)
('LOC_PROD_1', 0, 45, 0, 7, 7, 2, 1, NULL, 'Production Area 1', 0),
('LOC_PROD_2', 0, 55, 0, 7, 7, 2, 1, NULL, 'Production Area 2', 0),
('LOC_PROD_3', 15, 45, 0, 7, 7, 2, 1, NULL, 'Production Area 3', 0),
('LOC_PROD_4', 15, 55, 0, 7, 7, 2, 1, NULL, 'Production Area Priority', 0);


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
((SELECT id FROM location WHERE code = 'LOC01.3'), (SELECT id FROM zone WHERE code = 'ZON01')),
((SELECT id FROM location WHERE code = 'LOC05.1'), (SELECT id FROM zone WHERE code = 'ZON05')),
((SELECT id FROM location WHERE code = 'LOC05.2'), (SELECT id FROM zone WHERE code = 'ZON05')),
((SELECT id FROM location WHERE code = 'LOC05.3'), (SELECT id FROM zone WHERE code = 'ZON05')),
((SELECT id FROM location WHERE code = 'LOC03.1'), (SELECT id FROM zone WHERE code = 'ZON03')),
((SELECT id FROM location WHERE code = 'LOC03.2'), (SELECT id FROM zone WHERE code = 'ZON03')),
((SELECT id FROM location WHERE code = 'LOC04.1'), (SELECT id FROM zone WHERE code = 'ZON04')),
((SELECT id FROM location WHERE code = 'LOC04.2'), (SELECT id FROM zone WHERE code = 'ZON04')),
((SELECT id FROM location WHERE code = 'LOC04.3'), (SELECT id FROM zone WHERE code = 'ZON04'));

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
SELECT id, (SELECT id FROM zone WHERE code = 'ZON_PROD') FROM location WHERE code IN ('LOC_PROD_1', 'LOC_PROD_2', 'LOC_PROD_3', 'LOC_PROD_4');

-- Seed currencies (if not already present)
INSERT OR IGNORE INTO currency (code, symbol, name, rel_to_usd) VALUES
('USD', '$', 'US Dollar', 1.16),
('EUR', '€', 'Euro', 1.0),
('CHF', 'CHF', 'Swiss Franc', 0.94),
('BAM', 'KM', 'Bosnia and Herzegovina Convertible Mark', 1.96),
('GBP', '£', 'Pound Sterling', 0.86);

-- Seed languages (if not already present)
INSERT OR IGNORE INTO language (code, name, native_name) VALUES
('de', 'German', 'Deutsch'),
('fr', 'French', 'Français'),
('bs', 'Bosnian', 'Bosanski');

-- Seed taxes (if not already present)
INSERT OR IGNORE INTO tax (name, percent, description) VALUES
('DE Standard VAT', 19.0, 'Standard VAT for Germany'),
('AT Standard VAT', 20.0, 'Standard VAT for Austria'),
('CH Standard VAT', 7.7, 'Standard VAT for Switzerland'),
('BA Standard VAT', 17.0, 'Standard VAT for Bosnia and Herzegovina');

-- Seed countries
INSERT OR IGNORE INTO country (
    code, name, official_name, eu_member, currency_id, vat_standard, region, phone_code, language_id, active
) VALUES
('DE', 'Germany', 'Federal Republic of Germany', 1,
    (SELECT id FROM currency WHERE code='EUR'),
    (SELECT id FROM tax WHERE name='DE Standard VAT'),
    'Europe', '+49',
    (SELECT id FROM language WHERE code='de'), 1
),
('AT', 'Austria', 'Republic of Austria', 1,
    (SELECT id FROM currency WHERE code='EUR'),
    (SELECT id FROM tax WHERE name='AT Standard VAT'),
    'Europe', '+43',
    (SELECT id FROM language WHERE code='de'), 1
),
('CH', 'Switzerland', 'Swiss Confederation', 0,
    (SELECT id FROM currency WHERE code='CHF'),
    (SELECT id FROM tax WHERE name='CH Standard VAT'),
    'Europe', '+41',
    (SELECT id FROM language WHERE code='de'), 1
),
('BA', 'Bosnia and Herzegovina', 'Bosnia and Herzegovina', 0,
    (SELECT id FROM currency WHERE code='BAM'),
    (SELECT id FROM tax WHERE name='BA Standard VAT'),
    'Europe', '+387',
    (SELECT id FROM language WHERE code='bs'), 1
);

-- Partners (add more vendors)
INSERT INTO partner (
    name, street, city, country_id, zip,
    email, phone, notes,
    billing_name, billing_street, billing_city, billing_country_id, billing_zip,
    billing_email, billing_phone, billing_notes,
    partner_type, language_id
) VALUES
('Supplier A', 'Supplier St 1', 'Supplier City', 2, '1000',
    'supplierA@example.com', '123456789', 'Preferred vendor',
    'Supplier A Billing', 'Supplier Billing St 1', 'Supplier Billing City', 2, '1001',
    'billingA@example.com', '123456789', 'Billing contact for Supplier A',
    'vendor', (SELECT id FROM language WHERE code='de')
),
('Supplier B', 'Supplier St 2', 'Supplier City', 1, '1002',
    'supplierB@example.com', '223456789', '',
    'Supplier B Billing', 'Supplier Billing St 2', 'Supplier Billing City', 1, '1003',
    'billingB@example.com', '223456789', 'Billing contact for Supplier B',
    'vendor', (SELECT id FROM language WHERE code='de')
),
('Carrier C', 'Carrier Rd 10', 'Carrier City', 1, '2000',
    'carrier@example.com', '987654321', '',
    'Carrier C Billing', 'Carrier Billing Rd 10', 'Carrier Billing City', 1, '2001',
    'billingC@example.com', '987654321', 'Billing contact for Carrier C',
    'carrier', (SELECT id FROM language WHERE code='de')
),
('Customer B', 'Customer Ave 5', 'Customer City', 1, '3000',
    'customer@example.com', '555555555', '',
    'Customer B Billing', 'Customer Billing Ave 5', 'Customer Billing City', 1, '3001',
    'billing.customer@example.com', '555555555', 'Billing contact for Customer B',
    'customer', (SELECT id FROM language WHERE code='de')
),
('Owner A', 'Frikusweg 10', 'Kalsdorf bei Graz', 1, '8401',
    'owner@example.com', '111222333', '',
    'Owner A Billing', 'Nußbaumerstraße 14', 'Graz', 1, '8042',
    'billing.owner@example.com', '111222333', 'Billing contact for Owner A',
    'employee', (SELECT id FROM language WHERE code='de')
),
('Employee E', 'Employee St 3', 'Employee City', 1, '4000',
    'e@example.com', '444555666', '',
    'Employee E Billing', 'Employee Billing St 3', 'Employee Billing City', 1, '4001',
    'billing.e@example.com', '444555666', 'Billing contact for Employee E',
    'employee', (SELECT id FROM language WHERE code='de')
),
('Carton Supplier', 'Carton St 10', 'Carton City', 3, '1010',
    'carton.supplier@example.com', '333444555', '',
    'Carton Supplier Billing', 'Carton Billing St 10', 'Carton Billing City', 3, '1011',
    'billing.carton.supplier@example.com', '333444555', 'Billing contact for Carton Supplier',
    'vendor', (SELECT id FROM language WHERE code='de')
);

-- Companies
INSERT INTO company (partner_id, name, vat_number, logo_url, website)
VALUES
(5, 'AlpWolf GmbH', 'ATU12345678', '/static/img/AlpWolf_logo.png', 'https://www.alpwolf.at');

-- Users
INSERT INTO user (partner_id, company_id, username, password_hash, image_url, role)
VALUES (
    (SELECT id FROM partner WHERE name = 'Employee E'),
    (SELECT id FROM company WHERE name = 'AlpWolf GmbH'),
    'admin',
    '$2b$12$lffwZ.0/JoHoDkBJc8WWQeOgTUvXCVYzUADAs4I/dJbMM0nn9Il0O',
    '/static/img/default_user.png',
    'admin'
);

-- Warehouse
INSERT INTO warehouse (name, company_id) VALUES
('Main Warehouse', 1);

-- Items with each having its own vendor
-- Small Item A
INSERT INTO item (
    name, sku, barcode, size, description, route_id, vendor_id,
    cost, cost_currency_id, purchase_price, purchase_currency_id,
    length, width, height, weight, volume, image_url
) VALUES
('Item Small A', 'SKU001', 'BAR001', 'small',
 'A compact, lightweight product perfect for everyday use.',
 NULL, (SELECT id FROM partner WHERE name = 'Supplier A'),
 7.00, (SELECT id FROM currency WHERE code='EUR'), 7.50, (SELECT id FROM currency WHERE code='EUR'),
 12, 10, 10, 200, 1200,
 '/static/img/placeholder.png'
);

-- Big Item B
INSERT INTO item (
    name, sku, barcode, size, description, route_id, vendor_id,
    cost, cost_currency_id, purchase_price, purchase_currency_id,
    length, width, height, weight, volume, image_url
) VALUES
('Item Big B', 'SKU002', 'BAR002', 'big',
 'A large, robust item for demanding tasks and heavy-duty use.',
 NULL, (SELECT id FROM partner WHERE name = 'Supplier B'),
 15.00, (SELECT id FROM currency WHERE code='EUR'), 16.00, (SELECT id FROM currency WHERE code='EUR'),
 40, 20, 10, 1200, 8000,
 '/static/img/placeholder.png'
);

-- Kit Alpha
INSERT INTO item (
    name, sku, barcode, size, description, route_id, vendor_id,
    cost, cost_currency_id, purchase_price, purchase_currency_id, bom_id, is_assemblable, is_disassemblable,
    length, width, height, weight, volume, image_url
) VALUES (
    'Kit Alpha', 'KIT-ALPHA', 'KIT-ALPHA-BC', 'big',
    'A premium kit combining Small A and Big B for versatile applications.',
    NULL, NULL,
    20.00, (SELECT id FROM currency WHERE code='EUR'), NULL, (SELECT id FROM currency WHERE code='EUR'), NULL, 1, 1,
    40, 20, 20, 2600, 17200,
    '/static/img/KIT-ALPHA.png'
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


-- Add a shipping fee item
INSERT INTO item (name, description, sku, barcode, type, is_digital, is_assemblable, is_disassemblable, is_sellable, length, width, height, weight, volume) VALUES 
('Shipping', 'Shipping Fee', 'SHIP-001', 'SHIP-001-BC', 'service', 1, 0, 0, 0, NULL, NULL, NULL, NULL, NULL);

-- Carton Small
INSERT INTO item (
    name, sku, barcode, type, size, length, width, height, weight, volume, description, is_sellable, is_assemblable, is_disassemblable, vendor_id, image_url
) VALUES (
    'Carton Small', 'CARTON-S', 'CARTON-S-BC', 'product', 'small', 30, 20, 15, 350, 9000,
    'Small shipping carton (30x20x15 cm), ideal for compact shipments.',
    0, 0, 0, (SELECT id FROM partner WHERE name = 'Carton Supplier'),
    '/static/img/CARTON-S.png'
);

-- Carton Medium
INSERT INTO item (
    name, sku, barcode, type, size, length, width, height, weight, volume, description, is_sellable, is_assemblable, is_disassemblable, vendor_id, image_url
) VALUES (
    'Carton Medium', 'CARTON-M', 'CARTON-M-BC', 'product', 'big', 50, 30, 25, 600, 37500,
    'Medium shipping carton (50x30x25 cm), suitable for most orders.',
    0, 0, 0, (SELECT id FROM partner WHERE name = 'Carton Supplier'),
    '/static/img/CARTON-M.png'
);

-- Carton Large
INSERT INTO item (
    name, sku, barcode, type, size, length, width, height, weight, volume, description, is_sellable, is_assemblable, is_disassemblable, vendor_id, image_url
) VALUES (
    'Carton Large', 'CARTON-L', 'CARTON-L-BC', 'product', 'big', 80, 40, 40, 1200, 128000,
    'Large shipping carton (80x40x40 cm), for bulky or multiple items.',
    0, 0, 0, (SELECT id FROM partner WHERE name = 'Carton Supplier'),
    '/static/img/CARTON-L.png'
);

-- Software
INSERT INTO item (
    name, sku, barcode, type, size, description, is_sellable, is_digital, is_assemblable, is_disassemblable, image_url
) VALUES (
    'SuperApp Pro License',
    'SW-PRO',
    'SW-PRO-BC',
    'digital',
    NULL,
    'License key for SuperApp Pro software. Instant delivery by email.',
    1,    -- is_sellable
    1,    -- is_digital
    0,    -- is_assemblable
    0,    -- is_disassemblable
    '/static/img/SW-PRO.png'
);

-- For SuperApp Pro License (assuming item_id = X)
INSERT INTO service_hours (item_id, lot_id, weekday, start_time, end_time)
VALUES ((SELECT id FROM item WHERE sku = 'SW-PRO'), NULL, '24/7', '00:00:00', '23:59:59');

-- Monthly window
INSERT INTO service_window (timedelta, unit_time, max_bookings, notes)
VALUES (1, 'month', NULL, 'Monthly license window');

UPDATE item SET service_window_id = (SELECT id FROM service_window WHERE notes = 'Monthly license window')
WHERE sku = 'SW-PRO';

-- Open Doors
INSERT INTO item (
    name, sku, barcode, type, size, description, is_sellable, is_digital, is_assemblable, is_disassemblable, image_url
) VALUES (
    'OPEN DOORS',
    'OD-001',
    'OD-001-BC',
    'service',
    NULL,
    'Company Opening Hours Abstraction.',
    0,    -- is_sellable
    1,    -- is_digital
    0,    -- is_assemblable
    0,    -- is_disassemblable
    NULL
);

-- Seed service hours for AlpWolf GmbH (OD-001)
INSERT INTO service_hours (item_id, lot_id, weekday, start_time, end_time) VALUES
((SELECT id FROM item WHERE sku = 'OD-001'), NULL, 'Monday',    '08:00', '17:00'),
((SELECT id FROM item WHERE sku = 'OD-001'), NULL, 'Tuesday',   '08:00', '17:00'),
((SELECT id FROM item WHERE sku = 'OD-001'), NULL, 'Wednesday', '08:00', '17:00'),
((SELECT id FROM item WHERE sku = 'OD-001'), NULL, 'Thursday',  '08:00', '17:00'),
((SELECT id FROM item WHERE sku = 'OD-001'), NULL, 'Friday',    '08:00', '17:00'),
((SELECT id FROM item WHERE sku = 'OD-001'), NULL, 'Saturday',  '09:00', '13:00'),
((SELECT id FROM item WHERE sku = 'OD-001'), NULL, 'Sunday',    NULL,    NULL);

-- Seed service Exceptions for Alpwolf GmbH (OD-001)
INSERT INTO service_exception (item_id, lot_id, start_datetime, end_datetime, description) VALUES
((SELECT id FROM item WHERE sku = 'OD-001'), NULL, '2025-12-24 08:00:00', '2025-12-24 17:00:00', 'Christmas Eve'),
((SELECT id FROM item WHERE sku = 'OD-001'), NULL, '2025-12-25 08:00:00', '2025-12-25 17:00:00', 'Christmas Day'),
((SELECT id FROM item WHERE sku = 'OD-001'), NULL, '2025-12-31 08:00:00', '2025-12-31 17:00:00', 'New Years Eve');

-- Seed a helper item for booking click & collect time slots
INSERT INTO item (
    name, sku, barcode, type, description, is_sellable, is_digital, is_assemblable, is_disassemblable, image_url
) VALUES (
    'Click & Collect Service',
    'CC-SLOT-001',
    'CC-SLOT-001-BC',
    'service',
    'Helper item for booking click & collect pickup slots during checkout.',
    0,    -- is_sellable
    1,    -- is_digital
    0,    -- is_assemblable
    0,    -- is_disassemblable
    '/static/img/click_collect.png'
);

-- Add service_hours for Click & Collect Service (CC-SLOT-001)
INSERT INTO service_hours (item_id, lot_id, weekday, start_time, end_time)
VALUES ((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), NULL, 'Monday', '09:00', '14:00');
INSERT INTO service_hours (item_id, lot_id, weekday, start_time, end_time)
VALUES ((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), NULL, 'Tuesday', '09:00', '14:00');
INSERT INTO service_hours (item_id, lot_id, weekday, start_time, end_time)
VALUES ((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), NULL, 'Wednesday', '09:00', '14:00');
INSERT INTO service_hours (item_id, lot_id, weekday, start_time, end_time)
VALUES ((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), NULL, 'Thursday', '09:00', '14:00');
INSERT INTO service_hours (item_id, lot_id, weekday, start_time, end_time)
VALUES ((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), NULL, 'Friday', '09:00', '14:00');
INSERT INTO service_hours (item_id, lot_id, weekday, start_time, end_time)
VALUES ((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), NULL, 'Saturday', '09:00', '14:00');
INSERT INTO service_hours (item_id, lot_id, weekday, start_time, end_time)
VALUES ((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), NULL, 'Sunday', '09:00', '14:00');

-- Seed service_window for the next 5 days, each with 10 available 30-minute slots from 09:00 to 14:00
-- (You can adjust the slot count and times as needed)
-- Use SQLite date/time functions for dynamic seeding

-- one window per item
INSERT INTO service_window (timedelta, unit_time, max_bookings, notes)
VALUES (30, 'minute', 5, 'Click & Collect slots');

-- Assign the latest service_window to the item (repeat for each day if needed)
UPDATE item
SET service_window_id = (SELECT id FROM service_window ORDER BY id DESC LIMIT 1)
WHERE sku = 'CC-SLOT-001';

INSERT INTO service_booking (item_id, service_window_id, start_datetime, status, notes) VALUES
((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), (SELECT service_window_id FROM item WHERE sku = 'CC-SLOT-001'), datetime(date('now', '+0 days') || ' 09:00:00'), 'pending', 'Click & Collect slot on ' || date('now', '+0 days') || ' at 09:00'),
((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), (SELECT service_window_id FROM item WHERE sku = 'CC-SLOT-001'), datetime(date('now', '+1 days') || ' 09:00:00'), 'pending', 'Click & Collect slot on ' || date('now', '+1 days') || ' at 09:00'),
((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), (SELECT service_window_id FROM item WHERE sku = 'CC-SLOT-001'), datetime(date('now', '+2 days') || ' 09:00:00'), 'pending', 'Click & Collect slot on ' || date('now', '+2 days') || ' at 09:00'),
((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), (SELECT service_window_id FROM item WHERE sku = 'CC-SLOT-001'), datetime(date('now', '+3 days') || ' 09:00:00'), 'pending', 'Click & Collect slot on ' || date('now', '+3 days') || ' at 09:00'),
((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), (SELECT service_window_id FROM item WHERE sku = 'CC-SLOT-001'), datetime(date('now', '+4 days') || ' 09:00:00'), 'pending', 'Click & Collect slot on ' || date('now', '+4 days') || ' at 09:00'),
((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), (SELECT service_window_id FROM item WHERE sku = 'CC-SLOT-001'), datetime(date('now', '+0 days') || ' 10:00:00'), 'pending', 'Click & Collect slot on ' || date('now', '+0 days') || ' at 10:00'),
((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), (SELECT service_window_id FROM item WHERE sku = 'CC-SLOT-001'), datetime(date('now', '+1 days') || ' 10:00:00'), 'pending', 'Click & Collect slot on ' || date('now', '+1 days') || ' at 10:00'),
((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), (SELECT service_window_id FROM item WHERE sku = 'CC-SLOT-001'), datetime(date('now', '+2 days') || ' 10:00:00'), 'pending', 'Click & Collect slot on ' || date('now', '+2 days') || ' at 10:00'),
((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), (SELECT service_window_id FROM item WHERE sku = 'CC-SLOT-001'), datetime(date('now', '+3 days') || ' 10:00:00'), 'pending', 'Click & Collect slot on ' || date('now', '+3 days') || ' at 10:00'),
((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), (SELECT service_window_id FROM item WHERE sku = 'CC-SLOT-001'), datetime(date('now', '+4 days') || ' 10:00:00'), 'pending', 'Click & Collect slot on ' || date('now', '+4 days') || ' at 10:00'),
((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), (SELECT service_window_id FROM item WHERE sku = 'CC-SLOT-001'), datetime(date('now', '+0 days') || ' 11:00:00'), 'pending', 'Click & Collect slot on ' || date('now', '+0 days') || ' at 11:00'),
((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), (SELECT service_window_id FROM item WHERE sku = 'CC-SLOT-001'), datetime(date('now', '+1 days') || ' 11:00:00'), 'pending', 'Click & Collect slot on ' || date('now', '+1 days') || ' at 11:00'),
((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), (SELECT service_window_id FROM item WHERE sku = 'CC-SLOT-001'), datetime(date('now', '+2 days') || ' 11:00:00'), 'pending', 'Click & Collect slot on ' || date('now', '+2 days') || ' at 11:00'),
((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), (SELECT service_window_id FROM item WHERE sku = 'CC-SLOT-001'), datetime(date('now', '+3 days') || ' 11:00:00'), 'pending', 'Click & Collect slot on ' || date('now', '+3 days') || ' at 11:00'),
((SELECT id FROM item WHERE sku = 'CC-SLOT-001'), (SELECT service_window_id FROM item WHERE sku = 'CC-SLOT-001'), datetime(date('now', '+4 days') || ' 11:00:00'), 'pending', 'Click & Collect slot on ' || date('now', '+4 days') || ' at 11:00');

INSERT OR IGNORE INTO hs_code (code, description) VALUES
('847130', 'Portable automatic data processing machines, computers'),
('490199', 'Printed books, brochures, leaflets'),
('852349', 'Software licenses, digital media');

-- Item Small A (SKU001) as computer, all countries
INSERT OR IGNORE INTO item_hs_country (item_id, hs_code_id, country_id) VALUES
((SELECT id FROM item WHERE sku='SKU001'), (SELECT id FROM hs_code WHERE code='847130'), (SELECT id FROM country WHERE code='DE')),
((SELECT id FROM item WHERE sku='SKU001'), (SELECT id FROM hs_code WHERE code='847130'), (SELECT id FROM country WHERE code='AT')),
((SELECT id FROM item WHERE sku='SKU001'), (SELECT id FROM hs_code WHERE code='847130'), (SELECT id FROM country WHERE code='CH')),
((SELECT id FROM item WHERE sku='SKU001'), (SELECT id FROM hs_code WHERE code='847130'), (SELECT id FROM country WHERE code='BA'));

-- Item Big B (SKU002) as computer, all countries
INSERT OR IGNORE INTO item_hs_country (item_id, hs_code_id, country_id) VALUES
((SELECT id FROM item WHERE sku='SKU002'), (SELECT id FROM hs_code WHERE code='847130'), (SELECT id FROM country WHERE code='DE')),
((SELECT id FROM item WHERE sku='SKU002'), (SELECT id FROM hs_code WHERE code='847130'), (SELECT id FROM country WHERE code='AT')),
((SELECT id FROM item WHERE sku='SKU002'), (SELECT id FROM hs_code WHERE code='847130'), (SELECT id FROM country WHERE code='CH')),
((SELECT id FROM item WHERE sku='SKU002'), (SELECT id FROM hs_code WHERE code='847130'), (SELECT id FROM country WHERE code='BA'));

-- Kit Alpha (KIT-ALPHA) as computer, all countries
INSERT OR IGNORE INTO item_hs_country (item_id, hs_code_id, country_id) VALUES
((SELECT id FROM item WHERE sku='KIT-ALPHA'), (SELECT id FROM hs_code WHERE code='847130'), (SELECT id FROM country WHERE code='DE')),
((SELECT id FROM item WHERE sku='KIT-ALPHA'), (SELECT id FROM hs_code WHERE code='847130'), (SELECT id FROM country WHERE code='AT')),
((SELECT id FROM item WHERE sku='KIT-ALPHA'), (SELECT id FROM hs_code WHERE code='847130'), (SELECT id FROM country WHERE code='CH')),
((SELECT id FROM item WHERE sku='KIT-ALPHA'), (SELECT id FROM hs_code WHERE code='847130'), (SELECT id FROM country WHERE code='BA'));

-- SuperApp Pro License (SW-PRO) as software license, all countries
INSERT OR IGNORE INTO item_hs_country (item_id, hs_code_id, country_id) VALUES
((SELECT id FROM item WHERE sku='SW-PRO'), (SELECT id FROM hs_code WHERE code='852349'), (SELECT id FROM country WHERE code='DE')),
((SELECT id FROM item WHERE sku='SW-PRO'), (SELECT id FROM hs_code WHERE code='852349'), (SELECT id FROM country WHERE code='AT')),
((SELECT id FROM item WHERE sku='SW-PRO'), (SELECT id FROM hs_code WHERE code='852349'), (SELECT id FROM country WHERE code='CH')),
((SELECT id FROM item WHERE sku='SW-PRO'), (SELECT id FROM hs_code WHERE code='852349'), (SELECT id FROM country WHERE code='BA'));

-- For computers (HS_CODE_847130), standard VAT in each country
INSERT OR IGNORE INTO hs_country_tax (hs_code_id, country_id, tax_id) VALUES
((SELECT id FROM hs_code WHERE code='847130'), (SELECT id FROM country WHERE code='DE'), (SELECT id FROM tax WHERE name='DE Standard VAT')),
((SELECT id FROM hs_code WHERE code='847130'), (SELECT id FROM country WHERE code='AT'), (SELECT id FROM tax WHERE name='AT Standard VAT')),
((SELECT id FROM hs_code WHERE code='847130'), (SELECT id FROM country WHERE code='CH'), (SELECT id FROM tax WHERE name='CH Standard VAT')),
((SELECT id FROM hs_code WHERE code='847130'), (SELECT id FROM country WHERE code='BA'), (SELECT id FROM tax WHERE name='BA Standard VAT'));

-- For software licenses (HS_CODE_852349), standard VAT in each country
INSERT OR IGNORE INTO hs_country_tax (hs_code_id, country_id, tax_id) VALUES
((SELECT id FROM hs_code WHERE code='852349'), (SELECT id FROM country WHERE code='DE'), (SELECT id FROM tax WHERE name='DE Standard VAT')),
((SELECT id FROM hs_code WHERE code='852349'), (SELECT id FROM country WHERE code='AT'), (SELECT id FROM tax WHERE name='AT Standard VAT')),
((SELECT id FROM hs_code WHERE code='852349'), (SELECT id FROM country WHERE code='CH'), (SELECT id FROM tax WHERE name='CH Standard VAT')),
((SELECT id FROM hs_code WHERE code='852349'), (SELECT id FROM country WHERE code='BA'), (SELECT id FROM tax WHERE name='BA Standard VAT'));

-- Standard VAT for each country
INSERT OR IGNORE INTO tax (name, percent, description, label) VALUES
('DE Standard VAT', 19.0, 'Standard VAT for Germany', 'USt.'),
('AT Standard VAT', 20.0, 'Standard VAT for Austria', 'MwSt.'),
('CH Standard VAT', 7.7, 'Standard VAT for Switzerland', 'MWST/TVA/IVA'),
('BA Standard VAT', 17.0, 'Standard VAT for Bosnia and Herzegovina', 'PDV'),
('DE Reduced VAT', 7.0, 'Reduced VAT for Germany (books, food)', 'USt.'),
('AT Reduced VAT', 10.0, 'Reduced VAT for Austria (food, books)', 'MwSt.'),
('CH Reduced VAT', 2.5, 'Reduced VAT for Switzerland (food, books)', 'MWST/TVA/IVA');

-- -- Seed discounts
INSERT INTO discount (name, percent, amount, description) VALUES
('No Discount', NULL, 0.0, 'No discount'),
('Spring Sale', 10.0, NULL, '10% off for spring promotion'),
('Fixed 5 EUR', NULL, 5.0, '5 EUR off');

-- -- Seed price list
INSERT OR IGNORE INTO price_list (name, currency_id, valid_from, valid_to, country_id) VALUES
('European Union EUR 2025', (SELECT id FROM currency WHERE code='EUR'), '2025-01-01', '2025-12-31', (SELECT id FROM country WHERE code='DE')),
('European Union EUR 2025', (SELECT id FROM currency WHERE code='EUR'), '2026-01-01', '2026-12-31', (SELECT id FROM country WHERE code='AT')),
('Switzerland CHF 2025', (SELECT id FROM currency WHERE code='CHF'), '2025-01-01', '2025-12-31', (SELECT id FROM country WHERE code='CH')),
('World BAM 2025', (SELECT id FROM currency WHERE code='BAM'), '2025-01-01', '2025-12-31', (SELECT id FROM country WHERE code='BA'));

-- -- Price list items
-- Example items for Germany
INSERT OR IGNORE INTO price_list_item (price_list_id, item_id, price) VALUES
((SELECT id FROM price_list WHERE name='Germany EUR 2025'), (SELECT id FROM item WHERE sku='SKU001'), 12.99),
((SELECT id FROM price_list WHERE name='Germany EUR 2025'), (SELECT id FROM item WHERE sku='SKU002'), 24.99),
((SELECT id FROM price_list WHERE name='Germany EUR 2025'), (SELECT id FROM item WHERE sku='KIT-ALPHA'), 74.99),
((SELECT id FROM price_list WHERE name='Germany EUR 2025'), (SELECT id FROM item WHERE sku='SW-PRO'), 49.99);

-- Example items for Austria
INSERT OR IGNORE INTO price_list_item (price_list_id, item_id, price) VALUES
((SELECT id FROM price_list WHERE name='Austria EUR 2025'), (SELECT id FROM item WHERE sku='SKU001'), 13.49),
((SELECT id FROM price_list WHERE name='Austria EUR 2025'), (SELECT id FROM item WHERE sku='SKU002'), 25.49),
((SELECT id FROM price_list WHERE name='Austria EUR 2025'), (SELECT id FROM item WHERE sku='KIT-ALPHA'), 75.49),
((SELECT id FROM price_list WHERE name='Austria EUR 2025'), (SELECT id FROM item WHERE sku='SW-PRO'), 52.99);

-- Example items for Switzerland
INSERT OR IGNORE INTO price_list_item (price_list_id, item_id, price) VALUES
((SELECT id FROM price_list WHERE name='Switzerland CHF 2025'), (SELECT id FROM item WHERE sku='SKU001'), 14.99),
((SELECT id FROM price_list WHERE name='Switzerland CHF 2025'), (SELECT id FROM item WHERE sku='SKU002'), 27.99),
((SELECT id FROM price_list WHERE name='Switzerland CHF 2025'), (SELECT id FROM item WHERE sku='KIT-ALPHA'), 79.99),
((SELECT id FROM price_list WHERE name='Switzerland CHF 2025'), (SELECT id FROM item WHERE sku='SW-PRO'), 59.99);

-- Example items for Bosnia
INSERT OR IGNORE INTO price_list_item (price_list_id, item_id, price) VALUES
((SELECT id FROM price_list WHERE name='Bosnia BAM 2025'), (SELECT id FROM item WHERE sku='SKU001'), 10.99),
((SELECT id FROM price_list WHERE name='Bosnia BAM 2025'), (SELECT id FROM item WHERE sku='SKU002'), 20.99),
((SELECT id FROM price_list WHERE name='Bosnia BAM 2025'), (SELECT id FROM item WHERE sku='KIT-ALPHA'), 65.99),
((SELECT id FROM price_list WHERE name='Bosnia BAM 2025'), (SELECT id FROM item WHERE sku='SW-PRO'), 39.99);

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


-- Seed stock for cartons in Overstock Zone (ZON06)
INSERT INTO stock (item_id, location_id, quantity, reserved_quantity, target_quantity)
VALUES
    ((SELECT id FROM item WHERE sku = 'CARTON-S'), (SELECT id FROM location WHERE code = 'LOC_P6_L1'), 50, 0, 100),
    ((SELECT id FROM item WHERE sku = 'CARTON-M'), (SELECT id FROM location WHERE code = 'LOC_P7_L2'), 60, 0, 100),
    ((SELECT id FROM item WHERE sku = 'CARTON-L'), (SELECT id FROM location WHERE code = 'LOC_P7_L1'), 100, 0, 100);


-- Routes (set active=1 for all initial routes)
INSERT INTO route (name, description, active) VALUES
('Default', 'Default route for receiving and shipping goods', 1),
('Return Route', 'Route for customer returns with quality check', 1),
('Manufacturing Output', 'Route for finished goods from production to stock', 1),
('Manufacturing Supply', 'Route for supplying components to production', 1),
('Packing Supply', 'Route for supplying parcel components to packing area', 1),
('Unpacking Supply', 'Route for unpacking parcels (triggers packing)', 1),
('Unbuilding Supply', 'Route for supplying production zone to unbuild items', 1);


-- Rules (set active=1 for all initial rules)
INSERT INTO rule (
    route_id, action, source_id, target_id, delay, active
) VALUES
((SELECT id FROM route WHERE name = 'Default'), 'pull', (SELECT id FROM zone WHERE code='ZON08'), (SELECT id FROM zone WHERE code='ZON01'), 0, 1),
((SELECT id FROM route WHERE name = 'Default'), 'push', (SELECT id FROM zone WHERE code='ZON01'), (SELECT id FROM zone WHERE code='ZON05'), 0, 1),
((SELECT id FROM route WHERE name = 'Default'), 'push', (SELECT id FROM zone WHERE code='ZON05'), (SELECT id FROM zone WHERE code='ZON06'), 0, 1),

((SELECT id FROM route WHERE name = 'Default'), 'pull_or_buy', (SELECT id FROM zone WHERE code='ZON02'), (SELECT id FROM zone WHERE code='ZON_PROD'), 0, 1),

((SELECT id FROM route WHERE name = 'Default'), 'pull_or_buy', (SELECT id FROM zone WHERE code='ZON06'), (SELECT id FROM zone WHERE code='ZON07'), 0, 1),
((SELECT id FROM route WHERE name = 'Default'), 'pull', (SELECT id FROM zone WHERE code='ZON07'), (SELECT id FROM zone WHERE code='ZON03'), 0, 1),
((SELECT id FROM route WHERE name = 'Default'), 'pull_or_buy', (SELECT id FROM zone WHERE code='ZON03'), (SELECT id FROM zone WHERE code='ZON04'), 0, 1),
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
((SELECT id FROM route WHERE name = 'Manufacturing Supply'), 'push', (SELECT id FROM zone WHERE code='ZON05'), (SELECT id FROM zone WHERE code='ZON06'), 0, 1),

-- RULES FOR PACKING SUPPLY
((SELECT id FROM route WHERE name = 'Packing Supply'), 'pull', (SELECT id FROM zone WHERE code='ZON07'), (SELECT id FROM zone WHERE code='ZON03'), 0, 1),
((SELECT id FROM route WHERE name = 'Packing Supply'), 'pull_or_buy', (SELECT id FROM zone WHERE code='ZON06'), (SELECT id FROM zone WHERE code='ZON07'), 0, 1),
((SELECT id FROM route WHERE name = 'Packing Supply'), 'pull', (SELECT id FROM zone WHERE code='ZON08'), (SELECT id FROM zone WHERE code='ZON01'), 0, 1),
((SELECT id FROM route WHERE name = 'Packing Supply'), 'push', (SELECT id FROM zone WHERE code='ZON01'), (SELECT id FROM zone WHERE code='ZON05'), 0, 1),
((SELECT id FROM route WHERE name = 'Packing Supply'), 'push', (SELECT id FROM zone WHERE code='ZON05'), (SELECT id FROM zone WHERE code='ZON06'), 0, 1);

-- RULES FOR PACKING/UNPACKING TRIGGERD BY UNBUILD ORDER
INSERT INTO rule (route_id, action, source_id, target_id, delay, active) VALUES
-- Customer parcel unpacking (outgoing from ZON03 > unpacking in ZON09)
((SELECT id FROM route WHERE name = 'Unpacking Supply'), 'pull_or_buy', (SELECT id FROM zone WHERE code='ZON03'), (SELECT id FROM zone WHERE code='ZON04'), 0, 1),
((SELECT id FROM route WHERE name = 'Unpacking Supply'), 'pull', (SELECT id FROM zone WHERE code='ZON04'), (SELECT id FROM zone WHERE code='ZON09'), 0, 1),
-- Vendor return unpacking (outgoing from ZON03 > unpacking in ZON08)
((SELECT id FROM route WHERE name = 'Unpacking Supply'), 'pull', (SELECT id FROM zone WHERE code='ZON04'), (SELECT id FROM zone WHERE code='ZON08'), 0, 1),
-- Sales return parcel unpacking (incoming from ZON09 > unpacking in ZON05)
((SELECT id FROM route WHERE name = 'Unpacking Supply'), 'pull', (SELECT id FROM zone WHERE code='ZON01'), (SELECT id FROM zone WHERE code='ZON05'), 0, 1),
((SELECT id FROM route WHERE name = 'Unpacking Supply'), 'pull_or_buy', (SELECT id FROM zone WHERE code='ZON09'), (SELECT id FROM zone WHERE code='ZON01'), 0, 1),
-- Vendor supply unpacking (incoming from ZON08 > unpacking in ZON05)
((SELECT id FROM route WHERE name = 'Unpacking Supply'), 'pull_or_buy', (SELECT id FROM zone WHERE code='ZON08'), (SELECT id FROM zone WHERE code='ZON01'), 0, 1);

-- RULES FOR UNBUILDING TRIGGERD BY UNBUILD ORDER
INSERT INTO rule (route_id, action, source_id, target_id, delay, active) VALUES
((SELECT id FROM route WHERE name = 'Unbuilding Supply'), 'pull', (SELECT id FROM zone WHERE code='ZON02'), (SELECT id FROM zone WHERE code='ZON_PROD'), 0, 1);



INSERT INTO dropshipping_policy (
    item_id,
    vendor_id,
    customer_id,
    carrier_id,
    vendor_accepts_dropship,
    ordered_quantity_below,
    ordered_quantity_above,
    warehouse_stock_threshold,
    vendor_stock_threshold,
    vendor_shipping_cost_lower,
    action,
    priority,
    active
) VALUES 
    (NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'warehouse', 0, 1),
    (1,    NULL, NULL, NULL, NULL, NULL, 20, NULL, NULL, NULL, 'dropship',  0, 1);


-- Small carton
INSERT INTO packing_policy (
    origin_model, origin_id,
    action, min_cumulative_length, max_cumulative_length, min_cumulative_width, max_cumulative_width,
    min_cumulative_height, max_cumulative_height, min_cumulative_volume, max_cumulative_volume,
    min_cumulative_weight, max_cumulative_weight, min_cumulative_value, max_cumulative_value,
    contains_hazardous_type, carrier_id, shipping_method, recipient_id, sender_id,
    temperature_control, fragile, insurance_required, priority, active, notes
) VALUES (
    NULL, NULL,
    (SELECT id FROM item WHERE sku = 'CARTON-S'),
    NULL, 30, NULL, 20,
    NULL, 15, NULL, 9000,
    NULL, 350, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL,
    10, 1, 'Use small carton if dimensions and weight fit'
);

-- Medium carton
INSERT INTO packing_policy (
    origin_model, origin_id,
    action, min_cumulative_length, max_cumulative_length, min_cumulative_width, max_cumulative_width,
    min_cumulative_height, max_cumulative_height, min_cumulative_volume, max_cumulative_volume,
    min_cumulative_weight, max_cumulative_weight, min_cumulative_value, max_cumulative_value,
    contains_hazardous_type, carrier_id, shipping_method, recipient_id, sender_id,
    temperature_control, fragile, insurance_required, priority, active, notes
) VALUES (
    NULL, NULL,
    (SELECT id FROM item WHERE sku = 'CARTON-M'),
    31, 50, 21, 30,
    16, 25, 9001, 37500,
    351, 600, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL,
    5, 1, 'Use medium carton if dimensions and weight fit'
);

INSERT INTO packing_policy (
    origin_model, origin_id,
    action,
    min_cumulative_length, max_cumulative_length,
    min_cumulative_width, max_cumulative_width,
    min_cumulative_height, max_cumulative_height,
    min_cumulative_volume, max_cumulative_volume,
    min_cumulative_weight, max_cumulative_weight,
    min_cumulative_value, max_cumulative_value,
    contains_hazardous_type, carrier_id, shipping_method, recipient_id, sender_id,
    temperature_control, fragile, insurance_required, priority, active, notes
) VALUES (
    NULL, NULL,
    (SELECT id FROM item WHERE sku = 'CARTON-L'),
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL,
    0, 1, 'Fallback: use largest carton'
);