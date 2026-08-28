# Requested feature matrix — V3.1

| # | Request | V3.1 state |
|---|---|---|
| 1 | Username/password login | Implemented Admin/Client/POS |
| 2 | Unique username, min 4 | Implemented. Password remains 8+ for account security |
| 3 | Trackable unique IDs | Implemented readable IDs + existing UUIDs for core and new entities |
| 4 | Error/issues logs | Implemented Admin/Client/POS logs + business audit |
| 5 | Separate POS | Implemented as `apps/pos_app` |
| 5a | Selected product details | Implemented |
| 5b | Easy cash values | Implemented quick cash controls |
| 5c | Product/customer/supplier maintenance from POS | Reuses existing module screens when enabled/permitted |
| 5d | Expense/purchase from POS | Reuses existing screens when enabled/permitted |
| 6 | Privileged edits | Expense edit + safe Sale metadata edit with audit. Monetary sale-line mutation intentionally blocked |
| 7 | Admin invoice template manager | Implemented with samples/logos |
| 8 | A4/80mm GST/phone templates | Implemented design/assignment/preview foundation |
| 9 | Bulk data | Existing V3 bulk import retained/extended |
| 10 | Pending payments | Payment Center retained |
| 11 | Top products/customers | Dashboard V3 insights retained |
| 12 | Sale item type-ahead | Existing Autocomplete retained |
| 13 | Smoother/graphs/design | Material 3 + dashboard cards/charts/clean navigation retained and expanded |
| 14 | Production + service | Implemented Production and Transport Service modules |
| 14a | Raw materials -> finished stock | Production BOM + run through inventory adjustment; purchases shortcut |
| 14b | Taxi/truck service | Vehicle + route + distance + quantity/rate job records |
| 14c | Linked | Service jobs can link to normal Sales; production links inventory/purchases |
| 15 | Restaurant | Operational restaurant/KOT workflow implemented |
| 15a | KOT/dine-in/takeaway | Implemented |
| 15b | Table selection in POS | Restaurant workspace available in POS |
| 15c | Preparation timing | Implemented |
| 15d | Chef note | Implemented |
| 15e | Delivery/billing/finalize | Implemented; final bill uses Sales engine |
| 16 | APK/EXE/Web targets | Project targets prepared. Build binaries on Flutter workstation |
| 17 | One-time system login/ID | Implemented device activation + unique terminal ID |
| 18 | Multiple POS/child stores | Implemented locations/devices, origin tracking, local invoice number and separate/merged reporting |

## Important boundary: branch stock
The existing live Sales/Purchase/Inventory RPC bodies were not included in the uploaded project files. V3.1 therefore does NOT guess or rewrite the stock ledger to make physical stock balances branch-specific. New documents are accurately tagged to branch/device and receive branch-local billing numbers, but the existing transaction engine still posts stock according to its current inventory-location logic.

To safely implement independent branch stock next, run the read-only SQL in `EXPORT_LIVE_CORE_SQL_FOR_BRANCH_STOCK.sql` and provide the function definitions. Then the stock engine can be upgraded without losing moving-average costing, negative-stock protection or ledger integrity.
