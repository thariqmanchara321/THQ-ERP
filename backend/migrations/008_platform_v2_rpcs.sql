-- PROTECTED PLATFORM V2 RPCS

create or replace function public.platform_current_admin_context()
returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare v_role text; v_legacy boolean;
begin
  v_legacy := coalesce(public.current_user_is_platform_admin(), false);
  if auth.uid() is null then return jsonb_build_object('is_admin',false); end if;

  if v_legacy and not exists(select 1 from private.platform_admin_role_assignments where user_id=auth.uid()) then
    insert into private.platform_admin_role_assignments(user_id,role_key,active,created_by)
    values(auth.uid(),'super_admin',true,auth.uid())
    on conflict(user_id) do nothing;
  end if;

  select role_key into v_role from private.platform_admin_role_assignments where user_id=auth.uid() and active;
  return jsonb_build_object('is_admin',v_legacy or v_role is not null,'role_key',coalesce(v_role,case when v_legacy then 'super_admin' end));
end $$;

grant execute on function public.platform_current_admin_context() to authenticated;

create or replace function public.platform_modules_v2_list()
returns table(
  key text,name text,description text,category text,is_core boolean,sort_order integer,
  is_active boolean,is_beta boolean,requires_configuration boolean,minimum_plan_key text,
  dependencies text[],business_types text[]
)
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin access required'; end if;
  return query
  select m.key,m.name,m.description,m.category,m.is_core,m.sort_order,m.is_active,m.is_beta,m.requires_configuration,m.minimum_plan_key,
         coalesce((select array_agg(md.depends_on_module_key order by md.depends_on_module_key) from public.module_dependencies md where md.module_key=m.key),array[]::text[]),
         coalesce((select array_agg(mbt.business_type order by mbt.business_type) from public.module_business_types mbt where mbt.module_key=m.key),array[]::text[])
  from public.modules m order by m.category,m.sort_order,m.name;
end $$;

grant execute on function public.platform_modules_v2_list() to authenticated;

