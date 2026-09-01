-- THQ ERP v5.0.0 Build 26 — Admin POS/location hotfix.
-- Fixes new POS creation, automatic terminal prefixes, and canonical MAIN/child-store hierarchy.
begin;

create or replace function private.v500_ensure_main_location(p_tenant_id uuid)
returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_main uuid;
  v_name text;
begin
  select l.id into v_main
  from public.business_locations l
  where l.tenant_id=p_tenant_id and l.hierarchy_role='main_store'
  order by l.active desc,l.created_at
  limit 1;

  if v_main is null then
    select l.id into v_main
    from public.business_locations l
    where l.tenant_id=p_tenant_id and upper(l.location_code)='MAIN'
    order by l.created_at
    limit 1;
  end if;

  if v_main is null then
    select t.name into v_name from public.tenants t where t.id=p_tenant_id;
    if v_name is null then raise exception 'Business not found'; end if;

    insert into public.business_locations(
      tenant_id,parent_location_id,location_code,name,location_type,
      hierarchy_role,sort_order,invoice_prefix,active
    ) values(
      p_tenant_id,null,'MAIN',v_name||' - Main','head_office',
      'main_store',0,null,true
    ) returning id into v_main;
  else
    update public.business_locations
    set parent_location_id=null,
        location_code='MAIN',
        location_type='head_office',
        hierarchy_role='main_store',
        sort_order=0,
        active=true,
        updated_at=now()
    where id=v_main and tenant_id=p_tenant_id;
  end if;

  update public.business_locations
  set parent_location_id=v_main,updated_at=now()
  where tenant_id=p_tenant_id
    and id<>v_main
    and hierarchy_role<>'main_store'
    and parent_location_id is null;

  return v_main;
end $$;
revoke all on function private.v500_ensure_main_location(uuid) from public,anon,authenticated;

create or replace function private.v500_next_pos_invoice_prefix(p_tenant_id uuid)
returns text
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_no integer;
  v_prefix text;
begin
  -- Serialize prefix allocation per business so two admins cannot receive the same prefix.
  perform 1 from public.tenants where id=p_tenant_id for update;
  if not found then raise exception 'Business not found'; end if;

  select coalesce(max((substring(upper(trim(d.invoice_prefix)) from '^POS0*([0-9]+)$'))::integer),0)+1
    into v_no
  from public.business_devices d
  where d.tenant_id=p_tenant_id
    and d.app_type='pos'
    and nullif(trim(d.invoice_prefix),'') is not null;

  loop
    v_prefix:='POS'||lpad(v_no::text,2,'0');
    exit when not exists(
      select 1 from public.business_devices d
      where d.tenant_id=p_tenant_id
        and d.app_type='pos'
        and upper(trim(coalesce(d.invoice_prefix,'')))=v_prefix
    );
    v_no:=v_no+1;
    if v_no>999999 then raise exception 'POS invoice prefix sequence exhausted'; end if;
  end loop;

  return v_prefix;
end $$;
revoke all on function private.v500_next_pos_invoice_prefix(uuid) from public,anon,authenticated;

create or replace function public.platform_next_pos_invoice_prefix_v500(p_tenant_id uuid)
returns text
language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if not private.platform_v2_has_role('super_admin')
     and not private.platform_v2_has_role('support_admin') then
    raise exception 'Platform admin required';
  end if;
  return private.v500_next_pos_invoice_prefix(p_tenant_id);
end $$;
revoke all on function public.platform_next_pos_invoice_prefix_v500(uuid) from public,anon;
grant execute on function public.platform_next_pos_invoice_prefix_v500(uuid) to authenticated;

-- Restore the canonical MAIN location for businesses created after the old V4.2 backfill.
do $$
declare r record;
begin
  for r in select id from public.tenants loop
    perform private.v500_ensure_main_location(r.id);
  end loop;
end $$;

