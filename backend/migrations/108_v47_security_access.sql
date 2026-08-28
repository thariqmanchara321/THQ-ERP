-- THQ ERP V4.7 — fail closed for Client/POS app authorization.
begin;

create or replace function private.erp_user_app_allowed(p_tenant_id uuid,p_app_key text,p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public,private,pg_temp
as $$
  select private.erp_user_is_owner(p_tenant_id,p_user_id)
      or coalesce((select a.enabled from public.business_user_app_access a where a.tenant_id=p_tenant_id and a.user_id=p_user_id and a.app_key=p_app_key),false);
$$;
revoke all on function private.erp_user_app_allowed(uuid,text,uuid) from public;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(108,'4.7.0','Foundation Lock & Production Stabilization','Application authorization is fail-closed when no explicit access record exists (owners remain allowed).')
on conflict(migration_no) do update set notes=excluded.notes;
commit;
select 'THQ ERP V4.7 migration 108 security access ready' as status;
