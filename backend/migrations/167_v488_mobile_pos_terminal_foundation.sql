-- THQ ERP V4.8.8 — Mobile POS terminal foundation.
begin;

create table if not exists public.mobile_pos_terminal_settings_v488(
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  device_id uuid not null references public.business_devices(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete cascade,
  camera_scanner_enabled boolean not null default true,
  system_printing_enabled boolean not null default true,
  kot_groundwork_enabled boolean not null default true,
  settings jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key(tenant_id,device_id)
);
alter table public.mobile_pos_terminal_settings_v488 enable row level security;
revoke all on public.mobile_pos_terminal_settings_v488 from anon,authenticated;

create or replace function private.v488_mobile_pos_location(p_tenant_id uuid,p_device_id uuid)
returns uuid language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  return private.v486_pos_device_location(p_tenant_id,p_device_id,null);
end$$;
revoke all on function private.v488_mobile_pos_location(uuid,uuid) from public;

create or replace function public.mobile_pos_terminal_context_v488(p_tenant_id uuid,p_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;d public.business_devices%rowtype;l public.business_locations%rowtype;v_settings jsonb:='{}'::jsonb;v_restaurant boolean:=false;v_shift jsonb;
begin
  v_location:=private.v488_mobile_pos_location(p_tenant_id,p_device_id);
  select * into d from public.business_devices where id=p_device_id and tenant_id=p_tenant_id;
  select * into l from public.business_locations where id=v_location and tenant_id=p_tenant_id;
  select to_jsonb(s) into v_settings from public.mobile_pos_terminal_settings_v488 s where s.tenant_id=p_tenant_id and s.device_id=p_device_id;
  select exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key='restaurant' and tm.enabled) into v_restaurant;
  begin v_shift:=public.cashier_shift_current_v472(p_tenant_id,p_device_id);exception when others then v_shift:=null;end;
  return jsonb_build_object(
    'release','4.8.8','mobile_pos',true,'device_id',d.id,'device_code',d.device_code,'device_name',d.name,
    'location_id',l.id,'location_code',l.location_code,'location_name',l.name,
    'username',coalesce((select u.username::text from public.user_login_names u where u.user_id=auth.uid()),auth.uid()::text),
    'restaurant_enabled',v_restaurant,'current_shift',v_shift,'settings',coalesce(v_settings,'{}'::jsonb),
    'offline_supported',true,'camera_scanner',true,'system_printing',true,'kot_groundwork',true
  );
end$$;
grant execute on function public.mobile_pos_terminal_context_v488(uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(167,'4.8.8','Mobile POS Foundation','Mobile POS terminal context reusing active POS device activation, location scope, cashier-shift context and restaurant/KOT capability metadata.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.8 migration 167 mobile POS terminal foundation applied' as status;
