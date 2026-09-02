# THQ UI

Shared design foundation for THQ ERP Admin, Client, POS, Client Mobile, and POS Mobile.

## UI transformation checkpoint 1

This package introduces design tokens, responsive breakpoints, semantic status colors,
Material themes, and small reusable controls. It is intentionally not referenced by any
production application yet, so adding this checkpoint does not alter transaction,
accounting, GST, inventory, activation, printing, or offline behavior.

The initial dark palette is compatible with the existing Client Aurora/v4.3 visual
language so application migration can be incremental instead of a destructive rewrite.

## Rules

- Keep business and backend logic out of this package.
- Prefer semantic tokens over screen-specific hardcoded colors or sizes.
- Keep notifications non-modal by default and never request focus.
- Buttons with `busy: true` are disabled while displaying progress.
- Application permissions and transaction integrity remain authoritative outside UI.
