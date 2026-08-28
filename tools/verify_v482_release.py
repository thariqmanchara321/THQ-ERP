from pathlib import Path
import re, sys

ROOT=Path(__file__).resolve().parents[1]
results=[]
def check(name, ok, detail=''):
    results.append((name,bool(ok),detail))
def text(rel): return (ROOT/rel).read_text(encoding='utf-8')

# Versions / release contract
for app in ['admin_panel','client_app','pos_app']:
    s=text(f'apps/{app}/pubspec.yaml')
    check(f'{app} version 4.8.2+10', re.search(r'^version:\s*4\.8\.2\+10\s*$',s,re.M) is not None)
core=text('packages/erp_core/pubspec.yaml')
check('erp_core version 4.8.2', re.search(r'^version:\s*4\.8\.2\s*$',core,re.M) is not None)
rc=text('packages/erp_core/lib/src/release_contract.dart')
for token in ["appVersion = '4.8.2'",'minimumMigration = 134',"releaseName = 'Pricing & Product Identification'","apiVersion = 'v1'"]:
    check(f'release contract {token}', token in rc)

# Async BuildContext release gate
for app in ['admin_panel','client_app','pos_app']:
    opts=text(f'apps/{app}/analysis_options.yaml')
    check(f'{app} async context lint explicitly enabled','use_build_context_synchronously: true' in opts)
for p in ROOT.glob('apps/*/lib/**/*.dart'):
    src=p.read_text(encoding='utf-8',errors='ignore')
    check(f'no async context lint suppression {p.relative_to(ROOT)}','ignore: use_build_context_synchronously' not in src and 'ignore_for_file: use_build_context_synchronously' not in src)
client_home=text('apps/client_app/lib/screens/client_home_screen.dart')
pos_home=text('apps/pos_app/lib/screens/pos_home_screen.dart')
check('Client refresh mounted guard before success context',"if (!mounted) return;\n      ScaffoldMessenger.of(context)" in client_home)
check('POS refresh mounted guard before success context',"if (!mounted) return;\n      ScaffoldMessenger.of(context)" in pos_home)
validator=text('tools/validate_v482_windows.ps1')
check('Windows validator fatal infos','--fatal-infos' in validator)
check('Windows validator fatal warnings','--fatal-warnings' in validator)

# Shared pricing primitives
pricing=text('packages/erp_core/lib/src/pricing.dart')
for token in ['class PriceResolution','unitPrice','sourceLabel','class ProductIdentifier','isPrimary','generated']:
    check(f'erp_core pricing primitive {token}',token in pricing)
check('erp_core exports pricing',"export 'src/pricing.dart';" in text('packages/erp_core/lib/erp_core.dart'))

# Migrations 130-134 and upgrade mirrors
for n in range(130,135):
    matches=list((ROOT/'backend/migrations').glob(f'{n}_v482_*.sql'))
    check(f'migration {n} exists',len(matches)==1,str(matches))
    if matches:
        m=matches[0]; s=m.read_text(encoding='utf-8')
        check(f'migration {n} registered', re.search(rf"values\(\s*{n}\s*,\s*'4\.8\.2'",s,re.I) is not None)
        mirror=ROOT/'backend/upgrade_from_129'/m.name
        check(f'migration {n} upgrade mirror',mirror.exists() and mirror.read_bytes()==m.read_bytes())
        tags=re.findall(r'\$[A-Za-z_0-9]*\$',s)
        counts={tag:tags.count(tag) for tag in set(tags)}
        check(f'migration {n} dollar quotes paired',all(v%2==0 for v in counts.values()),str(counts))
        check(f'migration {n} transaction boundary',re.search(r'^begin\s*;',s,re.I|re.M) is not None and re.search(r'^commit\s*;',s,re.I|re.M) is not None)

m130=text('backend/migrations/130_v482_pricing_engine.sql')
for token in ['price_lists_v482','price_list_items_v482','customer_pricing_profiles_v482','customer_prices_v482','pricing_resolve_v482_internal','pricing_resolve_v482','customers_list_v482']:
    check(f'pricing migration {token}',token in m130)
