begin;

-- THQ ERP v6.0.1 Build 2 — client-readiness stabilization.
--
-- This is the repository migration mirror for the access/location hardening
-- already validated during the final v6.0 stabilization audit, plus stricter
-- desktop runtime-context validation and the v6.0.1 Build 2 release registry.
--
-- GST compatibility rule is unchanged:
--   * legacy v5.1/v4.8.x documents retain legacy_unverified evidence
--   * v5.2 documents retain authoritative snapshots/component accounting
--   * never fall back to a legacy writer after an authoritative v5.2 failure

create or replace function private.erp_validate_transaction_origin(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_required_pos_module text
)
returns void
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_app text;
  v_device_location uuid;
  v_modules text[];
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  if not exists(
    select 1 from public.tenants t
    where t.id=p_tenant_id and t.status='active'
  ) then
    raise exception 'Business is inactive';
  end if;

  if p_location_id is null then
    raise exception 'A business location is required';
  end if;

  perform private.v4_location_access(p_tenant_id,p_location_id,'operate');

  if p_device_id is null then
    raise exception 'A registered system is required';
  end if;

  select d.app_type,d.location_id,d.allowed_modules
    into v_app,v_device_location,v_modules
  from public.business_devices d
  where d.id=p_device_id
    and d.tenant_id=p_tenant_id
    and d.status='active';

  if not found then
    raise exception 'Registered system is invalid or revoked';
  end if;

  if v_app='pos' then
    if not private.erp_user_app_allowed(p_tenant_id,'pos',auth.uid()) then
      raise exception 'POS app access is disabled for this user';
    end if;

    if v_device_location is distinct from p_location_id then
      raise exception 'POS terminals can only post to their assigned store';
    end if;

    if p_required_pos_module is not null
       and not (p_required_pos_module=any(coalesce(v_modules,'{}'::text[]))) then
      raise exception 'This POS terminal is not enabled for %',p_required_pos_module;
    end if;

  elsif v_app='client' then
    if not private.erp_user_app_allowed(p_tenant_id,'client',auth.uid()) then
      raise exception 'Client app access is disabled for this user';
    end if;

  else
    raise exception 'Unsupported system type';
  end if;
end
$function$;


