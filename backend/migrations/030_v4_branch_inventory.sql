-- FLEXI ERP V4
-- True branch product assignment + physical stock ledger layered safely over the proven global stock engine.
begin;

create schema if not exists private;

create table if not exists public.location_product_settings (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  active boolean not null default true,
  selling_price numeric,
  wholesale_price numeric,
  mrp numeric,
  minimum_selling_price numeric,
  reorder_level numeric,
  max_stock numeric,
  rack_code text,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, location_id, variant_id)
);
create index if not exists idx_location_product_settings_variant
  on public.location_product_settings(tenant_id,variant_id,active);
alter table public.location_product_settings enable row level security;
revoke all on table public.location_product_settings from anon,authenticated;

create table if not exists public.location_stock_balances (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  quantity numeric not null default 0,
  reserved_quantity numeric not null default 0,
  damaged_quantity numeric not null default 0,
  quarantine_quantity numeric not null default 0,
  average_cost numeric not null default 0,
  updated_at timestamptz not null default now(),
  primary key (tenant_id, location_id, variant_id),
  check (reserved_quantity >= 0),
  check (damaged_quantity >= 0),
  check (quarantine_quantity >= 0)
);
create index if not exists idx_location_stock_balances_variant
  on public.location_stock_balances(tenant_id,variant_id,location_id);
alter table public.location_stock_balances enable row level security;
revoke all on table public.location_stock_balances from anon,authenticated;

create table if not exists public.location_stock_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  movement_type text not null check (movement_type in (
    'opening','purchase','sale','sale_return','purchase_return','adjustment_in','adjustment_out',
    'transfer_in','transfer_out','stock_count','damage','damage_restore','quarantine_in','quarantine_out',
    'production_in','production_out','reservation','reservation_release'
  )),
  quantity_delta numeric not null,
  unit_cost numeric,
  reference_type text,
  reference_id uuid,
  reference_number text,
  note text,
  created_by uuid references auth.users(id) on delete set null,
  device_id uuid references public.business_devices(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists idx_location_stock_movements_lookup
  on public.location_stock_movements(tenant_id,location_id,variant_id,created_at desc);
alter table public.location_stock_movements enable row level security;
revoke all on table public.location_stock_movements from anon,authenticated;

-- Existing products/history belong to MAIN unless explicitly distributed later.
do $$
declare r record; v_main uuid;
begin
  for r in select t.id tenant_id from public.tenants t loop
    select id into v_main from public.business_locations
    where tenant_id=r.tenant_id and active
    order by case when location_code='MAIN' then 0 else 1 end, created_at
    limit 1;
    if v_main is null then continue; end if;

    insert into public.location_product_settings(tenant_id,location_id,variant_id,active,selling_price,reorder_level)
    select pv.tenant_id,v_main,pv.id,true,pv.selling_price,pv.reorder_level
    from public.product_variants pv
    where pv.tenant_id=r.tenant_id
    on conflict(tenant_id,location_id,variant_id) do nothing;

    insert into public.location_stock_balances(tenant_id,location_id,variant_id,quantity,average_cost)
    select sb.tenant_id,v_main,sb.variant_id,sum(sb.quantity),coalesce(max(pv.cost_price),0)
    from public.stock_balances sb
    join public.product_variants pv on pv.id=sb.variant_id and pv.tenant_id=sb.tenant_id
    where sb.tenant_id=r.tenant_id
    group by sb.tenant_id,sb.variant_id
    on conflict(tenant_id,location_id,variant_id) do nothing;
  end loop;
end $$;

create or replace function private.v4_location_access(
  p_tenant_id uuid,p_location_id uuid,p_required text default 'view'
) returns void
language plpgsql stable security definer
set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active) then
    raise exception 'Invalid or inactive location';
  end if;
  if private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.manage_all') then return; end if;
  if lower(coalesce(p_required,'view'))='view' and private.erp_has_permission(p_tenant_id,'locations.view_all') then return; end if;
  if not private.erp_user_location_allowed(p_tenant_id,p_location_id,p_required) then
    raise exception 'Location % access denied',p_required;
  end if;
end $$;
revoke all on function private.v4_location_access(uuid,uuid,text) from public;