for code in ['RETAIL','WHOLESALE','DEALER','CONTRACTOR']:
    check(f'default price list {code}',f"'{code}'" in m130)
check('pricing customer precedence first','customer_prices_v482 cp' in m130 and m130.find('customer_prices_v482 cp') < m130.find('price_list_items_v482 pli'))
check('pricing quantity breaks descending','cp.min_quantity<=v_qty order by cp.min_quantity desc' in m130 and 'pli.min_quantity<=v_qty order by pli.min_quantity desc' in m130)
check('pricing fallback includes unit/store/product',"'unit_price'" in m130 and "'location_price'" in m130 and "'product_price'" in m130)
check('pricing writes bump sync','thq_sync_bump_v480' in m130)

m131=text('backend/migrations/131_v482_product_identification.sql')
for token in ['product_identifiers_v482','product_identifier_sequences_v482','product_identifier_save_v482','product_identifier_generate_v482','product_identifier_archive_v482','inventory_product_lookup_v482','inventory_list_products_v482','v482_sync_legacy_identifiers']:
    check(f'identification migration {token}',token in m131)
for typ in ['barcode','qr','manufacturer','supplier','internal','alternate_sku']:
    check(f'identifier type {typ}',f"'{typ}'" in m131)
check('active code unique per tenant','ux_product_identifiers_v482_code' in m131 and 'where active' in m131)
check('generated EAN check digit','v482_ean13_check_digit' in m131 and "'28'||lpad" in m131)
check('generated QR namespace',"'THQ:PRODUCT:'" in m131)
check('SKU collision guard','v482_product_sku_guard' in m131)
check('legacy barcode/part fields synchronized','v482_sync_legacy_identifiers' in m131 and 'set barcode=v_barcode,part_number=v_part' in m131)
check('lookup has legacy compatibility fallback','Compatibility fallback for historical installations' in m131)

m132=text('backend/migrations/132_v482_label_printing.sql')
for token in ['label_templates_v482','THERMAL_50X30','THERMAL_38X25','A4_3COL','QR_50X30','label_template_save_v482']:
    check(f'label migration {token}',token in m132)

m133=text('backend/migrations/133_v482_authoritative_sale_pricing.sql')
for token in ['pricing_source','price_list_id','pricing_metadata','v482_price_sale_items','sales_create_v482','sales_get_detail_v482']:
    check(f'authoritative pricing {token}',token in m133)
check('server resolves each sale line','private.pricing_resolve_v482_internal' in m133)
check('priced items passed into proven v481 sale','sales_create_v481' in m133 and 'v_priced' in m133)

m134=text('backend/migrations/134_v482_release_contract.sql')
for token in ['thq_v482_release_verify',"'minimum_app_version','4.8.2'","'migration_no',134","'pricing'","'product-identifiers'","'label-templates'","'authoritative_sale_pricing','pricing_resolve_v482'"]:
    check(f'release migration {token}',token in m134)
check('release verifies sales v482','sales_create_v482' in m134 and 'sales_get_detail_v482' in m134)
check('release verifies identifier sync helper','v482_sync_legacy_identifiers' in m134)

# Runtime versions / backend compatibility
for rel in ['apps/client_app/lib/services/device_heartbeat_service.dart','apps/client_app/lib/services/device_installation_service.dart','apps/pos_app/lib/services/device_heartbeat_service.dart','apps/pos_app/lib/services/device_installation_service.dart']:
    check(f'{rel} reports 4.8.2',"'4.8.2'" in text(rel))
for rel in ['apps/client_app/lib/services/backend_compatibility_service.dart','apps/pos_app/lib/services/backend_compatibility_service.dart']:
    check(f'{rel} requires v4.8.2 release contract','THQ ERP 4.8.2 requires migration' in text(rel) and 'ThqReleaseContract.minimumMigration' in text(rel))

