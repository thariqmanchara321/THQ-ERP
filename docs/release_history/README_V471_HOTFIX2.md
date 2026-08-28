# THQ ERP v4.7.1 — Hotfix 2 (Migration 116)

Apply this after migration 115.

## Fix
The V4.7.1 system/customer RPCs no longer call the overloaded `private.business_audit_write(...)` directly. They now use the unique `private.business_audit_write_v471(...)` wrapper, eliminating PostgreSQL error 42725 caused by untyped NULL arguments.

This specifically covers Client system create/update/revoke, Admin system deactivate/update/delete, Admin store delete/archive, and customer balance receipts. The held-invoice feed fix from migration 115 is reapplied as part of the RPC refresh.

## Apply
1. Back up the database.
2. Run `116_v471_hotfix2_audit_overload_hardening.sql` in Supabase SQL Editor.
3. Run `V471_HOTFIX2_POST_CHECK.sql`.
4. Confirm migration 116 and all boolean checks are `true`.
5. Restart/refresh Admin, Client and POS. No Edge Function deployment is required for Hotfix 2.

## Expected backend contract
- schema_version: 4.7.1
- migration_no: 116
- minimum_app_version: 4.7.1


## Superseded operational note
Hotfix 3 migration 117 should be applied after this release to align POS Cashier Shift/Terminal Daily module visibility.
