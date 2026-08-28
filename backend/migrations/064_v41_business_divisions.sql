-- FLEXI ERP V4.1
-- Business Division -> tenant/business -> MAIN/child locations -> terminals hierarchy.
begin;

create table if not exists public.business_divisions(
  id uuid primary key default gen_random_uuid(),
  division_code text not null unique,
  name text not null,
  main_tenant_id uuid references public.tenants(id) on delete set null,
  active boolean not null default true,
  settings jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.business_division_members(
  division_id uuid not null references public.business_divisions(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  member_type text not null default 'child' check(member_type in('main','child')),
  created_at timestamptz not null default now(),
  primary key(division_id,tenant_id),
  unique(tenant_id)
);
create unique index if not exists ux_business_division_one_main
  on public.business_division_members(division_id) where member_type='main';

alter table public.business_divisions enable row level security;
alter table public.business_division_members enable row level security;
revoke all on public.business_divisions,public.business_division_members from anon,authenticated;

create sequence if not exists public.business_division_code_seq;

create or replace function public.platform_divisions_list_v41()
returns table(division_id uuid,division_code text,division_name text,main_tenant_id uuid,main_business_name text,member_count bigint,active boolean)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required';end if;
  return query
  select d.id,d.division_code::text,d.name::text,d.main_tenant_id,t.name::text,
    (select count(*) from public.business_division_members dm where dm.division_id=d.id),d.active
  from public.business_divisions d
  left join public.tenants t on t.id=d.main_tenant_id
  order by d.active desc,d.name;
end $$;
grant execute on function public.platform_divisions_list_v41() to authenticated;

create or replace function public.platform_division_save_v41(
  p_division_id uuid,p_name text,p_division_code text default null,p_active boolean default true
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid:=coalesce(p_division_id,gen_random_uuid());v_code text;begin
  if not private.platform_v2_has_role('super_admin') then raise exception 'Super Admin required';end if;
  if trim(coalesce(p_name,''))='' then raise exception 'Division name is required';end if;
  v_code:=upper(regexp_replace(trim(coalesce(p_division_code,'')),'[^A-Za-z0-9_-]+','','g'));
  if v_code='' then v_code:='DIV-'||lpad(nextval('public.business_division_code_seq')::text,5,'0');end if;
  insert into public.business_divisions(id,division_code,name,active,created_by,updated_at)
  values(v_id,v_code,trim(p_name),coalesce(p_active,true),auth.uid(),now())
  on conflict(id) do update set name=excluded.name,active=excluded.active,updated_at=now();
  perform private.platform_audit_write(case when p_division_id is null then 'division.create' else 'division.update' end,'business_division',v_id::text,null,jsonb_build_object('name',trim(p_name),'code',v_code));
  return v_id;
end $$;
grant execute on function public.platform_division_save_v41(uuid,text,text,boolean) to authenticated;

create or replace function public.platform_division_assign_business_v41(
  p_division_id uuid,p_tenant_id uuid,p_member_type text default 'child'
) returns void
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_type text:=lower(coalesce(p_member_type,'child'));v_old_div uuid;v_old_type text;begin
  if not private.platform_v2_has_role('super_admin') then raise exception 'Super Admin required';end if;
  if not exists(select 1 from public.business_divisions where id=p_division_id and active) then raise exception 'Division not found';end if;
  if not exists(select 1 from public.tenants where id=p_tenant_id) then raise exception 'Business not found';end if;
  if v_type not in('main','child') then raise exception 'Invalid division member type';end if;

  select division_id,member_type into v_old_div,v_old_type from public.business_division_members where tenant_id=p_tenant_id;
  delete from public.business_division_members where tenant_id=p_tenant_id;
  if v_old_div is not null and v_old_type='main' and (v_old_div<>p_division_id or v_type<>'main') then
    update public.business_divisions set main_tenant_id=null,updated_at=now() where id=v_old_div and main_tenant_id=p_tenant_id;
  end if;
  if v_type='main' then
    -- One main business per division. The previous main remains a child member.
    update public.business_division_members set member_type='child' where division_id=p_division_id and member_type='main';
    update public.business_divisions set main_tenant_id=p_tenant_id,updated_at=now() where id=p_division_id;
  end if;
  insert into public.business_division_members(division_id,tenant_id,member_type) values(p_division_id,p_tenant_id,v_type)
  on conflict(division_id,tenant_id) do update set member_type=excluded.member_type;
  perform private.platform_audit_write('division.assign_business','business_division',p_division_id::text,p_tenant_id,jsonb_build_object('member_type',v_type));
end $$;
grant execute on function public.platform_division_assign_business_v41(uuid,uuid,text) to authenticated;

create or replace function public.platform_division_remove_business_v41(p_tenant_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_div uuid;begin
  if not private.platform_v2_has_role('super_admin') then raise exception 'Super Admin required';end if;
  select division_id into v_div from public.business_division_members where tenant_id=p_tenant_id;
  delete from public.business_division_members where tenant_id=p_tenant_id;
  if v_div is not null then
    update public.business_divisions set main_tenant_id=null,updated_at=now() where id=v_div and main_tenant_id=p_tenant_id;
  end if;
  perform private.platform_audit_write('division.remove_business','tenant',p_tenant_id::text,p_tenant_id,'{}'::jsonb);
end $$;
grant execute on function public.platform_division_remove_business_v41(uuid) to authenticated;

create or replace function public.platform_list_businesses_v41()
returns table(
  id uuid,name text,slug text,business_type text,status text,module_count bigint,created_at timestamptz,
  division_id uuid,division_name text,division_role text
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required';end if;
  return query
  select t.id,t.name::text,t.slug::text,t.business_type::text,t.status::text,
    (select count(*) from public.tenant_modules tm where tm.tenant_id=t.id and tm.enabled),t.created_at,
    dm.division_id,d.name::text,dm.member_type::text
  from public.tenants t
  left join public.business_division_members dm on dm.tenant_id=t.id
  left join public.business_divisions d on d.id=dm.division_id
  order by coalesce(d.name,t.name),case when dm.member_type='main' then 0 else 1 end,t.name;
end $$;
grant execute on function public.platform_list_businesses_v41() to authenticated;

create or replace function public.platform_business_prepare_delete_v41(
  p_tenant_id uuid,p_confirm_code text
) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_tenant record;v_member record;v_children bigint;begin
  if not private.platform_v2_has_role('super_admin') then raise exception 'Super Admin required';end if;
  select id,name,business_code,status into v_tenant from public.tenants where id=p_tenant_id;
  if v_tenant.id is null then raise exception 'Business not found';end if;
  if upper(trim(coalesce(p_confirm_code,'')))<>upper(coalesce(v_tenant.business_code,'')) then
    raise exception 'Business code confirmation does not match';
  end if;
  select division_id,member_type into v_member from public.business_division_members where tenant_id=p_tenant_id;
  if v_member.member_type='main' then
    select count(*) into v_children from public.business_division_members
    where division_id=v_member.division_id and tenant_id<>p_tenant_id;
    if coalesce(v_children,0)>0 then
      raise exception 'Move or remove child businesses from this division before permanently deleting the main business';
    end if;
  end if;
  perform private.platform_audit_write(
    'business.permanent_delete_requested','tenant',p_tenant_id::text,p_tenant_id,
    jsonb_build_object('name',v_tenant.name,'business_code',v_tenant.business_code)
  );
  return jsonb_build_object(
    'tenant_id',v_tenant.id,'name',v_tenant.name,'business_code',v_tenant.business_code,
    'status',v_tenant.status,'division_id',v_member.division_id,'division_role',v_member.member_type
  );
end $$;
grant execute on function public.platform_business_prepare_delete_v41(uuid,text) to authenticated;

create or replace function public.platform_business_archive_v41(p_tenant_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.platform_v2_has_role('super_admin') then raise exception 'Super Admin required';end if;
  if not exists(select 1 from public.tenants where id=p_tenant_id) then raise exception 'Business not found';end if;
  update public.tenants set status='inactive' where id=p_tenant_id;
  update public.business_devices set status='revoked',activation_hash=null,activation_expires_at=null,updated_at=now() where tenant_id=p_tenant_id and status<>'revoked';
  perform private.platform_audit_write('business.archive','tenant',p_tenant_id::text,p_tenant_id,jsonb_build_object('reason',nullif(trim(coalesce(p_reason,'')),'')));
end $$;
grant execute on function public.platform_business_archive_v41(uuid,text) to authenticated;

commit;
select 'Flexi ERP V4.1 business divisions ready' as status;
