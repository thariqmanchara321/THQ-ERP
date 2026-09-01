from pathlib import Path
import re, sys
ROOT=Path(__file__).resolve().parents[1]
results=[]
def check(name, ok, detail=''):
    results.append((name,bool(ok),str(detail)))
def text(rel):
    return (ROOT/rel).read_text(encoding='utf-8',errors='ignore')

# Versions / contract.
for app in ['admin_panel','client_app','pos_app']:
    s=text(f'apps/{app}/pubspec.yaml')
    check(f'{app} version 4.8.5+13', bool(re.search(r'^version:\s*4\.8\.5\+13\s*$',s,re.M)))
check('erp_core version 4.8.5', bool(re.search(r'^version:\s*4\.8\.5\s*$',text('packages/erp_core/pubspec.yaml'),re.M)))
rc=text('packages/erp_core/lib/src/release_contract.dart')
for token in ["appVersion = '4.8.5'",'minimumMigration = 153',"releaseName = 'Warehouse & Transfers'","apiVersion = 'v1'"]:
    check(f'release contract {token}',token in rc)

# Migrations and upgrade mirrors.
for n in range(147,154):
    matches=list((ROOT/'backend/migrations').glob(f'{n}_v485_*.sql'))
    check(f'migration {n} exists once',len(matches)==1,matches)
    if not matches: continue
    p=matches[0]; s=p.read_text(encoding='utf-8')
    check(f'migration {n} registered 4.8.5',bool(re.search(rf"values\(\s*{n}\s*,\s*'4\.8\.5'",s,re.I)))
    check(f'migration {n} begins transaction',bool(re.search(r'^begin\s*;',s,re.I|re.M)))
    check(f'migration {n} commits transaction',bool(re.search(r'^commit\s*;',s,re.I|re.M)))
    tags=re.findall(r'\$[A-Za-z_0-9]*\$',s); counts={tag:tags.count(tag) for tag in set(tags)}
    check(f'migration {n} dollar quotes paired',all(v%2==0 for v in counts.values()),counts)
    mirror=ROOT/'backend/upgrade_from_146'/p.name
    check(f'migration {n} upgrade mirror matches',mirror.exists() and mirror.read_bytes()==p.read_bytes())

m147=text('backend/migrations/147_v485_warehouse_transfer_foundation.sql')
for token in ['stock_transfer_allocations_v485','stock_transfer_history_v485','reserved_quantity','reserved_transfer_id',"'in_transit'","'missing'",'warehouse_locations_v485']:
    check(f'foundation contains {token}',token in m147)
check('warehouse uses existing business_locations', 'from public.business_locations' in m147 and 'create table public.warehouses' not in m147.lower())

m148=text('backend/migrations/148_v485_transfer_request_approval.sql')
for token in ['inventory_transfer_request_v485','inventory_transfer_decide_v485','inventory_transfer_cancel_v485','v485_transfer_release_reservation']:
    check(f'request/approval contains {token}',token in m148)
check('request reserves aggregate stock','set reserved_quantity=reserved_quantity+v_qty' in m148)
check('serial transfer reservation','reserved_transfer_id=v_id' in m148)
check('batch transfer reservation','set reserved_quantity=reserved_quantity+v_batch_qty' in m148)
check('batch IDs tenant/product validated','Batch does not belong to the selected product/business' in m148)
check('FEFO customer sale excludes transfer reservations','bb.quantity-coalesce(bb.reserved_quantity,0)' in m148)
check('serial customer sale excludes reserved serial','reserved_transfer_id is null' in m148)

m149=text('backend/migrations/149_v485_dispatch_in_transit_receive.sql')
for token in ['inventory_transfer_dispatch_v485','inventory_transfer_receive_v485',"status='in_transit'",'transfer_out','transfer_in']:
    check(f'dispatch/receive contains {token}',token in m149)
check('dispatch removes only source location stock',"v.from_location_id,r.variant_id,-r.quantity,'transfer_out'" in m149)
check('receive adds destination location stock',"v.to_location_id,r.variant_id,r.dispatched_quantity,'transfer_in'" in m149)
check('company stock not mutated during transfer','inventory_adjust_stock' not in m149)
check('serial transfer trace linked','transfer_id,transfer_item_id' in m149 and "set status='in_transit',current_location_id=null" in m149)
check('batch source consumed on dispatch','quantity=quantity-a.quantity' in m149)
check('batch destination received','inventory_batch_balances_v483' in m149 and 'excluded.quantity' in m149)

m150=text('backend/migrations/150_v485_transfer_history_warehouse_inventory.sql')
for token in ['inventory_transfers_list_v485','inventory_transfer_history_v485','inventory_transfer_detail_v485','inventory_transfer_tracking_options_v485','warehouse_inventory_v485','in_transit_quantity']:
    check(f'history/reporting contains {token}',token in m150)

