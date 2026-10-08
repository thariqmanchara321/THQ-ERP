begin;
CREATE OR REPLACE FUNCTION private.reports_inventory_rows_v631(p_tenant_id uuid, p_location_id uuid DEFAULT NULL::uuid, p_days integer DEFAULT 30, p_query text DEFAULT ''::text, p_limit integer DEFAULT 1000)
 RETURNS TABLE(location_id uuid, location_code text, location_name text, variant_id uuid, product_name text, sku text, quantity numeric, available numeric, reorder_level numeric, max_stock numeric, average_cost numeric, stock_value numeric, net_sold_qty numeric, avg_daily_sales numeric, days_cover numeric, suggested_reorder numeric, last_sale_date date, last_purchase_date date, status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_days integer:=greatest(1,least(coalesce(p_days,30),365));
  v_from date:=current_date-(greatest(1,least(coalesce(p_days,30),365))-1);
  q text:='%'||lower(trim(coalesce(p_query,'')))||'%';
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if p_location_id is not null and not private.reports_scope_v631(p_tenant_id,p_location_id,p_location_id,'view') then raise exception 'Location access denied';end if;

  return query
  with sold as (
    select o.location_id,si.variant_id,
      sum(greatest(si.quantity-coalesce((
        select sum(ri.quantity)
        from public.sales_return_items ri
        join public.sales_returns r on r.id=ri.sales_return_id
        where ri.sale_item_id=si.id and r.refund_status<>'waived' and r.return_date<=current_date
      ),0),0))::numeric qty
    from public.sale_items si join public.sales s on s.id=si.sale_id
    join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.sale_date between v_from and current_date
      and coalesce(s.status,'') not in('draft','void','cancelled')
      and (p_location_id is null or o.location_id=p_location_id)
      and private.reports_scope_v631(p_tenant_id,o.location_id,p_location_id,'view')
    group by o.location_id,si.variant_id
  ), last_sold as (
    select o.location_id,si.variant_id,max(s.sale_date) last_sale
    from public.sale_items si join public.sales s on s.id=si.sale_id
    join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('draft','void','cancelled')
      and (p_location_id is null or o.location_id=p_location_id)
      and private.reports_scope_v631(p_tenant_id,o.location_id,p_location_id,'view')
    group by o.location_id,si.variant_id
  ), purchased as (
    select o.location_id,pi.variant_id,max(p.purchase_date) last_purchase
    from public.purchase_items pi join public.purchases p on p.id=pi.purchase_id
    join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id
    where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('draft','void','cancelled')
      and (p_location_id is null or o.location_id=p_location_id)
      and private.reports_scope_v631(p_tenant_id,o.location_id,p_location_id,'view')
    group by o.location_id,pi.variant_id
  ), base as (
    select l.id location_id,l.location_code,l.name location_name,pv.id variant_id,p.name product_name,pv.sku,
      coalesce(b.quantity,0)::numeric quantity,
      (coalesce(b.quantity,0)-coalesce(b.reserved_quantity,0)-coalesce(b.damaged_quantity,0)-coalesce(b.quarantine_quantity,0))::numeric available,
      coalesce(s.reorder_level,pv.reorder_level,0)::numeric reorder_level,coalesce(s.max_stock,0)::numeric max_stock,
      coalesce(b.average_cost,pv.cost_price,0)::numeric average_cost,
      coalesce(so.qty,0)::numeric net_sold_qty,
      ls.last_sale,pu.last_purchase
    from (select tenant_id,location_id,variant_id from public.location_product_settings where tenant_id=p_tenant_id union select tenant_id,location_id,variant_id from public.location_stock_balances where tenant_id=p_tenant_id) slots left join public.location_product_settings s on s.tenant_id=slots.tenant_id and s.location_id=slots.location_id and s.variant_id=slots.variant_id
    join public.business_locations l on l.id=slots.location_id and l.tenant_id=slots.tenant_id
    join public.product_variants pv on pv.id=slots.variant_id and pv.tenant_id=slots.tenant_id
    join public.products p on p.id=pv.product_id and p.tenant_id=slots.tenant_id
    left join public.location_stock_balances b on b.tenant_id=slots.tenant_id and b.location_id=slots.location_id and b.variant_id=slots.variant_id
    left join sold so on so.location_id=slots.location_id and so.variant_id=slots.variant_id
    left join last_sold ls on ls.location_id=slots.location_id and ls.variant_id=slots.variant_id
    left join purchased pu on pu.location_id=slots.location_id and pu.variant_id=slots.variant_id
    where slots.tenant_id=p_tenant_id and (coalesce(s.active,true) or coalesce(b.quantity,0)<>0)
      and (p_location_id is null or slots.location_id=p_location_id)
      and private.reports_scope_v631(p_tenant_id,slots.location_id,p_location_id,'view')
      and (trim(coalesce(p_query,''))='' or lower(p.name) like q or lower(coalesce(pv.sku,'')) like q or lower(coalesce(pv.barcode,'')) like q or lower(coalesce(pv.part_number,'')) like q)
  )
  select b.location_id,b.location_code,b.location_name,b.variant_id,b.product_name,b.sku,b.quantity,b.available,b.reorder_level,b.max_stock,b.average_cost,
    round(b.quantity*b.average_cost,2)::numeric,
    b.net_sold_qty,round(b.net_sold_qty/v_days,4)::numeric,
    case when b.net_sold_qty<=0 then null else round(b.available/(b.net_sold_qty/v_days),1) end::numeric,
    greatest(
      case
        when b.max_stock>0 and b.available<=b.reorder_level then b.max_stock-b.available
        when b.reorder_level>0 and b.available<=b.reorder_level then greatest(b.reorder_level*2-b.available,0)
        else 0
      end,0
    )::numeric,
    b.last_sale,b.last_purchase,
    (case
      when b.available<=0 then 'out_of_stock'
      when b.reorder_level>0 and b.available<=b.reorder_level then 'low_stock'
      when b.max_stock>0 and b.available>b.max_stock then 'overstock'
      when b.net_sold_qty=0 and b.available>0 and coalesce(b.last_sale,date '1900-01-01')<current_date-interval '90 days' then 'dead_stock'
      else 'healthy' end)::text
  from base b
  order by
    case when b.available<=0 then 0 when b.reorder_level>0 and b.available<=b.reorder_level then 1 when b.net_sold_qty=0 and b.available>0 then 2 else 3 end,
    b.product_name,b.location_name;
end $function$;
CREATE OR REPLACE FUNCTION private.reports_returns_rows_v631(p_tenant_id uuid, p_kind text DEFAULT 'all'::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_location_id uuid DEFAULT NULL::uuid, p_query text DEFAULT ''::text, p_limit integer DEFAULT 5000)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare r record;q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if lower(coalesce(p_kind,'all')) not in('all','sales','purchase') then raise exception 'Invalid return type';end if;
  for r in
    with rows as (
      select
        'sales'::text return_side,sr.id return_id,sr.return_number::text return_number,sr.return_date return_date,
        s.id source_id,coalesce(dn.terminal_number,ln.local_number,s.sale_number)::text source_number,
        c.id party_id,c.name::text party_name,'customer'::text party_type,
        sri.variant_id,p.name::text product_name,pv.sku::text sku,pv.barcode::text barcode,pv.part_number::text part_number,
        pia.hsn_sac::text hsn_sac,coalesce(pia.unit_code,'')::text unit_code,
        sri.quantity::numeric quantity,sri.unit_price::numeric unit_rate,sri.discount_amount::numeric discount_amount,sri.tax_rate::numeric tax_rate,
        round(greatest(sri.line_total-((sri.unit_price*sri.quantity)-sri.discount_amount),0),2)::numeric tax_amount,
        round((sri.unit_price*sri.quantity)-sri.discount_amount,2)::numeric taxable_amount,sri.line_total::numeric line_total,
        sr.subtotal::numeric document_subtotal,sr.tax_total::numeric document_tax,sr.grand_total::numeric document_total,
        sr.reason::text reason,sr.refund_status::text settlement_status,
        sr.location_id,bl.location_code::text location_code,bl.name::text location_name,sr.created_by,sr.created_at,
        (select j.id from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='sales_return' and j.source_id=sr.id and j.status='posted' limit 1) accounting_journal_id,
        'inventory_in / cogs_reversal / output_tax_reversal / customer_credit_or_ar'::text accounting_effect
      from public.sales_returns sr
      join public.sales_return_items sri on sri.sales_return_id=sr.id
      join public.sales s on s.id=sr.sale_id
      join public.customers c on c.id=s.customer_id
      join public.product_variants pv on pv.id=sri.variant_id
      join public.products p on p.id=pv.product_id
      left join public.product_invoice_attributes_v45 pia on pia.tenant_id=sr.tenant_id and pia.variant_id=sri.variant_id
      left join public.business_locations bl on bl.id=sr.location_id
      left join public.location_document_numbers ln on ln.entity_type='sale' and ln.entity_id=s.id
      left join public.device_document_numbers dn on dn.entity_type='sale' and dn.entity_id=s.id
      where sr.tenant_id=p_tenant_id and private.reports_scope_v631(p_tenant_id,sr.location_id,p_location_id,'view') and sr.refund_status<>'waived'
        and (p_from is null or sr.return_date>=p_from) and (p_to is null or sr.return_date<=p_to)
        and (p_location_id is null or sr.location_id=p_location_id)
      union all
      select
        'purchase'::text,pr.id,pr.return_number::text,pr.return_date,
        pch.id,coalesce(dn.terminal_number,ln.local_number,pch.purchase_number)::text,
        s.id,s.name::text,'supplier'::text,
        pri.variant_id,prod.name::text,pv.sku::text,pv.barcode::text,pv.part_number::text,
        pia.hsn_sac::text,coalesce(pia.unit_code,'')::text,
        pri.quantity::numeric,pri.unit_cost::numeric,pri.discount_amount::numeric,pri.tax_rate::numeric,
        round(greatest(pri.line_total-((pri.unit_cost*pri.quantity)-pri.discount_amount),0),2)::numeric,
        round((pri.unit_cost*pri.quantity)-pri.discount_amount,2)::numeric,pri.line_total::numeric,
        pr.subtotal::numeric,pr.tax_total::numeric,pr.grand_total::numeric,
        pr.reason::text,pr.credit_status::text,
        pr.location_id,bl.location_code::text,bl.name::text,pr.created_by,pr.created_at,
        (select j.id from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='purchase_return' and j.source_id=pr.id and j.status='posted' limit 1),
        'inventory_out / input_tax_reversal / supplier_credit_or_ap'::text
      from public.purchase_returns pr
      join public.purchase_return_items pri on pri.purchase_return_id=pr.id
      join public.purchases pch on pch.id=pr.purchase_id
      join public.suppliers s on s.id=pch.supplier_id
      join public.product_variants pv on pv.id=pri.variant_id
      join public.products prod on prod.id=pv.product_id
      left join public.product_invoice_attributes_v45 pia on pia.tenant_id=pr.tenant_id and pia.variant_id=pri.variant_id
      left join public.business_locations bl on bl.id=pr.location_id
      left join public.location_document_numbers ln on ln.entity_type='purchase' and ln.entity_id=pch.id
      left join public.device_document_numbers dn on dn.entity_type='purchase' and dn.entity_id=pch.id
      where pr.tenant_id=p_tenant_id and private.reports_scope_v631(p_tenant_id,pr.location_id,p_location_id,'view') and pr.credit_status<>'waived'
        and (p_from is null or pr.return_date>=p_from) and (p_to is null or pr.return_date<=p_to)
        and (p_location_id is null or pr.location_id=p_location_id)
    )
    select * from rows x
    where (lower(coalesce(p_kind,'all'))='all' or x.return_side=lower(p_kind))
      and (trim(coalesce(p_query,''))='' or lower(x.return_number) like q or lower(coalesce(x.source_number,'')) like q or lower(x.party_name) like q or lower(x.product_name) like q or lower(coalesce(x.sku,'')) like q or lower(coalesce(x.barcode,'')) like q or lower(coalesce(x.hsn_sac,'')) like q or lower(coalesce(x.reason,'')) like q)
    order by return_date desc,created_at desc
loop return next to_jsonb(r);end loop;return;
end $function$;
CREATE OR REPLACE FUNCTION private.reports_statement_v631(p_tenant_id uuid, p_statement text, p_from date, p_to date, p_location_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_key text:=lower(trim(coalesce(p_statement,'')));
  v_rows jsonb:='[]'::jsonb;
  v_summary jsonb:='{}'::jsonb;
  v_revenue numeric:=0; v_cogs numeric:=0; v_expenses numeric:=0; v_net numeric:=0;
  v_assets numeric:=0; v_liabilities numeric:=0; v_equity numeric:=0; v_current_earnings numeric:=0;
  v_dr numeric:=0; v_cr numeric:=0; v_in numeric:=0; v_out numeric:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'accounting.view')
     and not private.erp_has_permission(p_tenant_id,'accounting.manage') then
    raise exception 'Accounting permission required';
  end if;
  if p_to is null then raise exception 'End date is required';end if;
  if p_from is null then p_from:=date '2000-01-01';end if;
  if p_from>p_to then raise exception 'Invalid date range';end if;

  if v_key='trial_balance' then
    with balances as (
      select a.id,a.code::text code,a.name::text name,a.account_type::text account_type,
        coalesce(sum(jl.debit) filter(where j.id is not null),0)::numeric debit,
        coalesce(sum(jl.credit) filter(where j.id is not null),0)::numeric credit
      from public.accounting_accounts a
      left join public.journal_lines jl on jl.account_id=a.id
      left join public.journal_entries j on j.id=jl.journal_entry_id
        and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date<=p_to
        and private.reports_scope_v631(p_tenant_id,j.location_id,p_location_id,'view')
      where a.tenant_id=p_tenant_id
      group by a.id,a.code,a.name,a.account_type
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'account_id',id,'code',code,'name',name,'account_type',account_type,
      'debit',debit,'credit',credit,
      'balance',case when account_type in('asset','expense','cogs') then debit-credit else credit-debit end
    ) order by code),'[]'::jsonb),coalesce(sum(debit),0),coalesce(sum(credit),0)
    into v_rows,v_dr,v_cr from balances where abs(debit)>0.0001 or abs(credit)>0.0001;
    v_summary:=jsonb_build_object('total_debit',v_dr,'total_credit',v_cr,'difference',v_dr-v_cr);

  elsif v_key='profit_loss' then
    with balances as (
      select a.id,a.code::text code,a.name::text name,a.account_type::text account_type,
        case when a.account_type='income' then coalesce(sum(jl.credit-jl.debit) filter(where j.id is not null),0)
             else coalesce(sum(jl.debit-jl.credit) filter(where j.id is not null),0) end::numeric amount
      from public.accounting_accounts a
      left join public.journal_lines jl on jl.account_id=a.id
      left join public.journal_entries j on j.id=jl.journal_entry_id
        and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date between p_from and p_to
        and private.reports_scope_v631(p_tenant_id,j.location_id,p_location_id,'view')
      where a.tenant_id=p_tenant_id and a.account_type in('income','cogs','expense')
      group by a.id,a.code,a.name,a.account_type
    )
    select coalesce(jsonb_agg(jsonb_build_object('account_id',id,'code',code,'name',name,'account_type',account_type,'amount',amount) order by account_type,code),'[]'::jsonb),
      coalesce(sum(amount) filter(where account_type='income'),0),
      coalesce(sum(amount) filter(where account_type='cogs'),0),
      coalesce(sum(amount) filter(where account_type='expense'),0)
    into v_rows,v_revenue,v_cogs,v_expenses from balances where abs(amount)>0.0001;
    v_net:=v_revenue-v_cogs-v_expenses;
    v_summary:=jsonb_build_object('revenue',v_revenue,'cogs',v_cogs,'expenses',v_expenses,'net_profit',v_net,'from',p_from,'to',p_to);

  elsif v_key='balance_sheet' then
    with balances as (
      select a.id,a.code::text code,a.name::text name,a.account_type::text account_type,
        case when a.account_type='asset' then coalesce(sum(jl.debit-jl.credit) filter(where j.id is not null),0)
             else coalesce(sum(jl.credit-jl.debit) filter(where j.id is not null),0) end::numeric amount
      from public.accounting_accounts a
      left join public.journal_lines jl on jl.account_id=a.id
      left join public.journal_entries j on j.id=jl.journal_entry_id
        and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date<=p_to
        and private.reports_scope_v631(p_tenant_id,j.location_id,p_location_id,'view')
      where a.tenant_id=p_tenant_id and a.account_type in('asset','liability','equity')
      group by a.id,a.code,a.name,a.account_type
    ), earnings as (
      select coalesce(sum(case when a.account_type='income' then jl.credit-jl.debit when a.account_type in('expense','cogs') then -(jl.debit-jl.credit) else 0 end),0)::numeric amount
      from public.journal_lines jl
      join public.accounting_accounts a on a.id=jl.account_id and a.tenant_id=p_tenant_id
      join public.journal_entries j on j.id=jl.journal_entry_id and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date<=p_to
      where a.account_type in('income','expense','cogs') and private.reports_scope_v631(p_tenant_id,j.location_id,p_location_id,'view')
    )
    select coalesce(jsonb_agg(jsonb_build_object('account_id',id,'code',code,'name',name,'account_type',account_type,'amount',amount) order by account_type,code),'[]'::jsonb),
      coalesce(sum(amount) filter(where account_type='asset'),0),
      coalesce(sum(amount) filter(where account_type='liability'),0),
      coalesce(sum(amount) filter(where account_type='equity'),0)
    into v_rows,v_assets,v_liabilities,v_equity from balances where abs(amount)>0.0001;
    select coalesce(sum(case when a.account_type='income' then jl.credit-jl.debit when a.account_type in('expense','cogs') then -(jl.debit-jl.credit) else 0 end),0)::numeric into v_current_earnings from public.journal_lines jl join public.accounting_accounts a on a.id=jl.account_id and a.tenant_id=p_tenant_id join public.journal_entries j on j.id=jl.journal_entry_id and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date<=p_to where a.account_type in('income','expense','cogs') and private.reports_scope_v631(p_tenant_id,j.location_id,p_location_id,'view');
    v_summary:=jsonb_build_object(
      'assets',v_assets,'liabilities',v_liabilities,'equity',v_equity,
      'current_earnings',v_current_earnings,
      'liabilities_and_equity',v_liabilities+v_equity+v_current_earnings,
      'difference',v_assets-(v_liabilities+v_equity+v_current_earnings),'as_of',p_to
    );

  elsif v_key='cash_flow' then
    with cash_accounts as (
      select distinct a.id,a.code::text code,a.name::text name,a.system_key::text system_key
      from public.accounting_accounts a
      left join public.accounting_account_mappings m on m.tenant_id=a.tenant_id and m.account_id=a.id
      where a.tenant_id=p_tenant_id
        and (a.system_key in('cash','bank','upi','card') or m.mapping_key in('payment.cash','payment.bank','payment.upi','payment.card'))
    ), moves as (
      select a.id,a.code,a.name,a.system_key,
        coalesce(sum(jl.debit) filter(where j.id is not null),0)::numeric inflow,
        coalesce(sum(jl.credit) filter(where j.id is not null),0)::numeric outflow
      from cash_accounts a
      left join public.journal_lines jl on jl.account_id=a.id
      left join public.journal_entries j on j.id=jl.journal_entry_id
        and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date between p_from and p_to
        and private.reports_scope_v631(p_tenant_id,j.location_id,p_location_id,'view')
      group by a.id,a.code,a.name,a.system_key
    )
    select coalesce(jsonb_agg(jsonb_build_object('account_id',id,'code',code,'name',name,'system_key',system_key,'inflow',inflow,'outflow',outflow,'net_change',inflow-outflow) order by code),'[]'::jsonb),
      coalesce(sum(inflow),0),coalesce(sum(outflow),0)
    into v_rows,v_in,v_out from moves where abs(inflow)>0.0001 or abs(outflow)>0.0001;
    v_summary:=jsonb_build_object('inflow',v_in,'outflow',v_out,'net_change',v_in-v_out,'from',p_from,'to',p_to,'note','Cash/Bank/UPI/Card account movement');
  else
    raise exception 'Unknown accounting statement %',p_statement;
  end if;

  return jsonb_build_object('statement',v_key,'rows',v_rows,'summary',v_summary,'location_id',p_location_id);
