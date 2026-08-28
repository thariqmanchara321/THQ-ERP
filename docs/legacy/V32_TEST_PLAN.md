# V3.2 test plan

Run tests in this order and stop on the first failure.

## 1. Admin
- Username login works.
- Home icon returns to Admin Dashboard from a deep screen.
- Business Details is responsive with no header overflow.
- Locations & Systems lists MAIN and existing terminals.
- Create a second POS terminal or edit Counter 1.
- Choose only `sales` for one terminal and `sales + expenses` for another.
- Set different terminal invoice prefixes.

## 2. Client Owner
- Device activation and username login work.
- Menu search finds modules by first letters.
- Search ERP finds a Product ID/SKU/customer/supplier/invoice.
- Stores & Systems shows MAIN, child stores and POS/Client systems.
- Add a child store and a POS system if desired.
- Team & Access: create a staff user, choose Client/POS access, stores and View/Operate/Manage.

## 3. Store scope
- Owner selects `All stores • merged`: Dashboard/Sales/Purchases/Expenses/Payments/Reports/Accounting load merged values.
- Select MAIN: those same pages show MAIN-only documents.
- A user assigned to one child store must not see another store.
- A View-only user can read allowed documents but cannot create a Sale/Purchase/Expense there.

## 4. IDs / SKU
- New Product proposes the next `SKU-xxxxxx` automatically.
- Editing the SKU to a duplicate is rejected.
- Product Details shows Product ID (`PRD-...`).
- Customer/Supplier lists show Customer ID / Supplier ID and allow searching those IDs.

## 5. POS
- Left navigation collapses/expands.
- Only modules selected for that exact POS terminal appear.
- Product search works with first letters, SKU, barcode and part number.
- Category filter and sort work with a large product list.
- Product cards/detail strip show price/stock/SKU/part/brand/category context.
- Billing steps: Products → Payment → Confirm.
- Cash quick buttons and change calculation work.
- After confirmation the POS resets automatically to Products for the next customer.
- A4/80mm preview is optional.
- The completed Sale receives the terminal-local invoice number and normal core `SAL-...` reference.

## 6. Cross-store invoice numbering
- Create one Sale from Client MAIN and one from POS Counter 1.
- Confirm their display invoice sequences are independent by terminal/prefix.
- Confirm both still have immutable core Sale IDs/tracking IDs.

## 7. Vertical store scope
- Production: with All Stores selected, owner can read all permitted production history; selecting MAIN shows only MAIN runs. Posting a run uses the selected writable store.
- Transport: vehicles/jobs show only selected/allowed store data; a vehicle cannot be used for a job in another store; linked Sale must belong to the same store.
- Restaurant Client: All Stores can read merged permitted orders; new table/order uses the selected writable store.
- Restaurant POS: table/order/KOT/status/billing are locked to the POS terminal store and require `restaurant` in that terminal's module list.

## 8. Existing modules
Retest Inventory, Sales, Purchases, Customers, Suppliers, Expenses, Accounting, Reports, Production, Transport Service and Restaurant/KOT after V3.2 installation.
