# THQ ERP v4.8.4 release acceptance

- [ ] Backend contract reports minimum app version 4.8.4 and migration 146.
- [ ] PR can be created, submitted, approved/rejected, and converted to one PO.
- [ ] PO cannot be approved through the legacy status action; approval requires approval permission.
- [ ] GRN supports partial receiving.
- [ ] GRN enforces received = accepted + damaged + rejected.
- [ ] Rejected quantity requires a reason and does not enter stock.
- [ ] Damaged quantity increments physical stock and damaged/quarantine stock, not normal availability.
- [ ] Serial GRN captures exact accepted/damaged serial counts.
- [ ] Batch GRN captures exact accepted/damaged quantities and expiry policy.
- [ ] Purchase Invoice cannot exceed posted receipt quantity remaining.
- [ ] Posting Purchase Invoice does not change inventory quantity.
- [ ] Posting Purchase Invoice creates AP/input-tax journal.
- [ ] Supplier Payment supports partial allocation and updates invoice balance/status.
- [ ] Supplier Ledger includes legacy and Purchasing V2 activity without duplicating v4.8.4 rows.
- [ ] Purchase Price History includes posted v4.8.4 invoice lines and legacy purchase lines.
- [ ] Client and POS management Purchases modules open Purchasing V2 and expose Legacy Purchases separately.
- [ ] THQ API backend and Supabase Edge Function mirrors are identical.
