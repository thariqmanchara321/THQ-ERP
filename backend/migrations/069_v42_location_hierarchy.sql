-- FLEXI ERP V4.2
-- Normalized physical location hierarchy and runtime context.
-- Keeps tenant/business identity separate from physical MAIN/child/warehouse locations
-- so V4.3 can redesign navigation without changing transaction ownership.
begin;

alter table public.business_locations
  add column if not exists hierarchy_role text,
  add column if not exists sort_order integer not null default 100;

update public.business_locations
set hierarchy_role = case
  when upper(location_code)='MAIN' or location_type='head_office' then 'main_store'
  when location_type='warehouse' then 'warehouse'
  else 'child_store'
end
where hierarchy_role is null or trim(hierarchy_role)='';

alter table public.business_locations alter column hierarchy_role set default 'child_store';
alter table public.business_locations alter column hierarchy_role set not null;

do $$
declare c record;
begin
  for c in
    select conname
    from pg_constraint
    where conrelid='public.business_locations'::regclass
      and contype='c'
      and pg_get_constraintdef(oid) ilike '%hierarchy_role%'
  loop
    execute format('alter table public.business_locations drop constraint %I',c.conname);
  end loop;
end $$;

alter table public.business_locations
  add constraint business_locations_hierarchy_role_check
  check(hierarchy_role in('main_store','child_store','warehouse','operational'));

-- Keep exactly one canonical MAIN location for tenants that already have locations.
do $$
declare r record; v_main uuid;
begin
  for r in select id from public.tenants loop
    select id into v_main
    from public.business_locations
    where tenant_id=r.id
    order by
      case when upper(location_code)='MAIN' then 0 when location_type='head_office' then 1 when hierarchy_role='main_store' then 2 else 3 end,
      created_at
    limit 1;

    if v_main is null then
      insert into public.business_locations(tenant_id,location_code,name,location_type,hierarchy_role,active,sort_order)
      select r.id,'MAIN',t.name||' - Main','head_office','main_store',true,0
      from public.tenants t where t.id=r.id
      returning id into v_main;
    end if;

    update public.business_locations
    set hierarchy_role=case when id=v_main then 'main_store' when location_type='warehouse' then 'warehouse' else coalesce(nullif(hierarchy_role,'main_store'),'child_store') end,
        parent_location_id=case when id=v_main then null when parent_location_id is null then v_main else parent_location_id end,
        location_type=case when id=v_main then 'head_office' else location_type end,
        active=case when id=v_main then true else active end,
        sort_order=case when id=v_main then 0 else sort_order end,
        updated_at=now()
    where tenant_id=r.id;
  end loop;
end $$;

create unique index if not exists ux_business_locations_one_main_v42
  on public.business_locations(tenant_id)
  where hierarchy_role='main_store';
create index if not exists idx_business_locations_parent_v42
  on public.business_locations(tenant_id,parent_location_id,active,sort_order,name);

create or replace function private.v42_main_location(p_tenant_id uuid)
returns uuid language sql stable security definer set search_path=public,private,pg_temp
as $$
  select id from public.business_locations
  where tenant_id=p_tenant_id and hierarchy_role='main_store'
  order by active desc,created_at limit 1
$$;
revoke all on function private.v42_main_location(uuid) from public;

create or replace function private.v42_validate_location_hierarchy()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_parent_tenant uuid; v_found boolean;
begin
  -- Existing business-creation code already uses location code MAIN. Promote it
  -- automatically so businesses created after V4.2 also get the canonical root.
  if upper(coalesce(new.location_code,''))='MAIN' then
    new.hierarchy_role:='main_store';
  end if;

  if new.hierarchy_role='main_store' then
    new.parent_location_id:=null;
    new.location_type:='head_office';
    new.active:=true;
    new.sort_order:=0;
  elsif new.parent_location_id is null then
    new.parent_location_id:=private.v42_main_location(new.tenant_id);
  end if;

  if new.parent_location_id is not null then
    if new.parent_location_id=new.id then raise exception 'A location cannot be its own parent'; end if;
    select tenant_id into v_parent_tenant from public.business_locations where id=new.parent_location_id;
    if v_parent_tenant is null or v_parent_tenant<>new.tenant_id then raise exception 'Parent location must belong to the same business'; end if;

    with recursive ancestors as (
      select id,parent_location_id from public.business_locations where id=new.parent_location_id
      union all
      select l.id,l.parent_location_id from public.business_locations l join ancestors a on l.id=a.parent_location_id
    )
    select exists(select 1 from ancestors where id=new.id) into v_found;
    if coalesce(v_found,false) then raise exception 'Location hierarchy cycle detected'; end if;
  end if;
  return new;
