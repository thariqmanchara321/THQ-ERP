from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
results = []

def check(name, ok, detail=''):
    results.append((name, bool(ok), str(detail)))

def text(rel):
    return (ROOT / rel).read_text(encoding='utf-8', errors='ignore')

# Version contract.
for app in ['admin_panel', 'client_app', 'pos_app']:
    s = text(f'apps/{app}/pubspec.yaml')
    check(f'{app} version 4.8.4+12', re.search(r'^version:\s*4\.8\.4\+12\s*$', s, re.M) is not None)
core = text('packages/erp_core/pubspec.yaml')
check('erp_core version 4.8.4', re.search(r'^version:\s*4\.8\.4\s*$', core, re.M) is not None)
rc = text('packages/erp_core/lib/src/release_contract.dart')
for token in ["appVersion = '4.8.4'", 'minimumMigration = 146', "releaseName = 'Purchasing V2'", "apiVersion = 'v1'"]:
    check(f'release contract {token}', token in rc)

# Migrations 140-146 and bundle mirrors.
for n in range(140, 147):
    matches = list((ROOT / 'backend/migrations').glob(f'{n}_v484_*.sql'))
    check(f'migration {n} exists once', len(matches) == 1, matches)
    if not matches:
        continue
    p = matches[0]
    s = p.read_text(encoding='utf-8')
    check(f'migration {n} registered 4.8.4', re.search(rf"values\(\s*{n}\s*,\s*'4\.8\.4'", s, re.I) is not None)
    check(f'migration {n} begins transaction', re.search(r'^begin\s*;', s, re.I | re.M) is not None)
    check(f'migration {n} commits transaction', re.search(r'^commit\s*;', s, re.I | re.M) is not None)
    tags = re.findall(r'\$[A-Za-z_0-9]*\$', s)
    counts = {tag: tags.count(tag) for tag in set(tags)}
    check(f'migration {n} dollar quotes paired', all(v % 2 == 0 for v in counts.values()), counts)
    mirror = ROOT / 'backend/upgrade_from_139' / p.name
    check(f'migration {n} upgrade mirror matches', mirror.exists() and mirror.read_bytes() == p.read_bytes())

m140 = text('backend/migrations/140_v484_purchase_requests_po_v2.sql')
for token in [
    'purchase_requests_v484','purchase_request_items_v484','purchase_request_history_v484',
    'purchase_request_create_v484','purchase_request_status_v484','purchase_order_create_v484','purchase_order_decide_v484',
    'purchasing_v484_permission','purchasing_v484_access','purchasing_v484_approval_access'
]:
    check(f'PR/PO foundation contains {token}', token in m140)
check('PO statuses include partial/received/closed', all(x in m140 for x in ["'partially_received'", "'received'", "'closed'"]))
check('PO legacy approval bypass blocked', 'Use the V4.8.4 PO approval action' in m140)
check('partial received PO cancellation blocked', 'partially received Purchase Order cannot be cancelled' in m140)
check('PR rejection requires reason', 'Rejection reason is required' in m140)

m141 = text('backend/migrations/141_v484_goods_receiving.sql')
for token in ['goods_receipts_v484','goods_receipt_items_v484','goods_receipt_create_v484','goods_receipt_post_v484','goods_receipt_apply_tracking_v484']:
    check(f'GRN contains {token}', token in m141)
check('GRN quantity equation enforced', 'received_quantity-(accepted_quantity+damaged_quantity+rejected_quantity)' in m141)
check('GRN rejected reason required', 'Rejected quantity requires a reason' in m141)
check('GRN rejected stock excluded', 'v_physical:=gi.accepted_quantity+gi.damaged_quantity' in m141)
check('serial damaged uses quarantine', "v_serial,'quarantine'" in m141)
check('serial accepted uses in_stock', "v_serial,'in_stock'" in m141)
check('batch damaged balance separate', 'damaged_quantity=public.inventory_batch_balances_v483.damaged_quantity+excluded.damaged_quantity' in m141)
check('tracked reconciliation includes damaged physical stock', "status in('in_stock','quarantine')" in m141 and 'bb.quantity+coalesce(bb.damaged_quantity,0)' in m141)
check('GRN posts via existing stock ledger', 'private.v4_location_stock_apply' in m141 and 'public.inventory_adjust_stock' in m141)
check('GRN PO status history captures prior status', 'v_old_po_status' in m141)

