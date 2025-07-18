import sqlite3
import pytest
import os

@pytest.fixture(scope="session")
def db():
    # Load schema and seed data
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA recursive_triggers = ON;")
    with open("schema.sql", encoding="utf-8") as f:
        conn.executescript(f.read())
    yield conn
    conn.close()

###### TEST SEED DATA ######

def test_items_exist(db):
    cursor = db.execute("SELECT name, sku, barcode FROM item")
    items = cursor.fetchall()
    assert len(items) >= 3, "At least three items should exist"
    names = {row["name"] for row in items}
    assert "Item Small A" in names
    assert "Item Big B" in names
    assert "Kit Alpha" in names

def test_stock_seeded(db):
    # There should be stock for each vendor's item in their location
    cursor = db.execute("""
        SELECT i.name, s.quantity, l.code
        FROM stock s
        JOIN item i ON s.item_id = i.id
        JOIN location l ON s.location_id = l.id
        WHERE s.quantity > 0
    """)
    rows = cursor.fetchall()
    assert rows, "No stock records found"
    # At least one stock record for each item
    item_names = {row["name"] for row in rows}
    assert "Item Small A" in item_names
    assert "Item Big B" in item_names

    cursor = db.execute("SELECT COUNT(*) FROM stock WHERE location_id NOT IN (SELECT location_id FROM location_zone WHERE zone_id=(SELECT id from zone WHERE code='ZON08'))")
    stock_count = cursor.fetchone()[0]
    assert stock_count == 0, "Stock should be empty in the warehouse"

    cursor = db.execute("SELECT COUNT(*) FROM stock WHERE location_id IN (SELECT location_id FROM location_zone WHERE zone_id=(SELECT id from zone WHERE code='ZON08'))")
    stock_count = cursor.fetchone()[0]
    assert stock_count > 0, "Stock should be available in Vendor Area"


def test_users_exist(db):
    cursor = db.execute("SELECT username, password_hash FROM user")
    users = cursor.fetchall()
    assert users, "No users found"
    usernames = {row["username"] for row in users}
    assert "admin" in usernames, "Admin user not found"
    # Check password hash for admin (bcrypt hash for 'admin')
    admin_hash = next((row["password_hash"] for row in users if row["username"] == "admin"), None)
    assert admin_hash and admin_hash.startswith("$2b$"), "Admin password hash missing or not bcrypt"

def test_partners_exist(db):
    cursor = db.execute("SELECT name, partner_type FROM partner")
    partners = cursor.fetchall()
    assert partners, "No partners found"
    types = {row["partner_type"] for row in partners}
    assert "vendor" in types
    assert "customer" in types
    assert "employee" in types
    names = {row["name"] for row in partners}
    assert "Supplier A" in names
    assert "Supplier B" in names
    assert "Customer B" in names
    assert "Owner A" in names

def test_currencies_exist(db):
    cursor = db.execute("SELECT code, symbol FROM currency")
    currencies = {row["code"]: row["symbol"] for row in cursor.fetchall()}
    assert "EUR" in currencies and currencies["EUR"] == "€"
    assert "USD" in currencies and currencies["USD"] == "$"

def test_lots_exist(db):
    cursor = db.execute("SELECT lot_number, item_id FROM lot")
    lots = cursor.fetchall()
    assert lots, "No lots found"
    lot_numbers = {row["lot_number"] for row in lots}
    assert "LOT-A-001" in lot_numbers

def test_all_zones_exist(db):
    # List of expected zone codes from schema.sql
    expected_zones = [
        'ZON01', 'ZON05', 'ZON02', 'ZON06', 'ZON07', 'ZON03', 'ZON04',
        'ZON08', 'ZON09', 'ZON10', 'ZON_PROD'
    ]
    cursor = db.execute("SELECT code FROM zone")
    found_zones = {row[0] for row in cursor.fetchall()}
    for code in expected_zones:
        assert code in found_zones, f"Zone {code} not found in the database"

