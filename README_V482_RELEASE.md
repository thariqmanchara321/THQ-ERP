# THQ ERP v4.8.2 — Pricing & Product Identification

THQ ERP v4.8.2 extends the v4.8 inventory/unit foundation with a server-authoritative pricing engine and a unified product-identification/label system.

## Release versions
- Admin: `4.8.2+10`
- Client: `4.8.2+10`
- POS: `4.8.2+10`
- erp_core: `4.8.2`
- Database migration: `134`
- THQ API: `v1`

## Pricing precedence
1. Customer-specific quantity price
2. Customer assigned/default Price List quantity rule
3. Product Unit sale price
4. Store/location price
5. Product retail/base selling price

The Client/POS UI previews the result, but PostgreSQL resolves the price again when a sale is posted.

## Product identification
A variant can have multiple active identifiers: barcode, QR, manufacturer code, supplier code, internal code and alternate SKU. Search/scan uses SKU plus active identifiers. Legacy barcode/part-number fields remain synchronized for compatibility.

## Label printing
Product Details → Codes, Barcode & Labels supports generated/manual identifiers and default thermal/A4 label templates. Barcode and QR labels can include business, product, price, SKU and code text.

## Upgrade
If the current database is migration 129, apply only migrations 130–134 or `backend/upgrade_from_129/THQ_ERP_V482_UPGRADE_FROM_129.sql`, then run `V482_POST_UPGRADE_CHECK.sql` and deploy the updated `thq-api` Edge Function.

## Runtime release gate
The source contains `tools/validate_v482_windows.ps1`. Run it on a Flutter-capable Windows development machine. The script treats analyzer infos/warnings as fatal so lifecycle lints such as `use_build_context_synchronously` block release rather than being ignored.

## Analyzer quality gate
Run `tools/validate_v482_windows.ps1` before accepting the release. The script runs `flutter analyze --fatal-infos --fatal-warnings`, so analyzer infos such as async BuildContext lifecycle issues, deprecated members and release lints fail the gate instead of being ignored.

The `flutter pub get` message about newer packages is informational. v4.8.2 deliberately keeps the tested dependency constraints; dependency upgrades should be handled as a separate controlled maintenance pass.
