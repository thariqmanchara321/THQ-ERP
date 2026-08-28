# V2 test plan

## Flutter static checks
Client:
```
cd D:\ERP\flexi_erp\apps\client_app
dart fix --apply
dart format lib
flutter analyze
```

Admin:
```
cd D:\ERP\flexi_erp\apps\admin_panel
dart fix --apply
dart format lib
flutter analyze
```

## Admin runtime
Run web server and open http://localhost:8080

Verify:
1. Existing Super Admin login/logout.
2. Platform metrics load.
3. Businesses still open.
4. Modules screen lists POS/Settings/industry packs; edit a harmless description and save.
5. Templates list seeded templates.
6. Subscription plans list; review example pricing.
7. Platform Admins lists current admin after re-login.
8. Settings loads global defaults.
9. Audit log shows V2 configuration changes.
10. Existing business → Subscription can assign Trial/Business/Professional.
11. Existing business → Modules can enable POS. If assigned plan does not include a module, backend must reject it.
12. Existing Users/Roles screens still work.

## Client runtime
1. Login with an actual tenant member, not platform Super Admin.
2. Existing Dashboard/Inventory/Sales/Purchases/Customers/Suppliers still load.
3. Verify a known product stock before POS.
4. Enable POS in Admin and ensure user role has both the sales permission required by your existing sales RPC and `pos.use`.
5. Re-login client to refresh session.
6. Open POS; search/scan a product; add quantity 1; choose Walk-in Customer; Cash; Complete Sale.
7. Verify a SAL number was created, sale appears in Sales, stock decreased exactly by quantity sold, and movement history shows the sale.
8. Test UPI/Card checkout.
9. Test a non-walk-in Credit sale only if your existing sales_create permits credit sales and credit limit is sufficient.
10. Open Business Settings as Owner and save a harmless invoice footer. Re-login and verify settings still load.
11. Assign a plan that excludes POS, re-login, verify POS disappears.
12. Set subscription suspended, re-login, verify restricted client view/banner.

## Regression rule
If any existing Inventory/Sales/Purchase behavior changes unexpectedly, stop and restore the backed-up app/database function before continuing. V2 should extend those engines, not rewrite them.
