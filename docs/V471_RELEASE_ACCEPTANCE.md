# THQ ERP v4.7.1 Release Acceptance

Use a staging/test business first. After financial tests, Admin → System Health must remain at **0 critical**.

## Backend / startup
- Backend contract reports migration 114 / schema 4.7.1.
- Admin, Client and POS start and log in.
- Existing system/store identity and invoice prefix are unchanged.

## POS Hold / Resume
- Hold an invoice with multiple items and a named customer.
- Resume shows a compact held card inline on the product/billing screen.
- Selecting it restores items, quantities, prices, discounts, customer and notes.
- Resumed hold is removed only after restoration and can continue to checkout.

## Customer receivables
- Create a ₹1,000 sale for a named customer and pay ₹600.
- Full sale remains ₹1,000; outstanding becomes ₹400.
- Client/Admin/POS customer account shows ₹400.
- Receive ₹100 without a new sale; balance becomes ₹300.
- Receive a payment against one invoice and another against overall account.
- Overall payment allocates oldest open invoices first.
- Sales return reduces outstanding correctly.
- Attempt overpayment; backend rejects it.
- Two concurrent receipt attempts cannot collect the same remaining balance twice.

## Cashier Shift / Terminal Daily
- Enable `cashier_shifts` and `terminal_day` for a POS.
- Billing is blocked before opening shift.
- Open shift, make cash/card sale, receive old customer cash, create expense/refund if supported.
- Cashier Shift shows customer receipts separately and expected cash is correct.
- Terminal Daily displays invoices, returns and customer receipts.
- PDF and Excel contain customer receipts.
- Close shift and verify difference/variance calculation.

## POS modules
- Add/remove Cashier Shift and Terminal Daily on an existing POS and save.
- Relogin/refresh; assigned modules match configuration.

## Store / system hierarchy
- Create POS under MAIN STORE.
- Create Back Office, Office and Inventory Client systems under chosen stores.
- Move a system to another active store and verify store assignment changes while system code remains.
- Moving a POS with an open shift is rejected.
- Moving a POS with a held invoice is rejected.

## Delete / archive
- Delete an unused POS: it is removed safely.
- Delete/revoke a historical POS: history remains and system is revoked/archived.
- Attempt to delete MAIN STORE: rejected.
- Attempt to delete store with systems/children: rejected until moved/removed.
- Delete unused non-MAIN store.
- Test permanent business deletion only on a disposable business: requires Super Admin password + business code and updated Edge Function.

## Financial regression
- Cash/Card/UPI/Credit sale.
- Purchase and purchase return.
- Sales return.
- Inventory adjustment/transfer.
- Customer and supplier outstanding.
- Accounting journals remain balanced.
- Day close agrees with actual cash.
- Duplicate/lost-response checkout produces one sale/invoice/stock movement only.
- Concurrent last-stock sale obeys negative-stock policy.
