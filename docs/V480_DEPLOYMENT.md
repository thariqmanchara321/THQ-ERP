# THQ ERP v4.8.0 — Deployment from v4.7.3 / migration 119

## 1. Backup
Take a verified database backup before applying the upgrade.

## 2. Database
The current production/staging backend must already be at migration **119**.

Apply only:

1. `120_v480_connectivity_sync.sql`
2. `121_v480_operational_intelligence.sql`
3. `122_v480_purchase_planning.sql`
4. `123_v480_api_mobile_contracts.sql`
5. `124_v480_release_contract.sql`

You can instead run the combined `backend/THQ_ERP_V480_UPGRADE_FROM_119.sql`.

Do not replay migrations 001–119.

## 3. Backend verification
Run `backend/upgrade_from_119/V480_POST_UPGRADE_CHECK.sql`.

Expected contract:

- schema version: `4.8.0`
- migration: `124`
- minimum app: `4.8.0`
- API version: `v1`
- `thq_v480_release_verify().ready`: `true`

## 4. Deploy the API gateway
Deploy the included Supabase Edge Function as **thq-api**.

From a linked Supabase project:

```powershell
supabase functions deploy thq-api
```

The source exists in both `supabase/functions/thq-api/` and the mirrored `backend/functions/thq-api/` directory.

The function uses the caller's bearer token and does not create a service-role client for normal application traffic.

## 5. Validate Flutter locally
From the source root on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\validate_v480_windows.ps1
```

To include release builds:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\validate_v480_windows.ps1 -Build
```

## 6. Staging acceptance
Run `docs/V480_RELEASE_ACCEPTANCE.md` before live rollout.

Start with one business / one Client / one POS. Confirm sync drift detection, Operations Intelligence, Purchase Planning, PO workflow and the preserved v4.7.3 billing/returns/shift/terminal-day flows before wider deployment.
