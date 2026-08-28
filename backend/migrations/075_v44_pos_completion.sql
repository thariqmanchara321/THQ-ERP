-- FLEXI ERP V4.4
-- POS completion: printer routing, KOT profiles, cash drawer metadata,
-- device preferences and server-side held invoices.
begin;

alter table public.printer_profiles
  add column if not exists purpose text not null default 'invoice',
  add column if not exists route_name text,
  add column if not exists cash_drawer_enabled boolean not null default false,
  add column if not exists cash_drawer_command text,
  add column if not exists is_default boolean not null default false,
  add column if not exists updated_at timestamptz not null default now();

do $$ begin
  if not exists(
    select 1 from pg_constraint where conname='printer_profiles_purpose_check'
  ) then
    alter table public.printer_profiles add constraint printer_profiles_purpose_check
      check(purpose in('invoice','kot','report','label'));
  end if;
end $$;

create index if not exists idx_printer_profiles_device_purpose
  on public.printer_profiles(tenant_id,device_id,purpose,active);

create table if not exists public.pos_device_preferences(
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  device_id uuid not null references public.business_devices(id) on delete cascade,
  settings jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  primary key(tenant_id,device_id)
);

create table if not exists public.pos_held_sales(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete cascade,
  device_id uuid not null references public.business_devices(id) on delete cascade,
  hold_code text not null,
  customer_id uuid references public.customers(id) on delete set null,
  label text,
  state jsonb not null default '{}'::jsonb,
  held_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,hold_code)
);
create index if not exists idx_pos_held_sales_device on public.pos_held_sales(tenant_id,device_id,created_at desc);

alter table public.pos_device_preferences enable row level security;
alter table public.pos_held_sales enable row level security;
revoke all on public.pos_device_preferences,public.pos_held_sales from anon,authenticated;

create or replace function public.pos_printer_profiles_list_v44(p_tenant_id uuid,p_device_id uuid)
returns setof public.printer_profiles
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_location uuid;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select location_id into v_location from public.business_devices
  where id=p_device_id and tenant_id=p_tenant_id and status='active';
  if v_location is null then raise exception 'Active POS terminal not found';end if;
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_user_location_allowed(p_tenant_id,v_location,'view') then
    raise exception 'Terminal access denied';
  end if;
  return query
    select p.* from public.printer_profiles p
    where p.tenant_id=p_tenant_id and p.active
      and (p.device_id=p_device_id or (p.device_id is null and (p.location_id=v_location or p.location_id is null)))
    order by p.purpose,p.is_default desc,p.name;
end $$;
grant execute on function public.pos_printer_profiles_list_v44(uuid,uuid) to authenticated;

create or replace function public.pos_printer_profile_save_v44(
  p_tenant_id uuid,p_device_id uuid,p_profile_id uuid,p_name text,p_purpose text,
  p_paper_size text,p_printer_name text,p_route_name text,p_copies integer,
  p_auto_print boolean,p_cash_drawer_enabled boolean,p_cash_drawer_command text,
  p_is_default boolean,p_active boolean,p_settings jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_id uuid:=coalesce(p_profile_id,gen_random_uuid());v_location uuid;v_purpose text:=lower(coalesce(p_purpose,'invoice'));
begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'settings.manage') then
    raise exception 'Settings permission required';
  end if;
  select location_id into v_location from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active';
  if v_location is null then raise exception 'Active terminal not found';end if;
  if v_purpose not in('invoice','kot','report','label') then raise exception 'Invalid printer purpose';end if;
  if lower(coalesce(p_paper_size,'80mm')) not in('58mm','80mm','a4') then raise exception 'Invalid paper size';end if;
  if trim(coalesce(p_name,''))='' then raise exception 'Printer profile name is required';end if;

  if coalesce(p_is_default,false) then
    update public.printer_profiles set is_default=false,updated_at=now()
    where tenant_id=p_tenant_id and device_id=p_device_id and purpose=v_purpose and id<>v_id;
  end if;

  insert into public.printer_profiles(
    id,tenant_id,location_id,device_id,name,paper_size,printer_name,copies,auto_print,active,settings,
    purpose,route_name,cash_drawer_enabled,cash_drawer_command,is_default,updated_at
  ) values(
    v_id,p_tenant_id,v_location,p_device_id,trim(p_name),lower(coalesce(p_paper_size,'80mm')),
    nullif(trim(coalesce(p_printer_name,'')),''),greatest(1,least(coalesce(p_copies,1),10)),coalesce(p_auto_print,false),coalesce(p_active,true),coalesce(p_settings,'{}'::jsonb),
    v_purpose,nullif(trim(coalesce(p_route_name,'')),''),coalesce(p_cash_drawer_enabled,false),nullif(trim(coalesce(p_cash_drawer_command,'')),''),coalesce(p_is_default,false),now()
  ) on conflict(id) do update set
    name=excluded.name,paper_size=excluded.paper_size,printer_name=excluded.printer_name,copies=excluded.copies,
    auto_print=excluded.auto_print,active=excluded.active,settings=excluded.settings,purpose=excluded.purpose,
    route_name=excluded.route_name,cash_drawer_enabled=excluded.cash_drawer_enabled,
    cash_drawer_command=excluded.cash_drawer_command,is_default=excluded.is_default,updated_at=now();
  return v_id;
end $$;
grant execute on function public.pos_printer_profile_save_v44(uuid,uuid,uuid,text,text,text,text,text,integer,boolean,boolean,text,boolean,boolean,jsonb) to authenticated;

