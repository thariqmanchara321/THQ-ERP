# v4.7.1 Edge Function deployment

Required changed function:
- `delete-business-v41` — now delegates permanent deletion to `platform_business_delete_v471` after existing Super Admin reauthentication and business-code validation.

The `backend/functions/delete-business-v41/index.ts` and `supabase/functions/delete-business-v41/index.ts` copies are byte-identical in this release.
