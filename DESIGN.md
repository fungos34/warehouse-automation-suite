# Warehouse Management System

By JOHANNES WAGNER

Video overview: <URL HERE>

## Purpose
The Warehouse Management System (WMS) is designed to track and manage goods stored in a warehouse, record incoming and outgoing shipments, and monitor stock levels across multiple locations. This system aims to improve inventory accuracy and streamline operations.

## Scope
This system includes:
- Managing item master data
- Tracking items across warehouse locations
- Recording stock levels
- Managing suppliers and shipments
- Assigning employees to track item movements

## Entity Relationship Diagram
![ERD](erd.png)

## Entities & Relationships

- **items**: Unique products tracked by SKU and description.
- **locations**: Physical storage units (aisle, shelf).
- **stock**: Quantity of a given item at a location.
- **suppliers**: Provide items to the warehouse.
- **shipments**: Represent incoming or outgoing movements of items.
- **shipment_items**: Association table between shipments and items.
- **employees**: Staff responsible for warehouse operations.

Relationships:
- One `item` can be in many `locations`
- One `shipment` can have many `shipment_items`
- One `supplier` can provide many `items`
- One `employee` can handle many `shipments`

## Optimizations
- Composite indexes on `stock(item_id, location_id)`
- Indexes on `shipment_id`, `supplier_id`, and `employee_id` for fast lookups

## Limitations
- No user authentication
- Doesn't handle partial shipment returns
- Only supports a single warehouse (no multi-warehouse handling)

## Author
- Name: Johannes Wagner
- GitHub: fungos34
- edX Username: johannes_34
- Country: Austria
