# THQ ERP v4.8.1 Inventory Architecture

## Canonical stock model
Each product variant has one base inventory unit. `location_stock_balances.quantity` and the proven transaction engine continue to operate in base quantity.

Alternate units are product-specific conversion rules:

`entered quantity × conversion_to_base = canonical/base quantity`

Example: 2 Coil × 90 = 180 Meter.

## Movement ledger
`location_stock_movements` remains the authoritative movement history and is enriched with entered/display quantity, base quantity delta, unit, conversion, balance before/after, source line and metadata. This avoids creating a second competing inventory ledger.

## Documents
Sale/purchase item quantity columns remain canonical base quantities for inventory/accounting compatibility. v4.8.1 stores the original entered unit/quantity/unit price or cost alongside them so receipts/invoices retain business meaning.

## Returns
Return UI quantities use the original entered unit. v4.8.1 converts them back to base quantity before calling the proven return engine, then preserves entered-unit metadata on the return.

## Location model
Existing `business_locations` is generalized with production/office/scrap types. Production is a location/operational area, not a POS terminal.
