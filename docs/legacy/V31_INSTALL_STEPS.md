# Flexi ERP V3.1 installation steps

## 0. Back up first
Make a full copy of `D:\ERP\flexi_erp` before replacing app folders or running SQL.

## 1. Do not rerun 001-009
Your live Supabase project already has migrations 001-009. V3.1 starts at 010.

## 2. Run migration 010 only
In Supabase SQL Editor run:
`backend/migrations/010_v31_identity_tracking.sql`

If it fails, STOP and send the exact error. Do not continue.

After 010 succeeds, save the generated usernames:

```sql
select
  n.username,
  u.email,
  n.user_id
from public.user_login_names n
join auth.users u on u.id = n.user_id
order by u.email;
```

Existing passwords are unchanged.

## 3. Run the remaining migrations one at a time

1. `011_error_logs_audit_edits.sql`
2. `012_invoice_templates_business_settings.sql`
3. `013_payments_analytics_bulk_import.sql`
4. `014_v31_locations_devices.sql`
5. `015_v31_production_service.sql`
6. `016_v31_restaurant.sql`
7. `017_v31_tracking_location_reports.sql`
8. `018_v31_modules_templates_permissions.sql`
9. `019_v31_admin_identity_devices.sql`
10. `020_v31_verify.sql`

Stop on the first error. `020` should return `V3.1 backend verification passed`.

## 4. Deploy Edge Functions
From the project root where the Supabase CLI is linked to `flexi-erp-dev`:

```powershell
supabase functions deploy username-login --no-verify-jwt
supabase functions deploy device-activate --no-verify-jwt
supabase functions deploy manage-business-users-v31 --no-verify-jwt
```

Keep the existing `manage-business-users` Edge Function deployed. V3.1 wraps it rather than replacing its proven Auth-management workflow.

The three V3.1 functions perform their own authentication/authorization where required. Do not place a service-role/secret key in any Flutter app.

## 5. Replace app folders
After SQL + Edge Functions succeed, replace the complete folders rather than overlaying old `lib` files:

- `D:\ERP\flexi_erp\apps\admin_panel`
- `D:\ERP\flexi_erp\apps\client_app`

Add:
- `D:\ERP\flexi_erp\apps\pos_app`

This avoids stale files from earlier versions.

## 6. Analyze all three apps

### Admin
```powershell
cd D:\ERP\flexi_erp\apps\admin_panel
dart fix --apply
dart format lib
flutter analyze
```

### Client
```powershell
cd D:\ERP\flexi_erp\apps\client_app
flutter pub get
dart fix --apply
dart format lib
flutter analyze
```

### POS
```powershell
cd D:\ERP\flexi_erp\apps\pos_app
flutter pub get
dart fix --apply
dart format lib
flutter analyze
```

Do not continue until all three report `No issues found!`.

## 7. Sign in to Admin using username
Run the Admin Panel, sign out any old session and log in with the username generated after migration 010 plus the existing password.

## 8. Configure a business location and systems
Open Business -> Locations & Systems.
The migration creates a MAIN location for existing tenants.
Create extra child stores if needed.

For each installation choose the branch, choose Flexi ERP Client or Flexi POS, give the counter/system a name and click Activate System.
Save the one-time Business Code + Activation Code shown. The activation code expires in 24 hours and is consumed once.

## 9. Activate Client/POS installation
On first launch, enter the Business Code + one-time Activation Code. After activation the installation stores its device registration securely and displays normal username login.

## 10. Test in order
Use `docs/V31_TEST_PLAN.md`.