end $function$;
create or replace function private.reports_definitions_v631() returns jsonb language sql immutable set search_path=pg_catalog as $defs$select '[{"key":"sales_summary","title":"Sales Summary","category":"Sales","description":"Posted sales, returns, tax, invoice cost and margin for the selected document dates.","basis":"period","kind":"summary","columns":[{"key":"metric","label":"Metric","type":"text","total":false,"width":150},{"key":"amount","label":"Amount","type":"money","total":false,"width":150}]},{"key":"sales_register","title":"Sales Register","category":"Sales","description":"One row per posted invoice. Payments and outstanding are measured through the To date. Open a row for saved items, payments and load evidence.","basis":"period","kind":"table","columns":[{"key":"sale_number","label":"Sale Number","type":"text","total":false,"width":150},{"key":"sale_date","label":"Sale Date","type":"date","total":false,"width":150},{"key":"customer_name","label":"Customer Name","type":"text","total":false,"width":240},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240},{"key":"taxable_total","label":"Taxable Total","type":"money","total":true,"width":150},{"key":"tax_total","label":"Tax Total","type":"money","total":true,"width":150},{"key":"grand_total","label":"Grand Total","type":"money","total":true,"width":150},{"key":"paid_as_of","label":"Paid As Of","type":"money","total":true,"width":150},{"key":"outstanding","label":"Outstanding","type":"money","total":true,"width":150},{"key":"status","label":"Status","type":"text","total":false,"width":150}]},{"key":"sales_items","title":"Sales Line Details","category":"Sales","description":"Saved invoice line descriptions, units, rates, discounts, tax components and pricing evidence.","basis":"period","kind":"table","columns":[{"key":"sale_number","label":"Sale Number","type":"text","total":false,"width":150},{"key":"sale_date","label":"Sale Date","type":"date","total":false,"width":150},{"key":"customer_name","label":"Customer Name","type":"text","total":false,"width":240},{"key":"product_name","label":"Product Name","type":"text","total":false,"width":240},{"key":"sku","label":"Sku","type":"text","total":false,"width":150},{"key":"unit_code","label":"Unit Code","type":"text","total":false,"width":150},{"key":"quantity","label":"Quantity","type":"number","total":false,"width":150},{"key":"unit_price","label":"Unit Price","type":"money","total":false,"width":150},{"key":"discount_amount","label":"Discount Amount","type":"money","total":true,"width":150},{"key":"taxable_amount","label":"Taxable Amount","type":"money","total":true,"width":150},{"key":"tax_amount","label":"Tax Amount","type":"money","total":true,"width":150},{"key":"line_total","label":"Line Total","type":"money","total":true,"width":150}]},{"key":"sales_by_product","title":"Sales by Product","category":"Sales","description":"Posted invoice lines grouped by material/product and base unit. Returns are reported separately.","basis":"period","kind":"table","columns":[{"key":"product_name","label":"Product Name","type":"text","total":false,"width":240},{"key":"sku","label":"Sku","type":"text","total":false,"width":150},{"key":"unit_code","label":"Unit Code","type":"text","total":false,"width":150},{"key":"quantity","label":"Quantity","type":"number","total":false,"width":150},{"key":"taxable_sales","label":"Taxable Sales","type":"money","total":true,"width":150},{"key":"tax","label":"Tax","type":"money","total":true,"width":150},{"key":"total","label":"Total","type":"money","total":true,"width":150},{"key":"gross_profit","label":"Gross Profit","type":"money","total":true,"width":150}]},{"key":"sales_by_customer","title":"Sales by Customer","category":"Sales","description":"Posted invoices grouped using recorded document origin and creator; customer profile changes do not change attribution.","basis":"period","kind":"table","columns":[{"key":"customer_name","label":"Customer Name","type":"text","total":false,"width":240},{"key":"invoices","label":"Invoices","type":"number","total":true,"width":150},{"key":"taxable_sales","label":"Taxable Sales","type":"money","total":true,"width":150},{"key":"tax","label":"Tax","type":"money","total":true,"width":150},{"key":"total","label":"Total","type":"money","total":true,"width":150},{"key":"gross_profit","label":"Gross Profit","type":"money","total":true,"width":150}]},{"key":"sales_by_salesperson","title":"Sales by Recorded User","category":"Sales","description":"Posted invoices grouped using recorded document origin and creator; customer profile changes do not change attribution.","basis":"period","kind":"table","columns":[{"key":"recorded_by","label":"Recorded By","type":"text","total":false,"width":150},{"key":"invoices","label":"Invoices","type":"number","total":true,"width":150},{"key":"taxable_sales","label":"Taxable Sales","type":"money","total":true,"width":150},{"key":"tax","label":"Tax","type":"money","total":true,"width":150},{"key":"total","label":"Total","type":"money","total":true,"width":150},{"key":"gross_profit","label":"Gross Profit","type":"money","total":true,"width":150}]},{"key":"sales_by_store","title":"Sales by Store","category":"Sales","description":"Posted invoices grouped using recorded document origin and creator; customer profile changes do not change attribution.","basis":"period","kind":"table","columns":[{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240},{"key":"invoices","label":"Invoices","type":"number","total":true,"width":150},{"key":"taxable_sales","label":"Taxable Sales","type":"money","total":true,"width":150},{"key":"tax","label":"Tax","type":"money","total":true,"width":150},{"key":"total","label":"Total","type":"money","total":true,"width":150},{"key":"gross_profit","label":"Gross Profit","type":"money","total":true,"width":150}]},{"key":"sales_by_pos","title":"Sales by POS","category":"Sales","description":"Posted invoices grouped using recorded document origin and creator; customer profile changes do not change attribution.","basis":"period","kind":"table","columns":[{"key":"terminal","label":"Terminal","type":"text","total":false,"width":150},{"key":"invoices","label":"Invoices","type":"number","total":true,"width":150},{"key":"taxable_sales","label":"Taxable Sales","type":"money","total":true,"width":150},{"key":"tax","label":"Tax","type":"money","total":true,"width":150},{"key":"total","label":"Total","type":"money","total":true,"width":150},{"key":"gross_profit","label":"Gross Profit","type":"money","total":true,"width":150}]},{"key":"sales_by_payment_method","title":"Sales by Payment Method","category":"Sales","description":"Customer receipts recorded in the selected payment-date period, grouped by method.","basis":"period","kind":"table","columns":[{"key":"payment_method","label":"Payment Method","type":"text","total":false,"width":150},{"key":"payment_count","label":"Payment Count","type":"number","total":true,"width":150},{"key":"amount","label":"Amount","type":"money","total":true,"width":150}]},{"key":"sales_payments","title":"Customer Receipt Register","category":"Sales","description":"Every saved receipt, including its bank reference, invoice, method and notes. Dates use the business timezone.","basis":"period","kind":"table","columns":[{"key":"paid_at","label":"Paid At","type":"datetime","total":false,"width":150},{"key":"sale_number","label":"Sale Number","type":"text","total":false,"width":150},{"key":"customer_name","label":"Customer Name","type":"text","total":false,"width":240},{"key":"payment_method","label":"Payment Method","type":"text","total":false,"width":150},{"key":"amount","label":"Amount","type":"money","total":true,"width":150},{"key":"reference_number","label":"Reference Number","type":"text","total":false,"width":150},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240},{"key":"notes","label":"Notes","type":"text","total":false,"width":150}]},{"key":"returns","title":"Sales Returns","category":"Sales","description":"One row per returned line, with original invoice, customer, reason and settlement evidence.","basis":"period","kind":"table","columns":[{"key":"return_number","label":"Return Number","type":"text","total":false,"width":150},{"key":"return_date","label":"Return Date","type":"date","total":false,"width":150},{"key":"source_number","label":"Source Number","type":"text","total":false,"width":150},{"key":"party_name","label":"Party Name","type":"text","total":false,"width":240},{"key":"product_name","label":"Product Name","type":"text","total":false,"width":240},{"key":"unit_code","label":"Unit Code","type":"text","total":false,"width":150},{"key":"quantity","label":"Quantity","type":"number","total":false,"width":150},{"key":"taxable_amount","label":"Taxable Amount","type":"money","total":true,"width":150},{"key":"tax_amount","label":"Tax Amount","type":"money","total":true,"width":150},{"key":"line_total","label":"Line Total","type":"money","total":true,"width":150},{"key":"settlement_status","label":"Settlement Status","type":"text","total":false,"width":150},{"key":"reason","label":"Reason","type":"text","total":false,"width":150}]},{"key":"current_stock","title":"Current Stock","category":"Inventory","description":"Current authorized store balances. Sales velocity uses the selected period length ending today; this is not a historical stock snapshot.","basis":"current","kind":"table","columns":[{"key":"product_name","label":"Product Name","type":"text","total":false,"width":240},{"key":"sku","label":"Sku","type":"text","total":false,"width":150},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240},{"key":"quantity","label":"Quantity","type":"number","total":false,"width":150},{"key":"available","label":"Available","type":"number","total":false,"width":150},{"key":"reorder_level","label":"Reorder Level","type":"number","total":false,"width":150},{"key":"average_cost","label":"Average Cost","type":"money","total":false,"width":150},{"key":"stock_value","label":"Stock Value","type":"money","total":true,"width":150},{"key":"status","label":"Status","type":"text","total":false,"width":150}]},{"key":"stock_valuation","title":"Current Stock Valuation","category":"Inventory","description":"Current authorized store balances. Sales velocity uses the selected period length ending today; this is not a historical stock snapshot.","basis":"current","kind":"table","columns":[{"key":"product_name","label":"Product Name","type":"text","total":false,"width":240},{"key":"sku","label":"Sku","type":"text","total":false,"width":150},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240},{"key":"quantity","label":"Quantity","type":"number","total":false,"width":150},{"key":"available","label":"Available","type":"number","total":false,"width":150},{"key":"reorder_level","label":"Reorder Level","type":"number","total":false,"width":150},{"key":"average_cost","label":"Average Cost","type":"money","total":false,"width":150},{"key":"stock_value","label":"Stock Value","type":"money","total":true,"width":150},{"key":"status","label":"Status","type":"text","total":false,"width":150}]},{"key":"low_stock","title":"Low Stock","category":"Inventory","description":"Current authorized store balances. Sales velocity uses the selected period length ending today; this is not a historical stock snapshot.","basis":"current","kind":"table","columns":[{"key":"product_name","label":"Product Name","type":"text","total":false,"width":240},{"key":"sku","label":"Sku","type":"text","total":false,"width":150},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240},{"key":"quantity","label":"Quantity","type":"number","total":false,"width":150},{"key":"available","label":"Available","type":"number","total":false,"width":150},{"key":"reorder_level","label":"Reorder Level","type":"number","total":false,"width":150},{"key":"average_cost","label":"Average Cost","type":"money","total":false,"width":150},{"key":"stock_value","label":"Stock Value","type":"money","total":true,"width":150},{"key":"status","label":"Status","type":"text","total":false,"width":150}]},{"key":"dead_stock","title":"Dead Stock","category":"Inventory","description":"Current authorized store balances. Sales velocity uses the selected period length ending today; this is not a historical stock snapshot.","basis":"current","kind":"table","columns":[{"key":"product_name","label":"Product Name","type":"text","total":false,"width":240},{"key":"sku","label":"Sku","type":"text","total":false,"width":150},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240},{"key":"quantity","label":"Quantity","type":"number","total":false,"width":150},{"key":"available","label":"Available","type":"number","total":false,"width":150},{"key":"reorder_level","label":"Reorder Level","type":"number","total":false,"width":150},{"key":"average_cost","label":"Average Cost","type":"money","total":false,"width":150},{"key":"stock_value","label":"Stock Value","type":"money","total":true,"width":150},{"key":"status","label":"Status","type":"text","total":false,"width":150}]},{"key":"stock_aging","title":"Stock Activity and Aging","category":"Inventory","description":"Current stock with days since the last purchase and sales activity. This measures inactivity, not FIFO lot age.","basis":"current","kind":"table","columns":[{"key":"product_name","label":"Product Name","type":"text","total":false,"width":240},{"key":"sku","label":"Sku","type":"text","total":false,"width":150},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240},{"key":"quantity","label":"Quantity","type":"number","total":false,"width":150},{"key":"stock_value","label":"Stock Value","type":"money","total":true,"width":150},{"key":"last_sale_date","label":"Last Sale Date","type":"date","total":false,"width":150},{"key":"last_purchase_date","label":"Last Purchase Date","type":"date","total":false,"width":150},{"key":"days_since_purchase","label":"Days Since Purchase","type":"number","total":false,"width":150},{"key":"net_sold_qty","label":"Net Sold Qty","type":"number","total":false,"width":150},{"key":"days_cover","label":"Days Cover","type":"number","total":false,"width":150},{"key":"status","label":"Status","type":"text","total":false,"width":150}]},{"key":"stock_movement","title":"Stock Movement","category":"Inventory","description":"Saved stock ledger movements, base and entered quantities, references and before/after balances.","basis":"period","kind":"table","columns":[{"key":"created_at","label":"Created At","type":"datetime","total":false,"width":150},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240},{"key":"product_name","label":"Product Name","type":"text","total":false,"width":240},{"key":"sku","label":"Sku","type":"text","total":false,"width":150},{"key":"unit_code","label":"Unit Code","type":"text","total":false,"width":150},{"key":"base_quantity_delta","label":"Base Quantity Delta","type":"number","total":false,"width":150},{"key":"balance_before","label":"Balance Before","type":"number","total":false,"width":150},{"key":"balance_after","label":"Balance After","type":"number","total":false,"width":150},{"key":"unit_cost","label":"Unit Cost","type":"money","total":false,"width":150},{"key":"movement_type","label":"Movement Type","type":"text","total":false,"width":150},{"key":"reference_number","label":"Reference Number","type":"text","total":false,"width":150},{"key":"note","label":"Note","type":"text","total":false,"width":150}]},{"key":"expiry","title":"Batch Expiry","category":"Inventory","description":"Current non-zero batch balances whose expiry date falls in the selected range.","basis":"expiry","kind":"table","columns":[{"key":"product_name","label":"Product Name","type":"text","total":false,"width":240},{"key":"sku","label":"Sku","type":"text","total":false,"width":150},{"key":"batch_number","label":"Batch Number","type":"text","total":false,"width":150},{"key":"expiry_on","label":"Expiry On","type":"date","total":false,"width":150},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240},{"key":"quantity","label":"Quantity","type":"number","total":false,"width":150},{"key":"status","label":"Status","type":"text","total":false,"width":150}]},{"key":"batches","title":"Batch and Lot Balances","category":"Inventory","description":"Current saved batch balances and complete lot information.","basis":"current","kind":"table","columns":[{"key":"product_name","label":"Product Name","type":"text","total":false,"width":240},{"key":"sku","label":"Sku","type":"text","total":false,"width":150},{"key":"batch_number","label":"Batch Number","type":"text","total":false,"width":150},{"key":"manufactured_on","label":"Manufactured On","type":"date","total":false,"width":150},{"key":"expiry_on","label":"Expiry On","type":"date","total":false,"width":150},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240},{"key":"quantity","label":"Quantity","type":"number","total":false,"width":150},{"key":"reserved_quantity","label":"Reserved Quantity","type":"number","total":false,"width":150},{"key":"damaged_quantity","label":"Damaged Quantity","type":"number","total":false,"width":150}]},{"key":"serials","title":"Serial Numbers","category":"Inventory","description":"Current serial state and store, with complete saved serial evidence.","basis":"current","kind":"table","columns":[{"key":"serial_number","label":"Serial Number","type":"text","total":false,"width":150},{"key":"product_name","label":"Product Name","type":"text","total":false,"width":240},{"key":"sku","label":"Sku","type":"text","total":false,"width":150},{"key":"status","label":"Status","type":"text","total":false,"width":150},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240},{"key":"updated_at","label":"Updated At","type":"datetime","total":false,"width":150}]},{"key":"purchase_register","title":"Purchase Register","category":"Purchase","description":"One row per posted supplier bill, including saved lines and payments through the To date.","basis":"period","kind":"table","columns":[{"key":"purchase_number","label":"Purchase Number","type":"text","total":false,"width":150},{"key":"purchase_date","label":"Purchase Date","type":"date","total":false,"width":150},{"key":"supplier_name","label":"Supplier Name","type":"text","total":false,"width":240},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240},{"key":"taxable_total","label":"Taxable Total","type":"money","total":true,"width":150},{"key":"tax_total","label":"Tax Total","type":"money","total":true,"width":150},{"key":"grand_total","label":"Grand Total","type":"money","total":true,"width":150},{"key":"paid_as_of","label":"Paid As Of","type":"money","total":true,"width":150},{"key":"outstanding","label":"Outstanding","type":"money","total":true,"width":150},{"key":"status","label":"Status","type":"text","total":false,"width":150}]},{"key":"purchase_items","title":"Purchase Line Details","category":"Purchase","description":"Saved supplier bill lines, entered units and costs, discounts and tax evidence.","basis":"period","kind":"table","columns":[{"key":"purchase_number","label":"Purchase Number","type":"text","total":false,"width":150},{"key":"purchase_date","label":"Purchase Date","type":"date","total":false,"width":150},{"key":"supplier_name","label":"Supplier Name","type":"text","total":false,"width":240},{"key":"product_name","label":"Product Name","type":"text","total":false,"width":240},{"key":"sku","label":"Sku","type":"text","total":false,"width":150},{"key":"unit_code","label":"Unit Code","type":"text","total":false,"width":150},{"key":"quantity","label":"Quantity","type":"number","total":false,"width":150},{"key":"unit_cost","label":"Unit Cost","type":"money","total":false,"width":150},{"key":"discount_amount","label":"Discount Amount","type":"money","total":true,"width":150},{"key":"taxable_amount","label":"Taxable Amount","type":"money","total":true,"width":150},{"key":"tax_amount","label":"Tax Amount","type":"money","total":true,"width":150},{"key":"line_total","label":"Line Total","type":"money","total":true,"width":150}]},{"key":"supplier_purchase","title":"Supplier Purchases","category":"Purchase","description":"Posted bills grouped by the saved supplier identity for the selected period.","basis":"period","kind":"table","columns":[{"key":"supplier_name","label":"Supplier Name","type":"text","total":false,"width":240},{"key":"bills","label":"Bills","type":"number","total":true,"width":150},{"key":"taxable_purchases","label":"Taxable Purchases","type":"money","total":true,"width":150},{"key":"tax","label":"Tax","type":"money","total":true,"width":150},{"key":"total","label":"Total","type":"money","total":true,"width":150}]},{"key":"purchase_returns","title":"Purchase Returns","category":"Purchase","description":"Returned purchase lines with original bill, supplier, reason and credit evidence.","basis":"period","kind":"table","columns":[{"key":"return_number","label":"Return Number","type":"text","total":false,"width":150},{"key":"return_date","label":"Return Date","type":"date","total":false,"width":150},{"key":"source_number","label":"Source Number","type":"text","total":false,"width":150},{"key":"party_name","label":"Party Name","type":"text","total":false,"width":240},{"key":"product_name","label":"Product Name","type":"text","total":false,"width":240},{"key":"unit_code","label":"Unit Code","type":"text","total":false,"width":150},{"key":"quantity","label":"Quantity","type":"number","total":false,"width":150},{"key":"taxable_amount","label":"Taxable Amount","type":"money","total":true,"width":150},{"key":"tax_amount","label":"Tax Amount","type":"money","total":true,"width":150},{"key":"line_total","label":"Line Total","type":"money","total":true,"width":150},{"key":"settlement_status","label":"Settlement Status","type":"text","total":false,"width":150},{"key":"reason","label":"Reason","type":"text","total":false,"width":150}]},{"key":"purchase_payments","title":"Supplier Payment Register","category":"Purchase","description":"Every saved supplier payment in the selected payment-date period.","basis":"period","kind":"table","columns":[{"key":"paid_at","label":"Paid At","type":"datetime","total":false,"width":150},{"key":"purchase_number","label":"Purchase Number","type":"text","total":false,"width":150},{"key":"supplier_name","label":"Supplier Name","type":"text","total":false,"width":240},{"key":"payment_method","label":"Payment Method","type":"text","total":false,"width":150},{"key":"amount","label":"Amount","type":"money","total":true,"width":150},{"key":"reference_number","label":"Reference Number","type":"text","total":false,"width":150},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240},{"key":"notes","label":"Notes","type":"text","total":false,"width":150}]},{"key":"supplier_outstanding","title":"Supplier Outstanding","category":"Purchase","description":"Supplier payable ledger balances through the To date; debits and credits show selected-period movement.","basis":"as_of","kind":"table","columns":[{"key":"party_name","label":"Party Name","type":"text","total":false,"width":240},{"key":"opening_balance","label":"Opening Balance","type":"money","total":true,"width":150},{"key":"debits","label":"Debits","type":"money","total":true,"width":150},{"key":"credits","label":"Credits","type":"money","total":true,"width":150},{"key":"balance","label":"Balance","type":"money","total":true,"width":150},{"key":"outstanding","label":"Outstanding","type":"money","total":true,"width":150},{"key":"advance_balance","label":"Advance Balance","type":"money","total":true,"width":150}]},{"key":"supplier_performance","title":"Supplier Settlement Performance","category":"Purchase","description":"Invoicing, returned value and settlement performance through the To date, restricted to authorized stores.","basis":"period","kind":"table","columns":[{"key":"supplier_name","label":"Supplier Name","type":"text","total":false,"width":240},{"key":"bills","label":"Bills","type":"number","total":true,"width":150},{"key":"total","label":"Total","type":"money","total":true,"width":150},{"key":"paid_as_of","label":"Paid As Of","type":"money","total":true,"width":150},{"key":"outstanding","label":"Outstanding","type":"money","total":true,"width":150},{"key":"overdue_bills","label":"Overdue Bills","type":"number","total":true,"width":150},{"key":"returns_total","label":"Returns Total","type":"money","total":true,"width":150}]},{"key":"price_history","title":"Purchase Price History","category":"Purchase","description":"Actual saved purchase rates and conversion units within the selected document-date range.","basis":"period","kind":"table","columns":[{"key":"purchase_date","label":"Purchase Date","type":"date","total":false,"width":150},{"key":"purchase_number","label":"Purchase Number","type":"text","total":false,"width":150},{"key":"supplier_name","label":"Supplier Name","type":"text","total":false,"width":240},{"key":"product_name","label":"Product Name","type":"text","total":false,"width":240},{"key":"sku","label":"Sku","type":"text","total":false,"width":150},{"key":"unit_code","label":"Unit Code","type":"text","total":false,"width":150},{"key":"quantity","label":"Quantity","type":"number","total":false,"width":150},{"key":"unit_cost","label":"Unit Cost","type":"money","total":false,"width":150},{"key":"entered_unit_cost","label":"Entered Unit Cost","type":"money","total":false,"width":150},{"key":"discount_amount","label":"Discount Amount","type":"money","total":false,"width":150},{"key":"tax_rate","label":"Tax Rate","type":"number","total":false,"width":150},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240}]},{"key":"profit_loss","title":"Profit and Loss","category":"Accounting","description":"Posted income, COGS and expense ledger balances, including Staff wages and yard costs.","basis":"period","kind":"statement","columns":[{"key":"code","label":"Code","type":"text","total":false,"width":150},{"key":"name","label":"Name","type":"text","total":false,"width":240},{"key":"account_type","label":"Account Type","type":"text","total":false,"width":150},{"key":"amount","label":"Amount","type":"money","total":false,"width":150}]},{"key":"balance_sheet","title":"Balance Sheet","category":"Accounting","description":"Posted account balances and accumulated earnings through the To date, including inactive accounts with history.","basis":"as_of","kind":"statement","columns":[{"key":"code","label":"Code","type":"text","total":false,"width":150},{"key":"name","label":"Name","type":"text","total":false,"width":240},{"key":"account_type","label":"Account Type","type":"text","total":false,"width":150},{"key":"amount","label":"Amount","type":"money","total":false,"width":150}]},{"key":"trial_balance","title":"Trial Balance","category":"Accounting","description":"Opening balance, period movement and closing debit/credit balances from posted journals.","basis":"as_of","kind":"statement","columns":[{"key":"code","label":"Code","type":"text","total":false,"width":150},{"key":"name","label":"Name","type":"text","total":false,"width":240},{"key":"account_type","label":"Account Type","type":"text","total":false,"width":150},{"key":"opening_balance","label":"Opening Balance","type":"money","total":false,"width":150},{"key":"debit","label":"Debit","type":"money","total":true,"width":150},{"key":"credit","label":"Credit","type":"money","total":true,"width":150},{"key":"closing_debit","label":"Closing Debit","type":"money","total":true,"width":150},{"key":"closing_credit","label":"Closing Credit","type":"money","total":true,"width":150}]},{"key":"general_ledger","title":"General Ledger","category":"Accounting","description":"One row per posted ledger line. Running balances include all authorized prior entries; search filters only displayed rows.","basis":"period","kind":"table","columns":[{"key":"code","label":"Code","type":"text","total":false,"width":150},{"key":"account_name","label":"Account Name","type":"text","total":false,"width":240},{"key":"entry_date","label":"Entry Date","type":"date","total":false,"width":150},{"key":"entry_number","label":"Entry Number","type":"text","total":false,"width":150},{"key":"source_reference","label":"Source Reference","type":"text","total":false,"width":150},{"key":"party_name","label":"Party Name","type":"text","total":false,"width":240},{"key":"line_detail","label":"Line Detail","type":"text","total":false,"width":150},{"key":"debit","label":"Debit","type":"money","total":true,"width":150},{"key":"credit","label":"Credit","type":"money","total":true,"width":150},{"key":"running_balance","label":"Running Balance","type":"money","total":false,"width":150}]},{"key":"cash_flow","title":"Cash and Bank Movement","category":"Accounting","description":"Posted Cash/Bank/UPI/Card account movement, opening balances and closing balances; internal transfers appear on both sides.","basis":"period","kind":"statement","columns":[{"key":"code","label":"Code","type":"text","total":false,"width":150},{"key":"name","label":"Name","type":"text","total":false,"width":240},{"key":"system_key","label":"System Key","type":"text","total":false,"width":150},{"key":"opening_balance","label":"Opening Balance","type":"money","total":false,"width":150},{"key":"inflow","label":"Inflow","type":"money","total":true,"width":150},{"key":"outflow","label":"Outflow","type":"money","total":true,"width":150},{"key":"net_change","label":"Net Change","type":"money","total":true,"width":150},{"key":"closing_balance","label":"Closing Balance","type":"money","total":false,"width":150}]},{"key":"receivables","title":"Accounts Receivable","category":"Accounting","description":"Posted control-account balances through the To date. Payables includes supplier, Staff and load-cost creditors.","basis":"as_of","kind":"table","columns":[{"key":"party_name","label":"Party Name","type":"text","total":false,"width":240},{"key":"party_type","label":"Party Type","type":"text","total":false,"width":150},{"key":"opening_balance","label":"Opening Balance","type":"money","total":true,"width":150},{"key":"debits","label":"Debits","type":"money","total":true,"width":150},{"key":"credits","label":"Credits","type":"money","total":true,"width":150},{"key":"balance","label":"Balance","type":"money","total":true,"width":150},{"key":"outstanding","label":"Outstanding","type":"money","total":true,"width":150},{"key":"advance_balance","label":"Advance Balance","type":"money","total":true,"width":150}]},{"key":"payables","title":"Accounts Payable","category":"Accounting","description":"Posted control-account balances through the To date. Payables includes supplier, Staff and load-cost creditors.","basis":"as_of","kind":"table","columns":[{"key":"party_name","label":"Party Name","type":"text","total":false,"width":240},{"key":"party_type","label":"Party Type","type":"text","total":false,"width":150},{"key":"opening_balance","label":"Opening Balance","type":"money","total":true,"width":150},{"key":"debits","label":"Debits","type":"money","total":true,"width":150},{"key":"credits","label":"Credits","type":"money","total":true,"width":150},{"key":"balance","label":"Balance","type":"money","total":true,"width":150},{"key":"outstanding","label":"Outstanding","type":"money","total":true,"width":150},{"key":"advance_balance","label":"Advance Balance","type":"money","total":true,"width":150}]},{"key":"journal_register","title":"Journal Register","category":"Accounting","description":"One row per posted journal with every saved account/party line available in the record preview.","basis":"period","kind":"table","columns":[{"key":"entry_date","label":"Entry Date","type":"date","total":false,"width":150},{"key":"entry_number","label":"Entry Number","type":"text","total":false,"width":150},{"key":"source_type","label":"Source Type","type":"text","total":false,"width":150},{"key":"source_reference","label":"Source Reference","type":"text","total":false,"width":150},{"key":"description","label":"Description","type":"text","total":false,"width":240},{"key":"total_debit","label":"Total Debit","type":"money","total":true,"width":150},{"key":"total_credit","label":"Total Credit","type":"money","total":true,"width":150},{"key":"difference","label":"Difference","type":"money","total":true,"width":150},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240},{"key":"status","label":"Status","type":"text","total":false,"width":150}]},{"key":"expenses","title":"Expense Register","category":"Accounting","description":"Posted expense documents; Staff and load-cost journals are shown in their dedicated reports and Profit and Loss.","basis":"period","kind":"table","columns":[{"key":"expense_date","label":"Expense Date","type":"date","total":false,"width":150},{"key":"expense_number","label":"Expense Number","type":"text","total":false,"width":150},{"key":"category","label":"Category","type":"text","total":false,"width":150},{"key":"payee","label":"Payee","type":"text","total":false,"width":150},{"key":"description","label":"Description","type":"text","total":false,"width":240},{"key":"amount","label":"Amount","type":"money","total":true,"width":150},{"key":"tax_amount","label":"Tax Amount","type":"money","total":true,"width":150},{"key":"total_amount","label":"Total Amount","type":"money","total":true,"width":150},{"key":"payment_method","label":"Payment Method","type":"text","total":false,"width":150},{"key":"reference_number","label":"Reference Number","type":"text","total":false,"width":150},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240}]},{"key":"tax","title":"GST and Recorded Tax","category":"Accounting","description":"Immutable GST snapshots with recorded tax components. Legacy documents are identified separately and excluded from authoritative component totals.","basis":"period","kind":"statement","columns":[{"key":"document_date","label":"Document Date","type":"date","total":false,"width":150},{"key":"source_number","label":"Source Number","type":"text","total":false,"width":150},{"key":"document_kind","label":"Document Kind","type":"text","total":false,"width":150},{"key":"document_class","label":"Document Class","type":"text","total":false,"width":150},{"key":"verification","label":"Verification","type":"text","total":false,"width":150},{"key":"direction","label":"Direction","type":"text","total":false,"width":150},{"key":"document_sign","label":"Document Sign","type":"number","total":false,"width":150},{"key":"taxable_total","label":"Taxable Total","type":"money","total":false,"width":150},{"key":"cgst_total","label":"Cgst Total","type":"money","total":false,"width":150},{"key":"sgst_total","label":"Sgst Total","type":"money","total":false,"width":150},{"key":"igst_total","label":"Igst Total","type":"money","total":false,"width":150},{"key":"utgst_total","label":"Utgst Total","type":"money","total":false,"width":150},{"key":"cess_total","label":"Cess Total","type":"money","total":false,"width":150},{"key":"tax_collected_total","label":"Tax Collected Total","type":"money","total":false,"width":150},{"key":"rcm_tax_payable_total","label":"Rcm Tax Payable Total","type":"money","total":false,"width":150}]},{"key":"reconciliation","title":"Financial and Document Reconciliation","category":"Accounting","description":"Read-only checks for journal balance, invoice posting and immutable snapshot totals; this report does not repair or rewrite records.","basis":"period","kind":"statement","columns":[{"key":"entry_date","label":"Entry Date","type":"date","total":false,"width":150},{"key":"check_name","label":"Check Name","type":"text","total":false,"width":240},{"key":"source_reference","label":"Source Reference","type":"text","total":false,"width":150},{"key":"source_type","label":"Source Type","type":"text","total":false,"width":150},{"key":"expected","label":"Expected","type":"money","total":false,"width":150},{"key":"actual","label":"Actual","type":"money","total":false,"width":150},{"key":"difference","label":"Difference","type":"money","total":false,"width":150},{"key":"result","label":"Result","type":"text","total":false,"width":150},{"key":"description","label":"Description","type":"text","total":false,"width":240}]},{"key":"load_register","title":"Material Load Register","category":"Material Yard","description":"Saved load, vehicle, driver, trip, delivery, expenses, payments and invoice evidence. The range selects load dates; delivery/payment states are current.","basis":"period_current","kind":"table","columns":[{"key":"load_number","label":"Load Number","type":"text","total":false,"width":150},{"key":"load_date","label":"Load Date","type":"date","total":false,"width":150},{"key":"direction","label":"Direction","type":"text","total":false,"width":150},{"key":"product_name","label":"Product Name","type":"text","total":false,"width":240},{"key":"quantity","label":"Quantity","type":"number","total":false,"width":150},{"key":"unit_code","label":"Unit Code","type":"text","total":false,"width":150},{"key":"vehicle_registration","label":"Vehicle Registration","type":"text","total":false,"width":150},{"key":"driver_name","label":"Driver Name","type":"text","total":false,"width":240},{"key":"source_name","label":"Source Name","type":"text","total":false,"width":240},{"key":"destination_name","label":"Destination Name","type":"text","total":false,"width":240},{"key":"status","label":"Status","type":"text","total":false,"width":150},{"key":"cost_total","label":"Cost Total","type":"money","total":true,"width":150},{"key":"customer_charge_total","label":"Customer Charge Total","type":"money","total":true,"width":150}]},{"key":"load_costs","title":"Load Expenses and Charges","category":"Material Yard","description":"All saved load costs, customer charges and payment evidence. Monthly salary allocations are identified and do not repost payroll.","basis":"period_current","kind":"table","columns":[{"key":"load_number","label":"Load Number","type":"text","total":false,"width":150},{"key":"load_date","label":"Load Date","type":"date","total":false,"width":150},{"key":"cost_kind","label":"Cost Kind","type":"text","total":false,"width":150},{"key":"description","label":"Description","type":"text","total":false,"width":240},{"key":"payee","label":"Payee","type":"text","total":false,"width":150},{"key":"staff_mode","label":"Staff Mode","type":"text","total":false,"width":150},{"key":"quantity","label":"Quantity","type":"number","total":false,"width":150},{"key":"rate","label":"Rate","type":"money","total":false,"width":150},{"key":"amount","label":"Amount","type":"money","total":true,"width":150},{"key":"bill_amount","label":"Bill Amount","type":"money","total":true,"width":150},{"key":"paid_amount","label":"Paid Amount","type":"money","total":true,"width":150},{"key":"outstanding","label":"Outstanding","type":"money","total":true,"width":150},{"key":"status","label":"Status","type":"text","total":false,"width":150}]},{"key":"load_payments","title":"Load Cost Payments","category":"Material Yard","description":"External cost payments and Staff wage allocations in the selected payment period, with journal and advance linkage.","basis":"period","kind":"table","columns":[{"key":"payment_date","label":"Payment Date","type":"date","total":false,"width":150},{"key":"load_number","label":"Load Number","type":"text","total":false,"width":150},{"key":"payee","label":"Payee","type":"text","total":false,"width":150},{"key":"cost_description","label":"Cost Description","type":"text","total":false,"width":240},{"key":"payment_method","label":"Payment Method","type":"text","total":false,"width":150},{"key":"amount","label":"Amount","type":"money","total":true,"width":150},{"key":"reference","label":"Reference","type":"text","total":false,"width":150},{"key":"payment_source","label":"Payment Source","type":"text","total":false,"width":150},{"key":"notes","label":"Notes","type":"text","total":false,"width":150}]},{"key":"load_delivery","title":"Driver and Delivery Records","category":"Material Yard","description":"Latest saved delivery locations, driver details, timestamps, odometer, GPS and proof references for the selected load dates.","basis":"period_current","kind":"table","columns":[{"key":"load_number","label":"Load Number","type":"text","total":false,"width":150},{"key":"load_date","label":"Load Date","type":"date","total":false,"width":150},{"key":"vehicle_registration","label":"Vehicle Registration","type":"text","total":false,"width":150},{"key":"driver_name","label":"Driver Name","type":"text","total":false,"width":240},{"key":"driver_contact_phone","label":"Driver Contact Phone","type":"text","total":false,"width":150},{"key":"source_name","label":"Source Name","type":"text","total":false,"width":240},{"key":"destination_name","label":"Destination Name","type":"text","total":false,"width":240},{"key":"delivery_address","label":"Delivery Address","type":"text","total":false,"width":240},{"key":"dispatch_at","label":"Dispatch At","type":"datetime","total":false,"width":150},{"key":"delivered_at","label":"Delivered At","type":"datetime","total":false,"width":150},{"key":"received_by","label":"Received By","type":"text","total":false,"width":150},{"key":"proof_reference","label":"Proof Reference","type":"text","total":false,"width":150}]},{"key":"staff_balances","title":"Staff Wage and Advance Balances","category":"Staff","description":"Staff payable and advance ledger balances through the To date, with period earnings/payments and saved profile evidence.","basis":"as_of","kind":"table","columns":[{"key":"staff_code","label":"Staff Code","type":"text","total":false,"width":150},{"key":"name","label":"Name","type":"text","total":false,"width":240},{"key":"job_role","label":"Job Role","type":"text","total":false,"width":150},{"key":"wage_basis","label":"Wage Basis","type":"text","total":false,"width":150},{"key":"base_rate","label":"Base Rate","type":"money","total":false,"width":150},{"key":"opening_payable","label":"Opening Payable","type":"money","total":true,"width":150},{"key":"period_earned","label":"Period Earned","type":"money","total":true,"width":150},{"key":"period_paid","label":"Period Paid","type":"money","total":true,"width":150},{"key":"outstanding","label":"Outstanding","type":"money","total":true,"width":150},{"key":"advance_balance","label":"Advance Balance","type":"money","total":true,"width":150}]},{"key":"staff_attendance","title":"Staff Attendance","category":"Staff","description":"Saved attendance, working hours, overtime and notes.","basis":"period","kind":"table","columns":[{"key":"work_date","label":"Work Date","type":"date","total":false,"width":150},{"key":"staff_name","label":"Staff Name","type":"text","total":false,"width":240},{"key":"status","label":"Status","type":"text","total":false,"width":150},{"key":"hours","label":"Hours","type":"number","total":true,"width":150},{"key":"overtime_hours","label":"Overtime Hours","type":"number","total":true,"width":150},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240},{"key":"notes","label":"Notes","type":"text","total":false,"width":150}]},{"key":"staff_earnings","title":"Staff Salary and Wages","category":"Staff","description":"Every posted payroll/wage earning and its payment allocations through the To date.","basis":"period","kind":"table","columns":[{"key":"earning_date","label":"Earning Date","type":"date","total":false,"width":150},{"key":"staff_name","label":"Staff Name","type":"text","total":false,"width":240},{"key":"kind","label":"Kind","type":"text","total":false,"width":150},{"key":"period_from","label":"Period From","type":"date","total":false,"width":150},{"key":"period_to","label":"Period To","type":"date","total":false,"width":150},{"key":"units","label":"Units","type":"number","total":false,"width":150},{"key":"rate","label":"Rate","type":"money","total":false,"width":150},{"key":"gross_amount","label":"Gross Amount","type":"money","total":true,"width":150},{"key":"allowances","label":"Allowances","type":"money","total":true,"width":150},{"key":"deductions","label":"Deductions","type":"money","total":true,"width":150},{"key":"amount","label":"Amount","type":"money","total":true,"width":150},{"key":"paid_amount","label":"Paid Amount","type":"money","total":true,"width":150},{"key":"outstanding","label":"Outstanding","type":"money","total":true,"width":150}]},{"key":"staff_payments","title":"Staff Payments and Advances","category":"Staff","description":"Saved Staff payment amounts, initial advance portions and all payroll/advance allocations.","basis":"period","kind":"table","columns":[{"key":"payment_date","label":"Payment Date","type":"date","total":false,"width":150},{"key":"staff_name","label":"Staff Name","type":"text","total":false,"width":240},{"key":"payee_snapshot","label":"Payee Snapshot","type":"text","total":false,"width":150},{"key":"payment_method","label":"Payment Method","type":"text","total":false,"width":150},{"key":"amount","label":"Amount","type":"money","total":true,"width":150},{"key":"advance_amount","label":"Advance Amount","type":"money","total":true,"width":150},{"key":"reference","label":"Reference","type":"text","total":false,"width":150},{"key":"location_name","label":"Location Name","type":"text","total":false,"width":240},{"key":"notes","label":"Notes","type":"text","total":false,"width":150}]},{"key":"salary_allocations","title":"Salary Allocated to Loads","category":"Staff","description":"Operational allocation of monthly salary to load cost. These amounts must not be added to posted payroll expenses.","basis":"period","kind":"table","columns":[{"key":"load_date","label":"Load Date","type":"date","total":false,"width":150},{"key":"load_number","label":"Load Number","type":"text","total":false,"width":150},{"key":"staff_name","label":"Staff Name","type":"text","total":false,"width":240},{"key":"description","label":"Description","type":"text","total":false,"width":240},{"key":"amount","label":"Amount","type":"money","total":true,"width":150},{"key":"staff_mode","label":"Staff Mode","type":"text","total":false,"width":150},{"key":"status","label":"Status","type":"text","total":false,"width":150}]},{"key":"transport_trips","title":"Unified Transport Trips","category":"Transport","description":"Unified saved trip links with underlying material load, service job, stock trip or logistics operation evidence.","basis":"period","kind":"table","columns":[{"key":"trip_number","label":"Trip Number","type":"text","total":false,"width":150},{"key":"trip_kind","label":"Trip Kind","type":"text","total":false,"width":150},{"key":"created_at","label":"Created At","type":"datetime","total":false,"width":150},{"key":"vehicle_registration","label":"Vehicle Registration","type":"text","total":false,"width":150},{"key":"driver_name","label":"Driver Name","type":"text","total":false,"width":240},{"key":"source_name","label":"Source Name","type":"text","total":false,"width":240},{"key":"destination_name","label":"Destination Name","type":"text","total":false,"width":240},{"key":"status","label":"Status","type":"text","total":false,"width":150},{"key":"load_number","label":"Load Number","type":"text","total":false,"width":150},{"key":"sale_number","label":"Sale Number","type":"text","total":false,"width":150},{"key":"purchase_number","label":"Purchase Number","type":"text","total":false,"width":150}]},{"key":"vehicle_profitability","title":"Vehicle Load Profitability","category":"Transport","description":"Tax-exclusive invoice sales and margin minus saved load costs for each vehicle. Salary allocations are operational cost attribution, not another accounting expense.","basis":"period","kind":"table","columns":[{"key":"vehicle_registration","label":"Vehicle Registration","type":"text","total":false,"width":150},{"key":"loads","label":"Loads","type":"number","total":true,"width":150},{"key":"invoiced_loads","label":"Invoiced Loads","type":"number","total":true,"width":150},{"key":"invoice_sales","label":"Invoice Sales","type":"money","total":true,"width":150},{"key":"invoice_cost","label":"Invoice Cost","type":"money","total":true,"width":150},{"key":"load_cost","label":"Load Cost","type":"money","total":true,"width":150},{"key":"gross_profit_after_load_cost","label":"Gross Profit After Load Cost","type":"money","total":true,"width":150}]}]'::jsonb$defs$;
create or replace function private.reports_scope_v631(t uuid,document_location uuid,requested uuid,required text default 'view')
returns boolean language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
 if auth.uid() is null or not private.erp_user_has_tenant_access(t) then return false;end if;
 if document_location is null then return requested is null and private.erp_user_is_owner(t);end if;
 if not exists(select 1 from public.business_locations where tenant_id=t and id=document_location) then return false;end if;
 return private.erp_document_scope_allowed(t,document_location,requested,required);