create or replace function public.pos_device_preferences_get_v44(p_tenant_id uuid,p_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare v jsonb;v_location uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select location_id into v_location from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active';
  if v_location is null then raise exception 'Terminal not found';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_user_location_allowed(p_tenant_id,v_location,'view') then raise exception 'Terminal access denied';end if;
  select settings into v from public.pos_device_preferences where tenant_id=p_tenant_id and device_id=p_device_id;
  return coalesce(v,'{}'::jsonb);
end $$;
grant execute on function public.pos_device_preferences_get_v44(uuid,uuid) to authenticated;

create or replace function public.pos_device_preferences_set_v44(p_tenant_id uuid,p_device_id uuid,p_settings jsonb)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'settings.manage') then raise exception 'Settings permission required';end if;
  if not exists(select 1 from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active') then raise exception 'Terminal not found';end if;
  insert into public.pos_device_preferences(tenant_id,device_id,settings,updated_at,updated_by)
  values(p_tenant_id,p_device_id,coalesce(p_settings,'{}'::jsonb),now(),auth.uid())
  on conflict(tenant_id,device_id) do update set settings=excluded.settings,updated_at=now(),updated_by=auth.uid();
end $$;
grant execute on function public.pos_device_preferences_set_v44(uuid,uuid,jsonb) to authenticated;

create sequence if not exists public.pos_hold_code_seq;

create or replace function public.pos_hold_sale_v44(
  p_tenant_id uuid,p_device_id uuid,p_customer_id uuid,p_label text,p_state jsonb
) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_location uuid;v_id uuid:=gen_random_uuid();v_code text;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'pos.use') and not private.erp_has_permission(p_tenant_id,'sales.manage') then raise exception 'POS permission required';end if;
  select location_id into v_location from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active';
  if v_location is null then raise exception 'Active terminal not found';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_user_location_allowed(p_tenant_id,v_location,'operate') then raise exception 'Terminal location access denied';end if;
  if p_customer_id is not null and not exists(select 1 from public.customers where id=p_customer_id and tenant_id=p_tenant_id) then raise exception 'Customer does not belong to this business';end if;
  if coalesce(jsonb_array_length(coalesce(p_state->'items','[]'::jsonb)),0)=0 then raise exception 'Cannot hold an empty sale';end if;
  v_code:='HOLD-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.pos_hold_code_seq')::text,5,'0');
  insert into public.pos_held_sales(id,tenant_id,location_id,device_id,hold_code,customer_id,label,state,held_by)
  values(v_id,p_tenant_id,v_location,p_device_id,v_code,p_customer_id,nullif(trim(coalesce(p_label,'')),''),coalesce(p_state,'{}'::jsonb),auth.uid());
  return jsonb_build_object('id',v_id,'hold_code',v_code);
end $$;
grant execute on function public.pos_hold_sale_v44(uuid,uuid,uuid,text,jsonb) to authenticated;

create or replace function public.pos_held_sales_list_v44(p_tenant_id uuid,p_device_id uuid)
returns table(id uuid,hold_code text,label text,customer_id uuid,customer_name text,item_count integer,total numeric,held_by text,created_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare v_location uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select location_id into v_location from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active';
  if v_location is null then raise exception 'Active terminal not found';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_user_location_allowed(p_tenant_id,v_location,'view') then raise exception 'Terminal access denied';end if;
  return query
  select h.id,h.hold_code,h.label,h.customer_id,c.name::text,
    coalesce(jsonb_array_length(h.state->'items'),0),
    coalesce((h.state->>'total')::numeric,0),coalesce(ul.username::text,''),h.created_at
  from public.pos_held_sales h
  left join public.customers c on c.id=h.customer_id
  left join public.user_login_names ul on ul.user_id=h.held_by
  where h.tenant_id=p_tenant_id and h.device_id=p_device_id
  order by h.created_at desc;
end $$;
grant execute on function public.pos_held_sales_list_v44(uuid,uuid) to authenticated;

create or replace function public.pos_held_sale_get_v44(p_tenant_id uuid,p_device_id uuid,p_hold_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare v jsonb;v_location uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select location_id into v_location from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active';
  if v_location is null then raise exception 'Active terminal not found';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_user_location_allowed(p_tenant_id,v_location,'view') then raise exception 'Terminal access denied';end if;
  select jsonb_build_object('id',h.id,'hold_code',h.hold_code,'label',h.label,'customer_id',h.customer_id,'state',h.state,'created_at',h.created_at)
  into v from public.pos_held_sales h where h.id=p_hold_id and h.tenant_id=p_tenant_id and h.device_id=p_device_id;
  if v is null then raise exception 'Held sale not found';end if;
  return v;
end $$;
grant execute on function public.pos_held_sale_get_v44(uuid,uuid,uuid) to authenticated;

create or replace function public.pos_held_sale_delete_v44(p_tenant_id uuid,p_device_id uuid,p_hold_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_location uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select location_id into v_location from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active';
  if v_location is null then raise exception 'Active terminal not found';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_user_location_allowed(p_tenant_id,v_location,'operate') then raise exception 'Terminal access denied';end if;
  delete from public.pos_held_sales where id=p_hold_id and tenant_id=p_tenant_id and device_id=p_device_id;
end $$;
grant execute on function public.pos_held_sale_delete_v44(uuid,uuid,uuid) to authenticated;

commit;
select 'Flexi ERP V4.4 POS completion ready' as status;
