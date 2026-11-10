-- THQ ERP Material Yard workflow update.
-- Operational loads share the transport hub and fleet.
-- Invoice writers remain the stock, GST and accounting authority.
alter table public.transport_trip_hub_v611
  add column if not exists material_load_id uuid
    references public.aggregate_loads_v617(id) on delete cascade;
alter table public.transport_trip_hub_v611
  drop constraint if exists transport_trip_hub_v611_trip_kind_check;
alter table public.transport_trip_hub_v611
  add constraint transport_trip_hub_v611_trip_kind_check
  check (trip_kind in ('operational','stock_transfer','customer_transport','material_load'));
create unique index if not exists transport_trip_hub_v629_material_load_uq
  on public.transport_trip_hub_v611(material_load_id)
  where material_load_id is not null;

create or replace function private.aggregate_load_trip_sync_v629()
returns trigger language plpgsql security definer
set search_path=public,private,pg_temp as $$
begin
  if new.direction='direct_delivery' then return new; end if;
  insert into public.transport_trip_hub_v611(
    tenant_id,trip_number,trip_kind,material_load_id,created_by,created_at,updated_at
  ) values (
    new.tenant_id,'YARD-'||new.load_number,'material_load',new.id,
    new.created_by,new.created_at,new.updated_at
  )
  on conflict (material_load_id) where material_load_id is not null
  do update set updated_at=excluded.updated_at;
  return new;
end;
$$;
revoke all on function private.aggregate_load_trip_sync_v629() from public,anon,authenticated;
drop trigger if exists aggregate_load_trip_sync_v629 on public.aggregate_loads_v617;
create trigger aggregate_load_trip_sync_v629
after insert or update on public.aggregate_loads_v617
for each row execute function private.aggregate_load_trip_sync_v629();

insert into public.transport_trip_hub_v611(
  tenant_id,trip_number,trip_kind,material_load_id,created_by,created_at,updated_at
)
select l.tenant_id,'YARD-'||l.load_number,'material_load',l.id,l.created_by,l.created_at,l.updated_at
from public.aggregate_loads_v617 l where l.direction<>'direct_delivery'
on conflict (material_load_id) where material_load_id is not null do nothing;

create or replace function private.aggregate_load_can_view_v629(p_tenant_id uuid)
returns boolean language sql stable security definer
set search_path=public,private,pg_temp as $$
  select private.erp_user_has_tenant_access(p_tenant_id)
    and exists(select 1 from public.tenant_modules
      where tenant_id=p_tenant_id and module_key='aggregate_yard' and enabled)
    and (private.erp_has_permission(p_tenant_id,'aggregate_yard.view')
      or private.erp_has_permission(p_tenant_id,'aggregate_yard.manage'));
$$;
revoke all on function private.aggregate_load_can_view_v629(uuid) from public,anon,authenticated;

