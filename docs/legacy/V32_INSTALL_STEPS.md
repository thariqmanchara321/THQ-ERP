# V3.2 installation steps

## A. Flutter apps

Replace these complete folders from the V3.2 bundle:

- `D:\ERP\flexi_erp\apps\admin_panel`
- `D:\ERP\flexi_erp\apps\client_app`
- `D:\ERP\flexi_erp\apps\pos_app`

Then run:

```powershell
cd D:\ERP\flexi_erp\apps\admin_panel
flutter pub get
dart fix --apply
dart format lib
flutter analyze

cd D:\ERP\flexi_erp\apps\client_app
flutter pub get
dart fix --apply
dart format lib
flutter analyze

cd D:\ERP\flexi_erp\apps\pos_app
flutter pub get
dart fix --apply
dart format lib
flutter analyze
```

All three must report `No issues found!` before runtime testing.

The V3.2 Client Windows project intentionally keeps `BINARY_NAME "client_app"` to avoid the CMake target mismatch previously seen on this machine.

## B. Supabase migrations

Your database already has 001–020. Run only these new files, one at a time, stopping on any error:

1. `021_v32_terminals_access_codes.sql`
2. `022_v32_device_modules_locations_users.sql`
3. `023_v32_scoped_operations_search.sql`
4. `024_v32_team_permissions_templates.sql`
5. `025_v32_verify.sql`
6. `026_v32_atomic_scoped_transactions.sql`
7. `027_v32_verify_final.sql`
8. `028_v32_vertical_location_security.sql`
9. `029_v32_verify_verticals.sql`

Expected final row:

`Flexi ERP V3.2 complete backend verification passed`

## C. Edge Functions

Copy the bundle function folders into `D:\ERP\flexi_erp\supabase\functions\`.

Redeploy the V3.2 username login because it now enforces application + store access:

```powershell
cd D:\ERP\flexi_erp
npx.cmd supabase functions deploy username-login --no-verify-jwt
```

Deploy Client-side owner/team management:

```powershell
npx.cmd supabase functions deploy manage-tenant-users-v32 --no-verify-jwt
```

`device-activate` does not need a V3.2 redeploy if the already-working V3.1 function is still deployed.

Keep the existing Admin user-management function(s) deployed because Admin still needs to create/manage the initial Owner during business provisioning.

## D. First runtime refresh

After SQL + function deployment:

1. Sign out of Admin, Client and POS.
2. Admin: verify Business → Locations & Systems.
3. Configure allowed modules separately for each POS terminal.
4. Client Owner: open Team & Access and choose which users can use POS and which store(s) they may view/operate/manage.
5. Client: choose a store scope from the header.
6. POS: sign in again so terminal module settings are reloaded.

## E. Release builds

Use `tools\build_release.ps1`, or manually:

```powershell
# Client
cd D:\ERP\flexi_erp\apps\client_app
flutter build apk --release
flutter build windows --release
flutter build web --release

# POS
cd D:\ERP\flexi_erp\apps\pos_app
flutter build apk --release
flutter build windows --release
```
