# THQ ERP v4.7.2 Changelog

## Terminal Operations Redesign

- Cashier Shift and Terminal Daily are now independent POS modules.
- Cashier Shift owns shift start/end state and cash accountability.
- Terminal Daily is a read-only daily summary and cannot alter shift state.
- Shift start/end timestamps default automatically and are editable.
- Opening/closing cash values are editable.
- Added audited shift corrections with before/after snapshots and mandatory reason.
- Added owner/`pos.shift_manage` protection for closed-shift corrections.
- Added overlap protection for cashier shifts on the same terminal.
- Prevented disabling Cashier Shift while an open shift exists.
- Terminal Daily can be enabled/disabled at any time because it owns no operational state.
- Terminal Daily now summarizes sales, tax, discounts, returns, collections, customer receipts, purchases, expenses, cash-in/cash-out and cashier shifts.
- Removed legacy transaction-detail arrays from Terminal Daily response so it remains a summary report.
- POS navigation and billing continue to use effective module gating.

## Release contract

- Admin: `4.7.2+5`
- Client: `4.7.2+5`
- POS: `4.7.2+5`
- erp_core: `4.7.2`
- Minimum database migration: `118`
