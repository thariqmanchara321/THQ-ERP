# Material Yard and Staff v5

The yard's Sales entry starts with Load Register. Create an outbound load, record its driver, truck, delivery and expenses, confirm it, and continue to the prefilled invoice. Existing sale history remains available under Sales Details. Inbound loads still continue to Purchase. Direct supply retains its existing separate workflow.

## Start after installing

Close the running client, apply the package, run its verifier, rebuild or run the client using your existing environment configuration, and sign in again. The Staff module and permissions are loaded at sign-in. This source update does not replace an already installed Windows executable until you rebuild it.

The connected **flexi-erp-dev** database already has the included migrations. The apply script copies matching migration source files and does not execute SQL. A different database requires those migrations in sequence after the existing v629 yard migrations, using the normal deployment process.

Owners receive Staff, load cost and invoice tax adjustment permissions. Managers receive Staff view/manage and load cost permissions; accountants receive Staff view/payroll, load costs and invoice tax adjustment; auditors receive Staff view. Existing user overrides, subscription limits and location restrictions continue to apply. A device with a restricted module list must also allow Staff. No passwords, server keys or environment settings are included in the package.

## Staff

Add a staff profile with contact details, role, joining/leaving dates, wage basis and rate, overtime rate, emergency contact and optional bank details. Choosing Driver creates or updates its linked logistics driver, including licence and phone. Existing logistics drivers have been retained and linked to Staff with a zero default rate; edit the rate before using it for wages. Deactivate departed staff rather than removing their financial history.

Staff supports monthly, daily, hourly and per-trip rates. Record attendance with status, hours and overtime. Payroll suggests units from the selected attendance period and the selected staff member's wage basis; check the units, rate, overtime, allowances and deductions before posting. Changing a date range does not post payroll automatically.

Payments settle the oldest outstanding earnings at the same location. Any excess becomes a staff advance. Later earnings apply available advances at that location. Payment method, reference and notes are retained. Overlapping payroll periods are rejected, and attendance inside a posted payroll period is locked. Current outstanding/advance balances are labelled separately from the filtered attendance/earnings/payment period.

Staff statements provide profiles, attendance, earnings, payments with allocations, monthly salary allocations to loads and audit history. Use the full record preview or export Excel, complete JSON or a PDF through the print dialog.

## Load expenses and customer charges

Add as many separate expense entries as needed: driver/staff wages, vehicle rent, diesel, loading/unloading, toll, freight or another expense. Each entry saves its quantity, editable cost rate, amount, payee, receipt reference, notes and any payment made on confirmation.

For a linked driver paid per trip, the driver's Staff rate is suggested. Choose the appropriate wage treatment:

| Treatment | Staff and accounts | Load cost |
| --- | --- | --- |
| Additional wage | Creates a wage earning and payable when the load is confirmed; payments reduce that balance | Included |
| Monthly salary allocation | Tracks the portion of monthly salary assigned to the load; monthly payroll remains the accounting entry | Included, without posting monthly payroll a second time |
| External expense | Posts the expense and payable; cash/bank payments reduce the payable | Included |

A monthly allocation cannot have a separate load payment. Pay the salary through Staff. An allocation is not a second salary payable, so it is not included in the load's unpaid expense total.

The **Amount charged to customer before GST** is separate from your internal cost. Leave it zero for an internal expense or enter the amount to recover from the customer. Select the invoice service used to classify that customer charge. You can create a service in the expense editor with the necessary permission. Registered GST businesses must enter the applicable SAC, treatment and rate; Non-GST businesses use zero GST. New charge services use tax-exclusive rates. A tax-inclusive service is rejected for a load charge so the entered before-tax amount cannot be changed by a default service price rule.

Several expenses billed using the same service become one combined service line, with the individual expense descriptions. Their individual costs, amounts charged, payees and payments remain in load evidence and reports. The service uses its explicit base unit, so a different default sales unit cannot multiply the charge. These charges are already included in the invoice total; the evidence printed below the invoice is informational and is not added again.

Draft expenses and delivery details are saved with the load. Confirmation posts incurred expenses and any initial payments together. Confirmation alone does not create the sale or post its stock/GST/revenue; invoice creation remains the existing authoritative transaction writer. Draft load edits can be saved without altering costs when the user lacks load cost permission. Cancel an unconfirmed load to keep its records. Confirmed or invoiced loads cannot be deleted/cancelled through this workflow.

You can pay an outstanding posted expense in Load Details, including partial payments, or use Staff payments for a linked wage. Repeat submissions reuse stable request IDs, and overpayments are rejected. After invoicing, additional expenses are internal only: the posted invoice remains fixed. Customer-billed entries must be added before creating the invoice.

