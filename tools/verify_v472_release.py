from pathlib import Path
import re, sys

ROOT=Path(__file__).resolve().parents[1]
results=[]
def check(name, ok, detail=''):
    results.append((name,bool(ok),detail))
def text(rel): return (ROOT/rel).read_text(encoding='utf-8')

# Release versions/contracts.
for app in ['admin_panel','client_app','pos_app']:
    s=text(f'apps/{app}/pubspec.yaml')
    check(f'{app} version 4.7.2+5', re.search(r'^version:\s*4\.7\.2\+5\s*$',s,re.M) is not None)
core=text('packages/erp_core/pubspec.yaml')
check('erp_core version 4.7.2', re.search(r'^version:\s*4\.7\.2\s*$',core,re.M) is not None)
rc=text('packages/erp_core/lib/src/release_contract.dart')
check('shared app version 4.7.2', "appVersion = '4.7.2'" in rc)
check('shared minimum migration 118', 'minimumMigration = 118' in rc)
check('shared release name', "releaseName = 'Terminal Operations Redesign'" in rc)

# Migration 118 architecture.
m=text('backend/migrations/118_v472_terminal_operations_redesign.sql')
for fn in [
    'cashier_shift_open_v472','cashier_shift_close_v472','cashier_shift_edit_v472',
    'cashier_shift_current_v472','cashier_shift_history_v472','cashier_shift_edits_v472',
    'pos_terminal_day_v472'
]:
    check(f'{fn} defined', f'function public.{fn}' in m)
check('shift edit audit table', 'create table if not exists public.cashier_shift_edits' in m)
check('shift edits require reason', "Edit reason is required" in m)
check('closed shift manager permission', "pos.shift_manage" in m and 'Closed shifts' in m)
check('opening and closing timestamps editable', 'p_opened_at timestamptz' in m and 'p_closed_at timestamptz' in m)
check('opening/closing amounts editable', 'p_opening_cash numeric' in m and 'p_declared_cash numeric' in m)
check('shift overlap protection', 'v472_shift_period_conflicts' in m and 'overlaps another shift' in m)
check('cashier module disable guard', 'trg_v472_guard_operational_module_change' in m and 'End the open Cashier Shift before deactivating' in m)
check('terminal daily backend activation check', 'v472_terminal_day_module_enabled' in m and 'Terminal Daily is disabled for this POS' in m)
check('terminal daily removes legacy detailed payloads', "v:=coalesce(v,'{}'::jsonb)-array['shift','invoices','returns','customer_receipt_rows']" in m)
check('terminal daily read-only wording', 'Terminal Daily: pure report' in m and 'never opens/closes/edits shifts' in m)
check('module independence', "('cashier_shifts','pos'),('terminal_day','pos')" in m and "depends_on_module_key in('cashier_shifts','terminal_day')" in m)
check('terminal summary includes purchases', "'purchase_count'" in m and "'purchases'" in m)
check('terminal summary includes receipts', "'customer_receipts_cash'" in m and "'customer_receipts_other'" in m)
check('terminal summary includes cash in/out', "'cash_in'" in m and "'cash_out'" in m)
check('terminal summary includes shift summary read-only', "'shift_summary'" in m and "'shifts',v_shift_rows" in m)
check('migration 118 registered', re.search(r"values\(\s*118\s*,\s*'4\.7\.2'",m,re.I) is not None)
check('backend contract minimum app 4.7.2', "'minimum_app_version','4.7.2'" in m)
check('no ambiguous id in shift edit history lookup', 'where s.id=p_shift_id and s.tenant_id=p_tenant_id' in m)

# POS app integration.
svc=text('apps/pos_app/lib/services/cashier_shift_service.dart')
for rpc in ['cashier_shift_current_v472','cashier_shift_history_v472','cashier_shift_open_v472','cashier_shift_close_v472','cashier_shift_edit_v472','cashier_shift_edits_v472']:
    check(f'POS shift service uses {rpc}', rpc in svc)
check('shift service sends start time', "'p_opened_at': openedAt.toIso8601String()" in svc)
check('shift service sends end time', "'p_closed_at': closedAt.toIso8601String()" in svc)

cashui=text('apps/pos_app/lib/screens/cashier_shift_screen.dart')
for token in ['Start Cashier Shift','Shift start time','Opening cash','End Cashier Shift','Shift end time','Closing cash counted','Recent Shifts','Reason for correction']:
    check(f'Cashier UI: {token}', token in cashui)
check('cashier UI can edit closed shifts', '_editShift' in cashui and '_canManageClosed' in cashui)
check('cashier UI records automatic now defaults', 'var startAt = DateTime.now();' in cashui and 'var endAt = DateTime.now();' in cashui)
check('cashier UI backup moved to shift close', '_autoBackupAfterShiftClose' in cashui)