def test_all_locations_exist(db):
    # List of expected location codes from schema.sql and seed logic
    expected_locations = [
        # Example dock/zone locations
        'LOC01.1', 'LOC01.2', 'LOC03.1', 'LOC04.1', 'LOC04.2', 'LOC05.1', 'LOC05.2',
        # Production locations
        'LOC_PROD_1',
        # Shelf locations (only first 2 shelves in each row for simplicity)
        'LOC_A1_L1', 'LOC_A1_L2', 'LOC_A1_L3', 'LOC_A1_L4',
        'LOC_A2_L1', 'LOC_A2_L2', 'LOC_A2_L3', 'LOC_A2_L4',
        'LOC_B1_L1', 'LOC_B1_L2', 'LOC_B1_L3', 'LOC_B1_L4',
        'LOC_B2_L1', 'LOC_B2_L2', 'LOC_B2_L3', 'LOC_B2_L4',
        'LOC_D1_L1', 'LOC_D1_L2', 'LOC_D1_L3', 'LOC_D1_L4',
        'LOC_D2_L1', 'LOC_D2_L2', 'LOC_D2_L3', 'LOC_D2_L4',
        'LOC_E1_L1', 'LOC_E1_L2', 'LOC_E1_L3', 'LOC_E1_L4',
        'LOC_E2_L1', 'LOC_E2_L2', 'LOC_E2_L3', 'LOC_E2_L4',
        'LOC_G1_L1', 'LOC_G1_L2', 'LOC_G1_L3', 'LOC_G1_L4',
        'LOC_G2_L1', 'LOC_G2_L2', 'LOC_G2_L3', 'LOC_G2_L4',
        'LOC_H1_L1', 'LOC_H1_L2', 'LOC_H1_L3', 'LOC_H1_L4',
        'LOC_H2_L1', 'LOC_H2_L2', 'LOC_H2_L3', 'LOC_H2_L4',
        'LOC_J1_L1', 'LOC_J1_L2', 
        'LOC_J2_L1', 'LOC_J2_L2', 
        'LOC_K1_L1', 'LOC_K1_L2', 
        'LOC_K2_L1', 'LOC_K2_L2', 
        'LOC_M1_L1', 'LOC_M1_L2', 
        'LOC_M2_L1', 'LOC_M2_L2', 
        'LOC_N1_L1', 'LOC_N1_L2', 
        'LOC_N2_L1', 'LOC_N2_L2', 
        'LOC_P1_L1', 'LOC_P1_L2', 
        'LOC_P2_L1', 'LOC_P2_L2', 
        'LOC_Q1_L1', 'LOC_Q1_L2', 'LOC_Q1_L3', 'LOC_Q1_L4',
        'LOC_Q2_L1', 'LOC_Q2_L2', 'LOC_Q2_L3', 'LOC_Q2_L4',
    ]
    cursor = db.execute("SELECT code FROM location")
    found_locations = {row[0] for row in cursor.fetchall()}
    for code in expected_locations:
        assert code in found_locations, f"Location {code} not found in the database"


