-- FLEXI ERP V4 return/void accounting + return-aware balances and summaries.
-- This migration completes the financial side of 033_v4_returns_reversals.sql.
begin;

-- Dedicated credit balances make paid returns/account credits explicit instead of
-- forcing them into cash or silently making AR/AP negative.
insert into public.accounting_accounts(tenant_id,code,name,account_type,system_key,is_system,description)
select t.id,x.code,x.name,x.type,x.key,true,x.description
from public.tenants t
cross join (values
  ('2050','Customer Refunds / Credits','liability','customer_credits','Amounts owed or credited to customers after returns'),
  ('1150','Supplier Credits','asset','supplier_credits','Credits/refunds due from suppliers after purchase returns')
) x(code,name,type,key,description)
on conflict(tenant_id,code) do nothing;

insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id)
select a.tenant_id,a.system_key,a.id
from public.accounting_accounts a
where a.system_key in('customer_credits','supplier_credits')
on conflict(tenant_id,mapping_key) do nothing;

create or replace function private.v4_post_sales_return(p_return_id uuid)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  r public.sales_returns%rowtype;
  v_sale public.sales%rowtype;
  v_paid numeric:=0;
  v_previous_returns numeric:=0;
  v_outstanding_before numeric:=0;
  v_ar_reduce numeric:=0;
  v_customer_credit numeric:=0;
  v_cost numeric:=0;
  v_lines jsonb:='[]'::jsonb;
begin
  select * into r from public.sales_returns where id=p_return_id;
  if not found or coalesce(r.grand_total,0)<=0 then return null; end if;
  select * into v_sale from public.sales where id=r.sale_id and tenant_id=r.tenant_id;
  if not found then return null; end if;

  if exists(select 1 from public.journal_entries where tenant_id=r.tenant_id and source_type='sales_return' and source_id=r.id and status='posted') then
    return (select id from public.journal_entries where tenant_id=r.tenant_id and source_type='sales_return' and source_id=r.id and status='posted' limit 1);
  end if;

  select coalesce(sum(amount),0) into v_paid from public.sale_payments where sale_id=r.sale_id;
  select coalesce(sum(grand_total),0) into v_previous_returns
  from public.sales_returns
  where sale_id=r.sale_id and id<>r.id and created_at<=r.created_at and refund_status<>'waived';

  v_outstanding_before:=greatest(coalesce(v_sale.grand_total,0)-v_paid-v_previous_returns,0);
  v_ar_reduce:=least(coalesce(r.grand_total,0),v_outstanding_before);
  v_customer_credit:=greatest(coalesce(r.grand_total,0)-v_ar_reduce,0);

  select coalesce(sum(coalesce(si.cost_total,0)*(ri.quantity/nullif(si.quantity,0))),0)
  into v_cost
  from public.sales_return_items ri
  join public.sale_items si on si.id=ri.sale_item_id
  where ri.sales_return_id=r.id;

  if coalesce(r.subtotal,0)>0 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'account_id',private.v4_account_id(r.tenant_id,'sales_revenue'),'debit',r.subtotal,'credit',0,
      'party_type','customer','party_id',v_sale.customer_id,'description','Sales return revenue reversal'));
  end if;
  if coalesce(r.tax_total,0)>0 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'account_id',private.v4_account_id(r.tenant_id,'output_gst'),'debit',r.tax_total,'credit',0,
      'description','Sales return GST reversal'));
  end if;
  if v_ar_reduce>0 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'account_id',private.v4_account_id(r.tenant_id,'accounts_receivable'),'debit',0,'credit',v_ar_reduce,
      'party_type','customer','party_id',v_sale.customer_id,'description','Reduce customer receivable'));
  end if;
  if v_customer_credit>0 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'account_id',private.v4_account_id(r.tenant_id,'customer_credits'),'debit',0,'credit',v_customer_credit,
      'party_type','customer','party_id',v_sale.customer_id,'description','Customer return credit / refund due'));
  end if;
  if v_cost>0 then
    v_lines:=v_lines||jsonb_build_array(
      jsonb_build_object('account_id',private.v4_account_id(r.tenant_id,'inventory_asset'),'debit',v_cost,'credit',0,'description','Returned inventory restored'),
      jsonb_build_object('account_id',private.v4_account_id(r.tenant_id,'cogs'),'debit',0,'credit',v_cost,'description','COGS reversed for returned goods')
    );
  end if;

  return private.v4_journal_create(r.tenant_id,r.location_id,r.return_date,'Sales return '||r.return_number,'sales_return',r.id,r.return_number,v_lines);
