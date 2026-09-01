-- THQ ERP v5.0.0 Build 24 release contract.
begin;
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$ select jsonb_build_object(
 'product','THQ ERP','schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
 'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),'minimum_app_version','4.9.0',
 'release','THQ ERP 5 Milestone','api_version','v1','backward_compatible',true
) $$;
grant execute on function public.thq_backend_contract_v47() to authenticated;
create or replace function public.thq_api_contract_v480()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$ select public.thq_backend_contract_v47()||jsonb_build_object('app_version','5.0.0','build',24,'minimum_migration',210,'capabilities',public.thq_v500_capabilities()) $$;
grant execute on function public.thq_api_contract_v480() to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(210,'5.0.0','THQ ERP 5 Milestone','Build 24 milestone release contract. Finance, CRM, intelligent purchasing, reports, notifications/tasks, BI and reconciliation.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v5.0.0 Build 24 migration 210 applied' as status;
