# THQ ERP v4.7 — Foundation Lock & Production Stabilization

This package is the v4.7 source release built on the supplied current THQ Admin, Client and POS code plus the confirmed backend migration history through migration 100.

## Upgrade baseline

Your live database must already have **migration 100 (`100_v46_core_fixes.sql`) applied**.

Apply only migrations **101 → 110**, in numeric order. For convenience, the package contains:

- `backend/upgrade_from_100/` — individual v4.7 migrations.
- `backend/THQ_ERP_V47_UPGRADE_FROM_100.sql` — the same migrations concatenated in order.
- `backend/migrations/` — full migration history 001 → 110 for source/history purposes.

Do not replay migrations 001–100 against a database that already contains them.

## What v4.7 changes

- strict accounting posting for sale/purchase/expense origins; critical accounting errors no longer disappear silently;
- default accounting provisioning for newly created businesses and backfill of required mappings for current businesses;
- retry-safe request IDs for core transaction commands, including sale/purchase creation, payments, returns, expenses, stock adjustments/transfers and POS shift open/close;
- POS checkout keeps one request ID across retry until the sale succeeds;
- separate physical `system_installations` history while keeping existing `business_devices` logical system IDs compatible;
- database-atomic activation claim used by the `device-activate` Edge Function;
- username login validates the active physical installation as well as the logical system/device secret;
- available-stock validation occurs inside the row-locked branch stock mutation;
- Client/POS fail closed when app access is not explicitly granted (owners remain allowed);
- Client/POS refuse to start against a backend older than v4.7 migration 110;
- Admin business details include a System Health screen backed by a live integrity scan;
- Client/POS use a real shared `erp_core` release/money/error foundation;
- application version bumped to `4.7.0+1`.

## Required deployment order

1. Back up the production database.
2. Apply migrations 101 → 110 to a staging copy first.
3. Run `select * from public.thq_backend_contract_v47();` and confirm migration `110`, schema `4.7.0`.
4. For each test business, run `select * from public.system_integrity_scan_v47('<tenant-uuid>');`.
5. Resolve critical integrity findings before production deployment.
6. Deploy the updated `device-activate` and `username-login` Edge Functions.
7. Deploy/update Admin.
8. Update Client and POS to 4.7.0.
9. Perform the acceptance flow in `docs/V47_RELEASE_ACCEPTANCE.md`.

## Compatibility

Older v4/v4.6 RPCs remain in place. V4.7 adds new wrappers rather than removing the existing interfaces. This is intentional so the database can be upgraded before every Client/POS machine is updated.

The v4.7 Client/POS applications themselves require backend migration 110.

## Important release note

This package is a **source release**. The environment used to assemble it does not contain the Flutter SDK or a runnable local PostgreSQL/Supabase stack, so binary builds and runtime migration execution are not falsely marked as completed. Run the included verification/build steps in your normal development/staging environment before production rollout.
