# v4.8.3 release acceptance

Accept the release only after all of the following pass:

- Database reports schema `4.8.3`, migration `139`, release verify `ready=true`.
- Serial receipt with N base units requires exactly N unique serial numbers.
- Existing serial stock registration exactly matches ledger stock and adds no stock quantity.
- Selling a serial marks that serial sold and links supplier/purchase/customer/sale history.
- Batch receipt quantity reconciles to stock; manufacture/expiry dates persist.
- Batch sale consumes eligible stock in FEFO order by default.
- Expired batch stock is skipped unless the product policy permits expired sale.
- Warranty is created only when enabled and expiry matches the configured period.
- Serial and batch searches obey the user's store/location scope.
- POS serial scan resolves the product, prevents duplicate serials, survives Hold/Resume and posts the same serial at checkout.
- Generic adjustment/count/transfer/return/void attempts for tracked products are rejected rather than desynchronizing trace stock.
- `python tools/verify_v483_release.py` passes.
- Flutter analyzer/tests pass on the build machine; release builds pass when `tools/validate_v483_windows.ps1 -Build` is used.