end $$;
revoke all on function private.v4_post_sales_return(uuid) from public;

create or replace function private.v4_post_purchase_return(p_return_id uuid)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  r public.purchase_returns%rowtype;
  v_purchase public.purchases%rowtype;
  v_paid numeric:=0;
  v_previous_returns numeric:=0;
  v_payable_before numeric:=0;
  v_ap_reduce numeric:=0;
  v_supplier_credit numeric:=0;
  v_lines jsonb:='[]'::jsonb;
begin
  select * into r from public.purchase_returns where id=p_return_id;
  if not found or coalesce(r.grand_total,0)<=0 then return null; end if;
  select * into v_purchase from public.purchases where id=r.purchase_id and tenant_id=r.tenant_id;
  if not found then return null; end if;

  if exists(select 1 from public.journal_entries where tenant_id=r.tenant_id and source_type='purchase_return' and source_id=r.id and status='posted') then
    return (select id from public.journal_entries where tenant_id=r.tenant_id and source_type='purchase_return' and source_id=r.id and status='posted' limit 1);
  end if;

  select coalesce(sum(amount),0) into v_paid from public.purchase_payments where purchase_id=r.purchase_id;
  select coalesce(sum(grand_total),0) into v_previous_returns
  from public.purchase_returns
  where purchase_id=r.purchase_id and id<>r.id and created_at<=r.created_at and credit_status<>'waived';

  v_payable_before:=greatest(coalesce(v_purchase.grand_total,0)-v_paid-v_previous_returns,0);
  v_ap_reduce:=least(coalesce(r.grand_total,0),v_payable_before);
  v_supplier_credit:=greatest(coalesce(r.grand_total,0)-v_ap_reduce,0);

  if v_ap_reduce>0 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'account_id',private.v4_account_id(r.tenant_id,'accounts_payable'),'debit',v_ap_reduce,'credit',0,
      'party_type','supplier','party_id',v_purchase.supplier_id,'description','Reduce supplier payable'));
  end if;
  if v_supplier_credit>0 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'account_id',private.v4_account_id(r.tenant_id,'supplier_credits'),'debit',v_supplier_credit,'credit',0,
      'party_type','supplier','party_id',v_purchase.supplier_id,'description','Supplier return credit / refund due'));
  end if;
  if coalesce(r.subtotal,0)>0 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'account_id',private.v4_account_id(r.tenant_id,'inventory_asset'),'debit',0,'credit',r.subtotal,
      'party_type','supplier','party_id',v_purchase.supplier_id,'description','Purchase return inventory reduction'));
  end if;
  if coalesce(r.tax_total,0)>0 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'account_id',private.v4_account_id(r.tenant_id,'input_gst'),'debit',0,'credit',r.tax_total,
      'description','Purchase return input GST reversal'));
  end if;

  return private.v4_journal_create(r.tenant_id,r.location_id,r.return_date,'Purchase return '||r.return_number,'purchase_return',r.id,r.return_number,v_lines);
end $$;
revoke all on function private.v4_post_purchase_return(uuid) from public;

create or replace function private.v4_reverse_source_journal(p_tenant_id uuid,p_source_type text,p_source_id uuid,p_reversal_type text,p_description text)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_original public.journal_entries%rowtype;
  v_lines jsonb;
  v_id uuid;
begin
  select * into v_original
  from public.journal_entries
  where tenant_id=p_tenant_id and source_type=p_source_type and source_id=p_source_id and status='posted'
  order by created_at limit 1;
  if not found then return null; end if;

  if exists(select 1 from public.journal_entries where tenant_id=p_tenant_id and source_type=p_reversal_type and source_id=p_source_id and status='posted') then
    return (select id from public.journal_entries where tenant_id=p_tenant_id and source_type=p_reversal_type and source_id=p_source_id and status='posted' limit 1);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'account_id',l.account_id,
    'party_type',l.party_type,
    'party_id',l.party_id,
    'description','Reversal • '||coalesce(l.description,v_original.description),
    'debit',l.credit,
    'credit',l.debit
  ) order by l.id),'[]'::jsonb)
  into v_lines
  from public.journal_lines l
  where l.journal_entry_id=v_original.id;

  v_id:=private.v4_journal_create(p_tenant_id,v_original.location_id,current_date,p_description,p_reversal_type,p_source_id,v_original.source_reference,v_lines);
  update public.journal_entries set reversal_of=v_original.id where id=v_id;
  return v_id;
