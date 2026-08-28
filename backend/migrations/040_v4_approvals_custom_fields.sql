-- FLEXI ERP V4 configurable approvals and custom fields.
begin;
create table if not exists public.approval_rules(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,module_key text not null,action_key text not null,threshold_type text not null default 'always' check(threshold_type in('always','amount','percentage')),threshold_value numeric,required_permission text not null default 'approvals.approve',active boolean not null default true,settings jsonb not null default '{}'::jsonb,created_at timestamptz not null default now()
);
create table if not exists public.approval_requests(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,rule_id uuid references public.approval_rules(id) on delete set null,module_key text not null,action_key text not null,entity_type text,entity_id uuid,amount numeric,percentage numeric,status text not null default 'pending' check(status in('pending','approved','rejected','cancelled')),reason text,requested_by uuid references auth.users(id),requested_at timestamptz not null default now(),decided_by uuid references auth.users(id),decided_at timestamptz,decision_note text
);
create table if not exists public.custom_field_definitions(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,entity_type text not null,field_key text not null,label text not null,field_type text not null check(field_type in('text','number','date','dropdown','checkbox','multi_select')),required boolean not null default false,searchable boolean not null default false,invoice_visible boolean not null default false,options jsonb not null default '[]'::jsonb,active boolean not null default true,sort_order integer not null default 0,unique(tenant_id,entity_type,field_key)
);
create table if not exists public.custom_field_values(
  tenant_id uuid not null references public.tenants(id) on delete cascade,definition_id uuid not null references public.custom_field_definitions(id) on delete cascade,entity_id uuid not null,value jsonb,updated_by uuid references auth.users(id),updated_at timestamptz not null default now(),primary key(definition_id,entity_id)
);
alter table public.approval_rules enable row level security;alter table public.approval_requests enable row level security;alter table public.custom_field_definitions enable row level security;alter table public.custom_field_values enable row level security;revoke all on public.approval_rules,public.approval_requests,public.custom_field_definitions,public.custom_field_values from anon,authenticated;

create or replace function public.approval_request_decide_v4(p_tenant_id uuid,p_request_id uuid,p_approve boolean,p_note text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$ begin if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'approvals.approve') then raise exception 'Approval permission required';end if;update public.approval_requests set status=case when p_approve then 'approved' else 'rejected' end,decided_by=auth.uid(),decided_at=now(),decision_note=nullif(trim(coalesce(p_note,'')),'') where id=p_request_id and tenant_id=p_tenant_id and status='pending';if not found then raise exception 'Pending approval not found';end if;end $$;
grant execute on function public.approval_request_decide_v4(uuid,uuid,boolean,text) to authenticated;


create or replace function public.approval_requests_list_v4(p_tenant_id uuid,p_status text default 'pending')
returns table(id uuid,module_key text,action_key text,entity_type text,entity_id uuid,amount numeric,percentage numeric,status text,reason text,requested_by uuid,requested_username text,requested_at timestamptz,decided_at timestamptz,decision_note text)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select r.id,r.module_key,r.action_key,r.entity_type,r.entity_id,r.amount,r.percentage,r.status,r.reason,r.requested_by,coalesce(u.username,''),r.requested_at,r.decided_at,r.decision_note
  from public.approval_requests r left join public.user_login_names u on u.user_id=r.requested_by
  where r.tenant_id=p_tenant_id and (p_status is null or p_status='' or r.status=p_status)
  order by case when r.status='pending' then 0 else 1 end,r.requested_at desc;
end $$;
grant execute on function public.approval_requests_list_v4(uuid,text) to authenticated;

create or replace function public.approval_rule_save_v4(p_tenant_id uuid,p_rule_id uuid,p_module_key text,p_action_key text,p_threshold_type text,p_threshold_value numeric,p_required_permission text,p_active boolean)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid; begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'settings.manage') then raise exception 'Settings permission required';end if;
  if p_rule_id is null then
    insert into public.approval_rules(tenant_id,module_key,action_key,threshold_type,threshold_value,required_permission,active)
    values(p_tenant_id,trim(p_module_key),trim(p_action_key),p_threshold_type,p_threshold_value,coalesce(nullif(trim(p_required_permission),''),'approvals.approve'),coalesce(p_active,true)) returning id into v_id;
  else
    update public.approval_rules set module_key=trim(p_module_key),action_key=trim(p_action_key),threshold_type=p_threshold_type,threshold_value=p_threshold_value,required_permission=coalesce(nullif(trim(p_required_permission),''),'approvals.approve'),active=coalesce(p_active,true)
    where id=p_rule_id and tenant_id=p_tenant_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'Approval rule not found';end if;
  return v_id;
end $$;
grant execute on function public.approval_rule_save_v4(uuid,uuid,text,text,text,numeric,text,boolean) to authenticated;

commit;
select 'Flexi ERP V4 approvals/custom fields foundation ready' as status;