m151=text('backend/migrations/151_v485_stock_count_trace_reconciliation.sql')
for token in ['inventory_stock_count_snapshot_v485','inventory_stock_count_post_v485',"status='missing'",'Batch count must provide batches','Stock count permission required']:
    check(f'stock count contains {token}',token in m151)
check('count blocks transfer reservations','Cannot post a stock count while product' in m151)
check('count batch IDs tenant/product validated','Batch does not belong to the selected product/business' in m151)
check('count enforces required batch expiry','require_batch_expiry' in m151 and 'Expiry date is required for batch' in m151)
check('count audits saleable/damaged mix','abs(v_batch_qty-v_old_qty)+abs(v_batch_damage-v_old_damage)' in m151)
check('count adjusts global and location ledgers','inventory_adjust_stock' in m151 and 'v4_location_stock_apply' in m151)

m152=text('backend/migrations/152_v485_reconciliation_api_contract.sql')
for token in ['stock_counts_list_v485','stock_count_detail_v485','inventory_stock_reconciliation_v485']:
    check(f'reconciliation contains {token}',token in m152)
for resource in ['warehouses','warehouse-inventory','stock-transfers','stock-counts','stock-reconciliation']:
    check(f'API contract resource {resource}',f"'{resource}'" in m152)
check('reconciliation checks tracked quantity','v483_location_tracked_quantity' in m152)
check('reconciliation checks company/location quantity','company_qty' in m152 and 'locations_qty' in m152)

m153=text('backend/migrations/153_v485_release_contract.sql')
check('release verifier migration 153',"'migration_no',153" in m153)
for proc in ['warehouse_locations_v485(uuid)','inventory_transfer_request_v485(uuid,uuid,uuid,jsonb,text,date,text,text)','inventory_transfer_dispatch_v485(uuid,uuid,uuid,text,text)','inventory_transfer_receive_v485(uuid,uuid,uuid,text)','inventory_stock_count_post_v485(uuid,uuid,jsonb,text,uuid,text)','inventory_stock_reconciliation_v485(uuid,uuid,text,boolean,integer)']:
    check(f'release verifier checks {proc}',proc in m153)

# Carry-forward v4.8.4 deployment bug must remain corrected.
for p in ROOT.glob('backend/**/*.sql'):
    s=p.read_text(encoding='utf-8',errors='ignore')
    check(f'no v484 purchase history missing-comma bug in {p.relative_to(ROOT)}',"'purchase_invoice_v484'::text ih.id" not in s)

# API edge function.
edge_b=ROOT/'backend/functions/thq-api/index.ts'; edge_s=ROOT/'supabase/functions/thq-api/index.ts'
check('THQ API backend exists',edge_b.exists()); check('THQ API mirror exists',edge_s.exists())
check('THQ API mirrors identical',edge_b.exists() and edge_s.exists() and edge_b.read_bytes()==edge_s.read_bytes())
if edge_b.exists():
    e=edge_b.read_text(encoding='utf-8')
    for resource in ['warehouses','warehouse-inventory','stock-transfers','stock-counts','stock-reconciliation']:
        check(f'THQ API routes {resource}',f"case '{resource}'" in e)
    for rpc in ['warehouse_locations_v485','warehouse_inventory_v485','inventory_transfer_request_v485','inventory_transfer_decide_v485','inventory_transfer_dispatch_v485','inventory_transfer_receive_v485','inventory_transfer_history_v485','inventory_stock_count_post_v485','inventory_stock_reconciliation_v485']:
        check(f'THQ API invokes {rpc}',rpc in e)
    check('THQ API has no service role key','SUPABASE_SERVICE_ROLE_KEY' not in e)

# Flutter integration.
for app in ['client_app','pos_app']:
    service=text(f'apps/{app}/lib/services/stock_transfer_service.dart')
    screen=text(f'apps/{app}/lib/screens/stock_transfers_screen.dart')
    home=text(f'apps/{app}/lib/screens/client_home_screen.dart')
    check(f'{app} routes stock_transfers workspace','StockTransfersScreen(session: session)' in home)
    for rpc in ['inventory_transfers_list_v485','warehouse_locations_v485','warehouse_inventory_v485','inventory_transfer_request_v485','inventory_transfer_decide_v485','inventory_transfer_dispatch_v485','inventory_transfer_receive_v485','inventory_stock_count_snapshot_v485','inventory_stock_count_post_v485','inventory_stock_reconciliation_v485']:
        check(f'{app} service uses {rpc}',rpc in service)
    for label in ['Transfers','Warehouses','Stock Counts','Reconciliation']:
        check(f'{app} workspace label {label}',label in screen)
    check(f'{app} serial transfer capture','serial_numbers' in screen)
    check(f'{app} batch transfer capture',"'batches'" in screen or 'batches' in screen)