end $$;
-- Report access is checked before any dataset, grouping or search is evaluated.
create or replace function private.reports_assert_v631(t uuid,k text,l uuid)
returns void language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare category text;permission text;module text;begin
 if auth.uid() is null or not private.erp_user_has_tenant_access(t) or not private.erp_has_permission(t,'reports.view') then
 raise exception 'Reports permission and active business membership required' using errcode='42501';end if;
 select d->>'category' into category from jsonb_array_elements(private.reports_definitions_v631()) d where d->>'key'=k;
 if category is null then raise exception 'Unknown report: %',k using errcode='22023';end if;
 module:=case category when 'Sales' then 'sales' when 'Purchase' then 'purchases' when 'Inventory' then 'inventory' when 'Accounting' then 'accounting' when 'Material Yard' then 'aggregate_yard' when 'Staff' then 'staff' else null end;
 permission:=case category when 'Sales' then 'sales.view' when 'Purchase' then 'purchases.view' when 'Inventory' then 'inventory.view' when 'Accounting' then 'accounting.view' when 'Material Yard' then 'aggregate_yard.view' when 'Staff' then 'staff.view' else 'transport_service.view' end;
 if not private.erp_has_permission(t,permission) and not(category='Transport' and (private.erp_has_permission(t,'vehicle_logistics.view') or private.erp_has_permission(t,'logistics_operations.view'))) then raise exception 'Report permission required: %',permission using errcode='42501';end if;
 if module is not null and not exists(select 1 from public.tenant_modules where tenant_id=t and module_key=module and enabled) then raise exception 'Report module is disabled: %',module using errcode='42501';end if;
 if category='Transport' and not exists(select 1 from public.tenant_modules where tenant_id=t and module_key in('aggregate_yard','transport_service','vehicle_logistics','logistics_operations') and enabled) then raise exception 'Transport module is disabled' using errcode='42501';end if;
 if k='sales_summary' and not private.erp_has_permission(t,'accounting.view') then raise exception 'Accounting view required for ledger totals' using errcode='42501';end if;
 -- Reports with saved financial evidence require access to cost/profit fields.
 if category='Sales' and k not in('sales_payments','sales_by_payment_method','returns') and not private.erp_has_permission(t,'sales.view_profit') then raise exception 'Sales profit permission required for complete invoice evidence' using errcode='42501';end if;
 if category='Inventory' and true and not private.erp_has_permission(t,'inventory.view_cost') then raise exception 'Inventory cost permission required' using errcode='42501';end if;
 if category='Material Yard' or k='vehicle_profitability' or k='salary_allocations' then
  if not private.erp_has_permission(t,'aggregate_yard.view') or not private.erp_has_permission(t,'aggregate_yard.costs') or not exists(select 1 from public.tenant_modules where tenant_id=t and module_key='aggregate_yard' and enabled) then raise exception 'Material yard cost access required' using errcode='42501';end if;
 end if;
 if k in('load_register','load_costs','load_payments') and not private.erp_has_permission(t,'staff.view') then raise exception 'Staff view permission required for wage/payment evidence' using errcode='42501';end if;
 if l is not null then
  if not exists(select 1 from public.business_locations where tenant_id=t and id=l) or not private.reports_scope_v631(t,l,l,'view') then raise exception 'Report location access denied' using errcode='42501';end if;
 end if;
