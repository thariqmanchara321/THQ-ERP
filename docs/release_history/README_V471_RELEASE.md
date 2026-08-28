> Hotfix 3: migration 117 aligns Cashier Shift / Terminal Daily visibility with POS enforcement.

# THQ ERP v4.7.1 — Operational Stabilization Patch

This release upgrades THQ ERP v4.7.0 / database migration 110 to v4.7.1 / migration 114.

## Upgrade prerequisite

The target Supabase database must already contain migrations through **110**. Apply **111, 112, 113, 114** only, in that order. A combined script is included at `backend/THQ_ERP_V471_UPGRADE_FROM_110.sql`.

## Main fixes

- POS Hold/Resume: held invoices are shown inline in the billing/product area and can be restored into the current cart.
- Customer receivables: full sale is retained, partial payment is recorded, remaining balance stays outstanding, later receipts can be taken without a new sale, and payments can target one invoice or the oldest open invoices.
- Return-aware customer balances: valid sales returns reduce customer outstanding.
- Customer account detail and overall receivables views in Client/Admin; POS can receive a selected customer's outstanding balance.
- Receipt accounting and POS cash-drawer/day-close integration.
- POS Cashier Shift enforcement when the module is enabled.
- Terminal Daily upgraded to v4.7.1 and includes customer receipts in UI/PDF/Excel.
- POS module editing includes `cashier_shifts` and `terminal_day`, with business-level backfill for POS-enabled tenants.
- Store/system hierarchy supports POS, Back Office PC, Office PC and Inventory PC roles.
- Systems can be assigned to a store at creation and moved later, with safety blocks for open shifts and held invoices.
- Safe store/system deletion or archival based on business history.
- Permanent business deletion now uses an integrity-aware service-role database RPC after Super Admin reauthentication/confirmation.
- Apps/backend compatibility contract bumped to 4.7.1 / migration 114.

## Deployment order

1. Back up the database.
2. Apply migrations 111 → 114 (or the combined upgrade script).
3. Run `backend/V471_POST_UPGRADE_CHECK.sql` in Supabase SQL Editor.
4. Deploy the updated `delete-business-v41` Edge Function.
5. Run Admin and open **Business → System Health** for each live business; critical issues must be 0 before rollout.
6. Run Flutter dependency/analyze/test/build checks locally.
7. Test one staging/test business and one POS before broad rollout.
8. Roll out Admin/Client/POS v4.7.1+2.

## Runtime verification limitation

This source package passed the included static verification (`V471_STATIC_VERIFICATION.txt`). The packaging environment does not contain a Flutter SDK or runnable PostgreSQL/Supabase instance, so Flutter compilation and actual migration execution must be performed in your staging environment before production deployment.

## Hotfix 1 — Migration 115
Runtime acceptance testing found and fixed two PostgreSQL resolution issues: ambiguous `id` in the held-sale feed and ambiguous `business_audit_write` overload selection when an untyped NULL was passed. Apply migration 115 after 114. Existing v4.7.1+2 app binaries remain compatible and do not require a rebuild for this hotfix.
