# FLEXI ERP V3 — BACKEND UPGRADE STEPS

The existing environment already has migrations 001–009. Run only 010–016 now, one file at a time in Supabase SQL Editor.

## 0. Backup first

Back up the current project and, if possible, take a database backup before changing authentication identity mapping.

## 1. Migration 010 — usernames, tracking IDs, permissions

Run:

`backend/migrations/010_identity_tracking_permissions.sql`

This creates `user_login_names`, backfills existing email-auth users with globally unique usernames, adds business/tracking IDs, V3 modules and granular permissions.

**While you are still logged into the old Admin Panel, run this query and save the result:**

```sql
select
  n.username,
  u.email,
  n.user_id
from public.user_login_names n
join auth.users u on u.id = n.user_id
order by u.email;
```

For most existing users, the username is the part before `@` in their existing email. Collisions are suffixed automatically. Existing passwords do not change.

## 2. Migration 011 — error logs, business audit, controlled edits

Run:

`backend/migrations/011_error_logs_audit_edits.sql`

Creates:
- `app_error_logs`
- `business_audit_log`
- `app_error_log_write`
- tenant/platform error-log viewers
- audited `expenses_update`
- safe audited `sales_update_metadata`

## 3. Migration 012 — invoice templates

Run:

`backend/migrations/012_invoice_templates_business_settings.sql`

Seeds:
- A4 Classic GST
- A4 Modern GST
- 80mm Compact GST
- 80mm Detailed

Creates global template editing and per-business A4/80mm assignment RPCs.

## 4. Migration 013 — payments, analytics, bulk products

Run:

`backend/migrations/013_payments_analytics_bulk_import.sql`

Creates:
- pending receivables/payables RPC
- top products/top customers/daily sales insights
- protected bulk product import which reuses `inventory_create_product`

Customer and supplier bulk import is performed from Flutter by repeatedly calling the already-protected existing `customers_create` / `suppliers_create` RPCs, so no duplicate backend master-data engine is introduced.

## 5. Migration 014 — module defaults

Run:

`backend/migrations/014_v3_module_catalog_defaults.sql`

Activates V3 tool modules and adds them to business templates. Existing active tenants get Logs and Invoice Templates enabled automatically. Payments and Bulk Import can be enabled from Admin as needed.

## 6. Migration 015 — username platform-admin RPCs

Run:

`backend/migrations/015_admin_username_invoice_rpcs.sql`

Moves platform-admin assignment/listing to usernames instead of email addresses.

## 7. Migration 016 — immutable tracking + activity viewer

Run:

`backend/migrations/016_tracking_and_business_audit.sql`

Makes tracking codes immutable, adds tracking lookup, and adds tenant business-audit viewing.

## 8. Deploy Edge Functions

Two new functions are under `backend/functions`.

### `username-login`

This function must be callable before a user has a JWT. Deploy it with JWT verification disabled.

If using Supabase CLI:

```powershell
supabase functions deploy username-login --no-verify-jwt
```

If using Supabase Dashboard Edge Functions, create/deploy `username-login` from the supplied `index.ts` and turn **Verify JWT OFF** for this function only.

### `manage-business-users-v3`

Deploy normally with JWT verification enabled:

```powershell
supabase functions deploy manage-business-users-v3
```

Keep the existing `manage-business-users` function deployed. V3 calls it internally for the privileged Auth create/reset/delete operations, then adds the username mapping.

Do not place the service-role key in any Flutter config. The service key is used only inside server-side Edge Functions through Supabase-managed environment variables.

## 9. Replace applications

Copy from this bundle into:

- `D:\ERP\flexi_erp\apps\admin_panel`
- `D:\ERP\flexi_erp\apps\client_app`
- `D:\ERP\flexi_erp\apps\pos_app`

For a clean replacement, replace the whole app folders rather than overlaying only `lib`, to avoid old stray files.

## 10. Analyze all three apps

Admin:

```powershell
cd D:\ERP\flexi_erp\apps\admin_panel
dart fix --apply
dart format lib
flutter analyze
```

Client:

```powershell
cd D:\ERP\flexi_erp\apps\client_app
dart fix --apply
dart format lib
flutter analyze
```

POS:

```powershell
cd D:\ERP\flexi_erp\apps\pos_app
dart fix --apply
dart format lib
flutter analyze
```

Target: `No issues found!` for all three. If any error appears, stop and fix it before runtime testing.

## 11. Runtime order

Admin Panel:

```powershell
cd D:\ERP\flexi_erp\apps\admin_panel
flutter run -d web-server --web-port=8080
```

Sign in with the generated username and the old password. Verify Businesses, Modules, Roles, Users, Invoice Templates, Error Logs.

Client:

```powershell
cd D:\ERP\flexi_erp\apps\client_app
flutter run -d windows
```

Verify username login, Dashboard, Sales autocomplete, Payments, Bulk Import, Logs, Activity Log, Tracking Lookup and invoice preview.

Standalone POS:

```powershell
cd D:\ERP\flexi_erp\apps\pos_app
flutter run -d windows
```

The test business must have the `pos` module enabled and the user must have the existing Sales/Inventory permissions plus `pos.use`.

## 12. Recommended permission checks

For an Owner, the normal owner-auto-permission logic should grant new permissions when their modules are enabled.

For restricted users, consider only what they need:
- `sales.edit`
- `sales.view_profit`
- `expenses.edit`
- `payments.view`
- `payments.receive`
- `bulk_import.manage`
- `logs.view`

Do not give cashiers cost/profit or edit privileges unless required.
