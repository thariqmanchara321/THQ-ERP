from pathlib import Path
import re, sys
ROOT=Path(__file__).resolve().parents[1]
results=[]
def check(name, ok, detail=''): results.append((name,bool(ok),str(detail)))
def text(rel): return (ROOT/rel).read_text(encoding='utf-8',errors='ignore')

# Versions / shared contract.
for app in ['admin_panel','client_app','pos_app']:
    s=text(f'apps/{app}/pubspec.yaml')
    check(f'{app} version 4.8.6+14',bool(re.search(r'^version:\s*4\.8\.6\+14\s*$',s,re.M)))
check('erp_core version 4.8.6',bool(re.search(r'^version:\s*4\.8\.6\s*$',text('packages/erp_core/pubspec.yaml'),re.M)))
rc=text('packages/erp_core/lib/src/release_contract.dart')
for token in ["appVersion = '4.8.6'",'minimumMigration = 160',"releaseName = 'Offline POS'","apiVersion = 'v1'"]:
    check(f'release contract {token}',token in rc)

# Original analyzer report fixes.
for app in ['client_app','pos_app']:
    s=text(f'apps/{app}/lib/screens/purchasing_v2_screen.dart')
    check(f'{app} unused _payments removed','_payments' not in s)
    for method in ['_createPoFromRequest','_receiveOrder','_createInvoiceFromOrder']:
        pos=s.find(f'Future<void> {method}')
        nxt=s.find('\n  Future<',pos+10)
        block=s[pos:nxt if nxt>0 else len(s)]
        check(f'{app} {method} mounted guard',('if (!mounted) return;' in block) or ('|| !mounted) return;' in block))
pos_purchases=text('apps/pos_app/lib/screens/purchases_screen.dart')
check('POS PurchasesScreen defines historyOnly','final bool historyOnly;' in pos_purchases and 'this.historyOnly = false' in pos_purchases)

# Flutter 3.33+ analyzer compatibility cleanup.
for app in ['client_app','pos_app']:
    policy=text(f'apps/{app}/lib/screens/product_tracking_policy_screen.dart')
    purchasing=text(f'apps/{app}/lib/screens/purchasing_v2_screen.dart')
    tracking=text(f'apps/{app}/lib/screens/tracking_workspace_screen.dart')
    check(f'{app} tracking dropdown uses initialValue', 'DropdownButtonFormField<String>(initialValue: _mode' in policy and 'DropdownButtonFormField<String>(value: _mode' not in policy)
    check(f'{app} purchasing dropdowns avoid deprecated value', 'DropdownButtonFormField<String>(value:' not in purchasing and '\n                value: _ledgerSupplierId,' not in purchasing)
    check(f'{app} tracking separators use wildcard underscore', 'separatorBuilder: (_, __)' not in tracking)
offline_analyzer=text('apps/pos_app/lib/services/offline_pos_service.dart')
for stmt in ['productStmt','customerStmt','serialStmt']:
    check(f'POS sqlite {stmt} uses close', f'{stmt}.close();' in offline_analyzer and f'{stmt}.dispose();' not in offline_analyzer)
check('POS offline summary loop uses braces', 'for (final row in rows) {' in offline_analyzer)

# Offline POS dependencies and local engine.
pos_pub=text('apps/pos_app/pubspec.yaml')
for dep in ['path: ^1.9.1','path_provider: ^2.1.6','sqlite3: ^3.5.1']:
    check(f'POS dependency {dep}',dep in pos_pub)
local=text('apps/pos_app/lib/services/offline_pos_service.dart')
for token in ['thq_pos_offline_v486.sqlite','PRAGMA journal_mode=WAL','PRAGMA synchronous=FULL','offline_products','offline_customers','offline_serials','offline_invoices','queueSale','BEGIN IMMEDIATE','reserved_request_id','_reapplyUnsyncedReservations','Future<OfflineInvoiceRecord?> invoice']:
    check(f'local DB contains {token}',token in local)
check('local queue reserves before insert',local.find('_applyReservation(db, tenantId, locationId, requestId') < local.find("INSERT INTO offline_invoices"))

sync=text('apps/pos_app/lib/services/offline_pos_sync_service.dart')
for rpc in ['pos_offline_product_cache_v486','pos_offline_customer_cache_v486','pos_offline_cache_manifest_v486','pos_offline_available_serials_v486','pos_offline_sale_sync_v486']:
    check(f'offline sync uses {rpc}',rpc in sync)
