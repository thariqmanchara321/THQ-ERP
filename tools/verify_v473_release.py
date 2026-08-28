from pathlib import Path
import re, sys, hashlib

ROOT=Path(__file__).resolve().parents[1]
results=[]
def check(name, ok, detail=''):
    results.append((name,bool(ok),detail))
def text(rel): return (ROOT/rel).read_text(encoding='utf-8')

# Versions / shared release contract.
for app in ['admin_panel','client_app','pos_app']:
    s=text(f'apps/{app}/pubspec.yaml')
    check(f'{app} version 4.7.3+7', re.search(r'^version:\s*4\.7\.3\+7\s*$',s,re.M) is not None)
core=text('packages/erp_core/pubspec.yaml')
check('erp_core version 4.7.3', re.search(r'^version:\s*4\.7\.3\s*$',core,re.M) is not None)
rc=text('packages/erp_core/lib/src/release_contract.dart')
check('shared app version 4.7.3', "appVersion = '4.7.3'" in rc)
check('shared minimum migration 119', 'minimumMigration = 119' in rc)
check('shared release name', "releaseName = 'Live Operations Polish'" in rc)

# Migration 119.
m=text('backend/migrations/119_v473_live_operations_polish.sql')
for fn in [
    'pos_terminal_day_v473','pos_terminal_invoices_v473','pos_sales_today_v473',
    'pos_purchases_today_v473','pos_expenses_today_v473','pos_return_documents_today_v473'
]:
    check(f'{fn} defined', f'function public.{fn}' in m)
check('migration 119 registered', re.search(r"values\(\s*119\s*,\s*'4\.7\.3'",m,re.I) is not None)
check('backend contract app 4.7.3', "'minimum_app_version','4.7.3'" in m)
check('backend contract release name', "'release','Live Operations Polish'" in m)
check('Terminal Daily strips detailed shift rows', "coalesce(v->'shift_summary','{}'::jsonb)-'shifts'" in m)
check('historical held invoices not reported', 'if coalesce(p_day,v_business_today)=v_business_today then' in m and "'held_count',v_held" in m)
check('invoice history exact terminal', "o.device_id=p_device_id" in m and 'pos_terminal_invoices_v473' in m)
check('invoice history selected day', 's.sale_date=coalesce(p_day,current_date)' in m)
check('return lookup exact terminal/day', 'pos_return_documents_today_v473' in m and "o.device_id=p_device_id" in m and 's.sale_date=coalesce(p_day,current_date)' in m)
check('POS sales current day exact terminal', 'pos_sales_today_v473' in m and "o.device_id=p_device_id" in m and 's.sale_date=coalesce(p_day,current_date)' in m)
check('POS purchases current day exact terminal', 'pos_purchases_today_v473' in m and 'p.purchase_date=coalesce(p_day,current_date)' in m)
check('POS expenses current day exact terminal', 'pos_expenses_today_v473' in m and 'e.expense_date=coalesce(p_day,current_date)' in m)
check('sales today balance is return aware', "s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0)" in m)
check('purchase today balance is return aware', "p.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0)" in m)

# Upgrade mirror is exact.
primary=ROOT/'backend/migrations/119_v473_live_operations_polish.sql'
mirror=ROOT/'backend/upgrade_from_118/119_v473_live_operations_polish.sql'
check('upgrade 119 mirror exists',mirror.exists())
check('upgrade 119 mirror byte-identical',mirror.exists() and primary.read_bytes()==mirror.read_bytes())
post=text('backend/upgrade_from_118/V473_POST_UPGRADE_CHECK.sql')
for token in ['pos_terminal_day_v473','pos_terminal_invoices_v473','pos_sales_today_v473','pos_purchases_today_v473','pos_expenses_today_v473','pos_return_documents_today_v473']:
    check(f'post-check covers {token}',token in post)

# Explicit refresh across apps.
admin=text('apps/admin_panel/lib/screens/admin_dashboard.dart')
check('Admin dashboard is refreshable stateful', 'class AdminDashboard extends StatefulWidget' in admin and 'Future<void> _refresh()' in admin)
check('Admin visible Refresh control', "tooltip: 'Refresh Platform'" in admin and 'Icons.refresh' in admin)

for app in ['client_app','pos_app']:
    home_rel='apps/client_app/lib/screens/client_home_screen.dart' if app=='client_app' else 'apps/pos_app/lib/screens/pos_home_screen.dart'
    home=text(home_rel)
    svc=text(f'apps/{app}/lib/services/client_session_service.dart')
    install=text(f'apps/{app}/lib/services/device_installation_service.dart')
    check(f'{app} refresh function', 'Future<void> _refreshAll()' in home)
    check(f'{app} refreshes business object', 'getAvailableBusinesses()' in home and 'currentBusiness' in home)
    check(f'{app} refresh strict runtime', 'requireRuntime: true' in home and 'bool requireRuntime = false' in svc)
    check(f'{app} strict refresh does not silently stale', "Unable to refresh system/store configuration" in svc)
    check(f'{app} refresh runtime binding persisted', 'updateRuntimeBinding(' in svc and 'Future<void> updateRuntimeBinding' in install)
    check(f'{app} local store id updated after refresh', "_storage.write(key: 'flexi.location_id'" in install)
    check(f'{app} active content remounted on refresh', '_contentGeneration' in home and 'KeyedSubtree' in home)
    check(f'{app} refreshes navigation', '_loadNavigation' in home if app=='client_app' else '_loadMenu' in home)
    check(f'{app} refresh navigation is strict', '_loadNavigation(strict: true)' in home if app=='client_app' else '_loadMenu(strict: true)' in home)

