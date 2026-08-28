from pathlib import Path
import re, sys

ROOT=Path(__file__).resolve().parents[1]
results=[]
def check(name, ok, detail=''):
    results.append((name,bool(ok),detail))
def text(rel): return (ROOT/rel).read_text(encoding='utf-8')

# Versions / shared release contract.
for app in ['admin_panel','client_app','pos_app']:
    s=text(f'apps/{app}/pubspec.yaml')
    check(f'{app} version 4.8.1+9', re.search(r'^version:\s*4\.8\.1\+9\s*$',s,re.M) is not None)
core=text('packages/erp_core/pubspec.yaml')
check('erp_core version 4.8.1', re.search(r'^version:\s*4\.8\.1\s*$',core,re.M) is not None)
rc=text('packages/erp_core/lib/src/release_contract.dart')
for token in ["appVersion = '4.8.1'",'minimumMigration = 129',"releaseName = 'Inventory & Unit Engine'","apiVersion = 'v1'"]:
    check(f'release contract {token}', token in rc)
unit_core=text('packages/erp_core/lib/src/inventory_units.dart')
for token in ['class InventoryUnit','class ProductUnitOption','conversionToBase','quantityStep','acceptsQuantity','salePriceFor','purchaseCostFor']:
    check(f'erp_core unit primitive {token}', token in unit_core)
check('erp_core exports unit primitives', "export 'src/inventory_units.dart';" in text('packages/erp_core/lib/erp_core.dart'))
check('fraction format uses int precision', 'decimalPlaces.clamp(0, 6).toInt()' in unit_core)

# Migrations 125-129 and exact upgrade mirrors.
for n in range(125,130):
    matches=list((ROOT/'backend/migrations').glob(f'{n}_v481_*.sql'))
    check(f'migration {n} exists',len(matches)==1,str(matches))
    if matches:
        m=matches[0]; s=m.read_text(encoding='utf-8')
        check(f'migration {n} registered', re.search(rf"values\(\s*{n}\s*,\s*'4\.8\.1'",s,re.I) is not None)
        mirror=ROOT/'backend/upgrade_from_124'/m.name
        check(f'migration {n} upgrade mirror',mirror.exists() and mirror.read_bytes()==m.read_bytes())
        tags=re.findall(r'\$[A-Za-z_0-9]*\$',s)
        counts={tag:tags.count(tag) for tag in set(tags)}
        check(f'migration {n} dollar quotes paired',all(v%2==0 for v in counts.values()),str(counts))
        check(f'migration {n} transaction boundary',re.search(r'^begin\s*;',s,re.I|re.M) is not None and re.search(r'^commit\s*;',s,re.I|re.M) is not None)

m125=text('backend/migrations/125_v481_units_location_types.sql')
for token in ['inventory_units_v481','product_units_v481','v481_seed_units','inventory_units_list_v481','inventory_unit_save_v481']:
    check(f'units migration {token}',token in m125)
for code in ['PCS','M','KG','L','BOX','CTN','COIL','ROLL','BDL','SET','PAIR','DOZ']:
    check(f'standard unit {code}',f"'{code}'" in m125)
for typ in ['store','warehouse','production','office','scrap']:
    check(f'location type {typ}',f"'{typ}'" in m125)
check('product unit one base unique','ux_product_units_v481_base' in m125 and 'where is_base and active' in m125)

m126=text('backend/migrations/126_v481_inventory_movement_ledger.sql')
for col in ['base_quantity_delta','display_quantity','unit_id','unit_code','conversion_to_base','balance_before','balance_after','source_line_id','movement_group','metadata']:
    check(f'movement ledger column {col}',col in m126)
for typ in ['production_consumption','production_output','wastage','scrap','rework_in','rework_out','grn','delivery']:
    check(f'future movement type {typ}',f"'{typ}'" in m126)
check('stock apply records before after','balance_before,balance_after' in m126 and 'v_before,v_after' in m126)
check('stock apply preserves locked availability','for update' in m126.lower() and 'v_available' in m126)
check('movement history qualified columns','select m.id,m.location_id,l.name,m.variant_id' in m126)

m127=text('backend/migrations/127_v481_product_unit_api.sql')
for token in ['inventory_product_units_v481','inventory_product_units_save_v481','inventory_create_product_v481','inventory_list_products_v481','inventory_location_movements_v481']:
    check(f'product unit API {token}',token in m127)
check('base unit change blocked after history','Base inventory unit cannot be changed after stock/history exists' in m127)
check('only one default sale unit','Only one default sale unit is allowed' in m127)
check('only one default purchase unit','Only one default purchase unit is allowed' in m127)
check('unit list exposes sale/purchase arrays',"'sale_units'" in m127 and "'purchase_units'" in m127 and "'base_unit'" in m127)

