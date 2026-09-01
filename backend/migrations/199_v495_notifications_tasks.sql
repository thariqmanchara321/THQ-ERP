-- THQ ERP v4.9.5 — synchronized operational notifications and tasks.
begin;

alter table public.business_tasks add column if not exists reminder_at timestamptz;
alter table public.business_tasks add column if not exists source_notification_id uuid references public.notifications(id) on delete set null;
alter table public.business_tasks add column if not exists metadata jsonb not null default '{}'::jsonb;
alter table public.business_tasks add column if not exists updated_at timestamptz not null default now();
create index if not exists idx_business_tasks_due_v495 on public.business_tasks(tenant_id,status,due_at,reminder_at);
create index if not exists idx_business_tasks_source_notification_v495 on public.business_tasks(tenant_id,source_notification_id);

create or replace function public.business_task_save_v495(
  p_tenant_id uuid,p_task_id uuid,p_location_id uuid,p_title text,p_description text,p_priority text,p_status text,
  p_assigned_to uuid,p_due_at timestamptz,p_reminder_at timestamptz default null,p_entity_type text default null,
  p_entity_id uuid default null,p_source_notification_id uuid default null,p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_id uuid; v_assigned uuid; v_old_status text;
begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'tasks.manage') then raise exception 'Task permission required';end if;
  if p_location_id is not null then perform private.v4_location_access(p_tenant_id,p_location_id,'operate');end if;
  if trim(coalesce(p_title,''))='' then raise exception 'Task title required';end if;
  if coalesce(p_priority,'normal') not in('low','normal','high','urgent') then raise exception 'Invalid task priority';end if;
  if coalesce(p_status,'open') not in('open','in_progress','done','cancelled') then raise exception 'Invalid task status';end if;
  if p_due_at is not null and p_reminder_at is not null and p_reminder_at>p_due_at then raise exception 'Reminder cannot be after the task due time';end if;
  if p_assigned_to is not null and not exists(
    select 1 from public.tenant_memberships m where m.tenant_id=p_tenant_id and m.user_id=p_assigned_to and m.status='active'
  ) then raise exception 'Assigned user is not an active member of this business';end if;

  if p_task_id is null then
    insert into public.business_tasks(
      tenant_id,location_id,title,description,priority,status,assigned_to,due_at,reminder_at,entity_type,entity_id,
      source_notification_id,metadata,created_by,updated_at
    ) values(
      p_tenant_id,p_location_id,trim(p_title),nullif(trim(coalesce(p_description,'')),''),coalesce(nullif(p_priority,''),'normal'),
      coalesce(nullif(p_status,''),'open'),p_assigned_to,p_due_at,p_reminder_at,nullif(trim(coalesce(p_entity_type,'')),''),p_entity_id,
      p_source_notification_id,coalesce(p_metadata,'{}'::jsonb),auth.uid(),now()
    ) returning id,assigned_to into v_id,v_assigned;
  else
    select status into v_old_status from public.business_tasks where id=p_task_id and tenant_id=p_tenant_id;
    update public.business_tasks set
      location_id=p_location_id,title=trim(p_title),description=nullif(trim(coalesce(p_description,'')),''),
      priority=coalesce(nullif(p_priority,''),'normal'),status=coalesce(nullif(p_status,''),'open'),assigned_to=p_assigned_to,
      due_at=p_due_at,reminder_at=p_reminder_at,entity_type=nullif(trim(coalesce(p_entity_type,'')),''),entity_id=p_entity_id,
      source_notification_id=coalesce(p_source_notification_id,source_notification_id),metadata=coalesce(p_metadata,metadata),updated_at=now(),
      completed_at=case when p_status='done' then coalesce(completed_at,now()) else null end
    where id=p_task_id and tenant_id=p_tenant_id returning id,assigned_to into v_id,v_assigned;
  end if;
  if v_id is null then raise exception 'Task not found';end if;

  if coalesce(p_status,'open') not in('done','cancelled') and v_assigned is not null then
    if not exists(select 1 from public.notifications n where n.tenant_id=p_tenant_id and n.user_id=v_assigned and n.category='task' and n.entity_type='task' and n.entity_id=v_id and n.read_at is null and n.created_at>now()-interval '15 minutes') then
      insert into public.notifications(tenant_id,user_id,location_id,category,severity,title,message,entity_type,entity_id)
      values(p_tenant_id,v_assigned,p_location_id,'task',case p_priority when 'urgent' then 'critical' when 'high' then 'warning' else 'info' end,
        case when p_task_id is null then 'Task assigned' else 'Task updated' end||' • '||trim(p_title),
        coalesce(nullif(trim(coalesce(p_description,'')),''),'Task requires attention')||case when p_due_at is null then '' else ' • Due '||p_due_at::text end,'task',v_id);
    end if;
  end if;

  if p_task_id is not null and v_old_status is distinct from p_status and p_status in('done','cancelled') then
    insert into public.notifications(tenant_id,user_id,location_id,category,severity,title,message,entity_type,entity_id)
    values(p_tenant_id,auth.uid(),p_location_id,'task','success','Task '||replace(p_status,'_',' ')||' • '||trim(p_title),'Task status changed to '||p_status,'task',v_id);
  end if;
  return v_id;
