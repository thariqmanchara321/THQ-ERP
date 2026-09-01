-- THQ ERP v5.0.0 — centralized Reports Center and detailed returns reporting.
begin;

create or replace function public.reports_catalog_v500()
returns jsonb language sql immutable as $$
select jsonb_build_array(
  jsonb_build_object('category','Sales','reports',jsonb_build_array('sales_summary','sales_register','sales_by_product','sales_by_customer','sales_by_salesperson','sales_by_store','sales_by_pos','sales_by_payment_method','returns')),
  jsonb_build_object('category','Inventory','reports',jsonb_build_array('current_stock','stock_valuation','stock_movement','stock_aging','expiry','dead_stock','low_stock','serials','batches')),
  jsonb_build_object('category','Purchase','reports',jsonb_build_array('purchase_register','supplier_purchase','purchase_returns','supplier_outstanding','supplier_performance','price_history')),
  jsonb_build_object('category','Accounting','reports',jsonb_build_array('profit_loss','balance_sheet','trial_balance','general_ledger','cash_flow','receivables','payables','journal_register','expenses','tax','reconciliation'))
)
$$;
grant execute on function public.reports_catalog_v500() to authenticated;

create or replace function public.returns_report_v500(
  p_tenant_id uuid,p_kind text default 'all',p_from date default null,p_to date default null,p_location_id uuid default null,p_query text default '',p_limit integer default 5000
) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
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
      where sr.tenant_id=p_tenant_id and sr.refund_status<>'waived'
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
      where pr.tenant_id=p_tenant_id and pr.credit_status<>'waived'
        and (p_from is null or pr.return_date>=p_from) and (p_to is null or pr.return_date<=p_to)
        and (p_location_id is null or pr.location_id=p_location_id)
    )
    select * from rows x
    where (lower(coalesce(p_kind,'all'))='all' or x.return_side=lower(p_kind))
      and (trim(coalesce(p_query,''))='' or lower(x.return_number) like q or lower(coalesce(x.source_number,'')) like q or lower(x.party_name) like q or lower(x.product_name) like q or lower(coalesce(x.sku,'')) like q or lower(coalesce(x.barcode,'')) like q or lower(coalesce(x.hsn_sac,'')) like q or lower(coalesce(x.reason,'')) like q)
    order by return_date desc,created_at desc
    limit greatest(1,least(coalesce(p_limit,5000),10000))
  loop return next to_jsonb(r);end loop;return;
end $$;
grant execute on function public.returns_report_v500(uuid,text,date,date,uuid,text,integer) to authenticated;

create or replace function public.reports_center_data_v500(
  p_tenant_id uuid,p_report_key text,p_from date,p_to date,p_location_id uuid default null,p_query text default '',p_limit integer default 1000
) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r record;k text:=lower(trim(coalesce(p_report_key,'')));begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if k='sales_summary' then return next public.reports_get_summary_v4(p_tenant_id,p_from,p_to,p_location_id);return;
  elsif k='sales_register' then for r in select * from public.accounting_register_v4(p_tenant_id,'sales',p_from,p_to,p_location_id,p_query) loop return next to_jsonb(r);end loop;return;
  elsif k='purchase_register' then for r in select * from public.accounting_register_v4(p_tenant_id,'purchases',p_from,p_to,p_location_id,p_query) loop return next to_jsonb(r);end loop;return;
  elsif k in('general_ledger','journal_register') then for r in select * from public.journal_center_list_v500(p_tenant_id,p_from,p_to,p_query,null,p_limit) loop return next to_jsonb(r);end loop;return;
  elsif k in('trial_balance','profit_loss','balance_sheet','cash_flow') then return next public.accounting_statement_v41(p_tenant_id,k,p_from,p_to,p_location_id);return;
  elsif k='receivables' then for r in select * from public.customer_credit_intelligence_v480(p_tenant_id,p_location_id,p_query,p_limit) loop return next to_jsonb(r);end loop;return;
  elsif k in('payables','supplier_outstanding') then for r in select * from public.supplier_payables_intelligence_v480(p_tenant_id,p_location_id,p_query,p_limit) loop return next to_jsonb(r);end loop;return;
  elsif k='supplier_performance' then for r in select * from public.supplier_performance_v500(p_tenant_id,p_from,p_to,p_limit) loop return next to_jsonb(r);end loop;return;
  elsif k in('current_stock','stock_valuation','stock_aging','dead_stock','low_stock') then for r in select * from public.inventory_intelligence_v480(p_tenant_id,p_location_id,greatest(1,least((p_to-p_from)+1,365)),p_query,p_limit) x where (k not in('dead_stock','low_stock') or (k='dead_stock' and x.status='dead_stock') or (k='low_stock' and x.status in('low_stock','out_of_stock'))) loop return next to_jsonb(r);end loop;return;
  elsif k in('returns','purchase_returns') then for r in select value row_json from jsonb_array_elements(coalesce((select jsonb_agg(x) from public.returns_report_v500(p_tenant_id,case when k='purchase_returns' then 'purchase' else 'all' end,p_from,p_to,p_location_id,p_query,p_limit) x),'[]'::jsonb)) loop return next r.row_json;end loop;return;
  elsif k='reconciliation' then return next public.finance_reconciliation_v491(p_tenant_id);return;
  elsif k='tax' then return next public.gst_summary_v4(p_tenant_id,p_from,p_to,p_location_id);return;
  elsif k='expenses' then for r in select e.expense_date,e.expense_number,c.name category,e.payee,e.description,e.amount,e.tax_amount,e.total_amount,e.payment_method,e.reference_number,e.status from public.expenses e join public.expense_categories c on c.id=e.category_id left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='expense' and o.entity_id=e.id where e.tenant_id=p_tenant_id and e.expense_date between p_from and p_to and e.status='posted' and (p_location_id is null or o.location_id=p_location_id) and (trim(coalesce(p_query,''))='' or lower(e.expense_number) like '%'||lower(trim(p_query))||'%' or lower(e.description) like '%'||lower(trim(p_query))||'%' or lower(coalesce(e.payee,'')) like '%'||lower(trim(p_query))||'%') order by e.expense_date desc limit greatest(1,least(coalesce(p_limit,1000),5000)) loop return next to_jsonb(r);end loop;return;
  else raise exception 'Unsupported report key: %',p_report_key;end if;
end $$;
grant execute on function public.reports_center_data_v500(uuid,text,date,date,uuid,text,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(204,'5.0.0','THQ Reports Center','Central report catalogue, detailed Sales/Purchase Returns data and unified report data endpoints for accounting, inventory, purchasing and sales.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v5.0.0 migration 204 applied' as status;
