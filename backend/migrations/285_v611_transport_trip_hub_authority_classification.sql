-- THQ ERP v6.1.1
-- Transport Trip Hub authority classification correction.
-- LIVE on dev as Supabase migration:
--   20260918124419 v611_transport_trip_hub_authority_classification
--
-- SOURCE PARITY ONLY. DO NOT EXECUTE THIS FILE AGAIN ON CURRENT DEV.
-- A standalone Logistics Operation remains operational even when purpose=transfer.
-- Inventory authority exists only when a real Stock Transfer Trip is linked.

create or replace function private.transport_trip_hub_register_v611(
  p_tenant_id uuid,
  p_source_type text,
  p_source_id uuid
) returns uuid
language plpgsql
security definer
set search_path = public, private, pg_temp
as $function$
declare
  v_existing uuid;
  v_id uuid := gen_random_uuid();
  v_kind text;
  v_number text;
  v_source_date date := current_date;
begin
  if p_tenant_id is null or p_source_id is null then
    raise exception 'Tenant and source are required';
  end if;

  case p_source_type
    when 'logistics_operation' then
      select h.id into v_existing
      from public.transport_trip_hub_v611 h
      where h.logistics_operation_id = p_source_id;
      if v_existing is not null then return v_existing; end if;

      if not exists (
        select 1 from public.logistics_operations_v61 o
        where o.id = p_source_id and o.tenant_id = p_tenant_id
      ) then raise exception 'Logistics operation not found'; end if;

      select operation_date, 'operational'
      into v_source_date, v_kind
      from public.logistics_operations_v61
      where id = p_source_id and tenant_id = p_tenant_id;

    when 'stock_transfer_trip' then
      select h.id into v_existing
      from public.transport_trip_hub_v611 h
      where h.stock_trip_id = p_source_id;
      if v_existing is not null then return v_existing; end if;

      if not exists (
        select 1 from public.transport_logistics_trips t
        where t.id = p_source_id and t.tenant_id = p_tenant_id
      ) then raise exception 'Stock-transfer trip not found'; end if;

      select coalesce(created_at::date,current_date), 'stock_transfer'
      into v_source_date, v_kind
      from public.transport_logistics_trips
      where id = p_source_id and tenant_id = p_tenant_id;

    when 'service_job' then
      select h.id into v_existing
      from public.transport_trip_hub_v611 h
      where h.service_job_id = p_source_id;
      if v_existing is not null then return v_existing; end if;

      if not exists (
        select 1 from public.service_jobs j
        where j.id = p_source_id and j.tenant_id = p_tenant_id
      ) then raise exception 'Transport service job not found'; end if;

      select service_date, 'customer_transport'
      into v_source_date, v_kind
      from public.service_jobs
      where id = p_source_id and tenant_id = p_tenant_id;

    else
      raise exception 'Unsupported trip source type';
  end case;

  v_number := 'TRIP-' || to_char(coalesce(v_source_date,current_date),'YYYYMMDD')
    || '-' || upper(substr(replace(v_id::text,'-',''),1,8));

  insert into public.transport_trip_hub_v611(
    id, tenant_id, trip_number, trip_kind,
    logistics_operation_id, stock_trip_id, service_job_id,
    created_by
  ) values (
    v_id, p_tenant_id, v_number, v_kind,
    case when p_source_type='logistics_operation' then p_source_id end,
    case when p_source_type='stock_transfer_trip' then p_source_id end,
    case when p_source_type='service_job' then p_source_id end,
    auth.uid()
  ) on conflict do nothing;

  select h.id into v_existing
  from public.transport_trip_hub_v611 h
  where (p_source_type='logistics_operation' and h.logistics_operation_id=p_source_id)
     or (p_source_type='stock_transfer_trip' and h.stock_trip_id=p_source_id)
     or (p_source_type='service_job' and h.service_job_id=p_source_id);

  if v_existing is null then raise exception 'Unable to register trip source'; end if;
  return v_existing;
end
$function$;

update public.transport_trip_hub_v611
set trip_kind = 'operational', updated_at = now()
where logistics_operation_id is not null
  and stock_trip_id is null
  and service_job_id is null
  and trip_kind <> 'operational';