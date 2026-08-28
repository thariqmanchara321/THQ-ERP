from pathlib import Path
import re, sys, hashlib
ROOT=Path(__file__).resolve().parents[1]
results=[]
def check(name, ok, detail=''):
    results.append((name,bool(ok),detail))

def text(rel): return (ROOT/rel).read_text(encoding='utf-8')

# Versions/contracts
for app in ['admin_panel','client_app','pos_app']:
    s=text(f'apps/{app}/pubspec.yaml')
    check(f'{app} version 4.7.1+4', re.search(r'^version:\s*4\.7\.1\+4\s*$',s,re.M) is not None)
core=text('packages/erp_core/pubspec.yaml')
check('erp_core version 4.7.1', re.search(r'^version:\s*4\.7\.1\s*$',core,re.M) is not None)
rc=text('packages/erp_core/lib/src/release_contract.dart')
check('shared app version', "appVersion = '4.7.1'" in rc)
check('shared migration contract 117', 'minimumMigration = 117' in rc)

# Migration set and combined script
expected=[
'111_v471_system_admin_fixes.sql','112_v471_customer_receivables.sql',
'113_v471_pos_operations.sql','114_v471_release_hardening.sql',
'115_v471_hotfix1_runtime_errors.sql','116_v471_hotfix2_audit_overload_hardening.sql',
'117_v471_hotfix3_pos_operational_module_visibility.sql']
actual=sorted(p.name for p in (ROOT/'backend/upgrade_from_110').glob('*.sql'))
check('upgrade folder exactly 111-117',actual==expected,str(actual))
combined=text('backend/THQ_ERP_V471_UPGRADE_FROM_110_TO_117.sql')
for n in expected: check(f'combined contains {n}',combined.count(f'FILE: {n}')==1)
for n in range(111,118):
    s=text(f'backend/migrations/{expected[n-111]}')
    check(f'migration {n} begins transaction', re.search(r'\bbegin\s*;',s,re.I) is not None)
    check(f'migration {n} commits', re.search(r'\bcommit\s*;',s,re.I) is not None)
    check(f'migration {n} registers itself', re.search(rf"values\s*\(\s*{n}\s*,\s*'4\.7\.1'", s, re.I) is not None)

m111=text('backend/migrations/111_v471_system_admin_fixes.sql')
m112=text('backend/migrations/112_v471_customer_receivables.sql')
m113=text('backend/migrations/113_v471_pos_operations.sql')
m114=text('backend/migrations/114_v471_release_hardening.sql')
m115=text('backend/migrations/115_v471_hotfix1_runtime_errors.sql')
m116=text('backend/migrations/116_v471_hotfix2_audit_overload_hardening.sql')
m117=text('backend/migrations/117_v471_hotfix3_pos_operational_module_visibility.sql')
for fn in ['platform_system_update_v471','platform_system_delete_v471','platform_location_delete_v471','tenant_system_create_v471','tenant_system_update_v471','tenant_system_revoke_v471']:
    check(f'{fn} defined',f'function public.{fn}' in m111)
check('system roles defined', all(x in m111 for x in ["'pos'","'back_office'","'office'","'inventory'"]))
check('POS modules include cashier shifts',"'cashier_shifts'" in m111)
check('POS modules include terminal daily',"'terminal_day'" in m111)
for fn in ['customer_account_v471','customer_accounts_list_v471','customer_receive_payment_v471']:
    check(f'{fn} defined',f'function public.{fn}' in m112)
check('receivables subtract returns','grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0)' in m112)
check('customer receipt concurrency lock','Serialize receipts per customer' in m112 and 'for update;' in m112)
check('customer receipt idempotency',"v47_request_existing" in m112 and "v47_request_complete" in m112)
check('customer receipt accounting','customer_receipt' in m112 and 'accounts_receivable' in m112)
check('customer receipt cash drawer','movement_type' in m112 and "'receipt'" in m112)
for fn in ['pos_held_sales_feed_v471','pos_terminal_day_v471']:
    check(f'{fn} defined',f'function public.{fn}' in m113)
