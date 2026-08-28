-- FLEXI ERP V3.1 - Locations, child stores, terminals and one-time activation.
create extension if not exists pgcrypto;
create schema if not exists private;

create table if not exists public.business_locations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  parent_location_id uuid references public.business_locations(id) on delete set null,
  location_code text not null,
  tracking_code text,
  name text not null,
  location_type text not null default 'branch'
    check(location_type in ('head_office','branch','store','warehouse','restaurant','kitchen','service_base')),
  phone text,
  email text,
  gstin text,
  address_line1 text,
  address_line2 text,
  city text,
  state text,
  postal_code text,
  country text not null default 'India',
  invoice_prefix text,
  inventory_location_id uuid,
  active boolean not null default true,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,location_code)
);
create unique index if not exists ux_business_locations_tracking
  on public.business_locations(tenant_id,tracking_code) where tracking_code is not null;
create index if not exists idx_business_locations_tenant on public.business_locations(tenant_id,active,name);
alter table public.business_locations enable row level security;
revoke all on table public.business_locations from anon,authenticated;

-- Seed one default location for existing tenants.
insert into public.business_locations(
  tenant_id,location_code,name,location_type,tracking_code
)
select
  t.id,
  'MAIN',
  t.name || ' - Main',
  'head_office',
  private.next_tracking_code(t.id,'business_locations','LOC')
from public.tenants t
where not exists(select 1 from public.business_locations l where l.tenant_id=t.id)
on conflict(tenant_id,location_code) do nothing;

create or replace function private.business_location_tracking()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if new.tracking_code is null or trim(new.tracking_code)='' then
    new.tracking_code:=private.next_tracking_code(new.tenant_id,'business_locations','LOC');
  end if;
  if new.location_code is null or trim(new.location_code)='' then
    new.location_code:='LOC-'||upper(substr(replace(new.id::text,'-',''),1,6));
  end if;
  return new;
end $$;
revoke all on function private.business_location_tracking() from public;
drop trigger if exists trg_business_location_tracking on public.business_locations;
create trigger trg_business_location_tracking before insert on public.business_locations
for each row execute function private.business_location_tracking();

drop trigger if exists trg_business_locations_tracking_immutable on public.business_locations;
create trigger trg_business_locations_tracking_immutable
before update of tracking_code on public.business_locations
for each row execute function private.prevent_tracking_code_change();

create table if not exists public.business_devices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete cascade,
  device_code text not null,
  tracking_code text,
  name text not null,
  app_type text not null check(app_type in ('client','pos')),
  platform_hint text,
  status text not null default 'pending' check(status in ('pending','active','revoked')),
  activation_hash text,
  activation_expires_at timestamptz,
  activated_at timestamptz,
  installation_id text,
  device_secret_hash text,
  last_seen_at timestamptz,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,device_code)
);
create unique index if not exists ux_business_devices_tracking
  on public.business_devices(tenant_id,tracking_code) where tracking_code is not null;
create unique index if not exists ux_business_devices_installation
  on public.business_devices(installation_id) where installation_id is not null and status='active';
create index if not exists idx_business_devices_tenant on public.business_devices(tenant_id,location_id,status);
alter table public.business_devices enable row level security;
revoke all on table public.business_devices from anon,authenticated;

create or replace function private.business_device_tracking()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if new.tracking_code is null or trim(new.tracking_code)='' then
    new.tracking_code:=private.next_tracking_code(new.tenant_id,'business_devices','DEV');
  end if;
  if new.device_code is null or trim(new.device_code)='' then
    new.device_code:=upper(new.app_type)||'-'||upper(substr(replace(new.id::text,'-',''),1,6));
  end if;
  return new;
end $$;
revoke all on function private.business_device_tracking() from public;
drop trigger if exists trg_business_device_tracking on public.business_devices;
create trigger trg_business_device_tracking before insert on public.business_devices
for each row execute function private.business_device_tracking();

drop trigger if exists trg_business_devices_tracking_immutable on public.business_devices;
create trigger trg_business_devices_tracking_immutable
before update of tracking_code on public.business_devices
for each row execute function private.prevent_tracking_code_change();

