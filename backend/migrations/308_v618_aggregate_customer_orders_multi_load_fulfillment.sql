-- THQ ERP v6.1.8 — Aggregate Customer Orders & Multi-Load Fulfillment
-- Supabase: ALREADY LIVE. Keep this file for repository migration history.
--
-- SAFETY CONTRACT
-- * Customer Orders are operational commitments only.
-- * Orders do not post stock, GST, accounting or receivables.
-- * Outbound Load Tickets remain operational.
-- * The existing authoritative THQ Sale writer remains the commercial authority.
-- * One order line may be fulfilled by many truck loads.
-- * Non-cancelled load allocation may never exceed ordered quantity.

insert into public.permissions(key,name,module_key,description)
values
 ('aggregate_yard.orders.view','View Material Yard Orders','aggregate_yard','View Aggregate customer orders and fulfillment progress'),
 ('aggregate_yard.orders.manage','Manage Material Yard Orders','aggregate_yard','Create, close and dispatch Aggregate customer orders')
on conflict(key) do update
set name=excluded.name,module_key=excluded.module_key,description=excluded.description;

create sequence if not exists public.aggregate_order_number_seq_v618;
revoke all on sequence public.aggregate_order_number_seq_v618
from public,anon,authenticated;
grant usage,select on sequence public.aggregate_order_number_seq_v618
to service_role;

create table if not exists public.aggregate_orders_v618(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete restrict,
  order_number text not null,
  order_date date not null default current_date,
  requested_date date,
  delivery_site_name text,
  delivery_address text,
  status text not null default 'open'
    check(status in(
      'open','partially_dispatched','completed','closed_partial','cancelled'
    )),
  close_reason text,
  notes text,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  closed_by uuid references auth.users(id),
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,order_number),
  unique(id,tenant_id)
);

create index if not exists aggregate_orders_v618_tenant_status_idx
on public.aggregate_orders_v618(
  tenant_id,status,order_date desc,created_at desc
);
create index if not exists aggregate_orders_v618_customer_idx
on public.aggregate_orders_v618(tenant_id,customer_id,created_at desc);
create index if not exists aggregate_orders_v618_location_idx
on public.aggregate_orders_v618(tenant_id,location_id,created_at desc);

alter table public.aggregate_orders_v618 enable row level security;

drop policy if exists aggregate_orders_v618_read
on public.aggregate_orders_v618;

create policy aggregate_orders_v618_read
on public.aggregate_orders_v618
for select to authenticated
using(
  private.erp_user_has_tenant_access(tenant_id)
  and exists(
    select 1 from public.tenant_modules tm
    where tm.tenant_id=aggregate_orders_v618.tenant_id
      and tm.module_key='aggregate_yard'
      and tm.enabled
  )
  and private.erp_document_scope_allowed(
    tenant_id,location_id,location_id,'view'
  )
  and (
    private.erp_has_permission(tenant_id,'aggregate_yard.view')
    or private.erp_has_permission(tenant_id,'aggregate_yard.manage')
    or private.erp_has_permission(tenant_id,'aggregate_yard.orders.view')
    or private.erp_has_permission(tenant_id,'aggregate_yard.orders.manage')
  )
);

revoke all on public.aggregate_orders_v618
from public,anon,authenticated;
grant select on public.aggregate_orders_v618
to authenticated,service_role;

create table if not exists public.aggregate_order_lines_v618(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  order_id uuid not null,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  product_name_snapshot text not null,
  unit_code text not null,
  ordered_quantity numeric not null check(ordered_quantity>0),
  agreed_rate numeric check(agreed_rate is null or agreed_rate>=0),
  note text,
  created_at timestamptz not null default now(),
  unique(order_id,variant_id,unit_code),
  unique(id,order_id,tenant_id),
  foreign key(order_id,tenant_id)
    references public.aggregate_orders_v618(id,tenant_id)
    on delete cascade
);

create index if not exists aggregate_order_lines_v618_order_idx
on public.aggregate_order_lines_v618(tenant_id,order_id);
create index if not exists aggregate_order_lines_v618_variant_idx
on public.aggregate_order_lines_v618(tenant_id,variant_id);

alter table public.aggregate_order_lines_v618 enable row level security;

drop policy if exists aggregate_order_lines_v618_read
on public.aggregate_order_lines_v618;

create policy aggregate_order_lines_v618_read
on public.aggregate_order_lines_v618
for select to authenticated
using(
  private.erp_user_has_tenant_access(tenant_id)
  and exists(
    select 1
    from public.aggregate_orders_v618 o
    where o.id=aggregate_order_lines_v618.order_id
      and o.tenant_id=aggregate_order_lines_v618.tenant_id
  )
  and (
    private.erp_has_permission(tenant_id,'aggregate_yard.view')
    or private.erp_has_permission(tenant_id,'aggregate_yard.manage')
    or private.erp_has_permission(tenant_id,'aggregate_yard.orders.view')
    or private.erp_has_permission(tenant_id,'aggregate_yard.orders.manage')
  )
);

revoke all on public.aggregate_order_lines_v618
from public,anon,authenticated;
grant select on public.aggregate_order_lines_v618
to authenticated,service_role;

create table if not exists public.aggregate_order_events_v618(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  order_id uuid not null,
  event_type text not null,
  from_status text,
  to_status text,
  note text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key(order_id,tenant_id)
    references public.aggregate_orders_v618(id,tenant_id)
    on delete cascade
);

create index if not exists aggregate_order_events_v618_order_idx
on public.aggregate_order_events_v618(tenant_id,order_id,created_at);

alter table public.aggregate_order_events_v618 enable row level security;

drop policy if exists aggregate_order_events_v618_read
on public.aggregate_order_events_v618;

create policy aggregate_order_events_v618_read
on public.aggregate_order_events_v618
for select to authenticated
using(
  private.erp_user_has_tenant_access(tenant_id)
  and (
    private.erp_has_permission(tenant_id,'aggregate_yard.view')
    or private.erp_has_permission(tenant_id,'aggregate_yard.manage')
    or private.erp_has_permission(tenant_id,'aggregate_yard.orders.view')
    or private.erp_has_permission(tenant_id,'aggregate_yard.orders.manage')
  )
);