# POS got location-hierarchy fields needed by shared workspace.
pos_model=text('apps/pos_app/lib/models/client_session.dart')
for token in ['hierarchyRole','isWarehouse','canOperate','roleLabel']:
    check(f'POS location access supports {token}',token in pos_model)

# Upgrade/release artifacts.
for rel in ['README_V485_RELEASE.md','CHANGELOG_V485.md','docs/V485_ARCHITECTURE.md','docs/V485_DEPLOYMENT.md','docs/V485_RELEASE_ACCEPTANCE.md','backend/THQ_ERP_V485_UPGRADE_FROM_146.sql','backend/V485_POST_UPGRADE_CHECK.sql','backend/V485_EDGE_FUNCTIONS_DEPLOY.md','backend/upgrade_from_146/THQ_ERP_V485_UPGRADE_FROM_146.sql','backend/upgrade_from_146/V485_POST_UPGRADE_CHECK.sql','backend/upgrade_from_146/README_DEPLOY_V485.md','tools/validate_v485_windows.ps1']:
    check(f'release artifact {rel}',(ROOT/rel).exists())

bundle=text('backend/THQ_ERP_V485_UPGRADE_FROM_146.sql')
positions=[bundle.find(f"values({n},'4.8.5'") for n in range(147,154)]
check('combined bundle contains 147-153',all(x>=0 for x in positions),positions)
check('combined bundle ordered 147-153',positions==sorted(positions),positions)
check('combined bundle mirror identical',(ROOT/'backend/upgrade_from_146/THQ_ERP_V485_UPGRADE_FROM_146.sql').read_bytes()==(ROOT/'backend/THQ_ERP_V485_UPGRADE_FROM_146.sql').read_bytes())

# Version assertions in tests.
for rel in ['apps/client_app/test/widget_test.dart','apps/pos_app/test/widget_test.dart','packages/erp_core/test/erp_core_test.dart']:
    s=text(rel); check(f'{rel} expects 4.8.5',"'4.8.5'" in s); check(f'{rel} expects 153','153' in s)

# Relative Dart imports resolve: gives broad full-tree coverage.
for p in list(ROOT.glob('apps/*/lib/**/*.dart'))+list(ROOT.glob('packages/erp_core/lib/**/*.dart')):
    src=p.read_text(encoding='utf-8',errors='ignore')
    for imp in re.findall(r"import\s+'([^']+)'",src):
        if imp.startswith('.'):
            target=(p.parent/imp).resolve()
            check(f'import resolves {p.relative_to(ROOT)} -> {imp}',target.exists(),target)

# Lightweight delimiter sanity for new Dart/TS source.
def balanced(path):
    src=path.read_text(encoding='utf-8',errors='ignore'); stack=[]; pairs={')':'(',']':'[','}':'{'}; i=0; state='code'; quote=''; block=0
    while i<len(src):
        c=src[i]; pair=src[i:i+2]
        if state=='code':
            if pair=='//': state='line'; i+=2; continue
            if pair=='/*': state='block'; block=1; i+=2; continue
            if c in "'\"": quote=c; state='string'; i+=1; continue
            if c in '([{': stack.append(c)
            elif c in ')]}':
                if not stack or stack[-1]!=pairs[c]: return False
                stack.pop()
            i+=1
        elif state=='line':
            if c=='\n': state='code'
            i+=1
        elif state=='block':
            if pair=='/*': block+=1; i+=2
            elif pair=='*/': block-=1; i+=2; state='code' if block==0 else 'block'
            else: i+=1
        else:
            if c=='\\': i+=2; continue
            if c==quote: state='code'
            i+=1
    return not stack and state not in ('block','string')
for rel in ['apps/client_app/lib/screens/stock_transfers_screen.dart','apps/pos_app/lib/screens/stock_transfers_screen.dart','apps/client_app/lib/services/stock_transfer_service.dart','apps/pos_app/lib/services/stock_transfer_service.dart','backend/functions/thq-api/index.ts','supabase/functions/thq-api/index.ts']:
    check(f'delimiters balanced {rel}',balanced(ROOT/rel))

failed=[r for r in results if not r[1]]
print(f'THQ ERP v4.8.5 static verification: {len(results)-len(failed)}/{len(results)} checks passed')
if failed:
    for name,_,detail in failed: print(f'FAIL: {name} {detail}')
    sys.exit(1)
print('PASS')
