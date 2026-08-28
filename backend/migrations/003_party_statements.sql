create or replace function public.customers_get_statement(p_tenant_id uuid, p_customer_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare v_name text; v_rows jsonb; v_debit numeric; v_credit numeric;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  select c.name into v_name from public.customers c where c.id=p_customer_id and c.tenant_id=p_tenant_id;
  if v_name is null then raise exception 'Customer not found'; end if;

  with raw as (
    select s.sale_date::timestamp as ts, s.sale_date as entry_date, 'sale'::text as entry_type,
           s.sale_number as reference, 'Sales invoice'::text as description,
           s.grand_total::numeric as debit, 0::numeric as credit
    from public.sales s
    where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') <> 'cancelled'
    union all
    select coalesce(sp.paid_at,sp.created_at) as ts, coalesce(sp.paid_at,sp.created_at)::date as entry_date,
           'payment'::text, s.sale_number, 'Customer payment'::text,
           0::numeric, sp.amount::numeric
    from public.sale_payments sp join public.sales s on s.id=sp.sale_id
    where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id
  ), running as (
    select *, sum(debit-credit) over(order by ts, entry_type, reference rows unbounded preceding) as balance
    from raw
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entry_date',entry_date,'entry_type',entry_type,'reference',reference,'description',description,
      'debit',debit,'credit',credit,'balance',balance
    ) order by ts,entry_type,reference),'[]'::jsonb),
    coalesce(sum(debit),0),coalesce(sum(credit),0)
  into v_rows,v_debit,v_credit from running;

  return jsonb_build_object(
    'party_id',p_customer_id,'party_name',v_name,'opening_balance',0,
    'total_debit',v_debit,'total_credit',v_credit,'closing_balance',v_debit-v_credit,'rows',v_rows
  );
end $$;

create or replace function public.suppliers_get_statement(p_tenant_id uuid, p_supplier_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare v_name text; v_rows jsonb; v_debit numeric; v_credit numeric;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  select s.name into v_name from public.suppliers s where s.id=p_supplier_id and s.tenant_id=p_tenant_id;
  if v_name is null then raise exception 'Supplier not found'; end if;

  with raw as (
    select p.purchase_date::timestamp as ts, p.purchase_date as entry_date, 'purchase'::text as entry_type,
           p.purchase_number as reference, 'Purchase bill'::text as description,
           p.grand_total::numeric as debit, 0::numeric as credit
    from public.purchases p
    where p.tenant_id=p_tenant_id and p.supplier_id=p_supplier_id and coalesce(p.status,'') <> 'cancelled'
    union all
    select coalesce(pp.paid_at,pp.created_at) as ts, coalesce(pp.paid_at,pp.created_at)::date as entry_date,
           'payment'::text, p.purchase_number, 'Supplier payment'::text,
           0::numeric, pp.amount::numeric
    from public.purchase_payments pp join public.purchases p on p.id=pp.purchase_id
    where p.tenant_id=p_tenant_id and p.supplier_id=p_supplier_id
  ), running as (
    select *, sum(debit-credit) over(order by ts, entry_type, reference rows unbounded preceding) as balance
    from raw
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entry_date',entry_date,'entry_type',entry_type,'reference',reference,'description',description,
      'debit',debit,'credit',credit,'balance',balance
    ) order by ts,entry_type,reference),'[]'::jsonb),
    coalesce(sum(debit),0),coalesce(sum(credit),0)
  into v_rows,v_debit,v_credit from running;

  return jsonb_build_object(
    'party_id',p_supplier_id,'party_name',v_name,'opening_balance',0,
    'total_debit',v_debit,'total_credit',v_credit,'closing_balance',v_debit-v_credit,'rows',v_rows
  );
end $$;

grant execute on function public.customers_get_statement(uuid,uuid) to authenticated;
grant execute on function public.suppliers_get_statement(uuid,uuid) to authenticated;