-- Generic origin link keeps existing transaction engines untouched.
create table if not exists public.document_origins (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  entity_type text not null check(entity_type in ('sale','purchase','expense','restaurant_order','production_run','service_job')),
  entity_id uuid not null,
  location_id uuid references public.business_locations(id) on delete set null,
  device_id uuid references public.business_devices(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key(entity_type,entity_id)
);
create index if not exists idx_document_origins_tenant_location
  on public.document_origins(tenant_id,location_id,entity_type,created_at desc);
alter table public.document_origins enable row level security;
revoke all on table public.document_origins from anon,authenticated;

create or replace function public.document_origin_attach(
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_location_id uuid,
  p_device_id uuid default null
)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not exists(select 1 from public.business_locations l where l.id=p_location_id and l.tenant_id=p_tenant_id and l.active) then
    raise exception 'Invalid business location';
  end if;
  if p_device_id is not null and not exists(
    select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.location_id=p_location_id and d.status='active'
  ) then raise exception 'Invalid device'; end if;
  insert into public.document_origins(tenant_id,entity_type,entity_id,location_id,device_id,created_by)
  values(p_tenant_id,p_entity_type,p_entity_id,p_location_id,p_device_id,auth.uid())
  on conflict(entity_type,entity_id) do nothing;
end $$;
grant execute on function public.document_origin_attach(uuid,text,uuid,uuid,uuid) to authenticated;

-- Platform admin location/device management.
create or replace function public.platform_business_locations_list(p_tenant_id uuid)
returns setof public.business_locations language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required'; end if;
  return query select * from public.business_locations where tenant_id=p_tenant_id order by active desc,name;
end $$;
grant execute on function public.platform_business_locations_list(uuid) to authenticated;

create or replace function public.platform_business_location_save(
  p_tenant_id uuid,p_location_id uuid,p_parent_location_id uuid,p_location_code text,p_name text,p_location_type text,
  p_phone text,p_email text,p_gstin text,p_address_line1 text,p_address_line2 text,p_city text,p_state text,p_postal_code text,p_country text,p_invoice_prefix text,p_active boolean
)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid; begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required'; end if;
  if trim(coalesce(p_name,''))='' then raise exception 'Location name required'; end if;
  if p_location_id is null then
    insert into public.business_locations(tenant_id,parent_location_id,location_code,name,location_type,phone,email,gstin,address_line1,address_line2,city,state,postal_code,country,invoice_prefix,active)
    values(p_tenant_id,p_parent_location_id,upper(trim(p_location_code)),trim(p_name),p_location_type,nullif(trim(p_phone),''),nullif(trim(p_email),''),nullif(trim(p_gstin),''),nullif(trim(p_address_line1),''),nullif(trim(p_address_line2),''),nullif(trim(p_city),''),nullif(trim(p_state),''),nullif(trim(p_postal_code),''),coalesce(nullif(trim(p_country),''),'India'),nullif(trim(p_invoice_prefix),''),coalesce(p_active,true))
    returning id into v_id;
  else
    update public.business_locations set parent_location_id=p_parent_location_id,location_code=upper(trim(p_location_code)),name=trim(p_name),location_type=p_location_type,phone=nullif(trim(p_phone),''),email=nullif(trim(p_email),''),gstin=nullif(trim(p_gstin),''),address_line1=nullif(trim(p_address_line1),''),address_line2=nullif(trim(p_address_line2),''),city=nullif(trim(p_city),''),state=nullif(trim(p_state),''),postal_code=nullif(trim(p_postal_code),''),country=coalesce(nullif(trim(p_country),''),'India'),invoice_prefix=nullif(trim(p_invoice_prefix),''),active=coalesce(p_active,true),updated_at=now()
    where id=p_location_id and tenant_id=p_tenant_id returning id into v_id;
    if v_id is null then raise exception 'Location not found'; end if;
  end if;
  perform private.platform_audit_write('location.save','business_location',v_id::text,p_tenant_id,jsonb_build_object('name',p_name,'code',p_location_code));
  return v_id;
end $$;
grant execute on function public.platform_business_location_save(uuid,uuid,uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,boolean) to authenticated;

create or replace function public.platform_business_devices_list(p_tenant_id uuid)
returns table(
  id uuid,tenant_id uuid,location_id uuid,location_name text,device_code text,tracking_code text,name text,app_type text,platform_hint text,status text,activated_at timestamptz,last_seen_at timestamptz,created_at timestamptz
) language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required'; end if;
  return query select d.id,d.tenant_id,d.location_id,l.name,d.device_code,d.tracking_code,d.name,d.app_type,d.platform_hint,d.status,d.activated_at,d.last_seen_at,d.created_at
  from public.business_devices d join public.business_locations l on l.id=d.location_id where d.tenant_id=p_tenant_id order by d.created_at desc;
end $$;
grant execute on function public.platform_business_devices_list(uuid) to authenticated;

create or replace function public.platform_device_issue_activation(
  p_tenant_id uuid,p_location_id uuid,p_name text,p_app_type text,p_platform_hint text default null
)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare
  v_id uuid:=gen_random_uuid(); v_code text; v_device_code text; v_exp timestamptz:=now()+interval '24 hours';
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required'; end if;
  if p_app_type not in ('client','pos') then raise exception 'Invalid app type'; end if;
  if not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active) then raise exception 'Invalid location'; end if;
  v_code:=upper(substr(encode(gen_random_bytes(8),'hex'),1,12));
  v_device_code:=upper(p_app_type)||'-'||upper(substr(replace(v_id::text,'-',''),1,6));
  insert into public.business_devices(id,tenant_id,location_id,device_code,name,app_type,platform_hint,status,activation_hash,activation_expires_at)
  values(v_id,p_tenant_id,p_location_id,v_device_code,trim(p_name),p_app_type,nullif(trim(p_platform_hint),''),'pending',encode(digest(v_code,'sha256'),'hex'),v_exp);
  perform private.platform_audit_write('device.activation_issue','business_device',v_id::text,p_tenant_id,jsonb_build_object('device_code',v_device_code,'app_type',p_app_type,'location_id',p_location_id));
  return jsonb_build_object('device_id',v_id,'device_code',v_device_code,'activation_code',v_code,'expires_at',v_exp);
