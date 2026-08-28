create or replace function public.dashboard_get_summary(p_tenant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_today_sales numeric:=0; v_month_sales numeric:=0; v_month_purchases numeric:=0; v_month_expenses numeric:=0;
  v_month_gp numeric:=0; v_receivables numeric:=0; v_payables numeric:=0; v_low int:=0; v_products int:=0; v_customers int:=0; v_suppliers int:=0;
  v_start date:=date_trunc('month',current_date)::date;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;

  select coalesce(sum(grand_total),0) into v_today_sales from public.sales where tenant_id=p_tenant_id and sale_date=current_date and coalesce(status,'')<>'cancelled';
  select coalesce(sum(grand_total),0),coalesce(sum(gross_profit),0) into v_month_sales,v_month_gp from public.sales where tenant_id=p_tenant_id and sale_date between v_start and current_date and coalesce(status,'')<>'cancelled';
  select coalesce(sum(grand_total),0) into v_month_purchases from public.purchases where tenant_id=p_tenant_id and purchase_date between v_start and current_date and coalesce(status,'')<>'cancelled';
  if to_regclass('public.expenses') is not null then select coalesce(sum(total_amount),0) into v_month_expenses from public.expenses where tenant_id=p_tenant_id and expense_date between v_start and current_date and status='posted'; end if;

  select coalesce(sum(greatest(s.grand_total-coalesce(p.paid,0),0)),0) into v_receivables
  from public.sales s left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id) p on p.sale_id=s.id
  where s.tenant_id=p_tenant_id and coalesce(s.status,'')<>'cancelled';
  select coalesce(sum(greatest(pu.grand_total-coalesce(py.paid,0),0)),0) into v_payables
  from public.purchases pu left join (select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id=pu.id
  where pu.tenant_id=p_tenant_id and coalesce(pu.status,'')<>'cancelled';

  select count(*) into v_products from public.products where tenant_id=p_tenant_id and coalesce(status,'active')='active';
  select count(*) into v_customers from public.customers where tenant_id=p_tenant_id and coalesce(status,'active')='active';
  select count(*) into v_suppliers from public.suppliers where tenant_id=p_tenant_id and coalesce(status,'active')='active';
  select count(*) into v_low from public.stock_balances sb join public.product_variants pv on pv.id=sb.variant_id
    where sb.tenant_id=p_tenant_id and sb.quantity <= coalesce(pv.reorder_level,0) and coalesce(pv.reorder_level,0)>0;

  return jsonb_build_object(
    'today_sales',v_today_sales,'month_sales',v_month_sales,'month_purchases',v_month_purchases,
    'month_expenses',v_month_expenses,'month_gross_profit',v_month_gp,'month_net_profit',v_month_gp-v_month_expenses,
    'receivables',v_receivables,'payables',v_payables,'low_stock_count',v_low,'product_count',v_products,
    'customer_count',v_customers,'supplier_count',v_suppliers
  );
end $$;

create or replace function public.reports_get_summary(p_tenant_id uuid,p_from_date date,p_to_date date)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_sales numeric:=0;v_sales_tax numeric:=0;v_purchases numeric:=0;v_purchase_tax numeric:=0;v_expenses numeric:=0;v_gp numeric:=0;
  v_recv numeric:=0;v_pay numeric:=0;v_stock numeric:=0;v_sc int:=0;v_pc int:=0;v_ec int:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if p_from_date is null or p_to_date is null or p_from_date>p_to_date then raise exception 'Invalid date range'; end if;

  select coalesce(sum(grand_total),0),coalesce(sum(tax_total),0),coalesce(sum(gross_profit),0),count(*) into v_sales,v_sales_tax,v_gp,v_sc
  from public.sales where tenant_id=p_tenant_id and sale_date between p_from_date and p_to_date and coalesce(status,'')<>'cancelled';
  select coalesce(sum(grand_total),0),coalesce(sum(tax_total),0),count(*) into v_purchases,v_purchase_tax,v_pc
  from public.purchases where tenant_id=p_tenant_id and purchase_date between p_from_date and p_to_date and coalesce(status,'')<>'cancelled';
  if to_regclass('public.expenses') is not null then select coalesce(sum(total_amount),0),count(*) into v_expenses,v_ec from public.expenses where tenant_id=p_tenant_id and expense_date between p_from_date and p_to_date and status='posted'; end if;

  select coalesce(sum(greatest(s.grand_total-coalesce(p.paid,0),0)),0) into v_recv from public.sales s left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id)p on p.sale_id=s.id where s.tenant_id=p_tenant_id and coalesce(s.status,'')<>'cancelled';
  select coalesce(sum(greatest(pu.grand_total-coalesce(py.paid,0),0)),0) into v_pay from public.purchases pu left join (select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id)py on py.purchase_id=pu.id where pu.tenant_id=p_tenant_id and coalesce(pu.status,'')<>'cancelled';
  select coalesce(sum(sb.quantity*pv.cost_price),0) into v_stock from public.stock_balances sb join public.product_variants pv on pv.id=sb.variant_id where sb.tenant_id=p_tenant_id;

  return jsonb_build_object('from_date',p_from_date,'to_date',p_to_date,'sales',v_sales,'sales_tax',v_sales_tax,'purchases',v_purchases,'purchase_tax',v_purchase_tax,'expenses',v_expenses,'gross_profit',v_gp,'net_profit',v_gp-v_expenses,'receivables',v_recv,'payables',v_pay,'stock_value',v_stock,'sale_count',v_sc,'purchase_count',v_pc,'expense_count',v_ec);
