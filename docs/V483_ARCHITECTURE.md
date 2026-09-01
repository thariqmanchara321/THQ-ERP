# v4.8.3 traceability architecture

## Authority model
The existing inventory engine remains the quantity/accounting authority:

`sale/purchase -> existing stock posting -> location_stock_balances/location_stock_movements`

v4.8.3 adds a parallel physical trace layer:

`product policy -> serial/batch registry -> per-location batch/serial state -> trace events -> warranty`

Tracked posting runs in the same PostgreSQL transaction as the existing posting wrapper. If trace validation/allocation fails, the parent sale/purchase rolls back too.

## Tracking modes
- `none`: existing ERP behavior.
- `serial`: one unique serial per whole base unit.
- `batch`: quantity is assigned to one or more batches; sales use FEFO unless explicit batch allocation is supplied by an API caller.

## Reconciliation
For tracked stock at a store:
- serial mode: count of `in_stock` serials at the location must equal stock quantity;
- batch mode: sum of batch balances at the location must equal stock quantity.

Existing v4.8.2 stock is adopted through an opening registration that does not change stock quantity. It only creates trace records matching the already-posted ledger quantity.

## Warranty
Warranty policy is product-level and requires serial or batch tracking. A sale creates warranty records linked to the customer, sale, sale line and serial/batch. Expiry is calculated from sale date plus configured months/days.

## Security
Public v4.8.3 operations are `SECURITY DEFINER` RPCs with tenant permission and ERP location-scope checks. Trace tables are not granted direct client read/write access.