def test_location_zone_assignments(db):
    """
    For every zone in the schema, ensure:
    - At least one location is assigned.
    - All assigned locations are suitable for the zone (based on naming conventions and schema.sql logic).
    """
    # Get all zones and their assigned locations
    cursor = db.execute("""
        SELECT z.code as zone_code, z.description as zone_desc, l.code as location_code
        FROM location_zone lz
        JOIN location l ON lz.location_id = l.id
        JOIN zone z ON lz.zone_id = z.id
    """)
    assignments = {}
    zone_descriptions = {}
    for row in cursor.fetchall():
        assignments.setdefault(row["zone_code"], set()).add(row["location_code"])
        zone_descriptions[row["zone_code"]] = row["zone_desc"]

    # Get all zones from the schema
    expected_zones = [
        'ZON01', 'ZON05', 'ZON02', 'ZON06', 'ZON07', 'ZON03', 'ZON04',
        'ZON08', 'ZON09', 'ZON10', 'ZON_PROD'
    ]

    # Each zone should have at least one location assigned
    for zone in expected_zones:
        assert zone in assignments, f"Zone {zone} has no locations assigned"
        assert len(assignments[zone]) > 0, f"Zone {zone} has an empty location assignment"

    # Suitability checks based on schema.sql logic and naming conventions
    for zone, locs in assignments.items():
        desc = zone_descriptions.get(zone, "")
        if zone == "ZON_PROD":
            for loc in locs:
                assert loc.startswith("LOC_PROD"), f"Non-production location {loc} assigned to {zone} ({desc})"
        elif zone == "ZON01":
            for loc in locs:
                assert loc.startswith("LOC01"), f"Location {loc} not suitable for {zone} ({desc})"
        elif zone == "ZON05":
            for loc in locs:
                assert loc.startswith("LOC05"), f"Location {loc} not suitable for {zone} ({desc})"
        elif zone == "ZON03":
            for loc in locs:
                assert loc.startswith("LOC03"), f"Location {loc} not suitable for {zone} ({desc})"
        elif zone == "ZON04":
            for loc in locs:
                assert loc.startswith("LOC04"), f"Location {loc} not suitable for {zone} ({desc})"
        elif zone == "ZON02":
            for loc in locs:
                assert (
                    loc.startswith("LOC_A") or loc.startswith("LOC_B") or loc.startswith("LOC_D") or
                    loc.startswith("LOC_E") or loc.startswith("LOC_G") or loc.startswith("LOC_H") or
                    loc.startswith("LOC_Q") or loc.startswith("LOC_J") or loc.startswith("LOC_K") or
                    loc.startswith("LOC_M") or loc.startswith("LOC_N") or loc.startswith("LOC_P")
                ), f"Location {loc} not suitable for {zone} ({desc})"
        elif zone == "ZON06":
            for loc in locs:
                assert (
                    loc.startswith("LOC_A") or loc.startswith("LOC_B") or loc.startswith("LOC_D") or
                    loc.startswith("LOC_E") or loc.startswith("LOC_G") or loc.startswith("LOC_H") or
                    loc.startswith("LOC_Q")
                ), f"Location {loc} not suitable for {zone} ({desc})"
        elif zone == "ZON07":
            for loc in locs:
                assert (
                    loc.startswith("LOC_J") or loc.startswith("LOC_K") or
                    loc.startswith("LOC_M") or loc.startswith("LOC_N") or
                    loc.startswith("LOC_P")
                ), f"Location {loc} not suitable for {zone} ({desc})"
        elif zone == "ZON08":
            for loc in locs:
                # Vendor/partner area: should match vendor/customer/partner location naming, e.g. LOC_VEND, LOC_PARTNER, etc.
                assert (
                    loc.startswith("LOC_VENDOR_")
                ), f"Location {loc} not suitable for {zone} ({desc})"
        elif zone == "ZON09":
            for loc in locs:
                # Customer area: should match customer location naming, e.g. LOC_CUST, LOC09, etc.
                assert (
                    loc.startswith("LOC_CUSTOMER_")
                ), f"Location {loc} not suitable for {zone} ({desc})"
        elif zone == "ZON10":
            for loc in locs:
                # Employee area: should match employee location naming, e.g. LOC_EMP, LOC10, etc.
                assert (
                    loc.startswith("LOC_EMPLOYEE_")
                ), f"Location {loc} not suitable for {zone} ({desc})"
        elif zone == "ZON11":
            for loc in locs:
                # Carrier area: should match carrier location naming, e.g. LOC_CARRIER, LOC11, etc.
                assert (
                    loc.startswith("LOC_CARRIER_")
                ), f"Location {loc} not suitable for {zone} ({desc})"


def test_routes_exist(db):
    cursor = db.execute("SELECT name FROM route")
    routes = {row["name"] for row in cursor.fetchall()}
    expected_routes = {
        "Default", "Return Route", "Manufacturing Output", "Manufacturing Supply"
    }
    for route in expected_routes:
        assert route in routes, f"Route {route} missing"


