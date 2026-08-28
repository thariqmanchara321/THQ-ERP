# Flexi ERP V3.1 changes

## Identity and security
- Username + password login for Admin, Client and POS.
- Global unique usernames, minimum 4 characters.
- Existing users receive a username alias while keeping their existing Auth password.
- New users use a hidden Auth email internally; the user works only with the username.
- New/reset account passwords require 8+ characters.
- Client/POS require one-time device activation before login.
- Device secrets are stored using `flutter_secure_storage`, never in Supabase tables as plaintext.
- No service-role/secret key is placed in Flutter.

## Tracking
- Immutable business code.
- Readable tracking IDs for products, variants when tenant-scoped, inventory locations, customers, suppliers, purchases, sales and expenses.
- Readable IDs for business locations, devices, production recipes/runs, service vehicles/jobs, restaurant tables/orders/KOTs.
- Tracking lookup screen resolves readable codes back to records.

## Multi-store / multi-POS
- Child stores/locations with parent relationship, GSTIN, phone/address and invoice prefix.
- Multiple registered Client/POS systems per location.
- 24-hour one-time system activation codes issued by Admin.
- Devices can be revoked centrally.
- Sales, purchases and expenses are tagged with the creating branch/device.
- Per-location and merged business summaries.
- Branch-local printable document numbers in addition to the original ERP document number.

## Separate POS
- POS removed from the Client ERP menu.
- New `apps/pos_app` with its own Android/Windows application identity.
- Product search/barcode/SKU/part-number lookup.
- Selected product details and stock context.
- Quick cash controls: Exact, +10, +50, +100, +200, +500, +1000, +2000 and Clear.
- Customer selection and normal payment methods.
- Access to Products, Customers, Suppliers, Purchases, Expenses and Logs when those modules are enabled.
- Restaurant workspace inside the standalone POS when Restaurant is enabled.

## Operations
- Safe privileged sale metadata edit with audit trail; posted monetary/stock lines are not silently rewritten.
- Full posted-expense edit for permitted users with before/after audit.
- Application error logs for Admin, Client and POS and user issue reporting.
- Business activity/audit log.
- Pending receivables/payables Payment Center.
- Top-selling products, top customers and sales trend analytics.
- Bulk import foundation for products/customers/suppliers.
- Existing New Sale product autocomplete retained.

## Invoice design
- Super Admin invoice-template manager.
- Sample A4 and 80mm templates.
- Sample Flexi logo assets.
- Per-business A4/80mm assignment.
- GSTIN, phone and address configuration.
- Branch invoice preview uses branch identity where configured.

## Production
- Production module with BOM/recipes.
- Raw-material purchase shortcut to Purchases.
- Production runs consume raw material and add finished goods through existing inventory adjustment RPC.
- Run history and readable tracking IDs.

## Transport service
- Taxi/truck/service vehicle registry.
- Jobs with customer, route, distance, quantity/unit/rate and notes.
- Service jobs can create and link a normal Sales invoice.

## Restaurant
- Dine-in, takeaway and delivery orders.
- Table selection.
- Preparation time.
- Chef/KOT notes.
- KOT generation and kitchen states.
- Ready/served/billed workflow.
- Final billing uses the existing Sales engine.

## Build targets
- Client: Android APK, Windows EXE bundle, Web.
- POS: Android APK, Windows EXE bundle.
- Admin: Web.
