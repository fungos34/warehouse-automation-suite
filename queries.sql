-- In this SQL file, write (and comment!) the typical SQL queries users will run on your database

-- SESSION SETTINGS
PRAGMA recursive_triggers = ON;
.headers ON
.mode column

-- ITEM LOCATION QUERIES
-- Show all locations and stock for a given item by SKU
SELECT i.sku, i.name AS item_name, l.code AS location_code, l.description AS location_description, s.quantity, s.reserved_quantity
FROM item i
JOIN stock s ON i.id = s.item_id
JOIN location l ON s.location_id = l.id
WHERE i.sku = 'SKU123';

-- Show all lots and their locations for a given item by SKU
SELECT i.sku, l.lot_number, loc.code AS location_code, s.quantity
FROM item i
JOIN lot l ON l.item_id = i.id
JOIN stock s ON s.lot_id = l.id
JOIN location loc ON s.location_id = loc.id
WHERE i.sku = 'SKU123';

-- WAREHOUSE FLOW: FROM QUOTATION TO SHIPPING

-- 1. Create a quotation (replace 3 with your customer partner_id)
INSERT INTO quotation (partner_id, status) VALUES (3, 'draft');

-- 2. Add quotation lines (replace 1 with your quotation_id, 1/2 with item_id, and quantity as needed)
INSERT INTO quotation_line (quantity, item_id, quotation_id) VALUES (5, 1, 1);
INSERT INTO quotation_line (quantity, item_id, quotation_id) VALUES (2, 2, 1);

-- 3. Confirm the quotation (replace 1 with your quotation_id)
UPDATE quotation SET status = 'confirmed' WHERE id = 1;

-- 4. Create a sale order from a confirmed quotation (replace 1 with your quotation_id, 3 with your customer partner_id)
INSERT INTO sale_order (quotation_id, partner_id, status) VALUES (1, 3, 'draft');

-- 5. Add order lines (replace 1 with your order_id, 1/2 with item_id, and quantity as needed)
INSERT INTO order_line (quantity, item_id, order_id) VALUES (5, 1, 1);
INSERT INTO order_line (quantity, item_id, order_id) VALUES (2, 2, 1);

-- 6. Confirm the sale order (replace 1 with your order_id)
UPDATE sale_order SET status = 'confirmed' WHERE id = 1;

-- 7. Create picking for the sale order (replace 1 with your sale_order_id)
INSERT INTO picking (origin, type, source_id, target_id, status, partner_id) VALUES ('sale_order', 'outbound', 1, NULL, 'draft', 3);

-- 8. Create moves for each order line (replace picking_id, item_id, quantity, source/target_id as needed)
INSERT INTO move (item_id, quantity, source_id, target_id, picking_id, status) VALUES (1, 5, 12, 13, 1, 'draft');
INSERT INTO move (item_id, quantity, source_id, target_id, picking_id, status) VALUES (2, 2, 12, 13, 1, 'draft');

-- 9. Create move lines for each move (replace move_id, lot_id, quantity as needed)
INSERT INTO move_line (move_id, lot_id, quantity, status) VALUES (1, 101, 5, 'draft');
INSERT INTO move_line (move_id, lot_id, quantity, status) VALUES (2, 102, 2, 'draft');

-- 10. Set move_line to done and set done_quantity (replace 1 with your move_line id)
UPDATE move_line SET status = 'done', done_quantity = quantity WHERE id = 1;

-- 11. Confirm picking (replace 1 with your picking_id)
UPDATE picking SET status = 'confirmed' WHERE id = 1;

-- 12. Create a transfer order for shipping (replace 3 with your partner_id)
INSERT INTO transfer_order (status, origin, partner_id) VALUES ('draft', 'Manual Transfer', 3);

-- 13. Add transfer order lines (replace 1 with your transfer_order_id, 1 with item_id, 2 with target_zone_id)
INSERT INTO transfer_order_line (transfer_order_id, item_id, quantity, target_zone_id) VALUES (1, 1, 10, 2);

-- 14. Confirm transfer order (replace 1 with your transfer_order_id)
UPDATE transfer_order SET status = 'confirmed' WHERE id = 1;

-- STOCK QUERIES
-- Add stock adjustment (replace as needed)
INSERT INTO stock_adjustment (item_id, location_id, delta, reason) VALUES (1, 12, 20, 'Manual restock');

-- Show stock for a specific item across all locations (replace 1 with item_id)
SELECT * FROM stock_by_location WHERE item_id = 1;

-- Show stock for all items across all locations
SELECT * FROM warehouse_stock_view;

-- Show all moves and move lines for a given origin (replace 'sale_order' and 1 as needed)
SELECT * FROM move_and_lines_by_origin WHERE origin_model = 'sale_order' AND origin_id = 1 ORDER BY move_id, move_line_id;

