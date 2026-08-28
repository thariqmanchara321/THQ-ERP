# THQ ERP v4.7.2 — Terminal Operations Redesign

This release upgrades a THQ ERP v4.7.1 Hotfix 3 database at migration **117** to migration **118**.

## Scope

v4.7.2 redesigns **Cashier Shift** and **Terminal Daily** as independent POS capabilities.

### Cashier Shift
- Can be enabled/disabled independently per POS.
- Owns cashier session state and cash accountability.
- Start time defaults automatically to the current time but can be corrected.
- End time defaults automatically to the current time but can be corrected.
- Opening and closing cash are editable.
- Shift corrections require an audit reason and preserve before/after values.
- Closed shift editing is restricted to owner / `pos.shift_manage` users.
- Prevents overlapping shifts for the same terminal.
- Billing requires an open shift only when Cashier Shift is effectively enabled.

### Terminal Daily
- Can be enabled/disabled independently per POS.
- Is read-only and never starts, closes, or edits Cashier Shift.
- Summarizes daily sales, returns, payments, customer receipts, purchases, expenses, cash movements, outstanding values, and a read-only shift summary.
- Does not return the old transaction-detail arrays from the legacy Terminal Daily response.

## Upgrade prerequisite

The database must already be at migration **117**. Apply only migration **118**.

## Deployment

1. Back up the database.
2. Run `backend/upgrade_from_117/118_v472_terminal_operations_redesign.sql` (or the same migration from the upgrade ZIP).
3. Run `backend/V472_POST_UPGRADE_CHECK.sql`.
4. Confirm `thq_backend_contract_v47()` reports schema `4.7.2`, migration `118`, minimum app version `4.7.2`.
5. Build/run Admin, Client and POS v4.7.2+5.
6. Sign out and sign back into POS after upgrade so effective module state is refreshed.
7. Test all four Cashier Shift / Terminal Daily ON/OFF combinations before broad rollout.

## Runtime verification limitation

The packaged source passes the included static release verification. This packaging environment does not provide a Flutter SDK or live PostgreSQL/Supabase runtime, so Flutter compilation/tests and actual migration execution still need to be performed in your staging environment.
