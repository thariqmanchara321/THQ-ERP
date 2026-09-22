-- THQ ERP v6.1.1
-- Transport & Logistics unification foundation.
-- Already live on dev as Supabase migration:
--   20260918102708 v611_transport_trip_hub_foundation
-- SOURCE PARITY ONLY. DO NOT RE-RUN ON CURRENT DEV.

create table if not exists public.transport_trip_hub_v611 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  trip_number text not null,
  trip_kind text not null check (trip_kind in ('operational','stock_transfer','customer_transport')),
  logistics_operation_id uuid null references public.logistics_operations_v61(id) on delete set null,
  stock_trip_id uuid null references public.transport_logistics_trips(id) on delete set null,
  service_job_id uuid null references public.service_jobs(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid null references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint transport_trip_hub_v611_tenant_number_uq unique (tenant_id, trip_number),
  constraint transport_trip_hub_v611_operation_uq unique (logistics_operation_id),
  constraint transport_trip_hub_v611_stock_trip_uq unique (stock_trip_id),
  constraint transport_trip_hub_v611_service_job_uq unique (service_job_id)
);

create index if not exists transport_trip_hub_v611_tenant_kind_idx
  on public.transport_trip_hub_v611(tenant_id, trip_kind, created_at desc);

alter table public.transport_trip_hub_v611 enable row level security;
revoke all on public.transport_trip_hub_v611 from public, anon, authenticated;

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

      select operation_date,
             case when purpose = 'transfer' then 'stock_transfer' else 'operational' end
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
  )
  values (
    v_id, p_tenant_id, v_number, v_kind,
    case when p_source_type='logistics_operation' then p_source_id end,
    case when p_source_type='stock_transfer_trip' then p_source_id end,
    case when p_source_type='service_job' then p_source_id end,
    auth.uid()
  )
  on conflict do nothing;

  select h.id into v_existing
  from public.transport_trip_hub_v611 h
  where (p_source_type='logistics_operation' and h.logistics_operation_id=p_source_id)
     or (p_source_type='stock_transfer_trip' and h.stock_trip_id=p_source_id)
     or (p_source_type='service_job' and h.service_job_id=p_source_id);

  if v_existing is null then
    raise exception 'Unable to register trip source';
  end if;
  return v_existing;
end
$function$;

create or replace function private.transport_trip_hub_source_insert_v611()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $function$
begin
  if tg_table_name = 'logistics_operations_v61' then
    perform private.transport_trip_hub_register_v611(new.tenant_id,'logistics_operation',new.id);
  elsif tg_table_name = 'transport_logistics_trips' then
    perform private.transport_trip_hub_register_v611(new.tenant_id,'stock_transfer_trip',new.id);
  elsif tg_table_name = 'service_jobs' then
    perform private.transport_trip_hub_register_v611(new.tenant_id,'service_job',new.id);
  end if;
  return new;
end
$function$;

drop trigger if exists trg_transport_trip_hub_operation_v611 on public.logistics_operations_v61;
create trigger trg_transport_trip_hub_operation_v611
after insert on public.logistics_operations_v61
for each row execute function private.transport_trip_hub_source_insert_v611();

drop trigger if exists trg_transport_trip_hub_stock_trip_v611 on public.transport_logistics_trips;
create trigger trg_transport_trip_hub_stock_trip_v611
after insert on public.transport_logistics_trips
for each row execute function private.transport_trip_hub_source_insert_v611();

drop trigger if exists trg_transport_trip_hub_service_job_v611 on public.service_jobs;
create trigger trg_transport_trip_hub_service_job_v611
after insert on public.service_jobs
for each row execute function private.transport_trip_hub_source_insert_v611();

insert into public.transport_trip_hub_v611(
  tenant_id, trip_number, trip_kind, logistics_operation_id, created_by, created_at
)
select
  o.tenant_id,
  'TRIP-' || to_char(o.operation_date,'YYYYMMDD') || '-' ||
    upper(substr(replace(o.id::text,'-',''),1,8)),
  case when o.purpose='transfer' then 'stock_transfer' else 'operational' end,
  o.id,
  o.created_by,
  o.created_at
from public.logistics_operations_v61 o
where not exists (
  select 1 from public.transport_trip_hub_v611 h
  where h.logistics_operation_id=o.id
)
on conflict do nothing;

insert into public.transport_trip_hub_v611(
  tenant_id, trip_number, trip_kind, stock_trip_id, created_by, created_at
)
select
  t.tenant_id,
  'TRIP-' || to_char(t.created_at::date,'YYYYMMDD') || '-' ||
    upper(substr(replace(t.id::text,'-',''),1,8)),
  'stock_transfer',
  t.id,
  t.created_by,
  t.created_at
