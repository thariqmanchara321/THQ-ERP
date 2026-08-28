# Flexi ERP V4 Runtime Test Plan

Run on a TEST business before real deployment.

## 1. Authentication / devices
- Admin username login.
- Client activated system login.
- POS activated terminal login.
- Confirm current username/role/store/device in UI.
- Revoke a test terminal and confirm access is blocked appropriately.

## 2. Multi-store
- Confirm MAIN exists.
- Create BRANCH01.
- Edit phone/GSTIN/address/invoice prefix/logo URL.
- Confirm restricted user cannot access unassigned branch.
- Confirm Owner can switch All Stores / MAIN / BRANCH01.

## 3. Product/store assignment
- Create test product while MAIN selected with opening stock 10.
- Confirm product appears in MAIN and merged view.
- Confirm it does not appear in BRANCH01 until assigned/transferred.
- Assign product to BRANCH01.

## 4. Stock transfer
- Transfer 3 MAIN -> BRANCH01.
- Dispatch.
- Receive.
- Confirm MAIN 7, BRANCH01 3, merged total 10.
- Confirm location movement histories contain transfer out/in.

## 5. Physical count
- Count BRANCH01 as 4.
- Confirm branch becomes 4 and aggregate company quantity increases by +1.
- Confirm stock-count movement/audit.

## 6. Sale
- MAIN sale quantity 1.
- Confirm MAIN stock decreases only.
- Confirm original `SAL-...`, terminal invoice number and tracking/origin exist.
- Confirm creator/location/device attribution.
- Confirm accounting journal: payment/AR + revenue/output tax + COGS/inventory.

## 7. Purchase
- Purchase quantity 2 into BRANCH01.
- Confirm only BRANCH01 physical stock increases.
- Confirm accounting/AP/payment and inventory/input GST journal.

## 8. Sale return
- Return part/all of a test sale.
- Confirm stock restored to original branch.
- Confirm return document and correction history.
- Confirm accounting reversal and customer credit/AR handling.

## 9. Purchase return
- Return eligible purchased stock.
- Confirm branch/global stock decreases.
- Confirm supplier credit/AP accounting.

## 10. Void
- Create an unpaid test sale and void with reason.
- Confirm stock and accounting reverse.
- Confirm paid sale direct void is blocked.
- Repeat for an unpaid purchase.

## 11. POS shift
- Open shift with opening cash.
- Make cash sale.
- Add test cash movement if permitted.
- Close shift.
- Verify expected/count/difference.

## 12. POS UX
- Search by product first letters, SKU, barcode and part number.
- Category and sort.
- Customer selection in catalog area.
- Add enough cart items to validate compact cart.
- Payment: invoice discount, payment method, quick cash, change.
- Review screen before posting.
- Confirm successful sale resets to new order.

## 13. Invoice
- A4 preview.
- 80mm preview.
- 58mm preview if used.
- Branch invoice number.
- GSTIN/phone/address.
- Customer GSTIN.
- Business/branch logo if URL configured.
- Terms/footer.
- Print system dialog.
- PDF share/save.
- Confirm invoice print event history.

## 14. Accounting
- Overview.
- Chart of Accounts add/edit/archive custom account.
- Attempt to archive protected system account -> must block.
- Configure Cash/Bank/UPI/Card/AR/AP mappings.
- Sales Register date/store filters.
- Search Sales Register by invoice/customer/product/SKU.
- Purchase Register.
- Cash Book.
- Bank/UPI/Card.
- GST Register.
- General Ledger.

## 15. Dashboard / reports / payments
- MAIN-only totals.
- BRANCH01-only totals.
- All Stores totals.
- Confirm returns reduce revenue/purchase totals and outstanding balances.
- Top products/customers.
- Low-stock analytics.

## 16. Backup
- Generate business JSON backup.
- Confirm output includes sales, purchases, expenses, customers, suppliers, stock, stores/devices, accounting, configuration and audit metadata.
- Store a copy outside the application machine.

## 17. Notifications / tasks / support
- Trigger low-stock notification.
- Create overdue receivable test if practical.
- Create task due today.
- Create support ticket.
- Confirm device heartbeat/version visible in Admin.

## 18. Workshop / Restaurant / Production / Transport
- Workshop vehicle + job card + status update.
- Existing Restaurant KOT/order/final billing smoke test.
- Existing Production flow smoke test.
- Existing Transport job/billing smoke test.

## 19. Security
- Test cashier cannot view protected profit/cost if permission removed.
- Test branch user cannot query another store through UI.
- Test unauthorized stock transfer/void/return/accounting operations are rejected by backend.

## 20. Regression
- Existing Inventory detail/edit/movements.
- Existing Customers/Suppliers.
- Existing Purchase payments.
- Existing Sales payments.
- Customer/Supplier statements.
- Admin business/modules/roles/subscriptions/templates/users.
