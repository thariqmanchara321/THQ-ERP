-- THQ ERP v5.0.0 — centralized tasks/notifications hardening, history and escalation.
begin;

alter table public.business_tasks add column if not exists escalation_at timestamptz;
alter table public.business_tasks add column if not exists escalated_at timestamptz;
alter table public.business_tasks add column if not exists escalation_user_id uuid references auth.users(id) on delete set null;

create table if not exists public.business_task_history_v500(
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  task_id uuid not null references public.business_tasks(id) on delete cascade,
  event_type text not null,
  from_status text,
  to_status text,
  note text,
  changed_by uuid references auth.users(id),
  changed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);
create index if not exists idx_task_history_v500 on public.business_task_history_v500(tenant_id,task_id,id desc);
alter table public.business_task_history_v500 enable row level security;
revoke all on public.business_task_history_v500 from anon,authenticated;

create table if not exists public.business_task_comments_v500(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  task_id uuid not null references public.business_tasks(id) on delete cascade,
  comment text not null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
alter table public.business_task_comments_v500 enable row level security;
revoke all on public.business_task_comments_v500 from anon,authenticated;

create or replace function private.v500_task_audit_trigger()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if tg_op='INSERT' then
    insert into public.business_task_history_v500(tenant_id,task_id,event_type,to_status,note,changed_by,metadata)
    values(new.tenant_id,new.id,'created',new.status,'Task created',coalesce(auth.uid(),new.created_by),jsonb_build_object('priority',new.priority,'assigned_to',new.assigned_to));
  elsif tg_op='UPDATE' then
    if old.status is distinct from new.status or old.assigned_to is distinct from new.assigned_to or old.due_at is distinct from new.due_at or old.priority is distinct from new.priority then
      insert into public.business_task_history_v500(tenant_id,task_id,event_type,from_status,to_status,note,changed_by,metadata)
      values(new.tenant_id,new.id,'updated',old.status,new.status,'Task updated',auth.uid(),jsonb_build_object('old_priority',old.priority,'priority',new.priority,'old_assigned_to',old.assigned_to,'assigned_to',new.assigned_to,'old_due_at',old.due_at,'due_at',new.due_at));
    end if;
  end if;return new;
end $$;
revoke all on function private.v500_task_audit_trigger() from public;
drop trigger if exists trg_business_task_audit_v500 on public.business_tasks;
create trigger trg_business_task_audit_v500 after insert or update on public.business_tasks for each row execute function private.v500_task_audit_trigger();

-- Fix the v4.9.5 citext/text mismatch explicitly and surface v5 escalation columns.
create or replace function public.business_tasks_list_v495(p_tenant_id uuid,p_location_id uuid default null,p_status text default null)
returns table(
  id uuid,title text,description text,priority text,status text,assigned_to uuid,assigned_username text,
  due_at timestamptz,reminder_at timestamptz,location_id uuid,location_code text,entity_type text,entity_id uuid,
  source_notification_id uuid,metadata jsonb,created_at timestamptz,updated_at timestamptz
)
language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  select t.id,t.title::text,t.description::text,t.priority::text,t.status::text,t.assigned_to,coalesce(u.username::text,''::text),
    t.due_at,t.reminder_at,t.location_id,coalesce(l.location_code::text,''::text),t.entity_type::text,t.entity_id,
    t.source_notification_id,coalesce(t.metadata,'{}'::jsonb),t.created_at,t.updated_at
  from public.business_tasks t
  left join public.user_login_names u on u.user_id=t.assigned_to
  left join public.business_locations l on l.id=t.location_id
  where t.tenant_id=p_tenant_id
    and (p_location_id is null or t.location_id=p_location_id)
    and (p_status is null or p_status='' or t.status=p_status)
    and (t.location_id is null or private.erp_user_location_allowed(p_tenant_id,t.location_id,'view') or private.erp_user_is_owner(p_tenant_id))
    and (t.assigned_to is null or t.assigned_to=auth.uid() or private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'tasks.manage'))
  order by case when t.status in('done','cancelled') then 1 else 0 end,case when t.due_at is not null and t.due_at<now() and t.status not in('done','cancelled') then 0 else 1 end,case t.priority when 'urgent' then 1 when 'high' then 2 when 'normal' then 3 else 4 end,coalesce(t.due_at,'infinity'::timestamptz),t.created_at desc;
