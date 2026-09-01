-- THQ ERP V4.8.6 — Offline POS server audit foundation.
begin;

create table if not exists public.pos_offline_sync_v486(
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  request_id text not null,
  device_id uuid not null references public.business_devices(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete cascade,
  local_invoice_number text,
  status text not null default 'pending' check(status in('pending','syncing','synced','conflict','error','cancelled')),
  conflict_code text,
  conflict_message text,
  payload_snapshot jsonb not null default '{}'::jsonb,
  server_response jsonb,
  attempts integer not null default 0,
  first_seen_at timestamptz not null default now(),
  last_attempt_at timestamptz,
  synced_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key(tenant_id,request_id)
);
create index if not exists idx_pos_offline_sync_v486_device on public.pos_offline_sync_v486(tenant_id,device_id,status,updated_at desc);
create index if not exists idx_pos_offline_sync_v486_location on public.pos_offline_sync_v486(tenant_id,location_id,status,updated_at desc);
alter table public.pos_offline_sync_v486 enable row level security;
revoke all on public.pos_offline_sync_v486 from anon,authenticated;

create or replace function private.v486_pos_device_location(p_tenant_id uuid,p_device_id uuid,p_location_id uuid)
returns uuid language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;v_type text;v_status text;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select d.location_id,d.app_type,d.status into v_location,v_type,v_status
  from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id;
  if v_location is null then raise exception 'POS terminal not found';end if;
  if v_status<>'active' then raise exception 'POS terminal is not active';end if;
  if v_type<>'pos' then raise exception 'Offline POS sync requires a POS terminal';end if;
  if p_location_id is not null and p_location_id<>v_location then raise exception 'POS terminal location mismatch';end if;
  return v_location;
end$$;
revoke all on function private.v486_pos_device_location(uuid,uuid,uuid) from public;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(154,'4.8.6','Offline POS','Server-side offline POS sync audit foundation and active-terminal validation.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.6 migration 154 offline POS foundation applied' as status;
