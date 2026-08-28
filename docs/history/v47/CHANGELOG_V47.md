# THQ ERP 4.7.0

## Foundation Lock & Production Stabilization

### Backend
- Added migrations 101–110 on top of the confirmed v4.6 migration-100 baseline.
- Accounting posting failures for core origin-linked documents now abort the transaction instead of being silently swallowed.
- New businesses automatically receive required THQ accounting system accounts/mappings; existing tenants are backfilled safely.
- Added request-ID transaction ledger and retry-safe v4.7 RPC wrappers.
- Added physical installation history and atomic activation claim while preserving existing logical system IDs.
- Hardened branch available-stock mutation under row lock.
- Added System Health/integrity scanner.
- Changed app-access fallback to fail closed.
- Heartbeat now updates physical installation status/history.

### POS
- Checkout uses `sales_create_v47`.
- Checkout request ID persists across retry until successful reset, reducing duplicate invoices after lost responses.
- Core payment/return/void/expense/shift service calls use v4.7 retry-safe APIs.
- Version updated to 4.7.0+1.

### Client
- Core sale/purchase/payment/return/expense service calls use v4.7 retry-safe APIs.
- Backend compatibility is checked before business bootstrap.
- Version updated to 4.7.0+1.

### Admin
- Added business System Health screen.
- Existing v4.6 configured-system activation flow remains compatible with v4.7 installation history.
- Version updated to 4.7.0+1.

### Shared core
- Replaced sample calculator package with THQ release contract, fixed-minor-unit `Money`, and standard `ErpFailure` primitives.
- Client and POS now consume the shared package.
