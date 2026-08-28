# THQ ERP v4.8.2 — Upgrade from migration 129

Use this package only when the current database is already on **THQ ERP v4.8.1 / migration 129**.

1. Take a Supabase/PostgreSQL backup.
2. Apply migrations **130 → 134** in order, or run `THQ_ERP_V482_UPGRADE_FROM_129.sql`.
3. Run `V482_POST_UPGRADE_CHECK.sql`.
4. Confirm `schema_version = 4.8.2`, `migration_no = 134`, and `thq_v482_release_verify().ready = true`.
5. Deploy the updated `thq-api` Edge Function from the full source release.
6. Run the Windows validation helper before distributing apps.
7. Test pricing precedence, quantity breaks, customer-specific prices, scanning/searching all identifier types, barcode/QR generation, and label printing in staging.

Do **not** replay migrations 001–129.
