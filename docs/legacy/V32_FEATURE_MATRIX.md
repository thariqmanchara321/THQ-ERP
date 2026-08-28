# V3.2 feature matrix

| Requirement | V3.2 implementation |
|---|---|
| Client menu search | Sidebar/drawer menu filter + global Search ERP screen |
| POS product search | Name, SKU, barcode, part number, brand, category; category filter + sort |
| Terminal invoice numbers | Per-device counter/prefix; core immutable document number is retained |
| Optional POS modules | `business_devices.allowed_modules`; configurable per terminal |
| Automatic SKU | `inventory_next_sku`; UI Generate Next SKU; uniqueness pre-check on create/edit |
| Friendly entity IDs | Immutable tracking codes displayed as Product ID / Customer ID / Supplier ID |
| POS multi-step billing | Products → Payment → Confirm → reset |
| Quick cash | Exact + common denominations including 10/20/50/100/200/500/1000/2000 |
| Invoice preview | Optional 80mm or A4 after payment |
| Collapsible POS nav | Yes |
| UI polish | Material 3, responsive cards/navigation, consistent inputs/buttons |
| Admin Home | Home action on sub-pages |
| Owner manages staff | Client Team & Access + `manage-tenant-users-v32` |
| Select users for POS | Client/POS app access flags per user |
| Browser password manager | Username/password autofill hints and successful autofill context completion |
| Child store/POS directory | Client Stores & Systems screen |
| MAIN + child stores | Parent-child business locations |
| Store scoped reports/accounting/docs | V3.2 scoped RPCs + Client scope selector |
| Store scoped vertical workflows | Production runs, transport vehicles/jobs and Restaurant tables/orders/KOT are location-checked server-side |
| Store role restrictions | Location access: View / Operate / Manage + server-side checks |
| Atomic scoped creates | Sale/Purchase/Expense wrappers rollback when store/device access fails |

## Financial record editing policy

Posted financial records are not hard-deleted. Expense editing and safe Sale metadata editing remain audited. Direct destructive deletion or arbitrary line mutation of posted Sales/Purchases is intentionally not added because it would desynchronize stock, tax, payments, COGS and accounting. A later reversal/void workflow should reverse those ledgers atomically.
