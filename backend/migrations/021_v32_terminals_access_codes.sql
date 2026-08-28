-- FLEXI ERP V3.2
-- Terminal-specific invoice numbers, per-POS module configuration,
-- user application/location access, and automatic business codes.
begin;

create schema if not exists private;

-- ---------------------------------------------------------------------------
-- 1. POS/Client terminal configuration
-- ---------------------------------------------------------------------------
alter table public.business_devices
  add column if not exists allowed_modules text[] not null default '{}'::text[],
  add column if not exists invoice_prefix text;

-- Existing POS terminals keep the same capabilities they had before V3.2.
update public.business_devices d
set allowed_modules = array_remove(array[
  case when exists(select 1 from public.tenant_modules tm where tm.tenant_id=d.tenant_id and tm.module_key='sales' and tm.enabled) then 'sales' end,
  case when exists(select 1 from public.tenant_modules tm where tm.tenant_id=d.tenant_id and tm.module_key='inventory' and tm.enabled) then 'inventory' end,
  case when exists(select 1 from public.tenant_modules tm where tm.tenant_id=d.tenant_id and tm.module_key='customers' and tm.enabled) then 'customers' end,
  case when exists(select 1 from public.tenant_modules tm where tm.tenant_id=d.tenant_id and tm.module_key='suppliers' and tm.enabled) then 'suppliers' end,
  case when exists(select 1 from public.tenant_modules tm where tm.tenant_id=d.tenant_id and tm.module_key='purchases' and tm.enabled) then 'purchases' end,
  case when exists(select 1 from public.tenant_modules tm where tm.tenant_id=d.tenant_id and tm.module_key='expenses' and tm.enabled) then 'expenses' end,
  case when exists(select 1 from public.tenant_modules tm where tm.tenant_id=d.tenant_id and tm.module_key='restaurant' and tm.enabled) then 'restaurant' end,
  case when exists(select 1 from public.tenant_modules tm where tm.tenant_id=d.tenant_id and tm.module_key='logs' and tm.enabled) then 'logs' end
], null)
where d.app_type='pos' and cardinality(d.allowed_modules)=0;

-- ---------------------------------------------------------------------------
-- 2. User app access and location scope
-- ---------------------------------------------------------------------------
create table if not exists public.business_user_app_access (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  app_key text not null check(app_key in ('client','pos')),
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key(tenant_id,user_id,app_key)
);
alter table public.business_user_app_access enable row level security;
revoke all on public.business_user_app_access from anon,authenticated;

create table if not exists public.business_user_location_access (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete cascade,
  access_level text not null default 'operate' check(access_level in ('view','operate','manage')),
  updated_at timestamptz not null default now(),
  primary key(tenant_id,user_id,location_id)
);
create index if not exists idx_business_user_location_access_user
  on public.business_user_location_access(tenant_id,user_id,location_id);
alter table public.business_user_location_access enable row level security;
revoke all on public.business_user_location_access from anon,authenticated;

