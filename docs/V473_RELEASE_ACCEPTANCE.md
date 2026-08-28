# THQ ERP v4.7.3 — Release Acceptance

Use a test business/POS before rolling to all terminals.

## A. Backend
- [ ] Migration 118 existed before upgrade.
- [ ] Migration 119 applies once without error.
- [ ] `thq_backend_contract_v47()` returns 4.7.3 / 119 / minimum app 4.7.3.
- [ ] All V4.7.3 RPC post-checks are true.

## B. Refresh / synchronization
- [ ] Admin dashboard Refresh reloads current platform overview.
- [ ] Client Refresh completes without error.
- [ ] POS Refresh completes without error.
- [ ] Change POS name in Admin -> POS Refresh -> updated name is visible.
- [ ] Move a test POS to another store -> POS Refresh -> new store is visible.
- [ ] After store move + Refresh, a new POS transaction posts to the new store.
- [ ] Enable/disable a POS module -> POS Refresh -> navigation changes without reactivation.
- [ ] Change product/customer data in Client -> POS Refresh -> updated data appears.
- [ ] If runtime configuration cannot be loaded, Refresh reports failure instead of claiming success.

## C. Hold / Resume
- [ ] Normal Billing shows no held-invoice strip/cards.
- [ ] Hold sale A.
- [ ] Hold sale B.
- [ ] Press Resume -> dedicated Held Invoices page opens.
- [ ] Held invoices render in a responsive grid, not horizontal scrolling.
- [ ] Search/product UI is replaced by Held Invoices until Back/Products is pressed.
- [ ] Back/Products returns to normal product grid.
- [ ] Select sale A -> cart/customer/discount/payment state is restored.
- [ ] Completing resumed sale succeeds.
- [ ] Trying Resume with a non-empty new cart asks user to hold/clear first.

## D. Today-only live POS
- [ ] Sales screen contains only today's sales from this exact POS.
- [ ] Another POS at the same store does not appear in this POS Sales list.
- [ ] Purchases screen contains only today's purchases from this exact POS.
- [ ] Expenses screen contains only today's expenses from this exact POS.
- [ ] Cashier Shift screen lists only today's shifts.
- [ ] Return lookup finds today's invoices from this POS only.
- [ ] A historical invoice is not shown in normal Return lookup.

## E. Terminal Daily historical reporting
- [ ] Terminal Daily defaults to today.
- [ ] Previous day works.
- [ ] Date picker opens any past day.
- [ ] Future dates cannot be selected.
- [ ] Summary shows only the selected POS.
- [ ] Historical Held Now is not reported.
- [ ] Cashier Shift section is aggregate/read-only only.
- [ ] No shift start/end/edit control exists in Terminal Daily.
- [ ] PDF/Excel are summary reports and do not export detailed shift rows.
- [ ] View Invoices is hidden by default.
- [ ] View Invoices loads only invoices from selected date + exact POS.
- [ ] Search by invoice number works.
- [ ] Search by sale number works.
- [ ] Search by customer works.
- [ ] Opening an invoice shows its normal detail.
- [ ] Returning from invoice detail refreshes Terminal Daily totals/list.
- [ ] Historical invoice return (if user has permission) is performed from invoice detail, not normal live Return search.

## F. Regression
- [ ] Cash sale.
- [ ] Credit/partial sale.
- [ ] Customer account receipt.
- [ ] Sales return.
- [ ] Cashier Shift open/close/edit.
- [ ] Terminal Daily totals reconcile with the day's transactions.
- [ ] System Health has zero unexpected critical findings.

## G. Build gate
Run locally where Flutter is installed:
- [ ] `flutter pub get` / `flutter analyze` / `flutter test` — erp_core
- [ ] Admin analyze/test/build
- [ ] Client analyze/test/build
- [ ] POS analyze/test/build