end $$;
create or replace function public.reports_center_catalog_v631(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare d jsonb;items jsonb:='[]';begin
 if auth.uid() is null or not private.erp_user_has_tenant_access(p_tenant_id) or not private.erp_has_permission(p_tenant_id,'reports.view') then raise exception 'Reports permission required' using errcode='42501';end if;
 for d in select value from jsonb_array_elements(private.reports_definitions_v631()) loop
  begin perform private.reports_assert_v631(p_tenant_id,d->>'key',null);items:=items||jsonb_build_array(d);exception when insufficient_privilege then null;end;
 end loop;
 return items;
end $$;
CREATE OR REPLACE FUNCTION private.reports_load_evidence_v631(t uuid, load uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare l public.aggregate_loads_v617%rowtype;result jsonb;
begin
 select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load;
 if not found then raise exception 'Load not found';end if;

 result:=jsonb_build_object('load',to_jsonb(l));
 return result||jsonb_build_object(
  'load_record',to_jsonb(l),
  'trip',coalesce((select to_jsonb(h) from public.transport_trip_hub_v611 h where h.tenant_id=t and h.material_load_id=load),'{}'::jsonb),
  'driver_current',coalesce((select to_jsonb(d) from public.logistics_drivers_v61 d where d.tenant_id=t and d.id=l.driver_id),'{}'::jsonb),
  'vehicle_current',coalesce((select to_jsonb(v)||jsonb_build_object('yard_profile',(select to_jsonb(p) from public.aggregate_vehicle_profiles_v617 p where p.tenant_id=t and p.vehicle_id=v.id)) from public.service_vehicles v where v.tenant_id=t and v.id=l.vehicle_id),'{}'::jsonb),
  'load_events',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at,e.id) from public.aggregate_load_events_v617 e where e.tenant_id=t and e.load_id=load),'[]'::jsonb),
  'location_name',(select name from public.business_locations where tenant_id=t and id=l.location_id),
  'legacy_freight_payments',coalesce((select jsonb_agg(to_jsonb(f) order by f.settled_at) from public.aggregate_freight_settlements_v620 f where f.tenant_id=t and f.load_id=load),'[]'::jsonb),
  'sale',coalesce((select to_jsonb(s) from public.sales s where s.tenant_id=t and s.id=l.sale_id),'{}'::jsonb),
  'customer_payments',coalesce((select jsonb_agg(to_jsonb(p)) from public.sale_payments p where p.tenant_id=t and p.sale_id=l.sale_id),'[]'::jsonb),
  'delivery',coalesce((select details from public.material_load_delivery_v630 where tenant_id=t and load_id=load),'{}'::jsonb),
  'costs',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('paid_amount',coalesce(private.load_cost_paid_v630(c.id),0),'outstanding',case when c.staff_mode='salary_allocation' or c.status<>'posted' then 0 else c.amount-coalesce(private.load_cost_paid_v630(c.id),0) end,'billing_service',(select p.name from public.product_variants v join public.products p on p.id=v.product_id and p.tenant_id=v.tenant_id where v.id=c.billing_variant_id and v.tenant_id=t)) order by c.created_at,c.id) from public.material_load_costs_v630 c where c.tenant_id=t and c.load_id=load),'[]'::jsonb),
  'cost_payments',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('cost_description',c.description,'payee',c.payee) order by p.payment_date,p.created_at) from public.material_load_cost_payments_v630 p join public.material_load_costs_v630 c on c.id=p.cost_id and c.tenant_id=p.tenant_id where c.tenant_id=t and c.load_id=load),'[]'::jsonb),
  'staff_payments',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'payment_date',p.payment_date,'amount',a.amount,'payment_method',p.payment_method,'reference',p.reference,'payee',p.payee_snapshot,'cost_id',c.id,'cost_description',c.description,'from_advance',a.from_advance,'journal_id',a.journal_id,'notes',p.notes) order by p.payment_date,p.created_at) from public.material_load_costs_v630 c join public.staff_payment_allocations_v630 a on a.earning_id=c.staff_earning_id join public.staff_payments_v630 p on p.id=a.payment_id and p.tenant_id=c.tenant_id where c.tenant_id=t and c.load_id=load),'[]'::jsonb),
  'cost_total',coalesce((select sum(amount) from public.material_load_costs_v630 where tenant_id=t and load_id=load and status<>'void'),0),
  'customer_charge_total',coalesce((select sum(bill_amount) from public.material_load_costs_v630 where tenant_id=t and load_id=load and status<>'void'),0),
  'history',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at) from public.workforce_audit_v630 a where a.tenant_id=t and a.load_id=load),'[]'::jsonb)
 );