end $$;
grant execute on function public.platform_device_issue_activation(uuid,uuid,text,text,text) to authenticated;

create or replace function public.platform_device_revoke(p_tenant_id uuid,p_device_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required'; end if;
  update public.business_devices set status='revoked',activation_hash=null,device_secret_hash=null,updated_at=now() where id=p_device_id and tenant_id=p_tenant_id;
  perform private.platform_audit_write('device.revoke','business_device',p_device_id::text,p_tenant_id,'{}'::jsonb);
end $$;
grant execute on function public.platform_device_revoke(uuid,uuid) to authenticated;


-- Existing documents predate device/location tracking. Attribute them to the tenant's MAIN location.
insert into public.document_origins(tenant_id,entity_type,entity_id,location_id,created_by,created_at)
select s.tenant_id,'sale',s.id,l.id,null,s.created_at
from public.sales s
join public.business_locations l on l.tenant_id=s.tenant_id and l.location_code='MAIN'
where not exists(select 1 from public.document_origins o where o.entity_type='sale' and o.entity_id=s.id)
on conflict(entity_type,entity_id) do nothing;

insert into public.document_origins(tenant_id,entity_type,entity_id,location_id,created_by,created_at)
select p.tenant_id,'purchase',p.id,l.id,null,p.created_at
from public.purchases p
join public.business_locations l on l.tenant_id=p.tenant_id and l.location_code='MAIN'
where not exists(select 1 from public.document_origins o where o.entity_type='purchase' and o.entity_id=p.id)
on conflict(entity_type,entity_id) do nothing;

insert into public.document_origins(tenant_id,entity_type,entity_id,location_id,created_by,created_at)
select e.tenant_id,'expense',e.id,l.id,null,e.created_at
from public.expenses e
join public.business_locations l on l.tenant_id=e.tenant_id and l.location_code='MAIN'
where not exists(select 1 from public.document_origins o where o.entity_type='expense' and o.entity_id=e.id)
on conflict(entity_type,entity_id) do nothing;

-- Per-location document numbering. This does not replace the immutable core SAL/PUR/EXP
-- references; it provides a branch-specific printed/billing number.
create table if not exists public.location_document_counters (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete cascade,
  entity_type text not null check(entity_type in ('sale','purchase','expense')),
  last_number bigint not null default 0,
  primary key(tenant_id,location_id,entity_type)
);
alter table public.location_document_counters enable row level security;
revoke all on public.location_document_counters from anon,authenticated;

create table if not exists public.location_document_numbers (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete cascade,
  entity_type text not null check(entity_type in ('sale','purchase','expense')),
  entity_id uuid not null,
  local_number text not null,
  created_at timestamptz not null default now(),
  primary key(entity_type,entity_id),
  unique(tenant_id,location_id,entity_type,local_number)
);
create index if not exists idx_location_document_numbers_lookup
  on public.location_document_numbers(tenant_id,location_id,entity_type,created_at desc);
alter table public.location_document_numbers enable row level security;
revoke all on public.location_document_numbers from anon,authenticated;

create or replace function private.assign_location_document_number(
  p_tenant_id uuid,p_location_id uuid,p_entity_type text,p_entity_id uuid
)
returns text language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_existing text;v_no bigint;v_prefix text;v_kind text;v_number text;
begin
  select local_number into v_existing from public.location_document_numbers
  where entity_type=p_entity_type and entity_id=p_entity_id;
  if v_existing is not null then return v_existing; end if;
  if p_entity_type not in ('sale','purchase','expense') then return null; end if;

  select coalesce(nullif(trim(invoice_prefix),''),location_code)
  into v_prefix from public.business_locations
  where id=p_location_id and tenant_id=p_tenant_id;
  if v_prefix is null then raise exception 'Invalid location for document number'; end if;

  insert into public.location_document_counters(tenant_id,location_id,entity_type,last_number)
  values(p_tenant_id,p_location_id,p_entity_type,1)
  on conflict(tenant_id,location_id,entity_type)
  do update set last_number=public.location_document_counters.last_number+1
  returning last_number into v_no;

  v_kind:=case p_entity_type when 'sale' then 'INV' when 'purchase' then 'PUR' else 'EXP' end;
  v_number:=upper(v_prefix)||'-'||v_kind||'-'||lpad(v_no::text,6,'0');
  insert into public.location_document_numbers(tenant_id,location_id,entity_type,entity_id,local_number)
  values(p_tenant_id,p_location_id,p_entity_type,p_entity_id,v_number)
  on conflict(entity_type,entity_id) do nothing;
  return coalesce((select local_number from public.location_document_numbers where entity_type=p_entity_type and entity_id=p_entity_id),v_number);
end $$;
revoke all on function private.assign_location_document_number(uuid,uuid,text,uuid) from public;

-- Redefine origin attach to also allocate a branch-local printable number.
create or replace function public.document_origin_attach(
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_location_id uuid,
  p_device_id uuid default null
)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not exists(select 1 from public.business_locations l where l.id=p_location_id and l.tenant_id=p_tenant_id and l.active) then
    raise exception 'Invalid business location';
  end if;
  if p_device_id is not null and not exists(
    select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.location_id=p_location_id and d.status='active'
  ) then raise exception 'Invalid device'; end if;
  insert into public.document_origins(tenant_id,entity_type,entity_id,location_id,device_id,created_by)
  values(p_tenant_id,p_entity_type,p_entity_id,p_location_id,p_device_id,auth.uid())
  on conflict(entity_type,entity_id) do nothing;
  if p_entity_type in ('sale','purchase','expense') then
    perform private.assign_location_document_number(p_tenant_id,p_location_id,p_entity_type,p_entity_id);
  end if;
end $$;
grant execute on function public.document_origin_attach(uuid,text,uuid,uuid,uuid) to authenticated;

-- Give historical documents attributed to MAIN a branch-local number too.
do $$
declare r record;
begin
  for r in select tenant_id,entity_type,entity_id,location_id from public.document_origins
           where entity_type in ('sale','purchase','expense') and location_id is not null
  loop
    perform private.assign_location_document_number(r.tenant_id,r.location_id,r.entity_type,r.entity_id);
  end loop;
end $$;

select 'V3.1 locations/devices ready' as status;
