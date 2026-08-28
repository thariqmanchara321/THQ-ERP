-- THQ V4.5
-- Hierarchical, admin-controlled navigation for Client and POS.
begin;

insert into public.modules(key,name,description,category,is_core,sort_order,is_active,is_beta,requires_configuration)
values('returns','Returns','Sales and purchase return workspace','Operations',false,38,true,false,false)
on conflict(key) do update set name=excluded.name,description=excluded.description,category=excluded.category,is_active=true,sort_order=excluded.sort_order;

insert into public.tenant_modules(tenant_id,module_key,enabled)
select distinct tenant_id,'returns',true from public.tenant_modules where module_key in('sales','purchases') and enabled
on conflict(tenant_id,module_key) do update set enabled=true;

insert into public.business_template_modules(template_id,module_key)
select distinct template_id,'returns' from public.business_template_modules where module_key in('sales','purchases')
on conflict do nothing;
insert into public.subscription_plan_modules(plan_id,module_key)
select distinct plan_id,'returns' from public.subscription_plan_modules where module_key in('sales','purchases')
on conflict do nothing;

update public.business_devices
set allowed_modules=case when not('returns'=any(allowed_modules)) then array_append(allowed_modules,'returns') else allowed_modules end,
    updated_at=now()
where app_type='pos' and status='active' and ('sales'=any(allowed_modules) or 'purchases'=any(allowed_modules));

create table if not exists public.app_menu_nodes_v45(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade,
  app_key text not null check(app_key in('client','pos')),
  node_key text not null,
  node_type text not null check(node_type in('group','module')),
  module_key text references public.modules(key) on delete restrict,
  parent_id uuid references public.app_menu_nodes_v45(id) on delete cascade,
  label text not null,
  icon_key text,
  sort_order integer not null default 100,
  enabled boolean not null default true,
  collapsed_by_default boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check((node_type='module' and module_key is not null) or (node_type='group' and module_key is null))
);
create unique index if not exists ux_app_menu_nodes_v45_scope_key
on public.app_menu_nodes_v45(coalesce(tenant_id,'00000000-0000-0000-0000-000000000000'::uuid),app_key,node_key);
create index if not exists idx_app_menu_nodes_v45_parent on public.app_menu_nodes_v45(tenant_id,app_key,parent_id,sort_order);
alter table public.app_menu_nodes_v45 enable row level security;
revoke all on public.app_menu_nodes_v45 from anon,authenticated;

-- Seed compact global Client menu.
insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,label,icon_key,sort_order)
values
(null,'client','overview','group','Overview','dashboard',10),
(null,'client','operations','group','Operations','operations',20),
(null,'client','parties','group','Contacts','contacts',30),
(null,'client','finance','group','Finance','finance',40),
(null,'client','industry','group','Business Modules','industry',50),
(null,'client','management','group','Management','settings',60)
on conflict do nothing;

insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order)
select null,'client',x.node_key,'module',x.module_key,p.id,x.label,x.icon_key,x.sort_order
from (values
 ('dashboard','dashboard','Dashboard','dashboard',10,'overview'),
 ('notifications','notifications','Notifications','notifications',20,'overview'),
 ('tasks','tasks','Tasks','tasks',30,'overview'),
 ('approvals','approvals','Approvals','approvals',40,'overview'),
 ('inventory','inventory','Inventory','inventory',10,'operations'),
 ('sales','sales','New Sale','sales',20,'operations'),
 ('purchases','purchases','New Purchase','purchases',30,'operations'),
 ('expenses','expenses','Expenses','expenses',40,'operations'),
 ('stock_transfers','stock_transfers','Stock Transfers','transfer',50,'operations'),
 ('customers','customers','Customers','customers',10,'parties'),
 ('suppliers','suppliers','Suppliers','suppliers',20,'parties'),
 ('accounting','accounting','Accounting','accounting',10,'finance'),
 ('payments','payments','Pending Payments','payments',20,'finance'),
 ('reports','reports','Reports','reports',30,'finance'),
 ('production','production','Production','production',10,'industry'),
 ('transport_service','transport_service','Transport / Service','transport',20,'industry'),
 ('restaurant','restaurant','Restaurant','restaurant',30,'industry'),
 ('workshop','workshop','Workshop','workshop',40,'industry'),
 ('warranty','warranty','Warranty','warranty',50,'industry'),
 ('vehicle_compatibility','vehicle_compatibility','Vehicle Compatibility','vehicle',60,'industry'),
 ('healthcare','healthcare','Healthcare','healthcare',70,'industry'),
 ('lab','lab','Lab','lab',80,'industry'),
 ('pharmacy','pharmacy','Pharmacy','pharmacy',90,'industry'),
 ('division_overview','division_overview','Division Overview','division',50,'industry'),
 ('locations','locations','Stores & Systems','locations',10,'management'),
 ('users','users','Team & Access','users',20,'management'),
 ('invoice_templates','invoice_templates','Invoice Templates','invoice',30,'management'),
 ('bulk_import','bulk_import','Bulk Import','import',40,'management'),
 ('barcode','barcode','Barcode Workbench','barcode',50,'management'),
 ('backup','backup','Backup','backup',60,'management'),
 ('logs','logs','Logs','logs',70,'management'),
 ('settings','settings','Business Settings','settings',80,'management'),
 ('support','support','Support','support',90,'management')
) as x(node_key,module_key,label,icon_key,sort_order,parent_key)
join public.app_menu_nodes_v45 p on p.tenant_id is null and p.app_key='client' and p.node_key=x.parent_key
on conflict do nothing;