check('automatic retry keeps transport failure pending',"markPending(record.requestId" in sync)
check('serial cache pagination','const pageSize = 1000' in sync and "'p_after': after" in sync)

receipt=text('apps/pos_app/lib/services/offline_receipt_service.dart')
for token in ['OFFLINE SALE RECEIPT','PENDING SERVER SYNC','final THQ invoice number','directPrintPdfBytes']:
    check(f'offline receipt {token}',token in receipt)

pos=text('apps/pos_app/lib/screens/pos_screen.dart')
for token in ['OfflinePosService.instance','OfflinePosSyncService()','Timer.periodic(const Duration(seconds: 20)','queueSale(','syncPending(widget.session','printQueuedReceipt(','findAvailableSerial(','Offline cached price',"'OFFLINE' : 'ONLINE'"]:
    check(f'POS integration {token}',token in pos)
check('POS no direct createSale checkout','_sales.createSale(' not in pos)
check('POS local queue before sync',pos.find('await _offlineLocal.queueSale(') < pos.find('await _offlineSync.syncPending(widget.session, onlyRequestId: requestId)'))
home=text('apps/pos_app/lib/screens/pos_home_screen.dart')
check('Offline Sync page routed','OfflinePosSyncScreen(session: session)' in home and "pages['offline_sync']" in home)

# Database migrations and mirrors.
for n in range(154,161):
    matches=list((ROOT/'backend/migrations').glob(f'{n}_v486_*.sql'))
    check(f'migration {n} exists once',len(matches)==1,matches)
    if not matches: continue
    p=matches[0]; s=p.read_text(encoding='utf-8')
    check(f'migration {n} registered 4.8.6',bool(re.search(rf"values\(\s*{n}\s*,\s*'4\.8\.6'",s,re.I)))
    check(f'migration {n} transaction begin',bool(re.search(r'^begin\s*;',s,re.I|re.M)))
    check(f'migration {n} transaction commit',bool(re.search(r'^commit\s*;',s,re.I|re.M)))
    tags=re.findall(r'\$[A-Za-z_0-9]*\$',s); counts={tag:tags.count(tag) for tag in set(tags)}
    check(f'migration {n} dollar quotes paired',all(v%2==0 for v in counts.values()),counts)
    mirror=ROOT/'backend/upgrade_from_153'/p.name
    check(f'migration {n} mirror exact',mirror.exists() and mirror.read_bytes()==p.read_bytes())

m154=text('backend/migrations/154_v486_offline_pos_foundation.sql')
for token in ['pos_offline_sync_v486','v486_pos_device_location',"d.status","d.app_type"]: check(f'm154 {token}',token in m154)
m155=text('backend/migrations/155_v486_offline_sale_sync.sql')
for token in ['pos_offline_sale_sync_v486','pg_advisory_xact_lock','v482_price_sale_items','PRICE_CHANGED','TAX_CHANGED','STOCK_CONFLICT','sales_create_v483','trim(p_request_id)']:
    check(f'm155 {token}',token in m155)
check('m155 no goto','goto ' not in m155.lower())
m157=text('backend/migrations/157_v486_offline_cache_contract.sql')
for token in ['location_product_settings','current_location_id','reserved_quantity','damaged_quantity','quarantine_quantity','as t(x)','pos_offline_available_serials_v486']:
    check(f'm157 {token}',token in m157)
check('m157 no wrong inventory serial location_id',re.search(r'\bs\.location_id\s*=',m157) is None)
m160=text('backend/migrations/160_v486_release_contract.sql')
check('m160 migration 160',"'migration_no',160" in m160)
check('m160 release verify','thq_v486_release_verify' in m160)

# Combined upgrade.
bundle=text('backend/THQ_ERP_V486_UPGRADE_FROM_153.sql')
positions=[bundle.find(f"values({n},'4.8.6'") for n in range(154,161)]
check('combined bundle contains 154-160',all(x>=0 for x in positions),positions)
check('combined bundle ordered',positions==sorted(positions),positions)
check('combined root/mirror identical',(ROOT/'backend/THQ_ERP_V486_UPGRADE_FROM_153.sql').read_bytes()==(ROOT/'backend/upgrade_from_153/THQ_ERP_V486_UPGRADE_FROM_153.sql').read_bytes())

# Carry-forward migration 144 bug fixed everywhere.
for p in ROOT.glob('backend/**/*.sql'):
    s=p.read_text(encoding='utf-8',errors='ignore')
    check(f'no v484 comma regression {p.relative_to(ROOT)}',"'purchase_invoice_v484'::text ih.id" not in s)