end $function$;
revoke all on function private.reports_load_evidence_v631(uuid,uuid) from public,anon,authenticated;
create or replace function private.reports_rows_v631(t uuid,k text,f date,z date,l uuid)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $body$
declare sql text;rec jsonb;begin
 case k
when 'sales_register' then sql:=$q$select to_jsonb(result) from (
 select s.*,bl.name location_name,private.v500_document_location($1,'sale',s.id) location_id,coalesce((select sum(x.amount) from public.sale_payments x where x.tenant_id=$1 and x.sale_id=s.id and (x.paid_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date<=$3),0) paid_as_of,
 greatest(s.grand_total-coalesce((select sum(x.amount) from public.sale_payments x where x.tenant_id=$1 and x.sale_id=s.id and (x.paid_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date<=$3),0)-coalesce((select sum(r.grand_total) from public.sales_returns r where r.tenant_id=$1 and r.sale_id=s.id and r.return_date<=$3 and r.refund_status<>'waived' and private.reports_scope_v631($1,r.location_id,$4,'view')),0),0) outstanding,
 coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at,x.id) from public.sale_items x where x.tenant_id=$1 and x.sale_id=s.id),'[]'::jsonb) saved_items,
 coalesce((select jsonb_agg(to_jsonb(x) order by x.paid_at,x.id) from public.sale_payments x where x.tenant_id=$1 and x.sale_id=s.id and (x.paid_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date<=$3),'[]'::jsonb) payments_through_to,
 (select to_jsonb(g)||jsonb_build_object('lines',(select jsonb_agg(to_jsonb(gl) order by gl.line_no) from public.gst_document_line_snapshots_v520 gl where gl.tenant_id=$1 and gl.snapshot_id=g.id)) from public.gst_document_snapshots_v520 g where g.tenant_id=$1 and g.source_type='sale' and g.source_id=s.id) gst_snapshot,
 coalesce((select jsonb_agg(to_jsonb(r) order by r.return_date,r.id) from public.sales_returns r where r.tenant_id=$1 and r.sale_id=s.id and r.return_date<=$3 and r.refund_status<>'waived' and private.reports_scope_v631($1,r.location_id,$4,'view')),'[]'::jsonb) returns_through_to
 , (select evidence from public.material_load_sale_snapshots_v630 where tenant_id=$1 and sale_id=s.id and private.erp_has_permission($1,'aggregate_yard.costs') and private.erp_has_permission($1,'staff.view')) saved_load_invoice
 from public.sales s left join public.business_locations bl on bl.tenant_id=$1 and bl.id=private.v500_document_location($1,'sale',s.id)
 where s.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'sale',s.id),$4,'view') and coalesce(s.status,'') not in('draft','void','cancelled') and s.sale_date between $2 and $3 order by s.sale_date desc,s.sale_number,s.id
 ) result$q$;
when 'sales_items' then sql:=$q$select to_jsonb(result) from (
 select i.id,i.sale_id,s.sale_number,s.sale_date,s.customer_id,s.customer_name,
 coalesce(g.product_name,i.product_name) product_name,i.sku,i.unit_code,i.quantity,
 i.unit_price,i.discount_amount,i.taxable_amount,i.tax_amount,i.line_total,
 private.v500_document_location($1,'sale',s.id) location_id,bl.name location_name,to_jsonb(i) saved_line,to_jsonb(g) gst_line
 from public.sale_items i join public.sales s on s.id=i.sale_id and s.tenant_id=i.tenant_id
 left join public.gst_document_snapshots_v520 gs on gs.tenant_id=$1 and gs.source_type='sale' and gs.source_id=s.id
 left join lateral(select g.* from public.gst_document_line_snapshots_v520 g where g.tenant_id=$1 and g.snapshot_id=gs.id and g.source_line_id=i.id order by g.line_no limit 1) g on true
 left join public.business_locations bl on bl.tenant_id=$1 and bl.id=private.v500_document_location($1,'sale',s.id)
 where s.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'sale',s.id),$4,'view') and coalesce(s.status,'') not in('draft','void','cancelled') and s.sale_date between $2 and $3 order by s.sale_date desc,s.sale_number,i.created_at,i.id
 ) result$q$;
when 'sales_payments' then sql:=$q$select to_jsonb(result) from (
 select x.*,s.sale_number,s.customer_name,s.customer_id,private.v500_document_location($1,'sale',s.id) location_id,bl.name location_name
 from public.sale_payments x join public.sales s on s.id=x.sale_id and s.tenant_id=x.tenant_id
 left join public.business_locations bl on bl.tenant_id=$1 and bl.id=private.v500_document_location($1,'sale',s.id)
 where s.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'sale',s.id),$4,'view') and x.tenant_id=$1 and (x.paid_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date between $2 and $3
 order by x.paid_at desc,x.id
 ) result$q$;
when 'purchase_register' then sql:=$q$select to_jsonb(result) from (
 select p.*,bl.name location_name,private.v500_document_location($1,'purchase',p.id) location_id,coalesce((select sum(x.amount) from public.purchase_payments x where x.tenant_id=$1 and x.purchase_id=p.id and (x.paid_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date<=$3),0) paid_as_of,
 greatest(p.grand_total-coalesce((select sum(x.amount) from public.purchase_payments x where x.tenant_id=$1 and x.purchase_id=p.id and (x.paid_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date<=$3),0)-coalesce((select sum(r.grand_total) from public.purchase_returns r where r.tenant_id=$1 and r.purchase_id=p.id and r.return_date<=$3 and r.credit_status<>'waived' and private.reports_scope_v631($1,r.location_id,$4,'view')),0),0) outstanding,
 coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at,x.id) from public.purchase_items x where x.tenant_id=$1 and x.purchase_id=p.id),'[]'::jsonb) saved_items,
 coalesce((select jsonb_agg(to_jsonb(x) order by x.paid_at,x.id) from public.purchase_payments x where x.tenant_id=$1 and x.purchase_id=p.id and (x.paid_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date<=$3),'[]'::jsonb) payments_through_to,
 (select to_jsonb(g)||jsonb_build_object('lines',(select jsonb_agg(to_jsonb(gl) order by gl.line_no) from public.gst_document_line_snapshots_v520 gl where gl.tenant_id=$1 and gl.snapshot_id=g.id)) from public.gst_document_snapshots_v520 g where g.tenant_id=$1 and g.source_type='purchase' and g.source_id=p.id) gst_snapshot,
 coalesce((select jsonb_agg(to_jsonb(r) order by r.return_date,r.id) from public.purchase_returns r where r.tenant_id=$1 and r.purchase_id=p.id and r.return_date<=$3 and r.credit_status<>'waived' and private.reports_scope_v631($1,r.location_id,$4,'view')),'[]'::jsonb) returns_through_to
 
 from public.purchases p left join public.business_locations bl on bl.tenant_id=$1 and bl.id=private.v500_document_location($1,'purchase',p.id)
 where p.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'purchase',p.id),$4,'view') and coalesce(p.status,'') not in('draft','void','cancelled') and p.purchase_date between $2 and $3 order by p.purchase_date desc,p.purchase_number,p.id
 ) result$q$;
when 'purchase_items' then sql:=$q$select to_jsonb(result) from (
 select i.id,i.purchase_id,p.purchase_number,p.purchase_date,p.supplier_id,p.supplier_name,
 coalesce(g.product_name,i.product_name) product_name,i.sku,i.unit_code,i.quantity,
 i.unit_cost,i.discount_amount,i.taxable_amount,i.tax_amount,i.line_total,
 private.v500_document_location($1,'purchase',p.id) location_id,bl.name location_name,to_jsonb(i) saved_line,to_jsonb(g) gst_line
 from public.purchase_items i join public.purchases p on p.id=i.purchase_id and p.tenant_id=i.tenant_id
 left join public.gst_document_snapshots_v520 gs on gs.tenant_id=$1 and gs.source_type='purchase' and gs.source_id=p.id
 left join lateral(select g.* from public.gst_document_line_snapshots_v520 g where g.tenant_id=$1 and g.snapshot_id=gs.id and g.source_line_id=i.id order by g.line_no limit 1) g on true
 left join public.business_locations bl on bl.tenant_id=$1 and bl.id=private.v500_document_location($1,'purchase',p.id)
 where p.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'purchase',p.id),$4,'view') and coalesce(p.status,'') not in('draft','void','cancelled') and p.purchase_date between $2 and $3 order by p.purchase_date desc,p.purchase_number,i.created_at,i.id
 ) result$q$;
when 'purchase_payments' then sql:=$q$select to_jsonb(result) from (
 select x.*,p.purchase_number,p.supplier_name,p.supplier_id,private.v500_document_location($1,'purchase',p.id) location_id,bl.name location_name
 from public.purchase_payments x join public.purchases p on p.id=x.purchase_id and p.tenant_id=x.tenant_id
 left join public.business_locations bl on bl.tenant_id=$1 and bl.id=private.v500_document_location($1,'purchase',p.id)
 where p.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'purchase',p.id),$4,'view') and x.tenant_id=$1 and (x.paid_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date between $2 and $3
 order by x.paid_at desc,x.id
 ) result$q$;
when 'sales_by_product' then sql:=$q$select to_jsonb(result) from (select i.variant_id,coalesce(g.product_name,i.product_name) product_name,i.sku,i.unit_code,
 sum(i.quantity) quantity,sum(i.taxable_amount) taxable_sales,sum(i.tax_amount) tax,sum(i.line_total) total,sum(i.gross_profit) gross_profit
 from public.sale_items i join public.sales s on s.id=i.sale_id and s.tenant_id=i.tenant_id
 left join public.gst_document_snapshots_v520 gs on gs.tenant_id=$1 and gs.source_type='sale' and gs.source_id=s.id
 left join lateral(select product_name from public.gst_document_line_snapshots_v520 where tenant_id=$1 and snapshot_id=gs.id and source_line_id=i.id order by line_no limit 1) g on true
 where s.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'sale',s.id),$4,'view') and coalesce(s.status,'') not in('draft','void','cancelled') and s.sale_date between $2 and $3 group by i.variant_id,coalesce(g.product_name,i.product_name),i.sku,i.unit_code order by total desc,product_name) result$q$;
when 'sales_by_customer' then sql:=$q$select to_jsonb(result) from (select coalesce(s.customer_name,'Unspecified') customer_name,s.customer_id group_id,count(*) invoices,sum(s.taxable_total) taxable_sales,
 sum(s.tax_total) tax,sum(s.grand_total) total,sum(s.gross_profit) gross_profit
 from public.sales s left join public.document_origins o on o.tenant_id=$1 and o.entity_type='sale' and o.entity_id=s.id
 left join public.business_locations bl on bl.tenant_id=$1 and bl.id=o.location_id
 where s.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'sale',s.id),$4,'view') and coalesce(s.status,'') not in('draft','void','cancelled') and s.sale_date between $2 and $3 group by coalesce(s.customer_name,'Unspecified'),s.customer_id order by total desc,customer_name) result$q$;
when 'sales_by_salesperson' then sql:=$q$select to_jsonb(result) from (select coalesce(s.created_by::text,'Unrecorded') recorded_by,s.created_by group_id,count(*) invoices,sum(s.taxable_total) taxable_sales,
 sum(s.tax_total) tax,sum(s.grand_total) total,sum(s.gross_profit) gross_profit
 from public.sales s left join public.document_origins o on o.tenant_id=$1 and o.entity_type='sale' and o.entity_id=s.id
 left join public.business_locations bl on bl.tenant_id=$1 and bl.id=o.location_id
 where s.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'sale',s.id),$4,'view') and coalesce(s.status,'') not in('draft','void','cancelled') and s.sale_date between $2 and $3 group by coalesce(s.created_by::text,'Unrecorded'),s.created_by order by total desc,recorded_by) result$q$;
when 'sales_by_store' then sql:=$q$select to_jsonb(result) from (select coalesce(bl.name,'Unassigned') location_name,private.v500_document_location($1,'sale',s.id) group_id,count(*) invoices,sum(s.taxable_total) taxable_sales,
 sum(s.tax_total) tax,sum(s.grand_total) total,sum(s.gross_profit) gross_profit
 from public.sales s left join public.document_origins o on o.tenant_id=$1 and o.entity_type='sale' and o.entity_id=s.id
 left join public.business_locations bl on bl.tenant_id=$1 and bl.id=o.location_id
 where s.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'sale',s.id),$4,'view') and coalesce(s.status,'') not in('draft','void','cancelled') and s.sale_date between $2 and $3 group by coalesce(bl.name,'Unassigned'),private.v500_document_location($1,'sale',s.id) order by total desc,location_name) result$q$;