-- Seed compact global POS menu.
insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,label,icon_key,sort_order)
values
(null,'pos','checkout','group','Checkout','pos',10),
(null,'pos','daily','group','Terminal','terminal',20),
(null,'pos','masters','group','Masters','inventory',30),
(null,'pos','pos_management','group','Management','settings',40)
on conflict do nothing;

insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order)
select null,'pos',x.node_key,'module',x.module_key,p.id,x.label,x.icon_key,x.sort_order
from (values
 ('sales','sales','Billing','pos',10,'checkout'),
 ('returns','returns','Returns','returns',20,'checkout'),
 ('restaurant','restaurant','Restaurant','restaurant',30,'checkout'),
 ('terminal_day','terminal_day','Terminal Daily','terminal',10,'daily'),
 ('cashier_shifts','cashier_shifts','Cashier Shift','shift',20,'daily'),
 ('inventory','inventory','Products','inventory',10,'masters'),
 ('customers','customers','Customers','customers',20,'masters'),
 ('suppliers','suppliers','Suppliers','suppliers',30,'masters'),
 ('purchases','purchases','Purchases','purchases',40,'masters'),
 ('expenses','expenses','Expenses','expenses',50,'masters'),
 ('notifications','notifications','Notifications','notifications',10,'pos_management'),
 ('logs','logs','Logs','logs',20,'pos_management'),
 ('support','support','Support','support',30,'pos_management'),
 ('settings','settings','Settings','settings',40,'pos_management')
) as x(node_key,module_key,label,icon_key,sort_order,parent_key)
join public.app_menu_nodes_v45 p on p.tenant_id is null and p.app_key='pos' and p.node_key=x.parent_key
on conflict do nothing;

create or replace function public.app_menu_tree_v45(p_tenant_id uuid,p_app_key text)
returns table(id uuid,node_key text,node_type text,module_key text,parent_id uuid,label text,icon_key text,sort_order integer,enabled boolean,collapsed_by_default boolean,metadata jsonb)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare use_tenant boolean;
begin
  if p_app_key not in('client','pos') then raise exception 'Invalid app key';end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select exists(select 1 from public.app_menu_nodes_v45 n where n.tenant_id=p_tenant_id and n.app_key=p_app_key) into use_tenant;
  return query
  select n.id,n.node_key,n.node_type,n.module_key,n.parent_id,n.label,n.icon_key,n.sort_order,n.enabled,n.collapsed_by_default,n.metadata
  from public.app_menu_nodes_v45 n
  where n.app_key=p_app_key and n.enabled and ((use_tenant and n.tenant_id=p_tenant_id) or (not use_tenant and n.tenant_id is null))
  order by n.sort_order,n.label;
end $$;
grant execute on function public.app_menu_tree_v45(uuid,text) to authenticated;

create or replace function public.platform_menu_nodes_v45_list(p_tenant_id uuid,p_app_key text)
returns setof public.app_menu_nodes_v45
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required';end if;
  return query select * from public.app_menu_nodes_v45 n
  where n.app_key=p_app_key and ((p_tenant_id is null and n.tenant_id is null) or n.tenant_id=p_tenant_id)
  order by n.parent_id nulls first,n.sort_order,n.label;
end $$;
grant execute on function public.platform_menu_nodes_v45_list(uuid,text) to authenticated;

create or replace function public.platform_menu_copy_default_v45(p_tenant_id uuid,p_app_key text)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare r record;v_parent uuid;v_new uuid;v_map jsonb:='{}'::jsonb;begin
  if not private.platform_v2_has_role('technical_admin') and not private.platform_v2_has_role('super_admin') then raise exception 'Super/technical admin required';end if;
  if not exists(select 1 from public.tenants where id=p_tenant_id) then raise exception 'Business not found';end if;
  if p_app_key not in('client','pos') then raise exception 'Invalid app key';end if;
  delete from public.app_menu_nodes_v45 where tenant_id=p_tenant_id and app_key=p_app_key;
  for r in
    with recursive tree as (
      select n.*,0 depth from public.app_menu_nodes_v45 n where n.tenant_id is null and n.app_key=p_app_key and n.parent_id is null
      union all
      select c.*,t.depth+1 from public.app_menu_nodes_v45 c join tree t on c.parent_id=t.id where c.tenant_id is null and c.app_key=p_app_key
    ) select * from tree order by depth,sort_order,label
  loop
    v_parent:=case when r.parent_id is null then null else nullif(v_map->>r.parent_id::text,'')::uuid end;
    insert into public.app_menu_nodes_v45(tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order,enabled,collapsed_by_default,metadata,updated_by)
    values(p_tenant_id,p_app_key,r.node_key,r.node_type,r.module_key,v_parent,r.label,r.icon_key,r.sort_order,r.enabled,r.collapsed_by_default,r.metadata,auth.uid()) returning id into v_new;
    v_map:=jsonb_set(v_map,array[r.id::text],to_jsonb(v_new::text),true);
  end loop;
  perform private.platform_audit_write('menu.copy_default','tenant',p_tenant_id::text,p_tenant_id,jsonb_build_object('app_key',p_app_key));
