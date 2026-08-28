# FLEXI ERP V3 FEATURE MATRIX

## Identity & security
- Username/password visible login: implemented in Admin, Client, POS.
- Username uniqueness: global, case-insensitive, minimum 4 chars.
- Password creation/reset: minimum 8 chars.
- Auth secrets: Flutter keeps publishable key only; service role remains Edge Function-side.

## Tracking
- Existing UUIDs remain canonical IDs.
- Added readable tenant tracking codes to supported product/location/customer/supplier/purchase/sale/expense tables.
- Codes are immutable after migration 016.
- Tracking lookup screen available from Logs.

## Logs / auditing
- Unhandled Flutter errors captured from Client/Admin/POS when authenticated.
- Tenant error log viewer.
- Platform-wide error viewer.
- User-reported Issue entry from Client/POS.
- Audited expense edits and safe sale metadata edits with before/after data.
- Business Activity Log from Logs.

## Standalone POS
- Separate app: `apps/pos_app`.
- Username login + business selection.
- Product search/cart and selected-product details.
- Quick cash tender chips: Exact and common ₹ increments.
- Customers, products, suppliers, purchases and expenses available as separate POS navigation destinations when modules are enabled.
- Checkout reuses existing `sales_create` engine.

## Sales / expenses
- Sales product autocomplete on first letters/name/SKU/part/barcode.
- Privileged safe sale metadata edits.
- Financial sale lines remain protected after posting.
- Authorized expense editing with audit history.

## Invoices
- Admin editable A4/80mm templates.
- Four seeded designs.
- Sample logo selection metadata.
- Per-tenant A4 and 80mm template assignment.
- Client A4/80mm invoice preview.
- Business legal name/GSTIN/phone/email/address/state settings.
- Direct PDF/OS printer spooler: next print phase, not claimed complete in V3.

## Bulk import
- Products via protected bulk RPC reusing `inventory_create_product`.
- Customers via existing protected `customers_create`.
- Suppliers via existing protected `suppliers_create`.
- CSV parser supports quoted fields/commas.

## Payments / analytics
- Pending customer receivables.
- Pending supplier payables.
- Open sale/purchase detail to record payment using existing payment RPCs.
- Top-selling products.
- Top customers.
- Daily sales trend visual.

## UI
- Material 3 themes.
- Modern metric cards, dashboard trend bars and ranking cards.
- Separate role/module-aware POS navigation.
