from pathlib import Path
import re, sys, hashlib

ROOT=Path(__file__).resolve().parents[1]
results=[]
def check(name, ok, detail=''):
    results.append((name,bool(ok),detail))
def text(rel): return (ROOT/rel).read_text(encoding='utf-8')

# Versions / release contract.
for app in ['admin_panel','client_app','pos_app']:
    s=text(f'apps/{app}/pubspec.yaml')
    check(f'{app} version 4.8.0+8', re.search(r'^version:\s*4\.8\.0\+8\s*$',s,re.M) is not None)
core=text('packages/erp_core/pubspec.yaml')
check('erp_core version 4.8.0', re.search(r'^version:\s*4\.8\.0\s*$',core,re.M) is not None)
rc=text('packages/erp_core/lib/src/release_contract.dart')
check('shared app version 4.8.0', "appVersion = '4.8.0'" in rc)
check('shared minimum migration 124', 'minimumMigration = 124' in rc)
check('shared API version v1', "apiVersion = 'v1'" in rc)
check('shared release name', 'Operational Intelligence & Connectivity' in rc)
api_core=text('packages/erp_core/lib/src/thq_api.dart')
for token in ['class ThqApiRequest','class ThqSyncVersions','class ThqApiContract','configurationOrMasterChangedFrom','anyChangedFrom']:
    check(f'erp_core API contract {token}', token in api_core)
check('erp_core exports API contract', "export 'src/thq_api.dart';" in text('packages/erp_core/lib/erp_core.dart'))

# Migrations and exact upgrade mirrors.
for n,fn in [(120,'connectivity_sync'),(121,'operational_intelligence'),(122,'purchase_planning'),(123,'api_mobile_contracts'),(124,'release_contract')]:
    matches=list((ROOT/'backend/migrations').glob(f'{n}_v480_*.sql'))
    check(f'migration {n} exists',len(matches)==1,str(matches))
    if matches:
        m=matches[0]; s=m.read_text(encoding='utf-8')
        check(f'migration {n} registered', re.search(rf"values\(\s*{n}\s*,\s*'4\.8\.0'",s,re.I) is not None)
        mirror=ROOT/'backend/upgrade_from_119'/m.name
        check(f'migration {n} upgrade mirror',mirror.exists() and mirror.read_bytes()==m.read_bytes())
        tags=re.findall(r'\$[A-Za-z_0-9]*\$',s)
        counts={tag:tags.count(tag) for tag in set(tags)}
        check(f'migration {n} dollar quotes paired',all(v%2==0 for v in counts.values()),str(counts))
        check(f'migration {n} transaction boundary',re.search(r'^begin\s*;',s,re.I|re.M) is not None and re.search(r'^commit\s*;',s,re.I|re.M) is not None)

m120=text('backend/migrations/120_v480_connectivity_sync.sql')
for token in ['thq_sync_state_v480','thq_sync_events_v480','thq_sync_bump_v480','thq_sync_versions_v480','operations_intelligence']:
    check(f'connectivity migration contains {token}',token in m120)
check('sync events bounded', '2000' in m120 and 'delete from public.thq_sync_events_v480' in m120)
check('custom tenant menu gets intelligence node', "p.tenant_id is not null" in m120 and "'operations_intelligence'" in m120)
check('sync domains cover config/catalog/parties', all(x in m120 for x in ["'configuration'","'catalogue'","'parties'"]))

m121=text('backend/migrations/121_v480_operational_intelligence.sql')
for token in ['inventory_intelligence_v480','customer_credit_intelligence_v480','supplier_payables_intelligence_v480','business_attention_summary_v480']:
    check(f'intelligence migration contains {token}',token in m121)
check('inventory uses available not raw only','reserved_quantity' in m121 and 'damaged_quantity' in m121 and 'quarantine_quantity' in m121)
check('inventory demand return-aware','sales_return_items' in m121 and 'sale_item_id=si.id' in m121)
check('inventory last sale is all-history','last_sold as' in m121 and 'max(s.sale_date)' in m121)
check('customer credit return-aware',"s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0)" in m121)
check('supplier payable return-aware',"p.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0)" in m121)
check('credit ageing buckets',all(x in m121 for x in ['days_1_30','days_31_60','days_61_90','days_90_plus']))

m122=text('backend/migrations/122_v480_purchase_planning.sql')
for token in ['purchase_orders_v480','purchase_order_items_v480','purchase_order_status_history_v480','purchase_reorder_suggestions_v480','purchase_order_create_v480','purchase_order_status_v480']:
    check(f'purchase planning contains {token}',token in m122)
check('PO statuses exclude receiving',"check(status in('draft','submitted','approved','ordered','cancelled'))" in m122)
check('PO controlled transitions',"when 'draft' then p_status in('submitted','cancelled')" in m122 and "when 'approved' then p_status in('ordered','cancelled')" in m122)
check('PO cancellation reason required','Cancellation reason is required' in m122)
check('PO creation does not touch stock','v4_location_stock_apply' not in m122 and 'inventory_adjust_stock' not in m122)
check('PO creation does not post accounting','v4_journal_create' not in m122 and 'journal_entries' not in m122)
check('reorder suggestion supplier/location aware','last_supplier_id' in m122 and 'o.location_id' in m122)
check('reorder suggestion carries product tax','tax_rate numeric' in m122 and 'pv.tax_rate' in m122)

