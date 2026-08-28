from pathlib import Path
root=Path(__file__).resolve().parents[1]
checks=[]
def ck(name,cond):
    checks.append((name,bool(cond)))
m=(root/'backend/migrations/116_v471_hotfix2_audit_overload_hardening.sql').read_text()
ck('migration 116 exists', bool(m))
ck('unique audit wrapper defined', 'create or replace function private.business_audit_write_v471' in m)
for fn in ['tenant_system_create_v471','tenant_system_update_v471','tenant_system_revoke_v471','platform_system_deactivate_v46','platform_system_update_v471','platform_system_delete_v471','platform_location_delete_v471','customer_receive_payment_v471']:
    pos=m.find('create or replace function public.'+fn)
    ck(fn+' defined', pos>=0)
ck('operational functions use unique writer', m.count('perform private.business_audit_write_v471(')>=8)
ck('backend contract reports hotfix2', "'release','Operational Stabilization Patch — Hotfix 2'" in m)
ck('release contract requires 116', 'minimumMigration = 116' in (root/'packages/erp_core/lib/src/release_contract.dart').read_text())
for app in ['admin_panel','client_app','pos_app']:
    ck(app+' build +3', 'version: 4.7.1+3' in (root/f'apps/{app}/pubspec.yaml').read_text())
failed=[n for n,v in checks if not v]
print(f'{sum(v for _,v in checks)}/{len(checks)} PASS')
for n,v in checks: print(('PASS' if v else 'FAIL')+' - '+n)
raise SystemExit(1 if failed else 0)