create or replace function private.v486_pos_device_location(
  p_tenant_id uuid,
  p_device_id uuid,
  p_location_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_location uuid;
  v_type text;
  v_status text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  if not exists(
    select 1 from public.tenants t
    where t.id=p_tenant_id and t.status='active'
  ) then
    raise exception 'Business is inactive';
  end if;

  if not private.erp_user_app_allowed(p_tenant_id,'pos',auth.uid()) then
    raise exception 'POS app access is disabled for this user';
  end if;

  select d.location_id,d.app_type,d.status
    into v_location,v_type,v_status
  from public.business_devices d
  where d.id=p_device_id and d.tenant_id=p_tenant_id;

  if v_location is null then
    raise exception 'POS terminal not found';
  end if;

  if v_status<>'active' then
    raise exception 'POS terminal is not active';
  end if;

  if v_type<>'pos' then
    raise exception 'Offline POS sync requires a POS terminal';
  end if;

  if p_location_id is not null and p_location_id<>v_location then
    raise exception 'POS terminal location mismatch';
  end if;

  perform private.v4_location_access(p_tenant_id,v_location,'operate');

  return v_location;
end
$function$;


create or replace function private.v487_client_mobile_location(
  p_tenant_id uuid,
  p_device_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_location uuid;
  v_type text;
  v_status text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  if not exists(
    select 1 from public.tenants t
    where t.id=p_tenant_id and t.status='active'
  ) then
    raise exception 'Business is inactive';
  end if;

  if not private.erp_user_app_allowed(p_tenant_id,'client',auth.uid()) then
    raise exception 'Client app access is disabled for this user';
  end if;

  select d.location_id,d.app_type,d.status
    into v_location,v_type,v_status
  from public.business_devices d
  where d.id=p_device_id and d.tenant_id=p_tenant_id;

  if v_location is null then
    raise exception 'Client Mobile system not found';
  end if;

  if v_status<>'active' then
    raise exception 'Client Mobile system is not active';
  end if;

  if v_type<>'client' then
    raise exception 'Client Mobile requires a Client system activation';
  end if;

  perform private.v4_location_access(p_tenant_id,v_location,'view');

  return v_location;
end
$function$;


create or replace function public.client_runtime_context_v4(
  p_tenant_id uuid,
  p_device_id uuid,
  p_app_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v jsonb;
  v_all boolean;
  v_username text;
  v_roles jsonb;
  v_main uuid;
  v_device_location uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_app_key not in ('client','pos') then
    raise exception 'Unsupported application';
  end if;

  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  if not exists(
    select 1 from public.tenants t
    where t.id=p_tenant_id and t.status='active'
  ) then
    raise exception 'Business is inactive';
  end if;

  if not private.erp_user_app_allowed(p_tenant_id,p_app_key) then
    raise exception 'This user is not enabled for this application';
  end if;

  select d.location_id
    into v_device_location
  from public.business_devices d
  where d.id=p_device_id
    and d.tenant_id=p_tenant_id
    and d.app_type=p_app_key
    and d.status='active';

  if not found then
    raise exception 'Device is not active';
  end if;

  if p_app_key='pos' then
    perform private.v4_location_access(
      p_tenant_id,
      v_device_location,
      'operate'
    );
  else
    perform private.v4_location_access(
      p_tenant_id,
      v_device_location,
      'view'
    );
  end if;

  v_all :=
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'locations.view_all')
    or private.erp_has_permission(p_tenant_id,'locations.manage_all');

  v_main:=private.v42_main_location(p_tenant_id);

  select username
    into v_username
  from public.user_login_names
  where user_id=auth.uid();

  select coalesce(jsonb_agg(r.key order by r.key),'[]'::jsonb)
    into v_roles
  from public.tenant_memberships tm
  join public.user_roles ur
    on ur.membership_id=tm.id
   and ur.tenant_id=tm.tenant_id
  join public.roles r
    on r.id=ur.role_id
  where tm.tenant_id=p_tenant_id
    and tm.user_id=auth.uid()
    and tm.status='active';

  select jsonb_build_object(
    'schema_version','4.2',
    'username',coalesce(v_username,''),
    'roles',coalesce(v_roles,'[]'::jsonb),
    'user_id',auth.uid(),
    'device_id',d.id,
    'device_code',d.device_code,
    'device_name',d.name,
    'device_modules',coalesce(to_jsonb(d.allowed_modules),'[]'::jsonb),
    'location_id',d.location_id,
    'location_code',l.location_code,
    'location_name',l.name,
    'device_invoice_prefix',d.invoice_prefix,
    'main_location_id',v_main,
    'can_view_all_locations',v_all,
    'locations',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',x.id,
          'parent_location_id',x.parent_location_id,
          'code',x.location_code,
          'name',x.name,
          'type',x.location_type,
          'hierarchy_role',x.hierarchy_role,
          'sort_order',x.sort_order,
          'tracking_code',x.tracking_code,
          'access_level',case when v_all then 'manage' else a.access_level end
        )
        order by
          case
            when x.hierarchy_role='main_store' then 0
            when x.hierarchy_role='warehouse' then 2
            else 1
          end,
          x.sort_order,
          x.name
      )
      from public.business_locations x
      left join public.business_user_location_access a
        on a.tenant_id=p_tenant_id
       and a.user_id=auth.uid()
       and a.location_id=x.id
      where x.tenant_id=p_tenant_id
        and x.active
        and (v_all or a.user_id is not null)
    ),'[]'::jsonb),
    'open_shift',
      case
        when p_app_key='pos' then coalesce((
          select jsonb_build_object(
            'id',s.id,
            'shift_number',s.shift_number,
            'opened_at',s.opened_at,
            'opening_cash',s.opening_cash
          )
          from public.cashier_shifts s
          where s.tenant_id=p_tenant_id
            and s.device_id=d.id
            and s.status='open'
          order by s.opened_at desc
          limit 1
        ),'{}'::jsonb)
        else '{}'::jsonb
      end
  )
    into v
  from public.business_devices d
  join public.business_locations l
    on l.id=d.location_id
   and l.tenant_id=d.tenant_id
   and l.active
  where d.id=p_device_id
    and d.tenant_id=p_tenant_id
    and d.app_type=p_app_key
    and d.status='active';

  if v is null then
    raise exception 'Active runtime context is unavailable';
  end if;

  return v;
