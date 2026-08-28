# THQ ERP v4.8.2 — Release Acceptance

## Database
- [ ] Backup created.
- [ ] Migrations 130, 131, 132, 133 and 134 applied in order.
- [ ] `thq_backend_contract_v47()` reports 4.8.2 / migration 134.
- [ ] `thq_v482_release_verify()` reports `ready=true`.
- [ ] Updated `thq-api` deployed.

## Flutter quality gate
- [ ] Run `tools/validate_v482_windows.ps1`.
- [ ] Admin analyze: no issues.
- [ ] Client analyze: no issues.
- [ ] POS analyze: no issues.
- [ ] erp_core/Admin/Client/POS tests pass.
- [ ] No `use_build_context_synchronously` warning/info exists.

## Pricing
- [ ] Retail fallback price works.
- [ ] Wholesale list can be assigned to a customer.
- [ ] Dealer/Contractor list works.
- [ ] Quantity rule 1 / 10 / 50 chooses the greatest matching threshold.
- [ ] Customer-specific price overrides the assigned list.
- [ ] Unit-specific prices work (e.g. Meter vs Coil).
- [ ] POS reprices after customer selection.
- [ ] POS reprices after quantity/unit change.
- [ ] Client sale reprices after customer/quantity/unit change.
- [ ] Directly altered client price is rejected/overridden by backend authoritative pricing.
- [ ] Posted sale detail contains pricing source/provenance.

## Identification
- [ ] Existing SKU lookup works.
- [ ] Existing legacy barcode lookup works.
- [ ] Multiple barcodes can be added to one variant.
- [ ] Manufacturer code search works.
- [ ] Supplier code search works.
- [ ] Alternate SKU search works.
- [ ] Generated barcode is unique and scannable.
- [ ] Generated QR is unique and searchable.
- [ ] Duplicate active identifier in the same business is rejected.
- [ ] Archiving a code removes it from active POS scan/search.

## Labels
- [ ] Thermal 50×30 label previews/prints.
- [ ] Thermal 38×25 label previews/prints.
- [ ] A4 three-column labels print.
- [ ] QR template prints QR.
- [ ] Copies setting is respected.
- [ ] Business/product/price/SKU/code text display correctly.

## Regression
- [ ] v4.8.1 Unit/Coil/partial-quantity sale still works.
- [ ] Purchase/return remains correct.
- [ ] POS Hold/Resume remains correct.
- [ ] Customer partial payment remains correct.
- [ ] Cashier Shift and Terminal Daily remain correct.