create or replace function private.v4_location_stock_apply(
  p_tenant_id uuid,p_location_id uuid,p_variant_id uuid,p_delta numeric,
  p_movement_type text,p_reference_type text default null,p_reference_id uuid default null,
  p_reference_number text default null,p_note text default null,p_device_id uuid default null,
  p_allow_negative boolean default false
) returns numeric
language plpgsql security definer
set search_path=public,private,pg_temp
as $$
declare v_before numeric:=0;v_after numeric;v_cost numeric:=0;
begin
  select quantity into v_before from public.location_stock_balances
  where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=p_variant_id
  for update;
  v_before:=coalesce(v_before,0);
  v_after:=v_before+coalesce(p_delta,0);
  if not p_allow_negative and v_after < 0 then
    raise exception 'Insufficient stock at selected store. Available: %, requested change: %',v_before,p_delta;
  end if;
  select coalesce(cost_price,0) into v_cost from public.product_variants where id=p_variant_id and tenant_id=p_tenant_id;
  insert into public.location_product_settings(tenant_id,location_id,variant_id,active)
  values(p_tenant_id,p_location_id,p_variant_id,true)
  on conflict(tenant_id,location_id,variant_id) do nothing;
  insert into public.location_stock_balances(tenant_id,location_id,variant_id,quantity,average_cost,updated_at)
  values(p_tenant_id,p_location_id,p_variant_id,v_after,v_cost,now())
  on conflict(tenant_id,location_id,variant_id) do update
    set quantity=excluded.quantity,average_cost=case when excluded.average_cost<>0 then excluded.average_cost else public.location_stock_balances.average_cost end,updated_at=now();
  insert into public.location_stock_movements(tenant_id,location_id,variant_id,movement_type,quantity_delta,unit_cost,reference_type,reference_id,reference_number,note,created_by,device_id)
  values(p_tenant_id,p_location_id,p_variant_id,p_movement_type,p_delta,v_cost,p_reference_type,p_reference_id,p_reference_number,nullif(trim(coalesce(p_note,'')),''),auth.uid(),p_device_id);
  return v_after;
end $$;
revoke all on function private.v4_location_stock_apply(uuid,uuid,uuid,numeric,text,text,uuid,text,text,uuid,boolean) from public;

create or replace function public.inventory_location_assign_v4(
  p_tenant_id uuid,p_location_id uuid,p_variant_id uuid,p_active boolean default true,
  p_selling_price numeric default null,p_reorder_level numeric default null,p_rack_code text default null
) returns void
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  perform private.v4_location_access(p_tenant_id,p_location_id,'manage');
  if not private.erp_has_permission(p_tenant_id,'inventory.manage') and not private.erp_user_is_owner(p_tenant_id) then
    raise exception 'Inventory manage permission required';
  end if;
  if not exists(select 1 from public.product_variants where id=p_variant_id and tenant_id=p_tenant_id) then raise exception 'Product not found'; end if;
  insert into public.location_product_settings(tenant_id,location_id,variant_id,active,selling_price,reorder_level,rack_code,updated_at)
  values(p_tenant_id,p_location_id,p_variant_id,coalesce(p_active,true),p_selling_price,p_reorder_level,nullif(trim(coalesce(p_rack_code,'')),''),now())
  on conflict(tenant_id,location_id,variant_id) do update set
    active=excluded.active,
    selling_price=coalesce(excluded.selling_price,public.location_product_settings.selling_price),
    reorder_level=coalesce(excluded.reorder_level,public.location_product_settings.reorder_level),
    rack_code=coalesce(excluded.rack_code,public.location_product_settings.rack_code),
    updated_at=now();
  insert into public.location_stock_balances(tenant_id,location_id,variant_id) values(p_tenant_id,p_location_id,p_variant_id)
  on conflict do nothing;
end $$;
grant execute on function public.inventory_location_assign_v4(uuid,uuid,uuid,boolean,numeric,numeric,text) to authenticated;

create or replace function public.inventory_list_products_v4(p_tenant_id uuid,p_location_id uuid default null)
returns setof jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare r jsonb;v_variant uuid;v_qty numeric;v_price numeric;v_reorder numeric;v_assigned boolean;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if p_location_id is not null then perform private.v4_location_access(p_tenant_id,p_location_id,'view'); end if;
  for r in select to_jsonb(x) from public.inventory_list_products(p_tenant_id) x loop
    begin v_variant:=coalesce(nullif(r->>'variant_id',''),nullif(r->>'id',''))::uuid; exception when others then v_variant:=null; end;
    if v_variant is null then continue; end if;
    if p_location_id is null then
      select coalesce(sum(b.quantity),0),coalesce(max(s.selling_price),null),coalesce(max(s.reorder_level),null),bool_or(coalesce(s.active,false))
      into v_qty,v_price,v_reorder,v_assigned
      from public.location_stock_balances b
      left join public.location_product_settings s on s.tenant_id=b.tenant_id and s.location_id=b.location_id and s.variant_id=b.variant_id
      where b.tenant_id=p_tenant_id and b.variant_id=v_variant;
      -- Owner/all-store view keeps historical products visible even before explicit assignment.
      v_assigned:=coalesce(v_assigned,true);
    else
      select coalesce(b.quantity,0),s.selling_price,s.reorder_level,coalesce(s.active,false)
      into v_qty,v_price,v_reorder,v_assigned
      from public.location_product_settings s
      left join public.location_stock_balances b on b.tenant_id=s.tenant_id and b.location_id=s.location_id and b.variant_id=s.variant_id
      where s.tenant_id=p_tenant_id and s.location_id=p_location_id and s.variant_id=v_variant;
      if not coalesce(v_assigned,false) then continue; end if;
    end if;
    return next r || jsonb_build_object(
      'stock_quantity',coalesce(v_qty,0),
      'selling_price',coalesce(v_price,(r->>'selling_price')::numeric),
      'reorder_level',coalesce(v_reorder,(r->>'reorder_level')::numeric),
      'location_id',p_location_id,
      'location_assigned',coalesce(v_assigned,false),
      'stock_scope',case when p_location_id is null then 'merged' else 'location' end
    );
  end loop;
  return;
