# THQ ERP v4.7.3 — POS Hold Workspace Hotfix (Build +7)

This app-only hotfix fixes the intermittent Flutter framework assertion seen when holding invoices and finalizes the POS center-workspace behavior.

## Upgrade

- Database: no change; remain on migration 119.
- Apps: 4.7.3+7.
- No Edge Function redeployment is required.

## Hold behavior

- Press **Hold** with a non-empty cart.
- The center product area switches to **Hold Current Invoice**.
- Enter an optional reference/customer name and press **Hold Invoice**.
- Reference labels may repeat. THQ generates a unique `HOLD-...` code for each held invoice.
- The cart and POS shell stay mounted.
- After a successful hold, the cart is cleared and the center workspace returns to Products.

## Resume behavior

- Press **Resume** with an empty cart.
- The center product area switches to the Held Invoices grid.
- Select a held invoice to restore it.
- Closing/back returns only the center workspace to Products.

## Runtime test

1. Hold 10+ invoices repeatedly, including several with the same reference name.
2. Confirm no red Flutter assertion screen appears.
3. Confirm every hold gets a different HOLD code.
4. Resume each invoice and verify cart/customer/discount state.
5. Confirm the right-side cart and main POS shell do not disappear while Hold/Resume workspace is open.

Static verification: 830/830 checks passed in the packaged source.
