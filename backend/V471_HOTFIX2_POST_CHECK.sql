-- THQ ERP V4.7.1 Hotfix 2 post-check
select public.thq_backend_contract_v47() as backend_contract;

select migration_no,schema_version,release_name,applied_at
from public.thq_schema_releases
where migration_no in (115,116)
order by migration_no;

select
  to_regprocedure('private.business_audit_write_v471(uuid,text,text,uuid,text,jsonb,jsonb)') is not null as unique_audit_writer_exists,
  position('business_audit_write_v471' in pg_get_functiondef('public.tenant_system_create_v471(uuid,uuid,text,text,text,text[],text,text)'::regprocedure)) > 0 as client_create_hardened,
  position('business_audit_write_v471' in pg_get_functiondef('public.tenant_system_update_v471(uuid,uuid,uuid,text,text[],text,text)'::regprocedure)) > 0 as client_update_hardened,
  position('business_audit_write_v471' in pg_get_functiondef('public.tenant_system_revoke_v471(uuid,uuid,text)'::regprocedure)) > 0 as client_revoke_hardened,
  position('business_audit_write_v471' in pg_get_functiondef('public.platform_system_deactivate_v46(uuid,uuid,text)'::regprocedure)) > 0 as admin_deactivate_hardened,
  position('business_audit_write_v471' in pg_get_functiondef('public.customer_receive_payment_v471(uuid,uuid,numeric,text,text,text,uuid,uuid,uuid,text)'::regprocedure)) > 0 as customer_receipt_hardened;