def test_rules_exist(db):
    cursor = db.execute("""
        SELECT r.id, r.action, zs.code as source_zone, zt.code as target_zone, rt.name as route_name
        FROM rule r
        LEFT JOIN zone zs ON r.source_id = zs.id
        LEFT JOIN zone zt ON r.target_id = zt.id
        LEFT JOIN route rt ON r.route_id = rt.id
        ORDER BY rt.name, r.action, zs.code, zt.code
    """)
    rules = cursor.fetchall()
    assert rules, "No rules found"

    # Define expected rules as tuples: (route_name, action, source_zone, target_zone)
    expected_rules = [
        # Default route
        ("Default", "push", "ZON08", "ZON01"),
        ("Default", "push", "ZON01", "ZON05"),
        ("Default", "push", "ZON05", "ZON06"),
        ("Default", "pull", "ZON02", "ZON_PROD"),
        ("Default", "pull_or_buy", "ZON06", "ZON07"),
        ("Default", "pull", "ZON07", "ZON03"),
        ("Default", "pull", "ZON03", "ZON04"),
        ("Default", "pull", "ZON04", "ZON09"),
        # Return Route
        ("Return Route", "push", "ZON09", "ZON01"),
        ("Return Route", "push", "ZON01", "ZON05"),
        ("Return Route", "push", "ZON05", "ZON02"),
        # Manufacturing Output
        ("Manufacturing Output", "push", "ZON_PROD", "ZON06"),
        # Manufacturing Supply
        ("Manufacturing Supply", "pull_or_buy", "ZON06", "ZON_PROD"),
        ("Manufacturing Supply", "push", "ZON08", "ZON01"),
        ("Manufacturing Supply", "push", "ZON01", "ZON05"),
    ]

    # Build a set of actual rules for easy comparison
    actual_rules = set((r["route_name"], r["action"], r["source_zone"], r["target_zone"]) for r in rules)

    # Check each expected rule exists and print details for missing ones
    missing = []
    for rule in expected_rules:
        if rule not in actual_rules:
            missing.append(rule)
    assert not missing, (
        "Missing rules:\n" +
        "\n".join(
            f"Route: {r[0]}, Action: {r[1]}, Source: {r[2]}, Target: {r[3]}"
            for r in missing
        )
    )

    # Verbose check: print all rules and highlight any unexpected ones
    unexpected = [r for r in actual_rules if r not in expected_rules]
    if unexpected:
        print("Unexpected rules found in DB:")
        for r in unexpected:
            print(f"Route: {r[0]}, Action: {r[1]}, Source: {r[2]}, Target: {r[3]}")

    # Additionally, check that all fields are not None for each rule
    for r in rules:
        assert r["route_name"], f"Rule {r['id']} missing route assignment"
        assert r["action"], f"Rule {r['id']} missing action"
        assert r["source_zone"], f"Rule {r['id']} missing source zone"
        assert r["target_zone"], f"Rule {r['id']} missing target zone"


def test_company_seeded(db):
    cursor = db.execute("SELECT name FROM company")
    companies = {row["name"] for row in cursor.fetchall()}
    assert "AlpWolf GmbH" in companies

def test_warehouse_seeded(db):
    cursor = db.execute("SELECT name FROM warehouse")
    warehouses = {row["name"] for row in cursor.fetchall()}
    assert "Main Warehouse" in warehouses

def test_bom_and_bom_lines_seeded(db):
    cursor = db.execute("SELECT id, instructions FROM bom")
    boms = cursor.fetchall()
    assert boms, "No BOMs found"
    # Check at least one BOM line for each BOM
    for bom in boms:
        cursor = db.execute("SELECT COUNT(*) FROM bom_line WHERE bom_id = ?", (bom["id"],))
        count = cursor.fetchone()[0]
        assert count > 0, f"No BOM lines found for BOM {bom['id']}"

def test_currency_seeded(db):
    cursor = db.execute("SELECT code, symbol, name FROM currency")
    currencies = {row["code"]: (row["symbol"], row["name"]) for row in cursor.fetchall()}
    assert "EUR" in currencies and currencies["EUR"][0] == "€"
    assert "USD" in currencies and currencies["USD"][0] == "$"