when 'sales_by_pos' then sql:=$q$select to_jsonb(result) from (select coalesce(o.device_id::text,'No recorded POS terminal') terminal,o.device_id group_id,count(*) invoices,sum(s.taxable_total) taxable_sales,
 sum(s.tax_total) tax,sum(s.grand_total) total,sum(s.gross_profit) gross_profit
 from public.sales s left join public.document_origins o on o.tenant_id=$1 and o.entity_type='sale' and o.entity_id=s.id
 left join public.business_locations bl on bl.tenant_id=$1 and bl.id=o.location_id
 where s.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'sale',s.id),$4,'view') and coalesce(s.status,'') not in('draft','void','cancelled') and s.sale_date between $2 and $3 group by coalesce(o.device_id::text,'No recorded POS terminal'),o.device_id order by total desc,terminal) result$q$;
when 'sales_by_payment_method' then sql:=$q$select to_jsonb(result) from (select coalesce(x.payment_method,'Unspecified') payment_method,count(*) payment_count,sum(x.amount) amount
 from public.sale_payments x join public.sales s on s.id=x.sale_id and s.tenant_id=x.tenant_id
 where s.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'sale',s.id),$4,'view') and x.tenant_id=$1 and (x.paid_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date between $2 and $3
 group by x.payment_method order by amount desc,payment_method) result$q$;
when 'supplier_purchase' then sql:=$q$select to_jsonb(result) from (select p.supplier_id,p.supplier_name,count(*) bills,sum(p.taxable_total) taxable_purchases,sum(p.tax_total) tax,sum(p.grand_total) total
 from public.purchases p where p.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'purchase',p.id),$4,'view') and coalesce(p.status,'') not in('draft','void','cancelled') and p.purchase_date between $2 and $3 group by p.supplier_id,p.supplier_name order by total desc,p.supplier_name) result$q$;
when 'supplier_performance' then sql:=$q$select to_jsonb(result) from (with bills as(select p.*,
 coalesce((select sum(x.amount) from public.purchase_payments x where x.tenant_id=$1 and x.purchase_id=p.id and (x.paid_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date<=$3),0) paid,
 coalesce((select sum(r.grand_total) from public.purchase_returns r where r.tenant_id=$1 and r.purchase_id=p.id and r.return_date<=$3 and r.credit_status<>'waived' and private.reports_scope_v631($1,r.location_id,$4,'view')),0) returned
 from public.purchases p where p.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'purchase',p.id),$4,'view') and coalesce(p.status,'') not in('draft','void','cancelled') and p.purchase_date between $2 and $3)
 select supplier_id,supplier_name,count(*) bills,sum(grand_total) total,sum(paid) paid_as_of,
 sum(greatest(grand_total-paid-returned,0)) outstanding,
 count(*) filter(where due_date<$3 and grand_total-paid-returned>0.005) overdue_bills,sum(returned) returns_total
 from bills group by supplier_id,supplier_name order by outstanding desc,supplier_name) result$q$;
when 'price_history' then sql:=$q$select to_jsonb(result) from (select i.*,p.purchase_date,p.purchase_number,p.supplier_name,p.supplier_id,
 private.v500_document_location($1,'purchase',p.id) location_id,bl.name location_name
 from public.purchase_items i join public.purchases p on p.id=i.purchase_id and p.tenant_id=i.tenant_id
 left join public.business_locations bl on bl.tenant_id=$1 and bl.id=private.v500_document_location($1,'purchase',p.id)
 where p.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'purchase',p.id),$4,'view') and coalesce(p.status,'') not in('draft','void','cancelled') and p.purchase_date between $2 and $3 order by p.purchase_date desc,i.created_at desc,i.id) result$q$;
when 'returns' then sql:=$q$select to_jsonb(result) from (select x->>'return_number' return_number,(x->>'return_date')::date return_date,x->>'source_number' source_number,
 x->>'party_name' party_name,x->>'product_name' product_name,x->>'unit_code' unit_code,(x->>'quantity')::numeric quantity,
 (x->>'taxable_amount')::numeric taxable_amount,(x->>'tax_amount')::numeric tax_amount,(x->>'line_total')::numeric line_total,
 x->>'settlement_status' settlement_status,x->>'reason' reason,x saved_return
 from private.reports_returns_rows_v631($1,'sales',$2,$3,$4,'',2147483647) x
 where private.reports_scope_v631($1,(x->>'location_id')::uuid,$4,'view')) result$q$;
when 'purchase_returns' then sql:=$q$select to_jsonb(result) from (select x->>'return_number' return_number,(x->>'return_date')::date return_date,x->>'source_number' source_number,
 x->>'party_name' party_name,x->>'product_name' product_name,x->>'unit_code' unit_code,(x->>'quantity')::numeric quantity,
 (x->>'taxable_amount')::numeric taxable_amount,(x->>'tax_amount')::numeric tax_amount,(x->>'line_total')::numeric line_total,
 x->>'settlement_status' settlement_status,x->>'reason' reason,x saved_return
 from private.reports_returns_rows_v631($1,'purchase',$2,$3,$4,'',2147483647) x
 where private.reports_scope_v631($1,(x->>'location_id')::uuid,$4,'view')) result$q$;
when 'current_stock' then sql:=$q$select to_jsonb(result) from (select x.*,case when last_purchase_date is null then null else current_date-last_purchase_date end days_since_purchase
 from private.reports_inventory_rows_v631($1,$4,greatest(1,least($3-$2+1,365)),'',2147483647) x ) result$q$;
when 'stock_valuation' then sql:=$q$select to_jsonb(result) from (select x.*,case when last_purchase_date is null then null else current_date-last_purchase_date end days_since_purchase
 from private.reports_inventory_rows_v631($1,$4,greatest(1,least($3-$2+1,365)),'',2147483647) x ) result$q$;
when 'stock_aging' then sql:=$q$select to_jsonb(result) from (select x.*,case when last_purchase_date is null then null else current_date-last_purchase_date end days_since_purchase
 from private.reports_inventory_rows_v631($1,$4,greatest(1,least($3-$2+1,365)),'',2147483647) x ) result$q$;
when 'low_stock' then sql:=$q$select to_jsonb(result) from (select x.*,case when last_purchase_date is null then null else current_date-last_purchase_date end days_since_purchase
 from private.reports_inventory_rows_v631($1,$4,greatest(1,least($3-$2+1,365)),'',2147483647) x where x.status in('low_stock','out_of_stock')) result$q$;
when 'dead_stock' then sql:=$q$select to_jsonb(result) from (select x.*,case when last_purchase_date is null then null else current_date-last_purchase_date end days_since_purchase
 from private.reports_inventory_rows_v631($1,$4,greatest(1,least($3-$2+1,365)),'',2147483647) x where x.status='dead_stock') result$q$;
when 'stock_movement' then sql:=$q$select to_jsonb(result) from (select m.*,p.name product_name,v.sku,l.name location_name
 from public.location_stock_movements m join public.product_variants v on v.id=m.variant_id and v.tenant_id=m.tenant_id
 join public.products p on p.id=v.product_id and p.tenant_id=v.tenant_id
 left join public.business_locations l on l.id=m.location_id and l.tenant_id=m.tenant_id
 where m.tenant_id=$1 and private.reports_scope_v631($1,m.location_id,$4,'view') and (m.created_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date between $2 and $3 order by m.created_at desc,m.id) result$q$;
when 'batches' then sql:=$q$select to_jsonb(result) from (select b.*,v.sku,p.name product_name,x.location_id,l.name location_name,x.quantity,x.reserved_quantity,x.damaged_quantity
 from public.inventory_batch_balances_v483 x join public.inventory_batches_v483 b on b.id=x.batch_id and b.tenant_id=x.tenant_id
 join public.product_variants v on v.id=b.variant_id and v.tenant_id=b.tenant_id join public.products p on p.id=v.product_id and p.tenant_id=v.tenant_id
 left join public.business_locations l on l.id=x.location_id and l.tenant_id=x.tenant_id
 where x.tenant_id=$1 and private.reports_scope_v631($1,x.location_id,$4,'view') 
 order by b.expiry_on nulls last,b.batch_number,x.location_id) result$q$;
when 'expiry' then sql:=$q$select to_jsonb(result) from (select b.*,v.sku,p.name product_name,x.location_id,l.name location_name,x.quantity,x.reserved_quantity,x.damaged_quantity
 from public.inventory_batch_balances_v483 x join public.inventory_batches_v483 b on b.id=x.batch_id and b.tenant_id=x.tenant_id
 join public.product_variants v on v.id=b.variant_id and v.tenant_id=b.tenant_id join public.products p on p.id=v.product_id and p.tenant_id=v.tenant_id
 left join public.business_locations l on l.id=x.location_id and l.tenant_id=x.tenant_id
 where x.tenant_id=$1 and private.reports_scope_v631($1,x.location_id,$4,'view') and x.quantity<>0 and b.expiry_on between $2 and $3
 order by b.expiry_on nulls last,b.batch_number,x.location_id) result$q$;
when 'serials' then sql:=$q$select to_jsonb(result) from (select x.*,x.current_location_id location_id,v.sku,p.name product_name,l.name location_name
 from public.inventory_serials_v483 x join public.product_variants v on v.id=x.variant_id and v.tenant_id=x.tenant_id
 join public.products p on p.id=v.product_id and p.tenant_id=v.tenant_id left join public.business_locations l on l.id=x.current_location_id and l.tenant_id=x.tenant_id
 where x.tenant_id=$1 and private.reports_scope_v631($1,x.current_location_id,$4,'view') order by x.serial_number,x.id) result$q$;
when 'trial_balance' then sql:=$q$select to_jsonb(result) from (with lines as(select j.*,l.id line_id,l.account_id,l.debit,l.credit,l.party_type,l.party_id,l.description line_description,a.code,a.name account_name,a.account_type,a.system_key,
 coalesce(c.name,s.name,m.name,k.payee,l.party_id::text,'') party_name
 from public.journal_entries j join public.journal_lines l on l.journal_entry_id=j.id
 join public.accounting_accounts a on a.id=l.account_id and a.tenant_id=j.tenant_id
 left join public.customers c on c.tenant_id=$1 and c.id=l.party_id and l.party_type='customer'
 left join public.suppliers s on s.tenant_id=$1 and s.id=l.party_id and l.party_type='supplier'
 left join public.staff_members_v630 m on m.tenant_id=$1 and m.id=l.party_id and l.party_type='staff'
 left join public.material_load_costs_v630 k on k.tenant_id=$1 and k.id=l.party_id and l.party_type='load_cost'
 where j.tenant_id=$1 and private.reports_scope_v631($1,j.location_id,$4,'view') and j.status='posted' and j.entry_date<=$3) select account_id,code,account_name name,account_type,
 coalesce(sum(debit-credit) filter(where entry_date<$2),0) opening_balance,
 coalesce(sum(debit) filter(where entry_date>=$2),0) debit,coalesce(sum(credit) filter(where entry_date>=$2),0) credit,
 greatest(sum(debit-credit),0) closing_debit,greatest(sum(credit-debit),0) closing_credit
 from lines group by account_id,code,account_name,account_type order by code,account_id) result$q$;
when 'general_ledger' then sql:=$q$select to_jsonb(result) from (with lines as(select j.*,l.id line_id,l.account_id,l.debit,l.credit,l.party_type,l.party_id,l.description line_description,a.code,a.name account_name,a.account_type,a.system_key,
 coalesce(c.name,s.name,m.name,k.payee,l.party_id::text,'') party_name
 from public.journal_entries j join public.journal_lines l on l.journal_entry_id=j.id
 join public.accounting_accounts a on a.id=l.account_id and a.tenant_id=j.tenant_id
 left join public.customers c on c.tenant_id=$1 and c.id=l.party_id and l.party_type='customer'
 left join public.suppliers s on s.tenant_id=$1 and s.id=l.party_id and l.party_type='supplier'
 left join public.staff_members_v630 m on m.tenant_id=$1 and m.id=l.party_id and l.party_type='staff'
 left join public.material_load_costs_v630 k on k.tenant_id=$1 and k.id=l.party_id and l.party_type='load_cost'
 where j.tenant_id=$1 and private.reports_scope_v631($1,j.location_id,$4,'view') and j.status='posted' and j.entry_date<=$3), balances as(select *,
 coalesce(sum(debit-credit) filter(where entry_date<$2) over(partition by account_id),0) opening_balance,
 sum(debit-credit) over(partition by account_id order by entry_date,created_at,id,line_id rows unbounded preceding) running_balance
 from lines) select *,coalesce(line_description,description) line_detail from balances where entry_date>=$2 order by code,entry_date,created_at,id,line_id) result$q$;
when 'cash_flow' then sql:=$q$select to_jsonb(result) from (with lines as(select j.*,l.id line_id,l.account_id,l.debit,l.credit,l.party_type,l.party_id,l.description line_description,a.code,a.name account_name,a.account_type,a.system_key,
 coalesce(c.name,s.name,m.name,k.payee,l.party_id::text,'') party_name
 from public.journal_entries j join public.journal_lines l on l.journal_entry_id=j.id
 join public.accounting_accounts a on a.id=l.account_id and a.tenant_id=j.tenant_id
 left join public.customers c on c.tenant_id=$1 and c.id=l.party_id and l.party_type='customer'
 left join public.suppliers s on s.tenant_id=$1 and s.id=l.party_id and l.party_type='supplier'
 left join public.staff_members_v630 m on m.tenant_id=$1 and m.id=l.party_id and l.party_type='staff'
 left join public.material_load_costs_v630 k on k.tenant_id=$1 and k.id=l.party_id and l.party_type='load_cost'
 where j.tenant_id=$1 and private.reports_scope_v631($1,j.location_id,$4,'view') and j.status='posted' and j.entry_date<=$3) select account_id,code,account_name name,system_key,
 coalesce(sum(debit-credit) filter(where entry_date<$2),0) opening_balance,
 coalesce(sum(debit) filter(where entry_date>=$2),0) inflow,coalesce(sum(credit) filter(where entry_date>=$2),0) outflow,
 coalesce(sum(debit-credit) filter(where entry_date>=$2),0) net_change,sum(debit-credit) closing_balance
 from lines where system_key in('cash','bank','upi','card') or account_id in(select account_id from public.accounting_account_mappings where tenant_id=$1 and mapping_key in('payment.cash','payment.bank','payment.upi','payment.card'))
 group by account_id,code,account_name,system_key order by code,account_id) result$q$;
when 'receivables' then sql:=$q$select to_jsonb(result) from (with lines as(select j.*,l.id line_id,l.account_id,l.debit,l.credit,l.party_type,l.party_id,l.description line_description,a.code,a.name account_name,a.account_type,a.system_key,
 coalesce(c.name,s.name,m.name,k.payee,l.party_id::text,'') party_name
 from public.journal_entries j join public.journal_lines l on l.journal_entry_id=j.id
 join public.accounting_accounts a on a.id=l.account_id and a.tenant_id=j.tenant_id
 left join public.customers c on c.tenant_id=$1 and c.id=l.party_id and l.party_type='customer'
 left join public.suppliers s on s.tenant_id=$1 and s.id=l.party_id and l.party_type='supplier'
 left join public.staff_members_v630 m on m.tenant_id=$1 and m.id=l.party_id and l.party_type='staff'
 left join public.material_load_costs_v630 k on k.tenant_id=$1 and k.id=l.party_id and l.party_type='load_cost'
 where j.tenant_id=$1 and private.reports_scope_v631($1,j.location_id,$4,'view') and j.status='posted' and j.entry_date<=$3), balances as(select party_type,party_id,party_name,
 coalesce(sum(debit-credit) filter(where entry_date<$2),0) opening_balance,
 coalesce(sum(debit) filter(where entry_date>=$2),0) debits,coalesce(sum(credit) filter(where entry_date>=$2),0) credits,sum(debit-credit) balance
 from lines where system_key='accounts_receivable' group by party_type,party_id,party_name)
 select *,greatest(balance,0) outstanding,greatest(-balance,0) advance_balance from balances where abs(balance)>0.0001 or abs(debits)+abs(credits)>0.0001 order by outstanding desc,party_name,party_id) result$q$;
when 'payables' then sql:=$q$select to_jsonb(result) from (with lines as(select j.*,l.id line_id,l.account_id,l.debit,l.credit,l.party_type,l.party_id,l.description line_description,a.code,a.name account_name,a.account_type,a.system_key,
 coalesce(c.name,s.name,m.name,k.payee,l.party_id::text,'') party_name
 from public.journal_entries j join public.journal_lines l on l.journal_entry_id=j.id
 join public.accounting_accounts a on a.id=l.account_id and a.tenant_id=j.tenant_id
 left join public.customers c on c.tenant_id=$1 and c.id=l.party_id and l.party_type='customer'
 left join public.suppliers s on s.tenant_id=$1 and s.id=l.party_id and l.party_type='supplier'
 left join public.staff_members_v630 m on m.tenant_id=$1 and m.id=l.party_id and l.party_type='staff'
 left join public.material_load_costs_v630 k on k.tenant_id=$1 and k.id=l.party_id and l.party_type='load_cost'
 where j.tenant_id=$1 and private.reports_scope_v631($1,j.location_id,$4,'view') and j.status='posted' and j.entry_date<=$3), balances as(select party_type,party_id,party_name,
 coalesce(sum(credit-debit) filter(where entry_date<$2),0) opening_balance,
 coalesce(sum(debit) filter(where entry_date>=$2),0) debits,coalesce(sum(credit) filter(where entry_date>=$2),0) credits,sum(credit-debit) balance
 from lines where system_key in('accounts_payable','staff_payable_v630','load_costs_payable_v630') group by party_type,party_id,party_name)
 select *,greatest(balance,0) outstanding,greatest(-balance,0) advance_balance from balances where abs(balance)>0.0001 or abs(debits)+abs(credits)>0.0001 order by outstanding desc,party_name,party_id) result$q$;
when 'supplier_outstanding' then sql:=$q$select to_jsonb(result) from (with lines as(select j.*,l.id line_id,l.account_id,l.debit,l.credit,l.party_type,l.party_id,l.description line_description,a.code,a.name account_name,a.account_type,a.system_key,
 coalesce(c.name,s.name,m.name,k.payee,l.party_id::text,'') party_name
 from public.journal_entries j join public.journal_lines l on l.journal_entry_id=j.id
 join public.accounting_accounts a on a.id=l.account_id and a.tenant_id=j.tenant_id
 left join public.customers c on c.tenant_id=$1 and c.id=l.party_id and l.party_type='customer'
 left join public.suppliers s on s.tenant_id=$1 and s.id=l.party_id and l.party_type='supplier'
 left join public.staff_members_v630 m on m.tenant_id=$1 and m.id=l.party_id and l.party_type='staff'
 left join public.material_load_costs_v630 k on k.tenant_id=$1 and k.id=l.party_id and l.party_type='load_cost'
 where j.tenant_id=$1 and private.reports_scope_v631($1,j.location_id,$4,'view') and j.status='posted' and j.entry_date<=$3), balances as(select party_type,party_id,party_name,
 coalesce(sum(credit-debit) filter(where entry_date<$2),0) opening_balance,
 coalesce(sum(debit) filter(where entry_date>=$2),0) debits,coalesce(sum(credit) filter(where entry_date>=$2),0) credits,sum(credit-debit) balance
 from lines where system_key in('accounts_payable','staff_payable_v630','load_costs_payable_v630') and party_type='supplier' group by party_type,party_id,party_name)
 select *,greatest(balance,0) outstanding,greatest(-balance,0) advance_balance from balances where abs(balance)>0.0001 or abs(debits)+abs(credits)>0.0001 order by outstanding desc,party_name,party_id) result$q$;
when 'journal_register' then sql:=$q$select to_jsonb(result) from (select j.*,bl.name location_name,x.total_debit,x.total_credit,x.total_debit-x.total_credit difference,x.saved_lines
 from public.journal_entries j left join public.business_locations bl on bl.id=j.location_id and bl.tenant_id=j.tenant_id
 cross join lateral(select coalesce(sum(l.debit),0) total_debit,coalesce(sum(l.credit),0) total_credit,
 jsonb_agg(to_jsonb(l)||jsonb_build_object('account_code',a.code,'account_name',a.name) order by l.id) saved_lines
 from public.journal_lines l join public.accounting_accounts a on a.id=l.account_id and a.tenant_id=$1 where l.journal_entry_id=j.id) x
 where j.tenant_id=$1 and private.reports_scope_v631($1,j.location_id,$4,'view') and j.status='posted' and j.entry_date between $2 and $3 order by j.entry_date desc,j.entry_number,j.id) result$q$;
when 'expenses' then sql:=$q$select to_jsonb(result) from (select e.*,c.name category,private.v500_document_location($1,'expense',e.id) location_id,l.name location_name
 from public.expenses e left join public.expense_categories c on c.id=e.category_id and c.tenant_id=e.tenant_id
 left join public.business_locations l on l.tenant_id=$1 and l.id=private.v500_document_location($1,'expense',e.id)
 where e.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'expense',e.id),$4,'view') and e.status='posted' and e.expense_date between $2 and $3 order by e.expense_date desc,e.expense_number,e.id) result$q$;
