# FLEXI ERP V3 TEST PLAN

Run these tests only after migrations 010–016 and both Edge Functions are deployed.

1. Username identity
   - Existing Admin signs in with generated username + old password.
   - Existing business user signs in with username + old password.
   - Create a new user with a globally unique username.
   - Confirm duplicate username is rejected regardless of letter case.
   - Confirm passwords below 8 chars are rejected when creating/resetting users.

2. Admin
   - Businesses/modules/templates/subscriptions still open.
   - Business Users list shows usernames.
   - Platform Admins uses usernames.
   - Invoice Templates shows A4 and 80mm seed templates and editing works.
   - Assign A4/80mm templates to test business.
   - Error Logs page opens.

3. Client
   - Login and business session load.
   - Existing Inventory/Purchases/Sales continue working.
   - New Sale product field filters as characters are typed.
   - Dashboard shows top products/customers and trend.
   - Payment Centre loads outstanding receivables/payables.
   - Bulk Import can import one test customer/supplier/product.
   - Logs → Report Issue appears in tenant/platform logs.
   - Logs → Activity Log shows audited edits.
   - Logs → Track ID resolves a known tracking code.
   - Sale Details → invoice preview works for A4 and 80mm.

4. POS
   - POS is not visible in normal Client ERP navigation.
   - `apps/pos_app` starts separately.
   - Login, choose business, open POS.
   - Add product and confirm selected-product info.
   - Add quantity/discount, use quick cash chips, complete sale.
   - Confirm one SAL number is created through existing Sales engine.
   - Confirm stock decreased exactly once.
   - Products/Customers/Suppliers/Purchases/Expenses only appear if corresponding tenant modules are enabled.

5. Controlled edits
   - User without `sales.edit` cannot edit sale metadata.
   - Authorized user changes sale customer/due date/notes.
   - Activity Log contains before/after record.
   - Authorized user edits an expense.
   - Activity Log contains before/after record.

Stop immediately on any SQL, analyzer, RPC or runtime error and fix that exact layer before continuing.