create or replace function private.erp_user_is_owner(p_tenant_id uuid,p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public,private,pg_temp
as $$
  select exists(
    select 1
    from public.tenant_memberships tm
    join public.user_roles ur on ur.tenant_id=tm.tenant_id and ur.membership_id=tm.id
    join public.roles r on r.id=ur.role_id
    where tm.tenant_id=p_tenant_id and tm.user_id=p_user_id and tm.status='active' and r.key='owner'
  );
$$;
revoke all on function private.erp_user_is_owner(uuid,uuid) from public;

create or replace function private.erp_user_app_allowed(p_tenant_id uuid,p_app_key text,p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public,private,pg_temp
as $$
  select private.erp_user_is_owner(p_tenant_id,p_user_id)
      or coalesce((select a.enabled from public.business_user_app_access a where a.tenant_id=p_tenant_id and a.user_id=p_user_id and a.app_key=p_app_key), p_app_key='client');
$$;
revoke all on function private.erp_user_app_allowed(uuid,text,uuid) from public;

create or replace function private.erp_user_location_allowed(
  p_tenant_id uuid,p_location_id uuid,p_required text default 'view',p_user_id uuid default auth.uid()
)
returns boolean language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_level text;v_rank int;v_required int;
begin
  if private.erp_user_is_owner(p_tenant_id,p_user_id) then return true;end if;
  select access_level into v_level from public.business_user_location_access
   where tenant_id=p_tenant_id and user_id=p_user_id and location_id=p_location_id;
  if v_level is null then return false;end if;
  v_rank:=case v_level when 'manage' then 3 when 'operate' then 2 else 1 end;
  v_required:=case p_required when 'manage' then 3 when 'operate' then 2 else 1 end;
  return v_rank>=v_required;
end $$;
revoke all on function private.erp_user_location_allowed(uuid,uuid,text,uuid) from public;

-- Existing active members remain able to use Client. POS remains enabled for existing
-- active members to avoid a surprise lockout; owners can tighten this in Client > Team.
insert into public.business_user_app_access(tenant_id,user_id,app_key,enabled)
select tm.tenant_id,tm.user_id,x.app_key,true
from public.tenant_memberships tm cross join (values('client'),('pos')) x(app_key)
where tm.status='active'
on conflict(tenant_id,user_id,app_key) do nothing;

-- Give existing non-owner members MAIN access unless they already have a location scope.
insert into public.business_user_location_access(tenant_id,user_id,location_id,access_level)
select tm.tenant_id,tm.user_id,l.id,'operate'
from public.tenant_memberships tm
join public.business_locations l on l.tenant_id=tm.tenant_id and l.location_code='MAIN'
where tm.status='active'
  and not private.erp_user_is_owner(tm.tenant_id,tm.user_id)
  and not exists(select 1 from public.business_user_location_access a where a.tenant_id=tm.tenant_id and a.user_id=tm.user_id)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 3. Per-terminal document/invoice numbers
-- ---------------------------------------------------------------------------
create table if not exists public.device_document_counters (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  device_id uuid not null references public.business_devices(id) on delete cascade,
  entity_type text not null check(entity_type in ('sale','purchase','expense')),
  last_number bigint not null default 0,
  primary key(tenant_id,device_id,entity_type)
);
alter table public.device_document_counters enable row level security;
revoke all on public.device_document_counters from anon,authenticated;

create table if not exists public.device_document_numbers (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  device_id uuid not null references public.business_devices(id) on delete cascade,
  entity_type text not null check(entity_type in ('sale','purchase','expense')),
  entity_id uuid not null,
  terminal_number text not null,
  created_at timestamptz not null default now(),
  primary key(entity_type,entity_id),
  unique(tenant_id,device_id,entity_type,terminal_number)
);
create index if not exists idx_device_document_numbers_device
  on public.device_document_numbers(tenant_id,device_id,entity_type,created_at desc);
create unique index if not exists ux_device_document_numbers_tenant_number
  on public.device_document_numbers(tenant_id,entity_type,terminal_number);
alter table public.device_document_numbers enable row level security;
revoke all on public.device_document_numbers from anon,authenticated;

create or replace function private.assign_device_document_number(
  p_tenant_id uuid,p_device_id uuid,p_entity_type text,p_entity_id uuid
)
returns text language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_existing text;v_no bigint;v_prefix text;v_kind text;v_number text;
begin
  if p_device_id is null or p_entity_type not in ('sale','purchase','expense') then return null;end if;
  select terminal_number into v_existing from public.device_document_numbers where entity_type=p_entity_type and entity_id=p_entity_id;
  if v_existing is not null then return v_existing;end if;

  select coalesce(nullif(trim(d.invoice_prefix),''),
                  coalesce(nullif(trim(l.invoice_prefix),''),l.location_code)||'-'||d.device_code)
  into v_prefix
  from public.business_devices d join public.business_locations l on l.id=d.location_id
  where d.id=p_device_id and d.tenant_id=p_tenant_id;
  if v_prefix is null then raise exception 'Invalid terminal for document number';end if;

  insert into public.device_document_counters(tenant_id,device_id,entity_type,last_number)
  values(p_tenant_id,p_device_id,p_entity_type,1)
  on conflict(tenant_id,device_id,entity_type)
  do update set last_number=public.device_document_counters.last_number+1
  returning last_number into v_no;

  v_kind:=case p_entity_type when 'sale' then 'INV' when 'purchase' then 'PUR' else 'EXP' end;
  v_number:=upper(v_prefix)||'-'||v_kind||'-'||lpad(v_no::text,6,'0');
  insert into public.device_document_numbers(tenant_id,device_id,entity_type,entity_id,terminal_number)
  values(p_tenant_id,p_device_id,p_entity_type,p_entity_id,v_number)
  on conflict(entity_type,entity_id) do nothing;
  return coalesce((select terminal_number from public.device_document_numbers where entity_type=p_entity_type and entity_id=p_entity_id),v_number);
end $$;
revoke all on function private.assign_device_document_number(uuid,uuid,text,uuid) from public;

-- Origin attachment now validates the requested operational location and allocates
-- both branch-local and terminal-local document numbers.
create or replace function public.document_origin_attach(
  p_tenant_id uuid,p_entity_type text,p_entity_id uuid,p_location_id uuid,p_device_id uuid default null
)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_location_allowed(p_tenant_id,p_location_id,'operate') then raise exception 'You cannot create records for this location';end if;
  if not exists(select 1 from public.business_locations l where l.id=p_location_id and l.tenant_id=p_tenant_id and l.active) then raise exception 'Invalid business location';end if;
  if p_device_id is not null and not exists(select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.status='active') then raise exception 'Invalid device';end if;
  insert into public.document_origins(tenant_id,entity_type,entity_id,location_id,device_id,created_by)
  values(p_tenant_id,p_entity_type,p_entity_id,p_location_id,p_device_id,auth.uid())
  on conflict(entity_type,entity_id) do nothing;
  if p_entity_type in ('sale','purchase','expense') then
    perform private.assign_location_document_number(p_tenant_id,p_location_id,p_entity_type,p_entity_id);
    if p_device_id is not null then perform private.assign_device_document_number(p_tenant_id,p_device_id,p_entity_type,p_entity_id);end if;
  end if;
end $$;
grant execute on function public.document_origin_attach(uuid,text,uuid,uuid,uuid) to authenticated;

create or replace function public.document_origin_get(p_tenant_id uuid,p_entity_type text,p_entity_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v jsonb;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if exists(select 1 from public.document_origins o where o.entity_type=p_entity_type and o.entity_id=p_entity_id and not private.erp_user_location_allowed(p_tenant_id,o.location_id,'view')) then raise exception 'Location access denied';end if;
  select jsonb_build_object(
    'location_id',o.location_id,'location_name',l.name,'location_code',l.location_code,'location_tracking_code',l.tracking_code,
    'local_number',n.local_number,'terminal_number',dn.terminal_number,'invoice_number',coalesce(dn.terminal_number,n.local_number),
    'gstin',l.gstin,'phone',l.phone,'email',l.email,
    'address_line1',l.address_line1,'address_line2',l.address_line2,'city',l.city,'state',l.state,'postal_code',l.postal_code,'country',l.country,
    'device_id',o.device_id,'device_code',d.device_code,'device_name',d.name,'device_invoice_prefix',d.invoice_prefix,'created_at',o.created_at
  ) into v
  from public.document_origins o
  left join public.business_locations l on l.id=o.location_id
  left join public.business_devices d on d.id=o.device_id
  left join public.location_document_numbers n on n.entity_type=o.entity_type and n.entity_id=o.entity_id
  left join public.device_document_numbers dn on dn.entity_type=o.entity_type and dn.entity_id=o.entity_id
  where o.tenant_id=p_tenant_id and o.entity_type=p_entity_type and o.entity_id=p_entity_id;
  return v;
end $$;
grant execute on function public.document_origin_get(uuid,text,uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Automatic sequential SKU generator
-- ---------------------------------------------------------------------------
create table if not exists public.tenant_code_counters (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code_key text not null,
  last_number bigint not null default 0,
  primary key(tenant_id,code_key)
);
alter table public.tenant_code_counters enable row level security;
revoke all on public.tenant_code_counters from anon,authenticated;

create or replace function public.inventory_next_sku(p_tenant_id uuid)
returns text language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_no bigint;v_sku text;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  loop
    insert into public.tenant_code_counters(tenant_id,code_key,last_number) values(p_tenant_id,'sku',1)
    on conflict(tenant_id,code_key) do update set last_number=public.tenant_code_counters.last_number+1
    returning last_number into v_no;
    v_sku:='SKU-'||lpad(v_no::text,6,'0');
    exit when not exists(select 1 from public.product_variants where tenant_id=p_tenant_id and upper(sku)=upper(v_sku));
  end loop;
  return v_sku;
end $$;
grant execute on function public.inventory_next_sku(uuid) to authenticated;

-- Expose immutable tracking_code as the friendly Product/Customer/Supplier ID.
create or replace function public.entity_public_id_get(p_tenant_id uuid,p_entity_type text,p_entity_id uuid)
returns text language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v text;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  case p_entity_type
    when 'product' then select tracking_code into v from public.products where tenant_id=p_tenant_id and id=p_entity_id;
    when 'customer' then select tracking_code into v from public.customers where tenant_id=p_tenant_id and id=p_entity_id;
    when 'supplier' then select tracking_code into v from public.suppliers where tenant_id=p_tenant_id and id=p_entity_id;
    when 'sale' then select tracking_code into v from public.sales where tenant_id=p_tenant_id and id=p_entity_id;
    when 'purchase' then select tracking_code into v from public.purchases where tenant_id=p_tenant_id and id=p_entity_id;
    else raise exception 'Unsupported entity type';
  end case;
  return v;
end $$;
grant execute on function public.entity_public_id_get(uuid,text,uuid) to authenticated;

commit;
select 'V3.2 terminals/access/codes ready' as status;
