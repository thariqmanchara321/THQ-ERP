-- FLEXI ERP V4 module catalog, permissions and template enrichment.
begin;

insert into public.modules(key,name,description,category,is_core,sort_order,is_active,is_beta,requires_configuration) values
('stock_transfers','Stock Transfers','Branch/warehouse stock transfer and receiving','Inventory',false,25,true,false,false),
('cashier_shifts','Cashier Shifts','Opening/closing cash and drawer reconciliation','POS',false,36,true,false,true),
('notifications','Notifications','Business alerts and action center','Core',false,95,true,false,false),
('tasks','Tasks','Internal tasks and follow-ups','CRM',false,96,true,false,false),
('approvals','Approvals','Configurable approval workflows','Administration',false,97,true,false,true),
('backup','Backup & Export','Portable tenant backup and export tools','Administration',false,98,true,false,false),
('support','Support','Support tickets and diagnostics','Administration',false,99,true,false,false)
on conflict(key) do update set name=excluded.name,description=excluded.description,category=excluded.category,sort_order=excluded.sort_order,is_active=true,requires_configuration=excluded.requires_configuration;

insert into public.module_dependencies(module_key,depends_on_module_key) values
('stock_transfers','inventory'),('cashier_shifts','pos'),('backup','settings'),('approvals','users'),('notifications','dashboard'),('tasks','users')
on conflict do nothing;

-- V4 permissions. Handle both permission table shapes used by prior Flexi migrations.
do $$ begin
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='permissions' and column_name='description') then
    insert into public.permissions(key,name,module_key,description) values
      ('inventory.transfer','Transfer Stock','inventory','Create/dispatch/receive branch stock transfers'),
      ('inventory.stock_count','Post Stock Counts','inventory','Post physical stock counts'),
      ('inventory.view_cost','View Inventory Cost','inventory','View purchase cost and inventory valuation'),
      ('sales.return','Create Sales Returns','sales','Return sold items and create customer credit'),
      ('sales.void','Void Unpaid Sales','sales','Void an unpaid sale with a required reason'),
      ('sales.view_profit','View Sales Profit','sales','View cost and gross profit'),
      ('purchases.return','Create Purchase Returns','purchases','Return purchased items to supplier'),
      ('purchases.void','Void Unpaid Purchases','purchases','Void an unpaid purchase with a required reason'),
      ('pos.shift_manage','Manage Cashier Shifts','cashier_shifts','Open/close/review cashier shifts'),
      ('accounting.view','View Accounting','accounting','View accounts and registers'),
      ('accounting.manage','Manage Accounts','accounting','Create/edit chart of accounts and mappings'),
      ('accounting.journal','Post Manual Journals','accounting','Post manual double-entry journals'),
      ('backup.export','Export Business Backup','backup','Create full business backup export'),
      ('approvals.approve','Approve Business Actions','approvals','Approve configured business actions'),
      ('tasks.manage','Manage Tasks','tasks','Create/assign/manage internal tasks'),
      ('support.create','Create Support Tickets','support','Create support tickets and diagnostics')
    on conflict(key) do update set name=excluded.name,module_key=excluded.module_key,description=excluded.description;
  else
    insert into public.permissions(key,name,module_key) values
      ('inventory.transfer','Transfer Stock','inventory'),('inventory.stock_count','Post Stock Counts','inventory'),('inventory.view_cost','View Inventory Cost','inventory'),
      ('sales.return','Create Sales Returns','sales'),('sales.void','Void Unpaid Sales','sales'),('sales.view_profit','View Sales Profit','sales'),
      ('purchases.return','Create Purchase Returns','purchases'),('purchases.void','Void Unpaid Purchases','purchases'),('pos.shift_manage','Manage Cashier Shifts','cashier_shifts'),
      ('accounting.view','View Accounting','accounting'),('accounting.manage','Manage Accounts','accounting'),('accounting.journal','Post Manual Journals','accounting'),
      ('backup.export','Export Business Backup','backup'),('approvals.approve','Approve Business Actions','approvals'),('tasks.manage','Manage Tasks','tasks'),('support.create','Create Support Tickets','support')
    on conflict(key) do update set name=excluded.name,module_key=excluded.module_key;
  end if;
end $$;

-- Owners get every V4 permission where applicable.
insert into public.role_permissions(role_id,permission_key)
select r.id,p.key from public.roles r join public.permissions p on p.key in(
'inventory.transfer','inventory.stock_count','inventory.view_cost','sales.return','sales.void','sales.view_profit','purchases.return','purchases.void','pos.shift_manage','accounting.view','accounting.manage','accounting.journal','backup.export','approvals.approve','tasks.manage','support.create') where r.key='owner'
on conflict do nothing;