m128=text('backend/migrations/128_v481_unit_transactions.sql')
for col in ['entered_unit_id','entered_unit_code','entered_quantity','conversion_to_base','entered_unit_price','entered_unit_cost']:
    check(f'transaction metadata {col}',col in m128)
for fn in ['sales_create_v481','purchases_create_v481','sales_return_create_v481','purchase_return_create_v481']:
    check(f'unit transaction RPC {fn}',fn in m128)
check('sale normalizes qty and unit price','v_qty*v_factor' in m128 and "'unit_price'" in m128 and 'v_price/v_factor' in m128)
check('purchase normalizes qty and unit cost',"'unit_cost'" in m128 and "'_entered_unit_cost'" in m128)
check('backend enforces fractional rule','only allows whole quantities' in m128)
check('backend enforces quantity step','must use increments of' in m128)
check('returns restore entered unit metadata','update public.sales_return_items' in m128 and 'update public.purchase_return_items' in m128)
check('returns convert entered to base',"jsonb_build_object('quantity',v_entered*v_factor" in m128)
check('unit-aware transaction forbids ambiguous duplicate variant','A product variant can appear only once per unit-aware transaction' in m128)

m129=text('backend/migrations/129_v481_release_contract.sql')
for token in ['thq_v481_release_verify','minimum_app_version\',\'4.8.1','migration_no\',129','inventory-movements','product-units',"'units'"]:
    check(f'release migration {token}',token in m129)
check('release verifies movement columns',"column_name='base_quantity_delta'" in m129 and "column_name='balance_after'" in m129)
check('release API contract keeps hardened financial path',"'core_financial_posting','direct_hardened_rpc'" in m129)

# App runtime versions.
for rel in ['apps/client_app/lib/services/device_heartbeat_service.dart','apps/client_app/lib/services/device_installation_service.dart','apps/pos_app/lib/services/device_heartbeat_service.dart','apps/pos_app/lib/services/device_installation_service.dart']:
    check(f'{rel} reports 4.8.1',"'4.8.1'" in text(rel))
for rel in ['apps/client_app/lib/services/backend_compatibility_service.dart','apps/pos_app/lib/services/backend_compatibility_service.dart']:
    check(f'{rel} requires migration 129','THQ ERP 4.8.1 requires migration' in text(rel))

# Service wiring.
for base in ['apps/client_app','apps/pos_app']:
    inv=text(f'{base}/lib/services/inventory_service.dart')
    sales=text(f'{base}/lib/services/sales_service.dart')
    purchase=text(f'{base}/lib/services/purchase_service.dart')
    check(f'{base} product list v481','inventory_list_products_v481' in inv)
    check(f'{base} sales v481','sales_create_v481' in sales)
    check(f'{base} sale returns v481','sales_return_create_v481' in sales)
    check(f'{base} purchases v481','purchases_create_v481' in purchase)
    check(f'{base} purchase returns v481','purchase_return_create_v481' in purchase)

# Client UX.
units_screen=text('apps/client_app/lib/screens/product_units_screen.dart')
for token in ['Base inventory unit','Additional purchase / sale units','Cut / Partial Quantity','New Custom Unit','Save Unit Configuration']:
    check(f'Client unit UI {token}',token in units_screen)
client_products=text('apps/client_app/lib/screens/inventory_products_screen.dart')
check('Client exposes movement ledger','InventoryMovementHistoryScreen' in client_products and 'Movement Ledger' in client_products)
client_detail=text('apps/client_app/lib/screens/product_detail_screen.dart')
check('Client exposes units from product detail','ProductUnitsScreen' in client_detail and 'Manage Units' in client_detail)
client_sales=text('apps/client_app/lib/screens/sales_screen.dart')
check('Client sale unit selector',"labelText: 'Sale Unit'" in client_sales and 'ProductUnitOption' in client_sales)
check('Client sale validates base stock','selectedUnit?.conversionToBase' in client_sales)
check('Client cutting charge supported','cuttingChargeApplied' in client_sales and 'Add cutting charge' in client_sales and '_cuttingCharges' in client_sales)
client_purchases=text('apps/client_app/lib/screens/purchases_screen.dart')
check('Client purchase unit selector',"labelText: 'Purchase Unit'" in client_purchases and 'ProductUnitOption' in client_purchases)

# POS UX / safety.
pos=text('apps/pos_app/lib/screens/pos_screen.dart')
for token in ['_PosWorkspace.quantity','Widget _quantityEditorPage()','Sale Unit','Base stock impact','cuttingChargeApplied']:
    check(f'POS unit workspace {token}',token in pos)
