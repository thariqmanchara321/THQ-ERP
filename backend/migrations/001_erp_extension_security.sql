-- FLEXI ERP extension security helpers.
-- Safe additive migration: does not replace existing inventory/sales/purchase engines.

create schema if not exists private;

create or replace function private.erp_user_has_tenant_access(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select exists (
    select 1
    from public.tenant_memberships tm
    where tm.tenant_id = p_tenant_id
      and tm.user_id = auth.uid()
      and tm.status = 'active'
  );
$$;

create or replace function private.erp_has_permission(p_tenant_id uuid, p_permission_key text)
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select exists (
    select 1
    from public.tenant_memberships tm
    join public.user_roles ur
      on ur.tenant_id = tm.tenant_id
     and ur.membership_id = tm.id
    join public.roles r on r.id = ur.role_id
    left join public.role_permissions rp on rp.role_id = r.id
    where tm.tenant_id = p_tenant_id
      and tm.user_id = auth.uid()
      and tm.status = 'active'
      and (r.key = 'owner' or rp.permission_key = p_permission_key)
  );
$$;

create or replace function private.erp_module_enabled(p_tenant_id uuid, p_module_key text)
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select exists (
    select 1 from public.tenant_modules tm
    where tm.tenant_id = p_tenant_id
      and tm.module_key = p_module_key
      and tm.enabled = true
  );
$$;

revoke all on function private.erp_user_has_tenant_access(uuid) from public;
revoke all on function private.erp_has_permission(uuid,text) from public;
revoke all on function private.erp_module_enabled(uuid,text) from public;

-- Add expenses.manage if the permissions table uses the current Flexi ERP shape.
do $$
begin
  if to_regclass('public.permissions') is not null then
    if exists (select 1 from information_schema.columns where table_schema='public' and table_name='permissions' and column_name='description') then
      execute $sql$
        insert into public.permissions (key, name, module_key, description)
        values ('expenses.manage', 'Manage Expenses', 'expenses', 'Create and manage business expenses')
        on conflict (key) do update
          set name=excluded.name, module_key=excluded.module_key, description=excluded.description
      $sql$;
    else
      execute $sql$
        insert into public.permissions (key, name, module_key)
        values ('expenses.manage', 'Manage Expenses', 'expenses')
        on conflict (key) do update
          set name=excluded.name, module_key=excluded.module_key
      $sql$;
    end if;
  end if;
end $$;

-- Existing owner roles automatically receive the new permission when Expenses is enabled.
insert into public.role_permissions (role_id, permission_key)
select r.id, 'expenses.manage'
from public.roles r
join public.tenant_modules tm
  on tm.tenant_id = r.tenant_id
 and tm.module_key = 'expenses'
 and tm.enabled = true
where r.key = 'owner'
on conflict do nothing;
