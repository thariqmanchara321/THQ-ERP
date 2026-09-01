# THQ ERP v4.8.3 — Edge Function deployment

After database migrations 135–139 are applied, deploy the updated `thq-api` Edge Function from `supabase/functions/thq-api/index.ts`.

```powershell
supabase functions deploy thq-api
```

The v4.8.3 API contract adds `tracking-policy`, `serials`, `batches`, `batch-history`, and `warranties`. The function uses the caller's JWT and does not use a service-role key for normal requests.

After deployment, call the API `contract` resource or run `backend/V483_POST_UPGRADE_CHECK.sql` and confirm migration 139 / schema 4.8.3.
