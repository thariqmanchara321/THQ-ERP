# THQ ERP v4.7.1 — Hotfix 3

Hotfix 3 moves the backend contract to migration **117** and fixes a POS module-visibility mismatch:

- A POS with `cashier_shifts` enabled could be blocked from billing until a shift was opened.
- The same POS could hide the **Cashier Shift** menu because plan entitlement filtering did not include that operational module.

Migration 117 backfills `cashier_shifts` and `terminal_day` into every POS-entitled subscription plan and keeps tenant/template configuration aligned.

The POS source also now treats these as operational children of the POS entitlement and requires a cashier shift only when `cashier_shifts` is effectively enabled in the current session.

Current app build: `4.7.1+4`  
Required backend migration: `117`
