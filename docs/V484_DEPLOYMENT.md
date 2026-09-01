# THQ ERP v4.8.4 deployment

1. Confirm the production backend is v4.8.3 / migration 139.
2. Take a database backup.
3. Apply migrations 140–146, preferably with `backend/THQ_ERP_V484_UPGRADE_FROM_139.sql`.
4. Run `backend/V484_POST_UPGRADE_CHECK.sql` and confirm the release verifier reports `ready: true`, version `4.8.4`, migration `146`.
5. Redeploy `thq-api` from `supabase/functions/thq-api/index.ts` (the backend mirror must be identical).
6. Run `tools/validate_v484_windows.ps1` on the Flutter build machine.
7. Smoke-test PR → PO approval → partial GRN → remaining GRN → Purchase Invoice → partial/full Supplier Payment → Supplier Ledger.
8. For serial/batch products, test accepted and damaged receipt traceability before production rollout.
