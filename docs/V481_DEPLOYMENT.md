# THQ ERP v4.8.1 Deployment

1. Back up the migration-124 database.
2. Apply `backend/THQ_ERP_V481_UPGRADE_FROM_124.sql` or individual 125–129 files.
3. Run `backend/upgrade_from_124/V481_POST_UPGRADE_CHECK.sql`.
4. Redeploy `supabase/functions/thq-api`.
5. Run `tools/validate_v481_windows.ps1` on the source machine.
6. Start one staging Client and POS, sign in again, and execute `docs/V481_RELEASE_ACCEPTANCE.md`.
7. Roll out to production only after stock, transaction, return and accounting checks pass.