check('POS stock checks base quantity','next * line.conversionToBase' in pos and 'parsed * line.conversionToBase' in pos)
check('POS hold preserves unit','unit_id' in pos and 'cutting_charge_applied' in pos)
check('POS totals cutting charge once','double get _cuttingCharges' in pos and 'additionalCharges: _cuttingCharges' in pos)
check('POS existing Hold workspace retained','_PosWorkspace.hold' in pos and '_PosWorkspace.heldInvoices' in pos)

# Location UI options.
for rel in ['apps/admin_panel/lib/screens/business_locations_devices_screen.dart','apps/client_app/lib/screens/locations_screen.dart']:
    s=text(rel)
    for typ in ['production','office','scrap']:
        check(f'{rel} location option {typ}',f"'{typ}'" in s)

# THQ API mirrors / resources.
edge_b=ROOT/'backend/functions/thq-api/index.ts'; edge_s=ROOT/'supabase/functions/thq-api/index.ts'
check('THQ API backend function exists',edge_b.exists())
check('THQ API supabase mirror exists',edge_s.exists())
check('THQ API mirrors identical',edge_b.exists() and edge_s.exists() and edge_b.read_bytes()==edge_s.read_bytes())
if edge_b.exists():
    e=edge_b.read_text(encoding='utf-8')
    for resource in ['units','product-units','inventory-movements']:
        check(f'THQ API routes {resource}',f"case '{resource}'" in e)
    check('THQ API normal path not service role','SUPABASE_SERVICE_ROLE_KEY' not in e)

# Tests updated.
for rel in ['apps/client_app/test/widget_test.dart','apps/pos_app/test/widget_test.dart','packages/erp_core/test/erp_core_test.dart']:
    s=text(rel); check(f'{rel} 4.8.1 test',"'4.8.1'" in s); check(f'{rel} migration 129','129' in s)

# Release artifacts.
for rel in ['README_V481_RELEASE.md','CHANGELOG_V481.md','docs/V481_ARCHITECTURE.md','docs/V481_RELEASE_ACCEPTANCE.md','docs/V481_DEPLOYMENT.md','backend/THQ_ERP_V481_UPGRADE_FROM_124.sql','backend/upgrade_from_124/V481_POST_UPGRADE_CHECK.sql','backend/upgrade_from_124/README_DEPLOY_V481.md','tools/validate_v481_windows.ps1']:
    check(f'release artifact {rel}',(ROOT/rel).exists())

# Combined bundle contains all five migrations in correct order.
bundle=text('backend/THQ_ERP_V481_UPGRADE_FROM_124.sql')
positions=[bundle.find(f'values({n},\'4.8.1\'') for n in range(125,130)]
check('combined migration bundle has 125-129',all(x>=0 for x in positions),str(positions))
check('combined migration bundle ordered',positions==sorted(positions),str(positions))

# Relative Dart imports resolve.
for p in list(ROOT.glob('apps/*/lib/**/*.dart'))+list(ROOT.glob('packages/erp_core/lib/**/*.dart')):
    src=p.read_text(encoding='utf-8',errors='ignore')
    for imp in re.findall(r"import\s+'([^']+)'",src):
        if imp.startswith('.'):
            target=(p.parent/imp).resolve()
            check(f'import resolves {p.relative_to(ROOT)} -> {imp}',target.exists(),str(target))

# Balanced delimiters ignoring comments/strings.
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

# Compile-risk heuristic: const InputDecoration cannot contain runtime private fields.
for p in list(ROOT.glob('apps/*/lib/**/*.dart')):
    src=p.read_text(encoding='utf-8',errors='ignore')
    for m in re.finditer(r'const\s+InputDecoration\((.*?)\)',src,re.S):
        block=m.group(1)
        bad=re.search(r'\b_[A-Za-z]\w*\b',block) is not None or '${' in block
        check(f'const decoration static {p.relative_to(ROOT)}:{src[:m.start()].count(chr(10))+1}',not bad,' '.join(block.split())[:160])

# Source cleanliness.
banned=[]
for p in ROOT.rglob('*'):
    if any(part in {'.git','node_modules','.dart_tool','.gradle','build','.idea','.vscode'} for part in p.parts): banned.append(str(p.relative_to(ROOT)))
check('release tree excludes generated/VCS clutter',not banned,', '.join(banned[:10]))

passed=sum(ok for _,ok,_ in results); total=len(results)
report=['THQ ERP V4.8.1 STATIC RELEASE VERIFICATION',f'Passed: {passed}/{total}','']
for name,ok,detail in results:
    report.append(f"{'PASS' if ok else 'FAIL'} | {name}" + (f' | {detail}' if detail and not ok else ''))
(ROOT/'V481_STATIC_VERIFICATION.txt').write_text('\n'.join(report)+'\n',encoding='utf-8')
print('\n'.join(report[:3]))
if passed!=total:
    for name,ok,detail in results:
        if not ok: print('FAIL:',name,detail)
    sys.exit(1)
