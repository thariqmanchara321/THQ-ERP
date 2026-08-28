# THQ ERP v4.7.3 — Live Operations Polish

This release is intended to close the v4.7 stabilization line with operational UX and manual synchronization improvements. The next architectural feature work (THQ API, automatic/versioned synchronization, mobile, offline POS, operational intelligence) belongs to v4.8+.

## Upgrade from v4.7.2
If the database is already at migration 118, apply only:

`backend/upgrade_from_118/119_v473_live_operations_polish.sql`

Then run:

`backend/upgrade_from_118/V473_POST_UPGRADE_CHECK.sql`

Expected contract:
- schema version: `4.7.3`
- migration: `119`
- minimum app: `4.7.3`

No Edge Function redeployment is required by v4.7.3.

## App rollout
Build/deploy Admin, Client, and POS `4.7.3+6` after migration 119 is present. Client/POS enforce the shared backend contract through `erp_core`.

## First verification after rollout
1. Login to Admin, Client and POS.
2. Change a test POS name/module/store assignment in Admin.
3. Press Refresh in POS and confirm the new values are applied without reactivation.
4. Change a product/customer in Client, press Refresh in POS, and confirm the updated data is loaded.
5. Hold two test sales. Confirm held cards are not visible during normal billing; press Resume and confirm the dedicated grid appears.
6. Verify normal POS Sales/Purchases/Expenses/Cashier Shift show only today and the exact terminal.
7. Open Terminal Daily, select an older date, search an invoice for that POS, and open it.
8. Run the release acceptance checklist in `docs/V473_RELEASE_ACCEPTANCE.md`.

## Validation note
The included static verifier checks source wiring, migration contracts, imports, SQL structure, and release packaging. The release still requires Flutter analyze/test/build and execution of migration 119 against your staging/production Supabase environment; those runtimes are not available in the packaging environment.
