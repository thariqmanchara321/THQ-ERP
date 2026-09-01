# THQ ERP v4.8.4 Edge Function deployment

After database migrations 140–146 are applied, redeploy the `thq-api` Edge Function from either maintained mirror:

- `backend/functions/thq-api/index.ts`
- `supabase/functions/thq-api/index.ts`

The two files must be identical. v4.8.4 adds API resources for Purchase Requests, Purchase Orders, GRNs, Purchase Invoices, Supplier Payments, Supplier Ledger, Purchase Price History, and the Purchasing dashboard.

Keep the existing Supabase URL/anon-key deployment configuration. The function must continue to execute RPCs as the authenticated caller and must not use a service-role key for normal application requests.
