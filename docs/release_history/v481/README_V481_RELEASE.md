# THQ ERP v4.8.1 — Inventory & Unit Engine

This release upgrades THQ ERP 4.8.0 / migration 124 to the first generalized inventory-and-unit foundation needed for retail, electrical/hardware, wholesale, warehouse and later manufacturing workflows.

## Versions
- THQ Admin: 4.8.1+9
- THQ Client: 4.8.1+9
- THQ POS: 4.8.1+9
- erp_core: 4.8.1
- Database migration: 129
- THQ API: v1

## Core additions
- Universal enriched inventory movement ledger using canonical/base quantities.
- Standard and custom units.
- Product-specific purchase/sale units and conversion-to-base rules.
- Piece / Meter / KG / Liter / Box / Carton / Coil / Roll / Bundle / Set / Pair / Dozen and related units.
- Decimal and variable-quantity validation.
- Optional cutting/partial-quantity charge in POS and Client sales.
- Unit-aware sales, purchases, sales returns and purchase returns.
- Transaction documents preserve entered quantity/unit/price while inventory stays in base quantity.
- Inventory Movement Ledger UI in Client.
- Store / Warehouse / Production / Office / Scrap location types.
- THQ API v1 resources for units, product units and inventory movements.

## Important inventory rule
Stock is stored in one canonical base unit per product variant. Alternate sale/purchase units convert into that base unit. Once a variant has stock/history, its base unit cannot be changed directly.

Example: Cable base unit = Meter; 1 Coil = 90 Meter. Purchasing 10 Coil posts +900 Meter. Selling 2 Coil posts -180 Meter while the invoice still shows 2 Coil.

## Upgrade
If the current database is migration 124, apply only migrations 125–129, in order, or run `backend/THQ_ERP_V481_UPGRADE_FROM_124.sql`.

After upgrade run `backend/upgrade_from_124/V481_POST_UPGRADE_CHECK.sql`.

## Edge Function
Redeploy `thq-api` because v4.8.1 adds API routes for units/product-units/inventory-movements.

## Runtime validation
On Windows run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\validate_v481_windows.ps1
```

Add `-Build` to also create release builds.

Static/source validation in the release package is not a substitute for applying migrations to staging and running Flutter analyze/tests/builds.
