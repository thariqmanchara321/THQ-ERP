# THQ ERP v4.8.5 database deployment

Baseline: **v4.8.4 / migration 146**. Target: **v4.8.5 / migration 153**.

1. Back up the production database.
2. Run `THQ_ERP_V485_UPGRADE_FROM_146.sql` once, or apply migrations 147 through 153 in order.
3. Run `V485_POST_UPGRADE_CHECK.sql`. `thq_v485_release_verify().ready` must be `true` and the backend contract must report migration `153` / version `4.8.5`.
4. Redeploy the `thq-api` Edge Function from this release.
5. Refresh/restart Client/POS sessions so the new contract and navigation are loaded.

Do not replay migrations 001–146 on an already-upgraded database.