check('terminal daily includes receipts','customer_receipt_rows' in m113)
check('cashier/day business modules backfilled',"'cashier_shifts'" in m113 and "'terminal_day'" in m113)
check('backend contract 4.7.1',"'minimum_app_version','4.7.1'" in m114)
check('backend base migration contract 114','<>114' in m114 and 'max(migration_no)' in m114)
check('hotfix 1 migration 115 registered', "values(115,'4.7.1'" in m115.replace(' ',''))
check('hotfix 2 unique audit writer','business_audit_write_v471' in m116)
check('hotfix 3 POS plan child entitlements', "('cashier_shifts')" in m117 and "('terminal_day')" in m117 and 'subscription_plan_modules' in m117)
check('hotfix 3 backend contract', "'release','Operational Stabilization Patch — Hotfix 3'" in m117)
check('business delete service-role only','platform_business_delete_v471' in m114 and "service_role" in m114)

# App wiring
pos=text('apps/pos_app/lib/screens/pos_screen.dart')
check('POS held strip inline','_heldSalesStrip()' in pos and '_restoreHeldSale' in pos)
check('POS customer partial payment','_accountBalance' in pos and 'will remain on' in pos)
check('POS customer balance action','_openCustomerAccount' in pos)
check('POS checkout shift enforcement aligned',"allowedModules.contains('cashier_shifts')" in pos and "widget.session.hasModule('cashier_shifts')" in pos)
check('POS stable checkout request id','_checkoutRequestId' in pos)
psess=text('apps/pos_app/lib/services/client_session_service.dart')
check('POS operational modules inherit POS entitlement', 'posOperationalModules' in psess and "'cashier_shifts'" in psess and "'terminal_day'" in psess and "entitledModules.contains('pos')" in psess)
pcs=text('apps/pos_app/lib/services/pos_completion_service.dart')
check('POS held feed service v471',"pos_held_sales_feed_v471" in pcs)
tds=text('apps/pos_app/lib/services/terminal_day_service.dart')
check('Terminal Daily service v471',"pos_terminal_day_v471" in tds and 'pos_terminal_day_v45' not in tds)
tdui=text('apps/pos_app/lib/screens/terminal_day_screen.dart')
check('Terminal Daily renders receipts','customer_receipt_rows' in tdui and 'Customer Receipts' in tdui)
tdexp=text('apps/pos_app/lib/services/terminal_day_export_service.dart')
check('Terminal Daily exports receipts',"Customer Receipts" in tdexp and "customer_receipt_rows" in tdexp)
cashui=text('apps/pos_app/lib/screens/cashier_shift_screen.dart')
check('Cashier Shift reads difference',"result['difference'] ?? result['variance']" in cashui)
check('Cashier Shift shows customer receipts',"Customer Receipts" in cashui)

admin=text('apps/admin_panel/lib/screens/business_details_screen.dart')
check('Admin customer accounts reachable','CustomerAccountsScreen' in admin and 'Customer Accounts' in admin)
adminloc=text('apps/admin_panel/lib/screens/business_locations_devices_screen.dart')
for token in ['platform_system_create_v471','platform_system_update_v471','platform_system_delete_v471','platform_location_delete_v471']:
    # service is separate, screen need not contain rpc names
    pass
admsvc=text('apps/admin_panel/lib/services/location_device_service.dart')
for token in ['platform_system_create_v471','platform_system_update_v471','platform_system_delete_v471','platform_location_delete_v471','platform_systems_list_v471']:
    check(f'Admin service uses {token}',token in admsvc)
check('Admin POS modules cashier/day',"cashier_shifts" in adminloc and "terminal_day" in adminloc)

cloc=text('apps/client_app/lib/services/location_service.dart')
for token in ['tenant_system_create_v471','tenant_system_update_v471','tenant_system_revoke_v471']:
    check(f'Client hierarchy uses {token}',token in cloc)