create or replace function public.platform_business_location_save_v42(
  p_tenant_id uuid,p_location_id uuid,p_parent_location_id uuid,p_location_code text,p_name text,p_location_type text,
  p_hierarchy_role text,p_sort_order integer,p_phone text,p_email text,p_gstin text,p_address_line1 text,p_address_line2 text,
  p_city text,p_state text,p_postal_code text,p_country text,p_invoice_prefix text,p_active boolean
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_id uuid;
  v_role text:=lower(coalesce(nullif(trim(p_hierarchy_role),''),'child_store'));
  v_parent uuid:=p_parent_location_id;
  v_main uuid;
begin
  if not private.platform_v2_has_role('super_admin')
     and not private.platform_v2_has_role('support_admin') then
    raise exception 'Platform admin required';
  end if;
  if nullif(trim(p_location_code),'') is null then raise exception 'Location code is required'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'Location name is required'; end if;
  if v_role not in('main_store','child_store','warehouse','operational') then raise exception 'Invalid location role'; end if;

  if p_location_id is not null
     and exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and hierarchy_role='main_store')
     and v_role<>'main_store' then
    raise exception 'MAIN Store role cannot be changed';
  end if;

  if v_role='main_store' then
    if exists(select 1 from public.business_locations where tenant_id=p_tenant_id and hierarchy_role='main_store' and id is distinct from p_location_id) then
      raise exception 'This business already has a MAIN Store';
    end if;
    if not coalesce(p_active,true) then raise exception 'MAIN Store cannot be deactivated'; end if;
    v_parent:=null;
  else
    v_main:=private.v500_ensure_main_location(p_tenant_id);
    v_parent:=coalesce(v_parent,v_main);
    if not exists(
      select 1 from public.business_locations l
      where l.id=v_parent and l.tenant_id=p_tenant_id and l.active
    ) then
      raise exception 'Parent location must be an active location in the same business';
    end if;
  end if;

  v_id:=public.platform_business_location_save(
    p_tenant_id,p_location_id,v_parent,upper(trim(p_location_code)),trim(p_name),p_location_type,
    p_phone,p_email,p_gstin,p_address_line1,p_address_line2,p_city,p_state,p_postal_code,p_country,
    coalesce(nullif(upper(trim(coalesce(p_invoice_prefix,''))),''),upper(trim(p_location_code))),p_active
  );

  update public.business_locations
  set hierarchy_role=v_role,
      sort_order=case when v_role='main_store' then 0 else coalesce(p_sort_order,100) end,
      parent_location_id=case when v_role='main_store' then null else v_parent end,
      updated_at=now()
  where id=v_id and tenant_id=p_tenant_id;

  return v_id;
end $$;
revoke all on function public.platform_business_location_save_v42(uuid,uuid,uuid,text,text,text,text,integer,text,text,text,text,text,text,text,text,text,text,boolean) from public,anon;
grant execute on function public.platform_business_location_save_v42(uuid,uuid,uuid,text,text,text,text,integer,text,text,text,text,text,text,text,text,text,text,boolean) to authenticated;

-- New businesses must always start with a canonical MAIN location.
create or replace function public.platform_create_business(p_name text,p_slug text,p_business_type text,p_module_keys text[])
returns uuid
language plpgsql security definer set search_path=''
as $$
declare
  v_tenant_id uuid;
  v_slug text;
begin
  if not private.is_platform_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'Business name is required'; end if;
  v_slug:=lower(trim(p_slug));
  if nullif(v_slug,'') is null then raise exception 'Business slug is required'; end if;
  if v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then raise exception 'Slug may contain only lowercase letters, numbers and hyphens'; end if;
  if exists(select 1 from public.tenants t where t.slug=v_slug) then raise exception 'A business with this slug already exists'; end if;
  if exists(
    select 1
    from unnest(coalesce(p_module_keys,array[]::text[])) requested(module_key)
    left join public.modules m on m.key=requested.module_key
    where m.key is null
  ) then raise exception 'One or more selected modules do not exist'; end if;

  insert into public.tenants(name,slug,business_type,status)
  values(trim(p_name),v_slug,nullif(trim(p_business_type),''),'active')
  returning id into v_tenant_id;

  insert into public.tenant_settings(tenant_id,currency_code,timezone,locale)
  values(v_tenant_id,'INR','Asia/Kolkata','en_IN');

  insert into public.tenant_modules(tenant_id,module_key,enabled)
  select v_tenant_id,m.key,true
  from public.modules m
  where m.key='dashboard' or m.key=any(coalesce(p_module_keys,array[]::text[]))
  on conflict(tenant_id,module_key) do update set enabled=true;

  perform private.seed_default_roles(v_tenant_id);
  perform private.v500_ensure_main_location(v_tenant_id);
  return v_tenant_id;