client_home=text('apps/client_app/lib/screens/client_home_screen.dart')
check('Client desktop Refresh button', "label: const Text('Refresh')" in client_home)
check('Client mobile Refresh icon', "tooltip: 'Refresh THQ'" in client_home)
pos_home=text('apps/pos_app/lib/screens/pos_home_screen.dart')
check('POS sidebar Refresh action', "_action(\n                            Icons.refresh" in pos_home or "Icons.refresh" in pos_home and "'Refresh'" in pos_home)
check('POS Refresh protects unheld cart', 'Future<void> _requestRefresh()' in pos_home and 'Complete or Hold any current cart first' in pos_home)

# Hold / Resume full-page UX.
pos=text('apps/pos_app/lib/screens/pos_screen.dart')
check('Resume opens held workspace', '_workspace = _PosWorkspace.heldInvoices' in pos and 'Future<void> _resumeSale()' in pos)
check('Resume blocks non-empty cart', 'Hold or clear the current sale before resuming another invoice.' in pos)
check('Held page stays inside product workspace', '_PosWorkspace.heldInvoices => _heldSalesPage()' in pos and 'Expanded(flex: 7, child: _productWorkspace())' in pos)
check('Held invoices full page method', 'Widget _heldSalesPage()' in pos)
check('Held invoices responsive grid', 'GridView.builder(' in pos and 'Held Invoices (${_heldSales.length})' in pos)
check('Held cards show customer/item/time/total', all(t in pos for t in ["row['customer_name']","row['item_count']","row['created_at']","_money(total)"]))
check('Held page has back/products controls', "tooltip: 'Back to products'" in pos and "label: const Text('Products')" in pos)
check('Selecting held sale restores and closes workspace', 'onTap: () => _restoreHeldSale(row)' in pos and '_workspace = _PosWorkspace.products' in pos)
check('Hold uses center workspace not modal', '_workspace = _PosWorkspace.hold' in pos and 'Widget _holdSalePage()' in pos and 'showDialog<String>' not in pos[pos.find('void _openHoldEditor()'):pos.find('Future<void> _refreshHeldSales')])
check('legacy horizontal held strip removed', '_heldSalesStrip' not in pos and 'scrollDirection: Axis.horizontal' not in pos[pos.find('Widget _heldSalesPage()'):])

# Current-day exact-terminal POS services/screens.
sales=text('apps/pos_app/lib/services/sales_service.dart')
purchases=text('apps/pos_app/lib/services/purchase_service.dart')
expenses=text('apps/pos_app/lib/services/expense_service.dart')
returns=text('apps/pos_app/lib/services/return_search_service.dart')
check('POS sales uses exact-terminal v473 RPC', "'pos_sales_today_v473'" in sales and "'p_device_id': activation.deviceId" in sales and "'p_day': _dateOnly(DateTime.now())" in sales)
check('POS purchases uses exact-terminal v473 RPC', "'pos_purchases_today_v473'" in purchases and "'p_device_id': activation.deviceId" in purchases and "'p_day': _dateOnly(DateTime.now())" in purchases)
check('POS expenses uses exact-terminal v473 RPC', "'pos_expenses_today_v473'" in expenses and "'p_device_id': activation.deviceId" in expenses)
check('POS return lookup uses today v473 RPC', "'pos_return_documents_today_v473'" in returns and "'p_day': _date(DateTime.now())" in returns)

cashui=text('apps/pos_app/lib/screens/cashier_shift_screen.dart')
check('Cashier screen history is today only', 'final today = DateTime(now.year, now.month, now.day);' in cashui and 'from: today' in cashui and 'to: today' in cashui)
check('Cashier screen says Today shifts', 'Today\'s Shifts' in cashui or '"Today\'s Shifts"' in cashui)
check('Cashier history directs older records to Terminal Daily', 'Historical shifts are available in Terminal Daily.' in cashui)
check('POS Sales title today', 'Today’s Sales' in text('apps/pos_app/lib/screens/sales_screen.dart'))
check('POS Purchases title today', 'Today’s Purchases' in text('apps/pos_app/lib/screens/purchases_screen.dart'))
check('POS Returns explains history in Terminal Daily', 'Historical invoices are available in Terminal Daily.' in text('apps/pos_app/lib/screens/return_center_screen.dart'))

