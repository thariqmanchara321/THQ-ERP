# Flexi ERP V4 Installation Steps

## A. Back up before upgrading

1. Make a full copy of `D:\ERP\flexi_erp`.
2. Keep the current working V3.2 app folders until V4 passes runtime tests.
3. Do not delete old Edge Functions while testing V4.

## B. Database migration order

The current live project already has `001`–`029` successfully installed.
Run ONLY `030`–`060` now, one at a time:

030_v4_branch_inventory.sql
031_v4_branch_transactions.sql
032_v4_stock_transfers_counts.sql
033_v4_returns_reversals.sql
034_v4_cashier_shifts.sql
035_v4_accounting_core.sql
036_v4_accounting_posting_registers.sql
037_v4_invoice_printing.sql
038_v4_backup_export.sql
039_v4_notifications_tasks_files.sql
040_v4_approvals_custom_fields.sql
041_v4_saved_views_activity.sql
042_v4_release_support.sql
043_v4_industry_phase2.sql
044_v4_reports_analytics_gst.sql
045_v4_modules_permissions_templates.sql
046_v4_runtime_search.sql
047_v4_verify.sql
048_v4_scoped_dashboard_reports.sql
049_v4_final_verify.sql
050_v4_complete_backup.sql
051_v4_actor_attribution.sql
052_v4_final_verify_complete.sql
053_v4_return_accounting_balances.sql
054_v4_financial_verify.sql
055_v4_configuration_notifications.sql
056_v4_final_verification.sql
057_v4_workshop_operations.sql
058_v4_verify_everything.sql
059_v4_location_branding_invoice_context.sql
060_v4_absolute_final_verify.sql
061_v4_rpc_security_hardening.sql
062_v4_release_candidate_verify.sql

Expected final status:

`FLEXI ERP V4 RELEASE CANDIDATE VERIFICATION PASSED`

STOP on any SQL error. Do not continue to later migrations until the error is fixed.

## C. Edge Functions

V4 uses the existing deployed functions from V3.2:

- username-login
- device-activate
- manage-business-users-v31
- manage-tenant-users-v32

No new V4 Edge Function is required by the core V4 migrations.
If the local function source needs to be redeployed, copy the relevant folder from `backend/functions` into `supabase/functions` and deploy with the same established CLI process.

## D. Replace application folders

Replace the complete folders, not only `lib`:

- `apps/admin_panel`
- `apps/client_app`
- `apps/pos_app`

The Client Windows CMake target is deliberately kept as `client_app` to avoid the previous `No target` mismatch.

## E. Analyze all apps

From the V4 root:

`powershell -ExecutionPolicy Bypass -File .\tools\analyze_all.ps1`

Or manually run `flutter pub get`, `dart fix --apply`, `dart format lib`, and `flutter analyze` inside each app.

Target: `No issues found!` for all three.

## F. Runtime smoke test order

1. Admin username login.
2. Business / Modules / Subscription.
3. MAIN location and existing devices.
4. Client activation/login.
5. POS activation/login.
6. Inventory by MAIN.
7. Create child store.
8. Assign product to child store.
9. Stock transfer MAIN -> child store.
10. Sale from MAIN.
11. Sale from child store.
12. Purchase into selected store.
13. Sale return.
14. Purchase return.
15. Cashier shift open/close.
16. A4 invoice print preview.
17. 80mm invoice print preview.
18. Accounting registers.
19. Dashboard/Reports by store and All Stores.
20. Backup export.
21. Notifications/support/app-version heartbeat.

## G. Release builds

After runtime stabilization:

`powershell -ExecutionPolicy Bypass -File .\tools\build_release.ps1`

Build targets:

- Admin Panel: Web
- Client ERP: Android APK, Windows, Web
- Flexi POS: Android APK, Windows

Do not distribute release builds until V4 test plan passes against a staging/test tenant and then a controlled real-business pilot.