end $$;
revoke all on function public.platform_create_business(text,text,text,text[]) from public,anon;
grant execute on function public.platform_create_business(text,text,text,text[]) to authenticated;

-- Replace the fragile V4.6 delegation. It failed because a NULL audit argument
-- became ambiguous after business_audit_write gained a second overload.
create or replace function public.platform_system_create_v471(
  p_tenant_id uuid,p_location_id uuid,p_name text,p_app_type text,p_platform_hint text default null,
  p_module_keys text[] default '{}'::text[],p_invoice_prefix text default null,p_system_role text default null
) returns jsonb
language plpgsql security definer set search_path=public,private,extensions,pg_temp
as $$
declare
  v_id uuid:=gen_random_uuid();
  v_modules text[]:='{}'::text[];
  v_prefix text;
  v_device_code text;
  v_role text;
begin
  if not private.platform_v2_has_role('super_admin')
     and not private.platform_v2_has_role('support_admin') then
    raise exception 'Platform admin required';
  end if;
  if p_app_type not in('client','pos') then raise exception 'Invalid app type'; end if;
  if not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active) then
    raise exception 'Target store/location is not active';
  end if;

  v_role:=coalesce(nullif(trim(p_system_role),''),case when p_app_type='pos' then 'pos' else 'office' end);
  if p_app_type='pos' and v_role<>'pos' then raise exception 'POS systems must use POS role'; end if;
  if p_app_type='client' and v_role not in('back_office','office','inventory') then raise exception 'Invalid Client system role'; end if;

  if p_app_type='pos' then
    select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules
    from unnest(coalesce(p_module_keys,'{}'::text[])) x
    where x in('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs','cashier_shifts','notifications','tasks','support','terminal_day')
      and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);
    if coalesce(array_length(v_modules,1),0)=0 then raise exception 'Select at least one enabled POS module'; end if;

    if nullif(upper(trim(coalesce(p_invoice_prefix,''))),'') is null then
      v_prefix:=private.v500_next_pos_invoice_prefix(p_tenant_id);
    else
      perform 1 from public.tenants where id=p_tenant_id for update;
      v_prefix:=upper(trim(p_invoice_prefix));
      if exists(select 1 from public.business_devices d where d.tenant_id=p_tenant_id and d.app_type='pos' and upper(trim(coalesce(d.invoice_prefix,'')))=v_prefix) then
        raise exception 'Terminal invoice prefix is already in use';
      end if;
    end if;
  else
    v_prefix:=null;
  end if;

  v_device_code:=upper(p_app_type)||'-'||upper(substr(replace(v_id::text,'-',''),1,8));
  insert into public.business_devices(
    id,tenant_id,location_id,device_code,name,app_type,platform_hint,status,
    allowed_modules,invoice_prefix,system_role,activation_count
  ) values(
    v_id,p_tenant_id,p_location_id,v_device_code,coalesce(nullif(trim(p_name),''),'System'),
    p_app_type,nullif(trim(p_platform_hint),''),'pending',v_modules,v_prefix,v_role,0
  );

  perform private.business_audit_write_v471(
    p_tenant_id,'system.create','business_device',v_id,v_device_code,null::jsonb,
    jsonb_build_object('location_id',p_location_id,'app_type',p_app_type,'system_role',v_role,'modules',v_modules,'invoice_prefix',v_prefix)
  );

  return jsonb_build_object(
    'device_id',v_id,'device_code',v_device_code,'status','pending','location_id',p_location_id,
    'invoice_prefix',v_prefix,'allowed_modules',v_modules,'system_role',v_role
  );
