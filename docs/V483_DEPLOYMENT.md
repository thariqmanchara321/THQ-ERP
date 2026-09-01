# THQ ERP v4.8.3 deployment

Target starting point: **v4.8.2 / migration 134**.

1. Back up Supabase/PostgreSQL.
2. Apply migrations 135 → 139 in order, or execute `backend/THQ_ERP_V483_UPGRADE_FROM_134.sql`.
3. Run `backend/V483_POST_UPGRADE_CHECK.sql`.
4. Confirm backend contract `minimum_app_version = 4.8.3`, migration `139`, and `thq_v483_release_verify().ready = true`.
5. Deploy `supabase/functions/thq-api/index.ts` as the `thq-api` Edge Function.
6. Run `tools/validate_v483_windows.ps1` on the release source. Run with `-Build` when producing distributable binaries.
7. Stage-test one serial product and one batch product end-to-end before production rollout.
8. For any product that already has stock, enable tracking and complete opening reconciliation at each applicable store before new tracked transactions.

Do not replay migrations 001–134.