end $$;

create or replace function public.accounting_get_summary(p_tenant_id uuid,p_from_date date,p_to_date date)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare v_revenue numeric:=0;v_cogs numeric:=0;v_gp numeric:=0;v_exp numeric:=0;v_recv numeric:=0;v_pay numeric:=0;v_stock numeric:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  select coalesce(sum(taxable_total),0),coalesce(sum(cost_total),0),coalesce(sum(gross_profit),0) into v_revenue,v_cogs,v_gp from public.sales where tenant_id=p_tenant_id and sale_date between p_from_date and p_to_date and coalesce(status,'')<>'cancelled';
  if to_regclass('public.expenses') is not null then select coalesce(sum(total_amount),0) into v_exp from public.expenses where tenant_id=p_tenant_id and expense_date between p_from_date and p_to_date and status='posted'; end if;
  select coalesce(sum(greatest(s.grand_total-coalesce(p.paid,0),0)),0) into v_recv from public.sales s left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id)p on p.sale_id=s.id where s.tenant_id=p_tenant_id and coalesce(s.status,'')<>'cancelled';
  select coalesce(sum(greatest(pu.grand_total-coalesce(py.paid,0),0)),0) into v_pay from public.purchases pu left join (select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id)py on py.purchase_id=pu.id where pu.tenant_id=p_tenant_id and coalesce(pu.status,'')<>'cancelled';
  select coalesce(sum(sb.quantity*pv.cost_price),0) into v_stock from public.stock_balances sb join public.product_variants pv on pv.id=sb.variant_id where sb.tenant_id=p_tenant_id;
  return jsonb_build_object('revenue',v_revenue,'cost_of_goods_sold',v_cogs,'gross_profit',v_gp,'operating_expenses',v_exp,'net_operating_profit',v_gp-v_exp,'receivables',v_recv,'payables',v_pay,'inventory_value',v_stock);
end $$;

create or replace function public.accounting_list_ledger(p_tenant_id uuid,p_from_date date,p_to_date date)
returns table(entry_date date,entry_type text,reference text,party text,description text,debit numeric,credit numeric)
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  return query
  select x.entry_date,x.entry_type,x.reference,x.party,x.description,x.debit,x.credit
  from (
    select s.sale_date entry_date,'sale'::text entry_type,s.sale_number reference,c.name party,'Sales invoice'::text description,s.grand_total::numeric debit,0::numeric credit
    from public.sales s join public.customers c on c.id=s.customer_id where s.tenant_id=p_tenant_id and s.sale_date between p_from_date and p_to_date and coalesce(s.status,'')<>'cancelled'
    union all
    select p.purchase_date,'purchase',p.purchase_number,sp.name,'Purchase bill',p.grand_total::numeric,0::numeric
    from public.purchases p join public.suppliers sp on sp.id=p.supplier_id where p.tenant_id=p_tenant_id and p.purchase_date between p_from_date and p_to_date and coalesce(p.status,'')<>'cancelled'
    union all
    select e.expense_date,'expense',e.expense_number,coalesce(e.payee,''),e.description,e.total_amount::numeric,0::numeric
    from public.expenses e where e.tenant_id=p_tenant_id and e.expense_date between p_from_date and p_to_date and e.status='posted'
    union all
    select coalesce(sp.paid_at,sp.created_at)::date,'customer_payment',s.sale_number,c.name,'Customer receipt',0::numeric,sp.amount::numeric
    from public.sale_payments sp join public.sales s on s.id=sp.sale_id join public.customers c on c.id=s.customer_id
    where s.tenant_id=p_tenant_id and coalesce(sp.paid_at,sp.created_at)::date between p_from_date and p_to_date
    union all
    select coalesce(pp.paid_at,pp.created_at)::date,'supplier_payment',p.purchase_number,s.name,'Supplier payment',0::numeric,pp.amount::numeric
    from public.purchase_payments pp join public.purchases p on p.id=pp.purchase_id join public.suppliers s on s.id=p.supplier_id
    where p.tenant_id=p_tenant_id and coalesce(pp.paid_at,pp.created_at)::date between p_from_date and p_to_date
  ) x order by x.entry_date desc,x.reference desc;
end $$;

grant execute on function public.dashboard_get_summary(uuid) to authenticated;
grant execute on function public.reports_get_summary(uuid,date,date) to authenticated;
grant execute on function public.accounting_get_summary(uuid,date,date) to authenticated;
grant execute on function public.accounting_list_ledger(uuid,date,date) to authenticated;