end $$;
revoke all on function public.platform_system_create_v471(uuid,uuid,text,text,text,text[],text,text) from public,anon;
grant execute on function public.platform_system_create_v471(uuid,uuid,text,text,text,text[],text,text) to authenticated;

create or replace function public.tenant_system_create_v471(
  p_tenant_id uuid,p_location_id uuid,p_name text,p_app_type text,p_platform_hint text default null,
  p_module_keys text[] default '{}'::text[],p_invoice_prefix text default null,p_system_role text default null
) returns jsonb
language plpgsql security definer set search_path=public,private,extensions,pg_temp
as $$
declare
  v_id uuid:=gen_random_uuid();
  v_code text;
  v_device_code text;
  v_exp timestamptz:=now()+interval '24 hours';
  v_modules text[]:='{}'::text[];
  v_prefix text;
  v_role text;
begin
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'locations.manage')
     and not private.erp_has_permission(p_tenant_id,'locations.manage_all') then
    raise exception 'Permission denied';
  end if;
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_user_location_allowed(p_tenant_id,p_location_id,'manage') then
    raise exception 'Location manage access denied';
  end if;
  if p_app_type not in('client','pos') then raise exception 'Invalid app type'; end if;
  if not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active) then
    raise exception 'Target store/location is not active';
  end if;

  v_role:=coalesce(nullif(trim(p_system_role),''),case when p_app_type='pos' then 'pos' else 'office' end);
  if p_app_type='pos' and v_role<>'pos' then raise exception 'POS systems must use POS role'; end if;
  if p_app_type='client' and v_role not in('back_office','office','inventory') then raise exception 'Invalid Client system role'; end if;

  if p_app_type='pos' then
    select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules
    from unnest(coalesce(p_module_keys,'{}'::text[])) x
    where x in('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs','cashier_shifts','notifications','tasks','support','terminal_day')
      and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);
    if coalesce(array_length(v_modules,1),0)=0 then raise exception 'Select at least one enabled POS module'; end if;

    if nullif(upper(trim(coalesce(p_invoice_prefix,''))),'') is null then
      v_prefix:=private.v500_next_pos_invoice_prefix(p_tenant_id);
    else
      perform 1 from public.tenants where id=p_tenant_id for update;
      v_prefix:=upper(trim(p_invoice_prefix));
      if exists(select 1 from public.business_devices d where d.tenant_id=p_tenant_id and d.app_type='pos' and upper(trim(coalesce(d.invoice_prefix,'')))=v_prefix) then
        raise exception 'Terminal invoice prefix is already in use';
      end if;
    end if;
  else
    v_prefix:=null;
  end if;

  v_code:=upper(substr(encode(gen_random_bytes(8),'hex'),1,12));
  v_device_code:=upper(p_app_type)||'-'||upper(substr(replace(v_id::text,'-',''),1,8));
  insert into public.business_devices(
    id,tenant_id,location_id,device_code,name,app_type,platform_hint,status,
    activation_hash,activation_expires_at,activation_issued_at,activation_issued_by,
    allowed_modules,invoice_prefix,system_role,activation_count
  ) values(
    v_id,p_tenant_id,p_location_id,v_device_code,coalesce(nullif(trim(p_name),''),'System'),p_app_type,
    nullif(trim(p_platform_hint),''),'pending',encode(digest(v_code,'sha256'),'hex'),v_exp,now(),auth.uid(),
    v_modules,v_prefix,v_role,1
  );

  perform private.business_audit_write_v471(
    p_tenant_id,'system.create','business_device',v_id,v_device_code,null::jsonb,
    jsonb_build_object('location_id',p_location_id,'app_type',p_app_type,'system_role',v_role,'modules',v_modules,'invoice_prefix',v_prefix)
  );

  return jsonb_build_object(
    'device_id',v_id,'device_code',v_device_code,'activation_code',v_code,'expires_at',v_exp,
    'location_id',p_location_id,'invoice_prefix',v_prefix,'allowed_modules',v_modules,'system_role',v_role
  );
end $$;
revoke all on function public.tenant_system_create_v471(uuid,uuid,text,text,text,text[],text,text) from public,anon;
grant execute on function public.tenant_system_create_v471(uuid,uuid,text,text,text,text[],text,text) to authenticated;