end $$;
grant execute on function public.business_tasks_list_v495(uuid,uuid,text) to authenticated;

create or replace function public.business_task_escalation_set_v500(p_tenant_id uuid,p_task_id uuid,p_escalation_at timestamptz,p_escalation_user_id uuid default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'tasks.manage') then raise exception 'Task permission required';end if;
  update public.business_tasks set escalation_at=p_escalation_at,escalation_user_id=p_escalation_user_id,escalated_at=null,updated_at=now() where id=p_task_id and tenant_id=p_tenant_id;if not found then raise exception 'Task not found';end if;
end $$;
grant execute on function public.business_task_escalation_set_v500(uuid,uuid,timestamptz,uuid) to authenticated;

create or replace function public.business_task_comment_add_v500(p_tenant_id uuid,p_task_id uuid,p_comment text)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$ declare v uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;if trim(coalesce(p_comment,''))='' then raise exception 'Comment is required';end if;
  if not exists(select 1 from public.business_tasks where tenant_id=p_tenant_id and id=p_task_id) then raise exception 'Task not found';end if;
  insert into public.business_task_comments_v500(tenant_id,task_id,comment,created_by) values(p_tenant_id,p_task_id,trim(p_comment),auth.uid()) returning id into v;
  insert into public.business_task_history_v500(tenant_id,task_id,event_type,note,changed_by) values(p_tenant_id,p_task_id,'comment',trim(p_comment),auth.uid());return v;
end $$;
grant execute on function public.business_task_comment_add_v500(uuid,uuid,text) to authenticated;

create or replace function public.business_task_timeline_v500(p_tenant_id uuid,p_task_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare h jsonb;c jsonb;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.changed_at desc),'[]'::jsonb) into h from public.business_task_history_v500 x where x.tenant_id=p_tenant_id and x.task_id=p_task_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'comment',x.comment,'created_by',x.created_by,'created_at',x.created_at) order by x.created_at desc),'[]'::jsonb) into c from public.business_task_comments_v500 x where x.tenant_id=p_tenant_id and x.task_id=p_task_id;
  return jsonb_build_object('history',h,'comments',c);
end $$;
grant execute on function public.business_task_timeline_v500(uuid,uuid) to authenticated;

