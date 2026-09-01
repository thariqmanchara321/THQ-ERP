# THQ ERP v4.8.6 Release Acceptance

- [ ] Client and POS analyzer output is clean with fatal infos/warnings.
- [ ] POS can cache active products/customers/serials online.
- [ ] Disconnect network, complete a cash invoice, and verify an `OFF-...` local number is created.
- [ ] Verify local stock/serial availability drops immediately.
- [ ] Reconnect and confirm one server invoice only, even after repeated Sync Now/retry.
- [ ] Confirm pending invoice survives POS restart.
- [ ] Confirm a stale price becomes `PRICE_CHANGED` without posting.
- [ ] Confirm stale stock/serial becomes `STOCK_CONFLICT` without duplicate posting.
- [ ] Cancel an unposted local invoice and verify local reservations restore exactly.
- [ ] Confirm offline receipt says `OFFLINE SALE RECEIPT / PENDING SERVER SYNC`.
- [ ] Confirm successful sync refreshes stock and produces the official server invoice.
