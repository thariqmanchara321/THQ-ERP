-- THQ ERP v6.1 Vehicle Logistics reports/dashboard.
-- NOTE: flexi-erp-dev already has this migration applied by ChatGPT.
-- This file is for Git/source history and future environments only.

create or replace function public.logistics_reports_dashboard_v1(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_from_date date default (current_date - 30),
  p_to_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $function$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if p_from_date is null or p_to_date is null then
    raise exception 'Date range is required';
  end if;
  if p_to_date < p_from_date then
    raise exception 'To date must be on or after from date';
  end if;
  if (p_to_date - p_from_date) > 366 then
    raise exception 'Maximum logistics report range is 366 days';
  end if;
  if p_location_id is not null then
    if not exists (
      select 1 from public.business_locations l
      where l.id = p_location_id and l.tenant_id = p_tenant_id
        and coalesce(l.active,true)
    ) then raise exception 'Location not found'; end if;
    if not private.erp_document_scope_allowed(p_tenant_id,p_location_id,null,'view') then
      raise exception 'Location access denied';
    end if;
  end if;

  with accessible_trips as (
    select t.*,v.registration_number,v.vehicle_type,v.make_model,
      fl.location_code as from_location_code,fl.name as from_location_name,
      tl.location_code as to_location_code,tl.name as to_location_name
    from public.transport_logistics_trips t
    join public.service_vehicles v on v.id=t.vehicle_id and v.tenant_id=t.tenant_id
    join public.business_locations fl on fl.id=t.from_location_id
    join public.business_locations tl on tl.id=t.to_location_id
    where t.tenant_id=p_tenant_id
      and coalesce(t.dispatched_at,t.planned_departure_at,t.created_at)::date between p_from_date and p_to_date
      and (p_location_id is null or t.from_location_id=p_location_id or t.to_location_id=p_location_id)
      and (
        private.erp_document_scope_allowed(p_tenant_id,t.from_location_id,null,'view')
        or private.erp_document_scope_allowed(p_tenant_id,t.to_location_id,null,'view')
      )
  ),
  docs as (
    select d.trip_id,st.id as transfer_id,st.transfer_number,
      case when st.status='dispatched' then 'in_transit' else st.status end as transfer_status,
      st.from_location_id,st.to_location_id,
      coalesce(sum(i.dispatched_quantity),0) as dispatched_quantity,
      coalesce(sum(i.received_quantity),0) as received_quantity
    from public.transport_logistics_trip_documents d
    join accessible_trips t on t.id=d.trip_id
    join public.stock_transfers st on st.id=d.stock_transfer_id and st.tenant_id=d.tenant_id
    left join public.stock_transfer_items i on i.transfer_id=st.id
    where d.tenant_id=p_tenant_id and d.active
    group by d.trip_id,st.id,st.transfer_number,st.status,st.from_location_id,st.to_location_id
  ),
  receipt_totals as (
    select r.trip_id,r.stock_transfer_id as transfer_id,count(*) as receipt_count,
      coalesce(sum(r.good_quantity),0) as good_quantity,
      coalesce(sum(r.damaged_quantity),0) as damaged_quantity,
      coalesce(sum(r.missing_quantity),0) as missing_quantity,
      coalesce(sum(r.returned_quantity),0) as returned_quantity,
      max(r.received_at) as received_at
    from public.transport_logistics_receipts r
    join accessible_trips t on t.id=r.trip_id
    where r.tenant_id=p_tenant_id
    group by r.trip_id,r.stock_transfer_id
  ),
  trip_totals as (
    select t.id as trip_id,count(d.transfer_id) as document_count,
      coalesce(sum(d.dispatched_quantity),0) as dispatched_quantity,
      coalesce(sum(d.received_quantity),0) as received_quantity,
      coalesce(sum(rt.good_quantity),0) as good_quantity,
      coalesce(sum(rt.damaged_quantity),0) as damaged_quantity,
      coalesce(sum(rt.missing_quantity),0) as missing_quantity,
      coalesce(sum(rt.returned_quantity),0) as returned_quantity
    from accessible_trips t
    left join docs d on d.trip_id=t.id
    left join receipt_totals rt on rt.trip_id=d.trip_id and rt.transfer_id=d.transfer_id
    group by t.id
  ),
  line_rollup as (
    select r.trip_id,r.stock_transfer_id as transfer_id,rl.variant_id,p.name as product_name,pv.sku,rl.tracking_mode,
      coalesce(sum(rl.dispatched_quantity),0) as dispatched_quantity,
      coalesce(sum(rl.good_quantity),0) as good_quantity,
      coalesce(sum(rl.damaged_quantity),0) as damaged_quantity,
      coalesce(sum(rl.missing_quantity),0) as missing_quantity,
      coalesce(sum(rl.returned_quantity),0) as returned_quantity
    from public.transport_logistics_receipts r
    join accessible_trips t on t.id=r.trip_id
    join public.transport_logistics_receipt_lines rl on rl.receipt_id=r.id and rl.tenant_id=r.tenant_id
    join public.product_variants pv on pv.id=rl.variant_id and pv.tenant_id=r.tenant_id
    join public.products p on p.id=pv.product_id
    where r.tenant_id=p_tenant_id
    group by r.trip_id,r.stock_transfer_id,rl.variant_id,p.name,pv.sku,rl.tracking_mode
  ),
  trace_rows as (
    select r.trip_id,r.stock_transfer_id as transfer_id,r.receipt_number,r.received_at,
      st.transfer_number,t.trip_number,p.name as product_name,pv.sku,rl.tracking_mode,detail
    from public.transport_logistics_receipts r
    join accessible_trips t on t.id=r.trip_id
    join public.stock_transfers st on st.id=r.stock_transfer_id
    join public.transport_logistics_receipt_lines rl on rl.receipt_id=r.id and rl.tenant_id=r.tenant_id
    join public.product_variants pv on pv.id=rl.variant_id and pv.tenant_id=r.tenant_id
    join public.products p on p.id=pv.product_id
    cross join lateral jsonb_array_elements(coalesce(rl.details,'[]'::jsonb)) detail
    where r.tenant_id=p_tenant_id
      and (coalesce((detail->>'damaged_quantity')::numeric,0)>0
        or coalesce((detail->>'missing_quantity')::numeric,0)>0
        or coalesce((detail->>'returned_quantity')::numeric,0)>0
        or lower(coalesce(detail->>'outcome','')) in ('damaged','missing','returned','returned_to_origin','mixed'))
  )
  select jsonb_build_object(
    'filters',jsonb_build_object('from_date',p_from_date,'to_date',p_to_date,'location_id',p_location_id),
    'summary',jsonb_build_object(
      'total_trips',(select count(*) from accessible_trips),
      'planned',(select count(*) from accessible_trips where status='planned'),
      'loading',(select count(*) from accessible_trips where status='loading'),
      'in_transit',(select count(*) from accessible_trips where status='in_transit'),
      'arrived',(select count(*) from accessible_trips where status='arrived'),
      'received',(select count(*) from accessible_trips where status='received'),
      'closed',(select count(*) from accessible_trips where status='closed'),
      'cancelled',(select count(*) from accessible_trips where status='cancelled'),
      'documents',(select count(*) from docs),
      'dispatched_quantity',(select coalesce(sum(dispatched_quantity),0) from docs),
      'stock_in_transit_quantity',(select coalesce(sum(case when transfer_status='in_transit' then greatest(dispatched_quantity-received_quantity,0) else 0 end),0) from docs),
      'pending_receipts',(select count(*) from docs where transfer_status='in_transit'),
      'good_quantity',(select coalesce(sum(good_quantity),0) from receipt_totals),
      'damaged_quantity',(select coalesce(sum(damaged_quantity),0) from receipt_totals),
      'missing_quantity',(select coalesce(sum(missing_quantity),0) from receipt_totals),
      'returned_quantity',(select coalesce(sum(returned_quantity),0) from receipt_totals),
      'variance_receipts',(select count(*) from receipt_totals where damaged_quantity+missing_quantity+returned_quantity>0)
    ),
    'trip_register',coalesce((select jsonb_agg(jsonb_build_object(
      'trip_id',t.id,'trip_number',t.trip_number,'status',t.status,
      'from_location',t.from_location_code||' • '||t.from_location_name,
      'to_location',t.to_location_code||' • '||t.to_location_name,
      'vehicle_registration',t.registration_number,'vehicle_type',t.vehicle_type,'make_model',t.make_model,
      'driver_name',t.driver_name,'driver_phone',t.driver_phone,
      'planned_departure_at',t.planned_departure_at,'dispatched_at',t.dispatched_at,
      'arrived_at',t.arrived_at,'received_at',t.received_at,'closed_at',t.closed_at,
      'document_count',coalesce(tt.document_count,0),'dispatched_quantity',coalesce(tt.dispatched_quantity,0),
      'received_quantity',coalesce(tt.received_quantity,0),'damaged_quantity',coalesce(tt.damaged_quantity,0),
      'missing_quantity',coalesce(tt.missing_quantity,0),'returned_quantity',coalesce(tt.returned_quantity,0)
    ) order by coalesce(t.dispatched_at,t.planned_departure_at,t.created_at) desc)
      from accessible_trips t left join trip_totals tt on tt.trip_id=t.id),'[]'::jsonb),
    'stock_in_transit',coalesce((select jsonb_agg(jsonb_build_object(
      'trip_id',t.id,'trip_number',t.trip_number,'transfer_id',d.transfer_id,'transfer_number',d.transfer_number,
      'from_location',t.from_location_code||' • '||t.from_location_name,'to_location',t.to_location_code||' • '||t.to_location_name,
      'vehicle_registration',t.registration_number,'driver_name',t.driver_name,
      'dispatched_quantity',d.dispatched_quantity,'received_quantity',d.received_quantity,
      'remaining_quantity',greatest(d.dispatched_quantity-d.received_quantity,0),'dispatched_at',t.dispatched_at
    ) order by t.dispatched_at desc nulls last,d.transfer_number)
      from docs d join accessible_trips t on t.id=d.trip_id where d.transfer_status='in_transit'),'[]'::jsonb),
    'pending_receipts',coalesce((select jsonb_agg(jsonb_build_object(
      'trip_id',t.id,'trip_number',t.trip_number,'trip_status',t.status,'transfer_id',d.transfer_id,'transfer_number',d.transfer_number,
      'to_location',t.to_location_code||' • '||t.to_location_name,'vehicle_registration',t.registration_number,
      'arrived_at',t.arrived_at,'dispatched_quantity',d.dispatched_quantity
    ) order by coalesce(t.arrived_at,t.dispatched_at) desc nulls last)
      from docs d join accessible_trips t on t.id=d.trip_id where d.transfer_status='in_transit' and t.status in ('in_transit','arrived')),'[]'::jsonb),
    'variances',coalesce((select jsonb_agg(jsonb_build_object(
      'receipt_id',r.id,'receipt_number',r.receipt_number,'trip_number',t.trip_number,'transfer_number',st.transfer_number,
      'from_location',t.from_location_code||' • '||t.from_location_name,'to_location',t.to_location_code||' • '||t.to_location_name,
      'vehicle_registration',t.registration_number,'received_at',r.received_at,'good_quantity',r.good_quantity,
      'damaged_quantity',r.damaged_quantity,'missing_quantity',r.missing_quantity,'returned_quantity',r.returned_quantity,'note',r.note
    ) order by r.received_at desc)
      from public.transport_logistics_receipts r join accessible_trips t on t.id=r.trip_id
      join public.stock_transfers st on st.id=r.stock_transfer_id
      where r.tenant_id=p_tenant_id and r.damaged_quantity+r.missing_quantity+r.returned_quantity>0),'[]'::jsonb),
    'vehicle_movement',coalesce((select jsonb_agg(row_data order by (row_data->>'trips')::numeric desc) from (
      select jsonb_build_object('vehicle_id',t.vehicle_id,'registration_number',t.registration_number,
        'vehicle_type',max(t.vehicle_type),'make_model',max(t.make_model),'trips',count(distinct t.id),
        'documents',count(distinct d.transfer_id),'dispatched_quantity',coalesce(sum(d.dispatched_quantity),0),
        'damaged_quantity',coalesce(sum(rt.damaged_quantity),0),'missing_quantity',coalesce(sum(rt.missing_quantity),0),
        'returned_quantity',coalesce(sum(rt.returned_quantity),0)) as row_data
      from accessible_trips t left join docs d on d.trip_id=t.id
      left join receipt_totals rt on rt.trip_id=d.trip_id and rt.transfer_id=d.transfer_id
      group by t.vehicle_id,t.registration_number
    ) q),'[]'::jsonb),
    'product_movement',coalesce((select jsonb_agg(jsonb_build_object(
      'variant_id',q.variant_id,'product_name',q.product_name,'sku',q.sku,'tracking_mode',q.tracking_mode,
      'dispatched_quantity',q.dispatched_quantity,'good_quantity',q.good_quantity,'damaged_quantity',q.damaged_quantity,
      'missing_quantity',q.missing_quantity,'returned_quantity',q.returned_quantity
    ) order by q.dispatched_quantity desc,q.product_name,q.sku) from (
      select variant_id,product_name,sku,tracking_mode,sum(dispatched_quantity) as dispatched_quantity,
        sum(good_quantity) as good_quantity,sum(damaged_quantity) as damaged_quantity,
        sum(missing_quantity) as missing_quantity,sum(returned_quantity) as returned_quantity
      from line_rollup group by variant_id,product_name,sku,tracking_mode
    ) q),'[]'::jsonb),
    'trace_exceptions',coalesce((select jsonb_agg(jsonb_build_object(
      'trip_number',trip_number,'transfer_number',transfer_number,'receipt_number',receipt_number,'received_at',received_at,
      'product_name',product_name,'sku',sku,'tracking_mode',tracking_mode,'serial_number',detail->>'serial_number',
      'batch_number',detail->>'batch_number','outcome',detail->>'outcome','quantity',coalesce((detail->>'quantity')::numeric,0),
      'damaged_quantity',coalesce((detail->>'damaged_quantity')::numeric,0),'missing_quantity',coalesce((detail->>'missing_quantity')::numeric,0),
      'returned_quantity',coalesce((detail->>'returned_quantity')::numeric,0)
    ) order by received_at desc) from trace_rows),'[]'::jsonb)
  ) into v_result;
  return v_result;
end
$function$;

revoke execute on function public.logistics_reports_dashboard_v1(uuid,uuid,date,date) from public, anon;
grant execute on function public.logistics_reports_dashboard_v1(uuid,uuid,date,date) to authenticated, service_role;