create or replace function public.platform_module_v2_upsert(
  p_key text,p_name text,p_description text,p_category text,p_sort_order integer,p_is_core boolean,
  p_is_active boolean,p_is_beta boolean,p_requires_configuration boolean,p_minimum_plan_key text,
  p_dependencies text[],p_business_types text[]
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  if not private.platform_v2_has_role('technical_admin') then raise exception 'Technical admin access required'; end if;
  if coalesce(trim(p_key),'')='' or coalesce(trim(p_name),'')='' then raise exception 'Module key and name are required'; end if;

  insert into public.modules(key,name,description,category,is_core,sort_order,is_active,is_beta,requires_configuration,minimum_plan_key)
  values(trim(p_key),trim(p_name),nullif(trim(p_description),''),coalesce(nullif(trim(p_category),''),'General'),coalesce(p_is_core,false),coalesce(p_sort_order,100),coalesce(p_is_active,true),coalesce(p_is_beta,false),coalesce(p_requires_configuration,false),nullif(trim(p_minimum_plan_key),''))
  on conflict(key) do update set name=excluded.name,description=excluded.description,category=excluded.category,is_core=excluded.is_core,sort_order=excluded.sort_order,is_active=excluded.is_active,is_beta=excluded.is_beta,requires_configuration=excluded.requires_configuration,minimum_plan_key=excluded.minimum_plan_key;

  delete from public.module_dependencies where module_key=p_key;
  insert into public.module_dependencies(module_key,depends_on_module_key)
  select p_key,x from unnest(coalesce(p_dependencies,array[]::text[])) x
  where x<>p_key and exists(select 1 from public.modules m where m.key=x)
  on conflict do nothing;

  delete from public.module_business_types where module_key=p_key;
  insert into public.module_business_types(module_key,business_type)
  select p_key,trim(x) from unnest(coalesce(p_business_types,array[]::text[])) x where trim(x)<>''
  on conflict do nothing;

  perform private.platform_audit_write('module.upsert','module',p_key,null,jsonb_build_object('name',p_name,'active',p_is_active));
end $$;

grant execute on function public.platform_module_v2_upsert(text,text,text,text,integer,boolean,boolean,boolean,boolean,text,text[],text[]) to authenticated;

create or replace function public.platform_templates_list()
returns table(id uuid,key text,name text,business_type text,description text,is_active boolean,is_system boolean,sort_order integer,module_keys text[],settings jsonb)
language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin access required'; end if;
  return query select bt.id,bt.key,bt.name,bt.business_type,bt.description,bt.is_active,bt.is_system,bt.sort_order,
    coalesce((select array_agg(btm.module_key order by m.sort_order,m.name) from public.business_template_modules btm join public.modules m on m.key=btm.module_key where btm.template_id=bt.id),array[]::text[]),bt.settings
  from public.business_templates bt order by bt.sort_order,bt.name;
end $$;
grant execute on function public.platform_templates_list() to authenticated;

create or replace function public.platform_template_upsert(
  p_id uuid,p_key text,p_name text,p_business_type text,p_description text,p_is_active boolean,p_sort_order integer,p_module_keys text[],p_settings jsonb
)
returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_id uuid;
begin
  if not private.platform_v2_has_role('technical_admin') then raise exception 'Technical admin access required'; end if;
  if coalesce(trim(p_key),'')='' or coalesce(trim(p_name),'')='' then raise exception 'Template key and name are required'; end if;
  if p_id is null then
    insert into public.business_templates(key,name,business_type,description,is_active,is_system,sort_order,settings)
    values(trim(p_key),trim(p_name),coalesce(nullif(trim(p_business_type),''),'Custom'),nullif(trim(p_description),''),coalesce(p_is_active,true),false,coalesce(p_sort_order,100),coalesce(p_settings,'{}'::jsonb))
    on conflict(key) do update set name=excluded.name,business_type=excluded.business_type,description=excluded.description,is_active=excluded.is_active,sort_order=excluded.sort_order,settings=excluded.settings,updated_at=now()
    returning id into v_id;
  else
    update public.business_templates set name=trim(p_name),business_type=coalesce(nullif(trim(p_business_type),''),'Custom'),description=nullif(trim(p_description),''),is_active=coalesce(p_is_active,true),sort_order=coalesce(p_sort_order,100),settings=coalesce(p_settings,settings),updated_at=now() where id=p_id returning id into v_id;
    if v_id is null then raise exception 'Template not found'; end if;
  end if;

  delete from public.business_template_modules where template_id=v_id;
  insert into public.business_template_modules(template_id,module_key)
  select v_id,x from unnest(coalesce(p_module_keys,array[]::text[])) x where exists(select 1 from public.modules m where m.key=x and m.is_active)
  on conflict do nothing;
  insert into public.business_template_modules(template_id,module_key) values(v_id,'dashboard') on conflict do nothing;
  perform private.platform_audit_write('template.upsert','business_template',v_id::text,null,jsonb_build_object('key',p_key));
  return v_id;
end $$;
grant execute on function public.platform_template_upsert(uuid,text,text,text,text,boolean,integer,text[],jsonb) to authenticated;

create or replace function public.platform_subscription_plans_list()
returns table(id uuid,key text,name text,description text,monthly_price numeric,yearly_price numeric,currency_code text,is_active boolean,sort_order integer,module_keys text[],limits jsonb)
language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin access required'; end if;
  return query select sp.id,sp.key,sp.name,sp.description,sp.monthly_price,sp.yearly_price,sp.currency_code,sp.is_active,sp.sort_order,
    coalesce((select array_agg(spm.module_key order by m.sort_order,m.name) from public.subscription_plan_modules spm join public.modules m on m.key=spm.module_key where spm.plan_id=sp.id),array[]::text[]),sp.limits
  from public.subscription_plans sp order by sp.sort_order,sp.name;
end $$;
grant execute on function public.platform_subscription_plans_list() to authenticated;

create or replace function public.platform_subscription_plan_upsert(
  p_id uuid,p_key text,p_name text,p_description text,p_monthly_price numeric,p_yearly_price numeric,p_currency_code text,p_is_active boolean,p_sort_order integer,p_module_keys text[],p_limits jsonb
)
returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_id uuid;
begin
  if not private.platform_v2_has_role('billing_admin') then raise exception 'Billing admin access required'; end if;
  if coalesce(trim(p_key),'')='' or coalesce(trim(p_name),'')='' then raise exception 'Plan key and name are required'; end if;
  if coalesce(p_monthly_price,0)<0 or coalesce(p_yearly_price,0)<0 then raise exception 'Prices cannot be negative'; end if;
  if p_id is null then
    insert into public.subscription_plans(key,name,description,monthly_price,yearly_price,currency_code,is_active,sort_order,limits)
    values(trim(p_key),trim(p_name),nullif(trim(p_description),''),coalesce(p_monthly_price,0),coalesce(p_yearly_price,0),upper(coalesce(nullif(trim(p_currency_code),''),'INR')),coalesce(p_is_active,true),coalesce(p_sort_order,100),coalesce(p_limits,'{}'::jsonb))
    on conflict(key) do update set name=excluded.name,description=excluded.description,monthly_price=excluded.monthly_price,yearly_price=excluded.yearly_price,currency_code=excluded.currency_code,is_active=excluded.is_active,sort_order=excluded.sort_order,limits=excluded.limits,updated_at=now()
    returning id into v_id;
  else
    update public.subscription_plans set name=trim(p_name),description=nullif(trim(p_description),''),monthly_price=coalesce(p_monthly_price,0),yearly_price=coalesce(p_yearly_price,0),currency_code=upper(coalesce(nullif(trim(p_currency_code),''),'INR')),is_active=coalesce(p_is_active,true),sort_order=coalesce(p_sort_order,100),limits=coalesce(p_limits,limits),updated_at=now() where id=p_id returning id into v_id;
    if v_id is null then raise exception 'Plan not found'; end if;
  end if;
  delete from public.subscription_plan_modules where plan_id=v_id;
  insert into public.subscription_plan_modules(plan_id,module_key) select v_id,x from unnest(coalesce(p_module_keys,array[]::text[])) x where exists(select 1 from public.modules m where m.key=x and m.is_active) on conflict do nothing;
  insert into public.subscription_plan_modules(plan_id,module_key) values(v_id,'dashboard') on conflict do nothing;
  perform private.platform_audit_write('subscription_plan.upsert','subscription_plan',v_id::text,null,jsonb_build_object('key',p_key));
  return v_id;
end $$;
grant execute on function public.platform_subscription_plan_upsert(uuid,text,text,text,numeric,numeric,text,boolean,integer,text[],jsonb) to authenticated;

create or replace function public.platform_admins_v2_list()
returns table(user_id uuid,email text,role_key text,active boolean,created_at timestamptz)
language plpgsql security definer set search_path=public,private,auth,pg_temp
as $$
begin
  if not private.platform_v2_has_role('super_admin') then raise exception 'Super Admin access required'; end if;
  return query select a.user_id,u.email::text,a.role_key,a.active,a.created_at from private.platform_admin_role_assignments a join auth.users u on u.id=a.user_id order by u.email;
end $$;
grant execute on function public.platform_admins_v2_list() to authenticated;

create or replace function public.platform_admin_v2_grant(p_email text,p_role_key text)
returns void
language plpgsql security definer set search_path=public,private,auth,pg_temp
as $$
declare v_user uuid;
begin
  if not private.platform_v2_has_role('super_admin') then raise exception 'Super Admin access required'; end if;
  if p_role_key not in ('super_admin','support_admin','billing_admin','sales_admin','technical_admin','auditor') then raise exception 'Invalid platform role'; end if;
  select id into v_user from auth.users where lower(email)=lower(trim(p_email)) limit 1;
  if v_user is null then raise exception 'No authenticated user exists with this email'; end if;
  insert into private.platform_admin_role_assignments(user_id,role_key,active,created_by) values(v_user,p_role_key,true,auth.uid())
  on conflict(user_id) do update set role_key=excluded.role_key,active=true,updated_at=now();
  perform private.platform_audit_write('platform_admin.grant','platform_admin',v_user::text,null,jsonb_build_object('email',lower(trim(p_email)),'role_key',p_role_key));
end $$;
grant execute on function public.platform_admin_v2_grant(text,text) to authenticated;

create or replace function public.platform_admin_v2_revoke(p_user_id uuid)
returns void
language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if not private.platform_v2_has_role('super_admin') then raise exception 'Super Admin access required'; end if;
  if p_user_id=auth.uid() then raise exception 'You cannot revoke your own platform access'; end if;
  update private.platform_admin_role_assignments set active=false,updated_at=now() where user_id=p_user_id;
  perform private.platform_audit_write('platform_admin.revoke','platform_admin',p_user_id::text,null,'{}'::jsonb);
end $$;
grant execute on function public.platform_admin_v2_revoke(uuid) to authenticated;

create or replace function public.platform_settings_list()
returns table(key text,value jsonb,description text)
language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin access required'; end if;
  return query select s.key,s.value,s.description from public.platform_settings s order by s.key;
end $$;
grant execute on function public.platform_settings_list() to authenticated;

create or replace function public.platform_setting_set(p_key text,p_value jsonb)
returns void
language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if not private.platform_v2_has_role('technical_admin') then raise exception 'Technical admin access required'; end if;
  insert into public.platform_settings(key,value,updated_by) values(trim(p_key),coalesce(p_value,'null'::jsonb),auth.uid())
  on conflict(key) do update set value=excluded.value,updated_by=auth.uid(),updated_at=now();
  perform private.platform_audit_write('platform_setting.set','platform_setting',p_key,null,jsonb_build_object('value',p_value));
end $$;
grant execute on function public.platform_setting_set(text,jsonb) to authenticated;

create or replace function public.platform_audit_list(p_limit integer default 200)
returns table(id uuid,created_at timestamptz,actor_email text,action text,entity_type text,entity_id text,tenant_name text,details jsonb)
language plpgsql security definer set search_path=public,private,auth,pg_temp
as $$
begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin access required'; end if;
  return query select a.id,a.created_at,coalesce(u.email::text,''),a.action,a.entity_type,a.entity_id,t.name,a.details
  from private.platform_audit_log a left join auth.users u on u.id=a.actor_user_id left join public.tenants t on t.id=a.tenant_id
  order by a.created_at desc limit least(greatest(coalesce(p_limit,200),1),1000);
end $$;
grant execute on function public.platform_audit_list(integer) to authenticated;

create or replace function public.platform_tenant_subscription_get(p_tenant_id uuid)
returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v jsonb;
begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin access required'; end if;
  select jsonb_build_object('tenant_id',p_tenant_id,'plan_id',sp.id,'plan_key',sp.key,'plan_name',sp.name,'status',ts.status,'billing_cycle',ts.billing_cycle,'starts_at',ts.starts_at,'ends_at',ts.ends_at,'trial_ends_at',ts.trial_ends_at,'limit_overrides',ts.limit_overrides)
  into v from public.tenant_subscriptions ts join public.subscription_plans sp on sp.id=ts.plan_id where ts.tenant_id=p_tenant_id;
  return coalesce(v,jsonb_build_object('tenant_id',p_tenant_id,'status','none','billing_cycle','monthly','limit_overrides','{}'::jsonb));
end $$;
grant execute on function public.platform_tenant_subscription_get(uuid) to authenticated;

create or replace function public.platform_tenant_subscription_set(p_tenant_id uuid,p_plan_id uuid,p_status text,p_billing_cycle text,p_ends_at timestamptz,p_trial_ends_at timestamptz,p_limit_overrides jsonb)
returns void
language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if not private.platform_v2_has_role('billing_admin') then raise exception 'Billing admin access required'; end if;
  if not exists(select 1 from public.tenants where id=p_tenant_id) then raise exception 'Tenant not found'; end if;
  if not exists(select 1 from public.subscription_plans where id=p_plan_id and is_active) then raise exception 'Plan not found or disabled'; end if;
  if p_status not in ('trial','active','past_due','suspended','cancelled') then raise exception 'Invalid subscription status'; end if;
  if p_billing_cycle not in ('monthly','yearly','custom') then raise exception 'Invalid billing cycle'; end if;
  insert into public.tenant_subscriptions(tenant_id,plan_id,status,billing_cycle,starts_at,ends_at,trial_ends_at,limit_overrides)
  values(p_tenant_id,p_plan_id,p_status,p_billing_cycle,now(),p_ends_at,p_trial_ends_at,coalesce(p_limit_overrides,'{}'::jsonb))
  on conflict(tenant_id) do update set plan_id=excluded.plan_id,status=excluded.status,billing_cycle=excluded.billing_cycle,ends_at=excluded.ends_at,trial_ends_at=excluded.trial_ends_at,limit_overrides=excluded.limit_overrides,updated_at=now();
  perform private.platform_audit_write('tenant_subscription.set','tenant_subscription',p_tenant_id::text,p_tenant_id,jsonb_build_object('plan_id',p_plan_id,'status',p_status,'billing_cycle',p_billing_cycle));
end $$;
grant execute on function public.platform_tenant_subscription_set(uuid,uuid,text,text,timestamptz,timestamptz,jsonb) to authenticated;

create or replace function public.client_subscription_context(p_tenant_id uuid)
returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  select jsonb_build_object(
    'plan_key',sp.key,'plan_name',sp.name,'status',ts.status,'billing_cycle',ts.billing_cycle,
    'entitled_modules',coalesce((select jsonb_agg(spm.module_key order by m.sort_order,m.name) from public.subscription_plan_modules spm join public.modules m on m.key=spm.module_key where spm.plan_id=sp.id and m.is_active),'[]'::jsonb),
    'limits',sp.limits || ts.limit_overrides
  ) into v from public.tenant_subscriptions ts join public.subscription_plans sp on sp.id=ts.plan_id where ts.tenant_id=p_tenant_id;
  return coalesce(v,jsonb_build_object('status','none','billing_cycle','monthly','entitled_modules','[]'::jsonb,'limits','{}'::jsonb));
end $$;
grant execute on function public.client_subscription_context(uuid) to authenticated;

create or replace function public.tenant_settings_v2_get(p_tenant_id uuid)
returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_platform jsonb; v_tenant jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) and not private.platform_v2_is_admin() then raise exception 'Access denied'; end if;
  select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) into v_platform from public.platform_settings;
  select settings into v_tenant from public.tenant_settings_v2 where tenant_id=p_tenant_id;
  return coalesce(v_platform,'{}'::jsonb) || coalesce(v_tenant,'{}'::jsonb);