m142 = text('backend/migrations/142_v484_purchase_invoices.sql')
for token in ['purchase_invoices_v484','purchase_invoice_items_v484','purchase_invoice_create_v484','purchase_invoice_post_v484']:
    check(f'purchase invoice contains {token}', token in m142)
check('invoice requires posted receipt state', 'Purchase Invoice requires posted GRN quantities' in m142)
check('invoice quantity matched to GRN/PO received qty', 'Invoice quantity exceeds accepted/damaged GRN quantity remaining' in m142 and 'Invoice quantity exceeds received payable PO quantity remaining' in m142)
check('invoice supplier number unique', 'ux_purchase_invoices_v484_supplier_invoice' in m142)
check('invoice posts accounting journal', 'private.v4_journal_create' in m142 and "'accounts_payable'" in m142 and "'input_gst'" in m142)
check('invoice does not call stock mutation', 'inventory_adjust_stock' not in m142 and 'v4_location_stock_apply' not in m142)

m143 = text('backend/migrations/143_v484_supplier_payments_ledger.sql')
for token in ['supplier_payments_v484','supplier_payment_allocations_v484','supplier_ledger_entries_v484','supplier_payment_create_v484','suppliers_get_statement_v484']:
    check(f'supplier finance contains {token}', token in m143)
check('payment allocation cannot exceed invoice balance', 'Allocation exceeds balance on invoice' in m143)
check('payment allocation cannot exceed payment', 'Allocated amount cannot exceed payment amount' in m143)
check('partial/full invoice payment status refresh', "v_paid>=v_total-0.005 then 'paid'" in m143 and "then 'part_paid'" in m143)
check('payment journal settles AP', "'accounts_payable'" in m143 and 'private.v4_payment_account' in m143)
check('supplier statement merges legacy and v484', "'legacy_purchase'" in m143 and 'supplier_ledger_entries_v484' in m143)

m144 = text('backend/migrations/144_v484_purchase_history_reporting.sql')
for token in ['purchase_order_list_v484','purchase_order_detail_v484','purchase_price_history_v484','purchasing_dashboard_v484']:
    check(f'reporting contains {token}', token in m144)
check('PO progress exposes received/damaged/rejected/invoiced', all(x in m144 for x in ['received_quantity','damaged_quantity','rejected_quantity','invoiced_quantity','remaining_receive_quantity','remaining_invoice_quantity']))
check('purchase history merges v484 and legacy', "'purchase_invoice_v484'" in m144 and "'legacy_purchase'" in m144)
check('history only includes posted v484 invoices', "ih.status in('posted','part_paid','paid')" in m144)

m145 = text('backend/migrations/145_v484_api_contract.sql')
for resource in ['purchase-requests','purchase-orders','goods-receipts','purchase-invoices','supplier-payments-v2','supplier-ledger-v2','purchase-price-history','purchasing-dashboard']:
    check(f'API contract resource {resource}', f"'{resource}'" in m145)
check('API contract separates stock and liability events', "'stock_receipt_event','goods_receipt'" in m145 and "'supplier_liability_event','purchase_invoice'" in m145)

m146 = text('backend/migrations/146_v484_release_contract.sql')
for proc in [
    'purchase_request_create_v484(uuid,uuid,jsonb,date,text,uuid,text,text)',
    'purchase_order_decide_v484(uuid,uuid,boolean,text)',
    'goods_receipt_post_v484(uuid,uuid,uuid)',
    'purchase_invoice_post_v484(uuid,uuid)',
    'supplier_payment_create_v484(uuid,uuid,uuid,date,numeric,text,jsonb,text,text)',
    'suppliers_get_statement_v484(uuid,uuid,date,date,uuid)',
    'purchase_price_history_v484(uuid,uuid,uuid,uuid,text,integer)'
]:
    check(f'release verifier checks {proc}', proc in m146)
check('release verifier migration 146', "'migration_no',146" in m146)

