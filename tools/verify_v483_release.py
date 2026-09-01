from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
results = []

def check(name, ok, detail=''):
    results.append((name, bool(ok), detail))

def text(rel):
    return (ROOT / rel).read_text(encoding='utf-8', errors='ignore')

# Release/version contract.
for app in ['admin_panel', 'client_app', 'pos_app']:
    s = text(f'apps/{app}/pubspec.yaml')
    check(f'{app} version 4.8.3+11', re.search(r'^version:\s*4\.8\.3\+11\s*$', s, re.M) is not None)
core = text('packages/erp_core/pubspec.yaml')
check('erp_core version 4.8.3', re.search(r'^version:\s*4\.8\.3\s*$', core, re.M) is not None)
rc = text('packages/erp_core/lib/src/release_contract.dart')
for token in ["appVersion = '4.8.3'", 'minimumMigration = 139', "releaseName = 'Serial / Batch / Warranty'", "apiVersion = 'v1'"]:
    check(f'release contract {token}', token in rc)

# Migrations 135-139.
for n in range(135, 140):
    matches = list((ROOT / 'backend/migrations').glob(f'{n}_v483_*.sql'))
    check(f'migration {n} exists once', len(matches) == 1, str(matches))
    if not matches:
        continue
    p = matches[0]
    s = p.read_text(encoding='utf-8')
    check(f'migration {n} registered as 4.8.3', re.search(rf"values\(\s*{n}\s*,\s*'4\.8\.3'", s, re.I) is not None)
    check(f'migration {n} begins transaction', re.search(r'^begin\s*;', s, re.I | re.M) is not None)
    check(f'migration {n} commits transaction', re.search(r'^commit\s*;', s, re.I | re.M) is not None)
    tags = re.findall(r'\$[A-Za-z_0-9]*\$', s)
    counts = {tag: tags.count(tag) for tag in set(tags)}
    check(f'migration {n} dollar quotes paired', all(v % 2 == 0 for v in counts.values()), str(counts))
    mirror = ROOT / 'backend/upgrade_from_134' / p.name
    check(f'migration {n} upgrade mirror matches', mirror.exists() and mirror.read_bytes() == p.read_bytes())

m135 = text('backend/migrations/135_v483_tracking_foundation.sql')
for token in [
    'product_tracking_policies_v483', 'inventory_batches_v483', 'inventory_batch_balances_v483',
    'inventory_serials_v483', 'inventory_trace_events_v483', 'product_warranties_v483',
    'inventory_tracking_policy_v483', 'inventory_tracking_policy_save_v483', 'inventory_list_products_v483'
]:
    check(f'foundation contains {token}', token in m135)
check('tracking modes none/serial/batch', "tracking_mode in('none','serial','batch')" in m135)
check('serial is tenant-unique', 'ux_inventory_serials_v483_number' in m135 and 'lower(trim(serial_number))' in m135)
check('trace tables not directly granted to clients', all(f'revoke all on public.{t} from anon,authenticated;' in m135 for t in [
    'product_tracking_policies_v483','inventory_batches_v483','inventory_batch_balances_v483','inventory_serials_v483','inventory_trace_events_v483','product_warranties_v483'
]))
check('tracking mode locks after history', 'Tracking mode cannot be changed after serial/batch history exists' in m135)

m136 = text('backend/migrations/136_v483_purchase_traceability.sql')
for token in ['inventory_tracking_reconciliation_v483','inventory_tracking_register_opening_v483','v483_apply_purchase_trace','purchases_create_v483']:
    check(f'purchase trace contains {token}', token in m136)
check('opening exact serial reconciliation', 'Register exactly % serial numbers to match current stock' in m136)
check('opening exact batch reconciliation', 'Batch quantities must total current stock' in m136)
check('purchase exact serial validation', 'Provide exactly % serial numbers for tracked purchase line' in m136)
check('purchase exact batch validation', 'Batch quantities must total base quantity' in m136)
check('purchase blocks unreconciled legacy stock', 'Register existing serial/batch opening stock before receiving product' in m136)
check('purchase rejects duplicate serials', 'Duplicate serial number % on tracked purchase line' in m136)
check('purchase rejects duplicate batches', 'Duplicate batch % on tracked purchase line' in m136)
check('batch date conflicts rejected', 'already exists with different manufacture/expiry dates' in m136)