from public.transport_logistics_trips t
where not exists (
  select 1 from public.transport_trip_hub_v611 h
  where h.stock_trip_id=t.id
)
on conflict do nothing;

insert into public.transport_trip_hub_v611(
  tenant_id, trip_number, trip_kind, service_job_id, created_by, created_at
)
select
  j.tenant_id,
  'TRIP-' || to_char(j.service_date,'YYYYMMDD') || '-' ||
    upper(substr(replace(j.id::text,'-',''),1,8)),
  'customer_transport',
  j.id,
  j.created_by,
  j.created_at
from public.service_jobs j
where not exists (
  select 1 from public.transport_trip_hub_v611 h
  where h.service_job_id=j.id
)
on conflict do nothing;

create or replace function public.transport_trip_hub_link_v611(
  p_tenant_id uuid,
  p_primary_source_type text,
  p_primary_source_id uuid,
  p_secondary_source_type text,
  p_secondary_source_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $function$
declare
  v_primary_id uuid;
  v_secondary_id uuid;
  v_primary public.transport_trip_hub_v611%rowtype;
  v_secondary public.transport_trip_hub_v611%rowtype;
  v_kind text;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if not (
    private.logistics_can_operate_v61(p_tenant_id)
    or private.erp_user_is_owner(p_tenant_id, auth.uid())
    or private.erp_has_permission(p_tenant_id,'transport_service.manage')
    or private.erp_has_permission(p_tenant_id,'inventory.manage')
  ) then
    raise exception 'Transport and logistics manage permission required';
  end if;

  v_primary_id := private.transport_trip_hub_register_v611(
    p_tenant_id,p_primary_source_type,p_primary_source_id
  );
  v_secondary_id := private.transport_trip_hub_register_v611(
    p_tenant_id,p_secondary_source_type,p_secondary_source_id
  );

  if v_primary_id = v_secondary_id then
    select * into v_primary from public.transport_trip_hub_v611 where id=v_primary_id;
    return to_jsonb(v_primary);
  end if;

  select * into v_primary
  from public.transport_trip_hub_v611
  where id=v_primary_id and tenant_id=p_tenant_id
  for update;

  select * into v_secondary
  from public.transport_trip_hub_v611
  where id=v_secondary_id and tenant_id=p_tenant_id
  for update;

  if v_primary.logistics_operation_id is not null
     and v_secondary.logistics_operation_id is not null
     and v_primary.logistics_operation_id <> v_secondary.logistics_operation_id then
    raise exception 'Both trip identities already contain different logistics operations';
  end if;
  if v_primary.stock_trip_id is not null
     and v_secondary.stock_trip_id is not null
     and v_primary.stock_trip_id <> v_secondary.stock_trip_id then
    raise exception 'Both trip identities already contain different stock-transfer trips';
  end if;
  if v_primary.service_job_id is not null
     and v_secondary.service_job_id is not null
     and v_primary.service_job_id <> v_secondary.service_job_id then
    raise exception 'Both trip identities already contain different customer transport jobs';
  end if;

  v_kind := case
    when coalesce(v_primary.service_job_id,v_secondary.service_job_id) is not null
      then 'customer_transport'
    when coalesce(v_primary.stock_trip_id,v_secondary.stock_trip_id) is not null
      then 'stock_transfer'
    else 'operational'
  end;

  update public.transport_trip_hub_v611
  set logistics_operation_id=coalesce(v_primary.logistics_operation_id,v_secondary.logistics_operation_id),
      stock_trip_id=coalesce(v_primary.stock_trip_id,v_secondary.stock_trip_id),
      service_job_id=coalesce(v_primary.service_job_id,v_secondary.service_job_id),
      trip_kind=v_kind,
      metadata=v_primary.metadata || v_secondary.metadata,
      updated_at=now()
  where id=v_primary_id;

  delete from public.transport_trip_hub_v611 where id=v_secondary_id;

  select * into v_primary from public.transport_trip_hub_v611 where id=v_primary_id;
  return to_jsonb(v_primary);
end
$function$;

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
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
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
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if p_kind is not null and p_kind not in ('operational','stock_transfer','customer_transport') then
    raise exception 'Invalid trip kind';
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

revoke all on function public.transport_trip_hub_link_v611(uuid,text,uuid,text,uuid) from public, anon;
revoke all on function public.transport_trip_hub_context_v611(uuid,text,uuid) from public, anon;
revoke all on function public.transport_trip_hub_list_v611(uuid,uuid,text,text,integer) from public, anon;
grant execute on function public.transport_trip_hub_link_v611(uuid,text,uuid,text,uuid) to authenticated, service_role;
grant execute on function public.transport_trip_hub_context_v611(uuid,text,uuid) to authenticated, service_role;
grant execute on function public.transport_trip_hub_list_v611(uuid,uuid,text,text,integer) to authenticated, service_role;