# Permission gates on read surfaces.
for rel in [
    'backend/migrations/140_v484_purchase_requests_po_v2.sql',
    'backend/migrations/141_v484_goods_receiving.sql',
    'backend/migrations/142_v484_purchase_invoices.sql',
    'backend/migrations/143_v484_supplier_payments_ledger.sql',
    'backend/migrations/144_v484_purchase_history_reporting.sql',
]:
    check(f'{Path(rel).name} uses purchasing permission gate', 'purchasing_v484_permission' in text(rel) or 'purchasing_v484_access' in text(rel))

# THQ API mirrors/routes.
edge_b = ROOT / 'backend/functions/thq-api/index.ts'
edge_s = ROOT / 'supabase/functions/thq-api/index.ts'
check('THQ API backend exists', edge_b.exists())
check('THQ API Supabase mirror exists', edge_s.exists())
check('THQ API mirrors identical', edge_b.exists() and edge_s.exists() and edge_b.read_bytes() == edge_s.read_bytes())
if edge_b.exists():
    e = edge_b.read_text(encoding='utf-8')
    for resource in ['purchase-requests','purchase-orders','goods-receipts','purchase-invoices','supplier-payments-v2','supplier-ledger-v2','purchase-price-history','purchasing-dashboard']:
        check(f'THQ API routes {resource}', f"case '{resource}'" in e)
    for rpc in ['purchase_request_create_v484','purchase_order_decide_v484','goods_receipt_post_v484','purchase_invoice_post_v484','supplier_payment_create_v484','suppliers_get_statement_v484','purchase_price_history_v484','purchasing_dashboard_v484']:
        check(f'THQ API invokes {rpc}', rpc in e)
    check('THQ API does not use service-role key', 'SUPABASE_SERVICE_ROLE_KEY' not in e)

# Flutter app integration.
for app in ['client_app','pos_app']:
    home = text(f'apps/{app}/lib/screens/client_home_screen.dart')
    service = text(f'apps/{app}/lib/services/purchasing_v2_service.dart')
    screen = text(f'apps/{app}/lib/screens/purchasing_v2_screen.dart')
    statement = text(f'apps/{app}/lib/services/party_statement_service.dart')
    check(f'{app} routes Purchases to PurchasingV2Screen', 'PurchasingV2Screen(session: session)' in home)
    check(f'{app} Purchasing V2 service exists', bool(service))
    for resource in ['purchase-requests','purchase-orders','goods-receipts','purchase-invoices','supplier-payments-v2','supplier-ledger-v2','purchase-price-history','purchasing-dashboard']:
        check(f'{app} service uses {resource}', resource in service)
    for label in ['Purchase Requests','Purchase Orders','GRN','Purchase Invoices','Supplier Ledger','Price History','Legacy Purchases']:
        check(f'{app} workspace tab {label}', label in screen)
    check(f'{app} GRN UI accepted/damaged/rejected', all(x in screen for x in ["labelText: 'Accepted'", "labelText: 'Damaged'", "labelText: 'Rejected'"]))
    check(f'{app} GRN UI captures rejection reason', 'Rejection reason (required if rejected)' in screen)
    check(f'{app} GRN UI serial/batch tracking', 'damaged_serial_numbers' in screen and "'batches'" in screen)
    check(f'{app} supplier statements use unified v484', 'suppliers_get_statement_v484' in statement)

# v4.8.3 trace baseline remains present.
for n in range(135, 140):
    check(f'v4.8.3 migration {n} preserved', len(list((ROOT/'backend/migrations').glob(f'{n}_v483_*.sql'))) == 1)
check('v4.8.3 serial registry preserved', 'inventory_serials_v483' in text('backend/migrations/135_v483_tracking_foundation.sql'))
check('v4.8.3 FEFO preserved', 'order by (b.expiry_on is null),b.expiry_on,b.created_at,b.batch_number' in text('backend/migrations/137_v483_sales_warranty.sql'))

# Upgrade/release artifacts.
for rel in [
    'README_V484_RELEASE.md','CHANGELOG_V484.md','docs/V484_ARCHITECTURE.md','docs/V484_DEPLOYMENT.md','docs/V484_RELEASE_ACCEPTANCE.md',
    'backend/THQ_ERP_V484_UPGRADE_FROM_139.sql','backend/V484_POST_UPGRADE_CHECK.sql','backend/V484_EDGE_FUNCTIONS_DEPLOY.md',
    'backend/upgrade_from_139/THQ_ERP_V484_UPGRADE_FROM_139.sql','backend/upgrade_from_139/V484_POST_UPGRADE_CHECK.sql',
    'backend/upgrade_from_139/README_DEPLOY_V484.md','tools/validate_v484_windows.ps1'
]:
    check(f'release artifact {rel}', (ROOT / rel).exists())