m137 = text('backend/migrations/137_v483_sales_warranty.sql')
for token in ['v483_assert_reconciled','v483_create_warranty','v483_apply_batch_sale','v483_apply_sale_trace','sales_create_v483']:
    check(f'sales trace contains {token}', token in m137)
check('batch FEFO ordering', "order by (b.expiry_on is null),b.expiry_on,b.created_at,b.batch_number" in m137)
check('expired batch default rejection', 'expired on %' in m137 and 'allow_expired_sale' in m137)
check('sale serial exact count', 'Provide exactly % serial numbers for serial-tracked product' in m137)
check('trace sale retry guard', 'where tenant_id=p_tenant_id and sale_id=p_sale_id' in m137 and 'then return;end if;' in m137)
for token in [
    'inventory_adjust_stock_v483','inventory_stock_count_post_v483','inventory_transfer_create_v483',
    'sales_return_create_v483','purchase_return_create_v483','sales_void_v483','purchase_void_v483'
]:
    check(f'guardrail RPC {token}', token in m137)
check('tracked mutation guardrails explain blocked release scope', m137.count('blocked in v4.8.3') >= 7)

m138 = text('backend/migrations/138_v483_trace_search_history.sql')
for token in ['inventory_serial_search_v483','inventory_batch_search_v483','inventory_batch_history_v483','inventory_serial_history_v483','warranty_register_v483','inventory_serial_resolve_v483']:
    check(f'trace API contains {token}', token in m138)
check('trace permission gate', 'v483_trace_view_allowed' in m138)
check('trace APIs enforce location scope', m138.count('private.erp_document_scope_allowed') >= 10)
for term in ['supplier_name','customer_name','purchase_number','sale_number']:
    check(f'trace output/search includes {term}', term in m138)
check('warranty expiration computed', "w.warranty_expiry<current_date then 'expired'" in m138)

m139 = text('backend/migrations/139_v483_release_contract.sql')
for resource in ['tracking-policy','serials','batches','batch-history','warranties']:
    check(f'API contract resource {resource}', f"'{resource}'" in m139)
for proc in [
    'inventory_tracking_policy_v483(uuid,uuid)',
    'inventory_tracking_policy_save_v483(uuid,uuid,text,boolean,integer,integer,boolean,boolean)',
    'inventory_tracking_register_opening_v483(uuid,uuid,uuid,jsonb,jsonb,text)',
    'purchases_create_v483(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid,text)',
    'sales_create_v483(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text)',
    'inventory_serial_search_v483(uuid,text,uuid,integer)',
    'inventory_batch_history_v483(uuid,uuid)',
    'warranty_register_v483(uuid,text,text,integer,integer,uuid)'
]:
    check(f'release verifier checks {proc}', proc in m139)

# Edge API mirrors and routes.
edge_b = ROOT / 'backend/functions/thq-api/index.ts'
edge_s = ROOT / 'supabase/functions/thq-api/index.ts'
check('THQ API backend exists', edge_b.exists())
check('THQ API Supabase mirror exists', edge_s.exists())
check('THQ API mirrors identical', edge_b.exists() and edge_s.exists() and edge_b.read_bytes() == edge_s.read_bytes())
if edge_b.exists():
    e = edge_b.read_text(encoding='utf-8')
    for resource in ['tracking-policy','serials','batches','batch-history','warranties']:
        check(f'THQ API routes {resource}', f"case '{resource}'" in e)
    for rpc in ['inventory_tracking_policy_v483','inventory_tracking_reconciliation_v483','inventory_tracking_register_opening_v483','inventory_serial_search_v483','inventory_batch_search_v483','inventory_batch_history_v483','warranty_register_v483']:
        check(f'THQ API invokes {rpc}', rpc in e)
    check('THQ API does not use service role key', 'SUPABASE_SERVICE_ROLE_KEY' not in e)