end $$;
grant execute on function public.business_task_save_v495(uuid,uuid,uuid,text,text,text,text,uuid,timestamptz,timestamptz,text,uuid,uuid,jsonb) to authenticated;

create or replace function public.business_tasks_list_v495(p_tenant_id uuid,p_location_id uuid default null,p_status text default null)
returns table(
  id uuid,title text,description text,priority text,status text,assigned_to uuid,assigned_username text,
  due_at timestamptz,reminder_at timestamptz,location_id uuid,location_code text,entity_type text,entity_id uuid,
  source_notification_id uuid,metadata jsonb,created_at timestamptz,updated_at timestamptz
)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  select t.id,t.title,t.description,t.priority,t.status,t.assigned_to,coalesce(u.username,''),
    t.due_at,t.reminder_at,t.location_id,coalesce(l.location_code,''),t.entity_type,t.entity_id,
    t.source_notification_id,coalesce(t.metadata,'{}'::jsonb),t.created_at,t.updated_at
  from public.business_tasks t
  left join public.user_login_names u on u.user_id=t.assigned_to
  left join public.business_locations l on l.id=t.location_id
  where t.tenant_id=p_tenant_id
    and (p_location_id is null or t.location_id=p_location_id)
    and (p_status is null or p_status='' or t.status=p_status)
    and (t.location_id is null or private.erp_user_location_allowed(p_tenant_id,t.location_id,'view') or private.erp_user_is_owner(p_tenant_id))
    and (t.assigned_to is null or t.assigned_to=auth.uid() or private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'tasks.manage'))
  order by
    case when t.status in('done','cancelled') then 1 else 0 end,
    case when t.due_at is not null and t.due_at<now() and t.status not in('done','cancelled') then 0 else 1 end,
    case t.priority when 'urgent' then 1 when 'high' then 2 when 'normal' then 3 else 4 end,
    coalesce(t.due_at,'infinity'::timestamptz),t.created_at desc;
end $$;
grant execute on function public.business_tasks_list_v495(uuid,uuid,text) to authenticated;

create or replace function public.business_task_from_notification_v495(
  p_tenant_id uuid,p_notification_id uuid,p_assigned_to uuid default null,p_due_at timestamptz default null,p_priority text default null
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare n public.notifications%rowtype; v_existing uuid; v_due timestamptz; v_priority text;
begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'tasks.manage') then raise exception 'Task permission required';end if;
  select * into n from public.notifications where id=p_notification_id and tenant_id=p_tenant_id and (user_id is null or user_id=auth.uid());
  if n.id is null then raise exception 'Notification not found';end if;
  select id into v_existing from public.business_tasks where tenant_id=p_tenant_id and source_notification_id=p_notification_id and status not in('done','cancelled') order by created_at desc limit 1;
  if v_existing is not null then return v_existing;end if;
  v_due:=coalesce(p_due_at,now()+case when n.severity='critical' then interval '4 hours' when n.severity='warning' then interval '1 day' else interval '3 days' end);
  v_priority:=coalesce(nullif(p_priority,''),case when n.severity='critical' then 'urgent' when n.severity='warning' then 'high' else 'normal' end);
  return public.business_task_save_v495(
    p_tenant_id,null,n.location_id,n.title,n.message,v_priority,'open',coalesce(p_assigned_to,auth.uid()),v_due,
    greatest(now(),v_due-interval '4 hours'),n.entity_type,n.entity_id,n.id,jsonb_build_object('notification_category',n.category,'notification_severity',n.severity)
  );
end $$;
grant execute on function public.business_task_from_notification_v495(uuid,uuid,uuid,timestamptz,text) to authenticated;