bundle = text('backend/THQ_ERP_V484_UPGRADE_FROM_139.sql')
positions = [bundle.find(f"values({n},'4.8.4'") for n in range(140,147)]
check('combined bundle contains 140-146', all(x >= 0 for x in positions), positions)
check('combined bundle ordered 140-146', positions == sorted(positions), positions)
check('combined bundle mirror identical', (ROOT/'backend/upgrade_from_139/THQ_ERP_V484_UPGRADE_FROM_139.sql').read_bytes() == (ROOT/'backend/THQ_ERP_V484_UPGRADE_FROM_139.sql').read_bytes())

# Tests/version assertions.
for rel in ['apps/client_app/test/widget_test.dart','apps/pos_app/test/widget_test.dart','packages/erp_core/test/erp_core_test.dart']:
    s = text(rel)
    check(f'{rel} expects 4.8.4', "'4.8.4'" in s)
    check(f'{rel} expects migration 146', '146' in s)

# Relative Dart imports resolve.
for p in list(ROOT.glob('apps/*/lib/**/*.dart')) + list(ROOT.glob('packages/erp_core/lib/**/*.dart')):
    src = p.read_text(encoding='utf-8', errors='ignore')
    for imp in re.findall(r"import\s+'([^']+)'", src):
        if imp.startswith('.'):
            target = (p.parent / imp).resolve()
            check(f'import resolves {p.relative_to(ROOT)} -> {imp}', target.exists(), target)

# Lightweight delimiter scanner for Dart/TS/SQL-owned source. It ignores comments and quoted strings.
def balanced(path):
    src = path.read_text(encoding='utf-8', errors='ignore')
    stack=[]; pairs={')':'(',']':'[','}':'{'}; i=0; state='code'; quote=''; triple=False; block_depth=0
    while i < len(src):
        c=src[i]; pair=src[i:i+2]
        if state=='code':
            if pair=='//': state='line'; i+=2; continue
            if pair=='/*': state='block'; block_depth=1; i+=2; continue
            if c in "'\"":
                quote=c
                if src[i:i+3]==c*3: triple=True; i+=3
                else: triple=False; i+=1
                state='string'; continue
            if c in '([{': stack.append(c)
            elif c in ')]}':
                if not stack or stack[-1] != pairs[c]: return False, f'mismatch at {i}'
                stack.pop()
            i+=1
        elif state=='line':
            if c=='\n': state='code'
            i+=1
        elif state=='block':
            if pair=='/*': block_depth+=1; i+=2
            elif pair=='*/': block_depth-=1; i+=2; state='code' if block_depth==0 else 'block'
            else: i+=1
        else:
            if c=='\\': i+=2; continue
            if triple:
                if src[i:i+3]==quote*3: state='code'; triple=False; i+=3
                else: i+=1
            else:
                if c==quote: state='code'
                i+=1
    return not stack and state not in ('block','string'), f'stack={stack} state={state}'

for rel in [
    'apps/client_app/lib/services/purchasing_v2_service.dart','apps/client_app/lib/screens/purchasing_v2_screen.dart',
    'apps/pos_app/lib/services/purchasing_v2_service.dart','apps/pos_app/lib/screens/purchasing_v2_screen.dart',
    'backend/functions/thq-api/index.ts','supabase/functions/thq-api/index.ts'
]:
    ok, detail = balanced(ROOT/rel)
    check(f'delimiters balanced {rel}', ok, detail)

# Common release hygiene.
for bad in ['.git', '.dart_tool', 'node_modules']:
    check(f'clean release excludes root {bad}', not (ROOT / bad).exists())

passed = sum(ok for _,ok,_ in results)
failed = [(n,d) for n,ok,d in results if not ok]
for name, ok, detail in results:
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f" :: {detail}" if detail and not ok else ''))
print(f'\nTHQ ERP v4.8.4 static verification: {passed}/{len(results)} checks passed.')
if failed:
    print('\nFailures:')
    for name, detail in failed:
        print(f'- {name}: {detail}')
    sys.exit(1)
