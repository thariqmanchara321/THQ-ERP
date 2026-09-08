-- THQ ERP v6.0
-- Deferred location stock balance/movement integrity guard.

create or replace function private.location_stock_integrity_guard_v600()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_tenant uuid;
  v_location uuid;
  v_variant uuid;
  v_balance numeric:=0;
  v_movements numeric:=0;
begin
  if tg_op='DELETE' then
    v_tenant:=old.tenant_id;
    v_location:=old.location_id;
    v_variant:=old.variant_id;
  else
    v_tenant:=new.tenant_id;
    v_location:=new.location_id;
    v_variant:=new.variant_id;
  end if;

  select coalesce(quantity,0)
    into v_balance
  from public.location_stock_balances
  where tenant_id=v_tenant
    and location_id=v_location
    and variant_id=v_variant;

  if not found then v_balance:=0; end if;

  select coalesce(sum(quantity_delta),0)
    into v_movements
  from public.location_stock_movements
  where tenant_id=v_tenant
    and location_id=v_location
    and variant_id=v_variant;

  if abs(round(v_balance-v_movements,6))>0.0001 then
    raise exception
      'Inventory integrity failure: location balance % does not match movement ledger % for variant %',
      v_balance,v_movements,v_variant;
  end if;

  return coalesce(new,old);
end
$function$;

drop trigger if exists trg_location_stock_balance_integrity_v600
on public.location_stock_balances;

create constraint trigger trg_location_stock_balance_integrity_v600
after insert or delete or update on public.location_stock_balances
deferrable initially deferred
for each row
execute function private.location_stock_integrity_guard_v600();

drop trigger if exists trg_location_stock_movement_integrity_v600
on public.location_stock_movements;

create constraint trigger trg_location_stock_movement_integrity_v600
after insert or delete or update on public.location_stock_movements
deferrable initially deferred
for each row
execute function private.location_stock_integrity_guard_v600();

create or replace function public.inventory_location_integrity_report_v600(
  p_tenant_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_count integer:=0;
  v_items jsonb:='[]'::jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  if not (
    private.erp_has_permission(p_tenant_id,'inventory.view')
    or private.erp_has_permission(p_tenant_id,'inventory.manage')
    or private.erp_has_permission(p_tenant_id,'accounting.view')
  ) then
    raise exception 'Inventory view permission required';
  end if;

  with m as (
    select
      tenant_id,
      location_id,
      variant_id,
      round(sum(quantity_delta),6) movement_quantity
    from public.location_stock_movements
    where tenant_id=p_tenant_id
    group by tenant_id,location_id,variant_id
  ),
  b as (
    select
      tenant_id,
      location_id,
      variant_id,
      round(quantity,6) balance_quantity
    from public.location_stock_balances
    where tenant_id=p_tenant_id
  ),
  x as (
    select
      coalesce(b.tenant_id,m.tenant_id) tenant_id,
      coalesce(b.location_id,m.location_id) location_id,
      coalesce(b.variant_id,m.variant_id) variant_id,
      coalesce(b.balance_quantity,0) balance_quantity,
      coalesce(m.movement_quantity,0) movement_quantity,
      round(
        coalesce(b.balance_quantity,0)-coalesce(m.movement_quantity,0),
        6
      ) difference
    from b
    full join m using(tenant_id,location_id,variant_id)
  )
  select
    count(*),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'location_id',x.location_id,
          'location_name',l.name,
          'variant_id',x.variant_id,
          'product_name',p.name,
          'sku',pv.sku,
          'balance_quantity',x.balance_quantity,
          'movement_quantity',x.movement_quantity,
          'difference',x.difference,
          'tracking_mode',private.v483_tracking_mode(p_tenant_id,x.variant_id)
        )
        order by abs(x.difference) desc
      ),
      '[]'::jsonb
    )
  into v_count,v_items
  from x
  left join public.business_locations l
    on l.id=x.location_id
   and l.tenant_id=x.tenant_id
  left join public.product_variants pv
    on pv.id=x.variant_id
   and pv.tenant_id=x.tenant_id
  left join public.products p
    on p.id=pv.product_id
   and p.tenant_id=pv.tenant_id
  where abs(x.difference)>0.0001;

  return jsonb_build_object(
    'tenant_id',p_tenant_id,
    'healthy',v_count=0,
    'mismatch_count',v_count,
    'items',v_items
  );
end
$function$;

revoke execute on function private.location_stock_integrity_guard_v600()
from public, anon, authenticated, service_role;

revoke execute on function public.inventory_location_integrity_report_v600(uuid)
from public, anon;

grant execute on function public.inventory_location_integrity_report_v600(uuid)
to authenticated, service_role;