revoke all on public.aggregate_order_events_v618
from public,anon,authenticated;
grant select on public.aggregate_order_events_v618
to authenticated,service_role;

alter table public.aggregate_loads_v617
  add column if not exists order_id uuid,
  add column if not exists order_line_id uuid;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conname='aggregate_loads_v617_order_fk'
  ) then
    alter table public.aggregate_loads_v617
      add constraint aggregate_loads_v617_order_fk
      foreign key(order_id,tenant_id)
      references public.aggregate_orders_v618(id,tenant_id)
      on delete set null;
  end if;

  if not exists(
    select 1 from pg_constraint
    where conname='aggregate_loads_v617_order_line_fk'
  ) then
    alter table public.aggregate_loads_v617
      add constraint aggregate_loads_v617_order_line_fk
      foreign key(order_line_id,order_id,tenant_id)
      references public.aggregate_order_lines_v618(id,order_id,tenant_id)
      on delete set null;
  end if;
end
$$;

create index if not exists aggregate_loads_v617_order_idx
on public.aggregate_loads_v617(tenant_id,order_id,created_at desc)
where order_id is not null;

create index if not exists aggregate_loads_v617_order_line_idx
on public.aggregate_loads_v617(tenant_id,order_line_id,created_at desc)
where order_line_id is not null;

