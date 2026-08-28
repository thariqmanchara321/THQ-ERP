# THQ ERP v4.8.0 — Release Acceptance

## Backend
- [ ] Backup staging database.
- [ ] Current backend is migration 119 before upgrade.
- [ ] Apply 120, 121, 122, 123, 124 in order.
- [ ] `thq_backend_contract_v47()` returns 4.8.0 / 124 / minimum app 4.8.0.
- [ ] `thq_v480_release_verify()` returns `ready=true`.
- [ ] Deploy Edge Function `thq-api`.
- [ ] Call THQ API `contract` and confirm `api_version=v1`.

## Flutter
- [ ] `flutter analyze` passes for erp_core.
- [ ] `flutter test` passes for erp_core.
- [ ] Admin analyze/tests pass.
- [ ] Client analyze/tests pass.
- [ ] POS analyze/tests pass.
- [ ] Windows/web/android builds required for your deployment pass.

## Synchronization
- [ ] Login Client and POS after migration 124.
- [ ] Admin changes a POS module; POS shows `Updates • Refresh` within ~15 seconds.
- [ ] Admin moves a POS/store configuration; Refresh loads the new binding.
- [ ] Change a product price; Client/POS detects catalogue drift.
- [ ] Create a normal POS sale; POS does not continuously show false catalogue/config updates.

## Operations Intelligence
- [ ] Operations Intelligence appears for businesses with Inventory/Reports/Purchases.
- [ ] Stock quantities match Inventory.
- [ ] Low/out-of-stock classification is correct.
- [ ] Inventory value is plausible against location stock × average cost.
- [ ] Return-aware demand does not count returned quantity as net demand.
- [ ] Customer outstanding matches Customer Accounts.
- [ ] Sales returns reduce receivables.
- [ ] Customer ageing buckets match due dates.
- [ ] Supplier payables match Purchase/Pending Payments.
- [ ] Purchase returns reduce supplier payable totals.

## Purchase Planning / PO
- [ ] Reorder suggestions are separated by store.
- [ ] Suggested quantities respect reorder/max settings.
- [ ] Last supplier/cost is populated when purchase history exists.
- [ ] Create PO from selected suggestions.
- [ ] PO creation does not change stock.
- [ ] PO creation does not create accounting journals.
- [ ] Draft → Submitted → Approved → Ordered works.
- [ ] Invalid status jumps are rejected.
- [ ] Cancellation requires a reason.
- [ ] Status history remains visible.

## Regression
- [ ] POS Billing works.
- [ ] Hold / Resume workspace works.
- [ ] Cashier Shift works.
- [ ] Terminal Daily works.
- [ ] Customer partial payment/receipt works.
- [ ] Sales Return works.
- [ ] Purchase Return works.
- [ ] Inventory adjustment/transfer works.
- [ ] System Health critical count remains zero after test transactions.