end $$;
revoke all on function private.v42_validate_location_hierarchy() from public;

drop trigger if exists trg_v42_location_hierarchy on public.business_locations;
create trigger trg_v42_location_hierarchy
before insert or update of tenant_id,parent_location_id,location_code,hierarchy_role,location_type,sort_order,active
on public.business_locations
for each row execute function private.v42_validate_location_hierarchy();

create or replace function public.business_location_tree_v42(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_all boolean; v_result jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  v_all:=private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all');

  with recursive tree as (
    select l.id,l.tenant_id,l.parent_location_id,l.location_code,l.tracking_code,l.name,l.location_type,l.hierarchy_role,
           l.sort_order,l.active,0 depth,array[l.id] path_ids,array[l.name::text] path_names,
           array[lpad(l.sort_order::text,10,'0')||':'||lower(l.name)] path_sort
    from public.business_locations l
    where l.tenant_id=p_tenant_id and l.parent_location_id is null
    union all
    select c.id,c.tenant_id,c.parent_location_id,c.location_code,c.tracking_code,c.name,c.location_type,c.hierarchy_role,
           c.sort_order,c.active,t.depth+1,t.path_ids||c.id,t.path_names||c.name::text,
           t.path_sort||(lpad(c.sort_order::text,10,'0')||':'||lower(c.name))
    from public.business_locations c join tree t on c.parent_location_id=t.id
    where c.tenant_id=p_tenant_id and not c.id=any(t.path_ids)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'parent_location_id',t.parent_location_id,'code',t.location_code,'tracking_code',t.tracking_code,
    'name',t.name,'type',t.location_type,'hierarchy_role',t.hierarchy_role,'sort_order',t.sort_order,'active',t.active,
    'depth',t.depth,'path',array_to_string(t.path_names,' / '),
    'access_level',case when v_all then 'manage' else a.access_level end,
    'device_count',(select count(*) from public.business_devices d where d.location_id=t.id and d.status<>'revoked')
  ) order by t.path_sort),'[]'::jsonb)
  into v_result
  from tree t
  left join public.business_user_location_access a
    on a.tenant_id=p_tenant_id and a.user_id=auth.uid() and a.location_id=t.id
  where v_all or a.user_id is not null;
  return coalesce(v_result,'[]'::jsonb);
end $$;
grant execute on function public.business_location_tree_v42(uuid) to authenticated;

