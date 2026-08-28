# Backend installation steps

Use Supabase project `flexi-erp-dev` and run each SQL file separately in SQL Editor. Stop immediately on any error and fix that migration before running the next one.

## Migration order
1. `001_erp_extension_security.sql`
2. `002_expenses.sql`
3. `003_party_statements.sql`
4. `004_dashboard_reports_accounting.sql`
5. `005_verify_existing_sales_rpcs.sql`
6. `006_platform_v2_core.sql`
7. `007_module_catalog_templates_plans.sql`
8. `008_platform_v2_rpcs.sql`
9. `009_existing_tenant_bootstrap_and_verify.sql`

001-005 are the additive ERP-extension migrations from the previous bundle. If you already ran them successfully, they are mostly idempotent; 005 is a verification migration. You may still run them in order if unsure, but stop on any schema mismatch.

## After 009

Sign out of the Admin Panel and sign in again. `platform_current_admin_context()` will bootstrap an existing legacy platform admin into the new `super_admin` assignment table on first login.

Then in Admin Panel:
1. Open Modules and confirm POS + Settings + industry packs exist.
2. Open Templates and confirm the seeded templates.
3. Open Subscriptions and review/edit the example prices and limits before selling them. They are starter values, not a business recommendation.
4. Open your existing business → Subscription and assign a plan if you want entitlement enforcement now. If no plan is assigned, the client remains backward-compatible and uses enabled tenant modules.
5. Open business Modules and enable `pos` if you want POS for that tenant. Dependencies are added/protected by the V2 update RPC.
6. Review Roles & Permissions. Owner gets new permissions automatically when modules are enabled. For a cashier using POS, give the role the existing Sales permission required by your `sales_create` RPC plus `pos.use`.

## Important backend limitation

The bundle intentionally does not replace your known-working `sales_create`, `purchases_create`, inventory ledger or moving-average-cost functions. Therefore commercial entitlement is enforced by the new client session and the V2 module-management path, while older transaction RPCs may still contain their original module checks. Before production SaaS launch, retrofit `private.erp_module_available(tenant_id,module_key)` into every privileged transaction RPC so a direct API caller cannot use a module excluded by subscription.

Do that only after exporting the current working function definitions and testing in a staging Supabase project; do not blindly replace your production transaction engines.

## Production tasks after V2
- Configure database backups/PITR appropriate to your Supabase plan.
- Create separate dev/staging/prod Supabase projects.
- Add automated migration source control under `backend/migrations`.
- Add CI to run Flutter analyze/tests and database migration tests.
- Add tenant operational audit logging for sales cancellation, stock adjustment, price override, role changes and sensitive healthcare actions.
- Add subscription payment provider/webhook processing on a trusted backend/Edge Function. Do not process subscription truth only from Flutter.
- Add invoice/POS printer integration and PDF invoice service.
- Add server-side enforcement of plan usage limits (users, locations, products, invoices/month).
