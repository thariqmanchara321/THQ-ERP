-- THQ ERP V4.7 — enforce AVAILABLE stock under the row lock.
begin;

create or replace function private.v4_location_stock_apply(
  p_tenant_id uuid,p_location_id uuid,p_variant_id uuid,p_delta numeric,
  p_movement_type text,p_reference_type text default null,p_reference_id uuid default null,
  p_reference_number text default null,p_note text default null,p_device_id uuid default null,
  p_allow_negative boolean default false
) returns numeric
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_before numeric:=0;v_after numeric;v_cost numeric:=0;v_reserved numeric:=0;v_damaged numeric:=0;v_quarantine numeric:=0;v_available numeric:=0;
begin
  -- Ensure a row exists BEFORE FOR UPDATE so simultaneous first movements serialize.
  insert into public.location_stock_balances(tenant_id,location_id,variant_id,quantity,average_cost,updated_at)
  values(p_tenant_id,p_location_id,p_variant_id,0,0,now()) on conflict(tenant_id,location_id,variant_id) do nothing;

  select quantity,reserved_quantity,damaged_quantity,quarantine_quantity
    into v_before,v_reserved,v_damaged,v_quarantine
  from public.location_stock_balances
  where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=p_variant_id
  for update;

  v_before:=coalesce(v_before,0);v_reserved:=coalesce(v_reserved,0);v_damaged:=coalesce(v_damaged,0);v_quarantine:=coalesce(v_quarantine,0);
  v_available:=v_before-v_reserved-v_damaged-v_quarantine;
  v_after:=v_before+coalesce(p_delta,0);

  if not p_allow_negative and coalesce(p_delta,0)<0 and v_available+coalesce(p_delta,0)<-0.000001 then
    raise exception 'Insufficient available stock at selected store. Available: %, requested: %',v_available,abs(p_delta);
  end if;
  if not p_allow_negative and v_after<0 then raise exception 'Insufficient physical stock at selected store';end if;

  select coalesce(cost_price,0) into v_cost from public.product_variants where id=p_variant_id and tenant_id=p_tenant_id;
  insert into public.location_product_settings(tenant_id,location_id,variant_id,active)
  values(p_tenant_id,p_location_id,p_variant_id,true) on conflict(tenant_id,location_id,variant_id) do nothing;

  update public.location_stock_balances
  set quantity=v_after,average_cost=case when v_cost<>0 then v_cost else average_cost end,updated_at=now()
  where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=p_variant_id;

  insert into public.location_stock_movements(tenant_id,location_id,variant_id,movement_type,quantity_delta,unit_cost,reference_type,reference_id,reference_number,note,created_by,device_id)
  values(p_tenant_id,p_location_id,p_variant_id,p_movement_type,p_delta,v_cost,p_reference_type,p_reference_id,p_reference_number,nullif(trim(coalesce(p_note,'')),''),auth.uid(),p_device_id);
  return v_after;
end $$;
revoke all on function private.v4_location_stock_apply(uuid,uuid,uuid,numeric,text,text,uuid,text,text,uuid,boolean) from public;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(106,'4.7.0','Foundation Lock & Production Stabilization','Available-stock validation moved inside row-locked stock mutation; first-movement race removed.')
on conflict(migration_no) do update set notes=excluded.notes;
commit;
select 'THQ ERP V4.7 migration 106 inventory atomicity ready' as status;
