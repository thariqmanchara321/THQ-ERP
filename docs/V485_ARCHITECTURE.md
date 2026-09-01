# v4.8.5 Warehouse & Transfers architecture

## Stock authority
`location_stock_balances` / `location_stock_movements` remain the physical stock authority. Serial and batch tables are traceability mirrors that must reconcile to the physical ledger.

## Warehouse model
No new warehouse master is introduced. A warehouse is a `business_location` with `hierarchy_role='warehouse'` or `location_type='warehouse'`.

## Transfer state machine
- `requested`: aggregate + tracked units reserved at source.
- `approved`: reservation remains; movement authorized.
- `in_transit`: dispatch removed quantity from source; serial/batch allocations are physically in transit.
- `received`: destination location stock and tracked registries updated.
- `rejected` / `cancelled`: pre-dispatch reservations released.

The legacy `dispatched` status remains readable for historical compatibility and is presented as `in_transit` by v4.8.5 list/detail APIs.

## Tracking
Serials use `reserved_transfer_id` while reserved. Dispatch clears the reservation and changes status to `in_transit`; receive changes status to `in_stock` at the destination.

Batch location balances carry `reserved_quantity`. Customer FEFO sale logic uses `quantity - reserved_quantity`. Dispatch consumes both quantity and reservation from source; receive adds saleable quantity at destination.

## Counts
Physical count is trace-aware. The count is blocked while aggregate transfer reservations exist on the product/location. Serial counts reconcile the exact set of serial identities. Batch counts reconcile exact batch saleable/damaged balances. Aggregate stock is adjusted only by the resulting physical quantity delta.
