# Flexi ERP V4 Feature Matrix

Status meanings:

- **Operational V4**: backend + primary UI/workflow included in this package.
- **Foundation V4**: schema/RPC/configuration base exists, but the complete end-user workflow is not finished.
- **Future**: intentionally remains after V4 stabilization.

## Core

| Feature | Status | Notes |
|---|---|---|
| Multi-tenant isolation | Operational V4 | Existing architecture retained and extended. |
| Username login | Operational V4 | Existing V3.1/V3.2 Edge Function flow retained. |
| Device activation | Operational V4 | Existing one-time business/device activation retained. |
| MAIN + child stores | Operational V4 | Client owner can manage stores/devices. |
| Per-terminal modules | Operational V4 | Existing V3.2 control retained. |
| Store-scoped users | Operational V4 | Existing V3.2 access model retained. |
| Friendly tracking IDs | Operational V4 | Existing immutable tracking model retained. |

## Inventory

| Feature | Status | Notes |
|---|---|---|
| Physical branch stock | Operational V4 | New branch ledger and balances. |
| Product assignment per store | Operational V4 | Product master is company-level; availability/settings are store-level. |
| Branch selling price/reorder/rack | Operational V4 | Store settings supported. |
| Stock transfer | Operational V4 | Request/create, dispatch, receive. |
| Physical stock count | Operational V4 | Variance posts to branch + aggregate ledger. |
| Damaged/quarantine workflows | Foundation V4 | Columns/movement types exist; full dedicated UI still future. |
| Batch/serial/expiry | Future | Roadmap retained. |
| Barcode label designer/printing | Future | Existing barcode module retained; full V4 label subsystem not completed. |

## Sales / Purchases

| Feature | Status | Notes |
|---|---|---|
| Branch-aware Sale | Operational V4 | Calls existing proven core engine then posts physical store movement. |
| Branch-aware Purchase | Operational V4 | Calls proven purchase engine then receives branch stock. |
| Sale Return | Operational V4 | Item-level quantity validation, stock + accounting reversal. |
| Purchase Return | Operational V4 | Item-level stock + accounting reversal. |
| Unpaid Sale/Purchase Void | Operational V4 | Reason required; stock/accounting reversed. |
| Paid document direct void | Blocked intentionally | Use return/refund/credit workflow rather than corrupting history. |
| Quotation / Sales Order / Delivery Note | Future | Roadmap item after core V4 stabilization. |
| Purchase Request / PO / GRN | Future | Roadmap item after V4 stabilization. |

## POS

| Feature | Status | Notes |
|---|---|---|
| Separate POS app | Operational V4 | Windows + Android project. |
| Product/customer/order screen | Operational V4 | Search/category/sort/customer in catalog area. |
| Compact cart | Operational V4 | More lines visible. |
| Payment page | Operational V4 | Discount moved here; compact method selector; quick cash. |
| Final Review & Confirm | Operational V4 | No transaction posting until final confirmation. |
| Auto reset next customer | Operational V4 | After successful sale. |
| Per-terminal modules | Operational V4 | Existing backend terminal entitlements. |
| Cashier shifts | Operational V4 | Open, cash movements, close, variance. |
| Full offline transaction queue | Future | Preserve/retry architecture should be implemented after online V4 is stable. |

## Accounting

| Feature | Status | Notes |
|---|---|---|
| Chart of Accounts | Operational V4 | Add/edit/archive custom accounts; protect system accounts. |
| Cash / Bank / UPI / Card mappings | Operational V4 | Configurable. |
| Accounts Receivable / Payable | Operational V4 | Proper mapped accounts. |
| Sales Revenue / COGS / Inventory / GST | Operational V4 | Automatic journal mappings. |
| Customer/Supplier return credits | Operational V4 | Dedicated system accounts. |
| Automatic Sale/Purchase/Expense journals | Operational V4 | V4 accounting triggers. |
| Later payment settlement journals | Operational V4 | Customer/supplier payment triggers. |
| Sale/Purchase return journal reversal | Operational V4 | Return-aware. |
| Unpaid void reversal | Operational V4 | Posted source journal reversed. |
| Sales Register | Operational V4 | Date/store/search filters. |
| Purchase Register | Operational V4 | Date/store/search filters. |
| Cash Book | Operational V4 | Account-filtered register. |
| Bank/UPI/Card | Operational V4 | Combined register. |
| GST Register | Operational V4 | GST account register + summary. |
| General Ledger | Operational V4 | Journal line view. |
| Product-wise register search | Operational V4 | Name/SKU/part number matched against referenced Sale/Purchase. |
| Full statutory accounting close/lock | Foundation/Future | Period/fiscal roadmap remains. |