-- Show all move lines for a given picking (replace 1 with your picking_id)
SELECT * FROM move_lines_by_picking WHERE picking_id = 1 ORDER BY id;

-- Show all empty locations (no stock or only zero quantity)
SELECT * FROM empty_locations;

-- Show all locations with stock
SELECT * FROM location_zone_view;

SELECT * FROM debug_log ORDER BY created_at DESC;

SELECT * FROM intervention ORDER BY created_at DESC;

SELECT * FROM stock_adjustment ORDER BY created_at DESC;

-- MANUFACTURING ORDER FLOW
-- 1. Create a manufacturing order (replace 1 with item_id, set status as needed)
INSERT INTO manufacturing_order (item_id, status) VALUES (1, 'draft');

-- 2. Confirm manufacturing order (replace 1 with manufacturing_order_id)
UPDATE manufacturing_order SET status = 'confirmed' WHERE id = 1;

-- 3. Add BOM lines (replace 1 with bom_id, 2 with lot_id)
INSERT INTO bom_line (bom_id, lot_id) VALUES (1, 2);

-- 4. Mark manufacturing order as done (replace 1 with manufacturing_order_id)
UPDATE manufacturing_order SET status = 'done' WHERE id = 1;

-- UNBUILD ORDER FLOW
-- 1. Create an unbuild order (replace 1 with item_id, set status as needed)
INSERT INTO unbuild_order (item_id, status) VALUES (1, 'draft');

-- 2. Confirm unbuild order (replace 1 with unbuild_order_id)
UPDATE unbuild_order SET status = 'confirmed' WHERE id = 1;

-- 3. Mark unbuild order as done (replace 1 with unbuild_order_id)
UPDATE unbuild_order SET status = 'done' WHERE id = 1;

-- RETURN ORDER FLOW
-- 1. Create a return order (replace 3 with partner_id, set status as needed)
INSERT INTO return_order (partner_id, status) VALUES (3, 'draft');

-- 2. Add return lines (replace 1 with return_order_id, 1/2 with item_id, quantity as needed)
INSERT INTO return_line (return_order_id, item_id, quantity) VALUES (1, 1, 2);

-- 3. Confirm return order (replace 1 with return_order_id)
UPDATE return_order SET status = 'confirmed' WHERE id = 1;

-- 4. Mark return order as done (replace 1 with return_order_id)
UPDATE return_order SET status = 'done' WHERE id = 1;

INSERT INTO purchase_order (partner_id, status) VALUES (3, 'draft');

-- SUBSCRIPTION & SERVICE FLOWS
-- Create a subscription (replace 1 with partner_id, 2 with item_id, 3 with service_window_id)
INSERT INTO subscription (partner_id, item_id, service_window_id, status) VALUES (1, 2, 3, 'active');

-- Add subscription line (replace 1 with subscription_id, 2 with sale_order_id)
INSERT INTO subscription_line (subscription_id, sale_order_id) VALUES (1, 2);

-- Cancel subscription (replace 1 with subscription_id)
UPDATE subscription SET status = 'cancelled' WHERE id = 1;

-- Renew subscription (replace 1 with subscription_id)
UPDATE subscription SET status = 'active' WHERE id = 1;

-- PACKING & PARCEL CREATION
-- Create packing policy (replace 1 with sender_id)
INSERT INTO packing_policy (sender_id) VALUES (1);

-- Create packing question (replace 1 with sender_id)
INSERT INTO packing_question (sender_id, question) VALUES (1, 'Is fragile?');

-- Answer packing question (replace 1 with packing_question_id)
UPDATE packing_question SET answer = 'yes' WHERE id = 1;

-- Create parcel item (replace 1 with item_id, 2 with lot_id)
INSERT INTO item (sku, description) VALUES ('PKG-sale_order-1', 'Parcel for sale order 1');
INSERT INTO lot (item_id) VALUES (1);

-- DROPSHIPPING FLOWS
-- Create dropshipping policy (replace 1 with carrier_id)
INSERT INTO dropshipping_policy (carrier_id) VALUES (1);

-- Create dropshipping question (replace 1 with carrier_id)
INSERT INTO dropshipping_question (carrier_id, question) VALUES (1, 'Can deliver to zone 2?');

-- Answer dropshipping question (replace 1 with dropshipping_question_id)
UPDATE dropshipping_question SET answer = 'yes' WHERE id = 1;

-- Assign carrier to transfer order (replace 1 with transfer_order_id, 2 with carrier_id)
UPDATE transfer_order SET carrier_id = 2 WHERE id = 1;