# Flutter service/RPC wiring.
for app in ['client_app','pos_app']:
    base = f'apps/{app}'
    inv = text(f'{base}/lib/services/inventory_service.dart')
    sales = text(f'{base}/lib/services/sales_service.dart')
    purchases = text(f'{base}/lib/services/purchase_service.dart')
    tracking = text(f'{base}/lib/services/tracking_service.dart')
    home = text(f'{base}/lib/screens/client_home_screen.dart')
    product = text(f'{base}/lib/screens/product_detail_screen.dart')
    check(f'{app} inventory list v483', 'inventory_list_products_v483' in inv)
    check(f'{app} stock adjustment guard RPC', 'inventory_adjust_stock_v483' in inv)
    check(f'{app} sales create v483', 'sales_create_v483' in sales)
    check(f'{app} sales return/void v483', 'sales_return_create_v483' in sales and 'sales_void_v483' in sales)
    check(f'{app} purchases create v483', 'purchases_create_v483' in purchases)
    check(f'{app} purchase return/void v483', 'purchase_return_create_v483' in purchases and 'purchase_void_v483' in purchases)
    for rpc in ['inventory_tracking_policy_v483','inventory_tracking_policy_save_v483','inventory_tracking_reconciliation_v483','inventory_tracking_register_opening_v483','inventory_serial_search_v483','inventory_batch_search_v483','inventory_serial_history_v483','inventory_batch_history_v483','warranty_register_v483','inventory_serial_resolve_v483']:
        check(f'{app} tracking service {rpc}', rpc in tracking)
    check(f'{app} tracking workspace navigation', 'TrackingWorkspaceScreen' in home)
    check(f'{app} product tracking policy', 'ProductTrackingPolicyScreen' in product and "product.itemType == 'stock'" in product)

client_purchases = text('apps/client_app/lib/screens/purchases_screen.dart')
pos_purchases = text('apps/pos_app/lib/screens/purchases_screen.dart')
for label, s in [('Client',client_purchases),('POS management',pos_purchases)]:
    check(f'{label} purchase serial payload', "'serial_numbers'" in s)
    check(f'{label} purchase batch payload', "'batches'" in s)
    check(f'{label} purchase tracking mode UI', 'trackingMode' in s)

client_sales = text('apps/client_app/lib/screens/sales_screen.dart')
pos_sales = text('apps/pos_app/lib/screens/sales_screen.dart')
for label, s in [('Client',client_sales),('POS management',pos_sales)]:
    check(f'{label} sale serial payload', "'serial_numbers'" in s)
    check(f'{label} batch FEFO UX', 'FEFO' in s)

pos = text('apps/pos_app/lib/screens/pos_screen.dart')
for token in ['serialNumbers','resolveSerial','serial_numbers','Hold','Resume']:
    check(f'POS serial workflow {token}', token in pos)
check('POS duplicate serial guard', 'already in this invoice' in pos or 'already added' in pos)

# v4.8.1 normalization remains the quantity bridge.
v481 = text('backend/migrations/128_v481_unit_transactions.sql')
check('v481 normalizer preserves caller JSON', "return p_item||jsonb_build_object" in v481)
check('v483 purchase normalizes base quantity', "v481_normalize_items(p_tenant_id,p_items,'purchase')" in m136)
check('v483 sale normalizes base quantity', "v481_normalize_items(p_tenant_id,p_items,'sale')" in m137)

# Release artifacts.
for rel in [
    'README_V483_RELEASE.md','CHANGELOG_V483.md','docs/V483_ARCHITECTURE.md','docs/V483_DEPLOYMENT.md','docs/V483_RELEASE_ACCEPTANCE.md',
    'backend/THQ_ERP_V483_UPGRADE_FROM_134.sql','backend/V483_POST_UPGRADE_CHECK.sql','backend/V483_EDGE_FUNCTIONS_DEPLOY.md',
    'backend/upgrade_from_134/THQ_ERP_V483_UPGRADE_FROM_134.sql','backend/upgrade_from_134/V483_POST_UPGRADE_CHECK.sql',
    'backend/upgrade_from_134/README_DEPLOY_V483.md','tools/validate_v483_windows.ps1'
]:
    check(f'release artifact {rel}', (ROOT / rel).exists())