when 'tax' then sql:=$q$select to_jsonb(result) from (select g.document_date,g.source_number,g.document_kind,g.document_class,'saved_gst_snapshot'::text verification,g.direction,
 g.taxable_total,g.cgst_total,g.sgst_total,g.igst_total,g.utgst_total,g.cess_total,g.tax_collected_total,g.rcm_tax_payable_total,
 case when g.source_type in('sales_return','purchase_return') then -1 else 1 end::numeric document_sign,
 to_jsonb(g)||jsonb_build_object('lines',(select jsonb_agg(to_jsonb(x) order by x.line_no) from public.gst_document_line_snapshots_v520 x where x.tenant_id=$1 and x.snapshot_id=g.id)) saved_snapshot
 from public.gst_document_snapshots_v520 g where g.tenant_id=$1 and private.reports_scope_v631($1,g.location_id,$4,'view') and g.document_date between $2 and $3
 union all select s.sale_date,s.sale_number,'invoice','legacy_record','legacy_unverified','outward',s.taxable_total,null,null,null,null,null,s.tax_total,null,1,to_jsonb(s)
 from public.sales s where s.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'sale',s.id),$4,'view') and coalesce(s.status,'') not in('draft','void','cancelled') and s.sale_date between $2 and $3 and not exists(select 1 from public.gst_document_snapshots_v520 g where g.tenant_id=$1 and g.source_type='sale' and g.source_id=s.id)
 union all select p.purchase_date,p.purchase_number,'bill','legacy_record','legacy_unverified','inward',p.taxable_total,null,null,null,null,null,p.tax_total,null,1,to_jsonb(p)
 from public.purchases p where p.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'purchase',p.id),$4,'view') and coalesce(p.status,'') not in('draft','void','cancelled') and p.purchase_date between $2 and $3 and not exists(select 1 from public.gst_document_snapshots_v520 g where g.tenant_id=$1 and g.source_type='purchase' and g.source_id=p.id)
 order by document_date desc,source_number) result$q$;
when 'reconciliation' then sql:=$q$select to_jsonb(result) from (with journals as(select j.*,bl.name location_name,x.total_debit,x.total_credit,x.total_debit-x.total_credit difference,x.saved_lines
 from public.journal_entries j left join public.business_locations bl on bl.id=j.location_id and bl.tenant_id=j.tenant_id
 cross join lateral(select coalesce(sum(l.debit),0) total_debit,coalesce(sum(l.credit),0) total_credit,
 jsonb_agg(to_jsonb(l)||jsonb_build_object('account_code',a.code,'account_name',a.name) order by l.id) saved_lines
 from public.journal_lines l join public.accounting_accounts a on a.id=l.account_id and a.tenant_id=$1 where l.journal_entry_id=j.id) x
 where j.tenant_id=$1 and private.reports_scope_v631($1,j.location_id,$4,'view') and j.status='posted' and j.entry_date between $2 and $3 order by j.entry_date desc,j.entry_number,j.id), docs as(
 select 'sale'::text source_type,s.id,s.sale_date entry_date,s.sale_number source_reference,s.grand_total amount from public.sales s where s.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'sale',s.id),$4,'view') and coalesce(s.status,'') not in('draft','void','cancelled') and s.sale_date between $2 and $3
 union all select 'purchase',p.id,p.purchase_date,p.purchase_number,p.grand_total from public.purchases p where p.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'purchase',p.id),$4,'view') and coalesce(p.status,'') not in('draft','void','cancelled') and p.purchase_date between $2 and $3)
 select entry_date,'Journal balance'::text check_name,source_reference,source_type,total_debit expected,total_credit actual,difference,
 case when abs(difference)<0.005 then 'Pass' else 'Review' end result,description,id journal_id from journals
 union all select d.entry_date,'Document posting',d.source_reference,d.source_type,1,x.n,x.n-1,case when x.n=1 then 'Pass' else 'Review' end,
 'Expected one posted source journal',d.id from docs d cross join lateral(select count(*)::numeric n from public.journal_entries j where j.tenant_id=$1 and j.source_type=d.source_type and j.source_id=d.id and j.status='posted') x
 union all select d.entry_date,'Saved GST total',d.source_reference,d.source_type,d.amount,g.grand_total,g.grand_total-d.amount,
 case when abs(g.grand_total-d.amount)<0.005 then 'Pass' else 'Review' end,'Invoice total compared with immutable GST snapshot',g.id
 from docs d join public.gst_document_snapshots_v520 g on g.tenant_id=$1 and g.source_type=d.source_type and g.source_id=d.id order by entry_date desc,check_name,source_reference) result$q$;
when 'load_register' then sql:=$q$select to_jsonb(result) from (select l.*,l.product_name_snapshot product_name,l.vehicle_registration_snapshot vehicle_registration,l.driver_name_snapshot driver_name,
 bl.name location_name,x.cost_total,x.customer_charge_total,private.reports_load_evidence_v631($1,l.id) saved_evidence
 from public.aggregate_loads_v617 l left join public.business_locations bl on bl.tenant_id=$1 and bl.id=l.location_id
 cross join lateral(select coalesce(sum(c.amount) filter(where c.status<>'void'),0) cost_total,coalesce(sum(c.bill_amount) filter(where c.status<>'void'),0) customer_charge_total from public.material_load_costs_v630 c where c.tenant_id=$1 and c.load_id=l.id) x
 where l.tenant_id=$1 and private.reports_scope_v631($1,l.location_id,$4,'view') and l.load_date between $2 and $3 order by l.load_date desc,l.load_number,l.id) result$q$;
when 'load_costs' then sql:=$q$select to_jsonb(result) from (select c.*,l.load_number,l.load_date,l.location_id,l.vehicle_id,l.driver_id,
 private.load_cost_paid_v630(c.id) paid_amount,case when c.staff_mode='salary_allocation' or c.status<>'posted' then 0 else greatest(c.amount-private.load_cost_paid_v630(c.id),0) end outstanding,
 coalesce((select jsonb_agg(to_jsonb(x) order by x.payment_date,x.id) from public.material_load_cost_payments_v630 x where x.tenant_id=$1 and x.cost_id=c.id),'[]'::jsonb) external_payments,
 coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('allocation',to_jsonb(a)) order by x.payment_date,x.id) from public.staff_payment_allocations_v630 a join public.staff_payments_v630 x on x.id=a.payment_id and x.tenant_id=$1 where a.earning_id=c.staff_earning_id),'[]'::jsonb) staff_payment_allocations
 from public.material_load_costs_v630 c join public.aggregate_loads_v617 l on l.id=c.load_id and l.tenant_id=c.tenant_id
 where l.tenant_id=$1 and private.reports_scope_v631($1,l.location_id,$4,'view') and l.load_date between $2 and $3 order by l.load_date desc,l.load_number,c.created_at,c.id) result$q$;
