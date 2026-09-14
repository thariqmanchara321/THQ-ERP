-- THQ ERP v6.1 Vehicle Logistics - Operational hardening source
-- Live Supabase migrations were applied directly to flexi-erp-dev on 2026-09-14.
-- This consolidated source file exists for Git history and future environments.
-- It does NOT change stock/accounting when resolving exceptions.
--
-- Proof files use the existing THQ ERP `thq-assets` bucket under:
--   <tenant_id>/logistics/<trip_id>/<unique_filename>
-- Evidence metadata itself is RPC-only and audit logged.

create table if not exists public.transport_logistics_evidence (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  trip_id uuid not null references public.transport_logistics_trips(id) on delete cascade,
  stock_transfer_id uuid references public.stock_transfers(id),
  receipt_id uuid references public.transport_logistics_receipts(id),
  evidence_type text not null,
  file_name text not null,
  storage_path text not null,
  mime_type text not null,
  file_size bigint not null,
  note text,
  captured_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  constraint transport_logistics_evidence_type_chk check (
    evidence_type in (
      'dispatch_photo','arrival_photo','delivery_photo',
      'damage_photo','receiver_signature','other'
    )
  ),
  constraint transport_logistics_evidence_mime_chk check (
    mime_type in ('image/jpeg','image/png')
  ),
  constraint transport_logistics_evidence_size_chk check (
    file_size > 0 and file_size <= 5242880
  ),
  constraint transport_logistics_evidence_storage_uq unique (storage_path)
);

create index if not exists transport_logistics_evidence_trip_idx
  on public.transport_logistics_evidence(tenant_id,trip_id,created_at desc);
create index if not exists transport_logistics_evidence_receipt_idx
  on public.transport_logistics_evidence(tenant_id,receipt_id,created_at desc)
  where receipt_id is not null;
create index if not exists transport_logistics_evidence_trip_fk_idx
  on public.transport_logistics_evidence(trip_id);
create index if not exists transport_logistics_evidence_transfer_fk_idx
  on public.transport_logistics_evidence(stock_transfer_id)
  where stock_transfer_id is not null;
create index if not exists transport_logistics_evidence_receipt_fk_idx
  on public.transport_logistics_evidence(receipt_id)
  where receipt_id is not null;

alter table public.transport_logistics_evidence enable row level security;
revoke all on table public.transport_logistics_evidence
  from public, anon, authenticated;
grant all on table public.transport_logistics_evidence to service_role;

create table if not exists public.transport_logistics_exceptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  trip_id uuid not null references public.transport_logistics_trips(id) on delete cascade,
  receipt_id uuid not null references public.transport_logistics_receipts(id) on delete cascade,
  receipt_line_id uuid not null references public.transport_logistics_receipt_lines(id) on delete cascade,
  stock_transfer_id uuid not null references public.stock_transfers(id),
  variant_id uuid not null references public.product_variants(id),
  exception_type text not null,
  quantity numeric not null,
  status text not null default 'open',
  resolution_code text,
  resolution_note text,
  external_reference text,
  opened_at timestamptz not null default now(),
  opened_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  resolved_at timestamptz,
  resolved_by uuid,
  constraint transport_logistics_exception_type_chk check (
    exception_type in ('damaged','missing')
  ),
  constraint transport_logistics_exception_qty_chk check (quantity > 0),
  constraint transport_logistics_exception_status_chk check (
    status in ('open','investigating','resolved','waived')
  ),
  constraint transport_logistics_exception_line_type_uq
    unique (receipt_line_id,exception_type)
);

create index if not exists transport_logistics_exceptions_tenant_status_idx
  on public.transport_logistics_exceptions(tenant_id,status,opened_at desc);
create index if not exists transport_logistics_exceptions_trip_idx
  on public.transport_logistics_exceptions(tenant_id,trip_id,status,opened_at desc);
create index if not exists transport_logistics_exceptions_trip_fk_idx
  on public.transport_logistics_exceptions(trip_id);
create index if not exists transport_logistics_exceptions_receipt_fk_idx
  on public.transport_logistics_exceptions(receipt_id);
create index if not exists transport_logistics_exceptions_transfer_fk_idx
  on public.transport_logistics_exceptions(stock_transfer_id);
create index if not exists transport_logistics_exceptions_variant_fk_idx
  on public.transport_logistics_exceptions(variant_id);

