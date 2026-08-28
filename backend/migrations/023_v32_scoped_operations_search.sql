-- FLEXI ERP V3.2
-- Server-side location scoping for operational lists/reports and global search.
begin;

create or replace function private.erp_document_scope_allowed(
  p_tenant_id uuid,p_location_id uuid,p_requested_location uuid default null,p_required text default 'view'
)
returns boolean language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ begin
  if p_location_id is null then return private.erp_user_is_owner(p_tenant_id);end if;
  if p_requested_location is not null and p_location_id<>p_requested_location then return false;end if;
  if private.erp_user_location_allowed(p_tenant_id,p_location_id,p_required) then return true;end if;
  if private.erp_has_permission(p_tenant_id,'locations.manage_all') then return true;end if;
  if lower(coalesce(p_required,'view'))='view' and private.erp_has_permission(p_tenant_id,'locations.view_all') then return true;end if;
  return false;
end $$;
revoke all on function private.erp_document_scope_allowed(uuid,uuid,uuid,text) from public;

create or replace function public.sales_list_v32(p_tenant_id uuid,p_location_id uuid default null)
returns table(
  sale_id uuid,sale_number text,invoice_number text,customer_id uuid,customer_name text,sale_date date,due_date date,
  subtotal numeric,discount_total numeric,tax_total numeric,additional_charges numeric,grand_total numeric,
  paid_amount numeric,balance_due numeric,payment_status text,cost_total numeric,gross_profit numeric,status text,created_at timestamptz,
  location_id uuid,location_name text,device_id uuid,device_name text
)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if p_location_id is not null and not private.erp_user_location_allowed(p_tenant_id,p_location_id,'view') and not private.erp_has_permission(p_tenant_id,'locations.view_all') and not private.erp_has_permission(p_tenant_id,'locations.manage_all') then raise exception 'Location access denied';end if;
  return query
  select s.id,s.sale_number,coalesce(dn.terminal_number,ln.local_number,s.sale_number),s.customer_id,c.name,s.sale_date,s.due_date,
    s.subtotal,s.discount_total,s.tax_total,s.additional_charges,s.grand_total,
    coalesce(py.paid,0)::numeric,greatest(s.grand_total-coalesce(py.paid,0),0)::numeric,
    case when greatest(s.grand_total-coalesce(py.paid,0),0)<=0.0001 then 'paid' when coalesce(py.paid,0)>0 then 'partial' else 'unpaid' end,
    coalesce(s.cost_total,0)::numeric,coalesce(s.gross_profit,0)::numeric,s.status,s.created_at,
    o.location_id,l.name,o.device_id,d.name
  from public.sales s
  join public.customers c on c.id=s.customer_id
  left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id) py on py.sale_id=s.id
  left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
  left join public.business_locations l on l.id=o.location_id
  left join public.business_devices d on d.id=o.device_id
  left join public.location_document_numbers ln on ln.entity_type='sale' and ln.entity_id=s.id
  left join public.device_document_numbers dn on dn.entity_type='sale' and dn.entity_id=s.id
  where s.tenant_id=p_tenant_id and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'sales.view') or private.erp_has_permission(p_tenant_id,'sales.manage')) and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
  order by s.sale_date desc,s.created_at desc;
end $$;
grant execute on function public.sales_list_v32(uuid,uuid) to authenticated;

create or replace function public.purchases_list_v32(p_tenant_id uuid,p_location_id uuid default null)
returns table(
  purchase_id uuid,purchase_number text,invoice_number text,supplier_id uuid,supplier_name text,supplier_invoice_number text,purchase_date date,due_date date,
  subtotal numeric,discount_total numeric,tax_total numeric,additional_charges numeric,grand_total numeric,paid_amount numeric,balance_due numeric,payment_status text,status text,created_at timestamptz,
  location_id uuid,location_name text,device_id uuid,device_name text
)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  select p.id,p.purchase_number,coalesce(dn.terminal_number,ln.local_number,p.purchase_number),p.supplier_id,s.name,p.supplier_invoice_number,p.purchase_date,p.due_date,
    p.subtotal,p.discount_total,p.tax_total,p.additional_charges,p.grand_total,
    coalesce(py.paid,0)::numeric,greatest(p.grand_total-coalesce(py.paid,0),0)::numeric,
    case when greatest(p.grand_total-coalesce(py.paid,0),0)<=0.0001 then 'paid' when coalesce(py.paid,0)>0 then 'partial' else 'unpaid' end,
    p.status,p.created_at,o.location_id,l.name,o.device_id,d.name
  from public.purchases p join public.suppliers s on s.id=p.supplier_id
  left join (select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id=p.id
  left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id
  left join public.business_locations l on l.id=o.location_id left join public.business_devices d on d.id=o.device_id
  left join public.location_document_numbers ln on ln.entity_type='purchase' and ln.entity_id=p.id
  left join public.device_document_numbers dn on dn.entity_type='purchase' and dn.entity_id=p.id
  where p.tenant_id=p_tenant_id and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'purchases.view') or private.erp_has_permission(p_tenant_id,'purchases.manage')) and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
  order by p.purchase_date desc,p.created_at desc;