-- MANUFACTURING BOM CONSUMPTION/PRODUCTION
-- Consume BOM components for manufacturing order (replace 1 with manufacturing_order_id, 2 with bom_line_id)
UPDATE bom_line SET consumed = 1 WHERE id = 2 AND bom_id = 1;

-- Create finished product for manufacturing order (replace 1 with manufacturing_order_id, 2 with item_id)
INSERT INTO lot (item_id, manufacturing_order_id) VALUES (2, 1);

-- SERVICE BOOKINGS & EXCEPTIONS
-- Create service booking (replace 1 with partner_id, 2 with item_id, 3 with lot_id, 4 with service_window_id)
INSERT INTO service_booking (partner_id, item_id, lot_id, service_window_id) VALUES (1, 2, 3, 4);

-- Create service exception (replace 1 with lot_id)
INSERT INTO service_exception (lot_id, reason) VALUES (1, 'Damaged during service');

-- RULE & TRIGGER MANAGEMENT
-- Create rule (replace 1 with target_id)
INSERT INTO rule (target_id, action) VALUES (1, 'pull_or_buy');

-- Create trigger (replace 1 with origin_id, 2 with trigger_type)
INSERT INTO trigger (origin_id, trigger_type, status) VALUES (1, 'supply', 'draft');

-- Link rule to move (replace 1 with move_id)
INSERT INTO rule_trigger (move_id) VALUES (1);

-- Evaluate trigger (replace 1 with trigger_id)
UPDATE trigger SET status = 'intervene' WHERE id = 1;

-- ZONE & ROUTE MANAGEMENT
-- Create zone (replace 1 with route_id)
INSERT INTO zone (route_id, description) VALUES (1, 'Zone A');

-- Assign location to zone (replace 1 with location_id, 2 with zone_id)
INSERT INTO location_zone (location_id, zone_id) VALUES (1, 2);

-- Change route for zone (replace 1 with zone_id, 2 with route_id)
UPDATE zone SET route_id = 2 WHERE id = 1;

-- DEBUG & INTERVENTION RESOLUTION
-- Insert debug event (replace 1 with move_id)
INSERT INTO debug_log (event, move_id, info) VALUES ('Move completed', 1, 'Details...');

-- Resolve intervention (replace 1 with intervention_id)
UPDATE intervention SET resolved = 1 WHERE id = 1;

-- UNBUILD ORDER DETAILS
-- Extract components from parcel (replace 1 with unbuild_order_id, 2 with lot_id)
INSERT INTO lot (unbuild_order_id, item_id) VALUES (1, 2);

-- Mark extracted lot as available (replace 1 with lot_id)
UPDATE lot SET available = 1 WHERE id = 1;

-- ADVANCED STOCK RESERVATION & ALLOCATION
-- Reserve stock for move (replace 1 with stock_id, 2 with quantity)
UPDATE stock SET reserved_quantity = reserved_quantity + 2 WHERE id = 1;

-- Fulfill stock for move (replace 1 with stock_id, 2 with quantity)
UPDATE stock SET quantity = quantity - 2, reserved_quantity = reserved_quantity - 2 WHERE id = 1;

-- PARTNER/LOCATION CREATION & ASSIGNMENT
-- Create partner (replace 1 with language_id)
INSERT INTO partner (language_id, name) VALUES (1, 'New Partner');

-- Auto-create location for partner (replace 1 with partner_id, 2 with warehouse_id)
INSERT INTO location (partner_id, warehouse_id, code, description) VALUES (1, 2, 'LOC-NEW', 'Auto-created location');

-- Assign location to zone (replace 1 with location_id, 2 with zone_id)
INSERT INTO location_zone (location_id, zone_id) VALUES (1, 2);

-- PRICE LIST & DISCOUNT APPLICATION
-- Create price list (replace 1 with country_id)
INSERT INTO price_list (country_id, name) VALUES (1, 'Standard Prices');

-- Add item to price list (replace 1 with price_list_id, 2 with item_id, 3 with unit_id, 4 with price)
INSERT INTO price_list_item (price_list_id, item_id, unit_id, price) VALUES (1, 2, 3, 99.99);

-- Apply discount to purchase order (replace 1 with purchase_order_id, 2 with discount_id)
UPDATE purchase_order SET discount_id = 2 WHERE id = 1;

-- 2. Add purchase order lines (replace 1 with purchase_order_id, 1/2 with item_id, lot_id, quantity as needed)
INSERT INTO purchase_order_line (purchase_order_id, item_id, lot_id, quantity) VALUES (1, 1, 101, 5);

-- 3. Confirm purchase order (replace 1 with purchase_order_id)
UPDATE purchase_order SET status = 'confirmed' WHERE id = 1;

-- 4. Mark purchase order as done (replace 1 with purchase_order_id)
UPDATE purchase_order SET status = 'done' WHERE id = 1;