clocui=text('apps/client_app/lib/screens/locations_screen.dart')
check('Client system store reassignment','Store / location' in clocui and 'locationId: locationId' in clocui)
check('Client system roles','Back Office PC' in clocui and 'Office PC' in clocui and 'Inventory PC' in clocui)
check('Client POS terminal_day module',"'terminal_day'" in clocui)
customers=text('apps/client_app/lib/screens/customers_screen.dart')
check('Client overall receivables reachable','CustomerAccountsScreen' in customers and 'Receivables' in customers)

# Customer services/dialogs all apps
for app in ['admin_panel','client_app','pos_app']:
    svc=text(f'apps/{app}/lib/services/customer_account_service.dart')
    dlg=text(f'apps/{app}/lib/widgets/customer_account_dialog.dart')
    check(f'{app} customer receipt RPC', 'customer_receive_payment_v471' in svc)
    check(f'{app} customer account details', 'open_invoices' in dlg and 'Payment history' in dlg and 'Receive Payment' in dlg)
    check(f'{app} customer return-aware UI', "row['returned']" in dlg)

# Delete function mirrors and RPC
b=text('backend/functions/delete-business-v41/index.ts'); s=text('supabase/functions/delete-business-v41/index.ts')
check('delete-business function mirrors match',b==s)
check('delete-business uses v471 RPC',"platform_business_delete_v471" in b and ".from('tenants').delete()" not in b)

# Relative Dart imports resolve
for p in ROOT.glob('apps/*/lib/**/*.dart'):
    src=p.read_text(encoding='utf-8')
    for imp in re.findall(r"import\s+'([^']+)'",src):
        if imp.startswith('.'):
            target=(p.parent/imp).resolve()
            check(f'import resolves {p.relative_to(ROOT)} -> {imp}',target.exists(),str(target))

# Basic balanced delimiters after stripping comments/strings (all Dart/TS changed surface)
def balanced(path, pairs='()[]{}'):
    src=path.read_text(encoding='utf-8')
    # remove block/line comments and quoted strings conservatively
    src=re.sub(r'/\*.*?\*/','',src,flags=re.S)
    src=re.sub(r'//.*','',src)
    src=re.sub(r"'''[\s\S]*?'''|\"\"\"[\s\S]*?\"\"\"|'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"",'',src)
    stack=[]; opens={'(':')','[':']','{':'}'}; closes=set(opens.values())
    for c in src:
        if c in opens: stack.append(opens[c])
        elif c in closes:
            if not stack or stack.pop()!=c: return False
    return not stack
for p in list(ROOT.glob('apps/*/lib/**/*.dart'))+list(ROOT.glob('packages/erp_core/lib/**/*.dart')):
    check(f'Dart delimiters {p.relative_to(ROOT)}',balanced(p))
for p in [ROOT/'backend/functions/delete-business-v41/index.ts',ROOT/'supabase/functions/delete-business-v41/index.ts']:
    src=p.read_text(encoding='utf-8')
    check(f'TS structural braces {p.relative_to(ROOT)}',src.count('{')==src.count('}') and src.count('(')==src.count(')'))

# SQL structural sanity: dollar tags paired; each v471 migration transaction boundaries.
for name in expected:
    p=ROOT/'backend/migrations'/name;s=p.read_text(encoding='utf-8')
    tags=re.findall(r'\$[A-Za-z_0-9]*\$',s)
    counts={t:tags.count(t) for t in set(tags)}
    check(f'SQL dollar quotes paired {name}',all(v%2==0 for v in counts.values()),str(counts))

passed=sum(ok for _,ok,_ in results); total=len(results)
report=[f'THQ ERP V4.7.1 STATIC RELEASE VERIFICATION',f'Passed: {passed}/{total}','']
for name,ok,detail in results:
    report.append(f"{'PASS' if ok else 'FAIL'} | {name}" + (f' | {detail}' if detail and not ok else ''))
(ROOT/'V471_STATIC_VERIFICATION.txt').write_text('\n'.join(report)+'\n',encoding='utf-8')
print('\n'.join(report[:4]))
if passed!=total:
    for name,ok,detail in results:
        if not ok: print('FAIL:',name,detail)
    sys.exit(1)