def test_tax_seeded(db):
    cursor = db.execute("SELECT name, percent FROM tax")
    taxes = {row["name"]: row["percent"] for row in cursor.fetchall()}
    assert "Standard VAT" in taxes and taxes["Standard VAT"] == 19.0
    assert "Reduced VAT" in taxes and taxes["Reduced VAT"] == 7.0

def test_price_list_seeded(db):
    cursor = db.execute("SELECT name FROM price_list")
    price_lists = {row["name"] for row in cursor.fetchall()}
    assert "Default EUR" in price_lists

def test_all_items_in_price_list_item(db):
    # Get all items
    cursor = db.execute("SELECT id, name FROM item")
    items = cursor.fetchall()
    item_ids = {row["id"] for row in items}
    item_names = {row["id"]: row["name"] for row in items}

    # Get all price_list_item entries
    cursor = db.execute("SELECT item_id FROM price_list_item")
    pli_item_ids = {row["item_id"] for row in cursor.fetchall()}

    # Check every item has at least one price_list_item entry
    missing = [item_names[iid] for iid in item_ids if iid not in pli_item_ids]
    assert not missing, f"Missing price_list_item for items: {', '.join(missing)}"

####### TESTS FOR BUSINESS LOGIC #######

def test_sale_of_bom_item_creates_manufacturing_order_and_po(db):
    """
    Integration test:
    - Sells an item with a BOM (e.g. 'Kit Alpha')
    - Confirms the sale order
    - Ensures a manufacturing order (move with target zone ZON_PROD) is created
    - Ensures a purchase order (PO) is created for the MO
    - Ensures the PO has correct lines for BOM components
    """
    # Find an item with a BOM (assume 'Kit Alpha' exists and has a BOM)
    item_row = db.execute("""
        SELECT i.id, i.name FROM item i
        JOIN bom_line bl ON bl.bom_id = i.bom_id
        WHERE i.name = 'Kit Alpha'
        LIMIT 1
    """).fetchone()
    assert item_row, "No BOM item found (expected 'Kit Alpha')"
    item_id = item_row["id"]

    # Create a new sale order for this item
    db.execute("INSERT INTO sale_order (code, partner_id, status) VALUES ('ORD_BOM_2', 4, 'draft')")
    sale_order_id = db.execute("SELECT id FROM sale_order WHERE code='ORD_BOM_2'").fetchone()["id"]
    db.execute("INSERT INTO order_line (order_id, item_id, quantity, price) VALUES (?, ?, ?, ?)",
               (sale_order_id, item_id, 1, 100))
    db.commit()

    # Confirm the sale order
    db.execute("UPDATE sale_order SET status='confirmed' WHERE id=?", (sale_order_id,))
    db.commit()

    # Check that a trigger was created for this sale order
    trigger = db.execute("SELECT * FROM trigger WHERE origin_model='sale_order' AND origin_id=?", (sale_order_id,)).fetchone()
    assert trigger is not None, "No trigger created for BOM sale order confirmation"
    # print("Trigger: ", [trigger[key] for key in [
    #     "id",
    #     "origin_model",
    #     "origin_id",
    #     "trigger_type",
    #     "trigger_route_id",
    #     "trigger_item_id",
    #     "trigger_lot_id",
    #     "trigger_zone_id",
    #     "trigger_item_quantity",
    #     "status",
    #     "type",
    #     "created_at",
    # ]])
    # Check that a manufacturing move (to ZON_PROD) was created for the trigger
    mo = db.execute("""
        SELECT m.* FROM move m
        JOIN zone z ON m.target_id = z.id
        WHERE m.trigger_id=? AND z.code='ZON09'
    """, (trigger["id"],)).fetchone()
    assert mo is not None, "No selling move (to ZON09) created for BOM sale order"