## Editable invoice items

Use the item pencil in New Sale to edit quantity, unit, rate, discount, invoice description, tax rate when permitted, batch allocations and serial selections. A manual rate survives customer price-list refresh and is recorded in pricing metadata. An invoice description is saved in the authoritative line snapshot and appears when the invoice is reopened and printed.

Invoice-specific tax adjustments require owner or `sales.tax_override` permission. They do not edit the product master and cannot bypass missing GST profiles, required profile review, the active rate master or GST place-of-supply rules. A Non-GST invoice must remain at zero GST. Supply location can be entered as the two-digit GST state code when required, including service charges. Quotes and posting use the same authoritative GST calculations, including inclusive pricing, component tax and rounding. Changing amounts refreshes the quote and clears outdated payment allocations.

The invoiced material quantity must equal the confirmed physical load after unit conversion. Equivalent sale units are supported. Correct a draft load before confirming if its physical quantity is wrong.

## Driver, trip and delivery records

Transport & Logistics has a Back button in both the main workspace and a pushed route. Load Details links to the matching yard trip and vehicle. The existing shared trip hub continues to derive the physical load's status and links, avoiding a second independently entered yard trip.

New loads retain the selected driver's contact and licence by default. You can enter different driver/contact details and delivery addresses, pickup/delivery contacts, departure/delivery timestamps with timezone, odometers, both GPS coordinates, receiver name, proof reference and notes. Updates validate the combined saved record, preventing reversed delivery times and odometers even when only one field is changed.

The invoice saves load/driver/delivery/cost/payment evidence at invoice creation. Later delivery updates and payments are visible in the current load and reports; they do not silently rewrite that invoice evidence. Current driver/vehicle masters are clearly separate from saved delivery evidence. Old loads keep the details actually available in their existing records; unavailable historical information is not invented.

## Reports and accounts

Load Reports filters by period, location, vehicle and driver. Full records include measurements, physical load record, truck/driver records, linked trip, physical load events, route/delivery evidence, costs, customer charges, cost and staff payments, customer invoice/payments, old freight settlements and change history. There is no arbitrary row limit in this new report. Draft/cancelled costs are shown as recorded operational data and are labelled separately from posted liabilities.

Financial reports include posted Staff/load expenses and current staff advances/payables and external load payables. Excel adds load, expense, payment, event and Staff worksheets. Existing expenses and sales continue to use their established reports. Staff-linked wages are counted through Staff accounting, and monthly allocations do not inflate expenses/payables. The accounting journal remains the ledger authority.

Complete JSON preserves every nested saved field. Excel splits load child records into separate sheets and rejects a field exceeding Excel's cell limit instead of silently truncating it. PDF printing paginates extensive notes and expense evidence. Invoice A4, 80 mm and 58 mm formats include the saved load evidence and recorded expense payments, including internal expenses as requested.

## Verification

Completed here: full client source semantic/lint analysis with the exact locked package sources; 20 rollback-only database check groups covering payroll, advances, costs, invoice/GST calculations, idempotency, accounting, reports, driver/trip evidence and access guards; RLS/RPC privilege checks for all new tables/helpers; existing business record counts and historical fingerprints unchanged; A4/80 mm/58 mm invoice renderer smoke tests and visual inspection with extensive notes/expenses.

The PDF smoke harness excludes optional network logos/QR images and platform print/share adapters. Flutter widget tests and a Windows build are still to be run on your machine. The supplied verifier runs dependency resolution, full Flutter analysis and all existing/new tests for the client and logistics package. New tests cover form validation, duplicate-save protection, retry evidence, small-screen layout, driver wage defaults, salary allocation payment rules, charge classification, old invoices and long invoice pagination.

Before using a real customer invoice, exercise one load in your normal test environment: add driver wage and fuel, confirm, check the invoice quote, adjust the material rate/discount, verify the service charges, post with matching payments, reopen/print the invoice, record a partial expense payment and compare Staff, Load Reports and the ledger. Check Transport Back from both routes. For monthly staff, post payroll once and verify the load allocation does not create another salary entry.

## Apply and restore

The package validates all files before changing any source, checks package hashes, accepts matching v3/v4/v4.1 source through patches, preserves unrelated edits, backs up every changed file and rolls back a failed patch application. Conflicting local edits stop the whole apply before any source changes. Verification failures are reported with a transcript; they do not erase your changes.

Use the printed backup path with the Restore script if needed. Restore checks the applied files and backups first and refuses to overwrite later edits. It restores source only; it does not undo database migrations or remove operational records. Retain the backup and verification log until your Windows verification and workflow check pass.