end $$;
grant execute on function public.platform_menu_copy_default_v45(uuid,text) to authenticated;

create or replace function public.platform_menu_node_save_v45(
 p_id uuid,p_tenant_id uuid,p_app_key text,p_node_key text,p_node_type text,p_module_key text,p_parent_id uuid,
 p_label text,p_icon_key text,p_sort_order integer,p_enabled boolean,p_collapsed_by_default boolean,p_metadata jsonb
) returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid:=coalesce(p_id,gen_random_uuid());begin
  if not private.platform_v2_has_role('technical_admin') and not private.platform_v2_has_role('super_admin') then raise exception 'Super/technical admin required';end if;
  if p_app_key not in('client','pos') then raise exception 'Invalid app key';end if;
  if p_node_type not in('group','module') then raise exception 'Invalid node type';end if;
  if trim(coalesce(p_label,''))='' or trim(coalesce(p_node_key,''))='' then raise exception 'Key and label required';end if;
  if p_node_type='module' and not exists(select 1 from public.modules where key=p_module_key) then raise exception 'Module not found';end if;
  if p_parent_id is not null then
    if p_parent_id=v_id then raise exception 'A menu cannot be its own parent';end if;
    if not exists(select 1 from public.app_menu_nodes_v45 x where x.id=p_parent_id and x.app_key=p_app_key and x.tenant_id is not distinct from p_tenant_id) then raise exception 'Parent menu not found';end if;
    if exists(
      with recursive ancestors as (
        select x.id,x.parent_id from public.app_menu_nodes_v45 x where x.id=p_parent_id
        union all
        select x.id,x.parent_id from public.app_menu_nodes_v45 x join ancestors a on x.id=a.parent_id
      ) select 1 from ancestors where id=v_id
    ) then raise exception 'Menu nesting would create a cycle';end if;
  end if;
  insert into public.app_menu_nodes_v45(id,tenant_id,app_key,node_key,node_type,module_key,parent_id,label,icon_key,sort_order,enabled,collapsed_by_default,metadata,updated_by)
  values(v_id,p_tenant_id,p_app_key,trim(p_node_key),p_node_type,case when p_node_type='module' then p_module_key else null end,p_parent_id,trim(p_label),nullif(trim(coalesce(p_icon_key,'')),''),coalesce(p_sort_order,100),coalesce(p_enabled,true),coalesce(p_collapsed_by_default,false),coalesce(p_metadata,'{}'::jsonb),auth.uid())
  on conflict(id) do update set node_key=excluded.node_key,node_type=excluded.node_type,module_key=excluded.module_key,parent_id=excluded.parent_id,label=excluded.label,icon_key=excluded.icon_key,sort_order=excluded.sort_order,enabled=excluded.enabled,collapsed_by_default=excluded.collapsed_by_default,metadata=excluded.metadata,updated_by=auth.uid(),updated_at=now();
  perform private.platform_audit_write('menu.node.save','app_menu_node',v_id::text,p_tenant_id,jsonb_build_object('app_key',p_app_key,'label',p_label,'module_key',p_module_key));
  return v_id;
end $$;
grant execute on function public.platform_menu_node_save_v45(uuid,uuid,text,text,text,text,uuid,text,text,integer,boolean,boolean,jsonb) to authenticated;

create or replace function public.platform_menu_node_delete_v45(p_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_tenant uuid;v_app text;begin
  if not private.platform_v2_has_role('technical_admin') and not private.platform_v2_has_role('super_admin') then raise exception 'Super/technical admin required';end if;
  select tenant_id,app_key into v_tenant,v_app from public.app_menu_nodes_v45 where id=p_id;
  delete from public.app_menu_nodes_v45 where id=p_id;
  perform private.platform_audit_write('menu.node.delete','app_menu_node',p_id::text,v_tenant,jsonb_build_object('app_key',v_app));
end $$;
grant execute on function public.platform_menu_node_delete_v45(uuid) to authenticated;

commit;
select 'THQ V4.5 dynamic navigation ready' as status;
