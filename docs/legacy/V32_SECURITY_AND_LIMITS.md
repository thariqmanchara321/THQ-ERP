# V3.2 security and known limits

## Identity

- Public login is Username + Password.
- Username minimum: 4 characters and globally unique.
- Account password minimum remains 8 characters. Four-character account passwords are intentionally not supported.
- Supabase Auth still uses a server-managed synthetic email internally; users do not need to know it.
- Service-role credentials exist only in Edge Functions, never Flutter.

## Device activation

- Client/POS installations must be registered.
- A revoked device cannot log in.
- POS terminals are locked to their assigned location for financial posting.
- Client systems can post to a selected location only when the signed-in user has Operate/Manage access there.

## Location access

- View: read permitted documents for that location.
- Operate: View + create/normal work for that location.
- Manage: Operate + location administration where the relevant permission allows it.
- `locations.view_all` permits merged/all-store reads but does not grant writes.
- `locations.manage_all` permits cross-store management.

## Vertical-module scoping

- Production recipes/BOMs remain tenant-wide shared configuration; production runs are store-scoped.
- Transport vehicles/jobs are assigned to stores and server-side location checked.
- Restaurant tables/orders/KOT/status/billing are location + registered-device checked. POS restaurant access also honors that terminal's allowed module list.
- Products, customers and suppliers remain shared tenant master data; financial/operational documents are store-scoped.

## Financial integrity

V3.2 does not hard-delete posted Sales or Purchases. Stock/payment/tax documents require a future atomic reversal/void workflow.

## Physical branch stock

Document origin and reporting are store-aware in V3.2. Physical inventory quantity is not yet truly separated by business location because the live core stock SQL was not available to safely retrofit the existing moving-average/ledger functions. Use `EXPORT_LIVE_CORE_SQL_FOR_BRANCH_STOCK.sql` after V3.2 validation for that final upgrade.