def test_manufacturing_order_confirmation_creates_po_with_bom_lines(db):
    """
    Integration test:
    - Confirms a manufacturing order (MO)
    - Ensures a purchase order (PO) is created for the MO
    - Ensures the PO has correct lines for BOM components
    """
    # Find a manufacturing order (MO) that is not yet confirmed
    mo = db.execute("""
        SELECT * FROM manufacturing_order WHERE id=1
    """).fetchone()
    assert mo is not None, "No manufacturing order (MO) found to confirm"

    # Confirm the MO
    db.execute("UPDATE manufacturing_order SET status='confirmed' WHERE id=?", (mo["id"],))
    db.commit()
    # Check that purchase orders have been created for the MO (multiple POs possible if BOM lines have different vendors)
    po = db.execute("""
        SELECT * FROM purchase_order
    """,).fetchall()
    assert po, "No purchase order created for manufacturing order"

    # Check that the PO(s) have lines for all BOM components
    bom_lines = db.execute("""
        SELECT bl.item_id, bl.quantity
        FROM bom_line bl
        WHERE bl.bom_id = (SELECT bom_id FROM item WHERE id=?)
    """, (mo["item_id"],)).fetchall()

    # Gather all PO line items from all POs
    po_ids = [o["id"] for o in po]
    if not po_ids:
        pytest.fail("No purchase orders found for manufacturing order")
    placeholders = ",".join("?" for _ in po_ids)
    query = f"""
        SELECT pol.item_id, pol.quantity
        FROM purchase_order_line pol
        WHERE pol.purchase_order_id IN ({placeholders})
    """
    po_lines = db.execute(query, po_ids).fetchall()
    po_line_items = {(row["item_id"], row["quantity"]) for row in po_lines}

    # print("BOM lines:", [(bl["item_id"], bl["quantity"]) for bl in bom_lines])
    # print("POs:", [(o["code"], o["status"]) for o in po])
    # print("PO lines:", po_line_items)
    for bl in bom_lines:
        assert (bl["item_id"], bl["quantity"]) in po_line_items, (
            f"PO(s) missing line for BOM component item_id={bl['item_id']} qty={bl['quantity']} -- got {po_line_items}"
        )

def test_sale_order_confirmation_creates_trigger_and_move(db):
    # Confirm the sale order
    db.execute("UPDATE sale_order SET status='confirmed' WHERE id=1")
    db.commit()

    # Check that a trigger was created
    trigger = db.execute("SELECT * FROM trigger WHERE origin_model='sale_order' AND origin_id=1").fetchone()
    assert trigger is not None, "No trigger created for sale order confirmation"

    # Check that a move was created for the trigger
    move = db.execute("SELECT * FROM move WHERE trigger_id=?", (trigger["id"],)).fetchone()
    assert move is not None, "No move created for trigger"

def test_stock_adjustment_resolves_intervention(db):
    # Simulate a move that needs intervention
    db.execute("UPDATE sale_order SET status='confirmed' WHERE id=1")
    db.commit()
    move = db.execute("SELECT * FROM move WHERE status='intervene'").fetchone()
    assert move is not None, "No move in intervene status"

    # Add stock to resolve intervention
    db.execute("INSERT INTO stock_adjustment (item_id, location_id, delta, reason) VALUES (?, ?, ?, ?)",
               (move["item_id"], 12, 100, "Test stock increase"))
    db.commit()

    # Check that the move is now confirmed
    move2 = db.execute("SELECT * FROM move WHERE id=? AND status='confirmed'", (move["id"],)).fetchone()
    assert move2 is not None, "Move was not confirmed after stock adjustment"

def test_purchase_order_confirmation_creates_supply_trigger(db):
    db.execute("UPDATE purchase_order SET status='confirmed' WHERE id=1")
    db.commit()
    trigger = db.execute("SELECT * FROM trigger WHERE origin_model='purchase_order' AND origin_id=1").fetchone()
    assert trigger is not None, "No supply trigger created for purchase order confirmation"

