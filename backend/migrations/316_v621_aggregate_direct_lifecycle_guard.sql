begin;

create or replace function private.aggregate_direct_load_lifecycle_guard_v621()
returns trigger
language plpgsql
security invoker
set search_path = public, private, pg_temp
as $$
declare
  v_is_direct boolean;
begin
  v_is_direct := coalesce(new.direction, '') = 'direct_delivery'
    or (tg_op = 'UPDATE' and coalesce(old.direction, '') = 'direct_delivery');
  if not v_is_direct then return new; end if;

  if tg_op = 'UPDATE' and new.direction is distinct from old.direction then
    raise exception 'Direct Supply direction is immutable after load creation';
  end if;
  if new.direction <> 'direct_delivery' then raise exception 'Direct Supply load must remain direct_delivery'; end if;
  if new.supplier_id is null then raise exception 'Supplier / quarry is required for Direct Supply'; end if;
  if new.customer_id is null then raise exception 'Customer is required for Direct Supply'; end if;

  if new.location_id is null or not exists(
    select 1 from public.aggregate_direct_transit_locations_v621 m
    where m.tenant_id=new.tenant_id and m.transit_location_id=new.location_id
  ) then raise exception 'Direct Supply load must use a controlled transit location'; end if;

  if new.sale_id is not null and new.purchase_id is null then
    raise exception 'Direct Supply Sale cannot be linked before the Purchase';
  end if;

  if new.status='completed' and (new.purchase_id is null or new.sale_id is null) then
    raise exception 'Direct Supply cannot be completed until Purchase and Sale are linked';
  end if;

  if tg_op='UPDATE' then
    if old.purchase_id is not null and new.purchase_id is distinct from old.purchase_id then
      raise exception 'Linked Direct Supply Purchase is immutable';
    end if;
    if old.sale_id is not null and new.sale_id is distinct from old.sale_id then
      raise exception 'Linked Direct Supply Sale is immutable';
    end if;
    if (old.purchase_id is not null or old.sale_id is not null) and (
      new.location_id is distinct from old.location_id
      or new.variant_id is distinct from old.variant_id
      or new.quantity is distinct from old.quantity
      or upper(coalesce(new.unit_code,'')) is distinct from upper(coalesce(old.unit_code,''))
      or new.supplier_id is distinct from old.supplier_id
      or new.customer_id is distinct from old.customer_id
    ) then raise exception 'Direct Supply commercial identity is immutable after document linking'; end if;

    if new.status='cancelled' and (
      old.purchase_id is not null or old.sale_id is not null
      or new.purchase_id is not null or new.sale_id is not null
    ) then raise exception 'Direct Supply with linked commercial documents cannot be cancelled'; end if;
  end if;
  return new;
end;
$$;

revoke all on function private.aggregate_direct_load_lifecycle_guard_v621() from public,anon,authenticated;
grant execute on function private.aggregate_direct_load_lifecycle_guard_v621() to postgres,service_role;

drop trigger if exists trg_aggregate_direct_load_lifecycle_v621 on public.aggregate_loads_v617;
create trigger trg_aggregate_direct_load_lifecycle_v621
before insert or update on public.aggregate_loads_v617
for each row execute function private.aggregate_direct_load_lifecycle_guard_v621();

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  316,'6.2.1-aggregate-direct-lifecycle','Aggregate Direct Supply Lifecycle Guard',
  'Enforces controlled transit for Direct Supply loads, Purchase-before-Sale linkage, immutable linked commercial documents and material/party/quantity identity, blocks cancellation after commercial linking, and requires both Purchase and Sale before operational completion. Existing non-direct loads and authoritative Purchase/Sale/GST/stock/accounting writers are unchanged.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
