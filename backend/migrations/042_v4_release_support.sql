-- FLEXI ERP V4 release management and support center.
begin;
create table if not exists public.platform_app_releases(
  id uuid primary key default gen_random_uuid(),app_key text not null check(app_key in('client','pos','admin')),platform text not null,version text not null,build_number integer not null default 1,status text not null default 'stable' check(status in('beta','stable','deprecated','blocked')),minimum_supported boolean not null default false,mandatory boolean not null default false,release_notes text,download_url text,released_at timestamptz not null default now(),unique(app_key,platform,version)
);
create table if not exists public.device_app_status(
  device_id uuid primary key references public.business_devices(id) on delete cascade,tenant_id uuid not null references public.tenants(id) on delete cascade,app_key text not null,platform text,version text,build_number integer,last_seen_at timestamptz not null default now(),metadata jsonb not null default '{}'::jsonb
);
create table if not exists public.support_tickets(
  id uuid primary key default gen_random_uuid(),tenant_id uuid references public.tenants(id) on delete set null,location_id uuid references public.business_locations(id) on delete set null,device_id uuid references public.business_devices(id) on delete set null,user_id uuid references auth.users(id) on delete set null,
  ticket_number text not null unique,app_key text,app_version text,category text not null default 'general',priority text not null default 'normal' check(priority in('low','normal','high','urgent')),status text not null default 'open' check(status in('open','in_progress','waiting_customer','resolved','closed')),subject text not null,description text not null,error_log_id uuid,assigned_platform_admin uuid references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),resolved_at timestamptz
);
create sequence if not exists public.support_ticket_number_seq;
alter table public.platform_app_releases enable row level security;alter table public.device_app_status enable row level security;alter table public.support_tickets enable row level security;revoke all on public.platform_app_releases,public.device_app_status,public.support_tickets from anon,authenticated;

