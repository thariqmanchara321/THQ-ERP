# Flexi ERP V3.1 runtime test plan

Do these tests only after all migrations, functions and analyzers succeed.

## Admin
1. Username login works.
2. Businesses page opens.
3. Modules/Templates/Subscriptions/Platform Admins/Settings/Audit/Error Logs open.
4. Existing business shows a Business Code.
5. Locations & Systems shows MAIN.
6. Create a child branch and verify its LOC tracking code.
7. Issue a Flexi POS activation and a Flexi ERP Client activation.
8. Invoice Designs shows A4 and 80mm samples.
9. Business Users creates a new user with a 4+ char unique username and 8+ char password.

## Client
1. Fresh installation asks for one-time activation before username login.
2. Correct business/location/device appears after login.
3. POS is NOT shown inside Client.
4. Existing Inventory/Sales/Purchases/Customers/Suppliers still work.
5. New Sale product autocomplete works by first letters/name/SKU/part number/barcode.
6. Create an Expense and confirm origin/audit/logging.
7. Open Payment Center, Dashboard insights, Bulk Import, Logs, Tracking Lookup and Locations.
8. Locations can show All locations merged and an individual branch.

## POS
1. Fresh POS activation binds the terminal to the chosen branch.
2. Username login works.
3. Header shows branch code and terminal code.
4. Search/scan product and verify product details/stock/tax.
5. Add product to cart, use Exact and denomination buttons, complete sale.
6. Confirm normal `SAL-xxxxxx` exists and stock decreased through the existing Sales engine.
7. Open Products/Customers/Suppliers/Purchases/Expenses from POS when permitted.
8. Check Logs.

## Tracking + branch billing
1. Search a PRD/SALR/LOC/DEV/etc tracking code.
2. Verify new sale has original ERP sale number and a branch-local printed number such as `MAIN-INV-000001`.
3. Verify branch/device origin is shown in invoice preview.

## Production
1. Create or choose raw-material stock products and a finished stock product.
2. Purchase raw material through normal Purchases.
3. Create a BOM/recipe.
4. Run a small production batch.
5. Verify raw material decreases and finished product increases through Stock Movement History.
6. Verify production RUN tracking code/history.

## Transport Service
1. Create taxi/truck vehicle.
2. Create job with customer, from/to, distance, quantity/unit/rate.
3. Bill the job using an active Service/Non-stock product.
4. Verify normal Sales invoice and job link.

## Restaurant
1. Create tables.
2. New dine-in order -> select table -> add items -> prep time -> chef note.
3. Send KOT; move through preparing/ready/served.
4. Finalize bill and verify normal Sales invoice.
5. Repeat takeaway.
6. Repeat delivery with delivery address.
7. Verify sale appears in standard Sales/Accounting/Reports.
