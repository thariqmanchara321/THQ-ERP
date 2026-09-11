create table if not exists public.restaurant_waitlist (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete cascade,
  guest_name text not null,
  phone text null,
  guest_count integer not null default 1 check (guest_count between 1 and 999),
  estimated_wait_minutes integer not null default 15 check (estimated_wait_minutes between 0 and 1440),
  preferred_area text null,
  note text null,
  status text not null default 'waiting' check (status in ('waiting','notified','seated','cancelled','no_show')),
  table_id uuid null references public.restaurant_tables(id) on delete set null,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  notified_at timestamptz null,
  seated_at timestamptz null,
  closed_at timestamptz null
);

alter table public.restaurant_waitlist enable row level security;

revoke all on table public.restaurant_waitlist from anon, authenticated;
grant select, insert, update, delete on table public.restaurant_waitlist to service_role;

create index if not exists idx_restaurant_waitlist_live
  on public.restaurant_waitlist(tenant_id, location_id, status, created_at);

create index if not exists idx_restaurant_waitlist_phone
  on public.restaurant_waitlist(tenant_id, location_id, phone)
  where phone is not null;

create or replace function public.restaurant_waitlist_list_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_status text default 'live',
  p_limit integer default 200
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_status text;
  v_limit integer;
  v_rows jsonb;
begin
  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,
    p_location_id,
    p_device_id,
    'restaurant',
    'view'
  );

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id, 'restaurant.view')
    or private.erp_has_permission(p_tenant_id, 'restaurant.order')
    or private.erp_has_permission(p_tenant_id, 'restaurant.manage')
  ) then
    raise exception 'Restaurant waitlist permission denied';
  end if;

  v_status := lower(trim(coalesce(p_status, 'live')));
  if v_status not in ('live','waiting','notified','seated','cancelled','no_show','all') then
    raise exception 'Invalid waitlist status filter';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 200), 1), 500);

  select coalesce(
    jsonb_agg(row_data order by created_at),
    '[]'::jsonb
  )
  into v_rows
  from (
    select
      w.created_at,
      jsonb_strip_nulls(
        jsonb_build_object(
          'id', w.id,
          'guest_name', w.guest_name,
          'phone', w.phone,
          'guest_count', w.guest_count,
          'estimated_wait_minutes', w.estimated_wait_minutes,
          'preferred_area', w.preferred_area,
          'note', w.note,
          'status', w.status,
          'table_id', w.table_id,
          'table_name', coalesce(nullif(trim(t.name), ''), t.table_code),
          'created_at', w.created_at,
          'updated_at', w.updated_at,
          'notified_at', w.notified_at,
          'seated_at', w.seated_at,
          'closed_at', w.closed_at,
          'waiting_minutes', greatest(0, floor(extract(epoch from (now() - w.created_at)) / 60))::integer
        )
      ) as row_data
    from public.restaurant_waitlist w
    left join public.restaurant_tables t
      on t.id = w.table_id
     and t.tenant_id = w.tenant_id
    where w.tenant_id = p_tenant_id
      and w.location_id = p_location_id
      and (
        v_status = 'all'
        or v_status = 'live' and w.status in ('waiting','notified')
        or v_status <> 'live' and v_status <> 'all' and w.status = v_status
      )
    order by w.created_at
    limit v_limit
  ) q;

  return jsonb_build_object(
    'success', true,
    'status_filter', v_status,
    'count', jsonb_array_length(v_rows),
    'entries', v_rows,
    'restaurant_engine', 'v6.1'
  );
end;
$$;

create or replace function public.restaurant_waitlist_add_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_guest_name text,
  p_phone text,
  p_guest_count integer,
  p_estimated_wait_minutes integer default 15,
  p_preferred_area text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_id uuid;
  v_name text;
  v_phone text;
  v_area text;
  v_note text;
  v_guests integer;
  v_wait integer;
begin
  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,
    p_location_id,
    p_device_id,
    'restaurant',
    'operate'
  );

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id, 'restaurant.order')
    or private.erp_has_permission(p_tenant_id, 'restaurant.manage')
  ) then
    raise exception 'Restaurant waitlist permission denied';
  end if;

  v_name := nullif(trim(coalesce(p_guest_name, '')), '');
  if v_name is null then
    raise exception 'Guest name is required';
  end if;

  v_phone := nullif(trim(coalesce(p_phone, '')), '');
  v_area := nullif(trim(coalesce(p_preferred_area, '')), '');
  v_note := nullif(trim(coalesce(p_note, '')), '');
  v_guests := greatest(1, least(coalesce(p_guest_count, 1), 999));
  v_wait := greatest(0, least(coalesce(p_estimated_wait_minutes, 15), 1440));

  insert into public.restaurant_waitlist(
    tenant_id,
    location_id,
    guest_name,
    phone,
    guest_count,
    estimated_wait_minutes,
    preferred_area,
    note,
    created_by
  )
  values (
    p_tenant_id,
    p_location_id,
    v_name,
    v_phone,
    v_guests,
    v_wait,
    v_area,
    v_note,
    auth.uid()
  )
  returning id into v_id;

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'transactions',
    'restaurant_waitlist',
    v_id::text,
    'add'
  );

  return jsonb_build_object(
    'success', true,
    'waitlist_id', v_id,
    'guest_name', v_name,
    'guest_count', v_guests,
    'estimated_wait_minutes', v_wait,
    'status', 'waiting',
    'restaurant_engine', 'v6.1'
  );