alter table public.transport_logistics_exceptions enable row level security;
revoke all on table public.transport_logistics_exceptions
  from public, anon, authenticated;
grant all on table public.transport_logistics_exceptions to service_role;

create or replace function private.v610_logistics_exception_capture()
returns trigger
language plpgsql
set search_path to 'public','private','pg_temp'
as $$
declare
  r public.transport_logistics_receipts%rowtype;
begin
  select * into r
  from public.transport_logistics_receipts
  where id=new.receipt_id and tenant_id=new.tenant_id;

  if not found then
    return new;
  end if;

  if coalesce(new.damaged_quantity,0)>0 then
    insert into public.transport_logistics_exceptions(
      tenant_id,trip_id,receipt_id,receipt_line_id,stock_transfer_id,
      variant_id,exception_type,quantity,status,opened_by,updated_by
    ) values(
      new.tenant_id,r.trip_id,r.id,new.id,r.stock_transfer_id,
      new.variant_id,'damaged',new.damaged_quantity,'open',auth.uid(),auth.uid()
    )
    on conflict (receipt_line_id,exception_type) do nothing;
  end if;

  if coalesce(new.missing_quantity,0)>0 then
    insert into public.transport_logistics_exceptions(
      tenant_id,trip_id,receipt_id,receipt_line_id,stock_transfer_id,
      variant_id,exception_type,quantity,status,opened_by,updated_by
    ) values(
      new.tenant_id,r.trip_id,r.id,new.id,r.stock_transfer_id,
      new.variant_id,'missing',new.missing_quantity,'open',auth.uid(),auth.uid()
    )
    on conflict (receipt_line_id,exception_type) do nothing;
  end if;

  return new;
end
$$;

revoke all on function private.v610_logistics_exception_capture()
  from public, anon, authenticated;

drop trigger if exists transport_logistics_receipt_line_exception_capture
  on public.transport_logistics_receipt_lines;
create trigger transport_logistics_receipt_line_exception_capture
after insert on public.transport_logistics_receipt_lines
for each row execute function private.v610_logistics_exception_capture();

insert into public.transport_logistics_exceptions(
  tenant_id,trip_id,receipt_id,receipt_line_id,stock_transfer_id,
  variant_id,exception_type,quantity,status,opened_at,opened_by,
  updated_at,updated_by
)
select
  l.tenant_id,r.trip_id,r.id,l.id,r.stock_transfer_id,l.variant_id,
  'damaged',l.damaged_quantity,'open',coalesce(r.received_at,r.created_at),
  null,coalesce(r.received_at,r.created_at),null
from public.transport_logistics_receipt_lines l
join public.transport_logistics_receipts r
  on r.id=l.receipt_id and r.tenant_id=l.tenant_id
where l.damaged_quantity>0
on conflict (receipt_line_id,exception_type) do nothing;

insert into public.transport_logistics_exceptions(
  tenant_id,trip_id,receipt_id,receipt_line_id,stock_transfer_id,
  variant_id,exception_type,quantity,status,opened_at,opened_by,
  updated_at,updated_by
)
select
  l.tenant_id,r.trip_id,r.id,l.id,r.stock_transfer_id,l.variant_id,
  'missing',l.missing_quantity,'open',coalesce(r.received_at,r.created_at),
  null,coalesce(r.received_at,r.created_at),null
from public.transport_logistics_receipt_lines l
join public.transport_logistics_receipts r
  on r.id=l.receipt_id and r.tenant_id=l.tenant_id
where l.missing_quantity>0
on conflict (receipt_line_id,exception_type) do nothing;