create or replace function private.aggregate_yard_assert_orders_view_v618(
  p_tenant_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;

  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Tenant access required' using errcode='42501';
  end if;

  if not exists(
    select 1
    from public.tenant_modules
    where tenant_id=p_tenant_id
      and module_key='aggregate_yard'
      and enabled
  ) then
    raise exception 'Material Yard module is not enabled'
      using errcode='42501';
  end if;

  if not (
    private.erp_has_permission(p_tenant_id,'aggregate_yard.view')
    or private.erp_has_permission(p_tenant_id,'aggregate_yard.manage')
    or private.erp_has_permission(
      p_tenant_id,'aggregate_yard.orders.view'
    )
    or private.erp_has_permission(
      p_tenant_id,'aggregate_yard.orders.manage'
    )
  ) then
    raise exception 'Material Yard order view permission required'
      using errcode='42501';
  end if;
end
$$;

revoke all
on function private.aggregate_yard_assert_orders_view_v618(uuid)
from public,anon,authenticated;

create or replace function private.aggregate_yard_assert_orders_manage_v618(
  p_tenant_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
begin
  perform private.aggregate_yard_assert_orders_view_v618(p_tenant_id);

  if not (
    private.erp_has_permission(p_tenant_id,'aggregate_yard.manage')
    or private.erp_has_permission(
      p_tenant_id,'aggregate_yard.orders.manage'
    )
  ) then
    raise exception 'Material Yard order manage permission required'
      using errcode='42501';
  end if;
end
$$;

revoke all
on function private.aggregate_yard_assert_orders_manage_v618(uuid)
from public,anon,authenticated;

create or replace function private.aggregate_order_refresh_v618(
  p_order_id uuid
)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_order public.aggregate_orders_v618%rowtype;
  v_next text;
  v_all_complete boolean:=false;
  v_any_load boolean:=false;
begin
  select *
  into v_order
  from public.aggregate_orders_v618
  where id=p_order_id
  for update;

  if v_order.id is null
     or v_order.status in('cancelled','closed_partial') then
    return;
  end if;

  select
    coalesce(
      bool_and(delivered_qty+0.0001>=ordered_quantity),
      false
    ),
    coalesce(bool_or(allocated_qty>0.0001),false)
  into v_all_complete,v_any_load
  from (
    select
      ol.id,
      ol.ordered_quantity,
      coalesce(
        sum(l.quantity) filter(
          where l.status in('delivered','completed')
        ),
        0
      ) as delivered_qty,
      coalesce(
        sum(l.quantity) filter(where l.status<>'cancelled'),
        0
      ) as allocated_qty
    from public.aggregate_order_lines_v618 ol
    left join public.aggregate_loads_v617 l
      on l.tenant_id=ol.tenant_id
     and l.order_line_id=ol.id
    where ol.order_id=p_order_id
      and ol.tenant_id=v_order.tenant_id
    group by ol.id,ol.ordered_quantity
  ) q;

  v_next:=case
    when v_all_complete then 'completed'
    when v_any_load then 'partially_dispatched'
    else 'open'
  end;

  if v_next<>v_order.status then
    update public.aggregate_orders_v618
    set status=v_next,
        updated_at=now(),
        updated_by=auth.uid()
    where id=p_order_id;

    insert into public.aggregate_order_events_v618(
      tenant_id,order_id,event_type,from_status,to_status,note,created_by
    )
    values(
      v_order.tenant_id,
      p_order_id,
      'status_changed',
      v_order.status,
      v_next,
      'Status refreshed from linked load progress',
      auth.uid()
    );
  else
    update public.aggregate_orders_v618
    set updated_at=now()
    where id=p_order_id;
  end if;
end
$$;

revoke all
on function private.aggregate_order_refresh_v618(uuid)
from public,anon,authenticated;

create or replace function private.aggregate_order_load_refresh_trigger_v618()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if tg_op='DELETE' then
    if old.order_id is not null then
      perform private.aggregate_order_refresh_v618(old.order_id);
    end if;
    return old;
  end if;

  if tg_op='UPDATE'
     and old.order_id is not null
     and old.order_id is distinct from new.order_id then
    perform private.aggregate_order_refresh_v618(old.order_id);
  end if;

  if new.order_id is not null then
    perform private.aggregate_order_refresh_v618(new.order_id);
  end if;

  return new;
end
$$;

revoke all
on function private.aggregate_order_load_refresh_trigger_v618()
from public,anon,authenticated;

drop trigger if exists trg_aggregate_order_load_refresh_v618
on public.aggregate_loads_v617;

create trigger trg_aggregate_order_load_refresh_v618
after insert or update of
  status,quantity,unit_code,order_id,order_line_id
or delete on public.aggregate_loads_v617
for each row
execute function private.aggregate_order_load_refresh_trigger_v618();

create or replace function private.aggregate_yard_grant_default_permissions_v617(
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  insert into public.role_permissions(role_id,permission_key)
  select r.id,p.key
  from public.roles r
  join public.permissions p
    on p.module_key='aggregate_yard'
  where r.tenant_id=p_tenant_id
    and (
      r.key='owner'
      or (
        r.key='manager'
        and p.key in(
          'aggregate_yard.view',
          'aggregate_yard.manage',
          'aggregate_yard.override_capacity',
          'aggregate_yard.orders.view',
          'aggregate_yard.orders.manage'
        )
      )
      or (
        r.key='store_keeper'
        and p.key in(
          'aggregate_yard.view',
          'aggregate_yard.manage',
          'aggregate_yard.orders.view',
          'aggregate_yard.orders.manage'
        )
      )
      or (
        r.key='salesperson'
        and p.key in(
          'aggregate_yard.view',
          'aggregate_yard.orders.view',
          'aggregate_yard.orders.manage'
        )
      )
      or (
        r.key='accountant'
        and p.key in(
          'aggregate_yard.view',
          'aggregate_yard.orders.view'
        )
      )
    )
  on conflict do nothing;
end
$$;

revoke all
on function private.aggregate_yard_grant_default_permissions_v617(uuid)
from public,anon,authenticated;

create or replace function public.aggregate_order_create_v618(
  p_tenant_id uuid,
  p_location_id uuid,
  p_customer_id uuid,
  p_requested_date date,
  p_delivery_site_name text,
  p_delivery_address text,
  p_notes text,
  p_lines jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_order_id uuid;
  v_order_number text;
  v_line jsonb;
  v_variant_id uuid;
  v_qty numeric;
  v_unit text;
  v_rate numeric;
  v_product text;
  v_line_count integer;
begin
  perform private.aggregate_yard_assert_orders_manage_v618(p_tenant_id);

  if not exists(
    select 1
    from public.business_locations l
    where l.id=p_location_id
      and l.tenant_id=p_tenant_id
      and l.active
  ) then
    raise exception 'Location not found';
  end if;

  if not private.erp_document_scope_allowed(
    p_tenant_id,p_location_id,p_location_id,'view'
  ) then
    raise exception 'Location access required' using errcode='42501';
  end if;

  if not exists(
    select 1
    from public.customers c
    where c.id=p_customer_id
      and c.tenant_id=p_tenant_id
      and c.status='active'
  ) then
    raise exception 'Active customer not found';
  end if;

  if jsonb_typeof(p_lines)<>'array' then
    raise exception 'Order lines must be a JSON array';
  end if;

  v_line_count:=jsonb_array_length(p_lines);

  if v_line_count<1 or v_line_count>50 then
    raise exception 'Order must contain between 1 and 50 lines';
  end if;

  if exists(
    select 1
    from (
      select
        (x->>'variant_id')::uuid variant_id,
        upper(trim(coalesce(x->>'unit_code',''))) unit_code,
        count(*) cnt
      from jsonb_array_elements(p_lines) x
      group by 1,2
      having count(*)>1
    ) d
  ) then
    raise exception 'Duplicate material/unit lines are not allowed';
  end if;

  v_order_number:=
    'ORD-'
    ||to_char(current_date,'YYYYMMDD')
    ||'-'
    ||lpad(
      nextval('public.aggregate_order_number_seq_v618')::text,
      6,
      '0'
    );

  insert into public.aggregate_orders_v618(
    tenant_id,
    location_id,
    customer_id,
    order_number,
    order_date,
    requested_date,
    delivery_site_name,
    delivery_address,
    notes,
    created_by,
    updated_by
  )
  values(
    p_tenant_id,
    p_location_id,
    p_customer_id,
    v_order_number,
    current_date,
    p_requested_date,
    nullif(trim(p_delivery_site_name),''),
    nullif(trim(p_delivery_address),''),
    nullif(trim(p_notes),''),
    auth.uid(),
    auth.uid()
  )
  returning id into v_order_id;

  for v_line in
    select value
    from jsonb_array_elements(p_lines)
  loop
    begin
      v_variant_id:=(v_line->>'variant_id')::uuid;
      v_qty:=(v_line->>'quantity')::numeric;
      v_unit:=upper(trim(coalesce(v_line->>'unit_code','')));
      v_rate:=case
        when nullif(
          trim(coalesce(v_line->>'agreed_rate','')),
          ''
        ) is null then null
        else (v_line->>'agreed_rate')::numeric
      end;
    exception when others then
      raise exception 'Invalid order line payload';
    end;

    if coalesce(v_qty,0)<=0 then
      raise exception 'Order line quantity must be greater than zero';
    end if;

    if v_rate is not null and v_rate<0 then
      raise exception 'Agreed rate cannot be negative';
    end if;

    if v_unit='' then
      raise exception 'Order line unit is required';
    end if;

    select
      p.name
      ||case
          when nullif(trim(pv.name),'') is not null
               and lower(trim(pv.name)) not in('default','standard')
          then ' - '||pv.name
          else ''
        end
    into v_product
    from public.product_variants pv
    join public.products p
      on p.id=pv.product_id
     and p.tenant_id=pv.tenant_id
    left join public.inventory_units_v481 bu
      on bu.id=p.base_unit_id
     and bu.tenant_id=p.tenant_id
    where pv.id=v_variant_id
      and pv.tenant_id=p_tenant_id
      and pv.status='active'
      and p.status='active'
      and p.item_type='stock'
      and (
        upper(coalesce(bu.code,''))=v_unit
        or exists(
          select 1
          from public.product_units_v481 pu
          join public.inventory_units_v481 u
            on u.id=pu.unit_id
           and u.tenant_id=pu.tenant_id
          where pu.tenant_id=p_tenant_id
            and pu.variant_id=pv.id
            and pu.active
            and pu.allow_sale
            and u.active
            and upper(u.code)=v_unit
        )
      );

    if v_product is null then
      raise exception
        'Material % is not an active stock product configured for unit %',
        v_variant_id,
        v_unit;
    end if;

    insert into public.aggregate_order_lines_v618(
      tenant_id,
      order_id,
      variant_id,
      product_name_snapshot,
      unit_code,
      ordered_quantity,
      agreed_rate,
      note
    )
    values(
      p_tenant_id,
      v_order_id,
      v_variant_id,
      v_product,
      v_unit,
      v_qty,
      v_rate,
      nullif(trim(v_line->>'note'),'')
    );
  end loop;

  insert into public.aggregate_order_events_v618(
    tenant_id,
    order_id,
    event_type,
    to_status,
    note,
    metadata,
    created_by
  )
  values(
    p_tenant_id,
    v_order_id,
    'created',
    'open',
    'Customer order created',
    jsonb_build_object('line_count',v_line_count),
    auth.uid()
  );

  return jsonb_build_object(
    'order_id',v_order_id,
    'order_number',v_order_number,
    'status','open',
    'line_count',v_line_count
  );
end
$$;

revoke all
on function public.aggregate_order_create_v618(
  uuid,uuid,uuid,date,text,text,text,jsonb
)
from public,anon;

grant execute
on function public.aggregate_order_create_v618(
  uuid,uuid,uuid,date,text,text,text,jsonb
)
to authenticated,service_role;

-- Phase 308 originally installs aggregate_order_close_v618 here.
-- Migration 309 replaces it with the active-load safety version.

create or replace function public.aggregate_order_load_create_v618(
  p_tenant_id uuid,
  p_order_line_id uuid,
  p_quantity numeric,
  p_measurement_method text,
  p_body_length_ft numeric,
  p_body_width_ft numeric,
  p_body_height_ft numeric,
  p_vehicle_id uuid,
  p_driver_id uuid,
  p_source_name text,
  p_destination_name text,
  p_freight_mode text,
  p_freight_amount numeric,
  p_capacity_override boolean,
  p_capacity_override_reason text,
  p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_order public.aggregate_orders_v618%rowtype;
  v_line public.aggregate_order_lines_v618%rowtype;
  v_allocated numeric:=0;
  v_effective_qty numeric;
  v_measure text:=lower(coalesce(p_measurement_method,'manual'));
  v_result jsonb;
  v_load_id uuid;
begin
  perform private.aggregate_yard_assert_orders_manage_v618(p_tenant_id);

  select ol.*
  into v_line
  from public.aggregate_order_lines_v618 ol
  where ol.id=p_order_line_id
    and ol.tenant_id=p_tenant_id;

  if v_line.id is null then
    raise exception 'Order line not found';
  end if;

  select *
  into v_order
  from public.aggregate_orders_v618
  where id=v_line.order_id
    and tenant_id=p_tenant_id
  for update;

  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  if v_order.status not in('open','partially_dispatched') then
    raise exception 'Order is not open for additional loads';
  end if;

  if v_measure='dimensions' then
    if v_line.unit_code<>'CFT' then
      raise exception
        'Dimension measurement is only valid for CFT order lines';
    end if;

    if coalesce(p_body_length_ft,0)<=0
       or coalesce(p_body_width_ft,0)<=0
       or coalesce(p_body_height_ft,0)<=0 then
      raise exception 'Length, width and height are required';
    end if;

    v_effective_qty:=round(
      p_body_length_ft*p_body_width_ft*p_body_height_ft,
      3
    );
  elsif v_measure='manual' then
    v_effective_qty:=p_quantity;
  else
    raise exception
      'Order dispatch supports manual or dimensions measurement';
  end if;

  if coalesce(v_effective_qty,0)<=0 then
    raise exception 'Load quantity must be greater than zero';
  end if;

  select coalesce(sum(l.quantity),0)
  into v_allocated
  from public.aggregate_loads_v617 l
  where l.tenant_id=p_tenant_id
    and l.order_line_id=v_line.id
    and l.status<>'cancelled';

  if v_effective_qty>
     greatest(v_line.ordered_quantity-v_allocated,0)+0.0001 then
    raise exception
      'Load quantity % exceeds unallocated order quantity % %',
      v_effective_qty,
      greatest(v_line.ordered_quantity-v_allocated,0),
      v_line.unit_code;
  end if;

  v_result:=public.aggregate_load_create_v617(
    p_tenant_id,
    'outbound',
    v_order.location_id,
    v_line.variant_id,
    v_effective_qty,
    v_line.unit_code,
    v_measure,
    p_body_length_ft,
    p_body_width_ft,
    p_body_height_ft,
    null,
    null,
    null,
    p_vehicle_id,
    p_driver_id,
    null,
    v_order.customer_id,
    nullif(trim(p_source_name),''),
    coalesce(
      nullif(trim(p_destination_name),''),
      nullif(trim(v_order.delivery_site_name),''),
      nullif(trim(v_order.delivery_address),'')
    ),
    v_order.order_number,
    p_freight_mode,
    p_freight_amount,
    p_capacity_override,
    p_capacity_override_reason,
    concat_ws(
      ' | ',
      'Customer Order '||v_order.order_number,
      nullif(trim(p_notes),'')
    )
  );

  v_load_id:=(v_result->>'load_id')::uuid;

  update public.aggregate_loads_v617
  set order_id=v_order.id,
      order_line_id=v_line.id,
      updated_by=auth.uid(),
      updated_at=now()
  where id=v_load_id
    and tenant_id=p_tenant_id;

  insert into public.aggregate_load_events_v617(
    tenant_id,
    load_id,
    event_type,
    note,
    metadata,
    created_by
  )
  values(
    p_tenant_id,
    v_load_id,
    'order_linked',
    'Linked to customer order '||v_order.order_number,
    jsonb_build_object(
      'order_id',v_order.id,
      'order_line_id',v_line.id,
      'order_number',v_order.order_number
    ),
    auth.uid()
  );

  perform private.aggregate_order_refresh_v618(v_order.id);

  return v_result||jsonb_build_object(
    'order_id',v_order.id,
    'order_line_id',v_line.id,
    'order_number',v_order.order_number
  );
end
$$;

revoke all
on function public.aggregate_order_load_create_v618(
  uuid,uuid,numeric,text,numeric,numeric,numeric,uuid,uuid,
  text,text,text,numeric,boolean,text,text
)
from public,anon;

grant execute
on function public.aggregate_order_load_create_v618(
  uuid,uuid,numeric,text,numeric,numeric,numeric,uuid,uuid,
  text,text,text,numeric,boolean,text,text
)
to authenticated,service_role;

create or replace function public.aggregate_order_list_v618(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_status text default null,
  p_query text default null,
  p_limit integer default 300
)
returns setof jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
begin
  perform private.aggregate_yard_assert_orders_view_v618(p_tenant_id);

  return query
  with load_agg as (
    select
      l.order_line_id,
      coalesce(
        sum(l.quantity) filter(where l.status<>'cancelled'),
        0
      )::numeric as allocated_qty,
      coalesce(
        sum(l.quantity) filter(
          where l.status in(
            'dispatched','in_transit','arrived','delivered','completed'
          )
        ),
        0
      )::numeric as dispatched_qty,
      coalesce(
        sum(l.quantity) filter(
          where l.status in('delivered','completed')
        ),
        0
      )::numeric as delivered_qty,
      count(*) filter(
        where l.status in(
          'draft','loading','dispatched','in_transit','arrived'
        )
      )::bigint as open_load_count
    from public.aggregate_loads_v617 l
    where l.tenant_id=p_tenant_id
      and l.order_line_id is not null
    group by l.order_line_id
  ),
  line_rollup as (
    select
      ol.order_id,
      count(*)::bigint as line_count,
      coalesce(
        sum(ol.ordered_quantity) filter(
          where upper(ol.unit_code)='CFT'
        ),
        0
      )::numeric as ordered_cft,
      coalesce(
        sum(coalesce(la.dispatched_qty,0)) filter(
          where upper(ol.unit_code)='CFT'
        ),
        0
      )::numeric as dispatched_cft,
      coalesce(
        sum(coalesce(la.delivered_qty,0)) filter(
          where upper(ol.unit_code)='CFT'
        ),
        0
      )::numeric as delivered_cft,
      coalesce(
        sum(
          greatest(
            ol.ordered_quantity-coalesce(la.delivered_qty,0),
            0
          )
        ) filter(where upper(ol.unit_code)='CFT'),
        0
      )::numeric as remaining_cft,
      jsonb_agg(
        jsonb_build_object(
          'line_id',ol.id,
          'variant_id',ol.variant_id,
          'product_name',ol.product_name_snapshot,
          'unit_code',ol.unit_code,
          'ordered_quantity',ol.ordered_quantity,
          'agreed_rate',ol.agreed_rate,
          'allocated_quantity',coalesce(la.allocated_qty,0),
          'dispatched_quantity',coalesce(la.dispatched_qty,0),
          'delivered_quantity',coalesce(la.delivered_qty,0),
          'remaining_to_plan',greatest(
            ol.ordered_quantity-coalesce(la.allocated_qty,0),
            0
          ),
          'remaining_to_deliver',greatest(
            ol.ordered_quantity-coalesce(la.delivered_qty,0),
            0
          ),
          'open_load_count',coalesce(la.open_load_count,0),
          'note',ol.note
        )
        order by ol.created_at,ol.product_name_snapshot
      ) as lines
    from public.aggregate_order_lines_v618 ol
    left join load_agg la
      on la.order_line_id=ol.id
    where ol.tenant_id=p_tenant_id
    group by ol.order_id
  )
  select jsonb_build_object(
    'order_id',o.id,
    'order_number',o.order_number,
    'order_date',o.order_date,
    'requested_date',o.requested_date,
    'status',o.status,
    'location_id',o.location_id,
    'customer_id',o.customer_id,
    'customer_name',c.name,
    'customer_phone',c.phone,
    'delivery_site_name',o.delivery_site_name,
    'delivery_address',o.delivery_address,
    'notes',o.notes,
    'close_reason',o.close_reason,
    'line_count',coalesce(lr.line_count,0),
    'ordered_cft',coalesce(lr.ordered_cft,0),
    'dispatched_cft',coalesce(lr.dispatched_cft,0),
    'delivered_cft',coalesce(lr.delivered_cft,0),
    'remaining_cft',coalesce(lr.remaining_cft,0),
    'lines',coalesce(lr.lines,'[]'::jsonb),
    'created_at',o.created_at,
    'updated_at',o.updated_at
  )
  from public.aggregate_orders_v618 o
  join public.customers c
    on c.id=o.customer_id
   and c.tenant_id=o.tenant_id
  left join line_rollup lr
    on lr.order_id=o.id
  where o.tenant_id=p_tenant_id
    and (p_location_id is null or o.location_id=p_location_id)
    and private.erp_document_scope_allowed(
      p_tenant_id,o.location_id,p_location_id,'view'
    )
    and (
      p_status is null
      or trim(p_status)=''
      or o.status=lower(trim(p_status))
    )
    and (
      p_query is null
      or trim(p_query)=''
      or o.order_number ilike '%'||trim(p_query)||'%'
      or c.name ilike '%'||trim(p_query)||'%'
      or coalesce(c.phone,'') ilike '%'||trim(p_query)||'%'
      or coalesce(o.delivery_site_name,'')
           ilike '%'||trim(p_query)||'%'
      or exists(
        select 1
        from public.aggregate_order_lines_v618 x
        where x.order_id=o.id
          and x.tenant_id=o.tenant_id
          and x.product_name_snapshot
              ilike '%'||trim(p_query)||'%'
      )
    )
  order by
    case
      when o.status in('open','partially_dispatched') then 0
      else 1
    end,
    o.order_date desc,
    o.created_at desc
  limit greatest(1,least(coalesce(p_limit,300),1000));
end
$$;

revoke all
on function public.aggregate_order_list_v618(
  uuid,uuid,text,text,integer
)
from public,anon;

grant execute
on function public.aggregate_order_list_v618(
  uuid,uuid,text,text,integer
)
to authenticated,service_role;

create or replace function public.aggregate_yard_context_v617(
  p_tenant_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_result jsonb;
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  select jsonb_build_object(
    'products',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'variant_id',v.id,
          'name',p.name,
          'variant_name',v.name,
          'sku',v.sku,
          'cost_price',v.cost_price,
          'selling_price',v.selling_price,
          'base_unit_code',bu.code,
          'sale_units',
          coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'unit_id',u.id,
                'code',u.code,
                'name',u.name,
                'is_base',pu.is_base,
                'is_default_sale',pu.is_default_sale,
                'conversion_to_base',pu.conversion_to_base,
                'sale_price',pu.sale_price
              )
              order by
                pu.is_default_sale desc,
                pu.is_base desc,
                u.code
            )
            from public.product_units_v481 pu
            join public.inventory_units_v481 u
              on u.id=pu.unit_id
             and u.tenant_id=pu.tenant_id
            where pu.tenant_id=p_tenant_id
              and pu.variant_id=v.id
              and pu.active
              and pu.allow_sale
              and u.active
          ),'[]'::jsonb)
        )
        order by p.name,v.name
      )
      from public.product_variants v
      join public.products p
        on p.id=v.product_id
       and p.tenant_id=v.tenant_id
      left join public.inventory_units_v481 bu
        on bu.id=p.base_unit_id
       and bu.tenant_id=p.tenant_id
      where v.tenant_id=p_tenant_id
        and v.status='active'
        and p.status='active'
    ),'[]'::jsonb),

    'vehicles',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'vehicle_id',v.id,
          'registration_number',v.registration_number,
          'vehicle_type',v.vehicle_type,
          'capacity',v.capacity,
          'capacity_unit',v.capacity_unit,
          'driver_name',v.driver_name,
          'driver_phone',v.driver_phone,
          'ownership_type',coalesce(ap.ownership_type,'hired'),
          'owner_name',ap.owner_name,
          'owner_phone',ap.owner_phone,
          'body_length_ft',ap.body_length_ft,
          'body_width_ft',ap.body_width_ft,
          'body_height_ft',ap.body_height_ft,
          'nominal_capacity_cft',
          coalesce(
            ap.nominal_capacity_cft,
            case
              when upper(coalesce(v.capacity_unit,''))='CFT'
              then v.capacity
              else null
            end
          ),
          'tare_weight_kg',ap.tare_weight_kg,
          'max_payload_kg',ap.max_payload_kg,
          'default_freight',coalesce(ap.default_freight,0)
        )
        order by v.registration_number
      )
      from public.service_vehicles v
      left join public.aggregate_vehicle_profiles_v617 ap
        on ap.tenant_id=v.tenant_id
       and ap.vehicle_id=v.id
       and ap.active
      where v.tenant_id=p_tenant_id
        and v.active
    ),'[]'::jsonb),

    'drivers',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'driver_id',d.id,
          'name',d.name,
          'phone',d.phone,
          'license_number',d.license_number
        )
        order by d.name
      )
      from public.logistics_drivers_v61 d
      where d.tenant_id=p_tenant_id
        and d.active
    ),'[]'::jsonb),

    'suppliers',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'supplier_id',s.id,
          'name',s.name,
          'phone',s.phone
        )
        order by s.name
      )
      from public.suppliers s
      where s.tenant_id=p_tenant_id
        and s.status='active'
    ),'[]'::jsonb),

    'customers',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'customer_id',c.id,
          'name',c.name,
          'phone',c.phone,
          'is_walk_in',c.is_walk_in
        )
        order by c.name
      )
      from public.customers c
      where c.tenant_id=p_tenant_id
        and c.status='active'
    ),'[]'::jsonb),

    'locations',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'location_id',l.id,
          'code',l.location_code,
          'name',l.name,
          'type',l.location_type
        )
        order by l.sort_order,l.name
      )
      from public.business_locations l
      where l.tenant_id=p_tenant_id
        and l.active
    ),'[]'::jsonb)
  )
  into v_result;

  return v_result;