end $$;
revoke all on function private.v4_reverse_source_journal(uuid,text,uuid,text,text) from public;

create or replace function private.v4_sales_return_accounting_trigger()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if coalesce(new.grand_total,0)>0 and (tg_op='INSERT' or coalesce(old.grand_total,0)<>coalesce(new.grand_total,0)) then
    perform private.v4_post_sales_return(new.id);
  end if;
  return new;
end $$;
drop trigger if exists trg_v4_sales_return_accounting on public.sales_returns;
create trigger trg_v4_sales_return_accounting after insert or update of grand_total on public.sales_returns for each row execute function private.v4_sales_return_accounting_trigger();

create or replace function private.v4_purchase_return_accounting_trigger()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if coalesce(new.grand_total,0)>0 and (tg_op='INSERT' or coalesce(old.grand_total,0)<>coalesce(new.grand_total,0)) then
    perform private.v4_post_purchase_return(new.id);
  end if;
  return new;
end $$;
drop trigger if exists trg_v4_purchase_return_accounting on public.purchase_returns;
create trigger trg_v4_purchase_return_accounting after insert or update of grand_total on public.purchase_returns for each row execute function private.v4_purchase_return_accounting_trigger();

create or replace function private.v4_sale_void_accounting_trigger()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if coalesce(old.status,'')<>'void' and coalesce(new.status,'')='void' then
    perform private.v4_reverse_source_journal(new.tenant_id,'sale',new.id,'sale_void','Void sale '||coalesce(new.sale_number,''));
  end if;
  return new;
end $$;
drop trigger if exists trg_v4_sale_void_accounting on public.sales;
create trigger trg_v4_sale_void_accounting after update of status on public.sales for each row execute function private.v4_sale_void_accounting_trigger();

create or replace function private.v4_purchase_void_accounting_trigger()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if coalesce(old.status,'')<>'void' and coalesce(new.status,'')='void' then
    perform private.v4_reverse_source_journal(new.tenant_id,'purchase',new.id,'purchase_void','Void purchase '||coalesce(new.purchase_number,''));
  end if;
  return new;
end $$;
drop trigger if exists trg_v4_purchase_void_accounting on public.purchases;
create trigger trg_v4_purchase_void_accounting after update of status on public.purchases for each row execute function private.v4_purchase_void_accounting_trigger();

-- Backfill any return/void journals that existed before this migration.
do $$ declare r record; begin
  for r in select id from public.sales_returns where grand_total>0 loop begin perform private.v4_post_sales_return(r.id); exception when others then null; end; end loop;
  for r in select id from public.purchase_returns where grand_total>0 loop begin perform private.v4_post_purchase_return(r.id); exception when others then null; end; end loop;
  for r in select tenant_id,id,sale_number from public.sales where status='void' loop begin perform private.v4_reverse_source_journal(r.tenant_id,'sale',r.id,'sale_void','Void sale '||coalesce(r.sale_number,'')); exception when others then null; end; end loop;
  for r in select tenant_id,id,purchase_number from public.purchases where status='void' loop begin perform private.v4_reverse_source_journal(r.tenant_id,'purchase',r.id,'purchase_void','Void purchase '||coalesce(r.purchase_number,'')); exception when others then null; end; end loop;
end $$;