create or replace function public.tenant_locations_devices_list_v42(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v_all boolean;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  v_all:=private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage') or private.erp_has_permission(p_tenant_id,'locations.manage_all');
  return jsonb_build_object(
    'locations',coalesce((select jsonb_agg(jsonb_build_object(
      'id',l.id,'parent_location_id',l.parent_location_id,'location_code',l.location_code,'tracking_code',l.tracking_code,
      'name',l.name,'location_type',l.location_type,'hierarchy_role',l.hierarchy_role,'sort_order',l.sort_order,
      'phone',l.phone,'email',l.email,'gstin',l.gstin,'address_line1',l.address_line1,'address_line2',l.address_line2,
      'city',l.city,'state',l.state,'postal_code',l.postal_code,'country',l.country,'invoice_prefix',l.invoice_prefix,
      'settings',coalesce(l.settings,'{}'::jsonb),'active',l.active,
      'access_level',case when v_all then 'manage' else a.access_level end
    ) order by case when l.hierarchy_role='main_store' then 0 when l.hierarchy_role='warehouse' then 2 else 1 end,l.sort_order,l.name)
      from public.business_locations l left join public.business_user_location_access a on a.tenant_id=p_tenant_id and a.user_id=auth.uid() and a.location_id=l.id
      where l.tenant_id=p_tenant_id and (v_all or a.user_id is not null)),'[]'::jsonb),
    'devices',coalesce((select jsonb_agg(jsonb_build_object(
      'id',d.id,'location_id',d.location_id,'device_code',d.device_code,'tracking_code',d.tracking_code,'name',d.name,
      'app_type',d.app_type,'platform_hint',d.platform_hint,'status',d.status,'allowed_modules',d.allowed_modules,
      'invoice_prefix',d.invoice_prefix,'activated_at',d.activated_at,'last_seen_at',d.last_seen_at,'settings',coalesce(d.settings,'{}'::jsonb)
    ) order by d.created_at desc)
      from public.business_devices d join public.business_locations l on l.id=d.location_id
      left join public.business_user_location_access a on a.tenant_id=p_tenant_id and a.user_id=auth.uid() and a.location_id=l.id
      where d.tenant_id=p_tenant_id and (v_all or a.user_id is not null)),'[]'::jsonb)
  );
end $$;
grant execute on function public.tenant_locations_devices_list_v42(uuid) to authenticated;

create or replace function public.tenant_business_location_save_v42(
  p_tenant_id uuid,p_location_id uuid,p_parent_location_id uuid,p_location_code text,p_name text,p_location_type text,
  p_hierarchy_role text,p_sort_order integer,p_phone text,p_email text,p_gstin text,p_address_line1 text,p_address_line2 text,
  p_city text,p_state text,p_postal_code text,p_country text,p_invoice_prefix text,p_logo_url text,p_active boolean
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_id uuid; v_role text:=lower(coalesce(nullif(trim(p_hierarchy_role),''),'child_store')); v_parent uuid:=p_parent_location_id;
begin
  if v_role not in('main_store','child_store','warehouse','operational') then raise exception 'Invalid location role';end if;
  if p_location_id is not null and exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and hierarchy_role='main_store') and v_role<>'main_store' then
    raise exception 'MAIN Store role cannot be changed';
  end if;
  if v_role='main_store' and exists(select 1 from public.business_locations where tenant_id=p_tenant_id and hierarchy_role='main_store' and id is distinct from p_location_id) then
    raise exception 'This business already has a MAIN Store';
  end if;
  if v_role='main_store' and not coalesce(p_active,true) then raise exception 'MAIN Store cannot be deactivated';end if;
  if v_role='main_store' then v_parent:=null; end if;
  v_id:=public.tenant_business_location_save_v4(
    p_tenant_id,p_location_id,v_parent,p_location_code,p_name,p_location_type,p_phone,p_email,p_gstin,
    p_address_line1,p_address_line2,p_city,p_state,p_postal_code,p_country,p_invoice_prefix,p_logo_url,p_active
  );
  update public.business_locations
  set hierarchy_role=v_role,sort_order=coalesce(p_sort_order,100),
      parent_location_id=case when v_role='main_store' then null else coalesce(v_parent,private.v42_main_location(p_tenant_id)) end,
      updated_at=now()
  where id=v_id and tenant_id=p_tenant_id;
  return v_id;
end $$;
grant execute on function public.tenant_business_location_save_v42(uuid,uuid,uuid,text,text,text,text,integer,text,text,text,text,text,text,text,text,text,text,text,boolean) to authenticated;

create or replace function public.platform_business_location_save_v42(
  p_tenant_id uuid,p_location_id uuid,p_parent_location_id uuid,p_location_code text,p_name text,p_location_type text,
  p_hierarchy_role text,p_sort_order integer,p_phone text,p_email text,p_gstin text,p_address_line1 text,p_address_line2 text,
  p_city text,p_state text,p_postal_code text,p_country text,p_invoice_prefix text,p_active boolean
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_id uuid; v_role text:=lower(coalesce(nullif(trim(p_hierarchy_role),''),'child_store'));v_parent uuid:=p_parent_location_id;
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required';end if;
  if v_role not in('main_store','child_store','warehouse','operational') then raise exception 'Invalid location role';end if;
  if p_location_id is not null and exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and hierarchy_role='main_store') and v_role<>'main_store' then
    raise exception 'MAIN Store role cannot be changed';
  end if;
  if v_role='main_store' and exists(select 1 from public.business_locations where tenant_id=p_tenant_id and hierarchy_role='main_store' and id is distinct from p_location_id) then
    raise exception 'This business already has a MAIN Store';
  end if;
  if v_role='main_store' and not coalesce(p_active,true) then raise exception 'MAIN Store cannot be deactivated';end if;
  if v_role='main_store' then v_parent:=null;end if;
  v_id:=public.platform_business_location_save(
    p_tenant_id,p_location_id,v_parent,p_location_code,p_name,p_location_type,p_phone,p_email,p_gstin,
    p_address_line1,p_address_line2,p_city,p_state,p_postal_code,p_country,p_invoice_prefix,p_active
  );
  update public.business_locations set hierarchy_role=v_role,sort_order=coalesce(p_sort_order,100),
    parent_location_id=case when v_role='main_store' then null else coalesce(v_parent,private.v42_main_location(p_tenant_id)) end,updated_at=now()
  where id=v_id and tenant_id=p_tenant_id;
  return v_id;
end $$;
grant execute on function public.platform_business_location_save_v42(uuid,uuid,uuid,text,text,text,text,integer,text,text,text,text,text,text,text,text,text,text,boolean) to authenticated;

-- Enrich the existing runtime contract instead of creating a UI-specific session API.
create or replace function public.client_runtime_context_v4(p_tenant_id uuid,p_device_id uuid,p_app_key text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v jsonb;v_all boolean;v_username text;v_roles jsonb;v_main uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_app_allowed(p_tenant_id,p_app_key) then raise exception 'This user is not enabled for this application';end if;
  if not exists(select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.app_type=p_app_key and d.status='active') then raise exception 'Device is not active';end if;
  v_all:=private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all');
  v_main:=private.v42_main_location(p_tenant_id);
  select username into v_username from public.user_login_names where user_id=auth.uid();
  select coalesce(jsonb_agg(r.key order by r.key),'[]'::jsonb) into v_roles
  from public.tenant_memberships tm join public.user_roles ur on ur.membership_id=tm.id and ur.tenant_id=tm.tenant_id join public.roles r on r.id=ur.role_id
  where tm.tenant_id=p_tenant_id and tm.user_id=auth.uid() and tm.status='active';
  select jsonb_build_object(
    'schema_version','4.2','username',coalesce(v_username,''),'roles',coalesce(v_roles,'[]'::jsonb),'user_id',auth.uid(),
    'device_id',d.id,'device_code',d.device_code,'device_name',d.name,'device_modules',coalesce(to_jsonb(d.allowed_modules),'[]'::jsonb),
    'location_id',d.location_id,'location_code',l.location_code,'location_name',l.name,'device_invoice_prefix',d.invoice_prefix,
    'main_location_id',v_main,'can_view_all_locations',v_all,
    'locations',coalesce((select jsonb_agg(jsonb_build_object(
      'id',x.id,'parent_location_id',x.parent_location_id,'code',x.location_code,'name',x.name,'type',x.location_type,
      'hierarchy_role',x.hierarchy_role,'sort_order',x.sort_order,'tracking_code',x.tracking_code,
      'access_level',case when v_all then 'manage' else a.access_level end
    ) order by case when x.hierarchy_role='main_store' then 0 when x.hierarchy_role='warehouse' then 2 else 1 end,x.sort_order,x.name)
      from public.business_locations x left join public.business_user_location_access a on a.tenant_id=p_tenant_id and a.user_id=auth.uid() and a.location_id=x.id
      where x.tenant_id=p_tenant_id and x.active and (v_all or a.user_id is not null)),'[]'::jsonb),
    'open_shift',case when p_app_key='pos' then coalesce((select jsonb_build_object('id',s.id,'shift_number',s.shift_number,'opened_at',s.opened_at,'opening_cash',s.opening_cash) from public.cashier_shifts s where s.tenant_id=p_tenant_id and s.device_id=d.id and s.status='open' order by s.opened_at desc limit 1),'{}'::jsonb) else '{}'::jsonb end
  ) into v from public.business_devices d join public.business_locations l on l.id=d.location_id where d.id=p_device_id and d.tenant_id=p_tenant_id;
  return coalesce(v,'{}'::jsonb);
end $$;
grant execute on function public.client_runtime_context_v4(uuid,uuid,text) to authenticated;

commit;
select 'Flexi ERP V4.2 location hierarchy ready' as status;
