-- Flexi ERP V4.3: tenant-editable Client/POS UI design templates.

create table if not exists public.ui_design_templates (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  app_key text not null check (app_key in ('client','pos')),
  description text,
  config jsonb not null default '{}'::jsonb,
  is_system boolean not null default false,
  is_default boolean not null default false,
  is_active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.ui_design_templates enable row level security;
drop policy if exists ui_design_templates_read on public.ui_design_templates;
create policy ui_design_templates_read on public.ui_design_templates
for select to authenticated
using (is_active or private.platform_v2_is_admin());
revoke insert, update, delete on public.ui_design_templates from authenticated;
grant select on public.ui_design_templates to authenticated;

create table if not exists public.tenant_ui_designs (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  app_key text not null check (app_key in ('client','pos')),
  template_id uuid not null references public.ui_design_templates(id),
  overrides jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  primary key (tenant_id, app_key)
);

alter table public.tenant_ui_designs enable row level security;
drop policy if exists tenant_ui_designs_read on public.tenant_ui_designs;
create policy tenant_ui_designs_read on public.tenant_ui_designs
for select to authenticated
using (private.erp_user_has_tenant_access(tenant_id) or private.platform_v2_is_admin());
revoke insert, update, delete on public.tenant_ui_designs from authenticated;
grant select on public.tenant_ui_designs to authenticated;

insert into public.ui_design_templates(key,name,app_key,description,config,is_system,is_default,is_active,sort_order) values
('client_aurora','Aurora Lavender','client','Airy modern ERP layout inspired by the V4.3 reference designs.',
 '{"primary":"#6C5CE7","secondary":"#AFA4F5","accent":"#7C6CF2","background":"#F5F3FF","surface":"#FFFFFF","sidebar":"#FBFAFF","border":"#E9E5F6","success":"#22A06B","warning":"#E6A700","danger":"#E05252","radius":18,"density":"comfortable","card_style":"soft","header_style":"clean","sidebar_style":"floating","table_style":"soft","gradient":true}'::jsonb,
 true,true,true,10),
('client_ocean','Ocean Blue','client','Crisp blue SaaS theme for service and distribution businesses.',
 '{"primary":"#2563EB","secondary":"#93C5FD","accent":"#0EA5E9","background":"#F3F7FC","surface":"#FFFFFF","sidebar":"#F8FBFF","border":"#DFE8F3","success":"#16A36A","warning":"#D99000","danger":"#D94A4A","radius":16,"density":"comfortable","card_style":"soft","header_style":"clean","sidebar_style":"floating","table_style":"soft","gradient":false}'::jsonb,
 true,false,true,20),
('client_emerald','Emerald Ledger','client','Calm emerald finance-first theme.',
 '{"primary":"#0F8A6A","secondary":"#84D9BE","accent":"#16A085","background":"#F2F8F6","surface":"#FFFFFF","sidebar":"#F8FCFB","border":"#DDECE7","success":"#138A62","warning":"#D89C19","danger":"#D95656","radius":16,"density":"comfortable","card_style":"soft","header_style":"clean","sidebar_style":"floating","table_style":"soft","gradient":false}'::jsonb,
 true,false,true,30),
('client_graphite','Graphite Pro','client','Neutral compact theme for dense back-office work.',
 '{"primary":"#303544","secondary":"#8F96A8","accent":"#596273","background":"#F4F5F7","surface":"#FFFFFF","sidebar":"#FAFAFB","border":"#E2E4E9","success":"#1F8B61","warning":"#C58A13","danger":"#C94C4C","radius":12,"density":"compact","card_style":"bordered","header_style":"compact","sidebar_style":"solid","table_style":"compact","gradient":false}'::jsonb,
 true,false,true,40),
('pos_aurora_grid','Aurora Retail Grid','pos','Fast product-grid POS with a modern cart panel.',
 '{"primary":"#6C5CE7","secondary":"#B7AEF7","accent":"#7C6CF2","background":"#F5F3FF","surface":"#FFFFFF","sidebar":"#FBFAFF","border":"#E8E3F5","success":"#20A36B","warning":"#E4A20A","danger":"#D9534F","radius":18,"density":"comfortable","card_style":"soft","sidebar_style":"floating","pos_layout":"retail_grid","pos_product_style":"soft_cards","pos_cart_width":380,"gradient":true}'::jsonb,
 true,true,true,10),
('pos_compact','Compact Cashier','pos','Dense desktop POS for keyboard-heavy high-volume counters.',
 '{"primary":"#1F2937","secondary":"#94A3B8","accent":"#334155","background":"#F1F3F5","surface":"#FFFFFF","sidebar":"#F8F9FA","border":"#DDE1E6","success":"#16875D","warning":"#C88700","danger":"#C94040","radius":10,"density":"compact","card_style":"bordered","sidebar_style":"solid","pos_layout":"compact_grid","pos_product_style":"solid_tiles","pos_cart_width":400,"gradient":false}'::jsonb,
 true,false,true,20),
('pos_coral_touch','Coral Touch','pos','Warm large-touch POS theme for restaurants and quick service.',
 '{"primary":"#EF5A3C","secondary":"#FFC2B5","accent":"#FF7A59","background":"#FFF6F2","surface":"#FFFFFF","sidebar":"#FFF9F6","border":"#F4DDD5","success":"#27966B","warning":"#DA9300","danger":"#D84B4B","radius":20,"density":"comfortable","card_style":"soft","sidebar_style":"floating","pos_layout":"touch_grid","pos_product_style":"image_cards","pos_cart_width":390,"gradient":true}'::jsonb,
 true,false,true,30),
('pos_ocean','Ocean Counter','pos','Cool blue retail counter design.',
 '{"primary":"#2563EB","secondary":"#93C5FD","accent":"#0EA5E9","background":"#F3F7FC","surface":"#FFFFFF","sidebar":"#F8FBFF","border":"#DFE8F3","success":"#16A36A","warning":"#D99000","danger":"#D94A4A","radius":16,"density":"comfortable","card_style":"soft","sidebar_style":"floating","pos_layout":"retail_grid","pos_product_style":"soft_cards","pos_cart_width":380,"gradient":false}'::jsonb,
 true,false,true,40)
on conflict(key) do update set
  name=excluded.name, app_key=excluded.app_key, description=excluded.description,
  config=excluded.config, is_system=true, is_default=excluded.is_default,
  is_active=true, sort_order=excluded.sort_order, updated_at=now();

create or replace function public.platform_ui_design_templates_list_v43(p_app_key text default null)
returns setof public.ui_design_templates
language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin access required'; end if;
  return query
  select * from public.ui_design_templates
  where p_app_key is null or app_key=p_app_key
  order by app_key,sort_order,name;
end $$;
grant execute on function public.platform_ui_design_templates_list_v43(text) to authenticated;

create or replace function public.platform_ui_design_template_upsert_v43(
  p_id uuid,p_key text,p_name text,p_app_key text,p_description text,p_config jsonb,
  p_is_active boolean,p_is_default boolean,p_sort_order integer
)
returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_id uuid;
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('technical_admin') then
    raise exception 'Technical admin access required';
  end if;
  if p_app_key not in ('client','pos') then raise exception 'Invalid app key'; end if;
  if coalesce(trim(p_key),'')='' or coalesce(trim(p_name),'')='' then raise exception 'Key and name are required'; end if;
  if p_id is not null and exists(select 1 from public.ui_design_templates where id=p_id and app_key<>p_app_key) then
    raise exception 'Template app key cannot be changed after creation';
  end if;

  if coalesce(p_is_default,false) then
    update public.ui_design_templates set is_default=false,updated_at=now() where app_key=p_app_key and is_default=true and (p_id is null or id<>p_id);
  end if;

  if p_id is null then
    insert into public.ui_design_templates(key,name,app_key,description,config,is_system,is_default,is_active,sort_order)
    values(trim(p_key),trim(p_name),p_app_key,nullif(trim(p_description),''),coalesce(p_config,'{}'::jsonb),false,coalesce(p_is_default,false),coalesce(p_is_active,true),coalesce(p_sort_order,100))
    on conflict(key) do update set name=excluded.name,app_key=excluded.app_key,description=excluded.description,config=excluded.config,is_default=excluded.is_default,is_active=excluded.is_active,sort_order=excluded.sort_order,updated_at=now()
    returning id into v_id;
  else
    update public.ui_design_templates set
      key=trim(p_key),name=trim(p_name),app_key=p_app_key,description=nullif(trim(p_description),''),
      config=coalesce(p_config,'{}'::jsonb),is_default=coalesce(p_is_default,false),is_active=coalesce(p_is_active,true),
      sort_order=coalesce(p_sort_order,100),updated_at=now()
    where id=p_id returning id into v_id;
    if v_id is null then raise exception 'Design template not found'; end if;
  end if;
  perform private.platform_audit_write('ui_design_template.upsert','ui_design_template',v_id::text,null,jsonb_build_object('key',p_key,'app_key',p_app_key));
  return v_id;
end $$;
grant execute on function public.platform_ui_design_template_upsert_v43(uuid,text,text,text,text,jsonb,boolean,boolean,integer) to authenticated;

create or replace function public.platform_tenant_ui_design_set_v43(p_tenant_id uuid,p_app_key text,p_template_id uuid,p_overrides jsonb default '{}'::jsonb)
returns void
language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin access required'; end if;
  if p_app_key not in ('client','pos') then raise exception 'Invalid app key'; end if;
  if not exists(select 1 from public.ui_design_templates where id=p_template_id and app_key=p_app_key and is_active) then
    raise exception 'Active design template not found for this app';
  end if;
  insert into public.tenant_ui_designs(tenant_id,app_key,template_id,overrides,updated_at,updated_by)
  values(p_tenant_id,p_app_key,p_template_id,coalesce(p_overrides,'{}'::jsonb),now(),auth.uid())
  on conflict(tenant_id,app_key) do update set template_id=excluded.template_id,overrides=excluded.overrides,updated_at=now(),updated_by=auth.uid();
  perform private.platform_audit_write('tenant.ui_design.set','tenant',p_tenant_id::text,p_tenant_id,jsonb_build_object('app_key',p_app_key,'template_id',p_template_id));
end $$;
grant execute on function public.platform_tenant_ui_design_set_v43(uuid,text,uuid,jsonb) to authenticated;

create or replace function public.tenant_ui_design_get_v43(p_tenant_id uuid,p_app_key text)
returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v jsonb;
begin
  if p_app_key not in ('client','pos') then raise exception 'Invalid app key'; end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  select jsonb_build_object(
    'template_id',t.id,'key',t.key,'name',t.name,'app_key',t.app_key,
    'config',t.config || coalesce(x.overrides,'{}'::jsonb),'base_config',t.config,'overrides',coalesce(x.overrides,'{}'::jsonb)
  ) into v
  from public.tenant_ui_designs x join public.ui_design_templates t on t.id=x.template_id
  where x.tenant_id=p_tenant_id and x.app_key=p_app_key and t.is_active;
  if v is null then
    select jsonb_build_object('template_id',id,'key',key,'name',name,'app_key',app_key,'config',config,'base_config',config,'overrides','{}'::jsonb)
    into v from public.ui_design_templates
    where app_key=p_app_key and is_active
    order by is_default desc,sort_order,name limit 1;
  end if;
  return coalesce(v,'{}'::jsonb);
end $$;
grant execute on function public.tenant_ui_design_get_v43(uuid,text) to authenticated;

create or replace function public.platform_tenant_ui_design_get_v43(p_tenant_id uuid,p_app_key text)
returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v jsonb;
begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin access required'; end if;
  if p_app_key not in ('client','pos') then raise exception 'Invalid app key'; end if;
  select jsonb_build_object(
    'template_id',t.id,'key',t.key,'name',t.name,'app_key',t.app_key,
    'config',t.config || coalesce(x.overrides,'{}'::jsonb),'base_config',t.config,'overrides',coalesce(x.overrides,'{}'::jsonb)
  ) into v
  from public.tenant_ui_designs x join public.ui_design_templates t on t.id=x.template_id
  where x.tenant_id=p_tenant_id and x.app_key=p_app_key;
  return coalesce(v,'{}'::jsonb);
end $$;
grant execute on function public.platform_tenant_ui_design_get_v43(uuid,text) to authenticated;