create or replace function public.logistics_evidence_register_v1(
  p_tenant_id uuid,
  p_trip_id uuid,
  p_evidence_type text,
  p_file_name text,
  p_storage_path text,
  p_mime_type text,
  p_file_size bigint,
  p_note text default null,
  p_stock_transfer_id uuid default null,
  p_receipt_id uuid default null,
  p_captured_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','storage','pg_temp'
as $$
declare
  t public.transport_logistics_trips%rowtype;
  v_id uuid;
  v_type text:=lower(trim(coalesce(p_evidence_type,'')));
  v_path text:=trim(coalesce(p_storage_path,''));
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if not (
    private.erp_user_is_owner(p_tenant_id,auth.uid())
    or private.erp_has_permission(p_tenant_id,'transport_service.create')
    or private.erp_has_permission(p_tenant_id,'transport_service.manage')
    or private.erp_has_permission(p_tenant_id,'inventory.transfer')
    or private.erp_has_permission(p_tenant_id,'inventory.manage')
  ) then
    raise exception 'Logistics evidence permission required';
  end if;

  select * into t
  from public.transport_logistics_trips
  where id=p_trip_id and tenant_id=p_tenant_id;
  if not found then
    raise exception 'Trip not found';
  end if;

  if v_type='dispatch_photo' then
    perform private.v4_location_access(
      p_tenant_id,t.from_location_id,'operate'
    );
  else
    perform private.v4_location_access(
      p_tenant_id,t.to_location_id,'operate'
    );
  end if;

  if v_type not in (
    'dispatch_photo','arrival_photo','delivery_photo',
    'damage_photo','receiver_signature','other'
  ) then
    raise exception 'Invalid evidence type';
  end if;
  if trim(coalesce(p_file_name,''))='' then
    raise exception 'File name is required';
  end if;
  if lower(trim(coalesce(p_mime_type,''))) not in ('image/jpeg','image/png') then
    raise exception 'Only JPEG or PNG evidence is allowed';
  end if;
  if coalesce(p_file_size,0)<=0 or p_file_size>5242880 then
    raise exception 'Evidence file must be between 1 byte and 5 MB';
  end if;
  if v_path not like
    p_tenant_id::text||'/logistics/'||p_trip_id::text||'/%'
  then
    raise exception 'Invalid evidence storage path';
  end if;
  if not exists(
    select 1 from storage.objects o
    where o.bucket_id='thq-assets' and o.name=v_path
  ) then
    raise exception 'Evidence file was not uploaded';
  end if;

  if p_stock_transfer_id is not null and not exists(
    select 1
    from public.transport_logistics_trip_documents d
    where d.tenant_id=p_tenant_id
      and d.trip_id=p_trip_id
      and d.stock_transfer_id=p_stock_transfer_id
      and d.active
  ) then
    raise exception 'Stock transfer is not linked to this trip';
  end if;

  if p_receipt_id is not null and not exists(
    select 1
    from public.transport_logistics_receipts r
    where r.tenant_id=p_tenant_id
      and r.trip_id=p_trip_id
      and r.id=p_receipt_id
      and (
        p_stock_transfer_id is null
        or r.stock_transfer_id=p_stock_transfer_id
      )
  ) then
    raise exception 'Receipt is not linked to this trip';
  end if;

  insert into public.transport_logistics_evidence(
    tenant_id,trip_id,stock_transfer_id,receipt_id,evidence_type,
    file_name,storage_path,mime_type,file_size,note,captured_at,created_by
  ) values(
    p_tenant_id,p_trip_id,p_stock_transfer_id,p_receipt_id,v_type,
    trim(p_file_name),v_path,lower(trim(p_mime_type)),p_file_size,
    nullif(trim(coalesce(p_note,'')),''),
    coalesce(p_captured_at,now()),auth.uid()
  )
  returning id into v_id;

  insert into public.transport_logistics_trip_events(
    tenant_id,trip_id,event_type,from_status,to_status,
    event_data,actor_user_id
  ) values(
    p_tenant_id,p_trip_id,'evidence_added',t.status,t.status,
    jsonb_build_object(
      'evidence_id',v_id,
      'evidence_type',v_type,
      'file_name',trim(p_file_name),
      'stock_transfer_id',p_stock_transfer_id,
      'receipt_id',p_receipt_id
    ),
    auth.uid()
  );

  perform private.business_audit_write_v471(
    p_tenant_id,
    'logistics.evidence.add',
    'transport_logistics_evidence',
    v_id,
    t.trip_number,
    null,
    (
      select to_jsonb(e)
      from public.transport_logistics_evidence e
      where e.id=v_id
    )
  );

  return jsonb_build_object(
    'success',true,
    'evidence_id',v_id,
    'trip_id',p_trip_id,
    'evidence_type',v_type,
    'storage_path',v_path
  );
end
$$;

create or replace function public.logistics_evidence_list_v1(
  p_tenant_id uuid,
  p_trip_id uuid
)
returns setof jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $$
declare
  t public.transport_logistics_trips%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if not (
    private.erp_user_is_owner(p_tenant_id,auth.uid())
    or private.erp_has_permission(p_tenant_id,'transport_service.view')
    or private.erp_has_permission(p_tenant_id,'transport_service.create')
    or private.erp_has_permission(p_tenant_id,'transport_service.manage')
    or private.erp_has_permission(p_tenant_id,'inventory.transfer')
    or private.erp_has_permission(p_tenant_id,'inventory.manage')
  ) then
    raise exception 'Logistics view permission required';
  end if;

  select * into t
  from public.transport_logistics_trips
  where id=p_trip_id and tenant_id=p_tenant_id;
  if not found then
    raise exception 'Trip not found';
  end if;

  if not (
    private.erp_document_scope_allowed(
      p_tenant_id,t.from_location_id,null,'view'
    )
    or private.erp_document_scope_allowed(
      p_tenant_id,t.to_location_id,null,'view'
    )
  ) then
    raise exception 'Location access denied';
  end if;

  return query
  select jsonb_build_object(
    'id',e.id,
    'trip_id',e.trip_id,
    'stock_transfer_id',e.stock_transfer_id,
    'receipt_id',e.receipt_id,
    'evidence_type',e.evidence_type,
    'file_name',e.file_name,
    'storage_path',e.storage_path,
    'mime_type',e.mime_type,
    'file_size',e.file_size,
    'note',e.note,
    'captured_at',e.captured_at,
    'created_by',e.created_by,
    'created_at',e.created_at
  )
  from public.transport_logistics_evidence e
  where e.tenant_id=p_tenant_id and e.trip_id=p_trip_id
  order by e.captured_at desc,e.created_at desc;
end
$$;

create or replace function public.logistics_exceptions_list_v1(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_status text default null,
  p_trip_id uuid default null,
  p_limit integer default 500
)
returns setof jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if not (
    private.erp_user_is_owner(p_tenant_id,auth.uid())
    or private.erp_has_permission(p_tenant_id,'transport_service.view')
    or private.erp_has_permission(p_tenant_id,'transport_service.create')
    or private.erp_has_permission(p_tenant_id,'transport_service.manage')
    or private.erp_has_permission(p_tenant_id,'inventory.transfer')
    or private.erp_has_permission(p_tenant_id,'inventory.manage')
  ) then
    raise exception 'Logistics view permission required';
  end if;

  return query
  select jsonb_build_object(
    'id',e.id,
    'trip_id',e.trip_id,
    'trip_number',t.trip_number,
    'receipt_id',e.receipt_id,
    'receipt_number',r.receipt_number,
    'stock_transfer_id',e.stock_transfer_id,
    'transfer_number',st.transfer_number,
    'variant_id',e.variant_id,
    'product_name',p.name,
    'sku',pv.sku,
    'exception_type',e.exception_type,
    'quantity',e.quantity,
    'status',e.status,
    'resolution_code',e.resolution_code,
    'resolution_note',e.resolution_note,
    'external_reference',e.external_reference,
    'opened_at',e.opened_at,
    'resolved_at',e.resolved_at,
    'from_location',fl.location_code||' â€¢ '||fl.name,
    'to_location',tl.location_code||' â€¢ '||tl.name,
    'vehicle_registration',v.registration_number
  )
  from public.transport_logistics_exceptions e
  join public.transport_logistics_trips t
    on t.id=e.trip_id and t.tenant_id=e.tenant_id
  join public.transport_logistics_receipts r
    on r.id=e.receipt_id and r.tenant_id=e.tenant_id
  join public.stock_transfers st
    on st.id=e.stock_transfer_id and st.tenant_id=e.tenant_id
  join public.product_variants pv on pv.id=e.variant_id
  join public.products p on p.id=pv.product_id
  join public.service_vehicles v
    on v.id=t.vehicle_id and v.tenant_id=t.tenant_id
  join public.business_locations fl
    on fl.id=t.from_location_id and fl.tenant_id=t.tenant_id
  join public.business_locations tl
    on tl.id=t.to_location_id and tl.tenant_id=t.tenant_id
  where e.tenant_id=p_tenant_id
    and (p_trip_id is null or e.trip_id=p_trip_id)
    and (
      p_status is null
      or trim(p_status)=''
      or e.status=lower(trim(p_status))
    )
    and (
      p_location_id is null
      or t.from_location_id=p_location_id
      or t.to_location_id=p_location_id
    )
    and (
      private.erp_document_scope_allowed(
        p_tenant_id,t.from_location_id,p_location_id,'view'
      )
      or private.erp_document_scope_allowed(
        p_tenant_id,t.to_location_id,p_location_id,'view'
      )
    )
  order by
    case when e.status in ('open','investigating') then 0 else 1 end,
    e.opened_at desc
  limit greatest(1,least(coalesce(p_limit,500),2000));
end
$$;

create or replace function public.logistics_exception_update_v1(
  p_tenant_id uuid,
  p_exception_id uuid,
  p_status text,
  p_resolution_code text default null,
  p_resolution_note text default null,
  p_external_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $$
declare
  e public.transport_logistics_exceptions%rowtype;
  a public.transport_logistics_exceptions%rowtype;
  t public.transport_logistics_trips%rowtype;
  s text:=lower(trim(coalesce(p_status,'')));
  b jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if not (
    private.erp_user_is_owner(p_tenant_id,auth.uid())
    or private.erp_has_permission(p_tenant_id,'transport_service.manage')
    or private.erp_has_permission(p_tenant_id,'inventory.manage')
  ) then
    raise exception 'Logistics exception management permission required';
  end if;

  select * into e
  from public.transport_logistics_exceptions
  where id=p_exception_id and tenant_id=p_tenant_id
  for update;
  if not found then
    raise exception 'Logistics exception not found';
  end if;

  select * into t
  from public.transport_logistics_trips
  where id=e.trip_id and tenant_id=p_tenant_id;
  if not found then
    raise exception 'Trip not found';
  end if;

  perform private.v4_location_access(
    p_tenant_id,t.to_location_id,'operate'
  );

  if s not in ('open','investigating','resolved','waived') then
    raise exception 'Invalid exception status';
  end if;
  if s in ('resolved','waived')
    and trim(coalesce(p_resolution_code,''))=''
  then
    raise exception 'Resolution code is required';
  end if;
  if s in ('resolved','waived')
    and trim(coalesce(p_resolution_note,''))=''
  then
    raise exception 'Resolution note is required';
  end if;

  b:=to_jsonb(e);

  update public.transport_logistics_exceptions
  set
    status=s,
    resolution_code=nullif(trim(coalesce(p_resolution_code,'')),''),
    resolution_note=nullif(trim(coalesce(p_resolution_note,'')),''),
    external_reference=nullif(trim(coalesce(p_external_reference,'')),''),
    resolved_at=case
      when s in ('resolved','waived')
        then coalesce(resolved_at,now())
      else null
    end,
    resolved_by=case
      when s in ('resolved','waived') then auth.uid()
      else null
    end,
    updated_at=now(),
    updated_by=auth.uid()
  where id=e.id
  returning * into a;

  insert into public.transport_logistics_trip_events(
    tenant_id,trip_id,event_type,from_status,to_status,
    event_data,actor_user_id
  ) values(
    p_tenant_id,e.trip_id,'exception_status_changed',t.status,t.status,
    jsonb_build_object(
      'exception_id',e.id,
      'exception_type',e.exception_type,
      'quantity',e.quantity,
      'from_exception_status',e.status,
      'to_exception_status',a.status,
      'resolution_code',a.resolution_code,
      'external_reference',a.external_reference
    ),
    auth.uid()
  );

  perform private.business_audit_write_v471(
    p_tenant_id,
    'logistics.exception.update',
    'transport_logistics_exception',
    e.id,
    t.trip_number,
    b,
    to_jsonb(a)
  );

  return jsonb_build_object(
    'success',true,
    'exception_id',a.id,
    'trip_id',a.trip_id,
    'status',a.status,
    'resolution_code',a.resolution_code,
    'resolved_at',a.resolved_at
  );
end
$$;

create or replace function public.logistics_operations_trips_v1(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_limit integer default 500
)
returns setof jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if not (
    private.erp_user_is_owner(p_tenant_id,auth.uid())
    or private.erp_has_permission(p_tenant_id,'transport_service.view')
    or private.erp_has_permission(p_tenant_id,'transport_service.create')
    or private.erp_has_permission(p_tenant_id,'transport_service.manage')
    or private.erp_has_permission(p_tenant_id,'inventory.transfer')
    or private.erp_has_permission(p_tenant_id,'inventory.manage')
  ) then
    raise exception 'Logistics view permission required';
  end if;

  return query
  select jsonb_build_object(
    'id',t.id,
    'trip_number',t.trip_number,
    'status',t.status,
    'vehicle_registration',v.registration_number,
    'driver_name',t.driver_name,
    'from_location',fl.location_code||' â€¢ '||fl.name,
    'to_location',tl.location_code||' â€¢ '||tl.name,
    'planned_departure_at',t.planned_departure_at,
    'expected_arrival_date',eta.expected_arrival_date,
    'is_overdue',case
      when t.status in ('planned','loading')
        and t.planned_departure_at is not null
        and t.planned_departure_at<now()
        then true
      when t.status='in_transit'
        and eta.expected_arrival_date is not null
        and eta.expected_arrival_date<current_date
        then true
      else false
    end,
    'overdue_kind',case
      when t.status in ('planned','loading')
        and t.planned_departure_at is not null
        and t.planned_departure_at<now()
        then 'departure'
      when t.status='in_transit'
        and eta.expected_arrival_date is not null
        and eta.expected_arrival_date<current_date
        then 'arrival'
      else null
    end,
    'evidence_count',(
      select count(*)
      from public.transport_logistics_evidence x
      where x.tenant_id=t.tenant_id and x.trip_id=t.id
    ),
    'open_exception_count',(
      select count(*)
      from public.transport_logistics_exceptions x
      where x.tenant_id=t.tenant_id
        and x.trip_id=t.id
        and x.status in ('open','investigating')
    )
  )
  from public.transport_logistics_trips t
  join public.service_vehicles v
    on v.id=t.vehicle_id and v.tenant_id=t.tenant_id
  join public.business_locations fl
    on fl.id=t.from_location_id and fl.tenant_id=t.tenant_id
  join public.business_locations tl
    on tl.id=t.to_location_id and tl.tenant_id=t.tenant_id
  left join lateral (
    select min(st.expected_arrival_date) expected_arrival_date
    from public.transport_logistics_trip_documents d
    join public.stock_transfers st
      on st.id=d.stock_transfer_id and st.tenant_id=d.tenant_id
    where d.trip_id=t.id
      and d.active
      and st.expected_arrival_date is not null
  ) eta on true
  where t.tenant_id=p_tenant_id
    and (
      p_location_id is null
      or t.from_location_id=p_location_id
      or t.to_location_id=p_location_id
    )
    and (
      private.erp_document_scope_allowed(
        p_tenant_id,t.from_location_id,p_location_id,'view'
      )
      or private.erp_document_scope_allowed(
        p_tenant_id,t.to_location_id,p_location_id,'view'
      )
    )
  order by
    case when (
      (
        t.status in ('planned','loading')
        and t.planned_departure_at is not null
        and t.planned_departure_at<now()
      )
      or (
        t.status='in_transit'
        and eta.expected_arrival_date is not null
        and eta.expected_arrival_date<current_date
      )
    ) then 0 else 1 end,
    t.created_at desc
  limit greatest(1,least(coalesce(p_limit,500),2000));
end
$$;

revoke all on function public.logistics_evidence_register_v1(
  uuid,uuid,text,text,text,text,bigint,text,uuid,uuid,timestamptz
) from public, anon;
revoke all on function public.logistics_evidence_list_v1(uuid,uuid)
  from public, anon;
revoke all on function public.logistics_exceptions_list_v1(
  uuid,uuid,text,uuid,integer
) from public, anon;
revoke all on function public.logistics_exception_update_v1(
  uuid,uuid,text,text,text,text
) from public, anon;
revoke all on function public.logistics_operations_trips_v1(
  uuid,uuid,integer
) from public, anon;

grant execute on function public.logistics_evidence_register_v1(
  uuid,uuid,text,text,text,text,bigint,text,uuid,uuid,timestamptz
) to authenticated, service_role;
grant execute on function public.logistics_evidence_list_v1(uuid,uuid)
  to authenticated, service_role;
grant execute on function public.logistics_exceptions_list_v1(
  uuid,uuid,text,uuid,integer
) to authenticated, service_role;
grant execute on function public.logistics_exception_update_v1(
  uuid,uuid,text,text,text,text
) to authenticated, service_role;
grant execute on function public.logistics_operations_trips_v1(
  uuid,uuid,integer
) to authenticated, service_role;