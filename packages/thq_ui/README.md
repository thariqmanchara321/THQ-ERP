# THQ UI

Shared presentation foundation for THQ ERP applications.

## Update 1 foundation

- Material 3 light/dark THQ themes
- spacing, radius, sizing, motion and breakpoint tokens
- THQ typography and tabular monetary styles
- semantic success/warning/critical/info/neutral colors
- primary, secondary, danger and busy-safe buttons
- compact text, numeric and search fields
- cards, summary cards, status badges and compact notification toasts
- loading, empty and error states

## Update 2 workspace primitives

- `ThqDesktopShell` — fixed 224px / collapsed 64px desktop navigation with mobile drawer fallback
- `ThqTopBar` — compact fixed top bar with scope/action slots
- `ThqPageFrame` — fixed page header/toolbar/footer while page content owns scrolling
- `ThqSplitPane` and `ThqWorkspacePane` — master/detail one-screen workspaces
- `ThqFilterBar` and `ThqFilterChip` — dense search/filter/action controls
- `ThqDenseTable` — fixed header with internal horizontal/vertical scrolling
- `ThqFormSection` and `ThqFormGrid` — responsive dense forms
- `ThqStickyActionBar` — fixed confirm/print/save actions
- `ThqDraftController` and `ThqDraftProtection` — dirty/submitting state and discard confirmation

## Design rules

The package is presentation-only. It must not own tenant logic, GST logic, inventory rules, accounting writers, permissions, offline synchronization, or transaction persistence.

Desktop transaction workspaces should keep navigation, page headers and final actions visible. Long lists and dense tables scroll inside their own pane rather than forcing the entire Sales/Purchase workspace to scroll. Mobile uses the same semantics with touch-safe sizing and responsive stacking.