bundle = text('backend/THQ_ERP_V483_UPGRADE_FROM_134.sql')
positions = [bundle.find(f"values({n},'4.8.3'") for n in range(135,140)]
check('combined migration bundle contains 135-139', all(x >= 0 for x in positions), str(positions))
check('combined migration bundle ordered 135-139', positions == sorted(positions), str(positions))
check('combined migration mirror identical', (ROOT/'backend/upgrade_from_134/THQ_ERP_V483_UPGRADE_FROM_134.sql').read_bytes() == (ROOT/'backend/THQ_ERP_V483_UPGRADE_FROM_134.sql').read_bytes())

# Tests/version assertions.
for rel in ['apps/client_app/test/widget_test.dart','apps/pos_app/test/widget_test.dart','packages/erp_core/test/erp_core_test.dart']:
    s = text(rel)
    check(f'{rel} expects 4.8.3', "'4.8.3'" in s)
    check(f'{rel} expects migration 139', '139' in s)

# Relative Dart imports resolve.
for p in list(ROOT.glob('apps/*/lib/**/*.dart')) + list(ROOT.glob('packages/erp_core/lib/**/*.dart')):
    src = p.read_text(encoding='utf-8', errors='ignore')
    for imp in re.findall(r"import\s+'([^']+)'", src):
        if imp.startswith('.'):
            target = (p.parent / imp).resolve()
            check(f'import resolves {p.relative_to(ROOT)} -> {imp}', target.exists(), str(target))

# Lightweight Dart delimiter scanner, ignoring strings/comments.
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
                if not stack or stack[-1] != pairs[c]: return False
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
                if src[i:i+3]==quote*3: state='code'; i+=3
                else: i+=1
            else:
                if c==quote: state='code'; i+=1
                else: i+=1
    return not stack and state in ('code','line')

paths = list(ROOT.glob('apps/*/lib/**/*.dart')) + list(ROOT.glob('packages/erp_core/lib/**/*.dart')) + list(ROOT.glob('apps/*/test/**/*.dart')) + list(ROOT.glob('packages/erp_core/test/**/*.dart'))
for p in paths:
    check(f'Dart structural balance {p.relative_to(ROOT)}', balanced(p))

# Analyzer policy continues to be a release gate.
validator = text('tools/validate_v483_windows.ps1')
check('Windows validator fatal analyzer infos', '--fatal-infos' in validator)
check('Windows validator fatal analyzer warnings', '--fatal-warnings' in validator)
check('Windows validator builds with switch', '[switch]$Build' in validator and "'build','windows','--release'" in validator)

# No whitespace errors in release-owned text are approximated by trailing-space scan.
release_owned = list((ROOT/'backend/migrations').glob('13[5-9]_v483_*.sql')) + [ROOT/r for r in [
    'README_V483_RELEASE.md','CHANGELOG_V483.md','docs/V483_ARCHITECTURE.md','docs/V483_DEPLOYMENT.md','docs/V483_RELEASE_ACCEPTANCE.md',
    'backend/V483_POST_UPGRADE_CHECK.sql','backend/V483_EDGE_FUNCTIONS_DEPLOY.md','tools/validate_v483_windows.ps1'
]]
for p in release_owned:
    bad=[i+1 for i,line in enumerate(p.read_text(encoding='utf-8',errors='ignore').splitlines()) if line.endswith((' ','\t'))]
    check(f'no trailing whitespace {p.relative_to(ROOT)}', not bad, str(bad[:10]))

passed = sum(ok for _, ok, _ in results)
total = len(results)
report = ['THQ ERP V4.8.3 STATIC RELEASE VERIFICATION', f'Passed: {passed}/{total}', '']
for name, ok, detail in results:
    report.append(f"{'PASS' if ok else 'FAIL'} | {name}" + (f' | {detail}' if detail and not ok else ''))
(ROOT / 'V483_STATIC_VERIFICATION.txt').write_text('\n'.join(report) + '\n', encoding='utf-8')
print('\n'.join(report[:3]))
if passed != total:
    for name, ok, detail in results:
        if not ok:
            print('FAIL:', name, detail)
    sys.exit(1)