def test_sale_order_of_buy_item_creates_purchase_order_when_out_of_stock(db):
    """
    Integration test:
    - Sells an item that is purchased from a vendor (not manufactured, e.g. 'Item Small A')
    - Ensures that if the item is out of stock, confirming the sale order creates a purchase order
    - Ensures the purchase order has the correct item and quantity (>10)
    """
    # Find a buyable item (not a BOM, e.g. 'Item Small A')
    item_row = db.execute("""
        SELECT i.id, i.name FROM item i
        LEFT JOIN bom_line bl ON bl.bom_id = i.bom_id
        WHERE i.name = 'Item Small A' AND bl.id IS NULL
        LIMIT 1
    """).fetchone()
    assert item_row, "No buyable item found (expected 'Item Small A')"
    item_id = item_row["id"]

    # Remove all stock for this item to simulate out-of-stock
    db.execute("DELETE FROM stock WHERE item_id=?", (item_id,))
    db.commit()

    # Create a new sale order for this item with quantity > 10
    db.execute("INSERT INTO sale_order (code, partner_id, status) VALUES ('ORD_BUY_1', 4, 'draft')")
    sale_order_id = db.execute("SELECT id FROM sale_order WHERE code='ORD_BUY_1'").fetchone()["id"]
    db.execute("INSERT INTO order_line (order_id, item_id, quantity, price) VALUES (?, ?, ?, ?)",
               (sale_order_id, item_id, 15, 42))
    db.commit()

    # Confirm the sale order
    db.execute("UPDATE sale_order SET status='confirmed' WHERE id=?", (sale_order_id,))
    db.commit()

    # Find the purchase order(s) created for this sale order by matching the origin field
    po = db.execute("""
        SELECT * FROM purchase_order
        WHERE origin LIKE '%' || ? || '%'
        ORDER BY id DESC
    """, (sale_order_id,)).fetchone()
    assert po is not None, "No purchase order created for out-of-stock buy item sale order"

    # Check that the PO has a line for the correct item and quantity
    po_lines = db.execute("""
        SELECT pol.item_id, pol.quantity
        FROM purchase_order_line pol
        WHERE pol.purchase_order_id = ?
    """, (po["id"],)).fetchall()
    assert po_lines, "No purchase order line created"

    found = False
    for pol in po_lines:
        if pol["item_id"] == item_id and pol["quantity"] == 15:
            found = True
            break
    assert found, f"PO line for item_id={item_id} with quantity=15 not found in PO lines: {[(row['item_id'], row['quantity']) for row in po_lines]}"


def test_fulfillment_flow_until_sale_order_done(db):
    """
    Integration test:
    - Confirms a sale order for a buyable item.
    - Iteratively sets all 'confirmed' move lines to 'done' until no more are found.
    - Asserts the sale order is fully delivered at the end.
    """
    # # Create a new sale order for a buyable item (not a BOM)
    # item_row = db.execute("""
    #     SELECT i.id FROM item i
    #     LEFT JOIN bom_line bl ON bl.bom_id = i.bom_id
    #     WHERE i.name = 'Item Small A' AND bl.id IS NULL
    #     LIMIT 1
    # """).fetchone()
    # assert item_row, "No buyable item found (expected 'Item Small A')"
    # item_id = item_row["id"]

    # db.execute("INSERT INTO sale_order (code, partner_id, status) VALUES ('ORD_FULFILL', 4, 'draft')")
    # sale_order_id = db.execute("SELECT id FROM sale_order WHERE code='ORD_FULFILL'").fetchone()["id"]
    # db.execute("INSERT INTO order_line (order_id, item_id, quantity, price) VALUES (?, ?, ?, ?)",
    #            (sale_order_id, item_id, 5, 42))
    # db.commit()

    db.execute("UPDATE purchase_order SET status='confirmed'",)
    db.commit()

    db.execute("UPDATE manufacturing_order SET status='done'",)
    db.commit()

    # Fulfillment loop: set all confirmed move lines to done until none remain
    while True:
        move_lines = db.execute("""
            SELECT id FROM move_line
            WHERE status = 'assigned' AND done_quantity < quantity
        """).fetchall()
        if not move_lines:
            break
        for ml in move_lines:
            db.execute("UPDATE move_line SET status='done', done_quantity=quantity WHERE id=?", (ml["id"],))
        db.commit()
        print(f"Set {len(move_lines)} move lines to done")

    # After all move lines are done, check that the sale order is fully delivered
    cursor = db.execute("""
        SELECT
            ol.item_id,
            ol.quantity AS ordered_qty,
            IFNULL(SUM(ml.done_quantity), 0) AS delivered_qty
        FROM order_line ol
        LEFT JOIN trigger t ON t.origin_model = 'sale_order' AND t.origin_id = ol.order_id AND t.trigger_item_id = ol.item_id
        LEFT JOIN move m ON m.trigger_id = t.id
        LEFT JOIN move_line ml ON ml.move_id = m.id
        WHERE ol.order_id IN (SELECT id FROM sale_order)
        GROUP BY ol.item_id, ol.quantity
        HAVING delivered_qty < ordered_qty;
    """,)
    assert cursor.fetchone() is None, "Sale order not fully delivered after all move lines set to done"


