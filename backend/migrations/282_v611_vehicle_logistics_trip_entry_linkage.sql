-- THQ ERP v6.1.1 Vehicle Logistics trip-entry / Stock Transfer linkage helper
-- Source-control parity for live migration v611_vehicle_logistics_trip_entry_linkage.
-- This function is read-only. It does not move stock, create sales, or post GST.

create or replace function public.logistics_transfer_trip_context_v1(
  p_tenant_id uuid,
  p_transfer_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_transfer public.stock_transfers%rowtype;
  v_trip public.transport_logistics_trips%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;

  select * into v_transfer
  from public.stock_transfers
  where id=p_transfer_id and tenant_id=p_tenant_id;
  if not found then raise exception 'Stock transfer not found'; end if;

  if not (
    private.erp_document_scope_allowed(p_tenant_id,v_transfer.from_location_id,null,'view')
    or private.erp_document_scope_allowed(p_tenant_id,v_transfer.to_location_id,null,'view')
  ) then raise exception 'Location access denied'; end if;

  select t.* into v_trip
  from public.transport_logistics_trip_documents d
  join public.transport_logistics_trips t
    on t.id=d.trip_id and t.tenant_id=d.tenant_id
  where d.tenant_id=p_tenant_id
    and d.stock_transfer_id=p_transfer_id
    and d.active
  order by
    case when t.status not in ('closed','cancelled') then 0 else 1 end,
    t.created_at desc
  limit 1;

  if v_trip.id is null then
    return jsonb_build_object(
      'assigned',false,
      'transfer_id',v_transfer.id,
      'transfer_number',v_transfer.transfer_number,
      'transfer_status',case when v_transfer.status='dispatched' then 'in_transit' else v_transfer.status end,
      'from_location_id',v_transfer.from_location_id,
      'to_location_id',v_transfer.to_location_id
    );
  end if;

  return jsonb_build_object(
    'assigned',true,
    'transfer_id',v_transfer.id,
    'transfer_number',v_transfer.transfer_number,
    'transfer_status',case when v_transfer.status='dispatched' then 'in_transit' else v_transfer.status end,
    'trip_id',v_trip.id,
    'trip_number',v_trip.trip_number,
    'trip_status',v_trip.status,
    'vehicle_id',v_trip.vehicle_id,
    'driver_name',v_trip.driver_name,
    'planned_departure_at',v_trip.planned_departure_at,
    'from_location_id',v_trip.from_location_id,
    'to_location_id',v_trip.to_location_id
  );
end $$;

revoke all on function public.logistics_transfer_trip_context_v1(uuid,uuid) from public,anon;
grant execute on function public.logistics_transfer_trip_context_v1(uuid,uuid) to authenticated,service_role;
