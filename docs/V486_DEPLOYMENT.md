# THQ ERP v4.8.6 Deployment

1. Back up the v4.8.5 database and confirm migration 153.
2. Run `backend/THQ_ERP_V486_UPGRADE_FROM_153.sql`.
3. Deploy the updated `thq-api` Edge Function.
4. Run `backend/V486_POST_UPGRADE_CHECK.sql`; require `ready=true`, version `4.8.6`, migration `160`.
5. On the Windows Flutter workstation run `tools/validate_v486_windows.ps1`.
6. Start each POS online at least once so products, customers, serials, shift state and printer settings can be cached before relying on offline mode.
