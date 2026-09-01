# THQ ERP v4.8.4 database upgrade

Use this directory only when the database is already on **v4.8.3 / migration 139**.

1. Back up the database.
2. Apply `140_v484_purchase_requests_po_v2.sql` through `146_v484_release_contract.sql` in order, or run `THQ_ERP_V484_UPGRADE_FROM_139.sql`.
3. Run `V484_POST_UPGRADE_CHECK.sql` and confirm `ready = true`, `schema_version = 4.8.4`, `migration_no = 146`.
4. Deploy the updated `thq-api` Edge Function.
5. Run `tools/validate_v484_windows.ps1` on a Flutter-capable Windows machine before distributing binaries.

Do not replay migrations 001–139.
