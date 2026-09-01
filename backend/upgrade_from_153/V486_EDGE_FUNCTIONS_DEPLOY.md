# v4.8.6 Edge Function deployment

Deploy `thq-api` after applying migrations 154–160. v4.8.6 adds the `offline-pos` API resource for sync, request lookup, queue status/summary, product/customer/serial cache, cache manifest and API contract.

Maintained mirrors:
- `backend/functions/thq-api/index.ts`
- `supabase/functions/thq-api/index.ts`

The two files must remain byte-identical.