end
$function$;


create or replace function private.business_device_active_location_guard_v600()
returns trigger
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
begin
  if new.status='active' then
    if not exists(
      select 1
      from public.tenants t
      where t.id=new.tenant_id and t.status='active'
    ) then
      raise exception 'Cannot activate a system for an inactive business';
    end if;

    if new.location_id is null or not exists(
      select 1
      from public.business_locations l
      where l.id=new.location_id
        and l.tenant_id=new.tenant_id
        and l.active
    ) then
      raise exception 'Cannot activate a system on an inactive or invalid store';
    end if;
  end if;

  return new;
end
$function$;

revoke all on function private.business_device_active_location_guard_v600()
  from public, anon, authenticated;

drop trigger if exists trg_v600_business_device_active_location_guard
  on public.business_devices;

create trigger trg_v600_business_device_active_location_guard
before insert or update on public.business_devices
for each row
execute function private.business_device_active_location_guard_v600();


create or replace function private.business_location_active_system_guard_v601()
returns trigger
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
begin
  if old.active
     and not new.active
     and exists(
       select 1
       from public.business_devices d
       where d.tenant_id=new.tenant_id
         and d.location_id=new.id
         and d.status='active'
     ) then
    raise exception
      'Deactivate or move active Client/POS systems before deactivating this store';
  end if;

  return new;
end
$function$;

revoke all on function private.business_location_active_system_guard_v601()
  from public, anon, authenticated;

drop trigger if exists trg_v601_business_location_active_system_guard
  on public.business_locations;

create trigger trg_v601_business_location_active_system_guard
before update of active on public.business_locations
for each row
execute function private.business_location_active_system_guard_v601();


insert into public.platform_app_releases(
  id, app_key, platform, version, build_number, status,
  minimum_supported, mandatory, release_notes, download_url, released_at
)
select
  gen_random_uuid(),
  v.app_key,
  v.platform,
  '6.0.1',
  2,
  'stable',
  false,
  false,
  'THQ ERP v6.0.1 Build 2 — Client Readiness Stabilization. Fixes GST workspace service lifecycle and Flutter runtime layout/scroll errors, makes desktop Client/POS runtime bootstrap fail closed, hardens active business/store and application-access enforcement, and synchronizes release versions across Client, POS, Admin and mobile apps.',
  null,
  now()
from (values
  ('client','windows'),
  ('client','web'),
  ('client','android'),
  ('pos','windows'),
  ('pos','android'),
  ('admin','web')
) as v(app_key,platform)
on conflict(app_key,platform,version) do update
set build_number = excluded.build_number,
    status = excluded.status,
    minimum_supported = excluded.minimum_supported,
    mandatory = excluded.mandatory,
    release_notes = excluded.release_notes;


insert into public.thq_schema_releases(
  migration_no,
  schema_version,
  release_name,
  notes
)
values(
  270,
  '6.0.1-build2',
  'v6.0.1 Build 2 Client Readiness Stabilization',
  'Runtime/app/store fail-closed hardening plus synchronized v6.0.1 Build 2 release registry. Preserves all v5.1 legacy_unverified and v5.2 authoritative GST/accounting compatibility rules.'
)
on conflict(migration_no) do update
set schema_version = excluded.schema_version,
    release_name = excluded.release_name,
    notes = excluded.notes;

commit;