## Printing

| Feature | Status | Notes |
|---|---|---|
| A4 PDF | Operational V4 | PDF generated from Sale detail. |
| 80mm thermal PDF | Operational V4 | Compact receipt layout. |
| 58mm PDF | Operational V4 | Compact receipt layout. |
| System print dialog | Operational V4 | Client + POS. |
| PDF share/save action | Operational V4 | Client + POS. |
| GSTIN/phone/address/customer GST | Operational V4 | Uses business/branch invoice context. |
| Branch/terminal invoice number | Operational V4 | Separate from immutable ERP Sale number. |
| Business/branch logo URL | Operational V4 | Optional; gracefully omitted if inaccessible. |
| Invoice template editor | Operational V4 foundation | Existing Admin template management retained; layout parameters drive preview/PDF. |
| Direct silent thermal printing | Future | Keep explicit system print flow first for safety. |

## Reliability / Support

| Feature | Status | Notes |
|---|---|---|
| Error logs | Operational V4 | Existing Client/POS/Admin logging retained. |
| Support tickets | Operational V4 | Client + platform support screens. |
| Device heartbeat/version | Operational V4 | App/device/version status. |
| Full business JSON backup export | Operational V4 | Broad operational/config/accounting data export. |
| Automatic one-click restore | Future | Must be separately validated to avoid destructive restore mistakes. |
| Binary attachment upload | Foundation V4 | Metadata APIs/tables included; storage/upload UI remains. |

## Productivity

| Feature | Status | Notes |
|---|---|---|
| Unified global search | Operational V4 | Client search + menu search merged. |
| Notifications | Operational V4 | Low stock, overdue receivables, due tasks. |
| Tasks | Operational V4 | Basic internal tasks. |
| Activity timeline | Operational/partial | Sale/Purchase detail; generic backend timeline available. |
| Custom field definitions | Operational V4 | Manage definitions and metadata. |
| Custom values embedded in every entity editor | Foundation V4 | Values API exists; complete rendering in every industry form remains. |
| Approval rules/requests | Foundation V4 | Management/decision infrastructure exists; not automatically interposed on every transaction rule. |
| Saved views | Foundation V4 | Backend preference structures exist; full reusable UI across every table remains. |

## Industry Packs

| Feature | Status | Notes |
|---|---|---|
| Restaurant core | Operational V4 inherited | Dine-in/takeaway/delivery, KOT/table/prep/final billing from existing pack. |
| Restaurant Phase-2 | Foundation V4 | Modifier/waiter/table event backend extensions; full UI still future. |
| Workshop | Operational V4 core | Vehicles, job cards, search/status/update. |
| Workshop estimate->invoice/technician costing | Foundation/Future | Continue after pilot. |
| Production core | Operational V4 inherited | Existing production flow retained. |
| Production BOM/reservation | Foundation V4 | New schema base; full user flow not complete. |
| Transport | Operational V4 inherited | Existing transport/service workflow retained. |
| Pharmacy | Foundation | Not production-complete dispensing/compliance. |
| Clinic/Hospital | Foundation | Not production-complete clinical system. |
| Diagnostic Lab | Foundation | Not production-complete lab workflow. |

## Future integrations

WhatsApp/SMS gateways, payment gateways, e-commerce, Tally, scales, API/webhooks, advanced offline sync, AI automation, automatic updater infrastructure and advanced clinical systems remain post-V4 roadmap items.
