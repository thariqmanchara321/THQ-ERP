# THQ ERP v4.8.2 — Pricing & Product Identification

## Added
- Retail, Wholesale, Dealer and Contractor price lists.
- Customer-assigned price lists and customer-specific product prices.
- Quantity-break pricing per product + sales unit.
- Server-authoritative sale pricing and pricing provenance on sale lines.
- Multiple product identifiers: barcode, QR, manufacturer, supplier, internal and alternate SKU.
- Generated EAN-style THQ barcodes and generated THQ QR identifiers.
- Unified product lookup/search across SKU and active identifiers, with legacy barcode/part-number compatibility.
- Barcode/QR label templates and label printing from Client Product Details.
- Client Pricing workspace and Codes & Labels product workspace.
- POS and Client price preview/re-resolution when customer, quantity or sale unit changes.

## Hardened
- Explicit `use_build_context_synchronously` lint remains enabled in all Flutter apps.
- Known Client/POS refresh paths guard `BuildContext` with `mounted` after async gaps.
- Release validation treats analyzer warnings/infos as fatal on Windows.
- Archiving/changing a primary identifier synchronizes the legacy `barcode`/`part_number` compatibility fields.
- Sale prices are resolved again in PostgreSQL before posting, so client-side price manipulation cannot bypass configured pricing.

## Database
- 130 — Pricing Engine
- 131 — Product Identification
- 132 — Label Printing
- 133 — Authoritative Sale Pricing
- 134 — Release Contract

## Analyzer / lifecycle clean-up
- Release gate uses `flutter analyze --fatal-infos --fatal-warnings` for erp_core, Admin, Client and POS.
- Fixed async BuildContext lifecycle guards in refresh/navigation paths; `use_build_context_synchronously` remains explicitly enabled.
- Fixed `prefer_final_fields` in Inventory Movement History.
- Removed unused `erp_core` import from Pricing.
- Replaced unnecessary multi-underscore callback parameters.
- Added braces around unit-default reset loops.
- Replaced deprecated `DropdownButtonFormField.value` usage in v4.8.1 unit selectors with `initialValue`.
- Dependency upgrades are intentionally not bundled into v4.8.2; newer incompatible package versions are reviewed separately to avoid feature-release regressions.