m123=text('backend/migrations/123_v480_api_mobile_contracts.sql')
for token in ['thq_api_contract_v480','mobile_store_status_v480','mobile_business_summary_v480']:
    check(f'API/mobile migration contains {token}',token in m123)
check('mobile summary includes attention/sync',"'attention',v_attention" in m123 and "'sync',public.thq_sync_versions_v480" in m123)

m124=text('backend/migrations/124_v480_release_contract.sql')
check('backend minimum app 4.8.0',"'minimum_app_version','4.8.0'" in m124)
check('backend API v1',"'api_version','v1'" in m124)
check('release verify exists','thq_v480_release_verify' in m124)

# THQ API Edge Function.
edge_b=ROOT/'backend/functions/thq-api/index.ts'; edge_s=ROOT/'supabase/functions/thq-api/index.ts'
check('THQ API backend function exists',edge_b.exists())
check('THQ API supabase mirror exists',edge_s.exists())
check('THQ API mirrors identical',edge_b.exists() and edge_s.exists() and edge_b.read_bytes()==edge_s.read_bytes())
if edge_b.exists():
    e=edge_b.read_text(encoding='utf-8')
    for resource in ['sync','attention','inventory-intelligence','customer-credit','supplier-payables','reorder-suggestions','purchase-orders','business-summary','store-summary']:
        check(f'THQ API routes {resource}',resource in e)
    check('THQ API caller-auth client','Authorization: authHeader' in e and 'caller.auth.getUser()' in e)
    check('THQ API normal path not service role','SUPABASE_SERVICE_ROLE_KEY' not in e)

# Client integration.
client_home=text('apps/client_app/lib/screens/client_home_screen.dart')
for token in ['ThqApiService','_startSyncMonitor','Duration(seconds: 20)','_updatesAvailable','OperationsIntelligenceScreen','operations_intelligence']:
    check(f'Client integration {token}',token in client_home)
check('Client detects all domain drift','latest.anyChangedFrom(previous)' in client_home)
check('Client refresh clears drift','_updatesAvailable = false' in client_home)
ops_screen=text('apps/client_app/lib/screens/operations_intelligence_screen.dart')
for token in ['Operations Intelligence','Stock Intelligence','Customer Credit','Supplier Payables','Purchase Planning','Purchase Orders','Create PO from selected']:
    check(f'Operations UI contains {token}',token in ops_screen)
check('PO grouping by store and supplier',"${row['location_id']}|${row['last_supplier_id']}" in ops_screen)
check('PO tax from suggestion',"'tax_rate': _n(r['tax_rate'])" in ops_screen)
check('PO dialog avoids disposable controller lifecycle','TextEditingController()' not in ops_screen[ops_screen.find('Future<void> _changeOrderStatus'):ops_screen.find('Future<void> _showOrder')])
svc=text('apps/client_app/lib/services/operations_intelligence_service.dart')
for resource in ['attention','inventory-intelligence','customer-credit','supplier-payables','reorder-suggestions','purchase-orders']:
    check(f'Client intelligence service uses {resource}',resource in svc)
client_api=text('apps/client_app/lib/services/thq_api_service.dart')
check('Client uses Edge thq-api',"functions.invoke(\n      'thq-api'" in client_api)

# POS sync drift does not react to ordinary sales/inventory.
pos_home=text('apps/pos_app/lib/screens/pos_home_screen.dart')
for token in ['ThqApiService','_startSyncMonitor','Duration(seconds: 15)','_updatesAvailable']:
    check(f'POS sync integration {token}',token in pos_home)
check('POS watches master/config only','configurationOrMasterChangedFrom(previous)' in pos_home)
check('POS explicit refresh remains','Future<void> _requestRefresh()' in pos_home and 'Complete or Hold any current cart first' in pos_home)
pos_api=text('apps/pos_app/lib/services/thq_api_service.dart')
check('POS uses Edge thq-api for sync',"functions.invoke(\n      'thq-api'" in pos_api)

# Admin support visibility.
health_service=text('apps/admin_panel/lib/services/system_health_service.dart')
health_screen=text('apps/admin_panel/lib/screens/system_health_screen.dart')
check('Admin health reads API contract','thq_api_contract_v480' in health_service)
check('Admin health reads sync versions','thq_sync_versions_v480' in health_service)
check('Admin health displays THQ API',"label: 'THQ API'" in health_screen)
check('Admin health displays Config Sync',"label: 'Config Sync'" in health_screen)