create or replace function public.device_heartbeat_v4(p_tenant_id uuid,p_device_id uuid,p_app_key text,p_platform text,p_version text,p_build integer,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_latest record;begin
  if not exists(select 1 from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active') then raise exception 'Device not active';end if;
  update public.business_devices set last_seen_at=now() where id=p_device_id;
  insert into public.device_app_status(device_id,tenant_id,app_key,platform,version,build_number,last_seen_at,metadata) values(p_device_id,p_tenant_id,p_app_key,p_platform,p_version,coalesce(p_build,0),now(),coalesce(p_metadata,'{}'::jsonb)) on conflict(device_id) do update set app_key=excluded.app_key,platform=excluded.platform,version=excluded.version,build_number=excluded.build_number,last_seen_at=now(),metadata=excluded.metadata;
  select * into v_latest from public.platform_app_releases where app_key=p_app_key and platform=p_platform and status='stable' order by released_at desc limit 1;
  return jsonb_build_object('latest_version',v_latest.version,'mandatory',coalesce(v_latest.mandatory,false),'status',case when v_latest.version is null or v_latest.version=p_version then 'latest' when coalesce(v_latest.mandatory,false) then 'update_required' else 'update_available' end,'release_notes',v_latest.release_notes,'download_url',v_latest.download_url);
end $$;
grant execute on function public.device_heartbeat_v4(uuid,uuid,text,text,text,integer,jsonb) to authenticated;

create or replace function public.support_ticket_create_v4(p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_app_key text,p_app_version text,p_category text,p_priority text,p_subject text,p_description text,p_error_log_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid:=gen_random_uuid();v_no text;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;v_no:='SUP-'||lpad(nextval('public.support_ticket_number_seq')::text,7,'0');
  insert into public.support_tickets(id,tenant_id,location_id,device_id,user_id,ticket_number,app_key,app_version,category,priority,subject,description,error_log_id) values(v_id,p_tenant_id,p_location_id,p_device_id,auth.uid(),v_no,p_app_key,p_app_version,coalesce(nullif(trim(p_category),''),'general'),case when p_priority in('low','normal','high','urgent') then p_priority else 'normal' end,trim(p_subject),trim(p_description),p_error_log_id);
  return jsonb_build_object('ticket_id',v_id,'ticket_number',v_no,'status','open');
end $$;
grant execute on function public.support_ticket_create_v4(uuid,uuid,uuid,text,text,text,text,text,text,uuid) to authenticated;


create or replace function public.platform_app_releases_list_v4()
returns setof public.platform_app_releases
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required';end if;
  return query select * from public.platform_app_releases order by app_key,platform,released_at desc;
end $$;
grant execute on function public.platform_app_releases_list_v4() to authenticated;

create or replace function public.platform_app_release_save_v4(
  p_id uuid,p_app_key text,p_platform text,p_version text,p_build_number integer,p_status text,p_minimum_supported boolean,p_mandatory boolean,p_release_notes text,p_download_url text
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid; begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('technical_admin') then raise exception 'Technical admin required';end if;
  if p_app_key not in('client','pos','admin') then raise exception 'Invalid app';end if;
  if trim(coalesce(p_platform,''))='' or trim(coalesce(p_version,''))='' then raise exception 'Platform and version required';end if;
  if p_minimum_supported then update public.platform_app_releases set minimum_supported=false where app_key=p_app_key and platform=p_platform;end if;
  if p_id is null then
    insert into public.platform_app_releases(app_key,platform,version,build_number,status,minimum_supported,mandatory,release_notes,download_url)
    values(p_app_key,trim(p_platform),trim(p_version),greatest(coalesce(p_build_number,1),1),case when p_status in('beta','stable','deprecated','blocked') then p_status else 'stable' end,coalesce(p_minimum_supported,false),coalesce(p_mandatory,false),nullif(trim(coalesce(p_release_notes,'')),''),nullif(trim(coalesce(p_download_url,'')),'')) returning id into v_id;
  else
    update public.platform_app_releases set app_key=p_app_key,platform=trim(p_platform),version=trim(p_version),build_number=greatest(coalesce(p_build_number,1),1),status=case when p_status in('beta','stable','deprecated','blocked') then p_status else 'stable' end,minimum_supported=coalesce(p_minimum_supported,false),mandatory=coalesce(p_mandatory,false),release_notes=nullif(trim(coalesce(p_release_notes,'')),''),download_url=nullif(trim(coalesce(p_download_url,'')),'') where id=p_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'Release not found';end if;
  return v_id;
end $$;
grant execute on function public.platform_app_release_save_v4(uuid,text,text,text,integer,text,boolean,boolean,text,text) to authenticated;

create or replace function public.platform_device_versions_list_v4(p_tenant_id uuid default null)
returns table(device_id uuid,tenant_id uuid,business_name text,location_code text,device_code text,device_name text,app_key text,platform text,version text,build_number integer,last_seen_at timestamptz)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required';end if;
  return query select s.device_id,s.tenant_id,t.name,l.location_code,d.device_code,d.name,s.app_key,s.platform,s.version,s.build_number,s.last_seen_at
  from public.device_app_status s join public.business_devices d on d.id=s.device_id join public.business_locations l on l.id=d.location_id join public.tenants t on t.id=s.tenant_id
  where p_tenant_id is null or s.tenant_id=p_tenant_id order by s.last_seen_at desc;
end $$;
grant execute on function public.platform_device_versions_list_v4(uuid) to authenticated;

create or replace function public.platform_support_tickets_list_v4(p_status text default null,p_limit integer default 300)
returns table(id uuid,ticket_number text,business_name text,location_code text,device_code text,username text,app_key text,app_version text,category text,priority text,status text,subject text,description text,created_at timestamptz,updated_at timestamptz)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required';end if;
  return query select s.id,s.ticket_number,coalesce(t.name,''),coalesce(l.location_code,''),coalesce(d.device_code,''),coalesce(u.username,''),s.app_key,s.app_version,s.category,s.priority,s.status,s.subject,s.description,s.created_at,s.updated_at
  from public.support_tickets s left join public.tenants t on t.id=s.tenant_id left join public.business_locations l on l.id=s.location_id left join public.business_devices d on d.id=s.device_id left join public.user_login_names u on u.user_id=s.user_id
  where p_status is null or p_status='' or s.status=p_status order by case s.priority when 'urgent' then 1 when 'high' then 2 when 'normal' then 3 else 4 end,s.created_at desc limit greatest(1,least(coalesce(p_limit,300),2000));
end $$;
grant execute on function public.platform_support_tickets_list_v4(text,integer) to authenticated;

create or replace function public.platform_support_ticket_status_v4(p_ticket_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required';end if;
  if p_status not in('open','in_progress','waiting_customer','resolved','closed') then raise exception 'Invalid status';end if;
  update public.support_tickets set status=p_status,updated_at=now(),resolved_at=case when p_status in('resolved','closed') then coalesce(resolved_at,now()) else null end where id=p_ticket_id;
end $$;
grant execute on function public.platform_support_ticket_status_v4(uuid,text) to authenticated;

commit;
select 'Flexi ERP V4 release/support foundation ready' as status;
