# THQ ERP v4.7.3 — Live Operations Polish

v4.7.3 is the final planned v4.7 UX/synchronization release. It does not add the v4.8 THQ API, offline engine, or mobile applications.

## Refresh / synchronization
- Added explicit Refresh actions to Admin, Client, and POS.
- Client/POS Refresh reloads the current business, modules, permissions, runtime store/system assignment, navigation, UI configuration, and remounts the active module so its data is fetched again.
- Runtime system/store metadata is written back to secure local activation metadata without changing the installation secret. A POS moved to another store therefore uses the new store for subsequent transactions after Refresh; reactivation is not required.
- Explicit Refresh uses strict runtime-context and navigation loading: it reports an error instead of silently claiming success with stale system/store configuration.
- POS warns before refreshing Billing because refreshing remounts the live billing screen; an unheld cart should be completed or held first.

## POS Hold / Resume
- Removed the always-visible/horizontal held-invoice strip.
- Resume now switches the billing workspace to a dedicated Held Invoices page.
- Held invoices use a responsive product-style grid.
- Cards show hold code, optional label, customer, item count, time, and total.
- Selecting a card restores the held cart/customer/discount/payment state and returns to Products.
- Back/Products closes the Held Invoices view without changing the current transaction.
- A current non-empty cart must be held or cleared before opening another held invoice.

## Today-only POS operations
The live POS is intentionally an operational view, not a historical browser.
- Sales list: current local day + exact activated POS only.
- Purchase list: current local day + exact activated POS only.
- Expense list: current local day + exact activated POS only.
- Return source search: current local day + exact activated POS only.
- Cashier Shift history: today's shifts only.
- Older invoices/history are accessed from Terminal Daily.

## Terminal Daily
- Remains read-only and summary-first.
- Select any historical date up to today.
- Previous/next-day controls added.
- Daily summary remains compact: sales, returns, net sales, collections, outstanding, payment methods, customer receipts, purchases, expenses, cash movements, and aggregate cashier-shift figures.
- Detailed cashier-shift rows are removed from the v4.7.3 report payload/exports.
- `View Invoices` provides on-demand invoice drill-down for the selected date and exact POS.
- Invoice search supports invoice number, sale number, or customer.
- Opening an invoice uses the normal sale detail screen; returning from it refreshes the daily summary and invoice list.

## Backend
Migration `119_v473_live_operations_polish.sql` adds:
- `pos_terminal_day_v473`
- `pos_terminal_invoices_v473`
- `pos_sales_today_v473`
- `pos_purchases_today_v473`
- `pos_expenses_today_v473`
- `pos_return_documents_today_v473`
- backend compatibility contract `4.7.3 / migration 119`

## Versions
- THQ Admin: `4.7.3+6`
- THQ Client: `4.7.3+6`
- THQ POS: `4.7.3+6`
- `erp_core`: `4.7.3`
- Database migration: `119`

## Build +7 — POS Hold Workspace Hotfix

- Fixed intermittent Flutter `dependents.isEmpty` assertion while holding a sale by removing the modal Hold dialog and its transient controller lifecycle.
- Hold references/customer names are explicitly allowed to repeat; the backend `hold_code` remains the unique identifier.
- Added a dedicated POS center workspace state: Products / Hold / Held Invoices.
- Hold entry now opens only in the center product workspace while the cart and POS shell remain mounted.
- Resume/Held Invoices stays only in the center product workspace and returns to Products when closed or restored.
- Established the center workspace as the pattern for future POS billing sub-workflows/editors.
- No database migration required; backend remains migration 119.
