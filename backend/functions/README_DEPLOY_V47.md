# THQ ERP v4.7 Edge Function Deployment

After migrations 101–110 are applied, redeploy these two changed functions before distributing v4.7 Client/POS:

```powershell
supabase functions deploy device-activate
supabase functions deploy username-login
```

The source is mirrored in both:

- `supabase/functions/`
- `backend/functions/`

## v4.7 changes

`device-activate` no longer performs the multi-step claim directly against `business_devices`. It hashes the activation code and generated device secret, then calls `system_claim_activation_v47`, which performs the claim atomically in PostgreSQL and creates the physical installation-history row.

`username-login` now requires both the active logical system row and the matching active `system_installations` binding/secret hash.

Do not deploy these function versions before migration 105 exists.