-- POS prefixes are auto-assigned at creation. Admin may edit the prefix until
-- the terminal has transaction history; after that it is locked to protect numbering.
create or replace function public.platform_system_update_v471(
  p_tenant_id uuid,p_system_id uuid,p_location_id uuid,p_name text,p_module_keys text[],
  p_invoice_prefix text,p_system_role text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  d public.business_devices%rowtype;
  v_modules text[];
  v_role text;
  v_old_location uuid;
  v_prefix text;
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required';end if;
  select * into d from public.business_devices where id=p_system_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'System not found';end if;
  if not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active) then raise exception 'Target store/location is not active';end if;
  v_old_location:=d.location_id;
  v_role:=coalesce(nullif(trim(p_system_role),''),d.system_role,case when d.app_type='pos' then 'pos' else 'office' end);
  if d.app_type='pos' and v_role<>'pos' then raise exception 'POS systems must use POS role';end if;
  if d.app_type='client' and v_role not in('back_office','office','inventory') then raise exception 'Invalid Client system role';end if;

  if d.location_id<>p_location_id then
    if exists(select 1 from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_system_id and status='open') then raise exception 'Close the cashier shift before moving this system to another store';end if;
    if exists(select 1 from public.pos_held_sales where tenant_id=p_tenant_id and device_id=p_system_id) then raise exception 'Resume or remove held invoices before moving this POS to another store';end if;
  end if;

  if d.app_type='pos' then
    select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules
    from unnest(coalesce(p_module_keys,'{}'::text[]))x
    where x in('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs','cashier_shifts','notifications','tasks','support','terminal_day')
      and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);
    if coalesce(array_length(v_modules,1),0)=0 then raise exception 'Select at least one enabled POS module'; end if;
    v_prefix:=coalesce(
      nullif(upper(trim(coalesce(p_invoice_prefix,''))),''),
      nullif(upper(trim(coalesce(d.invoice_prefix,''))),''),
      private.v500_next_pos_invoice_prefix(p_tenant_id)
    );
    if v_prefix is distinct from nullif(upper(trim(coalesce(d.invoice_prefix,''))),'') then
      if exists(
        select 1 from public.document_origins o
        where o.tenant_id=p_tenant_id and o.device_id=p_system_id
      ) then
        raise exception 'Terminal invoice prefix cannot be changed after this POS has transaction history';
      end if;
      if exists(
        select 1 from public.business_devices x
        where x.tenant_id=p_tenant_id and x.app_type='pos' and x.id<>p_system_id
          and upper(trim(coalesce(x.invoice_prefix,'')))=v_prefix
      ) then
        raise exception 'Terminal invoice prefix is already in use';
      end if;
    end if;
  else
    v_modules:='{}'::text[];
    v_prefix:=d.invoice_prefix;
  end if;

  update public.business_devices
  set location_id=p_location_id,
      name=coalesce(nullif(trim(p_name),''),name),
      allowed_modules=v_modules,
      invoice_prefix=v_prefix,
      system_role=v_role,
      updated_at=now()
  where id=p_system_id;

  perform private.business_audit_write_v471(
    p_tenant_id,'system.update','business_device',p_system_id,d.device_code,null::jsonb,
    jsonb_build_object('from_location_id',v_old_location,'to_location_id',p_location_id,'system_role',v_role,'modules',v_modules,'invoice_prefix',v_prefix)
  );
  return jsonb_build_object('success',true,'system_id',p_system_id,'location_id',p_location_id,'system_role',v_role,'allowed_modules',v_modules,'invoice_prefix',v_prefix);
end $$;
revoke all on function public.platform_system_update_v471(uuid,uuid,uuid,text,text[],text,text) from public,anon;
grant execute on function public.platform_system_update_v471(uuid,uuid,uuid,text,text[],text,text) to authenticated;

