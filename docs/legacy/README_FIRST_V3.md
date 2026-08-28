# FLEXI ERP PLATFORM V3 — READ THIS FIRST

This V3 bundle upgrades Flexi ERP without replacing the working Inventory, Purchase, Sales, stock-ledger, moving-average-cost, customer-credit, or payment transaction engines.

## Apps

- `apps/admin_panel` — platform control centre (web)
- `apps/client_app` — business ERP (Windows/Android)
- `apps/pos_app` — standalone Flexi POS (Windows/Android)

POS is no longer embedded in the normal Client ERP navigation.

## Major V3 additions

- Username + password login in Admin, Client, and POS.
- Case-insensitive globally unique usernames, minimum 4 characters.
- Password creation/reset remains minimum 8 characters.
- Human-readable immutable tracking codes in addition to UUID primary keys.
- Application error/issue logs and business audit history.
- Tracking-code lookup.
- Standalone POS app with selected-product details and quick cash tender chips.
- POS access to Products, Customers, Suppliers, Purchases, Expenses, and Logs when the tenant has those modules.
- Privileged safe sale metadata editing + fully audited expense editing.
- A4 and 80mm invoice template management, sample designs and sample logo keys.
- Business GST/phone/address invoice settings and invoice previews.
- Bulk product/customer/supplier CSV imports.
- Pending receivables/payables centre with receipt/payment entry through existing detail screens.
- Top-selling products, top customers, and sales-trend dashboard analytics.
- Sales product autocomplete by name/SKU/part number/barcode.
- Material 3 UI polish and visual dashboard cards/charts.

## Critical upgrade order

You already ran migrations 001–009. Do NOT replace the running apps first, because V3 login depends on the new database mapping and Edge Function.

1. Back up the current working project/database.
2. Extract this V3 bundle somewhere temporary.
3. Run migrations `010` through `016`, one at a time.
4. Immediately after migration `010`, record the generated usernames using the query in `docs/BACKEND_V3_STEPS.md`.
5. Deploy Edge Function `username-login` with JWT verification OFF (`--no-verify-jwt`).
6. Deploy Edge Function `manage-business-users-v3` with normal JWT verification ON.
7. KEEP the existing deployed `manage-business-users` function. V3 intentionally wraps it.
8. Replace the three app folders in your main project.
9. Run `dart fix --apply`, `dart format lib`, and `flutter analyze` in Admin, Client, and POS.
10. Sign in using the generated username + the SAME existing password.
11. Test Admin → Client → POS in that order.

Full steps are in `docs/BACKEND_V3_STEPS.md`.

## Important transaction rule

A posted sale is an accounting + stock event. V3 therefore does not silently rewrite quantity, price, tax, or item lines after posting. Users with `sales.edit` can safely change customer, due date, and notes, and the change is audited. A controlled void/recreate workflow for financial corrections should be added only after the exact live Sales SQL functions are exported and verified.

Expenses can be edited by authorized users and every before/after version is recorded in the business audit log.

## Invoice status

V3 includes editable template definitions, tenant assignment, and A4/80mm invoice previews with business legal name, GSTIN, phone and address settings. Direct PDF generation / Windows printer / 80mm thermal spooler integration is intentionally left for the next print-specific phase after V3 validates cleanly.
