# THQ ERP v4.8.3 database upgrade

Use this directory only when the database is already on **v4.8.2 / migration 134**.

1. Back up the database.
2. Apply `135_v483_tracking_foundation.sql` through `139_v483_release_contract.sql` in order, or run `THQ_ERP_V483_UPGRADE_FROM_134.sql`.
3. Run `V483_POST_UPGRADE_CHECK.sql` and confirm `ready = true`, `schema_version = 4.8.3`, `migration_no = 139`.
4. Deploy the updated `thq-api` Edge Function.
5. Run `tools/validate_v483_windows.ps1` on a Flutter-capable Windows machine before distributing binaries.

Do not replay migrations 001–134.
