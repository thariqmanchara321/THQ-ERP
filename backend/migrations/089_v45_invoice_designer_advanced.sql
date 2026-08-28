-- THQ V4.5
-- Advanced tenant-owned invoice templates, live-customizable overrides and optional store/terminal assignment.
begin;

alter table public.invoice_templates add column if not exists owner_tenant_id uuid references public.tenants(id) on delete cascade;
create index if not exists idx_invoice_templates_owner_v45 on public.invoice_templates(owner_tenant_id,paper_type,is_active);

drop policy if exists invoice_templates_read on public.invoice_templates;
drop policy if exists invoice_templates_read_v45 on public.invoice_templates;
create policy invoice_templates_read_v45 on public.invoice_templates for select to authenticated
using(
  (is_active and owner_tenant_id is null)
  or (owner_tenant_id is not null and private.erp_user_has_tenant_access(owner_tenant_id))
  or private.platform_v2_is_admin()
);

create table if not exists public.tenant_invoice_template_assignments_v45(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  paper_type text not null check(paper_type in('a4','80mm')),
  template_id uuid not null references public.invoice_templates(id) on delete restrict,
  location_id uuid references public.business_locations(id) on delete cascade,
  device_id uuid references public.business_devices(id) on delete cascade,
  overrides jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);
create unique index if not exists ux_tenant_invoice_assignment_v45
on public.tenant_invoice_template_assignments_v45(
  tenant_id,paper_type,
  coalesce(location_id,'00000000-0000-0000-0000-000000000000'::uuid),
  coalesce(device_id,'00000000-0000-0000-0000-000000000000'::uuid)
);
alter table public.tenant_invoice_template_assignments_v45 enable row level security;
revoke all on public.tenant_invoice_template_assignments_v45 from anon,authenticated;
grant select on public.tenant_invoice_template_assignments_v45 to authenticated;
drop policy if exists tenant_invoice_assignment_read_v45 on public.tenant_invoice_template_assignments_v45;
create policy tenant_invoice_assignment_read_v45 on public.tenant_invoice_template_assignments_v45 for select to authenticated
using(private.erp_user_has_tenant_access(tenant_id));

create or replace function public.tenant_invoice_templates_list_v45(p_tenant_id uuid,p_paper_type text default null)
returns table(
  template_id uuid,template_key text,template_name text,paper_type text,description text,
  base_config jsonb,selected boolean,overrides jsonb,effective_config jsonb,sample_logo_key text,
  is_custom boolean
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  select it.id,it.key::text,it.name::text,it.paper_type::text,it.description::text,it.config,
    (tit.template_id=it.id),coalesce(tit.overrides,'{}'::jsonb),it.config||coalesce(tit.overrides,'{}'::jsonb),it.sample_logo_key::text,
    (it.owner_tenant_id is not null)
  from public.invoice_templates it
  left join public.tenant_invoice_templates tit on tit.tenant_id=p_tenant_id and tit.paper_type=it.paper_type
  where it.is_active and (it.owner_tenant_id is null or it.owner_tenant_id=p_tenant_id)
    and (p_paper_type is null or it.paper_type=p_paper_type)
  order by it.paper_type,(tit.template_id=it.id) desc,(it.owner_tenant_id=p_tenant_id) desc,it.is_system desc,it.name;
end $$;
grant execute on function public.tenant_invoice_templates_list_v45(uuid,text) to authenticated;

create or replace function public.tenant_invoice_template_clone_v45(
  p_tenant_id uuid,p_source_template_id uuid,p_name text,p_paper_type text,p_config jsonb default null
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare src public.invoice_templates%rowtype;v_id uuid;v_key text;begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'settings.manage') then raise exception 'Settings permission required';end if;
  if trim(coalesce(p_name,''))='' then raise exception 'Template name is required';end if;
  if p_paper_type not in('a4','80mm') then raise exception 'Invalid paper type';end if;
  select * into src from public.invoice_templates where id=p_source_template_id and is_active and (owner_tenant_id is null or owner_tenant_id=p_tenant_id);
  if not found then raise exception 'Source template not found';end if;
  v_key:='tenant_'||replace(p_tenant_id::text,'-','')||'_'||substr(replace(gen_random_uuid()::text,'-',''),1,10);
  insert into public.invoice_templates(key,name,paper_type,description,config,sample_logo_key,is_system,is_active,owner_tenant_id)
  values(v_key,trim(p_name),p_paper_type,'Custom THQ invoice template',coalesce(p_config,src.config),src.sample_logo_key,false,true,p_tenant_id)
  returning id into v_id;
  perform private.business_audit_write(p_tenant_id,'invoice_template.create','invoice_template',v_id,p_name,null,jsonb_build_object('source_template_id',p_source_template_id,'paper_type',p_paper_type));
  return v_id;
end $$;
grant execute on function public.tenant_invoice_template_clone_v45(uuid,uuid,text,text,jsonb) to authenticated;

create or replace function public.tenant_invoice_template_update_v45(
  p_tenant_id uuid,p_template_id uuid,p_name text,p_config jsonb,p_is_active boolean default true
) returns void
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'settings.manage') then raise exception 'Settings permission required';end if;
  update public.invoice_templates set name=coalesce(nullif(trim(p_name),''),name),config=coalesce(p_config,config),is_active=p_is_active,updated_at=now()
  where id=p_template_id and owner_tenant_id=p_tenant_id;
  if not found then raise exception 'Only business-owned custom templates can be edited directly';end if;
  perform private.business_audit_write(p_tenant_id,'invoice_template.update','invoice_template',p_template_id,p_name,null,jsonb_build_object('active',p_is_active));
