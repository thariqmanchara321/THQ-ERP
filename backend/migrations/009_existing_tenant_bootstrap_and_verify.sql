-- EXISTING TENANT BOOTSTRAP + PLATFORM V2 VERIFICATION

-- Business Settings is a safe platform/core capability, so enable it for existing tenants.
insert into public.tenant_modules(tenant_id,module_key,enabled)
select t.id,'settings',true from public.tenants t
on conflict(tenant_id,module_key) do update set enabled=true;

insert into public.role_permissions(role_id,permission_key)
select r.id,'settings.manage' from public.roles r where r.key='owner'
on conflict do nothing;

create or replace function public.platform_overview_summary()
returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin access required'; end if;
  return jsonb_build_object(
    'businesses', (select count(*) from public.tenants),
    'active_businesses', (select count(*) from public.tenants where status='active'),
    'active_subscriptions', (select count(*) from public.tenant_subscriptions where status='active'),
    'trials', (select count(*) from public.tenant_subscriptions where status='trial'),
    'plans', (select count(*) from public.subscription_plans where is_active),
    'templates', (select count(*) from public.business_templates where is_active),
    'modules', (select count(*) from public.modules where is_active)
  );
end $$;
grant execute on function public.platform_overview_summary() to authenticated;

-- Fail fast if this database is not the expected Flexi ERP foundation.
do $$
begin
  if to_regclass('public.tenants') is null then raise exception 'Missing public.tenants'; end if;
  if to_regclass('public.tenant_modules') is null then raise exception 'Missing public.tenant_modules'; end if;
  if to_regclass('public.roles') is null then raise exception 'Missing public.roles'; end if;
  if to_regclass('public.permissions') is null then raise exception 'Missing public.permissions'; end if;
  if to_regclass('public.role_permissions') is null then raise exception 'Missing public.role_permissions'; end if;
  if to_regprocedure('public.platform_modules_v2_list()') is null then raise exception 'Missing platform_modules_v2_list'; end if;
  if to_regprocedure('public.platform_templates_list()') is null then raise exception 'Missing platform_templates_list'; end if;
  if to_regprocedure('public.platform_subscription_plans_list()') is null then raise exception 'Missing platform_subscription_plans_list'; end if;
  if to_regprocedure('public.client_subscription_context(uuid)') is null then raise exception 'Missing client_subscription_context'; end if;
  if to_regprocedure('public.tenant_settings_v2_get(uuid)') is null then raise exception 'Missing tenant_settings_v2_get'; end if;
  if not exists(select 1 from public.modules where key='pos') then raise exception 'POS module seed missing'; end if;
end $$;