end $$;
grant execute on function public.purchases_list_v32(uuid,uuid) to authenticated;

create or replace function public.expenses_list_v32(p_tenant_id uuid,p_location_id uuid default null,p_from_date date default null,p_to_date date default null)
returns table(
  expense_id uuid,expense_number text,invoice_number text,category_id uuid,category_name text,expense_date date,payee text,description text,
  amount numeric,tax_amount numeric,total_amount numeric,payment_method text,reference_number text,notes text,status text,created_at timestamptz,
  location_id uuid,location_name text,device_id uuid,device_name text
)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select e.id,e.expense_number,coalesce(dn.terminal_number,ln.local_number,e.expense_number),e.category_id,c.name,e.expense_date,e.payee,e.description,
    e.amount,e.tax_amount,e.total_amount,e.payment_method,e.reference_number,e.notes,e.status,e.created_at,o.location_id,l.name,o.device_id,d.name
  from public.expenses e join public.expense_categories c on c.id=e.category_id
  left join public.document_origins o on o.entity_type='expense' and o.entity_id=e.id
  left join public.business_locations l on l.id=o.location_id left join public.business_devices d on d.id=o.device_id
  left join public.location_document_numbers ln on ln.entity_type='expense' and ln.entity_id=e.id
  left join public.device_document_numbers dn on dn.entity_type='expense' and dn.entity_id=e.id
  where e.tenant_id=p_tenant_id and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
    and (p_from_date is null or e.expense_date>=p_from_date) and (p_to_date is null or e.expense_date<=p_to_date)
  order by e.expense_date desc,e.created_at desc;
end $$;
grant execute on function public.expenses_list_v32(uuid,uuid,date,date) to authenticated;


create or replace function public.expenses_update_v32(p_tenant_id uuid,p_expense_id uuid,p_category_id uuid,p_expense_date date,p_payee text,p_description text,p_amount numeric,p_tax_amount numeric,p_payment_method text,p_reference_number text,p_notes text)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_loc uuid;begin
  select location_id into v_loc from public.document_origins where entity_type='expense' and entity_id=p_expense_id and tenant_id=p_tenant_id;
  if not private.erp_document_scope_allowed(p_tenant_id,v_loc,null,'operate') then raise exception 'Location access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'expenses.edit') then raise exception 'Expense edit permission denied';end if;
  perform public.expenses_update(p_tenant_id,p_expense_id,p_category_id,p_expense_date,p_payee,p_description,p_amount,p_tax_amount,p_payment_method,p_reference_number,p_notes);
end $$;
grant execute on function public.expenses_update_v32(uuid,uuid,uuid,date,text,text,numeric,numeric,text,text,text) to authenticated;