end $$;
grant execute on function public.tenant_invoice_template_update_v45(uuid,uuid,text,jsonb,boolean) to authenticated;

create or replace function public.tenant_invoice_template_save_v45(p_tenant_id uuid,p_paper_type text,p_template_id uuid,p_overrides jsonb)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v jsonb:=coalesce(p_overrides,'{}'::jsonb);begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'settings.manage') then raise exception 'Settings permission required';end if;
  if p_paper_type not in('a4','80mm') then raise exception 'Invalid paper type';end if;
  if not exists(select 1 from public.invoice_templates where id=p_template_id and paper_type=p_paper_type and is_active and (owner_tenant_id is null or owner_tenant_id=p_tenant_id)) then raise exception 'Invoice template not found';end if;
  insert into public.tenant_invoice_templates(tenant_id,paper_type,template_id,overrides,updated_at,updated_by)
  values(p_tenant_id,p_paper_type,p_template_id,v,now(),auth.uid())
  on conflict(tenant_id,paper_type) do update set template_id=excluded.template_id,overrides=excluded.overrides,updated_at=now(),updated_by=auth.uid();
  perform private.business_audit_write(p_tenant_id,'invoice_template.default','invoice_template',p_template_id,p_paper_type,null,jsonb_build_object('paper_type',p_paper_type,'overrides',v));
end $$;
grant execute on function public.tenant_invoice_template_save_v45(uuid,text,uuid,jsonb) to authenticated;

create or replace function public.tenant_invoice_template_assign_v45(
  p_tenant_id uuid,p_paper_type text,p_template_id uuid,p_location_id uuid default null,p_device_id uuid default null,p_overrides jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid;begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'settings.manage') then raise exception 'Settings permission required';end if;
  if p_location_id is not null and not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id) then raise exception 'Store does not belong to business';end if;
  if p_device_id is not null and not exists(select 1 from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and (p_location_id is null or location_id=p_location_id)) then raise exception 'Terminal does not belong to selected store';end if;
  if not exists(select 1 from public.invoice_templates where id=p_template_id and paper_type=p_paper_type and is_active and (owner_tenant_id is null or owner_tenant_id=p_tenant_id)) then raise exception 'Template not available';end if;
  select id into v_id from public.tenant_invoice_template_assignments_v45
  where tenant_id=p_tenant_id and paper_type=p_paper_type and location_id is not distinct from p_location_id and device_id is not distinct from p_device_id
  limit 1;
  if v_id is null then
    insert into public.tenant_invoice_template_assignments_v45(tenant_id,paper_type,template_id,location_id,device_id,overrides,updated_at,updated_by)
    values(p_tenant_id,p_paper_type,p_template_id,p_location_id,p_device_id,coalesce(p_overrides,'{}'::jsonb),now(),auth.uid())
    returning id into v_id;
  else
    update public.tenant_invoice_template_assignments_v45 set template_id=p_template_id,overrides=coalesce(p_overrides,'{}'::jsonb),is_active=true,updated_at=now(),updated_by=auth.uid() where id=v_id;
  end if;
  perform private.business_audit_write(p_tenant_id,'invoice_template.assign','invoice_template',p_template_id,p_paper_type,p_location_id,jsonb_build_object('device_id',p_device_id));
  return v_id;
end $$;
grant execute on function public.tenant_invoice_template_assign_v45(uuid,text,uuid,uuid,uuid,jsonb) to authenticated;

create or replace function public.tenant_invoice_template_get_v45(p_tenant_id uuid,p_paper_type text,p_location_id uuid default null,p_device_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare a record;t record;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select x.* into a from public.tenant_invoice_template_assignments_v45 x
  where x.tenant_id=p_tenant_id and x.paper_type=p_paper_type and x.is_active
    and (x.location_id is null or x.location_id=p_location_id)
    and (x.device_id is null or x.device_id=p_device_id)
  order by (x.device_id is not null) desc,(x.location_id is not null) desc,x.updated_at desc limit 1;
  if found then
    select * into t from public.invoice_templates where id=a.template_id and is_active;
    return jsonb_build_object('id',t.id,'key',t.key,'name',t.name,'paper_type',t.paper_type,'config',t.config||coalesce(a.overrides,'{}'::jsonb),'sample_logo_key',t.sample_logo_key,'assignment_id',a.id);
  end if;
  select it.*,tit.overrides as tenant_overrides into t
  from public.tenant_invoice_templates tit join public.invoice_templates it on it.id=tit.template_id
  where tit.tenant_id=p_tenant_id and tit.paper_type=p_paper_type and it.is_active;
  if found then
    return jsonb_build_object('id',t.id,'key',t.key,'name',t.name,'paper_type',t.paper_type,'config',t.config||coalesce(t.tenant_overrides,'{}'::jsonb),'sample_logo_key',t.sample_logo_key);
  end if;
  select * into t from public.invoice_templates where paper_type=p_paper_type and is_active and owner_tenant_id is null order by is_system desc,name limit 1;
  return coalesce(jsonb_build_object('id',t.id,'key',t.key,'name',t.name,'paper_type',t.paper_type,'config',t.config,'sample_logo_key',t.sample_logo_key),'{}'::jsonb);
end $$;
grant execute on function public.tenant_invoice_template_get_v45(uuid,text,uuid,uuid) to authenticated;

commit;
select 'THQ V4.5 advanced invoice designer ready' as status;
