-- THQ ERP V4.8.8 — Mobile POS print/share audit events.
begin;
create table if not exists public.mobile_pos_receipt_events_v488(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  device_id uuid not null references public.business_devices(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete cascade,
  request_id text not null,
  local_invoice_number text,
  sale_id uuid references public.sales(id) on delete set null,
  event_type text not null check(event_type in('print','share')),
  receipt_state text not null default 'local' check(receipt_state in('local','synced')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists idx_mobile_pos_receipt_events_v488 on public.mobile_pos_receipt_events_v488(tenant_id,device_id,created_at desc);
alter table public.mobile_pos_receipt_events_v488 enable row level security;
revoke all on public.mobile_pos_receipt_events_v488 from anon,authenticated;

create or replace function public.mobile_pos_receipt_event_v488(p_tenant_id uuid,p_device_id uuid,p_request_id text,p_event_type text,p_local_invoice_number text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;v_sale uuid;v_state text:='local';v_id uuid;
begin
  v_location:=private.v488_mobile_pos_location(p_tenant_id,p_device_id);
  if lower(trim(coalesce(p_event_type,''))) not in('print','share') then raise exception 'Invalid receipt event';end if;
  select nullif(server_response->>'sale_id','')::uuid,case when status='synced' then 'synced' else 'local' end into v_sale,v_state
  from public.pos_offline_sync_v486 where tenant_id=p_tenant_id and request_id=trim(p_request_id);
  insert into public.mobile_pos_receipt_events_v488(tenant_id,device_id,location_id,request_id,local_invoice_number,sale_id,event_type,receipt_state,created_by)
  values(p_tenant_id,p_device_id,v_location,trim(p_request_id),nullif(trim(coalesce(p_local_invoice_number,'')),''),v_sale,lower(trim(p_event_type)),v_state,auth.uid()) returning id into v_id;
  return jsonb_build_object('ok',true,'event_id',v_id,'receipt_state',v_state);
end$$;
grant execute on function public.mobile_pos_receipt_event_v488(uuid,uuid,text,text,text) to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(169,'4.8.8','Mobile POS Foundation','Optional server audit for mobile receipt print/share events while printing itself remains device-local and offline-capable.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.8 migration 169 mobile receipt events applied' as status;