end $$;
grant execute on function public.tenant_settings_v2_get(uuid) to authenticated;

create or replace function public.tenant_settings_v2_set(p_tenant_id uuid,p_settings jsonb)
returns void
language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not private.erp_has_permission(p_tenant_id,'settings.manage') then raise exception 'Permission denied'; end if;
  insert into public.tenant_settings_v2(tenant_id,settings,updated_by) values(p_tenant_id,coalesce(p_settings,'{}'::jsonb),auth.uid())
  on conflict(tenant_id) do update set settings=excluded.settings,updated_by=auth.uid(),updated_at=now();
end $$;
grant execute on function public.tenant_settings_v2_set(uuid,jsonb) to authenticated;

create or replace function public.platform_apply_template_settings(p_tenant_id uuid,p_template_key text)
returns void
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_settings jsonb;
begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin access required'; end if;
  select settings into v_settings from public.business_templates where key=p_template_key and is_active;
  if v_settings is null then raise exception 'Template not found'; end if;
  insert into public.tenant_settings_v2(tenant_id,settings,updated_by) values(p_tenant_id,v_settings,auth.uid())
  on conflict(tenant_id) do update set settings=public.tenant_settings_v2.settings || excluded.settings,updated_by=auth.uid(),updated_at=now();
  perform private.platform_audit_write('template.apply_settings','tenant',p_tenant_id::text,p_tenant_id,jsonb_build_object('template_key',p_template_key));