# Preserve critical v4.7.3 behavior.
pos=text('apps/pos_app/lib/screens/pos_screen.dart')
check('Hold uses workspace not modal','_PosWorkspace.hold' in pos and 'Widget _holdSalePage()' in pos)
check('Resume held grid workspace','_PosWorkspace.heldInvoices' in pos and 'GridView.builder(' in pos)
check('Held selection returns to products','_workspace = _PosWorkspace.products' in pos)
check('POS terminal daily v473 retained',"'pos_terminal_day_v473'" in text('apps/pos_app/lib/services/terminal_day_service.dart'))
check('POS exact-terminal today sales retained',"'pos_sales_today_v473'" in text('apps/pos_app/lib/services/sales_service.dart'))

# Updated app runtime versions.
for rel in ['apps/client_app/lib/services/device_heartbeat_service.dart','apps/client_app/lib/services/device_installation_service.dart','apps/pos_app/lib/services/device_heartbeat_service.dart','apps/pos_app/lib/services/device_installation_service.dart']:
    check(f'{rel} reports 4.8.0',"'4.8.0'" in text(rel))
for rel in ['apps/client_app/lib/services/backend_compatibility_service.dart','apps/pos_app/lib/services/backend_compatibility_service.dart']:
    check(f'{rel} says ERP 4.8','THQ ERP 4.8 requires migration' in text(rel))

# Tests updated.
for rel in ['apps/client_app/test/widget_test.dart','apps/pos_app/test/widget_test.dart','packages/erp_core/test/erp_core_test.dart']:
    s=text(rel); check(f'{rel} 4.8.0 test',"'4.8.0'" in s); check(f'{rel} migration 124', '124' in s); check(f'{rel} API v1',"'v1'" in s)

# Required release artifacts.
for rel in ['README_V480_RELEASE.md','CHANGELOG_V480.md','docs/V480_ARCHITECTURE.md','docs/V480_RELEASE_ACCEPTANCE.md','docs/THQ_API_V1.md','backend/THQ_ERP_V480_UPGRADE_FROM_119.sql','backend/upgrade_from_119/V480_POST_UPGRADE_CHECK.sql']:
    check(f'release artifact {rel}',(ROOT/rel).exists())

# Relative Dart imports resolve.
for p in list(ROOT.glob('apps/*/lib/**/*.dart'))+list(ROOT.glob('packages/erp_core/lib/**/*.dart')):
    src=p.read_text(encoding='utf-8',errors='ignore')
    for imp in re.findall(r"import\s+'([^']+)'",src):
        if imp.startswith('.'):
            target=(p.parent/imp).resolve()
            check(f'import resolves {p.relative_to(ROOT)} -> {imp}',target.exists(),str(target))

# Balanced delimiters lexer ignoring comments/strings.
def balanced(path):
    src=path.read_text(encoding='utf-8',errors='ignore')
    stack=[]; pairs={')':'(',']':'[','}':'{'}; i=0; state='code'; quote=''; triple=False; block_depth=0
    while i<len(src):
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
                if not stack or stack[-1]!=pairs[c]: return False
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

for p in list(ROOT.glob('apps/*/lib/**/*.dart'))+list(ROOT.glob('packages/erp_core/lib/**/*.dart')):
    check(f'Dart structural balance {p.relative_to(ROOT)}',balanced(p))

check('Windows runtime validation helper included',(ROOT/'tools/validate_v480_windows.ps1').exists())
check('V4.8 deployment guide included',(ROOT/'docs/V480_DEPLOYMENT.md').exists())

# Runtime ambiguity hardening for PL/pgSQL RETURNS TABLE output names.
m121=(ROOT/'backend/migrations/121_v480_operational_intelligence.sql').read_text(encoding='utf-8')
m123=(ROOT/'backend/migrations/123_v480_api_mobile_contracts.sql').read_text(encoding='utf-8')
check('customer ageing qualifies output-name columns','from open_sales os group by os.customer_id' in m121)
check('supplier ageing qualifies output-name columns','from open_purchases op group by op.supplier_id' in m121)
check('mobile store stock CTE qualifies location/status','ii.location_id' in m123 and "ii.status='low_stock'" in m123)

# Source cleanliness.
banned=[]
for p in ROOT.rglob('*'):
    if any(part in {'.git','node_modules','.dart_tool','.gradle','build','.idea','.vscode'} for part in p.parts): banned.append(str(p.relative_to(ROOT)))
check('release tree excludes generated/VCS clutter',not banned,', '.join(banned[:10]))

passed=sum(ok for _,ok,_ in results); total=len(results)
report=['THQ ERP V4.8.0 STATIC RELEASE VERIFICATION',f'Passed: {passed}/{total}','']
for name,ok,detail in results:
    report.append(f"{'PASS' if ok else 'FAIL'} | {name}" + (f' | {detail}' if detail and not ok else ''))
(ROOT/'V480_STATIC_VERIFICATION.txt').write_text('\n'.join(report)+'\n',encoding='utf-8')
print('\n'.join(report[:3]))
if passed!=total:
    for name,ok,detail in results:
        if not ok: print('FAIL:',name,detail)
    sys.exit(1)