create or replace function private.v500_refresh_notifications(p_tenant_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare r record;begin
  -- Inventory severity: out-of-stock, low-stock and dead-stock.
  for r in select * from public.inventory_intelligence_v480(p_tenant_id,null,30,'',1000) where status in('out_of_stock','low_stock','dead_stock') order by case status when 'out_of_stock' then 0 when 'low_stock' then 1 else 2 end limit 150 loop
    if not exists(select 1 from public.notifications n where n.tenant_id=p_tenant_id and n.user_id=p_user_id and n.category='inventory' and n.entity_type='product_variant' and n.entity_id=r.variant_id and n.title like case when r.status='out_of_stock' then 'Out of stock%' when r.status='low_stock' then 'Low stock%' else 'Dead stock%' end and n.read_at is null and n.created_at>now()-interval '12 hours') then
      insert into public.notifications(tenant_id,user_id,location_id,category,severity,title,message,entity_type,entity_id)
      values(p_tenant_id,p_user_id,r.location_id,'inventory',case when r.status='out_of_stock' then 'critical' when r.status='low_stock' then 'warning' else 'info' end,case when r.status='out_of_stock' then 'Out of stock • ' when r.status='low_stock' then 'Low stock • ' else 'Dead stock • ' end||r.product_name,'Available '||round(r.available,2)||' • reorder '||round(r.suggested_reorder,2),'product_variant',r.variant_id);
    end if;
  end loop;

  -- POS/client systems that have not checked in for two hours.
  for r in select d.id,d.location_id,d.device_code,d.name,d.app_type,d.last_seen_at from public.business_devices d where d.tenant_id=p_tenant_id and d.status='active' and d.app_type in('pos','client') and d.last_seen_at is not null and d.last_seen_at<now()-interval '2 hours' order by d.last_seen_at limit 100 loop
    if not exists(select 1 from public.notifications n where n.tenant_id=p_tenant_id and n.user_id=p_user_id and n.category='sync' and n.entity_type='device' and n.entity_id=r.id and n.read_at is null and n.created_at>now()-interval '6 hours') then
      insert into public.notifications(tenant_id,user_id,location_id,category,severity,title,message,entity_type,entity_id) values(p_tenant_id,p_user_id,r.location_id,'sync','critical',upper(r.app_type)||' not synchronized • '||coalesce(r.device_code,r.name),'Last seen '||r.last_seen_at,'device',r.id);
    end if;
  end loop;

  -- Recurring expenses due now.
  for r in select id,location_id,title,next_run_date,amount from public.recurring_expenses_v500 where tenant_id=p_tenant_id and active and next_run_date<=current_date order by next_run_date limit 100 loop
    if not exists(select 1 from public.notifications n where n.tenant_id=p_tenant_id and n.user_id=p_user_id and n.category='expense' and n.entity_type='recurring_expense' and n.entity_id=r.id and n.read_at is null and n.created_at>now()-interval '24 hours') then
      insert into public.notifications(tenant_id,user_id,location_id,category,severity,title,message,entity_type,entity_id) values(p_tenant_id,p_user_id,r.location_id,'expense','warning','Recurring expense due • '||r.title,'Amount '||round(r.amount,2)||' • due '||r.next_run_date,'recurring_expense',r.id);
    end if;
  end loop;

  -- Task escalation.
  for r in select id,location_id,title,assigned_to,escalation_user_id,due_at from public.business_tasks where tenant_id=p_tenant_id and status not in('done','cancelled') and escalation_at is not null and escalation_at<=now() and escalated_at is null for update loop
    insert into public.notifications(tenant_id,user_id,location_id,category,severity,title,message,entity_type,entity_id) values(p_tenant_id,coalesce(r.escalation_user_id,r.assigned_to,p_user_id),r.location_id,'task','critical','Task escalated • '||r.title,case when r.due_at is null then 'Task requires immediate attention' else 'Due '||r.due_at end,'task',r.id);
    update public.business_tasks set escalated_at=now(),updated_at=now() where id=r.id;
  end loop;
end $$;
revoke all on function private.v500_refresh_notifications(uuid,uuid) from public;

create or replace function public.notifications_list_v4(p_tenant_id uuid,p_limit integer default 50)
returns setof public.notifications language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  perform private.v4_refresh_notifications(p_tenant_id,auth.uid());
  perform private.loan_v490_refresh_notifications(p_tenant_id,auth.uid());
  perform private.v495_refresh_notifications(p_tenant_id,auth.uid());
  perform private.v500_refresh_notifications(p_tenant_id,auth.uid());
  return query select * from public.notifications where tenant_id=p_tenant_id and (user_id is null or user_id=auth.uid()) order by case severity when 'critical' then 0 when 'warning' then 1 when 'info' then 2 else 3 end,(read_at is null) desc,created_at desc limit greatest(1,least(coalesce(p_limit,50),300));
end $$;
grant execute on function public.notifications_list_v4(uuid,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(205,'5.0.0','Notification & Task Center','Fixes task citext runtime mismatch and adds task history/comments/escalation plus inventory, sync, recurring-expense and task escalation notifications.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v5.0.0 migration 205 applied' as status;