end $$;
grant execute on function public.platform_apply_template_settings(uuid,text) to authenticated;

-- Enforces module dependencies and subscription entitlements when the admin changes tenant modules.
create or replace function public.platform_update_business_modules_v2(p_tenant_id uuid,p_module_keys text[])
returns void
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_requested text[]; v_expanded text[];
begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin access required'; end if;
  if not exists(select 1 from public.tenants where id=p_tenant_id) then raise exception 'Tenant not found'; end if;

  select array_agg(distinct x) into v_requested from unnest(coalesce(p_module_keys,array[]::text[]) || array['dashboard']) x;

  with recursive wanted(module_key) as (
    select unnest(v_requested)
    union
    select md.depends_on_module_key from public.module_dependencies md join wanted w on w.module_key=md.module_key
  ) select array_agg(distinct w.module_key) into v_expanded from wanted w join public.modules m on m.key=w.module_key and m.is_active;

  if exists(select 1 from public.tenant_subscriptions ts where ts.tenant_id=p_tenant_id and ts.status in ('trial','active','past_due')) then
    if exists(
      select 1 from unnest(v_expanded) x
      where not exists(select 1 from public.tenant_subscriptions ts join public.subscription_plan_modules spm on spm.plan_id=ts.plan_id where ts.tenant_id=p_tenant_id and spm.module_key=x)
    ) then raise exception 'One or more selected modules are not included in this tenant subscription plan'; end if;
  end if;

  insert into public.tenant_modules(tenant_id,module_key,enabled)
  select p_tenant_id,m.key,(m.key=any(v_expanded)) from public.modules m
  on conflict(tenant_id,module_key) do update set enabled=excluded.enabled;

  -- Remove disabled-module permissions. Owner gets permissions for every enabled module.
  delete from public.role_permissions rp using public.roles r,public.permissions p
  where rp.role_id=r.id and rp.permission_key=p.key and r.tenant_id=p_tenant_id and not (p.module_key=any(v_expanded));

  insert into public.role_permissions(role_id,permission_key)
  select r.id,p.key from public.roles r join public.permissions p on p.module_key=any(v_expanded)
  where r.tenant_id=p_tenant_id and r.key='owner'
  on conflict do nothing;

  perform private.platform_audit_write('tenant.modules.update','tenant',p_tenant_id::text,p_tenant_id,jsonb_build_object('module_keys',v_expanded));
end $$;
grant execute on function public.platform_update_business_modules_v2(uuid,text[]) to authenticated;