# App service wiring
for base in ['apps/client_app','apps/pos_app']:
    inv=text(f'{base}/lib/services/inventory_service.dart')
    sales=text(f'{base}/lib/services/sales_service.dart')
    pricing_s=text(f'{base}/lib/services/pricing_service.dart')
    ident=text(f'{base}/lib/services/product_identification_service.dart')
    cust=text(f'{base}/lib/services/customer_service.dart')
    check(f'{base} inventory list v482','inventory_list_products_v482' in inv)
    check(f'{base} sales v482','sales_create_v482' in sales and 'sales_get_detail_v482' in sales)
    check(f'{base} pricing resolver','pricing_resolve_v482' in pricing_s)
    check(f'{base} identifier lookup','inventory_product_lookup_v482' in ident)
    check(f'{base} customer price-list feed','customers_list_v482' in cust)

# Client UX
pricing_ui=text('apps/client_app/lib/screens/pricing_screen.dart')
for token in ['Price Lists','Customer Pricing','Minimum Quantity','Unit Price','Assigned Price List','Specific Price']:
    check(f'Client pricing UI {token}',token in pricing_ui)
client_home=text('apps/client_app/lib/screens/client_home_screen.dart')
check('Client pricing navigation','PricingScreen(session: session)' in client_home and "'pricing'" in client_home)
ident_ui=text('apps/client_app/lib/screens/product_identifiers_screen.dart')
for token in ['Codes & Labels','Generate Barcode','Generate QR','Manufacturer Code','Supplier Code','Alternate SKU','Label Template','Print label']:
    check(f'Client identifier UI {token}',token in ident_ui)
product_detail=text('apps/client_app/lib/screens/product_detail_screen.dart')
check('Product detail exposes identifiers','ProductIdentifiersScreen' in product_detail and 'Codes, Barcode & Labels' in product_detail)
label_service=text('apps/client_app/lib/services/label_printing_service.dart')
check('Label service uses pdf barcode widget','pw.BarcodeWidget' in label_service and 'Printing.layoutPdf' in label_service)
check('Label service supports QR','pw.Barcode.qrCode()' in label_service)
client_sales=text('apps/client_app/lib/screens/sales_screen.dart')
check('Client sale pricing preview','_pricingService.resolve' in client_sales and 'pricingSource' in client_sales)
check('Client search uses multiple identifiers','searchCodes' in client_sales)
barcode=text('apps/client_app/lib/services/barcode_service.dart')
check('Client barcode lookup generalized','inventory_product_lookup_v482' in barcode)

# POS UX / pricing
pos=text('apps/pos_app/lib/screens/pos_screen.dart')
check('POS exact scan searches identifiers','product.identifiers.any' in pos)
check('POS product filtering searches all codes','product.searchCodes' in pos)
check('POS resolves line price','_pricing.resolve' in pos and '_resolveLinePrice' in pos)
check('POS reprices cart on customer change','_resolveAllPrices' in pos)
check('POS shows pricing source','pricingSource' in pos)
check('POS existing hold workspace retained','_PosWorkspace.hold' in pos and '_PosWorkspace.heldInvoices' in pos)

# THQ API mirrors / resources
edge_b=ROOT/'backend/functions/thq-api/index.ts'; edge_s=ROOT/'supabase/functions/thq-api/index.ts'
check('THQ API backend function exists',edge_b.exists())
check('THQ API supabase mirror exists',edge_s.exists())
check('THQ API mirrors identical',edge_b.exists() and edge_s.exists() and edge_b.read_bytes()==edge_s.read_bytes())
if edge_b.exists():
    e=edge_b.read_text(encoding='utf-8')
    for resource in ['pricing','product-identifiers','label-templates']:
        check(f'THQ API routes {resource}',f"case '{resource}'" in e)
    check('THQ API normal path not service role','SUPABASE_SERVICE_ROLE_KEY' not in e)

# Tests updated
for rel in ['apps/client_app/test/widget_test.dart','apps/pos_app/test/widget_test.dart','packages/erp_core/test/erp_core_test.dart']:
    s=text(rel); check(f'{rel} 4.8.2 test',"'4.8.2'" in s); check(f'{rel} migration 134','134' in s)