end
$$;

revoke all
on function public.aggregate_yard_context_v617(uuid)
from public,anon;

grant execute
on function public.aggregate_yard_context_v617(uuid)
to authenticated,service_role;

create or replace function public.aggregate_load_list_v619(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_status text default null,
  p_query text default null,
  p_limit integer default 300
)
returns table(
  load_id uuid,
  load_number text,
  load_date date,
  direction text,
  status text,
  location_id uuid,
  variant_id uuid,
  supplier_id uuid,
  customer_id uuid,
  product_name text,
  quantity numeric,
  unit_code text,
  measurement_method text,
  vehicle_id uuid,
  vehicle_registration text,
  driver_name text,
  supplier_name text,
  customer_name text,
  source_name text,
  destination_name text,
  source_reference text,
  freight_mode text,
  freight_amount numeric,
  purchase_id uuid,
  sale_id uuid,
  order_id uuid,
  order_line_id uuid,
  order_number text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  return query
  select
    l.id,
    l.load_number,
    l.load_date,
    l.direction,
    l.status,
    l.location_id,
    l.variant_id,
    l.supplier_id,
    l.customer_id,
    l.product_name_snapshot,
    l.quantity,
    l.unit_code,
    l.measurement_method,
    l.vehicle_id,
    l.vehicle_registration_snapshot,
    l.driver_name_snapshot,
    s.name,
    c.name,
    l.source_name,
    l.destination_name,
    l.source_reference,
    l.freight_mode,
    l.freight_amount,
    l.purchase_id,
    l.sale_id,
    l.order_id,
    l.order_line_id,
    o.order_number,
    l.created_at
  from public.aggregate_loads_v617 l
  left join public.suppliers s
    on s.id=l.supplier_id
   and s.tenant_id=l.tenant_id
  left join public.customers c
    on c.id=l.customer_id
   and c.tenant_id=l.tenant_id
  left join public.aggregate_orders_v618 o
    on o.id=l.order_id
   and o.tenant_id=l.tenant_id
  where l.tenant_id=p_tenant_id
    and (p_location_id is null or l.location_id=p_location_id)
    and (
      p_status is null
      or trim(p_status)=''
      or l.status=lower(trim(p_status))
    )
    and (
      p_query is null
      or trim(p_query)=''
      or l.load_number ilike '%'||trim(p_query)||'%'
      or l.product_name_snapshot ilike '%'||trim(p_query)||'%'
      or coalesce(l.vehicle_registration_snapshot,'')
           ilike '%'||trim(p_query)||'%'
      or coalesce(l.driver_name_snapshot,'')
           ilike '%'||trim(p_query)||'%'
      or coalesce(s.name,'') ilike '%'||trim(p_query)||'%'
      or coalesce(c.name,'') ilike '%'||trim(p_query)||'%'
      or coalesce(o.order_number,'') ilike '%'||trim(p_query)||'%'
    )
  order by l.created_at desc
  limit greatest(1,least(coalesce(p_limit,300),1000));
end
$$;

revoke all
on function public.aggregate_load_list_v619(
  uuid,uuid,text,text,integer
)
from public,anon;

grant execute
on function public.aggregate_load_list_v619(
  uuid,uuid,text,text,integer
)
to authenticated,service_role;

create or replace function public.aggregate_yard_dashboard_v617(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_day date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_day date:=coalesce(p_day,current_date);
  v_today_in_cft numeric:=0;
  v_today_out_cft numeric:=0;
  v_today_in_loads bigint:=0;
  v_today_out_loads bigint:=0;
  v_stock_on_hand_cft numeric:=0;
  v_stock_available_cft numeric:=0;
  v_trucks_on_road bigint:=0;
  v_active_trucks bigint:=0;
  v_pending_delivery_cft numeric:=0;
  v_pending_delivery_loads bigint:=0;
  v_open_order_count bigint:=0;
  v_open_order_cft numeric:=0;
  v_receivables numeric:=0;
  v_receivables_visible boolean:=false;
  v_stock_by_material jsonb:='[]'::jsonb;
  v_active_loads jsonb:='[]'::jsonb;
  v_recent_loads jsonb:='[]'::jsonb;
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  if p_location_id is not null
     and not exists(
       select 1
       from public.business_locations l
       where l.id=p_location_id
         and l.tenant_id=p_tenant_id
         and l.active
     ) then
    raise exception 'Location not found';
  end if;

  if p_location_id is not null
     and not private.erp_document_scope_allowed(
       p_tenant_id,p_location_id,p_location_id,'view'
     ) then
    raise exception 'Location view access required'
      using errcode='42501';
  end if;

  select
    coalesce(
      sum(l.quantity) filter(
        where l.direction='inbound'
          and upper(l.unit_code)='CFT'
          and l.status in('received','completed')
      ),
      0
    ),
    count(*) filter(
      where l.direction='inbound'
        and l.status in('received','completed')
    ),
    coalesce(
      sum(l.quantity) filter(
        where l.direction='outbound'
          and upper(l.unit_code)='CFT'
          and l.status in(
            'dispatched','in_transit','arrived','delivered','completed'
          )
      ),
      0
    ),
    count(*) filter(
      where l.direction='outbound'
        and l.status in(
          'dispatched','in_transit','arrived','delivered','completed'
        )
    ),
    count(distinct l.vehicle_id) filter(
      where l.vehicle_id is not null
        and l.status in('dispatched','in_transit')
    ),
    count(distinct l.vehicle_id) filter(
      where l.vehicle_id is not null
        and l.status in('loading','dispatched','in_transit','arrived')
    ),
    coalesce(
      sum(l.quantity) filter(
        where l.direction='outbound'
          and upper(l.unit_code)='CFT'
          and l.status in(
            'draft','loading','dispatched','in_transit','arrived'
          )
      ),
      0
    ),
    count(*) filter(
      where l.direction='outbound'
        and l.status in(
          'draft','loading','dispatched','in_transit','arrived'
        )
    )
  into
    v_today_in_cft,
    v_today_in_loads,
    v_today_out_cft,
    v_today_out_loads,
    v_trucks_on_road,
    v_active_trucks,
    v_pending_delivery_cft,
    v_pending_delivery_loads
  from public.aggregate_loads_v617 l
  where l.tenant_id=p_tenant_id
    and l.load_date=v_day
    and l.status<>'cancelled'
    and (p_location_id is null or l.location_id=p_location_id)
    and (
      l.location_id is null
      or private.erp_document_scope_allowed(
        p_tenant_id,l.location_id,p_location_id,'view'
      )
    );

  select
    coalesce(
      sum(
        case
          when upper(coalesce(u.code,''))='CFT'
          then b.quantity
          else 0
        end
      ),
      0
    ),
    coalesce(
      sum(
        case
          when upper(coalesce(u.code,''))='CFT'
          then greatest(
            b.quantity
            -coalesce(b.reserved_quantity,0)
            -coalesce(b.damaged_quantity,0)
            -coalesce(b.quarantine_quantity,0),
            0
          )
          else 0
        end
      ),
      0
    )
  into
    v_stock_on_hand_cft,
    v_stock_available_cft
  from public.location_stock_balances b
  join public.product_variants pv
    on pv.id=b.variant_id
   and pv.tenant_id=b.tenant_id
   and pv.status='active'
  join public.products p
    on p.id=pv.product_id
   and p.tenant_id=pv.tenant_id
   and p.status='active'
  left join public.inventory_units_v481 u
    on u.id=p.base_unit_id
   and u.tenant_id=p.tenant_id
  where b.tenant_id=p_tenant_id
    and (p_location_id is null or b.location_id=p_location_id)
    and private.erp_document_scope_allowed(
      p_tenant_id,b.location_id,p_location_id,'view'
    );

  with delivered as (
    select
      l.order_line_id,
      coalesce(
        sum(l.quantity) filter(
          where l.status in('delivered','completed')
        ),
        0
      )::numeric as qty
    from public.aggregate_loads_v617 l
    where l.tenant_id=p_tenant_id
      and l.order_line_id is not null
    group by l.order_line_id
  )
  select
    count(distinct o.id),
    coalesce(
      sum(
        greatest(
          ol.ordered_quantity-coalesce(d.qty,0),
          0
        )
      ) filter(where upper(ol.unit_code)='CFT'),
      0
    )
  into
    v_open_order_count,
    v_open_order_cft
  from public.aggregate_orders_v618 o
  join public.aggregate_order_lines_v618 ol
    on ol.order_id=o.id
   and ol.tenant_id=o.tenant_id
  left join delivered d
    on d.order_line_id=ol.id
  where o.tenant_id=p_tenant_id
    and o.status in('open','partially_dispatched')
    and (p_location_id is null or o.location_id=p_location_id)
    and private.erp_document_scope_allowed(
      p_tenant_id,o.location_id,p_location_id,'view'
    );

  select coalesce(
    jsonb_agg(
      to_jsonb(q)
      order by q.product_name,q.variant_name
    ),
    '[]'::jsonb
  )
  into v_stock_by_material
  from (
    select
      pv.id as variant_id,
      p.name as product_name,
      pv.name as variant_name,
      coalesce(u.code,'') as unit_code,
      round(sum(b.quantity),3) as on_hand,
      round(
        sum(
          greatest(
            b.quantity
            -coalesce(b.reserved_quantity,0)
            -coalesce(b.damaged_quantity,0)
            -coalesce(b.quarantine_quantity,0),
            0
          )
        ),
        3
      ) as available,
      round(sum(coalesce(b.reserved_quantity,0)),3) as reserved
    from public.location_stock_balances b
    join public.product_variants pv
      on pv.id=b.variant_id
     and pv.tenant_id=b.tenant_id
     and pv.status='active'
    join public.products p
      on p.id=pv.product_id
     and p.tenant_id=pv.tenant_id
     and p.status='active'
    left join public.inventory_units_v481 u
      on u.id=p.base_unit_id
     and u.tenant_id=p.tenant_id
    where b.tenant_id=p_tenant_id
      and p.item_type='stock'
      and (p_location_id is null or b.location_id=p_location_id)
      and private.erp_document_scope_allowed(
        p_tenant_id,b.location_id,p_location_id,'view'
      )
    group by pv.id,p.name,pv.name,u.code
    having sum(b.quantity)<>0
    order by p.name,pv.name
    limit 200
  ) q;

  select coalesce(
    jsonb_agg(to_jsonb(q) order by q.created_at desc),
    '[]'::jsonb
  )
  into v_active_loads
  from (
    select
      l.id as load_id,
      l.load_number,
      l.direction,
      l.status,
      l.product_name_snapshot as product_name,
      l.quantity,
      l.unit_code,
      l.vehicle_registration_snapshot as vehicle_registration,
      l.driver_name_snapshot as driver_name,
      coalesce(l.source_name,s.name,'') as source_name,
      coalesce(l.destination_name,c.name,'') as destination_name,
      l.purchase_id,
      l.sale_id,
      l.order_id,
      o.order_number,
      l.created_at
    from public.aggregate_loads_v617 l
    left join public.suppliers s
      on s.id=l.supplier_id
     and s.tenant_id=l.tenant_id
    left join public.customers c
      on c.id=l.customer_id
     and c.tenant_id=l.tenant_id
    left join public.aggregate_orders_v618 o
      on o.id=l.order_id
     and o.tenant_id=l.tenant_id
    where l.tenant_id=p_tenant_id
      and l.status in(
        'loading','dispatched','in_transit','arrived'
      )
      and (p_location_id is null or l.location_id=p_location_id)
      and (
        l.location_id is null
        or private.erp_document_scope_allowed(
          p_tenant_id,l.location_id,p_location_id,'view'
        )
      )
    order by l.created_at desc
    limit 10
  ) q;

  select coalesce(
    jsonb_agg(to_jsonb(q) order by q.created_at desc),
    '[]'::jsonb
  )
  into v_recent_loads
  from (
    select
      l.id as load_id,
      l.load_number,
      l.load_date,
      l.direction,
      l.status,
      l.product_name_snapshot as product_name,
      l.quantity,
      l.unit_code,
      l.vehicle_registration_snapshot as vehicle_registration,
      l.order_id,
      o.order_number,
      l.created_at
    from public.aggregate_loads_v617 l
    left join public.aggregate_orders_v618 o
      on o.id=l.order_id
     and o.tenant_id=l.tenant_id
    where l.tenant_id=p_tenant_id
      and (p_location_id is null or l.location_id=p_location_id)
      and (
        l.location_id is null
        or private.erp_document_scope_allowed(
          p_tenant_id,l.location_id,p_location_id,'view'
        )
      )
    order by l.created_at desc
    limit 8
  ) q;

  v_receivables_visible :=
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'accounting.view')
    or private.erp_has_permission(p_tenant_id,'sales.view')
    or private.erp_has_permission(p_tenant_id,'sales.manage')
    or private.erp_has_permission(p_tenant_id,'customers.view')
    or private.erp_has_permission(p_tenant_id,'customers.manage');

  if v_receivables_visible then
    select coalesce(sum(ci.total_outstanding),0)
    into v_receivables
    from public.customer_credit_intelligence_v480(
      p_tenant_id,
      p_location_id,
      '',
      5000
    ) ci;
  end if;

  return jsonb_build_object(
    'day',v_day,
    'today_in_cft',round(v_today_in_cft,3),
    'today_in_loads',v_today_in_loads,
    'today_out_cft',round(v_today_out_cft,3),
    'today_out_loads',v_today_out_loads,
    'stock_on_hand_cft',round(v_stock_on_hand_cft,3),
    'stock_available_cft',round(v_stock_available_cft,3),
    'trucks_on_road',v_trucks_on_road,
    'active_trucks',v_active_trucks,
    'pending_delivery_cft',round(v_pending_delivery_cft,3),
    'pending_delivery_loads',v_pending_delivery_loads,
    'open_order_count',v_open_order_count,
    'open_order_cft',round(v_open_order_cft,3),
    'receivables',
    case
      when v_receivables_visible
      then round(v_receivables,2)
      else null
    end,
    'receivables_visible',v_receivables_visible,
    'stock_by_material',coalesce(v_stock_by_material,'[]'::jsonb),
    'active_loads',coalesce(v_active_loads,'[]'::jsonb),
    'recent_loads',coalesce(v_recent_loads,'[]'::jsonb)
  );
end
$$;

revoke all
on function public.aggregate_yard_dashboard_v617(
  uuid,uuid,date
)
from public,anon;

grant execute
on function public.aggregate_yard_dashboard_v617(
  uuid,uuid,date
)
to authenticated,service_role;

insert into public.thq_schema_releases(
  migration_no,
  schema_version,
  release_name,
  notes
)
values(
  308,
  '6.1.8-aggregate-customer-orders',
  'Aggregate Customer Orders & Multi-Load Fulfillment',
  'Adds operational customer orders with multiple material lines, multi-truck fulfillment, over-allocation protection, automatic progress/status refresh, order/load audit events, order-aware dashboard metrics and sale-UOM-aware order entry. Orders and Load Tickets remain non-financial; authoritative Sale/GST/stock/accounting posting is unchanged.'
);