create or replace function private.v495_refresh_notifications(p_tenant_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare r record;
begin
  -- Customer balances becoming due in the next three days.
  for r in
    select s.id,s.due_date,c.name,o.location_id,
      greatest(s.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0) balance
    from public.sales s join public.customers c on c.id=s.customer_id
    left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
    left join(select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.due_date between current_date and current_date+3
      and coalesce(s.status,'') not in('void','cancelled')
      and greatest(s.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)>0.005
      and (o.location_id is null or private.erp_user_is_owner(p_tenant_id) or private.erp_user_location_allowed(p_tenant_id,o.location_id,'view'))
    order by s.due_date limit 100
  loop
    if not exists(select 1 from public.notifications n where n.tenant_id=p_tenant_id and n.user_id=p_user_id and n.category='receivable' and n.entity_type='sale' and n.entity_id=r.id and n.title like 'Payment due soon%' and n.read_at is null and n.created_at>now()-interval '24 hours') then
      insert into public.notifications(tenant_id,user_id,location_id,category,severity,title,message,entity_type,entity_id)
      values(p_tenant_id,p_user_id,r.location_id,'receivable','info','Payment due soon • '||r.name,'Balance '||round(r.balance,2)||' • due '||r.due_date,'sale',r.id);
    end if;
  end loop;

  -- Supplier payable exposure, including Purchasing V2 invoices.
  for r in
    select * from public.supplier_payables_intelligence_v480(p_tenant_id,null,'',1000)
    where (days_1_30+days_31_60+days_61_90+days_90_plus)>0.005
    order by days_90_plus desc,total_outstanding desc limit 100
  loop
    if not exists(select 1 from public.notifications n where n.tenant_id=p_tenant_id and n.user_id=p_user_id and n.category='payable' and n.entity_type='supplier' and n.entity_id=r.supplier_id and n.read_at is null and n.created_at>now()-interval '24 hours') then
      insert into public.notifications(tenant_id,user_id,category,severity,title,message,entity_type,entity_id)
      values(p_tenant_id,p_user_id,'payable',case when r.days_90_plus>0 then 'critical' else 'warning' end,'Supplier payment overdue • '||r.supplier_name,
        'Outstanding '||round(r.total_outstanding,2)||case when r.oldest_due_date is null then '' else ' • oldest due '||r.oldest_due_date::text end,'supplier',r.supplier_id);
    end if;
  end loop;

  -- Pending approvals for users able to approve.
  if private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'approvals.approve') then
    for r in select id,module_key,action_key,entity_type,entity_id,amount,requested_at from public.approval_requests where tenant_id=p_tenant_id and status='pending' order by requested_at limit 100 loop
      if not exists(select 1 from public.notifications n where n.tenant_id=p_tenant_id and n.user_id=p_user_id and n.category='approval' and n.entity_type='approval_request' and n.entity_id=r.id and n.read_at is null and n.created_at>now()-interval '12 hours') then
        insert into public.notifications(tenant_id,user_id,category,severity,title,message,entity_type,entity_id)
        values(p_tenant_id,p_user_id,'approval','warning','Approval required • '||replace(r.module_key,'_',' '),replace(r.action_key,'_',' ')||coalesce(' • amount '||round(r.amount,2)::text,'')||' • requested '||r.requested_at,'approval_request',r.id);
      end if;
    end loop;
  end if;

  -- Explicit task reminders, including unassigned tasks for owners/managers.
  for r in
    select id,title,due_at,reminder_at,location_id,assigned_to,priority
    from public.business_tasks
    where tenant_id=p_tenant_id and status not in('done','cancelled')
      and (assigned_to=p_user_id or (assigned_to is null and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'tasks.manage'))))
      and coalesce(reminder_at,due_at) is not null and coalesce(reminder_at,due_at)<=now()+interval '15 minutes'
    order by coalesce(reminder_at,due_at) limit 100
  loop
    if not exists(select 1 from public.notifications n where n.tenant_id=p_tenant_id and n.user_id=p_user_id and n.category='task' and n.entity_type='task' and n.entity_id=r.id and n.read_at is null and n.created_at>now()-interval '6 hours') then
      insert into public.notifications(tenant_id,user_id,location_id,category,severity,title,message,entity_type,entity_id)
      values(p_tenant_id,p_user_id,r.location_id,'task',case when r.due_at is not null and r.due_at<now() then 'critical' when r.priority in('urgent','high') then 'warning' else 'info' end,
        case when r.due_at is not null and r.due_at<now() then 'Task overdue • ' else 'Task reminder • ' end||r.title,
        case when r.due_at is null then 'Task requires attention' else 'Due '||r.due_at end,'task',r.id);
    end if;
  end loop;
end $$;
revoke all on function private.v495_refresh_notifications(uuid,uuid) from public;

create or replace function public.notifications_list_v4(p_tenant_id uuid,p_limit integer default 50)
returns setof public.notifications language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  perform private.v4_refresh_notifications(p_tenant_id,auth.uid());
  perform private.loan_v490_refresh_notifications(p_tenant_id,auth.uid());
  perform private.v495_refresh_notifications(p_tenant_id,auth.uid());
  return query select * from public.notifications
    where tenant_id=p_tenant_id and (user_id is null or user_id=auth.uid())
    order by case severity when 'critical' then 0 when 'warning' then 1 else 2 end,(read_at is null) desc,created_at desc
    limit greatest(1,least(coalesce(p_limit,50),250));
end $$;
grant execute on function public.notifications_list_v4(uuid,integer) to authenticated;

create or replace function public.notifications_mark_all_read_v495(p_tenant_id uuid)
returns integer language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_count integer;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  update public.notifications set read_at=coalesce(read_at,now()) where tenant_id=p_tenant_id and (user_id is null or user_id=auth.uid()) and read_at is null;
  get diagnostics v_count=row_count; return v_count;
end $$;
grant execute on function public.notifications_mark_all_read_v495(uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(199,'4.9.5','Tasks & Notifications','Task reminders, notification-to-task conversion, customer/supplier due alerts, approvals and synchronized task status notifications.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.9.5 migration 199 applied' as status;