-- Return-aware pending receivables/payables.
create or replace function public.payments_pending_list_v4(p_tenant_id uuid,p_location_id uuid default null,p_limit integer default 300)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_rec jsonb;v_pay jsonb;v_lim int:=greatest(1,least(coalesce(p_limit,300),1000));begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_has_permission(p_tenant_id,'payments.view') and not private.erp_has_permission(p_tenant_id,'sales.manage') and not private.erp_has_permission(p_tenant_id,'purchases.manage') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Permission denied';end if;

  select coalesce(jsonb_agg(x order by (x->>'date')::date desc),'[]'::jsonb) into v_rec from (
    select jsonb_build_object(
      'id',s.id,'type','receivable','reference',coalesce(dn.terminal_number,ln.local_number,s.sale_number),
      'party_id',s.customer_id,'party_name',c.name,'date',s.sale_date,'due_date',s.due_date,'total',s.grand_total,
      'paid',coalesce(py.paid,0),'returned',coalesce(rt.returned,0),
      'balance',greatest(s.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0),
      'location_id',o.location_id,'location_name',l.name
    ) x
    from public.sales s
    join public.customers c on c.id=s.customer_id
    left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id) py on py.sale_id=s.id
    left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id) rt on rt.sale_id=s.id
    left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
    left join public.business_locations l on l.id=o.location_id
    left join public.location_document_numbers ln on ln.entity_type='sale' and ln.entity_id=s.id
    left join public.device_document_numbers dn on dn.entity_type='sale' and dn.entity_id=s.id
    where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('cancelled','void')
      and greatest(s.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)>0.005
      and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
    order by s.sale_date desc limit v_lim
  ) q;

  select coalesce(jsonb_agg(x order by (x->>'date')::date desc),'[]'::jsonb) into v_pay from (
    select jsonb_build_object(
      'id',p.id,'type','payable','reference',coalesce(dn.terminal_number,ln.local_number,p.purchase_number),
      'party_id',p.supplier_id,'party_name',s.name,'date',p.purchase_date,'due_date',p.due_date,'total',p.grand_total,
      'paid',coalesce(py.paid,0),'returned',coalesce(rt.returned,0),
      'balance',greatest(p.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0),
      'location_id',o.location_id,'location_name',l.name
    ) x
    from public.purchases p
    join public.suppliers s on s.id=p.supplier_id
    left join (select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id=p.id
    left join (select purchase_id,sum(grand_total) returned from public.purchase_returns where credit_status<>'waived' group by purchase_id) rt on rt.purchase_id=p.id
    left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id
    left join public.business_locations l on l.id=o.location_id
    left join public.location_document_numbers ln on ln.entity_type='purchase' and ln.entity_id=p.id
    left join public.device_document_numbers dn on dn.entity_type='purchase' and dn.entity_id=p.id
    where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('cancelled','void')
      and greatest(p.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)>0.005
      and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
    order by p.purchase_date desc limit v_lim
  ) q;

  return jsonb_build_object('receivables',v_rec,'payables',v_pay);
end $$;
grant execute on function public.payments_pending_list_v4(uuid,uuid,integer) to authenticated;

-- Journal-based accounting summary. Period income/expense comes from posted journals;
-- branch physical stock valuation comes from location_stock_balances.
create or replace function public.accounting_get_summary_v4(p_tenant_id uuid,p_from_date date,p_to_date date,p_location_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_revenue numeric:=0;v_cogs numeric:=0;v_exp numeric:=0;v_recv numeric:=0;v_pay numeric:=0;v_stock numeric:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_has_permission(p_tenant_id,'accounting.view') and not private.erp_has_permission(p_tenant_id,'accounting.manage') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Accounting permission required';end if;
  if p_from_date is null or p_to_date is null or p_from_date>p_to_date then raise exception 'Invalid date range';end if;

  select
    coalesce(sum(case when a.account_type='income' then l.credit-l.debit else 0 end),0),
    coalesce(sum(case when a.account_type='cogs' then l.debit-l.credit else 0 end),0),
    coalesce(sum(case when a.account_type='expense' then l.debit-l.credit else 0 end),0)
  into v_revenue,v_cogs,v_exp
  from public.journal_entries j
  join public.journal_lines l on l.journal_entry_id=j.id
  join public.accounting_accounts a on a.id=l.account_id and a.tenant_id=j.tenant_id
  where j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date between p_from_date and p_to_date
    and (p_location_id is null or j.location_id=p_location_id)
    and (j.location_id is null or private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view'));

  select
    coalesce(sum(case when a.system_key='accounts_receivable' then l.debit-l.credit else 0 end),0),
    coalesce(sum(case when a.system_key='accounts_payable' then l.credit-l.debit else 0 end),0)
  into v_recv,v_pay
  from public.journal_entries j
  join public.journal_lines l on l.journal_entry_id=j.id
  join public.accounting_accounts a on a.id=l.account_id and a.tenant_id=j.tenant_id
  where j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date<=p_to_date
    and (p_location_id is null or j.location_id=p_location_id)
    and (j.location_id is null or private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view'));

  select coalesce(sum(coalesce(b.quantity,0)*coalesce(nullif(b.average_cost,0),pv.cost_price,0)),0)
  into v_stock
  from public.location_product_settings s
  join public.product_variants pv on pv.id=s.variant_id
  join public.business_locations bl on bl.id=s.location_id and bl.active
  left join public.location_stock_balances b on b.tenant_id=s.tenant_id and b.location_id=s.location_id and b.variant_id=s.variant_id
  where s.tenant_id=p_tenant_id and s.active
    and (p_location_id is null or s.location_id=p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id,s.location_id,p_location_id,'view');

  return jsonb_build_object(
    'revenue',v_revenue,
    'cost_of_goods_sold',v_cogs,
    'gross_profit',v_revenue-v_cogs,
    'operating_expenses',v_exp,
    'net_operating_profit',v_revenue-v_cogs-v_exp,
    'receivables',greatest(v_recv,0),
    'payables',greatest(v_pay,0),
    'inventory_value',v_stock,
    'location_id',p_location_id,
    'stock_scope',case when p_location_id is null then 'accessible_locations' else 'location' end
  );
end $$;
grant execute on function public.accounting_get_summary_v4(uuid,date,date,uuid) to authenticated;

-- Upgrade dashboard values that should be return-aware while preserving V4 branch stock counts.
create or replace function public.dashboard_get_summary_v4(p_tenant_id uuid,p_location_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v jsonb;v_low integer:=0;v_products integer:=0;v_receivables numeric:=0;v_payables numeric:=0;
  v_today_returns numeric:=0;v_month_returns numeric:=0;v_month_purchase_returns numeric:=0;v_start date:=date_trunc('month',current_date)::date;
begin
  select public.dashboard_get_summary_v32(p_tenant_id,p_location_id) into v;

  select count(*) into v_products
  from public.location_product_settings s join public.business_locations l on l.id=s.location_id
  where s.tenant_id=p_tenant_id and s.active and l.active and (p_location_id is null or s.location_id=p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id,s.location_id,p_location_id,'view');

  select count(*) into v_low
  from public.location_product_settings s join public.product_variants pv on pv.id=s.variant_id join public.business_locations l on l.id=s.location_id
  left join public.location_stock_balances b on b.tenant_id=s.tenant_id and b.location_id=s.location_id and b.variant_id=s.variant_id
  where s.tenant_id=p_tenant_id and s.active and l.active and (p_location_id is null or s.location_id=p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id,s.location_id,p_location_id,'view')
    and coalesce(s.reorder_level,pv.reorder_level,0)>0 and coalesce(b.quantity,0)<=coalesce(s.reorder_level,pv.reorder_level,0);

  select coalesce(sum(r.grand_total),0) into v_today_returns from public.sales_returns r
  where r.tenant_id=p_tenant_id and r.return_date=current_date and r.refund_status<>'waived'
    and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view');
  select coalesce(sum(r.grand_total),0) into v_month_returns from public.sales_returns r
  where r.tenant_id=p_tenant_id and r.return_date between v_start and current_date and r.refund_status<>'waived'
    and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view');
  select coalesce(sum(r.grand_total),0) into v_month_purchase_returns from public.purchase_returns r
  where r.tenant_id=p_tenant_id and r.return_date between v_start and current_date and r.credit_status<>'waived'
    and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view');

  select coalesce(sum(greatest(s.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)),0) into v_receivables
  from public.sales s
  left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id) py on py.sale_id=s.id
  left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id) rt on rt.sale_id=s.id
  left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
  where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');

  select coalesce(sum(greatest(p.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)),0) into v_payables
  from public.purchases p
  left join (select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id=p.id
  left join (select purchase_id,sum(grand_total) returned from public.purchase_returns where credit_status<>'waived' group by purchase_id) rt on rt.purchase_id=p.id
  left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id
  where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');

  return coalesce(v,'{}'::jsonb)||jsonb_build_object(
    'today_sales',greatest(coalesce((v->>'today_sales')::numeric,0)-v_today_returns,0),
    'month_sales',greatest(coalesce((v->>'month_sales')::numeric,0)-v_month_returns,0),
    'month_purchases',greatest(coalesce((v->>'month_purchases')::numeric,0)-v_month_purchase_returns,0),
    'receivables',v_receivables,'payables',v_payables,'product_count',v_products,'low_stock_count',v_low,
    'sales_returns_month',v_month_returns,'purchase_returns_month',v_month_purchase_returns
  );
end $$;
grant execute on function public.dashboard_get_summary_v4(uuid,uuid) to authenticated;

-- Return-aware operational report plus physical branch stock value.
create or replace function public.reports_get_summary_v4(p_tenant_id uuid,p_from_date date,p_to_date date,p_location_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v jsonb;v_stock numeric:=0;v_sr numeric:=0;v_pr numeric:=0;v_sr_profit numeric:=0;v_recv numeric:=0;v_pay numeric:=0;
begin
  select public.reports_get_summary_v32(p_tenant_id,p_from_date,p_to_date,p_location_id) into v;
  select coalesce(sum(r.grand_total),0),coalesce(sum(r.subtotal-coalesce(c.return_cost,0)),0)
  into v_sr,v_sr_profit
  from public.sales_returns r
  left join (
    select ri.sales_return_id,sum(coalesce(si.cost_total,0)*(ri.quantity/nullif(si.quantity,0))) return_cost
    from public.sales_return_items ri join public.sale_items si on si.id=ri.sale_item_id group by ri.sales_return_id
  ) c on c.sales_return_id=r.id
  where r.tenant_id=p_tenant_id and r.return_date between p_from_date and p_to_date and r.refund_status<>'waived'
    and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view');
  select coalesce(sum(r.grand_total),0) into v_pr from public.purchase_returns r
  where r.tenant_id=p_tenant_id and r.return_date between p_from_date and p_to_date and r.credit_status<>'waived'
    and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view');

  select coalesce(sum(greatest(s.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)),0) into v_recv
  from public.sales s left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
  left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id
  left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
  where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
  select coalesce(sum(greatest(p.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0)),0) into v_pay
  from public.purchases p left join (select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id)py on py.purchase_id=p.id
  left join (select purchase_id,sum(grand_total) returned from public.purchase_returns where credit_status<>'waived' group by purchase_id)rt on rt.purchase_id=p.id
  left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id
  where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('cancelled','void') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');

  select coalesce(sum(coalesce(b.quantity,0)*coalesce(nullif(b.average_cost,0),pv.cost_price,0)),0) into v_stock
  from public.location_product_settings s join public.product_variants pv on pv.id=s.variant_id join public.business_locations bl on bl.id=s.location_id and bl.active
  left join public.location_stock_balances b on b.tenant_id=s.tenant_id and b.location_id=s.location_id and b.variant_id=s.variant_id
  where s.tenant_id=p_tenant_id and s.active and (p_location_id is null or s.location_id=p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id,s.location_id,p_location_id,'view');

  return coalesce(v,'{}'::jsonb)||jsonb_build_object(
    'sales',greatest(coalesce((v->>'sales')::numeric,0)-v_sr,0),
    'purchases',greatest(coalesce((v->>'purchases')::numeric,0)-v_pr,0),
    'gross_profit',coalesce((v->>'gross_profit')::numeric,0)-v_sr_profit,
    'net_profit',coalesce((v->>'gross_profit')::numeric,0)-v_sr_profit-coalesce((v->>'expenses')::numeric,0),
    'receivables',v_recv,'payables',v_pay,'stock_value',v_stock,
    'sales_returns',v_sr,'purchase_returns',v_pr,'stock_scope',case when p_location_id is null then 'accessible_locations' else 'location' end
  );
end $$;
grant execute on function public.reports_get_summary_v4(uuid,date,date,uuid) to authenticated;

commit;
select 'Flexi ERP V4 return-aware accounting and balances ready' as status;