-- Detail wrappers prevent a restricted child-store user from opening another store's record by UUID.
create or replace function public.sales_get_detail_v32(p_tenant_id uuid,p_sale_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_loc uuid;v jsonb;begin
  select location_id into v_loc from public.document_origins where entity_type='sale' and entity_id=p_sale_id and tenant_id=p_tenant_id;
  if not private.erp_document_scope_allowed(p_tenant_id,v_loc,null,'view') then raise exception 'Location access denied';end if;
  v:=public.sales_get_detail(p_tenant_id,p_sale_id);return v;
end $$;
grant execute on function public.sales_get_detail_v32(uuid,uuid) to authenticated;

create or replace function public.purchases_get_detail_v32(p_tenant_id uuid,p_purchase_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_loc uuid;v jsonb;begin
  select location_id into v_loc from public.document_origins where entity_type='purchase' and entity_id=p_purchase_id and tenant_id=p_tenant_id;
  if not private.erp_document_scope_allowed(p_tenant_id,v_loc,null,'view') then raise exception 'Location access denied';end if;
  v:=public.purchases_get_detail(p_tenant_id,p_purchase_id);return v;
end $$;
grant execute on function public.purchases_get_detail_v32(uuid,uuid) to authenticated;


create or replace function public.sales_add_payment_v32(p_tenant_id uuid,p_sale_id uuid,p_amount numeric,p_payment_method text,p_reference_number text,p_notes text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_loc uuid;v jsonb;begin
  select location_id into v_loc from public.document_origins where entity_type='sale' and entity_id=p_sale_id and tenant_id=p_tenant_id;
  if not private.erp_document_scope_allowed(p_tenant_id,v_loc,null,'operate') then raise exception 'Location access denied';end if;
  v:=public.sales_add_payment(p_tenant_id,p_sale_id,p_amount,p_payment_method,p_reference_number,p_notes);return v;
end $$;
grant execute on function public.sales_add_payment_v32(uuid,uuid,numeric,text,text,text) to authenticated;

create or replace function public.sales_update_metadata_v32(p_tenant_id uuid,p_sale_id uuid,p_customer_id uuid,p_due_date date,p_notes text)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_loc uuid;begin
  select location_id into v_loc from public.document_origins where entity_type='sale' and entity_id=p_sale_id and tenant_id=p_tenant_id;
  if not private.erp_document_scope_allowed(p_tenant_id,v_loc,null,'operate') then raise exception 'Location access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'sales.edit') then raise exception 'Sale edit permission denied';end if;
  perform public.sales_update_metadata(p_tenant_id,p_sale_id,p_customer_id,p_due_date,p_notes);
end $$;
grant execute on function public.sales_update_metadata_v32(uuid,uuid,uuid,date,text) to authenticated;

create or replace function public.purchases_add_payment_v32(p_tenant_id uuid,p_purchase_id uuid,p_amount numeric,p_payment_method text,p_reference_number text,p_notes text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_loc uuid;v jsonb;begin
  select location_id into v_loc from public.document_origins where entity_type='purchase' and entity_id=p_purchase_id and tenant_id=p_tenant_id;
  if not private.erp_document_scope_allowed(p_tenant_id,v_loc,null,'operate') then raise exception 'Location access denied';end if;
  v:=public.purchases_add_payment(p_tenant_id,p_purchase_id,p_amount,p_payment_method,p_reference_number,p_notes);return v;
end $$;
grant execute on function public.purchases_add_payment_v32(uuid,uuid,numeric,text,text,text) to authenticated;


-- Location-aware report/accounting summaries. Inventory value remains business-wide until
-- the live stock RPCs are upgraded to physical branch stock; the response explicitly marks this.
create or replace function public.reports_get_summary_v32(p_tenant_id uuid,p_from_date date,p_to_date date,p_location_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare
  v_sales numeric:=0;v_sales_tax numeric:=0;v_purchases numeric:=0;v_purchase_tax numeric:=0;v_expenses numeric:=0;v_gp numeric:=0;v_recv numeric:=0;v_pay numeric:=0;v_stock numeric:=0;
  v_sc int:=0;v_pc int:=0;v_ec int:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if p_from_date is null or p_to_date is null or p_from_date>p_to_date then raise exception 'Invalid date range';end if;
  select coalesce(sum(s.grand_total),0),coalesce(sum(s.tax_total),0),coalesce(sum(s.gross_profit),0),count(*) into v_sales,v_sales_tax,v_gp,v_sc
  from public.sales s left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
  where s.tenant_id=p_tenant_id and s.sale_date between p_from_date and p_to_date and coalesce(s.status,'') not in ('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
  select coalesce(sum(p.grand_total),0),coalesce(sum(p.tax_total),0),count(*) into v_purchases,v_purchase_tax,v_pc
  from public.purchases p left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id
  where p.tenant_id=p_tenant_id and p.purchase_date between p_from_date and p_to_date and coalesce(p.status,'') not in ('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
  select coalesce(sum(e.total_amount),0),count(*) into v_expenses,v_ec
  from public.expenses e left join public.document_origins o on o.entity_type='expense' and o.entity_id=e.id
  where e.tenant_id=p_tenant_id and e.expense_date between p_from_date and p_to_date and e.status='posted' and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
  select coalesce(sum(greatest(s.grand_total-coalesce(py.paid,0),0)),0) into v_recv
  from public.sales s left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id) py on py.sale_id=s.id
  left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
  where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in ('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
  select coalesce(sum(greatest(p.grand_total-coalesce(py.paid,0),0)),0) into v_pay
  from public.purchases p left join (select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id=p.id
  left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id
  where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in ('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
  select coalesce(sum(sb.quantity*pv.cost_price),0) into v_stock from public.stock_balances sb join public.product_variants pv on pv.id=sb.variant_id where sb.tenant_id=p_tenant_id;
  return jsonb_build_object('from_date',p_from_date,'to_date',p_to_date,'sales',v_sales,'sales_tax',v_sales_tax,'purchases',v_purchases,'purchase_tax',v_purchase_tax,'expenses',v_expenses,'gross_profit',v_gp,'net_profit',v_gp-v_expenses,'receivables',v_recv,'payables',v_pay,'stock_value',v_stock,'sale_count',v_sc,'purchase_count',v_pc,'expense_count',v_ec,'location_id',p_location_id,'stock_scope','business');
end $$;
grant execute on function public.reports_get_summary_v32(uuid,date,date,uuid) to authenticated;

create or replace function public.accounting_get_summary_v32(p_tenant_id uuid,p_from_date date,p_to_date date,p_location_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_revenue numeric:=0;v_cogs numeric:=0;v_gp numeric:=0;v_exp numeric:=0;v_recv numeric:=0;v_pay numeric:=0;v_stock numeric:=0;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select coalesce(sum(s.taxable_total),0),coalesce(sum(s.cost_total),0),coalesce(sum(s.gross_profit),0) into v_revenue,v_cogs,v_gp
  from public.sales s left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
  where s.tenant_id=p_tenant_id and s.sale_date between p_from_date and p_to_date and coalesce(s.status,'') not in ('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
  select coalesce(sum(e.total_amount),0) into v_exp from public.expenses e left join public.document_origins o on o.entity_type='expense' and o.entity_id=e.id
  where e.tenant_id=p_tenant_id and e.expense_date between p_from_date and p_to_date and e.status='posted' and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
  select coalesce(sum(greatest(s.grand_total-coalesce(py.paid,0),0)),0) into v_recv from public.sales s left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in ('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
  select coalesce(sum(greatest(p.grand_total-coalesce(py.paid,0),0)),0) into v_pay from public.purchases p left join (select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id)py on py.purchase_id=p.id left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in ('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
  select coalesce(sum(sb.quantity*pv.cost_price),0) into v_stock from public.stock_balances sb join public.product_variants pv on pv.id=sb.variant_id where sb.tenant_id=p_tenant_id;
  return jsonb_build_object('revenue',v_revenue,'cost_of_goods_sold',v_cogs,'gross_profit',v_gp,'operating_expenses',v_exp,'net_operating_profit',v_gp-v_exp,'receivables',v_recv,'payables',v_pay,'inventory_value',v_stock,'location_id',p_location_id,'stock_scope','business');
end $$;
grant execute on function public.accounting_get_summary_v32(uuid,date,date,uuid) to authenticated;

create or replace function public.accounting_list_ledger_v32(p_tenant_id uuid,p_from_date date,p_to_date date,p_location_id uuid default null)
returns table(entry_date date,entry_type text,reference text,party text,description text,debit numeric,credit numeric)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select x.entry_date,x.entry_type,x.reference,x.party,x.description,x.debit,x.credit from (
    select s.sale_date entry_date,'sale'::text entry_type,coalesce(dn.terminal_number,ln.local_number,s.sale_number) reference,c.name party,'Sales invoice'::text description,s.grand_total::numeric debit,0::numeric credit
    from public.sales s join public.customers c on c.id=s.customer_id left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id left join public.location_document_numbers ln on ln.entity_type='sale' and ln.entity_id=s.id left join public.device_document_numbers dn on dn.entity_type='sale' and dn.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.sale_date between p_from_date and p_to_date and coalesce(s.status,'') not in ('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
    union all
    select p.purchase_date,'purchase',coalesce(dn.terminal_number,ln.local_number,p.purchase_number),sp.name,'Purchase bill',p.grand_total::numeric,0::numeric
    from public.purchases p join public.suppliers sp on sp.id=p.supplier_id left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id left join public.location_document_numbers ln on ln.entity_type='purchase' and ln.entity_id=p.id left join public.device_document_numbers dn on dn.entity_type='purchase' and dn.entity_id=p.id
    where p.tenant_id=p_tenant_id and p.purchase_date between p_from_date and p_to_date and coalesce(p.status,'') not in ('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
    union all
    select e.expense_date,'expense',coalesce(dn.terminal_number,ln.local_number,e.expense_number),coalesce(e.payee,''),e.description,e.total_amount::numeric,0::numeric
    from public.expenses e left join public.document_origins o on o.entity_type='expense' and o.entity_id=e.id left join public.location_document_numbers ln on ln.entity_type='expense' and ln.entity_id=e.id left join public.device_document_numbers dn on dn.entity_type='expense' and dn.entity_id=e.id
    where e.tenant_id=p_tenant_id and e.expense_date between p_from_date and p_to_date and e.status='posted' and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
  )x order by x.entry_date desc,x.reference desc;
end $$;
grant execute on function public.accounting_list_ledger_v32(uuid,date,date,uuid) to authenticated;

-- Global search used by the Client menu. Search is intentionally capped and respects store scope for documents.
create or replace function public.global_search_v32(p_tenant_id uuid,p_query text,p_limit integer default 40)
returns table(entity_type text,entity_id uuid,public_id text,title text,subtitle text,module_key text,location_id uuid)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';lim int:=greatest(5,least(coalesce(p_limit,40),100));begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if trim(coalesce(p_query,''))='' then return;end if;
  return query
  select * from (
    select 'product'::text,pv.id,p.tracking_code,p.name,coalesce('SKU '||pv.sku||case when pv.part_number is not null and pv.part_number<>'' then ' • Part '||pv.part_number else '' end,''),'inventory'::text,null::uuid
      from public.products p join public.product_variants pv on pv.product_id=p.id and pv.tenant_id=p.tenant_id
      where p.tenant_id=p_tenant_id and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'inventory.view') or private.erp_has_permission(p_tenant_id,'inventory.manage')) and (lower(p.name) like q or lower(pv.sku) like q or lower(coalesce(pv.barcode,'')) like q or lower(coalesce(pv.part_number,'')) like q or lower(coalesce(p.tracking_code,'')) like q)
    union all
    select 'customer',c.id,c.tracking_code,c.name,coalesce(c.phone,''),'customers',null::uuid from public.customers c where c.tenant_id=p_tenant_id and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'customers.view') or private.erp_has_permission(p_tenant_id,'customers.manage')) and (lower(c.name) like q or lower(coalesce(c.phone,'')) like q or lower(coalesce(c.tracking_code,'')) like q)
    union all
    select 'supplier',s.id,s.tracking_code,s.name,coalesce(s.phone,''),'suppliers',null::uuid from public.suppliers s where s.tenant_id=p_tenant_id and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'suppliers.view') or private.erp_has_permission(p_tenant_id,'suppliers.manage')) and (lower(s.name) like q or lower(coalesce(s.phone,'')) like q or lower(coalesce(s.tracking_code,'')) like q)
    union all
    select 'sale',s.id,s.tracking_code,coalesce(dn.terminal_number,ln.local_number,s.sale_number),c.name,'sales',o.location_id from public.sales s join public.customers c on c.id=s.customer_id left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id left join public.location_document_numbers ln on ln.entity_type='sale' and ln.entity_id=s.id left join public.device_document_numbers dn on dn.entity_type='sale' and dn.entity_id=s.id where s.tenant_id=p_tenant_id and private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view') and (lower(s.sale_number) like q or lower(coalesce(s.tracking_code,'')) like q or lower(c.name) like q or lower(coalesce(dn.terminal_number,ln.local_number,'')) like q)
    union all
    select 'purchase',p.id,p.tracking_code,coalesce(dn.terminal_number,ln.local_number,p.purchase_number),sp.name,'purchases',o.location_id from public.purchases p join public.suppliers sp on sp.id=p.supplier_id left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id left join public.location_document_numbers ln on ln.entity_type='purchase' and ln.entity_id=p.id left join public.device_document_numbers dn on dn.entity_type='purchase' and dn.entity_id=p.id where p.tenant_id=p_tenant_id and private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view') and (lower(p.purchase_number) like q or lower(coalesce(p.tracking_code,'')) like q or lower(sp.name) like q or lower(coalesce(dn.terminal_number,ln.local_number,'')) like q)
  )z limit lim;
end $$;
grant execute on function public.global_search_v32(uuid,text,integer) to authenticated;



create or replace function public.sales_resolve_number_v32(p_tenant_id uuid,p_sale_number text)
returns uuid language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid;v_loc uuid;begin
  select s.id,o.location_id into v_id,v_loc from public.sales s left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
  where s.tenant_id=p_tenant_id and s.sale_number=p_sale_number order by s.created_at desc limit 1;
  if v_id is null then return null;end if;
  if not private.erp_document_scope_allowed(p_tenant_id,v_loc,null,'view') then raise exception 'Location access denied';end if;
  return v_id;
end $$;
grant execute on function public.sales_resolve_number_v32(uuid,text) to authenticated;


-- Location-aware dashboard, insights and pending-payment center.
create or replace function public.dashboard_get_summary_v32(p_tenant_id uuid,p_location_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare
  v_today_sales numeric:=0;v_month_sales numeric:=0;v_month_purchases numeric:=0;v_month_expenses numeric:=0;v_month_gp numeric:=0;
  v_receivables numeric:=0;v_payables numeric:=0;v_low int:=0;v_products int:=0;v_customers int:=0;v_suppliers int:=0;
  v_start date:=date_trunc('month',current_date)::date;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select coalesce(sum(s.grand_total),0) into v_today_sales from public.sales s left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.sale_date=current_date and coalesce(s.status,'') not in ('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
  select coalesce(sum(s.grand_total),0),coalesce(sum(s.gross_profit),0) into v_month_sales,v_month_gp from public.sales s left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.sale_date between v_start and current_date and coalesce(s.status,'') not in ('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
  select coalesce(sum(p.grand_total),0) into v_month_purchases from public.purchases p left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id
    where p.tenant_id=p_tenant_id and p.purchase_date between v_start and current_date and coalesce(p.status,'') not in ('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
  select coalesce(sum(e.total_amount),0) into v_month_expenses from public.expenses e left join public.document_origins o on o.entity_type='expense' and o.entity_id=e.id
    where e.tenant_id=p_tenant_id and e.expense_date between v_start and current_date and e.status='posted' and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
  select coalesce(sum(greatest(s.grand_total-coalesce(py.paid,0),0)),0) into v_receivables from public.sales s
    left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
    left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in ('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
  select coalesce(sum(greatest(p.grand_total-coalesce(py.paid,0),0)),0) into v_payables from public.purchases p
    left join (select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id)py on py.purchase_id=p.id
    left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id
    where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in ('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
  -- Master/product counts and stock warning remain tenant-wide until physical branch stock RPCs are upgraded.
  select count(*) into v_products from public.products where tenant_id=p_tenant_id and coalesce(status,'active')='active';
  select count(*) into v_customers from public.customers where tenant_id=p_tenant_id and coalesce(status,'active')='active';
  select count(*) into v_suppliers from public.suppliers where tenant_id=p_tenant_id and coalesce(status,'active')='active';
  select count(*) into v_low from public.stock_balances sb join public.product_variants pv on pv.id=sb.variant_id where sb.tenant_id=p_tenant_id and sb.quantity<=coalesce(pv.reorder_level,0) and coalesce(pv.reorder_level,0)>0;
  return jsonb_build_object('today_sales',v_today_sales,'month_sales',v_month_sales,'month_purchases',v_month_purchases,'month_expenses',v_month_expenses,
    'month_gross_profit',v_month_gp,'month_net_profit',v_month_gp-v_month_expenses,'receivables',v_receivables,'payables',v_payables,
    'low_stock_count',v_low,'product_count',v_products,'customer_count',v_customers,'supplier_count',v_suppliers,'stock_scope','business');
end $$;
grant execute on function public.dashboard_get_summary_v32(uuid,uuid) to authenticated;

create or replace function public.dashboard_v3_insights_v32(p_tenant_id uuid,p_location_id uuid default null,p_from_date date default (current_date-interval '29 days')::date,p_to_date date default current_date)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_top_products jsonb;v_top_customers jsonb;v_daily jsonb;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select coalesce(jsonb_agg(jsonb_build_object('variant_id',variant_id,'product_name',product_name,'quantity',qty,'sales',sales) order by sales desc),'[]'::jsonb) into v_top_products from (
    select si.variant_id,max(coalesce(pr.name,'Product')) product_name,sum(si.quantity)::numeric qty,sum(si.line_total)::numeric sales
    from public.sale_items si join public.sales s on s.id=si.sale_id left join public.product_variants pv on pv.id=si.variant_id left join public.products pr on pr.id=pv.product_id
    left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.sale_date between p_from_date and p_to_date and coalesce(s.status,'') not in ('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
    group by si.variant_id order by sales desc limit 10
  )x;
  select coalesce(jsonb_agg(jsonb_build_object('customer_id',customer_id,'customer_name',customer_name,'sales',sales,'invoice_count',invoice_count) order by sales desc),'[]'::jsonb) into v_top_customers from (
    select s.customer_id,max(c.name) customer_name,sum(s.grand_total)::numeric sales,count(*)::int invoice_count from public.sales s join public.customers c on c.id=s.customer_id
    left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.sale_date between p_from_date and p_to_date and coalesce(s.status,'') not in ('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
    group by s.customer_id order by sales desc limit 10
  )x;
  select coalesce(jsonb_agg(jsonb_build_object('date',d.day,'sales',coalesce(x.sales,0)) order by d.day),'[]'::jsonb) into v_daily
  from generate_series(p_from_date::timestamp,p_to_date::timestamp,interval '1 day')d(day)
  left join (
    select s.sale_date,sum(s.grand_total)::numeric sales from public.sales s left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.sale_date between p_from_date and p_to_date and coalesce(s.status,'') not in ('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view') group by s.sale_date
  )x on x.sale_date=d.day::date;
  return jsonb_build_object('top_products',v_top_products,'top_customers',v_top_customers,'daily_sales',v_daily);
end $$;
grant execute on function public.dashboard_v3_insights_v32(uuid,uuid,date,date) to authenticated;

create or replace function public.payments_pending_list_v32(p_tenant_id uuid,p_location_id uuid default null,p_limit integer default 300)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_rec jsonb;v_pay jsonb;v_lim int:=greatest(1,least(coalesce(p_limit,300),1000));begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_has_permission(p_tenant_id,'payments.view') and not private.erp_has_permission(p_tenant_id,'sales.manage') and not private.erp_has_permission(p_tenant_id,'purchases.manage') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Permission denied';end if;
  select coalesce(jsonb_agg(x order by (x->>'date')::date desc),'[]'::jsonb) into v_rec from (
    select jsonb_build_object('id',s.id,'type','receivable','reference',coalesce(dn.terminal_number,ln.local_number,s.sale_number),'party_id',s.customer_id,'party_name',c.name,'date',s.sale_date,'due_date',s.due_date,'total',s.grand_total,'paid',coalesce(py.paid,0),'balance',s.grand_total-coalesce(py.paid,0),'location_id',o.location_id,'location_name',l.name) x
    from public.sales s join public.customers c on c.id=s.customer_id left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
    left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id left join public.business_locations l on l.id=o.location_id
    left join public.location_document_numbers ln on ln.entity_type='sale' and ln.entity_id=s.id left join public.device_document_numbers dn on dn.entity_type='sale' and dn.entity_id=s.id
    where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in ('cancelled','void') and s.grand_total-coalesce(py.paid,0)>0.005 and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view') limit v_lim
  )q;
  select coalesce(jsonb_agg(x order by (x->>'date')::date desc),'[]'::jsonb) into v_pay from (
    select jsonb_build_object('id',p.id,'type','payable','reference',coalesce(dn.terminal_number,ln.local_number,p.purchase_number),'party_id',p.supplier_id,'party_name',s.name,'date',p.purchase_date,'due_date',p.due_date,'total',p.grand_total,'paid',coalesce(py.paid,0),'balance',p.grand_total-coalesce(py.paid,0),'location_id',o.location_id,'location_name',l.name) x
    from public.purchases p join public.suppliers s on s.id=p.supplier_id left join (select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id)py on py.purchase_id=p.id
    left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id left join public.business_locations l on l.id=o.location_id
    left join public.location_document_numbers ln on ln.entity_type='purchase' and ln.entity_id=p.id left join public.device_document_numbers dn on dn.entity_type='purchase' and dn.entity_id=p.id
    where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in ('cancelled','void') and p.grand_total-coalesce(py.paid,0)>0.005 and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view') limit v_lim
  )q;
  return jsonb_build_object('receivables',v_rec,'payables',v_pay);
end $$;
grant execute on function public.payments_pending_list_v32(uuid,uuid,integer) to authenticated;

commit;
select 'V3.2 scoped operations/search ready' as status;
