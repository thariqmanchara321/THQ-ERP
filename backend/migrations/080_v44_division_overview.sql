-- FLEXI ERP V4.4
-- Division-level Client aggregation foundation for MAIN business owners.
begin;

insert into public.modules(key,name,description,category,is_core,sort_order,is_active,is_beta,requires_configuration)
values('division_overview','Division Overview','Merged business summary for a Business Division','Management',false,12,true,false,false)
on conflict(key) do update set name=excluded.name,description=excluded.description,category=excluded.category,is_active=true,sort_order=excluded.sort_order;

insert into public.tenant_modules(tenant_id,module_key,enabled)
select d.main_tenant_id,'division_overview',true from public.business_divisions d where d.active and d.main_tenant_id is not null
on conflict(tenant_id,module_key) do update set enabled=true;

do $$
begin
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='permissions' and column_name='description') then
    insert into public.permissions(key,name,module_key,description)
    values('division.view','View Division Overview','division_overview','View merged figures for businesses under the same division')
    on conflict(key) do update set name=excluded.name,module_key=excluded.module_key,description=excluded.description;
  else
    insert into public.permissions(key,name,module_key)
    values('division.view','View Division Overview','division_overview')
    on conflict(key) do update set name=excluded.name,module_key=excluded.module_key;
  end if;
end $$;

-- The Client runtime also filters modules by plan entitlement. Make the
-- division summary available to existing plans; the RPC still requires the
-- dedicated owner/division permission and an actual division membership.
insert into public.subscription_plan_modules(plan_id,module_key)
select id,'division_overview' from public.subscription_plans
on conflict do nothing;

insert into public.role_permissions(role_id,permission_key)
select r.id,'division.view' from public.roles r where r.key='owner'
on conflict do nothing;


-- Keep the division module available when a new division is created after V4.4.
create or replace function private.v44_enable_division_overview_for_main()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if new.active and new.main_tenant_id is not null then
    insert into public.tenant_modules(tenant_id,module_key,enabled)
    values(new.main_tenant_id,'division_overview',true)
    on conflict(tenant_id,module_key) do update set enabled=true;
  end if;
  return new;
end $$;

drop trigger if exists trg_v44_division_overview_module on public.business_divisions;
create trigger trg_v44_division_overview_module
after insert or update of main_tenant_id,active on public.business_divisions
for each row execute function private.v44_enable_division_overview_for_main();

create or replace function public.division_overview_v44(p_main_tenant_id uuid,p_from date,p_to date)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare v_div uuid;v_name text;v_rows jsonb;v_sales numeric:=0;v_purchases numeric:=0;v_expenses numeric:=0;v_receivables numeric:=0;v_payables numeric:=0;
begin
  if not private.erp_user_has_tenant_access(p_main_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_is_owner(p_main_tenant_id) and not private.erp_has_permission(p_main_tenant_id,'division.view') then raise exception 'Division permission required';end if;
  select d.id,d.name into v_div,v_name from public.business_divisions d where d.main_tenant_id=p_main_tenant_id and d.active;
  if v_div is null then return jsonb_build_object('has_division',false,'businesses','[]'::jsonb);end if;

  with members as (
    select dm.tenant_id,dm.member_type,t.name,t.slug
    from public.business_division_members dm join public.tenants t on t.id=dm.tenant_id
    where dm.division_id=v_div
  ), totals as (
    select m.*,
      coalesce((select sum(s.grand_total) from public.sales s where s.tenant_id=m.tenant_id and s.sale_date between p_from and p_to and coalesce(s.status,'') not in('void','cancelled')),0)::numeric sales,
      coalesce((select sum(p.grand_total) from public.purchases p where p.tenant_id=m.tenant_id and p.purchase_date between p_from and p_to and coalesce(p.status,'') not in('void','cancelled')),0)::numeric purchases,
      coalesce((select sum(e.total_amount) from public.expenses e where e.tenant_id=m.tenant_id and e.expense_date between p_from and p_to and coalesce(e.status,'') not in('void','cancelled')),0)::numeric expenses,
      coalesce((select sum(greatest(s.grand_total-coalesce((select sum(sp.amount) from public.sale_payments sp where sp.sale_id=s.id),0),0)) from public.sales s where s.tenant_id=m.tenant_id and coalesce(s.status,'') not in('void','cancelled')),0)::numeric receivables,
      coalesce((select sum(greatest(p.grand_total-coalesce((select sum(pp.amount) from public.purchase_payments pp where pp.purchase_id=p.id),0),0)) from public.purchases p where p.tenant_id=m.tenant_id and coalesce(p.status,'') not in('void','cancelled')),0)::numeric payables
    from members m
  )
  select coalesce(jsonb_agg(jsonb_build_object('tenant_id',tenant_id,'name',name,'slug',slug,'member_type',member_type,'sales',sales,'purchases',purchases,'expenses',expenses,'receivables',receivables,'payables',payables) order by case when member_type='main' then 0 else 1 end,name),'[]'::jsonb),
    coalesce(sum(sales),0),coalesce(sum(purchases),0),coalesce(sum(expenses),0),coalesce(sum(receivables),0),coalesce(sum(payables),0)
  into v_rows,v_sales,v_purchases,v_expenses,v_receivables,v_payables from totals;

  return jsonb_build_object('has_division',true,'division_id',v_div,'division_name',v_name,'from',p_from,'to',p_to,
    'sales',v_sales,'purchases',v_purchases,'expenses',v_expenses,'receivables',v_receivables,'payables',v_payables,'businesses',v_rows);
end $$;
grant execute on function public.division_overview_v44(uuid,date,date) to authenticated;

commit;
select 'Flexi ERP V4.4 division overview ready' as status;