end;
$$;

create or replace function public.restaurant_waitlist_status_set_v610(
  p_tenant_id uuid,
  p_waitlist_id uuid,
  p_device_id uuid,
  p_status text,
  p_table_id uuid default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  w public.restaurant_waitlist%rowtype;
  t public.restaurant_tables%rowtype;
  v_status text;
  v_note text;
  v_table_name text;
begin
  v_status := lower(trim(coalesce(p_status, '')));
  v_note := nullif(trim(coalesce(p_note, '')), '');

  if v_status not in ('waiting','notified','seated','cancelled','no_show') then
    raise exception 'Invalid waitlist status';
  end if;

  select *
  into w
  from public.restaurant_waitlist
  where id = p_waitlist_id
    and tenant_id = p_tenant_id
  for update;

  if not found then
    raise exception 'Waitlist entry not found';
  end if;

  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,
    w.location_id,
    p_device_id,
    'restaurant',
    'operate'
  );

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id, 'restaurant.order')
    or private.erp_has_permission(p_tenant_id, 'restaurant.manage')
  ) then
    raise exception 'Restaurant waitlist permission denied';
  end if;

  if w.status in ('seated','cancelled','no_show') and v_status <> w.status then
    raise exception 'Waitlist entry is already closed';
  end if;

  if v_status = 'seated' then
    if p_table_id is null then
      raise exception 'Table is required when seating a waitlist guest';
    end if;

    select *
    into t
    from public.restaurant_tables
    where id = p_table_id
      and tenant_id = p_tenant_id
      and location_id = w.location_id
      and active = true
    for update;

    if not found then
      raise exception 'Restaurant table not found';
    end if;

    if t.operational_status <> 'available' then
      raise exception 'Restaurant table is not available';
    end if;

    if t.capacity < w.guest_count then
      raise exception 'Selected table capacity is smaller than guest count';
    end if;

    if exists (
      select 1
      from public.restaurant_orders o
      where o.tenant_id = p_tenant_id
        and o.location_id = w.location_id
        and o.table_id = p_table_id
        and o.status not in ('billed','cancelled')
    ) then
      raise exception 'Selected table already has an active order';
    end if;

    v_table_name := coalesce(nullif(trim(t.name), ''), t.table_code);
  elsif p_table_id is not null then
    raise exception 'Table may only be assigned when seating the guest';
  end if;

  update public.restaurant_waitlist
  set status = v_status,
      table_id = case when v_status = 'seated' then p_table_id else table_id end,
      note = case
        when v_note is null then note
        when nullif(trim(coalesce(note, '')), '') is null then v_note
        else note || ' | ' || v_note
      end,
      notified_at = case
        when v_status = 'notified' then coalesce(notified_at, now())
        else notified_at
      end,
      seated_at = case
        when v_status = 'seated' then coalesce(seated_at, now())
        else seated_at
      end,
      closed_at = case
        when v_status in ('seated','cancelled','no_show') then coalesce(closed_at, now())
        else null
      end,
      updated_at = now()
  where id = p_waitlist_id
    and tenant_id = p_tenant_id;

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'transactions',
    'restaurant_waitlist',
    p_waitlist_id::text,
    'status_' || v_status
  );

  return jsonb_strip_nulls(
    jsonb_build_object(
      'success', true,
      'waitlist_id', p_waitlist_id,
      'guest_name', w.guest_name,
      'guest_count', w.guest_count,
      'status', v_status,
      'table_id', case when v_status = 'seated' then p_table_id else w.table_id end,
      'table_name', v_table_name,
      'restaurant_engine', 'v6.1'
    )
  );
end;
$$;

revoke all on function public.restaurant_waitlist_list_v610(uuid,uuid,uuid,text,integer) from public, anon;
revoke all on function public.restaurant_waitlist_add_v610(uuid,uuid,uuid,text,text,integer,integer,text,text) from public, anon;
revoke all on function public.restaurant_waitlist_status_set_v610(uuid,uuid,uuid,text,uuid,text) from public, anon;

grant execute on function public.restaurant_waitlist_list_v610(uuid,uuid,uuid,text,integer) to authenticated, service_role;
grant execute on function public.restaurant_waitlist_add_v610(uuid,uuid,uuid,text,text,integer,integer,text,text) to authenticated, service_role;
grant execute on function public.restaurant_waitlist_status_set_v610(uuid,uuid,uuid,text,uuid,text) to authenticated, service_role;
