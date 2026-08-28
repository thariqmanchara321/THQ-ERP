-- FLEXI ERP V4 notifications, tasks/internal CRM and document attachments.
begin;
create table if not exists public.notifications(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,user_id uuid references auth.users(id) on delete cascade,location_id uuid references public.business_locations(id) on delete cascade,
  category text not null default 'system',severity text not null default 'info' check(severity in('info','success','warning','critical')),title text not null,message text not null,entity_type text,entity_id uuid,read_at timestamptz,created_at timestamptz not null default now()
);
create index if not exists idx_notifications_user on public.notifications(tenant_id,user_id,read_at,created_at desc);
create table if not exists public.business_tasks(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,location_id uuid references public.business_locations(id),title text not null,description text,priority text not null default 'normal' check(priority in('low','normal','high','urgent')),status text not null default 'open' check(status in('open','in_progress','done','cancelled')),assigned_to uuid references auth.users(id),due_at timestamptz,entity_type text,entity_id uuid,created_by uuid references auth.users(id),created_at timestamptz not null default now(),completed_at timestamptz
);
create table if not exists public.entity_attachments(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,entity_type text not null,entity_id uuid not null,file_name text not null,storage_path text not null,mime_type text,file_size bigint,visibility text not null default 'tenant' check(visibility in('tenant','restricted','private')),uploaded_by uuid references auth.users(id),created_at timestamptz not null default now()
);
alter table public.notifications enable row level security;alter table public.business_tasks enable row level security;alter table public.entity_attachments enable row level security;revoke all on public.notifications,public.business_tasks,public.entity_attachments from anon,authenticated;

create or replace function public.notifications_list_v4(p_tenant_id uuid,p_limit integer default 50)
returns setof public.notifications language plpgsql security definer set search_path=public,private,pg_temp as $$ begin if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;return query select * from public.notifications where tenant_id=p_tenant_id and (user_id is null or user_id=auth.uid()) order by created_at desc limit greatest(1,least(coalesce(p_limit,50),200));end $$;
grant execute on function public.notifications_list_v4(uuid,integer) to authenticated;
create or replace function public.notification_mark_read_v4(p_tenant_id uuid,p_notification_id uuid) returns void language sql security definer set search_path=public,private,pg_temp as $$ update public.notifications set read_at=coalesce(read_at,now()) where id=p_notification_id and tenant_id=p_tenant_id and (user_id is null or user_id=auth.uid()) $$;
grant execute on function public.notification_mark_read_v4(uuid,uuid) to authenticated;


create or replace function public.business_tasks_list_v4(p_tenant_id uuid,p_location_id uuid default null,p_status text default null)
returns table(id uuid,title text,description text,priority text,status text,assigned_to uuid,assigned_username text,due_at timestamptz,location_id uuid,location_code text,entity_type text,entity_id uuid,created_at timestamptz)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  select t.id,t.title,t.description,t.priority,t.status,t.assigned_to,coalesce(u.username,''),t.due_at,t.location_id,coalesce(l.location_code,''),t.entity_type,t.entity_id,t.created_at
  from public.business_tasks t
  left join public.user_login_names u on u.user_id=t.assigned_to
  left join public.business_locations l on l.id=t.location_id
  where t.tenant_id=p_tenant_id
    and (p_location_id is null or t.location_id=p_location_id)
    and (p_status is null or p_status='' or t.status=p_status)
    and (t.location_id is null or private.erp_user_location_allowed(p_tenant_id,t.location_id,'view') or private.erp_user_is_owner(p_tenant_id))
  order by case t.priority when 'urgent' then 1 when 'high' then 2 when 'normal' then 3 else 4 end,coalesce(t.due_at,'infinity'::timestamptz),t.created_at desc;
end $$;
grant execute on function public.business_tasks_list_v4(uuid,uuid,text) to authenticated;

create or replace function public.business_task_save_v4(
  p_tenant_id uuid,p_task_id uuid,p_location_id uuid,p_title text,p_description text,p_priority text,p_status text,p_assigned_to uuid,p_due_at timestamptz,p_entity_type text default null,p_entity_id uuid default null
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid; begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'tasks.manage') then raise exception 'Task permission required';end if;
  if p_location_id is not null then perform private.v4_location_access(p_tenant_id,p_location_id,'operate');end if;
  if trim(coalesce(p_title,''))='' then raise exception 'Task title required';end if;
  if p_task_id is null then
    insert into public.business_tasks(tenant_id,location_id,title,description,priority,status,assigned_to,due_at,entity_type,entity_id,created_by)
    values(p_tenant_id,p_location_id,trim(p_title),nullif(trim(coalesce(p_description,'')),''),coalesce(nullif(p_priority,''),'normal'),coalesce(nullif(p_status,''),'open'),p_assigned_to,p_due_at,nullif(trim(coalesce(p_entity_type,'')),''),p_entity_id,auth.uid()) returning id into v_id;
  else
    update public.business_tasks set location_id=p_location_id,title=trim(p_title),description=nullif(trim(coalesce(p_description,'')),''),priority=coalesce(nullif(p_priority,''),'normal'),status=coalesce(nullif(p_status,''),'open'),assigned_to=p_assigned_to,due_at=p_due_at,entity_type=nullif(trim(coalesce(p_entity_type,'')),''),entity_id=p_entity_id,completed_at=case when p_status='done' then coalesce(completed_at,now()) else null end
    where id=p_task_id and tenant_id=p_tenant_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'Task not found';end if;
  return v_id;
end $$;
grant execute on function public.business_task_save_v4(uuid,uuid,uuid,text,text,text,text,uuid,timestamptz,text,uuid) to authenticated;

commit;
select 'Flexi ERP V4 notifications/tasks/files foundation ready' as status;