# Terminal Daily summary-first + invoice drill-down.
tsvc=text('apps/pos_app/lib/services/terminal_day_service.dart')
tui=text('apps/pos_app/lib/screens/terminal_day_screen.dart')
texport=text('apps/pos_app/lib/services/terminal_day_export_service.dart')
check('Terminal Daily uses v473 summary RPC', "'pos_terminal_day_v473'" in tsvc)
check('Terminal Daily uses v473 invoice search', "'pos_terminal_invoices_v473'" in tsvc)
check('Terminal Daily read-only summary wording', 'Simple read-only summary for this POS.' in tui)
check('Terminal Daily date picker historical', 'showDatePicker' in tui and 'lastDate: DateTime(now.year, now.month, now.day)' in tui)
check('Terminal Daily previous/next controls', 'Previous day' in tui and 'Next day' in tui)
check('Terminal Daily summary sections', all(x in tui for x in ['Daily Summary','Payments','Other Activity','Cashier Shift Summary']))
check('Terminal Daily invoice drilldown hidden by default', 'bool _showInvoices = false;' in tui and "'View Invoices'" in tui)
check('Terminal Daily invoice search prompt', 'Invoice number / sale number / customer' in tui)
check('Terminal Daily opens SaleDetailScreen', 'SaleDetailScreen(session: widget.session, saleId: id)' in tui)
check('Terminal Daily refreshes summary after invoice detail', 'if (mounted) await _load();' in tui)
check('Historical held only today', "if (_isToday)\n            _metric('Held Now'" in tui)
check('Terminal Daily has no shift mutation controls', '_closeShift' not in tui and '_openShift' not in tui and 'End Shift' not in tui)
check('Terminal Daily export is summary-only no shift detail table', 'Shift Times' not in texport and "excel['Shift Summary']" not in texport and 'shift_number' not in texport)

# Tests reflect release contract.
for rel in ['apps/pos_app/test/widget_test.dart','apps/client_app/test/widget_test.dart','packages/erp_core/test/erp_core_test.dart']:
    s=text(rel)
    check(f'{rel} app version test 4.7.3', "'4.7.3'" in s)
    check(f'{rel} migration test 119', '119' in s)

# Required release docs.
for rel in ['README_V473_RELEASE.md','CHANGELOG_V473.md','docs/V473_RELEASE_ACCEPTANCE.md','backend/upgrade_from_118/V473_POST_UPGRADE_CHECK.sql']:
    check(f'release artifact exists {rel}',(ROOT/rel).exists())

# Relative Dart imports resolve.
for p in list(ROOT.glob('apps/*/lib/**/*.dart'))+list(ROOT.glob('packages/erp_core/lib/**/*.dart')):
    src=p.read_text(encoding='utf-8')
    for imp in re.findall(r"import\s+'([^']+)'",src):
        if imp.startswith('.'):
            target=(p.parent/imp).resolve()
            check(f'import resolves {p.relative_to(ROOT)} -> {imp}',target.exists(),str(target))

# Balanced delimiters with lexer that ignores strings/comments.
def balanced(path):
    src=path.read_text(encoding='utf-8')
    stack=[]; pairs={')':'(',']':'[','}':'{'}
    i=0; state='code'; quote=''; triple=False
    while i<len(src):
        c=src[i]; pair=src[i:i+2]
        if state=='code':
            if pair=='//': state='line'; i+=2; continue
            if pair=='/*': state='block'; i+=2; continue
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
            if pair=='*/': state='code'; i+=2
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

# SQL structural checks.
tags=re.findall(r'\$[A-Za-z_0-9]*\$',m)
counts={tag:tags.count(tag) for tag in set(tags)}
check('migration 119 SQL dollar quotes paired',all(v%2==0 for v in counts.values()),str(counts))
check('migration 119 transaction boundaries',re.search(r'^begin\s*;',m,re.I|re.M) is not None and re.search(r'^commit\s*;',m,re.I|re.M) is not None)
check('migration 119 no invalid expenses.view permission', "expenses.view" not in m)

# Package cleanliness checks now; generated release manifests themselves are allowed.
banned=[]
for p in ROOT.rglob('*'):
    if any(part in {'.git','node_modules','.dart_tool','build'} for part in p.parts):
        banned.append(str(p.relative_to(ROOT)))
check('release tree excludes generated/VCS clutter',not banned,', '.join(banned[:5]))

passed=sum(ok for _,ok,_ in results); total=len(results)
report=['THQ ERP V4.7.3 STATIC RELEASE VERIFICATION',f'Passed: {passed}/{total}','']
for name,ok,detail in results:
    report.append(f"{'PASS' if ok else 'FAIL'} | {name}" + (f' | {detail}' if detail and not ok else ''))
(ROOT/'V473_STATIC_VERIFICATION.txt').write_text('\n'.join(report)+'\n',encoding='utf-8')
print('\n'.join(report[:3]))
if passed!=total:
    for name,ok,detail in results:
        if not ok: print('FAIL:',name,detail)
    sys.exit(1)
