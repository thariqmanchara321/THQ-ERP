-- FLEXI ERP V4 saved views, preferences and unified activity timeline.
begin;

create table if not exists public.user_saved_views(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  module_key text not null,
  name text not null,
  filters jsonb not null default '{}'::jsonb,
  columns jsonb not null default '[]'::jsonb,
  sort jsonb not null default '{}'::jsonb,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  unique(tenant_id,user_id,module_key,name)
);

create table if not exists public.user_preferences_v4(
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  preferences jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key(tenant_id,user_id)
);

alter table public.user_saved_views enable row level security;
alter table public.user_preferences_v4 enable row level security;
revoke all on public.user_saved_views,public.user_preferences_v4 from anon,authenticated;

-- Extend the V3 audit table without breaking existing callers.
alter table public.business_audit_log
  add column if not exists location_id uuid references public.business_locations(id) on delete set null,
  add column if not exists device_id uuid references public.business_devices(id) on delete set null,
  add column if not exists reason text,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

create index if not exists idx_business_audit_location_created
  on public.business_audit_log(tenant_id,location_id,created_at desc);

-- Keep the original function signature used throughout V3/V4, but enrich every
-- future audit row with the best available location/device attribution.
create or replace function private.business_audit_write(
  p_tenant_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_reference text,
  p_before jsonb,
  p_after jsonb
)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_location_id uuid;
  v_device_id uuid;
begin
  -- Prefer the entity's immutable document origin when one exists.
  select o.location_id,o.device_id
    into v_location_id,v_device_id
  from public.document_origins o
  where o.tenant_id=p_tenant_id
    and o.entity_type=p_entity_type
    and o.entity_id=p_entity_id
  limit 1;

  insert into public.business_audit_log(
    tenant_id,user_id,action,entity_type,entity_id,entity_reference,
    before_data,after_data,location_id,device_id,metadata
  ) values(
    p_tenant_id,auth.uid(),p_action,p_entity_type,p_entity_id,p_reference,
    p_before,p_after,v_location_id,v_device_id,
    jsonb_build_object('source','erp','recorded_at',now())
  );
end $$;
revoke all on function private.business_audit_write(uuid,text,text,uuid,text,jsonb,jsonb) from public;

create or replace function public.user_saved_views_list_v4(p_tenant_id uuid,p_module_key text)
returns setof public.user_saved_views
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select * from public.user_saved_views
  where tenant_id=p_tenant_id and user_id=auth.uid() and module_key=p_module_key
  order by is_default desc,name;
end $$;
grant execute on function public.user_saved_views_list_v4(uuid,text) to authenticated;

create or replace function public.user_saved_view_save_v4(
  p_tenant_id uuid,p_module_key text,p_name text,p_filters jsonb,p_columns jsonb default '[]'::jsonb,p_sort jsonb default '{}'::jsonb,p_is_default boolean default false
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid; begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if trim(coalesce(p_name,''))='' then raise exception 'View name required';end if;
  if p_is_default then
    update public.user_saved_views set is_default=false
    where tenant_id=p_tenant_id and user_id=auth.uid() and module_key=p_module_key;
  end if;
  insert into public.user_saved_views(tenant_id,user_id,module_key,name,filters,columns,sort,is_default)
  values(p_tenant_id,auth.uid(),p_module_key,trim(p_name),coalesce(p_filters,'{}'::jsonb),coalesce(p_columns,'[]'::jsonb),coalesce(p_sort,'{}'::jsonb),coalesce(p_is_default,false))
  on conflict(tenant_id,user_id,module_key,name) do update set
    filters=excluded.filters,columns=excluded.columns,sort=excluded.sort,is_default=excluded.is_default
  returning id into v_id;
  return v_id;
end $$;
grant execute on function public.user_saved_view_save_v4(uuid,text,text,jsonb,jsonb,jsonb,boolean) to authenticated;

create or replace function public.entity_activity_timeline_v4(
  p_tenant_id uuid,p_entity_type text,p_entity_id uuid,p_limit integer default 100
)
returns table(
  activity_time timestamptz,activity_type text,title text,description text,
  user_name text,location_code text,device_code text,metadata jsonb
)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  select * from (
    select
      a.created_at,
      'audit'::text,
      a.action,
      coalesce(a.entity_reference,a.entity_type,'')::text,
      coalesce(u.username,''),
      coalesce(l.location_code,''),
      coalesce(d.device_code,''),
      coalesce(a.metadata,'{}'::jsonb) || jsonb_build_object('before',a.before_data,'after',a.after_data,'reason',a.reason)
    from public.business_audit_log a
    left join public.user_login_names u on u.user_id=a.user_id
    left join public.business_locations l on l.id=a.location_id
    left join public.business_devices d on d.id=a.device_id
    where a.tenant_id=p_tenant_id and a.entity_type=p_entity_type and a.entity_id=p_entity_id

    union all

    select
      c.created_at,
      'correction'::text,
      c.correction_type,
      c.reason,
      coalesce(u.username,''),
      coalesce(l.location_code,''),
      coalesce(d.device_code,''),
      coalesce(c.metadata,'{}'::jsonb)
    from public.transaction_corrections c
    left join public.user_login_names u on u.user_id=c.created_by
    left join public.document_origins o on o.tenant_id=c.tenant_id and o.entity_type=c.entity_type and o.entity_id=c.entity_id
    left join public.business_locations l on l.id=o.location_id
    left join public.business_devices d on d.id=o.device_id
    where c.tenant_id=p_tenant_id and c.entity_type=p_entity_type and c.entity_id=p_entity_id

    union all

    select
      p.created_at,
      'print'::text,
      p.action,
      coalesce(p.invoice_number,''),
      coalesce(u.username,''),
      coalesce(l.location_code,''),
      coalesce(d.device_code,''),
      jsonb_build_object('copy_number',p.copy_number,'template_id',p.template_id,'printer_profile_id',p.printer_profile_id)
    from public.invoice_print_events p
    left join public.user_login_names u on u.user_id=p.created_by
    left join public.business_devices d on d.id=p.device_id
    left join public.business_locations l on l.id=d.location_id
    where p.tenant_id=p_tenant_id and p.entity_type=p_entity_type and p.entity_id=p_entity_id
  ) x
  order by activity_time desc
  limit greatest(1,least(coalesce(p_limit,100),500));
end $$;
grant execute on function public.entity_activity_timeline_v4(uuid,text,uuid,integer) to authenticated;

commit;
select 'Flexi ERP V4 saved views/activity timeline ready' as status;
