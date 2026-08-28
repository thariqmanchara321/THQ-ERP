-- Flexi ERP V3: application logs, business audit, safe edits.
create table if not exists public.app_error_logs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  app_key text not null check(app_key in ('client','admin','pos','backend')),
  severity text not null default 'error' check(severity in ('info','warning','error','fatal','issue')),
  message text not null,
  stack_trace text,
  context jsonb not null default '{}'::jsonb,
  app_version text,
  created_at timestamptz not null default now()
);
create index if not exists idx_app_error_logs_tenant_created on public.app_error_logs(tenant_id,created_at desc);
create index if not exists idx_app_error_logs_app_created on public.app_error_logs(app_key,created_at desc);
alter table public.app_error_logs enable row level security;
revoke all on public.app_error_logs from anon, authenticated;

create table if not exists public.business_audit_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  entity_reference text,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_business_audit_tenant_created on public.business_audit_log(tenant_id,created_at desc);
alter table public.business_audit_log enable row level security;
revoke all on public.business_audit_log from anon, authenticated;

create or replace function private.business_audit_write(p_tenant_id uuid,p_action text,p_entity_type text,p_entity_id uuid,p_reference text,p_before jsonb,p_after jsonb)
returns void language sql security definer set search_path=public,private,pg_temp
as $$ insert into public.business_audit_log(tenant_id,user_id,action,entity_type,entity_id,entity_reference,before_data,after_data) values(p_tenant_id,auth.uid(),p_action,p_entity_type,p_entity_id,p_reference,p_before,p_after) $$;
revoke all on function private.business_audit_write(uuid,text,text,uuid,text,jsonb,jsonb) from public;

create or replace function public.app_error_log_write(p_app_key text,p_message text,p_stack_trace text default null,p_context jsonb default '{}'::jsonb,p_tenant_id uuid default null,p_severity text default 'error',p_app_version text default null)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_tenant_id is not null and not private.erp_user_has_tenant_access(p_tenant_id) and not private.platform_v2_is_admin() then raise exception 'Access denied'; end if;
  insert into public.app_error_logs(tenant_id,user_id,app_key,severity,message,stack_trace,context,app_version)
  values(p_tenant_id,auth.uid(),p_app_key,coalesce(nullif(p_severity,''),'error'),left(coalesce(p_message,'Unknown error'),4000),left(p_stack_trace,16000),coalesce(p_context,'{}'::jsonb),p_app_version)
  returning id into v_id;
  return v_id;
end $$;
grant execute on function public.app_error_log_write(text,text,text,jsonb,uuid,text,text) to authenticated;

create or replace function public.app_error_logs_list(p_tenant_id uuid,p_limit integer default 200)
returns setof public.app_error_logs language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not private.erp_has_permission(p_tenant_id,'logs.view') then raise exception 'Permission denied'; end if;
  return query select * from public.app_error_logs where tenant_id=p_tenant_id order by created_at desc limit greatest(1,least(coalesce(p_limit,200),1000));
end $$;
grant execute on function public.app_error_logs_list(uuid,integer) to authenticated;

create or replace function public.platform_app_error_logs_list(p_limit integer default 300)
returns setof public.app_error_logs language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required'; end if;
  return query select * from public.app_error_logs order by created_at desc limit greatest(1,least(coalesce(p_limit,300),2000));
end $$;
grant execute on function public.platform_app_error_logs_list(integer) to authenticated;

create or replace function public.expenses_update(
  p_tenant_id uuid,p_expense_id uuid,p_category_id uuid,p_expense_date date,p_payee text,p_description text,p_amount numeric,p_tax_amount numeric,p_payment_method text,p_reference_number text,p_notes text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_before jsonb; v_after jsonb; v_number text;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not private.erp_has_permission(p_tenant_id,'expenses.edit') and not private.erp_has_permission(p_tenant_id,'expenses.manage') then raise exception 'Permission denied'; end if;
  select to_jsonb(e),e.expense_number into v_before,v_number from public.expenses e where e.id=p_expense_id and e.tenant_id=p_tenant_id for update;
  if v_before is null then raise exception 'Expense not found'; end if;
  if coalesce((v_before->>'status'),'') <> 'posted' then raise exception 'Only posted expenses can be edited'; end if;
  if not exists(select 1 from public.expense_categories where id=p_category_id and tenant_id=p_tenant_id and active) then raise exception 'Invalid expense category'; end if;
  if coalesce(p_amount,0)<=0 or coalesce(p_tax_amount,0)<0 then raise exception 'Invalid amount'; end if;
  update public.expenses set category_id=p_category_id,expense_date=p_expense_date,payee=nullif(trim(p_payee),''),description=trim(p_description),amount=p_amount,tax_amount=coalesce(p_tax_amount,0),payment_method=coalesce(nullif(trim(p_payment_method),''),'cash'),reference_number=nullif(trim(p_reference_number),''),notes=nullif(trim(p_notes),''),updated_at=now()
  where id=p_expense_id and tenant_id=p_tenant_id;
  select to_jsonb(e) into v_after from public.expenses e where e.id=p_expense_id;
  perform private.business_audit_write(p_tenant_id,'update','expense',p_expense_id,v_number,v_before,v_after);
  return jsonb_build_object('expense_id',p_expense_id,'expense_number',v_number);
end $$;
grant execute on function public.expenses_update(uuid,uuid,uuid,date,text,text,numeric,numeric,text,text,text) to authenticated;

-- Safe posted-sale editing: customer/due-date/notes only. Monetary lines are never silently rewritten.
create or replace function public.sales_update_metadata(p_tenant_id uuid,p_sale_id uuid,p_customer_id uuid,p_due_date date,p_notes text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_before jsonb; v_after jsonb; v_number text;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not private.erp_has_permission(p_tenant_id,'sales.edit') and not private.erp_has_permission(p_tenant_id,'sales.manage') then raise exception 'Permission denied'; end if;
  select to_jsonb(s),s.sale_number into v_before,v_number from public.sales s where s.id=p_sale_id and s.tenant_id=p_tenant_id for update;
  if v_before is null then raise exception 'Sale not found'; end if;
  if coalesce(v_before->>'status','') in ('cancelled','void') then raise exception 'Voided sale cannot be edited'; end if;
  if not exists(select 1 from public.customers c where c.id=p_customer_id and c.tenant_id=p_tenant_id and coalesce(c.status,'active')='active') then raise exception 'Invalid customer'; end if;
  update public.sales set customer_id=p_customer_id,due_date=p_due_date,notes=nullif(trim(p_notes),'') where id=p_sale_id and tenant_id=p_tenant_id;
  select to_jsonb(s) into v_after from public.sales s where s.id=p_sale_id;
  perform private.business_audit_write(p_tenant_id,'update_metadata','sale',p_sale_id,v_number,v_before,v_after);
  return jsonb_build_object('sale_id',p_sale_id,'sale_number',v_number);
end $$;
grant execute on function public.sales_update_metadata(uuid,uuid,uuid,date,text) to authenticated;
