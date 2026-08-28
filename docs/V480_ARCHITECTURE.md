# THQ ERP v4.8 — Connectivity Architecture

Current migration path:

`Admin / Client / POS → THQ API v1 → Supabase adapter → PostgreSQL/RPC`

V4.8.0 introduces this boundary progressively. Existing hardened financial commands still call the proven RPCs directly. New intelligence, sync, purchase-planning and mobile-read workloads use THQ API v1 first.

The goal is that future clients depend on THQ contracts rather than Supabase-specific details. A future Oracle/Google/other adapter can be placed behind THQ API without changing the mobile/business client contract.

## Synchronization
Each business has monotonically increasing versions for:
- configuration
- catalogue
- parties
- transactions
- inventory
- finance

Version counters are the synchronization truth. Event rows contain metadata only and are bounded diagnostics, not a transaction queue.

Client detects all domain changes. POS deliberately watches configuration, catalogue and parties only so normal sales/stock/accounting posting does not constantly interrupt an active cashier.

## Purchase Planning
Purchase Orders are intent/planning documents. They do not create stock or accounting entries. Future GRN/receiving will own physical receipt, while Purchase Invoice will own the financial liability.