-- Useful manager/storekeeper/cashier defaults without granting sensitive finance visibility.
insert into public.role_permissions(role_id,permission_key)
select r.id,x.key from public.roles r join (values
('manager','inventory.transfer'),('manager','inventory.stock_count'),('manager','sales.return'),('manager','purchases.return'),('manager','approvals.approve'),('manager','tasks.manage'),
('store_keeper','inventory.transfer'),('store_keeper','inventory.stock_count'),
('accountant','accounting.view'),('accountant','accounting.journal'),
('cashier','support.create')
)x(role_key,key) on x.role_key=r.key on conflict do nothing;

-- Enable lightweight V4 utility modules for existing tenants; business owners can disable optional ones later.
insert into public.tenant_modules(tenant_id,module_key,enabled)
select t.id,x.key,true from public.tenants t cross join(values('notifications'),('support'))x(key)
on conflict(tenant_id,module_key) do nothing;

-- Extend common templates.
insert into public.business_template_modules(template_id,module_key)
select bt.id,x.module_key from public.business_templates bt join(values
('general_retail','stock_transfers'),('general_retail','cashier_shifts'),('general_retail','notifications'),('general_retail','support'),
('auto_parts','stock_transfers'),('auto_parts','cashier_shifts'),('auto_parts','notifications'),('auto_parts','backup'),('auto_parts','support'),
('grocery','stock_transfers'),('grocery','cashier_shifts'),('grocery','notifications'),('grocery','support'),
('restaurant','cashier_shifts'),('restaurant','notifications'),('restaurant','tasks'),('restaurant','support'),
('workshop','stock_transfers'),('workshop','notifications'),('workshop','tasks'),('workshop','approvals'),('workshop','backup'),('workshop','support'),
('pharmacy','stock_transfers'),('pharmacy','cashier_shifts'),('pharmacy','notifications'),('pharmacy','backup'),('pharmacy','support')
)x(template_key,module_key) on bt.key=x.template_key
on conflict do nothing;



-- V4 terminal module selectors include new POS utility modules.
create or replace function public.platform_device_issue_activation_v32(
  p_tenant_id uuid,p_location_id uuid,p_name text,p_app_type text,p_platform_hint text default null,p_module_keys text[] default '{}'::text[],p_invoice_prefix text default null
) returns jsonb language plpgsql security definer set search_path=public,private,extensions,pg_temp
as $$ declare v_id uuid:=gen_random_uuid();v_code text;v_device_code text;v_exp timestamptz:=now()+interval '24 hours';v_modules text[];begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required';end if;
  if p_app_type not in('client','pos') then raise exception 'Invalid app type';end if;
  if not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active) then raise exception 'Invalid location';end if;
  if p_app_type='pos' then select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules from unnest(coalesce(p_module_keys,'{}'::text[]))x where x in('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs','cashier_shifts','notifications','tasks','support') and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);else v_modules:='{}'::text[];end if;
  if nullif(upper(trim(p_invoice_prefix)),'') is not null and exists(select 1 from public.business_devices d where d.tenant_id=p_tenant_id and d.status<>'revoked' and upper(coalesce(d.invoice_prefix,''))=upper(trim(p_invoice_prefix))) then raise exception 'Terminal invoice prefix is already in use';end if;
  v_code:=upper(substr(encode(gen_random_bytes(8),'hex'),1,12));v_device_code:=upper(p_app_type)||'-'||upper(substr(replace(v_id::text,'-',''),1,6));
  insert into public.business_devices(id,tenant_id,location_id,device_code,name,app_type,platform_hint,status,activation_hash,activation_expires_at,allowed_modules,invoice_prefix) values(v_id,p_tenant_id,p_location_id,v_device_code,trim(p_name),p_app_type,nullif(trim(p_platform_hint),''),'pending',encode(digest(v_code,'sha256'),'hex'),v_exp,v_modules,nullif(upper(trim(p_invoice_prefix)),''));
  return jsonb_build_object('device_id',v_id,'device_code',v_device_code,'activation_code',v_code,'expires_at',v_exp,'allowed_modules',v_modules);
end $$;
grant execute on function public.platform_device_issue_activation_v32(uuid,uuid,text,text,text,text[],text) to authenticated;

