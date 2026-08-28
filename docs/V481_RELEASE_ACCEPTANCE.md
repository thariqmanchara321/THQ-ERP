# THQ ERP v4.8.1 Release Acceptance

Run against staging/test data before production.

## Upgrade
- [ ] Backup database at migration 124.
- [ ] Apply 125, 126, 127, 128, 129 in order.
- [ ] `thq_backend_contract_v47()` reports 4.8.1 / 129.
- [ ] `thq_v481_release_verify()` returns `ready: true`.
- [ ] Redeploy `thq-api`.

## Base unit / conversions
- [ ] Existing stock products have a base unit after migration.
- [ ] Create product with PCS base unit.
- [ ] Create product with M base unit.
- [ ] Add COIL conversion: 1 COIL = 90 M.
- [ ] Add BOX conversion: 1 BOX = 20 PCS.
- [ ] Configure default sale/purchase units.
- [ ] Backend rejects a base-unit change after stock/history exists.

## POS sales
- [ ] Sell 25.5 M where fractional quantity is allowed.
- [ ] Backend rejects fractional PCS/BOX if configured whole-only.
- [ ] Sell 2 COIL; stock decreases by 180 M.
- [ ] Invoice/detail shows 2 COIL and entered unit price, not 180 M as the customer quantity.
- [ ] Optional cutting charge is added exactly once.
- [ ] Hold/Resume preserves selected unit and cutting-charge state.

## Client sales/purchases
- [ ] Client sale can select alternate sale unit.
- [ ] Client optional cutting charge is included in totals.
- [ ] Purchase 10 COIL; stock increases by 900 M.
- [ ] Purchase detail preserves 10 COIL and entered unit cost.

## Returns
- [ ] Return 1 COIL from a 2 COIL sale; stock restores 90 M.
- [ ] Return unit step/fraction validation is enforced.
- [ ] Purchase return reverses correct base quantity.
- [ ] Accounting remains balanced after sale/purchase returns.

## Movement ledger
- [ ] Opening, purchase, sale, return, adjustment and transfer movements display.
- [ ] Entered/display quantity and base quantity are both correct.
- [ ] Balance before/after is correct for new movements.
- [ ] Location/date/type filters work.

## Locations
- [ ] Create Store.
- [ ] Create Warehouse.
- [ ] Create Production location.
- [ ] Create Office location.
- [ ] Create Scrap location.
- [ ] Existing MAIN/child-store hierarchy still behaves correctly.

## Regression
- [ ] POS Hold/Resume works.
- [ ] Customer partial payment works.
- [ ] Cashier Shift works.
- [ ] Terminal Daily works.
- [ ] Purchase Orders v4.8.0 still do not change inventory/accounting.
- [ ] System Health has zero critical integrity issues.
