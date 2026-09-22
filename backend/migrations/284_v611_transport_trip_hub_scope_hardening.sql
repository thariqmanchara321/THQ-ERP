-- THQ ERP v6.1.1
-- Transport Trip Hub permission-scope hardening.
-- Already live on dev as Supabase migration:
--   20260918103026 v611_transport_trip_hub_scope_hardening
-- SOURCE PARITY ONLY. DO NOT RE-RUN ON CURRENT DEV.

create or replace function public.transport_trip_hub_context_v611(
  p_tenant_id uuid,
  p_source_type text,
  p_source_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $function$
declare
  v_row public.transport_trip_hub_v611%rowtype;
  v_allowed boolean := false;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  v_allowed := case p_source_type
    when 'logistics_operation' then
      private.logistics_can_view_v61(p_tenant_id)
    when 'stock_transfer_trip' then
      private.erp_user_is_owner(p_tenant_id,auth.uid())
      or private.erp_has_permission(p_tenant_id,'vehicle_logistics.view')
      or private.erp_has_permission(p_tenant_id,'vehicle_logistics.reports')
      or private.erp_has_permission(p_tenant_id,'inventory.view')
      or private.erp_has_permission(p_tenant_id,'inventory.transfer')
      or private.erp_has_permission(p_tenant_id,'inventory.manage')
    when 'service_job' then
      private.erp_user_is_owner(p_tenant_id,auth.uid())
      or private.erp_has_permission(p_tenant_id,'transport_service.view')
      or private.erp_has_permission(p_tenant_id,'transport_service.create')
      or private.erp_has_permission(p_tenant_id,'transport_service.manage')
    else false
  end;

  if not v_allowed then
    raise exception 'Trip source view permission required';
  end if;

  select h.* into v_row
  from public.transport_trip_hub_v611 h
  where h.tenant_id=p_tenant_id
    and (
      (p_source_type='logistics_operation' and h.logistics_operation_id=p_source_id)
      or (p_source_type='stock_transfer_trip' and h.stock_trip_id=p_source_id)
      or (p_source_type='service_job' and h.service_job_id=p_source_id)
    )
  limit 1;

  if not found then
    return jsonb_build_object('found',false);
  end if;

  return jsonb_build_object(
    'found',true,
    'trip_id',v_row.id,
    'trip_number',v_row.trip_number,
    'trip_kind',v_row.trip_kind,
    'logistics_operation_id',v_row.logistics_operation_id,
    'stock_trip_id',v_row.stock_trip_id,
    'service_job_id',v_row.service_job_id
  );
end
$function$;

create or replace function public.transport_trip_hub_list_v611(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_kind text default null,
  p_query text default null,
  p_limit integer default 500
) returns table(
  trip_id uuid,
  trip_number text,
  trip_kind text,
  source_status text,
  source_reference text,
  source_date date,
  location_id uuid,
  vehicle_id uuid,
  vehicle_registration text,
  customer_id uuid,
  from_label text,
  to_label text,
  sale_id uuid,
  logistics_operation_id uuid,
  stock_trip_id uuid,
  service_job_id uuid,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $function$
declare
  v_can_ops boolean;
  v_can_stock boolean;
  v_can_customer boolean;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if p_kind is not null and p_kind not in ('operational','stock_transfer','customer_transport') then
    raise exception 'Invalid trip kind';
  end if;

  v_can_ops :=
    private.erp_user_is_owner(p_tenant_id,auth.uid())
    or private.erp_has_permission(p_tenant_id,'logistics_operations.view')
    or private.erp_has_permission(p_tenant_id,'logistics_operations.create')
    or private.erp_has_permission(p_tenant_id,'logistics_operations.execute')
    or private.erp_has_permission(p_tenant_id,'logistics_operations.manage')
    or private.erp_has_permission(p_tenant_id,'vehicle_logistics.view')
    or private.erp_has_permission(p_tenant_id,'vehicle_logistics.reports');

  v_can_stock :=
    private.erp_user_is_owner(p_tenant_id,auth.uid())
    or private.erp_has_permission(p_tenant_id,'vehicle_logistics.view')
    or private.erp_has_permission(p_tenant_id,'vehicle_logistics.reports')
    or private.erp_has_permission(p_tenant_id,'inventory.view')
    or private.erp_has_permission(p_tenant_id,'inventory.transfer')
    or private.erp_has_permission(p_tenant_id,'inventory.manage');

  v_can_customer :=
    private.erp_user_is_owner(p_tenant_id,auth.uid())
    or private.erp_has_permission(p_tenant_id,'transport_service.view')
    or private.erp_has_permission(p_tenant_id,'transport_service.create')
    or private.erp_has_permission(p_tenant_id,'transport_service.manage');

  if not (v_can_ops or v_can_stock or v_can_customer) then
    raise exception 'Transport and logistics view permission required';
  end if;

  return query
  select
    h.id,
    h.trip_number,
    h.trip_kind,
    coalesce(st.status, o.status, j.status, 'planned') as source_status,
    coalesce(st.trip_number, o.operation_number, j.job_number, h.trip_number) as source_reference,
    coalesce(o.operation_date, j.service_date, st.created_at::date, h.created_at::date) as source_date,
    coalesce(j.location_id, o.base_location_id, st.from_location_id) as location_id,
    coalesce(st.vehicle_id, j.vehicle_id, vr.vehicle_id) as vehicle_id,
    v.registration_number,
    j.customer_id,
    case
      when j.id is not null then j.from_location
      when st.id is not null then fl.name
      else null
    end as from_label,
    case
      when j.id is not null then j.to_location
      when st.id is not null then tl.name
      else null
    end as to_label,
    j.sale_id,
    h.logistics_operation_id,
    h.stock_trip_id,
    h.service_job_id,
    h.created_at
  from public.transport_trip_hub_v611 h
  left join public.logistics_operations_v61 o on o.id=h.logistics_operation_id and o.tenant_id=h.tenant_id
  left join public.transport_logistics_trips st on st.id=h.stock_trip_id and st.tenant_id=h.tenant_id
  left join public.service_jobs j on j.id=h.service_job_id and j.tenant_id=h.tenant_id
  left join lateral (
    select r.vehicle_id
    from public.logistics_vehicle_runs_v61 r
    where r.operation_id=o.id and r.tenant_id=h.tenant_id and r.status <> 'cancelled'
    order by r.run_no
    limit 1
  ) vr on true
  left join public.service_vehicles v on v.id=coalesce(st.vehicle_id,j.vehicle_id,vr.vehicle_id) and v.tenant_id=h.tenant_id
  left join public.business_locations fl on fl.id=st.from_location_id and fl.tenant_id=h.tenant_id
  left join public.business_locations tl on tl.id=st.to_location_id and tl.tenant_id=h.tenant_id
  where h.tenant_id=p_tenant_id
    and (
      (h.trip_kind='operational' and v_can_ops)
      or (h.trip_kind='stock_transfer' and v_can_stock)
      or (h.trip_kind='customer_transport' and v_can_customer)
    )
    and (p_kind is null or h.trip_kind=p_kind)
    and (
      p_location_id is null
      or j.location_id=p_location_id
      or o.base_location_id=p_location_id
      or st.from_location_id=p_location_id
      or st.to_location_id=p_location_id
    )
    and (
      nullif(trim(coalesce(p_query,'')),'') is null
      or h.trip_number ilike '%'||trim(p_query)||'%'
      or coalesce(st.trip_number,'') ilike '%'||trim(p_query)||'%'
      or coalesce(o.operation_number,'') ilike '%'||trim(p_query)||'%'
      or coalesce(j.job_number,'') ilike '%'||trim(p_query)||'%'
      or coalesce(v.registration_number,'') ilike '%'||trim(p_query)||'%'
      or coalesce(j.from_location,'') ilike '%'||trim(p_query)||'%'
      or coalesce(j.to_location,'') ilike '%'||trim(p_query)||'%'
    )
  order by coalesce(o.operation_date,j.service_date,st.created_at::date,h.created_at::date) desc, h.created_at desc
  limit greatest(1,least(coalesce(p_limit,500),1000));
end
$function$;

revoke all on function public.transport_trip_hub_context_v611(uuid,text,uuid) from public, anon;
revoke all on function public.transport_trip_hub_list_v611(uuid,uuid,text,text,integer) from public, anon;
grant execute on function public.transport_trip_hub_context_v611(uuid,text,uuid) to authenticated, service_role;
grant execute on function public.transport_trip_hub_list_v611(uuid,uuid,text,text,integer) to authenticated, service_role;
