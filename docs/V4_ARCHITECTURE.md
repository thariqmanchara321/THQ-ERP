# Flexi ERP V4 Architecture

## Transaction layers

Business transaction engines remain centralized:

- Sale -> existing protected Sales engine -> V4 document origin -> physical branch stock -> accounting journal
- Purchase -> existing protected Purchase engine -> V4 document origin -> physical branch stock -> accounting journal
- POS -> same Sales engine; never a separate stock/accounting engine
- Restaurant billing -> same Sales engine
- Workshop/Transport billing should continue converging on the same Sales engine

## Inventory model

Company master:

`products -> product_variants`

Company aggregate compatibility ledger:

`stock_balances + stock_movements`

V4 physical store layer:

`location_product_settings`
`location_stock_balances`
`location_stock_movements`

Transfers move branch balances only and must not change company aggregate quantity.
External purchases/sales/returns/count variances update both appropriate ledgers.

## Accounting model

`accounting_accounts`
`accounting_account_mappings`
`journal_entries`
`journal_lines`

Operational transactions generate accounting entries. Financial reporting should increasingly derive from the journal rather than independently summing unrelated tables.

## Identity / authorization

Access requires the intersection of:

- tenant membership
- active subscription/module entitlement
- user permission
- location access
- terminal/device module access where applicable

Flutter UI visibility is convenience only. Critical authorization is enforced by backend RPC/functions.

## Document identity

Every financial document can have several identifiers with different purposes:

- Internal UUID — immutable database identity
- Friendly tracking code — support/audit lookup
- ERP business document number — e.g. `SAL-000123`
- Branch/terminal invoice number — e.g. `CAL-POS01-INV-000043`

Do not replace immutable identifiers with user-editable display numbers.

## Corrections

Posted documents should not have financial lines silently rewritten.
Use:

- return
- credit/debit adjustment
- void where safe
- reversal/recreate

This preserves stock, tax, payment and accounting history.
