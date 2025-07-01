import sqlite3
import pytest
import os

@pytest.fixture
def db():
    # Load schema and seed data
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    with open("schema.sql", encoding="utf-8") as f:
        conn.executescript(f.read())
    yield conn
    conn.close()

def test_sale_order_confirmation_creates_trigger_and_move(db):
    # Confirm the sale order
    db.execute("UPDATE sale_order SET status='confirmed' WHERE code='ORD0001'")
    db.commit()

    # Check that a trigger was created
    trigger = db.execute("SELECT * FROM trigger WHERE origin_model='sale_order' AND origin_id=1").fetchone()
    assert trigger is not None, "No trigger created for sale order confirmation"

    # Check that a move was created for the trigger
    move = db.execute("SELECT * FROM move WHERE trigger_id=?", (trigger["id"],)).fetchone()
    assert move is not None, "No move created for trigger"

def test_stock_adjustment_resolves_intervention(db):
    # Simulate a move that needs intervention
    db.execute("UPDATE sale_order SET status='confirmed' WHERE code='ORD0001'")
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
    db.execute("UPDATE purchase_order SET status='confirmed' WHERE code='PO0001'")
    db.commit()
    trigger = db.execute("SELECT * FROM trigger WHERE origin_model='purchase_order' AND origin_id=(SELECT id FROM purchase_order WHERE code='PO0001')").fetchone()
    assert trigger is not None, "No supply trigger created for purchase order confirmation"