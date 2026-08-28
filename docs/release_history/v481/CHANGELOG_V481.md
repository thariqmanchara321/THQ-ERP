# THQ ERP v4.8.1 — Inventory & Unit Engine

## Added
- Inventory unit master and standard seeded units.
- Product unit conversion configuration.
- Canonical/base inventory quantities with entered/display unit metadata.
- Movement before/after balances and richer source metadata.
- Inventory Movement Ledger UI.
- Unit-aware sale/purchase wrappers and unit-aware return wrappers.
- POS center-workspace quantity/unit editor.
- Optional cutting charge in POS and Client sales.
- Generalized operational location types: Store, Warehouse, Production, Office and Scrap.
- THQ API v1 resources: units, product-units, inventory-movements.

## Safety / integrity
- Base unit changes are blocked after stock/history exists.
- Fractional and quantity-step rules are enforced in the backend as well as UI.
- Returns convert the entered document unit back to canonical base quantity before stock/accounting reversal.
- Existing hardened v4.7/v4.8 transaction engines remain authoritative.