# def test_expected_moves_and_move_lines_created(db):
#     """
#     Integration test:
#     - Ensures all expected moves are created after confirming a sale order for a BOM item.
#     - Ensures move lines exist for fulfillment (i.e., for picking, manufacturing, and delivery).
#     """
#     # Create and confirm a sale order for a BOM item (e.g. 'Kit Alpha')
#     item_row = db.execute("""
#         SELECT i.id FROM item i
#         JOIN bom_line bl ON bl.bom_id = i.bom_id
#         WHERE i.name = 'Kit Alpha'
#         LIMIT 1
#     """).fetchone()
#     assert item_row, "No BOM item found (expected 'Kit Alpha')"
#     item_id = item_row["id"]

#     db.execute("INSERT INTO sale_order (code, partner_id, status) VALUES ('ORD_BOM_MOVES', 4, 'draft')")
#     sale_order_id = db.execute("SELECT id FROM sale_order WHERE code='ORD_BOM_MOVES'").fetchone()["id"]
#     db.execute("INSERT INTO order_line (order_id, item_id, quantity, price) VALUES (?, ?, ?, ?)",
#                (sale_order_id, item_id, 2, 100))
#     db.commit()

#     db.execute("UPDATE sale_order SET status='confirmed' WHERE id=?", (sale_order_id,))
#     db.commit()

#     # Collect all moves related to this sale order (via triggers)
#     triggers = db.execute("""
#         SELECT id FROM trigger WHERE origin_model='sale_order' AND origin_id=?
#     """, (sale_order_id,)).fetchall()
#     trigger_ids = [row["id"] for row in triggers]
#     assert trigger_ids, "No triggers created for sale order"

#     # Find all moves created by these triggers
#     placeholders = ",".join("?" for _ in trigger_ids)
#     moves = db.execute(f"""
#         SELECT * FROM move WHERE trigger_id IN ({placeholders})
#     """, trigger_ids).fetchall()
#     assert moves, "No moves created for sale order triggers"

#     # Check that expected move types exist (e.g., picking, manufacturing, delivery)
#     move_types = {row["type"] for row in moves if "type" in row.keys()}
#     assert "pick" in move_types or "picking" in move_types, "No picking move created"
#     assert "manufacture" in move_types or "manufacturing" in move_types, "No manufacturing move created"
#     assert "delivery" in move_types, "No delivery move created"

#     # Check that there are move lines for fulfillment for these moves
#     move_ids = [row["id"] for row in moves]
#     placeholders = ",".join("?" for _ in move_ids)
#     move_lines = db.execute(f"""
#         SELECT * FROM move_line WHERE move_id IN ({placeholders})
#     """, move_ids).fetchall()
#     assert move_lines, "No move lines created for fulfillment"

#     # Optionally, check that move lines cover all items in the BOM
#     bom_lines = db.execute("""
#         SELECT bl.item_id, bl.quantity
#         FROM bom_line bl
#         WHERE bl.bom_id = (SELECT bom_id FROM item WHERE id=?)
#     """, (item_id,)).fetchall()
#     bom_item_ids = {row["item_id"] for row in bom_lines}
#     move_line_item_ids = {row["item_id"] for row in move_lines}
#     missing = bom_item_ids - move_line_item_ids
#     assert not missing, f"Move lines missing for BOM items: {missing}"