create or replace function public.tenant_system_update_v471(
  p_tenant_id uuid,p_system_id uuid,p_location_id uuid,p_name text,p_module_keys text[],p_invoice_prefix text,p_system_role text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  d public.business_devices%rowtype;
  v_modules text[];
  v_role text;
  v_old_location uuid;
  v_prefix text;
begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'locations.manage') and not private.erp_has_permission(p_tenant_id,'locations.manage_all') then raise exception 'Permission denied';end if;
  select * into d from public.business_devices where id=p_system_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'System not found';end if;
  if not private.erp_user_is_owner(p_tenant_id) and (not private.erp_user_location_allowed(p_tenant_id,d.location_id,'manage') or not private.erp_user_location_allowed(p_tenant_id,p_location_id,'manage')) then raise exception 'Location manage access denied';end if;
  if not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active) then raise exception 'Target store/location is not active';end if;
  v_old_location:=d.location_id;
  v_role:=coalesce(nullif(trim(p_system_role),''),d.system_role,case when d.app_type='pos' then 'pos' else 'office' end);
  if d.app_type='pos' and v_role<>'pos' then raise exception 'POS systems must use POS role';end if;
  if d.app_type='client' and v_role not in('back_office','office','inventory') then raise exception 'Invalid Client system role';end if;
  if d.location_id<>p_location_id then
    if exists(select 1 from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_system_id and status='open') then raise exception 'Close the cashier shift before moving this system to another store';end if;
    if exists(select 1 from public.pos_held_sales where tenant_id=p_tenant_id and device_id=p_system_id) then raise exception 'Resume or remove held invoices before moving this POS to another store';end if;
  end if;
  if d.app_type='pos' then
    select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules from unnest(coalesce(p_module_keys,'{}'::text[]))x
    where x in('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs','cashier_shifts','notifications','tasks','support','terminal_day')
      and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);
    if coalesce(array_length(v_modules,1),0)=0 then raise exception 'Select at least one enabled POS module'; end if;
    v_prefix:=coalesce(
      nullif(upper(trim(coalesce(p_invoice_prefix,''))),''),
      nullif(upper(trim(coalesce(d.invoice_prefix,''))),''),
      private.v500_next_pos_invoice_prefix(p_tenant_id)
    );
    if v_prefix is distinct from nullif(upper(trim(coalesce(d.invoice_prefix,''))),'') then
      if exists(
        select 1 from public.document_origins o
        where o.tenant_id=p_tenant_id and o.device_id=p_system_id
      ) then
        raise exception 'Terminal invoice prefix cannot be changed after this POS has transaction history';
      end if;
      if exists(
        select 1 from public.business_devices x
        where x.tenant_id=p_tenant_id and x.app_type='pos' and x.id<>p_system_id
          and upper(trim(coalesce(x.invoice_prefix,'')))=v_prefix
      ) then
        raise exception 'Terminal invoice prefix is already in use';
      end if;
    end if;
  else
    v_modules:='{}'::text[];
    v_prefix:=d.invoice_prefix;
  end if;
  update public.business_devices set location_id=p_location_id,name=coalesce(nullif(trim(p_name),''),name),allowed_modules=v_modules,invoice_prefix=v_prefix,system_role=v_role,updated_at=now() where id=p_system_id;
  perform private.business_audit_write_v471(p_tenant_id,'system.update','business_device',p_system_id,d.device_code,null::jsonb,jsonb_build_object('from_location_id',v_old_location,'to_location_id',p_location_id,'system_role',v_role,'modules',v_modules,'invoice_prefix',v_prefix));
  return jsonb_build_object('success',true,'system_id',p_system_id,'location_id',p_location_id,'system_role',v_role,'allowed_modules',v_modules,'invoice_prefix',v_prefix);
end $$;
revoke all on function public.tenant_system_update_v471(uuid,uuid,uuid,text,text[],text,text) from public,anon;
grant execute on function public.tenant_system_update_v471(uuid,uuid,uuid,text,text[],text,text) to authenticated;

-- Any existing POS without a prefix receives one now. Historical prefixes are never reused.
do $$
declare r record; v_prefix text;
begin
  for r in
    select d.id,d.tenant_id
    from public.business_devices d
    where d.app_type='pos' and nullif(trim(d.invoice_prefix),'') is null
    order by d.tenant_id,d.created_at,d.id
  loop
    v_prefix:=private.v500_next_pos_invoice_prefix(r.tenant_id);
    update public.business_devices set invoice_prefix=v_prefix,updated_at=now() where id=r.id;
  end loop;
