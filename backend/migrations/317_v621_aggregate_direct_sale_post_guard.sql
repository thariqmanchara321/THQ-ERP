begin;

create or replace function private.aggregate_direct_sale_post_guard_v621()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_operating_location_id uuid;
  v_customer_id uuid;
  v_line record;
  v_purchase_backed_capacity numeric;
  v_posted_sale_quantity numeric;
begin
  if new.entity_type <> 'sale' then return new; end if;

  select m.operating_location_id into v_operating_location_id
  from public.aggregate_direct_transit_locations_v621 m
  where m.tenant_id=new.tenant_id and m.transit_location_id=new.location_id
  for update;

  if v_operating_location_id is null then return new; end if;

  select s.customer_id into v_customer_id
  from public.sales s
  where s.tenant_id=new.tenant_id and s.id=new.entity_id
    and coalesce(s.status,'') not in('void','cancelled');
  if v_customer_id is null then raise exception 'Active Direct Supply Sale not found'; end if;

  if not exists(
    select 1 from public.sale_items si
    join public.product_variants pv on pv.tenant_id=si.tenant_id and pv.id=si.variant_id
    join public.products p on p.tenant_id=pv.tenant_id and p.id=pv.product_id
    where si.tenant_id=new.tenant_id and si.sale_id=new.entity_id and p.item_type='stock'
  ) then raise exception 'Direct Supply Sale must contain at least one stock material'; end if;

  for v_line in
    select si.variant_id,
      upper(coalesce(nullif(trim(si.entered_unit_code),''),nullif(trim(si.unit_code),''),'')) unit_code,
      sum(coalesce(si.entered_quantity,si.quantity))::numeric sale_quantity
    from public.sale_items si
    join public.product_variants pv on pv.tenant_id=si.tenant_id and pv.id=si.variant_id
    join public.products p on p.tenant_id=pv.tenant_id and p.id=pv.product_id
    where si.tenant_id=new.tenant_id and si.sale_id=new.entity_id and p.item_type='stock'
    group by si.variant_id,
      upper(coalesce(nullif(trim(si.entered_unit_code),''),nullif(trim(si.unit_code),''),''))
  loop
    if v_line.unit_code='' or coalesce(v_line.sale_quantity,0)<=0 then
      raise exception 'Direct Supply Sale has an invalid material quantity/unit';
    end if;

    select coalesce(sum(l.quantity),0) into v_purchase_backed_capacity
    from public.aggregate_loads_v617 l
    where l.tenant_id=new.tenant_id
      and l.direction='direct_delivery'
      and l.location_id=new.location_id
      and l.status<>'cancelled'
      and l.customer_id=v_customer_id
      and l.variant_id=v_line.variant_id
      and upper(l.unit_code)=v_line.unit_code
      and l.purchase_id is not null;

    select coalesce(sum(case
      when upper(coalesce(nullif(trim(si.entered_unit_code),''),nullif(trim(si.unit_code),''),''))=v_line.unit_code
      then coalesce(si.entered_quantity,si.quantity) else 0 end),0)
    into v_posted_sale_quantity
    from public.sales s
    join public.document_origins d
      on d.tenant_id=s.tenant_id and d.entity_type='sale'
     and d.entity_id=s.id and d.location_id=new.location_id
    join public.sale_items si
      on si.tenant_id=s.tenant_id and si.sale_id=s.id and si.variant_id=v_line.variant_id
    where s.tenant_id=new.tenant_id
      and s.customer_id=v_customer_id
      and coalesce(s.status,'') not in('void','cancelled');

    if v_posted_sale_quantity>v_purchase_backed_capacity+0.0001 then
      raise exception 'Direct Supply Sale is not backed by linked Purchase loads. Purchase-backed capacity: % %, posted Sale quantity: % %',
        round(v_purchase_backed_capacity,4),v_line.unit_code,
        round(v_posted_sale_quantity,4),v_line.unit_code;
    end if;
  end loop;
  return new;
end;
$$;

revoke all on function private.aggregate_direct_sale_post_guard_v621() from public,anon,authenticated;
grant execute on function private.aggregate_direct_sale_post_guard_v621() to postgres,service_role;

drop trigger if exists trg_aggregate_direct_sale_post_guard_v621 on public.document_origins;
create constraint trigger trg_aggregate_direct_sale_post_guard_v621
after insert on public.document_origins
deferrable initially deferred
for each row when (new.entity_type='sale')
execute function private.aggregate_direct_sale_post_guard_v621();

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  317,'6.2.1-aggregate-direct-sale-guard','Aggregate Direct Supply Sale Posting Guard',
  'Adds a deferred, serialized database guard for Sales posted to controlled Direct Supply transit locations. Transit Sales are limited to the same customer/material/unit capacity represented by non-cancelled Direct Supply loads whose Purchase is already linked, preventing shared residual transit stock from authorizing a Sale before matching Purchase-backed load capacity exists. Normal locations and authoritative Sale/GST/stock/accounting writers are unchanged.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