create or replace function public.transport_trip_hub_list_v629(
  p_tenant_id uuid,p_location_id uuid default null,p_kind text default null,
  p_query text default null,p_limit integer default 500,
  p_vehicle_id uuid default null,p_material_load_id uuid default null
) returns table(
  trip_id uuid,trip_number text,trip_kind text,source_status text,
  source_reference text,source_date date,location_id uuid,vehicle_id uuid,
  vehicle_registration text,customer_id uuid,from_label text,to_label text,
  sale_id uuid,logistics_operation_id uuid,stock_trip_id uuid,service_job_id uuid,
  created_at timestamptz,material_load_id uuid,purchase_id uuid,
  product_name text,quantity numeric,unit_code text,direction text,driver_name text
)
language plpgsql stable security definer
set search_path=public,private,pg_temp as $$
declare v_can_ops boolean;v_can_stock boolean;v_can_customer boolean;v_can_yard boolean;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if p_kind is not null and p_kind not in (
    'operational','stock_transfer','customer_transport','material_load'
  ) then raise exception 'Invalid trip kind'; end if;
  v_can_ops := private.erp_user_is_owner(p_tenant_id,auth.uid())
    or private.erp_has_permission(p_tenant_id,'logistics_operations.view')
    or private.erp_has_permission(p_tenant_id,'logistics_operations.create')
    or private.erp_has_permission(p_tenant_id,'logistics_operations.execute')
    or private.erp_has_permission(p_tenant_id,'logistics_operations.manage')
    or private.erp_has_permission(p_tenant_id,'vehicle_logistics.view')
    or private.erp_has_permission(p_tenant_id,'vehicle_logistics.reports');
  v_can_stock := private.erp_user_is_owner(p_tenant_id,auth.uid())
    or private.erp_has_permission(p_tenant_id,'vehicle_logistics.view')
    or private.erp_has_permission(p_tenant_id,'vehicle_logistics.reports')
    or private.erp_has_permission(p_tenant_id,'inventory.view')
    or private.erp_has_permission(p_tenant_id,'inventory.transfer')
    or private.erp_has_permission(p_tenant_id,'inventory.manage');
  v_can_customer := private.erp_user_is_owner(p_tenant_id,auth.uid())
    or private.erp_has_permission(p_tenant_id,'transport_service.view')
    or private.erp_has_permission(p_tenant_id,'transport_service.create')
    or private.erp_has_permission(p_tenant_id,'transport_service.manage');
  v_can_yard := private.aggregate_load_can_view_v629(p_tenant_id);
  if not (v_can_ops or v_can_stock or v_can_customer or v_can_yard) then
    raise exception 'Transport and logistics view permission required' using errcode='42501';
  end if;
  return query select
    h.id,h.trip_number,h.trip_kind,
    coalesce(l.status,st.status,o.status,j.status,'planned'),
    coalesce(l.load_number,st.trip_number,o.operation_number,j.job_number,h.trip_number),
    coalesce(l.load_date,o.operation_date,j.service_date,st.created_at::date,h.created_at::date),
    coalesce(l.location_id,j.location_id,o.base_location_id,st.from_location_id),
    coalesce(l.vehicle_id,st.vehicle_id,j.vehicle_id,vr.vehicle_id),
    coalesce(v.registration_number,l.vehicle_registration_snapshot),
    coalesce(l.customer_id,j.customer_id),
    case when l.id is not null then coalesce(nullif(l.source_name,''),s.name)
         when j.id is not null then j.from_location
         when st.id is not null then fl.name end,
    case when l.id is not null then coalesce(nullif(l.destination_name,''),c.name)
         when j.id is not null then j.to_location
         when st.id is not null then tl.name end,
    coalesce(l.sale_id,j.sale_id),
    h.logistics_operation_id,h.stock_trip_id,h.service_job_id,h.created_at,
    h.material_load_id,l.purchase_id,l.product_name_snapshot,l.quantity,l.unit_code,l.direction,
    coalesce(l.driver_name_snapshot,vr.driver_name_snapshot,v.driver_name)
  from public.transport_trip_hub_v611 h
  left join public.aggregate_loads_v617 l on l.id=h.material_load_id and l.tenant_id=h.tenant_id
  left join public.logistics_operations_v61 o on o.id=h.logistics_operation_id and o.tenant_id=h.tenant_id
  left join public.transport_logistics_trips st on st.id=h.stock_trip_id and st.tenant_id=h.tenant_id
  left join public.service_jobs j on j.id=h.service_job_id and j.tenant_id=h.tenant_id
  left join lateral (
    select r.vehicle_id,r.driver_name_snapshot from public.logistics_vehicle_runs_v61 r
    where r.operation_id=o.id and r.tenant_id=h.tenant_id and r.status<>'cancelled'
    order by r.run_no limit 1
  ) vr on true
  left join public.service_vehicles v on v.id=coalesce(l.vehicle_id,st.vehicle_id,j.vehicle_id,vr.vehicle_id) and v.tenant_id=h.tenant_id
  left join public.suppliers s on s.id=l.supplier_id and s.tenant_id=h.tenant_id
  left join public.customers c on c.id=l.customer_id and c.tenant_id=h.tenant_id
  left join public.business_locations fl on fl.id=st.from_location_id and fl.tenant_id=h.tenant_id
  left join public.business_locations tl on tl.id=st.to_location_id and tl.tenant_id=h.tenant_id
  where h.tenant_id=p_tenant_id
    and ((h.trip_kind='operational' and v_can_ops
          and private.erp_document_scope_allowed(p_tenant_id,o.base_location_id,p_location_id,'view'))
      or (h.trip_kind='stock_transfer' and v_can_stock
          and (private.erp_document_scope_allowed(p_tenant_id,st.from_location_id,p_location_id,'view')
            or private.erp_document_scope_allowed(p_tenant_id,st.to_location_id,p_location_id,'view')))
      or (h.trip_kind='customer_transport' and v_can_customer
          and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view'))
      or (h.trip_kind='material_load' and v_can_yard and l.direction<>'direct_delivery'
          and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view')))
    and (p_kind is null or h.trip_kind=p_kind)
    and (p_vehicle_id is null or p_vehicle_id=coalesce(l.vehicle_id,st.vehicle_id,j.vehicle_id,vr.vehicle_id))
    and (p_material_load_id is null or h.material_load_id=p_material_load_id)
    and (nullif(trim(coalesce(p_query,'')),'') is null
      or concat_ws(' ',h.trip_number,l.load_number,st.trip_number,o.operation_number,
         j.job_number,v.registration_number,l.vehicle_registration_snapshot,
         l.driver_name_snapshot,l.product_name_snapshot,l.source_name,l.destination_name,
         s.name,c.name,j.from_location,j.to_location,fl.name,tl.name)
         ilike '%'||trim(p_query)||'%')
  order by coalesce(l.load_date,o.operation_date,j.service_date,st.created_at::date,h.created_at::date) desc,h.created_at desc
  limit greatest(1,least(coalesce(p_limit,500),1000));
end;
$$;

create or replace function public.transport_trip_hub_context_v629(
  p_tenant_id uuid,p_source_type text,p_source_id uuid
) returns jsonb language plpgsql stable security definer
set search_path=public,private,pg_temp as $$
declare v_row public.transport_trip_hub_v611%rowtype;
begin
  if p_source_type<>'aggregate_load' then
    return public.transport_trip_hub_context_v611(p_tenant_id,p_source_type,p_source_id);
  end if;
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);
  select h.* into v_row from public.transport_trip_hub_v611 h
    join public.aggregate_loads_v617 l on l.id=h.material_load_id and l.tenant_id=h.tenant_id
  where h.tenant_id=p_tenant_id and h.material_load_id=p_source_id
    and private.erp_document_scope_allowed(p_tenant_id,l.location_id,null,'view');
  if not found then return jsonb_build_object('found',false); end if;
  return jsonb_build_object('found',true,'trip_id',v_row.id,'trip_number',v_row.trip_number,
    'trip_kind',v_row.trip_kind,'material_load_id',v_row.material_load_id);
end;
$$;
CREATE OR REPLACE FUNCTION public.aggregate_load_detail_v629(p_tenant_id uuid, p_load_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_result jsonb;
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  select jsonb_build_object(
    'load_id',l.id,
    'load_number',l.load_number,
    'load_date',l.load_date,
    'direction',l.direction,
    'status',l.status,
    'location_id',l.location_id,
    'variant_id',l.variant_id,
    'product_name',l.product_name_snapshot,
    'unit_code',l.unit_code,
    'quantity',l.quantity,
    'measurement_method',l.measurement_method,
    'body_length_ft',l.body_length_ft,
    'body_width_ft',l.body_width_ft,
    'body_height_ft',l.body_height_ft,
    'gross_weight_kg',l.gross_weight_kg,
    'tare_weight_kg',l.tare_weight_kg,
    'net_weight_kg',l.net_weight_kg,
    'vehicle_id',l.vehicle_id,
    'driver_id',l.driver_id,
    'vehicle_registration',l.vehicle_registration_snapshot,
    'driver_name',l.driver_name_snapshot,
    'supplier_name',s.name,'customer_name',c.name,
    'sale_number',sd.sale_number,'purchase_number',pd.purchase_number,
    'supplier_id',l.supplier_id,
    'customer_id',l.customer_id,
    'source_name',l.source_name,
    'destination_name',l.destination_name,
    'source_reference',l.source_reference,
    'freight_mode',l.freight_mode,
    'freight_amount',l.freight_amount,
    'capacity_override',l.capacity_override,
    'capacity_override_reason',l.capacity_override_reason,
    'notes',l.notes,
    'purchase_id',l.purchase_id,
    'sale_id',l.sale_id,
    'order_id',l.order_id,
    'order_line_id',l.order_line_id
  )
  into v_result
  from public.aggregate_loads_v617 l
  left join public.suppliers s on s.id=l.supplier_id and s.tenant_id=l.tenant_id
  left join public.customers c on c.id=l.customer_id and c.tenant_id=l.tenant_id
  left join public.sales sd on sd.id=l.sale_id and sd.tenant_id=l.tenant_id
  left join public.purchases pd on pd.id=l.purchase_id and pd.tenant_id=l.tenant_id
  where l.id=p_load_id
    and l.tenant_id=p_tenant_id
    and private.erp_document_scope_allowed(p_tenant_id,l.location_id,null,'view');

  if v_result is null then
    raise exception 'Load not found';
  end if;

  return v_result;
end
$function$
;

CREATE OR REPLACE FUNCTION public.aggregate_load_confirm_v628(p_tenant_id uuid, p_load_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_row public.aggregate_loads_v617%rowtype;
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  select *
  into v_row
  from public.aggregate_loads_v617
  where id=p_load_id
    and tenant_id=p_tenant_id
  for update;

  if v_row.id is null then
    raise exception 'Load not found';
  end if;

  perform private.v4_location_access(p_tenant_id,v_row.location_id,'operate');

  if v_row.status='completed' then
    return jsonb_build_object(
      'success',true,
      'already_confirmed',true,
      'load_id',v_row.id,
      'load_number',v_row.load_number,
      'status','completed'
    );
  end if;

  if v_row.status='cancelled' then
    raise exception 'Cancelled load cannot be confirmed';
  end if;

  update public.aggregate_loads_v617
  set status='completed',
      updated_by=auth.uid(),
      updated_at=now()
  where id=v_row.id
    and tenant_id=p_tenant_id;

  insert into public.aggregate_load_events_v617(
    tenant_id,load_id,event_type,from_status,to_status,note,created_by
  )
  values(
    p_tenant_id,v_row.id,'confirmed',v_row.status,'completed',
    'Load confirmed',auth.uid()
  );

  perform private.business_audit_write_v471(
    p_tenant_id,
    'aggregate_load.confirm',
    'aggregate_load',
    v_row.id,
    v_row.load_number,
    to_jsonb(v_row),
    jsonb_build_object('status','completed')
  );

  return jsonb_build_object(
    'success',true,
    'already_confirmed',false,
    'load_id',v_row.id,
    'load_number',v_row.load_number,
    'status','completed'
  );
end
$function$
;


-- Serialize the load before the authoritative writer. This transaction holds
-- the load lock until the invoice and its link have both succeeded.
create or replace function private.aggregate_load_document_lock_v629(
  p_tenant_id uuid,p_load_id uuid,p_direction text,p_location_id uuid
) returns public.aggregate_loads_v617 language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare v_load public.aggregate_loads_v617%rowtype;
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);
  select * into v_load from public.aggregate_loads_v617
    where id=p_load_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Load not found'; end if;
  perform private.v4_location_access(p_tenant_id,v_load.location_id,'operate');
  if v_load.direction<>p_direction then raise exception 'Invoice type does not match the load direction'; end if;
  if v_load.status<>'completed' then raise exception 'Confirm the load before creating its invoice'; end if;
  if v_load.location_id is distinct from p_location_id then
    raise exception 'Invoice location must match the load yard/store';
  end if;
  return v_load;
end;
$$;
revoke all on function private.aggregate_load_document_lock_v629(uuid,uuid,text,uuid) from public,anon,authenticated;

create or replace function public.aggregate_load_sale_create_v629(
  p_tenant_id uuid,p_load_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,
  p_items jsonb,p_payment_allocations jsonb,p_notes text,p_location_id uuid,
  p_device_id uuid,p_request_id text,p_supply_type text,p_place_of_supply_code text,
  p_charge_selections jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare v_load public.aggregate_loads_v617%rowtype;v_result jsonb;v_id uuid;
begin
  v_load := private.aggregate_load_document_lock_v629(p_tenant_id,p_load_id,'outbound',p_location_id);
  if v_load.customer_id is not null and v_load.customer_id is distinct from p_customer_id then
    raise exception 'Sale customer must match the confirmed load customer';
  end if;
  v_result := public.gst_client_sale_create_v611(
    p_tenant_id,p_customer_id,p_sale_date,p_due_date,p_items,p_payment_allocations,
    p_notes,p_location_id,p_device_id,p_request_id,p_supply_type,p_place_of_supply_code,p_charge_selections
  );
  v_id := nullif(v_result->>'sale_id','')::uuid;
  if v_id is null then raise exception 'Authoritative Sale did not return a sale ID'; end if;
  perform public.aggregate_load_link_document_v617(p_tenant_id,p_load_id,'sale',v_id);
  update public.aggregate_loads_v617 set customer_id=p_customer_id where id=p_load_id and tenant_id=p_tenant_id and customer_id is null;
  return v_result||jsonb_build_object('material_load_id',p_load_id,'load_linked',true);
end;
$$;

create or replace function public.aggregate_load_purchase_create_v629(
  p_tenant_id uuid,p_load_id uuid,p_supplier_id uuid,p_supplier_invoice_number text,
  p_purchase_date date,p_due_date date,p_items jsonb,p_additional_charges numeric default 0,
  p_round_off numeric default 0,p_initial_payment numeric default 0,p_payment_method text default 'cash',
  p_payment_reference text default null,p_notes text default null,p_location_id uuid default null,
  p_device_id uuid default null,p_request_id text default null,
  p_supply_type text default null,p_place_of_supply_code text default null
) returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare v_load public.aggregate_loads_v617%rowtype;v_result jsonb;v_id uuid;
begin
  v_load := private.aggregate_load_document_lock_v629(p_tenant_id,p_load_id,'inbound',p_location_id);
  if v_load.supplier_id is not null and v_load.supplier_id is distinct from p_supplier_id then
    raise exception 'Purchase supplier must match the confirmed load supplier';
  end if;
  v_result := public.gst_purchase_create_v520(
    p_tenant_id=>p_tenant_id,p_supplier_id=>p_supplier_id,
    p_supplier_invoice_number=>p_supplier_invoice_number,p_purchase_date=>p_purchase_date,
    p_due_date=>p_due_date,p_items=>p_items,p_additional_charges=>p_additional_charges,
    p_round_off=>p_round_off,p_initial_payment=>p_initial_payment,p_payment_method=>p_payment_method,
    p_payment_reference=>p_payment_reference,p_notes=>p_notes,p_location_id=>p_location_id,
    p_device_id=>p_device_id,p_request_id=>p_request_id,
    p_supply_type=>p_supply_type,p_place_of_supply_code=>p_place_of_supply_code
  );
  v_id := nullif(v_result->>'purchase_id','')::uuid;
  if v_id is null then raise exception 'Authoritative Purchase did not return a purchase ID'; end if;
  perform public.aggregate_load_link_document_v617(p_tenant_id,p_load_id,'purchase',v_id);
  update public.aggregate_loads_v617 set supplier_id=p_supplier_id where id=p_load_id and tenant_id=p_tenant_id and supplier_id is null;
  return v_result||jsonb_build_object('material_load_id',p_load_id,'load_linked',true);
end;
$$;
revoke all on function public.transport_trip_hub_list_v629(uuid,uuid,text,text,integer,uuid,uuid) from public,anon;
grant execute on function public.transport_trip_hub_list_v629(uuid,uuid,text,text,integer,uuid,uuid) to authenticated,service_role;
revoke all on function public.transport_trip_hub_context_v629(uuid,text,uuid) from public,anon;
grant execute on function public.transport_trip_hub_context_v629(uuid,text,uuid) to authenticated,service_role;
revoke all on function public.aggregate_load_detail_v629(uuid,uuid) from public,anon;
grant execute on function public.aggregate_load_detail_v629(uuid,uuid) to authenticated,service_role;
revoke all on function public.aggregate_load_sale_create_v629(uuid,uuid,uuid,date,date,jsonb,jsonb,text,uuid,uuid,text,text,text,jsonb) from public,anon;
grant execute on function public.aggregate_load_sale_create_v629(uuid,uuid,uuid,date,date,jsonb,jsonb,text,uuid,uuid,text,text,text,jsonb) to authenticated,service_role;
revoke all on function public.aggregate_load_purchase_create_v629(uuid,uuid,uuid,text,date,date,jsonb,numeric,numeric,numeric,text,text,text,uuid,uuid,text,text,text) from public,anon;
grant execute on function public.aggregate_load_purchase_create_v629(uuid,uuid,uuid,text,date,date,jsonb,numeric,numeric,numeric,text,text,text,uuid,uuid,text,text,text) to authenticated,service_role;


-- Use the same authorized location scope in the yard and transport lists.
CREATE OR REPLACE FUNCTION public.aggregate_load_list_v629(p_tenant_id uuid, p_location_id uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text, p_query text DEFAULT NULL::text, p_limit integer DEFAULT 300)
 RETURNS TABLE(load_id uuid, load_number text, load_date date, direction text, status text, location_id uuid, variant_id uuid, supplier_id uuid, customer_id uuid, product_name text, quantity numeric, unit_code text, measurement_method text, vehicle_id uuid, vehicle_registration text, driver_name text, supplier_name text, customer_name text, source_name text, destination_name text, source_reference text, freight_mode text, freight_amount numeric, purchase_id uuid, sale_id uuid, order_id uuid, order_line_id uuid, order_number text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  return query
  select
    l.id,l.load_number,l.load_date,l.direction,l.status,l.location_id,
    l.variant_id,l.supplier_id,l.customer_id,l.product_name_snapshot,
    l.quantity,l.unit_code,l.measurement_method,l.vehicle_id,
    l.vehicle_registration_snapshot,l.driver_name_snapshot,
    s.name,c.name,l.source_name,l.destination_name,l.source_reference,
    l.freight_mode,l.freight_amount,l.purchase_id,l.sale_id,
    l.order_id,l.order_line_id,o.order_number,l.created_at
  from public.aggregate_loads_v617 l
  left join public.suppliers s
    on s.id=l.supplier_id and s.tenant_id=l.tenant_id
  left join public.customers c
    on c.id=l.customer_id and c.tenant_id=l.tenant_id
  left join public.aggregate_orders_v618 o
    on o.id=l.order_id and o.tenant_id=l.tenant_id
  where l.tenant_id=p_tenant_id
    and l.direction<>'direct_delivery'
    and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view')
    and (p_status is null or trim(p_status)='' or l.status=lower(trim(p_status)))
    and (
      p_query is null or trim(p_query)=''
      or l.load_number ilike '%'||trim(p_query)||'%'
      or l.product_name_snapshot ilike '%'||trim(p_query)||'%'
      or coalesce(l.vehicle_registration_snapshot,'') ilike '%'||trim(p_query)||'%'
      or coalesce(l.driver_name_snapshot,'') ilike '%'||trim(p_query)||'%'
      or coalesce(s.name,'') ilike '%'||trim(p_query)||'%'
      or coalesce(c.name,'') ilike '%'||trim(p_query)||'%'
      or coalesce(o.order_number,'') ilike '%'||trim(p_query)||'%'
    )
  order by l.created_at desc
  limit greatest(1,least(coalesce(p_limit,300),1000));
end
$function$
;

CREATE OR REPLACE FUNCTION public.aggregate_yard_context_v629(p_tenant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare v_result jsonb;
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  select jsonb_build_object(
    'products',coalesce((
      select jsonb_agg(jsonb_build_object(
        'variant_id',v.id,'name',p.name,'variant_name',v.name,'sku',v.sku,
        'cost_price',v.cost_price,'selling_price',v.selling_price,
        'base_unit_code',bu.code,
        'sale_units',coalesce((
          select jsonb_agg(jsonb_build_object(
            'unit_id',u.id,'code',u.code,'name',u.name,'is_base',pu.is_base,
            'is_default_sale',pu.is_default_sale,
            'conversion_to_base',pu.conversion_to_base,'sale_price',pu.sale_price
          ) order by pu.is_default_sale desc,pu.is_base desc,u.code)
          from public.product_units_v481 pu
          join public.inventory_units_v481 u
            on u.id=pu.unit_id and u.tenant_id=pu.tenant_id
          where pu.tenant_id=p_tenant_id and pu.variant_id=v.id
            and pu.active and pu.allow_sale and u.active
        ),'[]'::jsonb)
      ) order by p.name,v.name)
      from public.product_variants v
      join public.products p
        on p.id=v.product_id and p.tenant_id=v.tenant_id
      left join public.product_units_v481 pbu
        on pbu.tenant_id=v.tenant_id
       and pbu.variant_id=v.id
       and pbu.is_base
       and pbu.active
      left join public.inventory_units_v481 bu
        on bu.id=pbu.unit_id
       and bu.tenant_id=pbu.tenant_id
       and bu.active
      where v.tenant_id=p_tenant_id and v.status='active' and p.status='active'
    ),'[]'::jsonb),
    'vehicles',coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehicle_id',v.id,'location_id',v.location_id,'registration_number',v.registration_number,
        'vehicle_type',v.vehicle_type,'capacity',v.capacity,
        'capacity_unit',v.capacity_unit,'driver_name',v.driver_name,
        'driver_phone',v.driver_phone,
        'ownership_type',coalesce(ap.ownership_type,'hired'),
        'owner_name',ap.owner_name,'owner_phone',ap.owner_phone,
        'body_length_ft',ap.body_length_ft,'body_width_ft',ap.body_width_ft,
        'body_height_ft',ap.body_height_ft,
        'nominal_capacity_cft',coalesce(
          ap.nominal_capacity_cft,
          case when upper(coalesce(v.capacity_unit,''))='CFT'
               then v.capacity else null end
        ),
        'tare_weight_kg',ap.tare_weight_kg,
        'max_payload_kg',ap.max_payload_kg,
        'default_freight',coalesce(ap.default_freight,0)
      ) order by v.registration_number)
      from public.service_vehicles v
      left join public.aggregate_vehicle_profiles_v617 ap
        on ap.tenant_id=v.tenant_id and ap.vehicle_id=v.id and ap.active
      where v.tenant_id=p_tenant_id and v.active
        and private.erp_document_scope_allowed(p_tenant_id,v.location_id,null,'view')
    ),'[]'::jsonb),
    'drivers',coalesce((
      select jsonb_agg(jsonb_build_object(
        'driver_id',d.id,'name',d.name,'phone',d.phone,
        'license_number',d.license_number
      ) order by d.name)
      from public.logistics_drivers_v61 d
      where d.tenant_id=p_tenant_id and d.active
    ),'[]'::jsonb),
    'suppliers',coalesce((
      select jsonb_agg(jsonb_build_object(
        'supplier_id',s.id,'name',s.name,'phone',s.phone
      ) order by s.name)
      from public.suppliers s
      where s.tenant_id=p_tenant_id and s.status='active'
    ),'[]'::jsonb),
    'customers',coalesce((
      select jsonb_agg(jsonb_build_object(
        'customer_id',c.id,'name',c.name,'phone',c.phone,'is_walk_in',c.is_walk_in
      ) order by c.name)
      from public.customers c
      where c.tenant_id=p_tenant_id and c.status='active'
    ),'[]'::jsonb),
    'locations',coalesce((
      select jsonb_agg(jsonb_build_object(
        'location_id',l.id,'code',l.location_code,'name',l.name,'type',l.location_type
      ) order by l.sort_order,l.name)
      from public.business_locations l
      where l.tenant_id=p_tenant_id
        and l.active
        and private.erp_document_scope_allowed(p_tenant_id,l.id,null,'view')
        and not exists(
          select 1
          from public.aggregate_direct_transit_locations_v621 m
          where m.tenant_id=l.tenant_id
            and m.transit_location_id=l.id
        )
    ),'[]'::jsonb)
  ) into v_result;

  return v_result;
end
$function$
;

revoke all on function public.aggregate_load_list_v629(uuid,uuid,text,text,integer) from public,anon;
grant execute on function public.aggregate_load_list_v629(uuid,uuid,text,text,integer) to authenticated,service_role;
revoke all on function public.aggregate_yard_context_v629(uuid) from public,anon;
grant execute on function public.aggregate_yard_context_v629(uuid) to authenticated,service_role;