end $$;

create unique index if not exists ux_business_devices_pos_invoice_prefix_v500
  on public.business_devices(tenant_id,upper(invoice_prefix))
  where app_type='pos' and nullif(trim(invoice_prefix),'') is not null;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(212,'5.0.0','Admin POS & Store Creation Hotfix','Automatic POS prefixes with safe pre-transaction editing, repaired POS creation audit path, canonical MAIN location creation, and child-store parent enforcement.')
on conflict(migration_no) do update
set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

create or replace function public.thq_v500_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare miss text[]:='{}';r record;begin
  for r in select * from (values
    ('finance_reconciliation_v500','public.finance_reconciliation_v500(uuid)'),
    ('financial_years_list_v500','public.financial_years_list_v500(uuid)'),
    ('financial_year_close_v500','public.financial_year_close_v500(uuid,uuid)'),
    ('opening_balance_post_v500','public.opening_balance_post_v500(uuid,date,jsonb,text,uuid)'),
    ('finance_voucher_post_v500','public.finance_voucher_post_v500(uuid,uuid,text,date,numeric,uuid,uuid,text,uuid,text,text,text)'),
    ('bank_statement_match_v500','public.bank_statement_match_v500(uuid,uuid,uuid)'),
    ('journal_reverse_v500','public.journal_reverse_v500(uuid,uuid,text)'),
    ('reports_center_data_v500','public.reports_center_data_v500(uuid,text,date,date,uuid,text,integer)'),
    ('dashboard_business_intelligence_v500','public.dashboard_business_intelligence_v500(uuid,uuid,date)'),
    ('business_tasks_list_v500','public.business_tasks_list_v500(uuid,uuid,text)'),
    ('platform_system_create_v471','public.platform_system_create_v471(uuid,uuid,text,text,text,text[],text,text)'),
    ('platform_business_location_save_v42','public.platform_business_location_save_v42(uuid,uuid,uuid,text,text,text,text,integer,text,text,text,text,text,text,text,text,text,text,boolean)'),
    ('platform_next_pos_invoice_prefix_v500','public.platform_next_pos_invoice_prefix_v500(uuid)')
  ) v(name,sig) loop if to_regprocedure(r.sig) is null then miss:=array_append(miss,r.name);end if;end loop;
  if not exists(select 1 from public.thq_schema_releases where migration_no=212 and schema_version='5.0.0') then miss:=array_append(miss,'migration.212');end if;
  if exists(
    select 1 from public.tenants t
    where not exists(select 1 from public.business_locations l where l.tenant_id=t.id and l.hierarchy_role='main_store')
  ) then miss:=array_append(miss,'location.main_store');end if;
  if exists(select 1 from public.business_devices d where d.app_type='pos' and d.status<>'revoked' and nullif(trim(d.invoice_prefix),'') is null) then miss:=array_append(miss,'pos.invoice_prefix');end if;
  return jsonb_build_object('ready',cardinality(miss)=0,'missing',to_jsonb(miss),'schema_version','5.0.0','migration_no',212,'build',26,'capabilities',public.thq_v500_capabilities());
end $$;
grant execute on function public.thq_v500_verify() to authenticated;

create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
select jsonb_build_object('product','THQ ERP','schema_version','5.0.0','migration_no',212,'minimum_app_version','5.0.0','minimum_client_migration',212,'build',26,'release','Admin POS & Store Creation Hotfix','api_version','v1','backward_compatible',true,'verified_by','thq_v500_verify') $$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_api_contract_v480()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
select public.thq_backend_contract_v47()||jsonb_build_object('app_version','5.0.0','build',26,'minimum_migration',212,'capabilities',public.thq_v500_capabilities()) $$;
grant execute on function public.thq_api_contract_v480() to authenticated;

commit;
select 'THQ ERP v5.0.0 migration 212 admin POS/location hotfix applied' as status;