# Edge API route and mirrors.
edge_b=ROOT/'backend/functions/thq-api/index.ts'; edge_s=ROOT/'supabase/functions/thq-api/index.ts'
check('THQ API mirrors exact',edge_b.read_bytes()==edge_s.read_bytes())
e=edge_b.read_text(encoding='utf-8')
check('THQ API offline-pos route',"case 'offline-pos':" in e)
for rpc in ['pos_offline_sale_sync_v486','pos_offline_request_lookup_v486','pos_offline_sync_list_v486','pos_offline_sync_summary_v486','pos_offline_product_cache_v486','pos_offline_customer_cache_v486','pos_offline_available_serials_v486','pos_offline_cache_manifest_v486','pos_offline_api_contract_v486']:
    check(f'THQ API {rpc}',rpc in e)
check('THQ API no service role key','SUPABASE_SERVICE_ROLE_KEY' not in e)

# Release artifacts.
for rel in ['README_V486_RELEASE.md','CHANGELOG_V486.md','docs/V486_ARCHITECTURE.md','docs/V486_DEPLOYMENT.md','docs/V486_RELEASE_ACCEPTANCE.md','backend/V486_POST_UPGRADE_CHECK.sql','backend/V486_EDGE_FUNCTIONS_DEPLOY.md','backend/upgrade_from_153/README_DEPLOY_V486.md','tools/validate_v486_windows.ps1']:
    check(f'release artifact {rel}',(ROOT/rel).exists())

# Tests lock expected version/migration.
for rel in ['apps/client_app/test/widget_test.dart','apps/pos_app/test/widget_test.dart','packages/erp_core/test/erp_core_test.dart']:
    s=text(rel); check(f'{rel} expects 4.8.6',"'4.8.6'" in s); check(f'{rel} expects 160','160' in s)

# Relative Dart imports resolve.
for p in list(ROOT.glob('apps/*/lib/**/*.dart'))+list(ROOT.glob('packages/erp_core/lib/**/*.dart')):
    src=p.read_text(encoding='utf-8',errors='ignore')
    for imp in re.findall(r"import\s+'([^']+)'",src):
        if imp.startswith('.'):
            target=(p.parent/imp).resolve()
            check(f'import resolves {p.relative_to(ROOT)} -> {imp}',target.exists(),target)

# Lightweight delimiter parser for new Dart/TS sources, aware of comments and triple strings.
def balanced(path):
    src=path.read_text(encoding='utf-8',errors='ignore'); stack=[]; pairs={')':'(',']':'[','}':'{'}; i=0; state='code'; quote=''; triple=False; block=0
    while i<len(src):
        c=src[i]; two=src[i:i+2]
        if state=='code':
            if two=='//': state='line'; i+=2; continue
            if two=='/*': state='block'; block=1; i+=2; continue
            if c in "'\"":
                quote=c; triple=src[i:i+3]==c*3; state='string'; i+=3 if triple else 1; continue
            if c in '([{': stack.append(c)
            elif c in ')]}':
                if not stack or stack[-1]!=pairs[c]: return False
                stack.pop()
            i+=1
        elif state=='line':
            if c=='\n': state='code'
            i+=1
        elif state=='block':
            if two=='/*': block+=1; i+=2
            elif two=='*/': block-=1; i+=2; state='code' if block==0 else 'block'
            else: i+=1
        else:
            if c=='\\': i+=2; continue
            if triple and src[i:i+3]==quote*3: state='code'; i+=3; continue
            if not triple and c==quote: state='code'; i+=1; continue
            i+=1
    return not stack and state not in ('block','string')
for rel in ['apps/pos_app/lib/services/offline_pos_service.dart','apps/pos_app/lib/services/offline_pos_sync_service.dart','apps/pos_app/lib/services/offline_receipt_service.dart','apps/pos_app/lib/screens/offline_pos_sync_screen.dart','apps/pos_app/lib/screens/pos_screen.dart','apps/pos_app/lib/screens/pos_home_screen.dart','apps/client_app/lib/screens/purchasing_v2_screen.dart','apps/pos_app/lib/screens/purchasing_v2_screen.dart','backend/functions/thq-api/index.ts','supabase/functions/thq-api/index.ts']:
    check(f'delimiters balanced {rel}',balanced(ROOT/rel))

failed=[r for r in results if not r[1]]
print(f'THQ ERP v4.8.6 static verification: {len(results)-len(failed)}/{len(results)} checks passed')
if failed:
    for name,_,detail in failed: print(f'FAIL: {name} {detail}')
    sys.exit(1)
print('PASS')
