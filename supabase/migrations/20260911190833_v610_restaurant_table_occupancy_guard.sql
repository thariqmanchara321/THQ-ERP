-- THQ ERP v6.1 Restaurant live-table occupancy guard
-- Prevents new dine-in orders or table moves onto unavailable/occupied tables.
-- Uses an advisory transaction lock so concurrent writers cannot create two live orders on one table.

create or replace function private.restaurant_live_table_guard_v610()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_status text;
begin
  if new.order_type <> 'dine_in'
     or new.table_id is null
     or new.status in ('billed', 'cancelled') then
    return new;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      new.tenant_id::text || ':' || new.table_id::text,
      0
    )
  );

  select t.operational_status
  into v_status
  from public.restaurant_tables t
  where t.id = new.table_id
    and t.tenant_id = new.tenant_id
    and t.location_id = new.location_id
    and t.active = true;

  if not found then
    raise exception 'Choose an active restaurant table from this store';
  end if;

  if v_status <> 'available' then
    raise exception 'Restaurant table is not available';
  end if;

  if exists (
    select 1
    from public.restaurant_orders o
    where o.tenant_id = new.tenant_id
      and o.location_id = new.location_id
      and o.table_id = new.table_id
      and o.id <> new.id
      and o.order_type = 'dine_in'
      and o.status not in ('billed', 'cancelled')
  ) then
    raise exception 'Restaurant table already has an active order';
  end if;

  return new;
end;
$$;

drop trigger if exists restaurant_live_table_guard_v610
  on public.restaurant_orders;

create trigger restaurant_live_table_guard_v610
before insert or update of table_id
on public.restaurant_orders
for each row
execute function private.restaurant_live_table_guard_v610();