end $$;
grant execute on function public.inventory_list_products_v4(uuid,uuid) to authenticated;

create or replace function public.inventory_location_stock_summary_v4(p_tenant_id uuid,p_variant_id uuid)
returns table(location_id uuid,location_code text,location_name text,quantity numeric,reserved numeric,damaged numeric,available numeric,selling_price numeric,reorder_level numeric,rack_code text)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  return query
  select l.id,l.location_code,l.name,coalesce(b.quantity,0),coalesce(b.reserved_quantity,0),coalesce(b.damaged_quantity,0),
    greatest(coalesce(b.quantity,0)-coalesce(b.reserved_quantity,0)-coalesce(b.damaged_quantity,0)-coalesce(b.quarantine_quantity,0),0),
    s.selling_price,s.reorder_level,s.rack_code
  from public.business_locations l
  join public.location_product_settings s on s.tenant_id=p_tenant_id and s.location_id=l.id and s.variant_id=p_variant_id and s.active
  left join public.location_stock_balances b on b.tenant_id=s.tenant_id and b.location_id=s.location_id and b.variant_id=s.variant_id
  where l.tenant_id=p_tenant_id and l.active
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_user_location_allowed(p_tenant_id,l.id,'view'))
  order by l.location_code;
end $$;
grant execute on function public.inventory_location_stock_summary_v4(uuid,uuid) to authenticated;

create or replace function public.inventory_location_movements_v4(
  p_tenant_id uuid,p_variant_id uuid,p_location_id uuid default null,p_limit integer default 250
) returns table(
  movement_id uuid,movement_type text,quantity_delta numeric,unit_cost numeric,location_name text,
  reference_type text,reference_number text,note text,occurred_at timestamptz,created_at timestamptz
)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if p_location_id is not null then perform private.v4_location_access(p_tenant_id,p_location_id,'view');end if;
  return query
  select m.id,m.movement_type,m.quantity_delta,m.unit_cost,
    coalesce(l.location_code||' • '||l.name,l.name,'Store'),m.reference_type,m.reference_number,m.note,m.created_at,m.created_at
  from public.location_stock_movements m
  join public.business_locations l on l.id=m.location_id
  where m.tenant_id=p_tenant_id and m.variant_id=p_variant_id
    and (p_location_id is null or m.location_id=p_location_id)
    and (
      private.erp_user_is_owner(p_tenant_id)
      or private.erp_has_permission(p_tenant_id,'locations.view_all')
      or private.erp_user_location_allowed(p_tenant_id,m.location_id,'view')
    )
  order by m.created_at desc
  limit greatest(1,least(coalesce(p_limit,250),1000));
end $$;
grant execute on function public.inventory_location_movements_v4(uuid,uuid,uuid,integer) to authenticated;

create or replace function public.inventory_adjust_stock_v4(
  p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_variant_id uuid,p_quantity_delta numeric,p_note text
) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_core jsonb;v_after numeric;v_type text;begin
  perform private.v4_location_access(p_tenant_id,p_location_id,'operate');
  if not private.erp_has_permission(p_tenant_id,'inventory.manage') and not private.erp_has_permission(p_tenant_id,'inventory.adjust') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Stock adjustment permission required'; end if;
  if coalesce(p_quantity_delta,0)=0 then raise exception 'Adjustment cannot be zero'; end if;
  select public.inventory_adjust_stock(p_tenant_id,p_variant_id,p_quantity_delta,p_note) into v_core;
  v_type:=case when p_quantity_delta>0 then 'adjustment_in' else 'adjustment_out' end;
  v_after:=private.v4_location_stock_apply(p_tenant_id,p_location_id,p_variant_id,p_quantity_delta,v_type,'stock_adjustment',null,null,p_note,p_device_id,false);
  return coalesce(v_core,'{}'::jsonb)||jsonb_build_object('location_id',p_location_id,'location_quantity',v_after);
end $$;
grant execute on function public.inventory_adjust_stock_v4(uuid,uuid,uuid,uuid,numeric,text) to authenticated;

commit;
select 'Flexi ERP V4 branch inventory foundation ready' as status;
