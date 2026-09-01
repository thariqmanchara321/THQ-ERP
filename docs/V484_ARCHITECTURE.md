# THQ ERP v4.8.4 Purchasing V2 architecture

## Document chain
Purchase Request (PR) → Purchase Order (PO) → Goods Received Note (GRN) → Purchase Invoice → Supplier Payment.

### PR
Demand/authorization only. No inventory or GL effect.

### PO
Supplier commitment and approval document. No inventory or GL effect. Existing `purchase_orders_v480` is upgraded instead of introducing a competing PO table.

### GRN
The authoritative Purchasing V2 stock receipt event. It updates the existing global/location stock ledgers. Partial receipt is supported. `accepted + damaged + rejected = received`. Rejected units do not enter stock; damaged units enter physical stock and are excluded from normal availability.

For v4.8.3 tracked products, the GRN also creates serial/batch trace records. Serial `quarantine` and batch `damaged_quantity` are included in physical tracking reconciliation but excluded from sale allocation.

### Purchase Invoice
The authoritative Purchasing V2 supplier liability event. It can invoice only quantities supported by posted accepted/damaged receipt quantities. It creates AP/input-tax accounting and does not touch stock.

### Supplier Payment / Ledger
Payments settle AP and may allocate against one or more open Purchase Invoices. The v4.8.4 statement API merges legacy purchase activity with Purchasing V2 ledger entries.

## Compatibility
Legacy `purchases` remain operational. Purchasing V2 does not rewrite historical data and does not require replaying migrations 001–139.