check('erp_core pricing tests','price resolution exposes pricing provenance' in text('packages/erp_core/test/erp_core_test.dart'))

# Release artifacts
for rel in ['README_V482_RELEASE.md','CHANGELOG_V482.md','docs/V482_ARCHITECTURE.md','docs/V482_RELEASE_ACCEPTANCE.md','docs/V482_DEPLOYMENT.md','backend/THQ_ERP_V482_UPGRADE_FROM_129.sql','backend/upgrade_from_129/V482_POST_UPGRADE_CHECK.sql','backend/upgrade_from_129/README_DEPLOY_V482.md','tools/validate_v482_windows.ps1']:
    check(f'release artifact {rel}',(ROOT/rel).exists())

bundle=text('backend/THQ_ERP_V482_UPGRADE_FROM_129.sql')
positions=[bundle.find(f"values({n},'4.8.2'") for n in range(130,135)]
check('combined migration bundle has 130-134',all(x>=0 for x in positions),str(positions))
check('combined migration bundle ordered',positions==sorted(positions),str(positions))

# Relative Dart imports resolve
for p in list(ROOT.glob('apps/*/lib/**/*.dart'))+list(ROOT.glob('packages/erp_core/lib/**/*.dart')):
    src=p.read_text(encoding='utf-8',errors='ignore')
    for imp in re.findall(r"import\s+'([^']+)'",src):
        if imp.startswith('.'):
            target=(p.parent/imp).resolve()
            check(f'import resolves {p.relative_to(ROOT)} -> {imp}',target.exists(),str(target))

# Balanced Dart delimiters, ignoring strings/comments
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

for p in list(ROOT.glob('apps/*/lib/**/*.dart'))+list(ROOT.glob('packages/erp_core/lib/**/*.dart'))+list(ROOT.glob('apps/*/test/**/*.dart'))+list(ROOT.glob('packages/erp_core/test/**/*.dart')):
    check(f'Dart structural balance {p.relative_to(ROOT)}',balanced(p))

# Basic compile-risk checks observed in prior releases.
for p in list(ROOT.glob('apps/*/lib/**/*.dart')):
    src=p.read_text(encoding='utf-8',errors='ignore')
    for m in re.finditer(r'const\s+InputDecoration\((.*?)\)',src,re.S):
        block=m.group(1)
        bad=re.search(r'\b_[A-Za-z]\w*\b',block) is not None or '${' in block
        check(f'const decoration static {p.relative_to(ROOT)}:{src[:m.start()].count(chr(10))+1}',not bad,' '.join(block.split())[:160])

# SQL function output ambiguity / known hotfix classes.
for p in [next((ROOT/'backend/migrations').glob(f'{n}_v482_*.sql')) for n in range(130,135)]:
    s=p.read_text(encoding='utf-8')
    check(f'{p.name} no ambiguous audit overload','business_audit_write(' not in s or 'business_audit_write_v471' in s)

# Source cleanliness
banned=[]
for p in ROOT.rglob('*'):
    if any(part in {'.git','node_modules','.dart_tool','.gradle','build','.idea','.vscode'} for part in p.parts): banned.append(str(p.relative_to(ROOT)))
check('release tree excludes generated/VCS clutter',not banned,', '.join(banned[:10]))

passed=sum(ok for _,ok,_ in results); total=len(results)
report=['THQ ERP V4.8.2 STATIC RELEASE VERIFICATION',f'Passed: {passed}/{total}','']
for name,ok,detail in results:
    report.append(f"{'PASS' if ok else 'FAIL'} | {name}" + (f' | {detail}' if detail and not ok else ''))
(ROOT/'V482_STATIC_VERIFICATION.txt').write_text('\n'.join(report)+'\n',encoding='utf-8')
print('\n'.join(report[:3]))
if passed!=total:
    for name,ok,detail in results:
        if not ok: print('FAIL:',name,detail)
    sys.exit(1)
