## Hotfix 3 — migration 117

- Fixed POS Cashier Shift navigation being hidden while checkout still required an open shift.
- POS plans now include Cashier Shift and Terminal Daily operational entitlements whenever POS is entitled.
- POS navigation and checkout now use aligned effective-module rules.

# THQ ERP v4.7.1 Changelog

## POS
- Reworked Hold/Resume into inline held-invoice cards on the billing screen.
- Preserves/restores cart, customer, discounts, notes and payment state when resuming.
- Allows partial payment for named customers while recording the full invoice.
- Adds customer-account balance action and standalone receipt collection.
- Requires an open cashier shift for billing/cash receipts only when `cashier_shifts` is enabled for that POS.
- Adds customer receipts to Cashier Shift and Terminal Daily.
- Terminal Daily now calls `pos_terminal_day_v471` and exports customer receipts.

## Customer receivables
- Added customer receipts and receipt allocations.
- Added account-level or invoice-specific payment allocation.
- Oldest-invoice-first allocation for account payments.
- Added idempotency and per-customer concurrency locking.
- Outstanding = sale total − valid returns − payments.
- Added customer receipt journal and POS cash-drawer movement.
- Added individual account history and all-customer receivables views.

## Store / system hierarchy
- Added logical roles: POS, Back Office, Office, Inventory.
- Admin and delegated Client managers use v4.7.1 system lifecycle RPCs.
- Systems can be reassigned to another active store without recreation.
- Store moves are blocked while a POS has an open shift or held invoice.
- Safe system/store delete/archive behavior preserves historical references.

## Admin
- Fixed POS module persistence including Terminal Daily.
- Added Customer Accounts from Business Details.
- Updated permanent business deletion to use `platform_business_delete_v471`.

## Backend
- Migrations 111–114.
- App/backend release contract 4.7.1 / migration 114.
- Business-level Cashier Shift and Terminal Daily capability backfill for POS-enabled tenants.

## Hotfix 2 — Migration 116
- Eliminated remaining runtime ambiguity from the legacy overloaded `private.business_audit_write` API by routing V4.7.1 operational RPCs through a uniquely named JSONB audit writer.
- Rehardened Client system create/update/revoke, Admin system lifecycle, customer receipts, and held-invoice feed definitions.
- Updated rebuilt app database floor to migration 116.
