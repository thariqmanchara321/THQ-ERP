# THQ ERP v4.7 Release Acceptance

Do not mark the release accepted until the following pass on a staging copy of real data.

## Backend / migration

- [ ] Production backup completed and restoration procedure confirmed.
- [ ] Migration 100 confirmed before upgrade.
- [ ] Migrations 101–110 apply successfully in order.
- [ ] `thq_backend_contract_v47()` reports schema `4.7.0`, migration `110`.
- [ ] `system_integrity_scan_v47()` has zero unresolved critical issues for release businesses.

## Activation / identity

- [ ] Existing active Client/POS installation can login after migration.
- [ ] New configured POS can issue an activation code and activate once.
- [ ] Reusing the consumed activation code fails.
- [ ] A physical installation already bound to another active system is rejected.
- [ ] Deactivate system invalidates its physical binding/login.
- [ ] Reactivate the same logical POS on a replacement PC and retain the same system identity/invoice configuration.

## Sales / POS

- [ ] Start terminal shift/day.
- [ ] Cash sale posts sale, branch stock, journal, invoice and cash movement.
- [ ] Card/UPI sale posts to the correct account.
- [ ] Credit sale produces the correct receivable.
- [ ] Hold and resume restores cart/customer/discount/tax correctly.
- [ ] Confirm and Confirm & Print do not double-submit while saving.
- [ ] Simulate response loss/retry with the same request ID: only one sale exists.
- [ ] Two POS terminals attempt the last available unit concurrently: configured no-negative-stock rule is respected.
- [ ] Sale return restores stock and posts reversal accounting.
- [ ] Sale void/reversal preserves audit/history.

## Purchases / inventory

- [ ] Purchase posts supplier payable/payment, branch stock, tax and journal.
- [ ] Purchase return reverses stock/payable/tax correctly.
- [ ] Stock adjustment uses correct location and cannot make available stock negative without an allowed path.
- [ ] Stock transfer reservation/dispatch/receipt remains consistent.
- [ ] Branch stock rollup equals location detail for sampled products.

## Accounting / cash

- [ ] Every new sale/purchase/expense receives its required posted journal.
- [ ] Every posted journal balances debit = credit.
- [ ] Customer outstanding agrees with invoice/payment history.
- [ ] Supplier outstanding agrees with purchase/payment history.
- [ ] Cash drawer expected amount agrees with cash movements.
- [ ] Day close expected/declared/difference is correct after sales, expenses, returns, cash in/out.

## Security / scope

- [ ] User without explicit Client access is denied unless owner.
- [ ] User without explicit POS access is denied unless owner.
- [ ] Store-limited user cannot read/create for an unauthorized store.
- [ ] Tenant A cannot read/write Tenant B data using RPCs.
- [ ] Platform financial/system actions remain audited.

## Apps / build

- [ ] `flutter pub get` succeeds for Admin, Client, POS and `erp_core`.
- [ ] `flutter analyze` succeeds for all apps/packages.
- [ ] `flutter test` succeeds for all apps/packages.
- [ ] Windows Client/POS build succeeds.
- [ ] Android Client/POS build succeeds where supported.
- [ ] Production signing is configured before distribution.