create or replace function public.platform_device_settings_update(p_tenant_id uuid,p_device_id uuid,p_module_keys text[],p_invoice_prefix text,p_name text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_type text;v_modules text[];begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required';end if;select app_type into v_type from public.business_devices where id=p_device_id and tenant_id=p_tenant_id;if v_type is null then raise exception 'Device not found';end if;
  if v_type='pos' then select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules from unnest(coalesce(p_module_keys,'{}'::text[]))x where x in('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs','cashier_shifts','notifications','tasks','support') and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);else v_modules:='{}'::text[];end if;
  if nullif(upper(trim(p_invoice_prefix)),'') is not null and exists(select 1 from public.business_devices d where d.tenant_id=p_tenant_id and d.id<>p_device_id and d.status<>'revoked' and upper(coalesce(d.invoice_prefix,''))=upper(trim(p_invoice_prefix))) then raise exception 'Terminal invoice prefix is already in use';end if;
  update public.business_devices set allowed_modules=v_modules,invoice_prefix=nullif(upper(trim(p_invoice_prefix)),''),name=coalesce(nullif(trim(p_name),''),name),updated_at=now() where id=p_device_id and tenant_id=p_tenant_id;
end $$;
grant execute on function public.platform_device_settings_update(uuid,uuid,text[],text,text) to authenticated;

create or replace function public.tenant_device_issue_activation(
  p_tenant_id uuid,p_location_id uuid,p_name text,p_app_type text,p_platform_hint text default null,p_module_keys text[] default '{}'::text[],p_invoice_prefix text default null
) returns jsonb language plpgsql security definer set search_path=public,private,extensions,pg_temp
as $$ declare v_id uuid:=gen_random_uuid();v_code text;v_device_code text;v_exp timestamptz:=now()+interval '24 hours';v_modules text[];begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'locations.manage') then raise exception 'Permission denied';end if;if not private.erp_user_location_allowed(p_tenant_id,p_location_id,'manage') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Location manage access denied';end if;if p_app_type not in('client','pos') then raise exception 'Invalid app type';end if;
  if p_app_type='pos' then select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules from unnest(coalesce(p_module_keys,'{}'::text[]))x where x in('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs','cashier_shifts','notifications','tasks','support') and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);else v_modules:='{}'::text[];end if;
  if nullif(upper(trim(p_invoice_prefix)),'') is not null and exists(select 1 from public.business_devices d where d.tenant_id=p_tenant_id and d.status<>'revoked' and upper(coalesce(d.invoice_prefix,''))=upper(trim(p_invoice_prefix))) then raise exception 'Terminal invoice prefix is already in use';end if;
  v_code:=upper(substr(encode(gen_random_bytes(8),'hex'),1,12));v_device_code:=upper(p_app_type)||'-'||upper(substr(replace(v_id::text,'-',''),1,6));insert into public.business_devices(id,tenant_id,location_id,device_code,name,app_type,platform_hint,status,activation_hash,activation_expires_at,allowed_modules,invoice_prefix) values(v_id,p_tenant_id,p_location_id,v_device_code,trim(p_name),p_app_type,nullif(trim(p_platform_hint),''),'pending',encode(digest(v_code,'sha256'),'hex'),v_exp,v_modules,nullif(upper(trim(p_invoice_prefix)),''));return jsonb_build_object('device_id',v_id,'device_code',v_device_code,'activation_code',v_code,'expires_at',v_exp,'allowed_modules',v_modules);
end $$;
grant execute on function public.tenant_device_issue_activation(uuid,uuid,text,text,text,text[],text) to authenticated;

create or replace function public.tenant_device_settings_update(p_tenant_id uuid,p_device_id uuid,p_module_keys text[],p_invoice_prefix text,p_name text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_loc uuid;v_type text;v_modules text[];begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'locations.manage') then raise exception 'Permission denied';end if;select location_id,app_type into v_loc,v_type from public.business_devices where tenant_id=p_tenant_id and id=p_device_id;if v_loc is null then raise exception 'Device not found';end if;if not private.erp_user_location_allowed(p_tenant_id,v_loc,'manage') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Location manage access denied';end if;
  if v_type='pos' then select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules from unnest(coalesce(p_module_keys,'{}'::text[]))x where x in('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs','cashier_shifts','notifications','tasks','support') and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);else v_modules:='{}'::text[];end if;
  update public.business_devices set allowed_modules=v_modules,invoice_prefix=nullif(upper(trim(p_invoice_prefix)),''),name=coalesce(nullif(trim(p_name),''),name),updated_at=now() where id=p_device_id and tenant_id=p_tenant_id;
end $$;
grant execute on function public.tenant_device_settings_update(uuid,uuid,text[],text,text) to authenticated;

commit;
select 'Flexi ERP V4 modules/permissions/templates ready' as status;
