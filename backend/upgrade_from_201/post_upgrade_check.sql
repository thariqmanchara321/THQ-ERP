-- THQ ERP v5.0.0 Build 24 — post-upgrade verification
select max(migration_no) as current_migration,
       (array_agg(schema_version order by migration_no desc))[1] as schema_version,
       (array_agg(release_name order by migration_no desc))[1] as release_name
from public.thq_schema_releases;

select public.thq_backend_contract_v47() as backend_contract;
select public.thq_v500_capabilities() as v5_capabilities;
select public.thq_v500_verify() as v5_database_verification;

-- Run reconciliation for tenants visible to the current user/service role.
select t.id as tenant_id,
       t.name as tenant_name,
       public.finance_reconciliation_v500(t.id) as finance_reconciliation
from public.tenants t
where private.erp_user_has_tenant_access(t.id) or private.platform_v2_is_admin()
order by t.name;
