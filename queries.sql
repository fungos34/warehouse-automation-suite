-- In this SQL file, write (and comment!) the typical SQL queries users will run on your database

-- SESSION SETTINGS
PRAGMA recursive_triggers = ON;
.headers ON
.mode column

-- SALE ORDER QUERIES
-- Create a sale order (replace 3 with your customer partner_id)
INSERT INTO sale_order (code, partner_id, status) VALUES ('ORD0002', 3, 'draft');

-- Add order lines (replace 1 with your order_id, 1/2 with item_id, and quantity as needed)
INSERT INTO order_line (quantity, item_id, order_id) VALUES (5, 1, 1);
INSERT INTO order_line (quantity, item_id, order_id) VALUES (2, 2, 1);

-- Show all unconfirmed sale orders
SELECT * FROM sale_order WHERE status != 'confirmed' ORDER BY id;
-- sale order items view
SELECT * FROM sale_order_item_view;

-- Set the sale order to confirmed (replace 1 with your order_id)
UPDATE sale_order SET status = 'confirmed' WHERE id = 1;


-- PICKING LIST QUERIES
-- Set a move_line to done and set done_quantity (replace 1 with your move_line id)
UPDATE move_line SET status = 'done', done_quantity = quantity WHERE id = 1;


-- WAREHOUSE QUERIES
-- Create a transfer order (replace 3 with your partner_id)
INSERT INTO transfer_order (status, origin, partner_id) VALUES ('draft', 'Manual Transfer', 3);

-- Add transfer order lines (replace 1 with your transfer_order_id, 1 with item_id, 2 with target_zone_id)
INSERT INTO transfer_order_line (transfer_order_id, item_id, quantity, target_zone_id) VALUES (1, 1, 10, 2);

-- Add 20 units of item 1 to location 12 (replace as needed)
INSERT INTO stock_adjustment (item_id, location_id, delta, reason) VALUES (1, 12, 20, 'Manual restock');

-- Show stock for a specific item across all locations (replace 1 with item_id)
SELECT * FROM stock_by_location WHERE item_id = 1;

-- shoq stock for all items across all locations
SELECT * FROM warehouse_stock_view;

-- Show all moves and move lines for a given origin (replace 'sale_order' and 1 as needed)
SELECT * FROM move_and_lines_by_origin WHERE origin_model = sale_order AND origin_id = 1SELECT * FROM stock_by_location WHERE item_id = ?; ORDER BY move_id, move_line_id;

-- Show all move lines for a given picking (replace 1 with your picking_id)
SELECT * FROM move_lines_by_picking WHERE picking_id = 1 ORDER BY id;

-- Show all empty locations (no stock or only zero quantity)
SELECT * FROM empty_locations;

-- Show all locations with stock
SELECT * FROM location_zone_view;


-- DEBUG LOG QUERIES
SELECT * FROM debug_log ORDER BY created_at DESC;

-- Show recent interventions
SELECT * FROM intervention ORDER BY created_at DESC;

-- Show all stock adjustments
SELECT * FROM stock_adjustment ORDER BY created_at DESC;