when 'load_payments' then sql:=$q$select to_jsonb(result) from (select p.id,p.payment_date,l.load_number,c.payee,c.description cost_description,p.payment_method,p.amount,p.reference,'external_payment'::text payment_source,p.notes,l.location_id,to_jsonb(p) saved_payment,to_jsonb(c) saved_cost
 from public.material_load_cost_payments_v630 p join public.material_load_costs_v630 c on c.id=p.cost_id and c.tenant_id=p.tenant_id join public.aggregate_loads_v617 l on l.id=c.load_id and l.tenant_id=c.tenant_id
 where l.tenant_id=$1 and private.reports_scope_v631($1,l.location_id,$4,'view') and p.payment_date between $2 and $3
 union all select a.id,case when a.from_advance then (a.created_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date else p.payment_date end,l.load_number,p.payee_snapshot,c.description,p.payment_method,a.amount,p.reference,
 case when a.from_advance then 'advance_applied' else 'staff_wage_payment' end,p.notes,l.location_id,to_jsonb(p)||jsonb_build_object('allocation',to_jsonb(a)),to_jsonb(c)
 from public.staff_payment_allocations_v630 a join public.staff_payments_v630 p on p.id=a.payment_id and p.tenant_id=$1
 join public.material_load_costs_v630 c on c.staff_earning_id=a.earning_id and c.tenant_id=$1 join public.aggregate_loads_v617 l on l.id=c.load_id and l.tenant_id=c.tenant_id
 where l.tenant_id=$1 and private.reports_scope_v631($1,l.location_id,$4,'view') and (case when a.from_advance then (a.created_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date else p.payment_date end) between $2 and $3
 union all select p.id,(p.settled_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date,l.load_number,null,'Freight settlement',p.payment_method,p.total_paid,p.reference_number,'legacy_freight',p.note,l.location_id,to_jsonb(p),null
 from public.aggregate_freight_settlements_v620 p join public.aggregate_loads_v617 l on l.id=p.load_id and l.tenant_id=p.tenant_id
 where l.tenant_id=$1 and private.reports_scope_v631($1,l.location_id,$4,'view') and (p.settled_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date between $2 and $3 order by payment_date desc,load_number,id) result$q$;
when 'load_delivery' then sql:=$q$select to_jsonb(result) from (select l.id,l.load_number,l.load_date,l.vehicle_registration_snapshot vehicle_registration,l.driver_name_snapshot driver_name,
 coalesce(d.details->>'driver_contact_phone',l.driver_phone_snapshot) driver_contact_phone,l.source_name,l.destination_name,
 d.details->>'delivery_address' delivery_address,d.details->>'dispatch_at' dispatch_at,d.details->>'delivered_at' delivered_at,d.details->>'received_by' received_by,d.details->>'proof_reference' proof_reference,
 l.location_id,l.vehicle_id,l.driver_id,to_jsonb(l) saved_load,d.details saved_delivery
 from public.aggregate_loads_v617 l left join public.material_load_delivery_v630 d on d.load_id=l.id and d.tenant_id=l.tenant_id
 where l.tenant_id=$1 and private.reports_scope_v631($1,l.location_id,$4,'view') and l.load_date between $2 and $3 order by l.load_date desc,l.load_number,l.id) result$q$;
when 'staff_balances' then sql:=$q$select to_jsonb(result) from (with lines as(select j.*,l.id line_id,l.account_id,l.debit,l.credit,l.party_type,l.party_id,l.description line_description,a.code,a.name account_name,a.account_type,a.system_key,
 coalesce(c.name,s.name,m.name,k.payee,l.party_id::text,'') party_name
 from public.journal_entries j join public.journal_lines l on l.journal_entry_id=j.id
 join public.accounting_accounts a on a.id=l.account_id and a.tenant_id=j.tenant_id
 left join public.customers c on c.tenant_id=$1 and c.id=l.party_id and l.party_type='customer'
 left join public.suppliers s on s.tenant_id=$1 and s.id=l.party_id and l.party_type='supplier'
 left join public.staff_members_v630 m on m.tenant_id=$1 and m.id=l.party_id and l.party_type='staff'
 left join public.material_load_costs_v630 k on k.tenant_id=$1 and k.id=l.party_id and l.party_type='load_cost'
 where j.tenant_id=$1 and private.reports_scope_v631($1,j.location_id,$4,'view') and j.status='posted' and j.entry_date<=$3),b as(select party_id,
 coalesce(sum(credit-debit) filter(where system_key='staff_payable_v630' and entry_date<$2),0) opening_payable,
 coalesce(sum(credit-debit) filter(where system_key='staff_payable_v630'),0) payable,
 coalesce(sum(debit-credit) filter(where system_key='staff_advance_v630'),0) advance
 from lines where party_type='staff' group by party_id)
 select m.*,coalesce(b.opening_payable,0) opening_payable,greatest(coalesce(b.payable,0),0) outstanding,greatest(coalesce(b.advance,0),0) advance_balance,
 coalesce((select sum(e.amount) from public.staff_earnings_v630 e where e.tenant_id=$1 and e.staff_id=m.id and e.earning_date between $2 and $3 and private.reports_scope_v631($1,e.location_id,$4,'view')),0) period_earned,
 coalesce((select sum(p.amount) from public.staff_payments_v630 p where p.tenant_id=$1 and p.staff_id=m.id and p.payment_date between $2 and $3 and private.reports_scope_v631($1,p.location_id,$4,'view')),0) period_paid
 from public.staff_members_v630 m left join b on b.party_id=m.id where m.tenant_id=$1 and private.reports_scope_v631($1,m.location_id,$4,'view') order by m.name,m.id) result$q$;
when 'staff_attendance' then sql:=$q$select to_jsonb(result) from (select a.*,m.name staff_name,l.name location_name from public.staff_attendance_v630 a join public.staff_members_v630 m on m.tenant_id=a.tenant_id and m.id=a.staff_id
 left join public.business_locations l on l.tenant_id=a.tenant_id and l.id=a.location_id where a.tenant_id=$1 and private.reports_scope_v631($1,a.location_id,$4,'view') and a.work_date between $2 and $3 order by a.work_date desc,m.name,a.id) result$q$;
when 'staff_earnings' then sql:=$q$select to_jsonb(result) from (select e.*,m.name staff_name,x.paid_amount,greatest(e.amount-x.paid_amount,0) outstanding,x.allocations
 from public.staff_earnings_v630 e join public.staff_members_v630 m on m.id=e.staff_id and m.tenant_id=e.tenant_id
 cross join lateral(select coalesce(sum(a.amount),0) paid_amount,coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('payment',to_jsonb(p)) order by p.payment_date,a.created_at,a.id),'[]'::jsonb) allocations
 from public.staff_payment_allocations_v630 a join public.staff_payments_v630 p on p.id=a.payment_id and p.tenant_id=$1
 where a.earning_id=e.id and p.payment_date<=$3 and (a.created_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date<=$3 and private.reports_scope_v631($1,p.location_id,$4,'view')) x
 where e.tenant_id=$1 and private.reports_scope_v631($1,e.location_id,$4,'view') and e.earning_date between $2 and $3 order by e.earning_date desc,m.name,e.id) result$q$;
when 'staff_payments' then sql:=$q$select to_jsonb(result) from (select p.*,m.name staff_name,l.name location_name,
 (select jsonb_agg(to_jsonb(a) order by a.created_at,a.id) from public.staff_payment_allocations_v630 a where a.payment_id=p.id and (a.created_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date<=$3) allocations_through_to
 from public.staff_payments_v630 p join public.staff_members_v630 m on m.id=p.staff_id and m.tenant_id=p.tenant_id
 left join public.business_locations l on l.tenant_id=p.tenant_id and l.id=p.location_id
 where p.tenant_id=$1 and private.reports_scope_v631($1,p.location_id,$4,'view') and p.payment_date between $2 and $3 order by p.payment_date desc,m.name,p.id) result$q$;
when 'salary_allocations' then sql:=$q$select to_jsonb(result) from (select c.*,l.load_number,l.load_date,l.location_id,m.name staff_name
 from public.material_load_costs_v630 c join public.aggregate_loads_v617 l on l.id=c.load_id and l.tenant_id=c.tenant_id
 join public.staff_members_v630 m on m.id=c.staff_id and m.tenant_id=c.tenant_id where l.tenant_id=$1 and private.reports_scope_v631($1,l.location_id,$4,'view') and l.load_date between $2 and $3 and c.staff_mode='salary_allocation' order by l.load_date desc,l.load_number,c.id) result$q$;
when 'transport_trips' then sql:=$q$select to_jsonb(result) from (select h.*,coalesce(v.registration_number,l.vehicle_registration_snapshot) vehicle_registration,
 coalesce(l.driver_name_snapshot,st.driver_name,v.driver_name) driver_name,coalesce(l.source_name,j.from_location,fl.name) source_name,coalesce(l.destination_name,j.to_location,tl.name) destination_name,
 coalesce(l.status,j.status,st.status,op.status) status,l.load_number,s.sale_number,p.purchase_number,
 coalesce(l.location_id,j.location_id,st.from_location_id,op.base_location_id) location_id,to_jsonb(l) material_load,to_jsonb(j) service_job,to_jsonb(st) stock_trip,to_jsonb(op) logistics_operation,
 coalesce(l.load_date,j.service_date,op.operation_date,(h.created_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date) trip_date
 from public.transport_trip_hub_v611 h left join public.aggregate_loads_v617 l on l.id=h.material_load_id and l.tenant_id=h.tenant_id
 left join public.service_jobs j on j.id=h.service_job_id and j.tenant_id=h.tenant_id
 left join public.transport_logistics_trips st on st.id=h.stock_trip_id and st.tenant_id=h.tenant_id
 left join public.logistics_operations_v61 op on op.id=h.logistics_operation_id and op.tenant_id=h.tenant_id
 left join public.service_vehicles v on v.id=coalesce(l.vehicle_id,j.vehicle_id,st.vehicle_id) and v.tenant_id=h.tenant_id
 left join public.business_locations fl on fl.id=st.from_location_id and fl.tenant_id=h.tenant_id left join public.business_locations tl on tl.id=st.to_location_id and tl.tenant_id=h.tenant_id
 left join public.sales s on s.id=coalesce(l.sale_id,j.sale_id) and s.tenant_id=h.tenant_id left join public.purchases p on p.id=l.purchase_id and p.tenant_id=h.tenant_id
 where h.tenant_id=$1 and private.reports_scope_v631($1,coalesce(l.location_id,j.location_id,st.from_location_id,op.base_location_id),$4,'view')
 and ((h.material_load_id is not null and private.erp_has_permission($1,'aggregate_yard.view')) or (h.service_job_id is not null and private.erp_has_permission($1,'transport_service.view')) or (h.stock_trip_id is not null and private.erp_has_permission($1,'vehicle_logistics.view')) or (h.logistics_operation_id is not null and private.erp_has_permission($1,'logistics_operations.view')))
 and coalesce(l.load_date,j.service_date,op.operation_date,(h.created_at at time zone coalesce((select timezone from public.tenant_settings where tenant_id=$1),'UTC'))::date) between $2 and $3
 order by trip_date desc,h.trip_number,h.id) result$q$;
when 'vehicle_profitability' then sql:=$q$select to_jsonb(result) from (with loads as(select l.id,l.vehicle_id,coalesce(l.vehicle_registration_snapshot,'Unassigned') vehicle_registration,
 case when s.status='posted' then s.id end sale_id,case when s.status='posted' then s.taxable_total else 0 end invoice_sales,
 case when s.status='posted' then s.cost_total else 0 end invoice_cost,case when s.status='posted' then s.gross_profit else 0 end invoice_margin,
 coalesce((select sum(c.amount) from public.material_load_costs_v630 c where c.tenant_id=$1 and c.load_id=l.id and c.status<>'void'),0) load_cost
 from public.aggregate_loads_v617 l left join public.sales s on s.id=l.sale_id and s.tenant_id=l.tenant_id
 where l.tenant_id=$1 and private.reports_scope_v631($1,l.location_id,$4,'view') and l.load_date between $2 and $3 and l.status not in('void','cancelled','draft'))
 select vehicle_id,vehicle_registration,count(*) loads,count(sale_id) invoiced_loads,sum(invoice_sales) invoice_sales,sum(invoice_cost) invoice_cost,sum(load_cost) load_cost,
 sum(invoice_margin-load_cost) gross_profit_after_load_cost,jsonb_agg(to_jsonb(loads) order by id) saved_load_margins
 from loads group by vehicle_id,vehicle_registration order by gross_profit_after_load_cost desc,vehicle_registration) result$q$;
when 'sales_summary' then sql:=$q$select to_jsonb(result) from (with sales as(select coalesce(sum(s.grand_total),0) gross,coalesce(sum(s.tax_total),0) tax,coalesce(sum(s.taxable_total),0) taxable,count(*) invoices from public.sales s where s.tenant_id=$1 and private.reports_scope_v631($1,private.v500_document_location($1,'sale',s.id),$4,'view') and coalesce(s.status,'') not in('draft','void','cancelled') and s.sale_date between $2 and $3),
 returns as(select coalesce(sum(r.grand_total),0) amount,coalesce(sum(r.tax_total),0) tax from public.sales_returns r where r.tenant_id=$1 and private.reports_scope_v631($1,r.location_id,$4,'view') and r.refund_status<>'waived' and r.return_date between $2 and $3),
 pl as(select coalesce(sum(case when a.account_type='income' then l.credit-l.debit else 0 end),0) revenue,
 coalesce(sum(case when a.account_type='cogs' then l.debit-l.credit else 0 end),0) cogs,
 coalesce(sum(case when a.account_type='expense' then l.debit-l.credit else 0 end),0) expenses
 from public.journal_entries j join public.journal_lines l on l.journal_entry_id=j.id join public.accounting_accounts a on a.id=l.account_id and a.tenant_id=j.tenant_id
 where j.tenant_id=$1 and private.reports_scope_v631($1,j.location_id,$4,'view') and j.status='posted' and j.entry_date between $2 and $3)
 select metrics.metric,metrics.amount from sales cross join returns cross join pl cross join lateral(values
 ('Posted invoices',invoices::numeric),('Invoice sales including tax',gross),('Sales returns including tax',amount),('Net sales including tax',gross-amount),
 ('Recorded sales tax less return tax',sales.tax-returns.tax),('Ledger revenue',revenue),('Ledger cost of goods sold',cogs),('Ledger expenses including Staff and load costs',expenses),('Ledger net profit',revenue-cogs-expenses)) metrics(metric,amount)) result$q$;
 else raise exception 'Unsupported report key: %',k;end case;
 for rec in execute sql using t,f,z,l loop return next rec;end loop;return;
end $body$;
create or replace function public.reports_center_run_v631(
 p_tenant_id uuid,p_report_key text,p_from date,p_to date,p_location_id uuid default null,
 p_query text default '',p_offset integer default 0,p_limit integer default 100,p_filters jsonb default '{}',p_sort_key text default null,p_sort_desc boolean default false)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare definition jsonb;raw_rows jsonb;matched jsonb;page_rows jsonb;columns jsonb;summary jsonb:='[]';totals jsonb:='{}';
 col jsonb;row_value jsonb;entry record;v_amount numeric;n integer;all_n integer;key text;from_date date;to_date date;scope_name text;statement jsonb;
begin
 perform private.reports_assert_v631(p_tenant_id,p_report_key,p_location_id);
 if p_from is null or p_to is null or p_from>p_to then raise exception 'Choose a valid date range' using errcode='22023';end if;
 if p_offset is null or p_offset<0 or p_limit is null or p_limit<0 or p_limit>1000 then raise exception 'Invalid page size or offset' using errcode='22023';end if;
 if jsonb_typeof(coalesce(p_filters,'{}'))<>'object' then raise exception 'Invalid report filters' using errcode='22023';end if;
 for key in select jsonb_object_keys(coalesce(p_filters,'{}')) loop
  if key not in('status','customer_id','supplier_id','vehicle_id','driver_id','staff_id','account_id','direction') then raise exception 'Unsupported filter: %',key using errcode='22023';end if;
 end loop;
 select d into definition from jsonb_array_elements(private.reports_definitions_v631()) d where d->>'key'=p_report_key;
 columns:=definition->'columns';
 if p_sort_key is not null and not exists(select 1 from jsonb_array_elements(columns) c where c->>'key'=p_sort_key) then raise exception 'Invalid sort column' using errcode='22023';end if;
 if p_report_key in('profit_loss','balance_sheet') then
  statement:=private.reports_statement_v631(p_tenant_id,p_report_key,p_from,p_to,p_location_id);raw_rows:=statement->'rows';
  for entry in select * from jsonb_each(statement->'summary') loop
   if jsonb_typeof(entry.value)='number' then summary:=summary||jsonb_build_array(jsonb_build_object('key',entry.key,'label',initcap(replace(entry.key,'_',' ')),'value',entry.value,'type','money'));end if;
  end loop;
 else select coalesce(jsonb_agg(x),'[]') into raw_rows from private.reports_rows_v631(p_tenant_id,p_report_key,p_from,p_to,p_location_id) x;
 end if;
 all_n:=jsonb_array_length(raw_rows);
 -- Ordinality retains the documented default order; numeric values sort numerically.
 select coalesce(jsonb_agg(value order by
  case when not coalesce(p_sort_desc,false) and jsonb_typeof(value->p_sort_key)='number' then (value->>p_sort_key)::numeric end asc nulls last,
  case when coalesce(p_sort_desc,false) and jsonb_typeof(value->p_sort_key)='number' then (value->>p_sort_key)::numeric end desc nulls last,
  case when not coalesce(p_sort_desc,false) then lower(value->>p_sort_key) end asc nulls last,
  case when coalesce(p_sort_desc,false) then lower(value->>p_sort_key) end desc nulls last,ordinality),'[]') into matched
 from jsonb_array_elements(raw_rows) with ordinality as records(value,ordinality)
 where (coalesce(trim(p_query),'')='' or strpos(lower(value::text),lower(trim(p_query)))>0)
 and not exists(select 1 from jsonb_each_text(coalesce(p_filters,'{}')) filter where filter.value<>'' and coalesce(records.value->>filter.key,'')<>filter.value);
 n:=jsonb_array_length(matched);
 select coalesce(jsonb_agg(value order by ordinality),'[]') into page_rows from jsonb_array_elements(matched) with ordinality where ordinality>p_offset and (p_limit=0 or ordinality<=p_offset+p_limit);
 for col in select x from jsonb_array_elements(columns) x where x->>'total'='true' loop
  select coalesce(sum((x->>(col->>'key'))::numeric),0) into v_amount from jsonb_array_elements(matched) x where jsonb_typeof(x->(col->>'key'))='number';
  totals:=totals||jsonb_build_object(col->>'key',v_amount);
  summary:=summary||jsonb_build_array(jsonb_build_object('key',col->>'key','label',col->>'label','value',v_amount,'type',col->>'type'));
 end loop;
 if p_report_key='trial_balance' then
  summary:=summary||jsonb_build_array(jsonb_build_object('key','difference','label','Closing balance difference','value',coalesce((totals->>'closing_debit')::numeric,0)-coalesce((totals->>'closing_credit')::numeric,0),'type','money'));
 elsif p_report_key='reconciliation' then
  select count(*) into v_amount from jsonb_array_elements(matched) x where x->>'result'='Review';summary:=summary||jsonb_build_array(jsonb_build_object('key','review_count','label','Checks requiring review','value',v_amount,'type','number'));
 elsif p_report_key='tax' then
  for key in select unnest(array['cgst_total','sgst_total','igst_total','utgst_total','cess_total','tax_collected_total','rcm_tax_payable_total']) loop
   for entry in select unnest(array['outward','inward']) direction loop
    select coalesce(sum((x->>key)::numeric*coalesce((x->>'document_sign')::numeric,1)),0) into v_amount from jsonb_array_elements(matched) x where x->>'verification'='saved_gst_snapshot' and x->>'direction'=entry.direction;
    summary:=summary||jsonb_build_array(jsonb_build_object('key',entry.direction||'_'||key,'label',initcap(entry.direction||' '||replace(key,'_',' ')),'value',v_amount,'type','money'));
   end loop;
  end loop;
  select coalesce(sum((x->>'tax_collected_total')::numeric),0) into v_amount from jsonb_array_elements(matched) x where x->>'verification'='legacy_unverified';
  summary:=summary||jsonb_build_array(jsonb_build_object('key','legacy_recorded_tax','label','Legacy recorded tax (unverified)','value',v_amount,'type','money'));
 end if;
 scope_name:=case when p_location_id is null then 'All authorized stores' else (select name from public.business_locations where tenant_id=p_tenant_id and id=p_location_id) end;
 return jsonb_build_object('version','6.3.1','definition',definition,'columns',columns,'rows',page_rows,'summary',summary,'totals',totals,'total_rows',n,'source_rows',all_n,'offset',p_offset,'limit',p_limit,'complete',p_offset=0 and jsonb_array_length(page_rows)=n,
 'context',jsonb_build_object('tenant_id',p_tenant_id,'company',(select name from public.tenants where id=p_tenant_id),'currency',coalesce((select currency_code from public.tenant_settings where tenant_id=p_tenant_id),'INR'),'timezone',coalesce((select timezone from public.tenant_settings where tenant_id=p_tenant_id),'UTC'),
 'from',p_from,'to',p_to,'location_id',p_location_id,'location',scope_name,'query',coalesce(p_query,''),'filters',coalesce(p_filters,'{}'),'sort_key',p_sort_key,'sort_desc',p_sort_desc,'generated_at',statement_timestamp(),
 'summary_basis',case when p_report_key in('profit_loss','balance_sheet') then 'Full authorized statement; table search does not change statement totals' else 'All matching records, including undisplayed pages' end));
end $$;
revoke all on function private.reports_scope_v631(uuid,uuid,uuid,text) from public,anon,authenticated;
revoke all on function private.reports_definitions_v631() from public,anon,authenticated;
revoke all on function private.reports_assert_v631(uuid,text,uuid) from public,anon,authenticated;
revoke all on function private.reports_rows_v631(uuid,text,date,date,uuid) from public,anon,authenticated;
revoke all on function private.reports_inventory_rows_v631(uuid,uuid,integer,text,integer) from public,anon,authenticated;
revoke all on function private.reports_returns_rows_v631(uuid,text,date,date,uuid,text,integer) from public,anon,authenticated;
revoke all on function private.reports_statement_v631(uuid,text,date,date,uuid) from public,anon,authenticated;
revoke all on function public.reports_center_catalog_v631(uuid) from public,anon;
revoke all on function public.reports_center_run_v631(uuid,text,date,date,uuid,text,integer,integer,jsonb,text,boolean) from public,anon;
grant execute on function public.reports_center_catalog_v631(uuid) to authenticated;
grant execute on function public.reports_center_run_v631(uuid,text,date,date,uuid,text,integer,integer,jsonb,text,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
