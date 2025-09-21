# Warehouse Management System

By JOHANNES WAGNER

Video overview: <URL HERE>

## Purpose

The Warehouse Management System (WMS) is a comprehensive solution for automating, tracking, and optimizing all physical and digital flows in a modern warehouse. It is designed to support multi-zone, multi-location, and multi-partner operations, including inventory management, order fulfillment, manufacturing, returns, service bookings, and logistics. The system enables accurate stock control, traceability of lots and items, and seamless integration of business processes from quotation to shipping and returns.

A key goal is to enable warehouse automation through the use of **routes** and **rules**. These concepts allow the system to dynamically determine the best path for goods and tasks, automate decision-making for picking, packing, manufacturing, and returns, and reduce manual intervention. Unlike traditional decision tables, which are static mappings of conditions to actions, routes and rules in this system are flexible, context-aware, and can be extended to support complex workflows and triggers.

## Scope

This WMS supports the following core workflows and features:

- **Item and Lot Management:** Track products, digital goods, and services by SKU, barcode, and lot number, including BOM (Bill of Materials) for kits and assemblies.
- **Multi-location and Multi-zone Stock Tracking:** Manage stock and reserved quantities across shelves, zones, and warehouses, with support for overstock, hot picking, production, and packing areas.
- **Order and Fulfillment Flows:** Handle quotations, sale orders, purchase orders, transfer orders, and returns, with full traceability from customer request to shipment and after-sales processes.
- **Manufacturing and Unbuild Flows:** Support production and disassembly of items, including BOM consumption and finished goods creation.
- **Service and Subscription Management:** Enable booking of services, time slots, and subscriptions, with automated scheduling and exception handling.
- **Partner and Company Management:** Manage vendors, customers, carriers, employees, and companies, with automatic location assignment and multi-language support.
- **Tax, Customs, and Pricing:** Integrate country-specific taxes, customs duties, price lists, discounts, and currency conversions.
- **Automation via Routes and Rules:** Automate warehouse flows using configurable routes and rules, enabling dynamic fulfillment, supply, and intervention handling.
- **Packing, Dropshipping, and Logistics:** Support carton selection, packing policies, dropshipping, and carrier assignment.
- **Debugging and Intervention:** Track unresolved moves and interventions, with automated resolution based on stock and triggers.

The system is designed to be extensible, supporting additional workflows such as advanced analytics, multi-warehouse operations, and integration with external systems.

## Entity Relationship Diagram

![Warehouse Management System](/docs/warehouse_mermaid_erd_hierachical.svg)

## Entities & Relationships

The database schema is composed of over 60 tables, supporting a rich set of relationships. Key entities include:

- **item, lot, bom, bom_line:** Represent products, digital goods, lots/batches, and their bill of materials.
- **stock, location, zone, warehouse:** Track quantities and movements of items across physical locations and logical zones within warehouses.
- **partner, company, user:** Manage business partners, companies, and users, with roles and multi-language support.
- **quotation, quotation_line, sale_order, order_line, purchase_order, purchase_order_line, transfer_order, transfer_order_line, return_order, return_line:** Model the full order lifecycle, from quotation to fulfillment, returns, and transfers.
- **service_booking, service_window, service_hours, service_exception, subscription, subscription_line:** Enable service and subscription management, including booking, scheduling, and exceptions.
- **tax, hs_code, hs_country_tax, item_hs_country, currency, discount, price_list, price_list_item:** Support pricing, taxation, customs, and currency conversion.
- **move, move_line, picking, stock_adjustment, intervention, debug_log:** Track all physical and logical movements, adjustments, and interventions in the warehouse.
- **packing_policy, packing_question, dropshipping_policy, dropshipping_question, carrier_label:** Manage packing, dropshipping, and logistics operations.
- **route, rule, trigger, rule_trigger:** Enable warehouse automation by defining routes (paths between zones), rules (actions and conditions), and triggers (events that initiate actions).

**Relationships are emphasized throughout the schema:**
- Items and lots are linked to BOMs, zones, and locations.
- Orders and quotations are linked to partners, items, and pricing.
- Moves and pickings are linked to zones, locations, and triggers.
- Rules and routes define the logic for automated flows, connecting zones and actions.
- Packing and dropshipping policies are linked to partners, items, and carriers.

## Optimizations

The schema is optimized for performance and integrity:

- **Indexes:** All foreign keys, unique columns, and frequently queried fields are indexed, including composite indexes for multi-column lookups (e.g., stock(item_id, location_id, lot_id)).
- **Views:** Common queries are supported by views (e.g., stock_by_location, warehouse_stock_view, sale_order_item_view, move_and_lines_by_origin), enabling fast reporting and analytics.
- **Triggers:** Automated triggers handle stock adjustments, order confirmations, manufacturing and unbuild flows, partner location creation, and intervention resolution.
- **Constraints:** Unique, not null, and check constraints enforce data integrity and business rules.
- **Seed Data:** The schema includes seed data for zones, locations, units, currencies, languages, taxes, partners, companies, items, and rules, enabling immediate testing and demonstration.

## Limitations

While the WMS is highly extensible and covers most warehouse workflows, there are some limitations:

- **No user authentication or access control** is implemented at the database level.
- **Multi-warehouse support** is limited; the schema is designed for a single warehouse but can be extended.
- **Partial shipment returns** and advanced fulfillment scenarios may require additional logic.
- **External system integration** (e.g., ERP, shipping APIs) is not included but can be added.
- **Decision tables** are not used; instead, automation is achieved via routes and rules, which are more flexible but may require more configuration for complex scenarios.
- **Advanced analytics and reporting** are not included but can be built on top of the existing views and indexes.

## Author

- Name: Johannes Wagner
- GitHub: fungos34
- edX Username: johannes_34
- Country: Austria
