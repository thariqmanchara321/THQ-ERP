# Inventory Reports

Inventory Reports is part of the main desktop ERP workspace. It appears in the
main menu for users who can view both Inventory and Reports. It also opens from
the Inventory toolbar and Reports Center. Existing inventory transaction screens
continue to use their existing services and writers.

| Report | Content | Date basis |
| --- | --- | --- |
| Stock overview | Physical, available, reserved, damaged and quarantined stock; SKU, store, base unit, tracking mode and stock status | Current balances |
| Stock valuation | Current location average cost, physical value, available value and held value | Current balances and current costs |
| Stock statement | Opening, receipts, issues, closing and ledger variance | Posting dates in the business timezone |
| Stock movements | Posting type, readable document number, quantities, before/after balances and notes | Posting dates |
| Reorder planning | Low/out of stock, reorder/max levels, net sales velocity, days of cover and suggested replenishment | Current balances and selected activity lookback |
| Stock activity | Last inbound and sale activity, slow/non-moving lines and days of cover | Current balances and selected activity lookback |
| Batch stock | Batch number, quality, quantities, manufacture/expiry dates and status | Current batch balances |
| Expiry watch | Positive batch stock already expired or expiring within the chosen horizon | Today in the business timezone |
| Serial register | Serial status, store, receipt/sale dates and purchase/invoice numbers | Current serial status |
| Warranty register | Customer, invoice, serial/batch, coverage dates, quantity and current status | Selected coverage expiry dates |
| Stock transfers | Requested, dispatched, received and in-transit quantities, status and transport reference | Transfer creation dates and current status |
| Stock counts | System/physical quantities, variance, count reference and draft/posted status | Count creation dates |
| Stock and tracking checks | Physical stock versus movement ledger and current batch/serial stock | Current balances |
| Tracking events | Batch/serial events, references, quantities and trace-only conversion markers | Event posting dates |
| Tracking changes | Mode changes, revisions, reasons and authorized store snapshots | Conversion audit dates |

Search and filters run on the server before pagination. Sort a column by clicking
its header; click again to reverse it. Store scope follows the shared ERP store
selector. The report workspace uses compact controls and totals so the table gets most
of the desktop height. Each report shows its relevant columns. Product and SKU
share the first column, numbers and their headings align to the right, and the
columns fit the available width without horizontal scrolling. Store is omitted
when one store is selected; when a column is collapsed, its unit, store or document
reference remains attached to the appropriate row where needed. Narrow windows
use readable lists. The totals toggle provides additional table space. Opening a row shows readable details and saved
references. Internal UUIDs are removed from row previews and exported reports.

Summary figures include **all matching rows**, including undisplayed pages.
Physical quantities are grouped by the configured base unit: CFT, NOS and other
units are never added into a single quantity total. The module uses configured
unit conversions and does not assume a CFT-to-ton conversion.

Excel, PDF, print and JSON export fetch the entire matching dataset, preserve the
selected filters and sort, and refuse an incomplete result. Exporting over
50,000 matching rows requires a narrower period, store or product; the server
returns an explicit error instead of silently truncating. Excel includes the
full report columns, separate unit summaries and readable row evidence. PDF/print
uses the existing Unicode report fonts and export builder.

Stock statements reconstruct historical quantities from current location
balances and subsequent postings. They do not reconstruct historical average
cost or FIFO inventory layers. Stock activity measures time since postings,
not the age of each surviving stock layer. Ledger/tracking gaps are displayed
for review; reports never repair or change inventory. Retired batch/serial
evidence stays available when tracking modes change. Conversion audit reporting
is optional on backends that do not have the conversion history table.

The backend enforces active membership, both module permissions, enabled
Inventory/Reports modules, and authorized locations. Valuation additionally
requires `inventory.view_cost`. Cost fields are removed before search, summaries,
pagination and export for other users. Public RPCs use SECURITY INVOKER wrappers
over a private gateway. Anonymous execution and direct stock/row helper execution
are revoked. Device permissions and subscription entitlements also control the
client entry points.

## Installation and validation

This compact UI revision changes client presentation only and needs no database
migration. The installer detects the existing module and applies its UI update;
fresh installations receive the full module with the same compact layout.

The main ERP backend has the two additive Inventory Reports migrations applied.
They add reporting routines only. Sales, purchases, GST, Staff, accounting,
inventory writers and existing stock data are not modified by these migrations.
No test backend migration is required for this release.

The source builds on checkpoint `c468b9c36b58ff463bd24b69bc4c95364c9560bd`, preserving
the latest Material Yard, Reports Center, tracking, invoice and Staff changes.
Apply the supplied update package to the existing main ERP checkout and rebuild
the Windows client to display the new module. The package uses checked Git
patches and backs up changed source files. It preserves local changes in other
files and does not change the checkout's branch or backend configuration.
GitHub publishing was blocked by the connection's HTTP 403 response, so the
remote main branch has not yet received this module.

```powershell
Set-Location D:\ERP\flexi_erp
& '<extracted-package>\Apply-InventoryReports.ps1' -TargetPath D:\ERP\flexi_erp -LaunchWindows
```

`backend/tests/inventory_reports_v635_regression.sql` verifies all 15 report
datasets, stock and valuation arithmetic, units, complete exports, pagination,
filters, movement ordering, permissions, location scope and cost redaction using
existing authorized members. It writes only temporary verification results and
rolls back. `test/inventory_reports_v635_test.dart` covers window sizes, large
text, readable row details, access gates, stale requests, shared scope, sorting,
pagination and complete exports over 5,000 rows.

`test/inventory_report_table_test.dart` verifies all 15 report layouts against the
report catalog at desktop, compact and narrow widths, including 150% text,
vertical-only scrolling, numeric heading/value alignment, row evidence, scoped
store columns and batch identities.
