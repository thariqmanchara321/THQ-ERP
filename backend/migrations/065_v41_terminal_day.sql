-- FLEXI ERP V4.1
-- Per-terminal daily summary and day-close support for POS.
begin;

insert into public.modules(key,name,description,category,is_core,sort_order,is_active,is_beta,requires_configuration)
values('terminal_day','Terminal Daily','Daily terminal invoices, payment totals, cashier shift and day close','POS',false,37,true,false,false)
on conflict(key) do update set name=excluded.name,description=excluded.description,category=excluded.category,is_active=true,sort_order=excluded.sort_order;

insert into public.module_dependencies(module_key,depends_on_module_key)
values('terminal_day','pos') on conflict do nothing;

-- Existing POS terminals with cashier shifts receive Terminal Daily by default.
update public.business_devices d
set allowed_modules = case
  when not ('terminal_day'=any(d.allowed_modules)) then array_append(d.allowed_modules,'terminal_day')
  else d.allowed_modules end,
  updated_at=now()
where d.app_type='pos' and d.status='active' and ('cashier_shifts'=any(d.allowed_modules) or 'sales'=any(d.allowed_modules));

insert into public.tenant_modules(tenant_id,module_key,enabled)
select tm.tenant_id,'terminal_day',true from public.tenant_modules tm where tm.module_key='pos' and tm.enabled
on conflict(tenant_id,module_key) do nothing;

-- Keep future POS-capable templates/plans consistent too.
insert into public.business_template_modules(template_id,module_key)
select btm.template_id,'terminal_day'
from public.business_template_modules btm
where btm.module_key='pos'
on conflict(template_id,module_key) do nothing;

insert into public.subscription_plan_modules(plan_id,module_key)
select spm.plan_id,'terminal_day'
from public.subscription_plan_modules spm
where spm.module_key='pos'
on conflict(plan_id,module_key) do nothing;

create or replace function public.pos_terminal_day_v41(
  p_tenant_id uuid,p_device_id uuid,p_day date default current_date
) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_location uuid;v_invoice_count bigint:=0;v_gross numeric:=0;v_cash numeric:=0;v_upi numeric:=0;v_card numeric:=0;v_bank numeric:=0;v_other numeric:=0;v_invoices jsonb:='[]'::jsonb;v_shift jsonb:='{}'::jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select d.location_id into v_location from public.business_devices d
  where d.id=p_device_id and d.tenant_id=p_tenant_id and d.status='active';
  if v_location is null then raise exception 'Active terminal not found';end if;
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_user_location_allowed(p_tenant_id,v_location,'view') then
    raise exception 'Terminal access denied';
  end if;

  select count(*),coalesce(sum(s.grand_total),0)
  into v_invoice_count,v_gross
  from public.sales s
  join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id and o.device_id=p_device_id
  where s.tenant_id=p_tenant_id and s.sale_date=p_day and coalesce(s.status,'') not in('cancelled','void');

  select
    coalesce(sum(sp.amount) filter(where lower(sp.payment_method)='cash'),0),
    coalesce(sum(sp.amount) filter(where lower(sp.payment_method)='upi'),0),
    coalesce(sum(sp.amount) filter(where lower(sp.payment_method)='card'),0),
    coalesce(sum(sp.amount) filter(where lower(sp.payment_method)='bank'),0),
    coalesce(sum(sp.amount) filter(where lower(sp.payment_method) not in('cash','upi','card','bank')),0)
  into v_cash,v_upi,v_card,v_bank,v_other
  from public.sale_payments sp
  join public.sales s on s.id=sp.sale_id and s.tenant_id=p_tenant_id
  join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id and o.device_id=p_device_id
  where s.sale_date=p_day and coalesce(s.status,'') not in('cancelled','void');

  select coalesce(jsonb_agg(jsonb_build_object(
      'sale_id',s2.id,'sale_number',s2.sale_number,
      'invoice_number',coalesce(dn2.terminal_number,ln2.local_number,s2.sale_number),
      'created_at',s2.created_at,'customer_name',c2.name,'grand_total',s2.grand_total,
      'paid_amount',coalesce((select sum(pp2.amount) from public.sale_payments pp2 where pp2.sale_id=s2.id),0),
      'status',s2.status
    ) order by s2.created_at desc),'[]'::jsonb)
  into v_invoices
  from public.sales s2
  join public.document_origins o2 on o2.tenant_id=p_tenant_id and o2.entity_type='sale' and o2.entity_id=s2.id and o2.device_id=p_device_id
  join public.customers c2 on c2.id=s2.customer_id
  left join public.location_document_numbers ln2 on ln2.tenant_id=p_tenant_id and ln2.entity_type='sale' and ln2.entity_id=s2.id
  left join public.device_document_numbers dn2 on dn2.tenant_id=p_tenant_id and dn2.entity_type='sale' and dn2.entity_id=s2.id
  where s2.tenant_id=p_tenant_id and s2.sale_date=p_day;

  select coalesce((
      select to_jsonb(cs) || jsonb_build_object(
        'expected_now',coalesce((select sum(cm.amount) from public.cash_drawer_movements cm where cm.shift_id=cs.id),0)
      )
      from public.cashier_shifts cs
      where cs.tenant_id=p_tenant_id and cs.device_id=p_device_id
        and cs.opened_at::date<=p_day and coalesce(cs.closed_at::date,p_day)>=p_day
      order by cs.opened_at desc limit 1
    ),'{}'::jsonb) into v_shift;

  return jsonb_build_object(
    'day',p_day,'device_id',p_device_id,'location_id',v_location,
    'invoice_count',v_invoice_count,'gross_sales',v_gross,
    'cash',v_cash,'upi',v_upi,'card',v_card,'bank',v_bank,'other_payments',v_other,
    'invoices',v_invoices,'shift',v_shift
  );
end $$;
grant execute on function public.pos_terminal_day_v41(uuid,uuid,date) to authenticated;

commit;
select 'Flexi ERP V4.1 terminal daily ready' as status;