terminal_svc=text('apps/pos_app/lib/services/terminal_day_service.dart')
check('Terminal Daily service v472', 'pos_terminal_day_v472' in terminal_svc and 'pos_terminal_day_v471' not in terminal_svc)
terminal_ui=text('apps/pos_app/lib/screens/terminal_day_screen.dart')
check('Terminal Daily no shift service import', 'cashier_shift_service.dart' not in terminal_ui)
check('Terminal Daily has no shift close action', '_closeShift' not in terminal_ui and 'Day Close' not in terminal_ui)
check('Terminal Daily explicitly read-only', 'Read-only daily summary' in terminal_ui)
check('Terminal Daily summary sections', all(x in terminal_ui for x in ['Sales Summary','Collections & Payments','Other Terminal Activity','Customer Receipt Breakdown','Cashier Shift Summary']))
terminal_export=text('apps/pos_app/lib/services/terminal_day_export_service.dart')
check('Terminal Daily export read-only', 'Read-only report' in terminal_export)
check('Terminal Daily export summary only', "excel['Invoices']" not in terminal_export and "excel['Returns']" not in terminal_export and "excel['Customer Receipts']" not in terminal_export)

home=text('apps/pos_app/lib/screens/pos_home_screen.dart')
check('Cashier page independently gated', "if (_allowed('cashier_shifts'))" in home)
check('Terminal Daily independently gated', "if (_allowed('terminal_day'))" in home and "_allowed('terminal_day') || _allowed('cashier_shifts')" not in home)
pos=text('apps/pos_app/lib/screens/pos_screen.dart')
check('billing requires shift only when cashier module enabled', "device.allowedModules.contains('cashier_shifts')" in pos and "widget.session.hasModule('cashier_shifts')" in pos)
check('billing error points to Cashier Shift', 'Start a shift from Cashier Shift before billing' in pos)

admin=text('apps/admin_panel/lib/screens/business_locations_devices_screen.dart')
check('new POS no longer forces cashier/day', "final selectedModules = <String>{'sales'};" in admin)
check('Admin explains independent switches', 'Cashier Shift and Terminal Daily are independent' in admin)
check('Admin module list has both', "'cashier_shifts'" in admin and "'terminal_day'" in admin)
settings=text('apps/pos_app/lib/screens/pos_settings_screen.dart')
check('backup wording follows shift close', 'Backup automatically after Shift Close' in settings and 'day-close screen writes' not in settings)

# Tests reflect new contract.
for rel in ['apps/pos_app/test/widget_test.dart','apps/client_app/test/widget_test.dart','packages/erp_core/test/erp_core_test.dart']:
    s=text(rel)
    check(f'{rel} app version test 4.7.2', "'4.7.2'" in s)
    check(f'{rel} migration test 118', '118' in s)

# Relative Dart imports resolve.
for p in list(ROOT.glob('apps/*/lib/**/*.dart'))+list(ROOT.glob('packages/erp_core/lib/**/*.dart')):
    src=p.read_text(encoding='utf-8')
    for imp in re.findall(r"import\s+'([^']+)'",src):
        if imp.startswith('.'):
            target=(p.parent/imp).resolve()
            check(f'import resolves {p.relative_to(ROOT)} -> {imp}',target.exists(),str(target))

# Balanced delimiters with a small lexer that ignores strings/comments.
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

# SQL dollar-quote and transaction structural checks for migration 118.
tags=re.findall(r'\$[A-Za-z_0-9]*\$',m)
counts={tag:tags.count(tag) for tag in set(tags)}
check('migration 118 SQL dollar quotes paired',all(v%2==0 for v in counts.values()),str(counts))
check('migration 118 transaction boundaries',re.search(r'^begin\s*;',m,re.I|re.M) is not None and re.search(r'^commit\s*;',m,re.I|re.M) is not None)

passed=sum(ok for _,ok,_ in results); total=len(results)
report=['THQ ERP V4.7.2 STATIC RELEASE VERIFICATION',f'Passed: {passed}/{total}','']
for name,ok,detail in results:
    report.append(f"{'PASS' if ok else 'FAIL'} | {name}" + (f' | {detail}' if detail and not ok else ''))
(ROOT/'V472_STATIC_VERIFICATION.txt').write_text('\n'.join(report)+'\n',encoding='utf-8')
print('\n'.join(report[:3]))
if passed!=total:
    for name,ok,detail in results:
        if not ok: print('FAIL:',name,detail)
    sys.exit(1)
