-- THQ ERP v4.8.9 Build 17
-- Combined database upgrade from migration 174 (v4.8.8) to migration 180 (v4.8.9).
-- Run once against a database currently at migration 174.


-- ============================================================
-- 175_v489_operations_intelligence.sql
-- ============================================================
-- THQ ERP v4.8.9 — operational intelligence consolidation.
-- Makes the existing intelligence APIs aware of Purchasing V2, transfers,
-- offline sync, trace expiry and restaurant operations.
begin;

create or replace function public.supplier_payables_intelligence_v480(
  p_tenant_id uuid,p_location_id uuid default null,p_query text default '',p_limit integer default 1000
)
returns table(
  supplier_id uuid,supplier_name text,phone text,total_outstanding numeric,current_amount numeric,days_1_30 numeric,days_31_60 numeric,days_61_90 numeric,days_90_plus numeric,
  open_invoice_count bigint,oldest_due_date date,last_purchase_date date,status text
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  with legacy_open as (
    select p.supplier_id,p.purchase_date,coalesce(p.due_date,p.purchase_date) due_date,
      greatest(p.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)::numeric balance
    from public.purchases p
    left join(select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id=p.id
    left join(select purchase_id,sum(grand_total) returned from public.purchase_returns where credit_status<>'waived' group by purchase_id) rt on rt.purchase_id=p.id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id
    where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled')
      and (p_location_id is null or o.location_id=p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
      and greatest(p.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)>0.005
  ), v2_open as (
    select i.supplier_id,i.invoice_date as purchase_date,coalesce(i.due_date,i.invoice_date) due_date,
      greatest(i.balance_due,0)::numeric balance
    from public.purchase_invoices_v484 i
    where i.tenant_id=p_tenant_id and i.status in('posted','part_paid') and i.balance_due>0.005
      and (p_location_id is null or i.location_id=p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id,i.location_id,p_location_id,'view')
  ), open_docs as (
    select * from legacy_open
    union all
    select * from v2_open
  ), agg as (
    select op.supplier_id,sum(op.balance)::numeric outstanding,count(*)::bigint cnt,min(op.due_date) oldest,max(op.purchase_date) last_purchase,
      coalesce(sum(op.balance) filter(where op.due_date>=current_date),0)::numeric current_amt,
      coalesce(sum(op.balance) filter(where op.due_date<current_date and op.due_date>=current_date-30),0)::numeric a1,
      coalesce(sum(op.balance) filter(where op.due_date<current_date-30 and op.due_date>=current_date-60),0)::numeric a2,
      coalesce(sum(op.balance) filter(where op.due_date<current_date-60 and op.due_date>=current_date-90),0)::numeric a3,
      coalesce(sum(op.balance) filter(where op.due_date<current_date-90),0)::numeric a4
    from open_docs op group by op.supplier_id
  )
  select s.id,s.name,coalesce(s.phone,''),coalesce(a.outstanding,0)::numeric,coalesce(a.current_amt,0)::numeric,coalesce(a.a1,0)::numeric,
    coalesce(a.a2,0)::numeric,coalesce(a.a3,0)::numeric,coalesce(a.a4,0)::numeric,coalesce(a.cnt,0),a.oldest,a.last_purchase,
    (case when coalesce(a.outstanding,0)<=0.005 then 'clear' when coalesce(a.a4,0)>0 then 'critical_overdue'
      when coalesce(a.a1,0)+coalesce(a.a2,0)+coalesce(a.a3,0)>0 then 'overdue' else 'current' end)::text
  from public.suppliers s left join agg a on a.supplier_id=s.id
  where s.tenant_id=p_tenant_id and coalesce(s.status,'active')='active'
    and (trim(coalesce(p_query,''))='' or lower(s.name) like q or lower(coalesce(s.phone,'')) like q)
  order by coalesce(a.a4,0) desc,coalesce(a.outstanding,0) desc,s.name
  limit greatest(1,least(coalesce(p_limit,1000),5000));
end $$;
grant execute on function public.supplier_payables_intelligence_v480(uuid,uuid,text,integer) to authenticated;

create or replace function public.operations_pipeline_v489(
  p_tenant_id uuid,
  p_location_id uuid default null
) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v_pr bigint:=0;v_po bigint:=0;v_grn bigint:=0;v_invoice bigint:=0;
  v_transit bigint:=0;v_conflicts bigint:=0;v_batches bigint:=0;v_warranty bigint:=0;
  v_restaurant bigint:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select count(*) into v_pr from public.purchase_requests_v484 r
   where r.tenant_id=p_tenant_id and r.status='submitted'
     and (p_location_id is null or r.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view');
  select count(*) into v_po from public.purchase_orders_v480 p
   where p.tenant_id=p_tenant_id and p.status='submitted'
     and (p_location_id is null or p.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,p.location_id,p_location_id,'view');
  select count(*) into v_grn from public.goods_receipts_v484 g
   where g.tenant_id=p_tenant_id and g.status='draft'
     and (p_location_id is null or g.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,g.location_id,p_location_id,'view');
  select count(*) into v_invoice from public.purchase_invoices_v484 i
   where i.tenant_id=p_tenant_id and i.status='draft'
     and (p_location_id is null or i.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,i.location_id,p_location_id,'view');
  select count(*) into v_transit from public.stock_transfers t
   where t.tenant_id=p_tenant_id and t.status in('dispatched','in_transit')
     and (p_location_id is null or t.from_location_id=p_location_id or t.to_location_id=p_location_id)
     and (private.erp_document_scope_allowed(p_tenant_id,t.from_location_id,p_location_id,'view')
       or private.erp_document_scope_allowed(p_tenant_id,t.to_location_id,p_location_id,'view'));
  select count(*) into v_conflicts from public.pos_offline_sync_v486 q
   where q.tenant_id=p_tenant_id and q.status in('conflict','error')
     and (p_location_id is null or q.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,q.location_id,p_location_id,'view');
  select count(distinct b.id) into v_batches
    from public.inventory_batches_v483 b
    join public.inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id
   where b.tenant_id=p_tenant_id and b.status='active' and b.expiry_on between current_date and current_date+30
     and bb.quantity>0 and (p_location_id is null or bb.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,bb.location_id,p_location_id,'view');
  select count(*) into v_warranty from public.product_warranties_v483 w
   where w.tenant_id=p_tenant_id and w.status='active' and w.warranty_expiry between current_date and current_date+30
     and exists(select 1 from public.document_origins o where o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=w.sale_id
       and (p_location_id is null or o.location_id=p_location_id) and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view'));
  select count(*) into v_restaurant from public.restaurant_orders r
   where r.tenant_id=p_tenant_id and coalesce(r.status,'') not in('billed','cancelled','closed')
     and (p_location_id is null or r.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view');
  return jsonb_build_object(
    'purchase_requests_awaiting_approval',v_pr,
    'purchase_orders_awaiting_approval',v_po,
    'draft_grns',v_grn,
    'draft_purchase_invoices',v_invoice,
    'transfers_in_transit',v_transit,
    'offline_pos_conflicts',v_conflicts,
    'batches_expiring_30d',v_batches,
    'warranties_expiring_30d',v_warranty,
    'restaurant_open_orders',v_restaurant
  );
end $$;
grant execute on function public.operations_pipeline_v489(uuid,uuid) to authenticated;

create or replace function public.business_attention_summary_v480(p_tenant_id uuid,p_location_id uuid default null,p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_low bigint:=0;v_out bigint:=0;v_dead bigint:=0;v_stock numeric:=0;v_recv numeric:=0;v_pay numeric:=0;v_overdue numeric:=0;v_pipeline jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select count(*) filter(where status='low_stock'),count(*) filter(where status='out_of_stock'),count(*) filter(where status='dead_stock'),coalesce(sum(stock_value),0)
    into v_low,v_out,v_dead,v_stock from public.inventory_intelligence_v480(p_tenant_id,p_location_id,p_days,'',5000);
  select coalesce(sum(total_outstanding),0),coalesce(sum(days_1_30+days_31_60+days_61_90+days_90_plus),0)
    into v_recv,v_overdue from public.customer_credit_intelligence_v480(p_tenant_id,p_location_id,'',5000);
  select coalesce(sum(total_outstanding),0) into v_pay from public.supplier_payables_intelligence_v480(p_tenant_id,p_location_id,'',5000);
  v_pipeline:=public.operations_pipeline_v489(p_tenant_id,p_location_id);
  return jsonb_build_object('low_stock',v_low,'out_of_stock',v_out,'dead_stock',v_dead,'inventory_value',round(v_stock,2),
    'receivables',round(v_recv,2),'overdue_receivables',round(v_overdue,2),'payables',round(v_pay,2),'days',greatest(1,least(coalesce(p_days,30),365)))||v_pipeline;
end $$;
grant execute on function public.business_attention_summary_v480(uuid,uuid,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(175,'4.8.9','Stabilization & Operations','Unified legacy + Purchasing V2 supplier payables and cross-module operational attention pipeline.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.8.9 migration 175 operations intelligence applied' as status;

-- ============================================================
-- 176_v489_rounding_engine.sql
-- ============================================================
-- THQ ERP v4.8.9 — explicit document round-off engine.
-- Round-off is a post-tax document adjustment and is posted to the tenant rounding account.
begin;

alter table public.sales add column if not exists round_off numeric not null default 0;
alter table public.purchases add column if not exists round_off numeric not null default 0;
alter table public.expenses add column if not exists round_off numeric not null default 0;
alter table public.purchase_invoices_v484 add column if not exists round_off numeric not null default 0;

-- Expenses originally used a generated total_amount=(amount+tax_amount). v4.8.9 needs
-- round_off included in that total, so convert it to a trigger-maintained stored value.
do $$
begin
  if exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='expenses' and column_name='total_amount'
      and is_generated='ALWAYS'
  ) then
    alter table public.expenses alter column total_amount drop expression;
  end if;
end $$;

create or replace function private.expense_total_v489()
returns trigger language plpgsql set search_path=public,private,pg_temp as $$
begin
  new.total_amount:=round(coalesce(new.amount,0)+coalesce(new.tax_amount,0)+coalesce(new.round_off,0),2);
  return new;
end $$;
drop trigger if exists trg_expense_total_v489 on public.expenses;
create trigger trg_expense_total_v489 before insert or update of amount,tax_amount,round_off on public.expenses
for each row execute function private.expense_total_v489();
update public.expenses set total_amount=round(coalesce(amount,0)+coalesce(tax_amount,0)+coalesce(round_off,0),2);

-- Rebuild the standard accounting poster so rounding never distorts revenue, inventory or tax.
create or replace function private.v4_accounting_post_document(p_tenant_id uuid,p_entity_type text,p_entity_id uuid)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_loc uuid;v_total numeric;v_tax numeric;v_net numeric;v_cost numeric:=0;v_paid numeric:=0;v_round numeric:=0;
  v_method text:='cash';v_date date;v_ref text;v_party uuid;v_lines jsonb:='[]'::jsonb;v_pay_account uuid;
begin
  select location_id into v_loc from public.document_origins where tenant_id=p_tenant_id and entity_type=p_entity_type and entity_id=p_entity_id;
  if p_entity_type='sale' then
    select grand_total,tax_total,round_off,greatest(grand_total-tax_total-round_off,0),cost_total,sale_date,sale_number,customer_id
      into v_total,v_tax,v_round,v_net,v_cost,v_date,v_ref,v_party from public.sales where id=p_entity_id and tenant_id=p_tenant_id;
    if not found then return null;end if;
    select coalesce(sum(amount),0),(array_agg(payment_method order by paid_at,id))[1] into v_paid,v_method from public.sale_payments where sale_id=p_entity_id;
    v_paid:=least(coalesce(v_paid,0),v_total);v_pay_account:=private.v4_payment_account(p_tenant_id,v_method);
    if v_paid>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_pay_account,'debit',v_paid,'credit',0,'party_type','customer','party_id',v_party,'description','Sale receipt'));end if;
    if v_total-v_paid>0.005 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_receivable'),'debit',v_total-v_paid,'credit',0,'party_type','customer','party_id',v_party,'description','Customer receivable'));end if;
    if v_net>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'sales_revenue'),'debit',0,'credit',v_net,'party_type','customer','party_id',v_party,'description','Sales revenue'));end if;
    if v_tax>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'output_gst'),'debit',0,'credit',v_tax,'description','Output GST'));end if;
    if v_round>0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',0,'credit',v_round,'description','Sale round off'));end if;
    if v_round< -0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',abs(v_round),'credit',0,'description','Sale round off'));end if;
    if coalesce(v_cost,0)>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'cogs'),'debit',v_cost,'credit',0,'description','Cost of goods sold'),jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'inventory_asset'),'debit',0,'credit',v_cost,'description','Inventory issued'));end if;
    return private.v4_journal_create(p_tenant_id,v_loc,v_date,'Sale '||v_ref,'sale',p_entity_id,v_ref,v_lines);
  elsif p_entity_type='purchase' then
    select grand_total,tax_total,round_off,greatest(grand_total-tax_total-round_off,0),purchase_date,purchase_number,supplier_id
      into v_total,v_tax,v_round,v_net,v_date,v_ref,v_party from public.purchases where id=p_entity_id and tenant_id=p_tenant_id;
    if not found then return null;end if;
    select coalesce(sum(amount),0),(array_agg(payment_method order by paid_at,id))[1] into v_paid,v_method from public.purchase_payments where purchase_id=p_entity_id;
    v_paid:=least(coalesce(v_paid,0),v_total);v_pay_account:=private.v4_payment_account(p_tenant_id,v_method);
    if v_net>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'inventory_asset'),'debit',v_net,'credit',0,'party_type','supplier','party_id',v_party,'description','Purchase / inventory'));end if;
    if v_tax>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'input_gst'),'debit',v_tax,'credit',0,'description','Input GST'));end if;
    if v_round>0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',v_round,'credit',0,'description','Purchase round off'));end if;
    if v_round< -0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',0,'credit',abs(v_round),'description','Purchase round off'));end if;
    if v_paid>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_pay_account,'debit',0,'credit',v_paid,'party_type','supplier','party_id',v_party,'description','Supplier payment'));end if;
    if v_total-v_paid>0.005 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_payable'),'debit',0,'credit',v_total-v_paid,'party_type','supplier','party_id',v_party,'description','Supplier payable'));end if;
    return private.v4_journal_create(p_tenant_id,v_loc,v_date,'Purchase '||v_ref,'purchase',p_entity_id,v_ref,v_lines);
  elsif p_entity_type='expense' then
    select total_amount,tax_amount,round_off,greatest(total_amount-tax_amount-round_off,0),expense_date,expense_number
      into v_total,v_tax,v_round,v_net,v_date,v_ref from public.expenses where id=p_entity_id and tenant_id=p_tenant_id;
    if not found then return null;end if;
    select payment_method into v_method from public.expenses where id=p_entity_id;v_pay_account:=private.v4_payment_account(p_tenant_id,v_method);
    if v_net>0 then v_lines:=jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'operating_expense'),'debit',v_net,'credit',0,'description','Operating expense'));end if;
    if v_tax>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'input_gst'),'debit',v_tax,'credit',0,'description','Input GST'));end if;
    if v_round>0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',v_round,'credit',0,'description','Expense round off'));end if;
    if v_round< -0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',0,'credit',abs(v_round),'description','Expense round off'));end if;
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_pay_account,'debit',0,'credit',v_total,'description','Expense payment'));
    return private.v4_journal_create(p_tenant_id,v_loc,v_date,'Expense '||v_ref,'expense',p_entity_id,v_ref,v_lines);
  end if;
  return null;
end $$;
revoke all on function private.v4_accounting_post_document(uuid,text,uuid) from public;

create or replace function public.sales_create_v489(
  p_tenant_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,p_items jsonb,p_additional_charges numeric,p_round_off numeric,
  p_initial_payment numeric,p_payment_method text,p_payment_reference text,p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v jsonb;v_id uuid;v_round numeric:=round(coalesce(p_round_off,0),2);v_add numeric:=greatest(coalesce(p_additional_charges,0),0);v_final numeric;v_old_round numeric;v_old_add numeric;v_old_total numeric;
begin
  if abs(v_round)>0.999999 then raise exception 'Round off must be between -1.00 and 1.00';end if;
  v:=public.sales_create_v483(p_tenant_id,p_customer_id,p_sale_date,p_due_date,p_items,v_add+greatest(v_round,0),p_initial_payment,p_payment_method,p_payment_reference,p_notes,p_location_id,p_device_id,p_request_id);
  v_id:=nullif(v->>'sale_id','')::uuid;if v_id is null then return v;end if;
  select round_off,additional_charges,grand_total into v_old_round,v_old_add,v_old_total from public.sales where id=v_id and tenant_id=p_tenant_id for update;
  select round(coalesce(sum(si.line_total),0)+v_add+v_round,2) into v_final from public.sale_items si where si.sale_id=v_id;
  if v_final<0 then raise exception 'Rounded sale total cannot be negative';end if;
  if coalesce(p_initial_payment,0)>v_final+0.005 then raise exception 'Payment cannot exceed rounded sale total';end if;
  if abs(coalesce(v_old_round,0)-v_round)>0.000001 or abs(coalesce(v_old_add,0)-v_add)>0.000001 or abs(coalesce(v_old_total,0)-v_final)>0.000001 then
    -- This is a replacement journal, not a void. Retire the original posting and create
    -- one corrected posting; a posted reversal would be double-counted by reports that
    -- intentionally read only status='posted' journals.
    update public.journal_entries set status='reversed' where tenant_id=p_tenant_id and source_type='sale' and source_id=v_id and status='posted';
    update public.sales set additional_charges=v_add,round_off=v_round,grand_total=v_final where id=v_id and tenant_id=p_tenant_id;
    perform private.v4_accounting_post_document(p_tenant_id,'sale',v_id);
  end if;
  return v||jsonb_build_object('grand_total',v_final,'round_off',v_round,'rounding_engine','v4.8.9');
end $$;
grant execute on function public.sales_create_v489(uuid,uuid,date,date,jsonb,numeric,numeric,numeric,text,text,text,uuid,uuid,text) to authenticated;

create or replace function public.purchases_create_v489(
  p_tenant_id uuid,p_supplier_id uuid,p_supplier_invoice_number text,p_purchase_date date,p_due_date date,p_items jsonb,p_additional_charges numeric,p_round_off numeric,
  p_initial_payment numeric,p_payment_method text,p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v jsonb;v_id uuid;v_round numeric:=round(coalesce(p_round_off,0),2);v_add numeric:=greatest(coalesce(p_additional_charges,0),0);v_final numeric;v_old_round numeric;v_old_add numeric;v_old_total numeric;
begin
  if abs(v_round)>0.999999 then raise exception 'Round off must be between -1.00 and 1.00';end if;
  v:=public.purchases_create_v483(p_tenant_id,p_supplier_id,p_supplier_invoice_number,p_purchase_date,p_due_date,p_items,v_add+greatest(v_round,0),p_initial_payment,p_payment_method,p_notes,p_location_id,p_device_id,p_request_id);
  v_id:=nullif(v->>'purchase_id','')::uuid;if v_id is null then return v;end if;
  select round_off,additional_charges,grand_total into v_old_round,v_old_add,v_old_total from public.purchases where id=v_id and tenant_id=p_tenant_id for update;
  select round(coalesce(sum(pi.line_total),0)+v_add+v_round,2) into v_final from public.purchase_items pi where pi.purchase_id=v_id;
  if v_final<0 then raise exception 'Rounded purchase total cannot be negative';end if;
  if coalesce(p_initial_payment,0)>v_final+0.005 then raise exception 'Payment cannot exceed rounded purchase total';end if;
  if abs(coalesce(v_old_round,0)-v_round)>0.000001 or abs(coalesce(v_old_add,0)-v_add)>0.000001 or abs(coalesce(v_old_total,0)-v_final)>0.000001 then
    update public.journal_entries set status='reversed' where tenant_id=p_tenant_id and source_type='purchase' and source_id=v_id and status='posted';
    update public.purchases set additional_charges=v_add,round_off=v_round,grand_total=v_final where id=v_id and tenant_id=p_tenant_id;
    perform private.v4_accounting_post_document(p_tenant_id,'purchase',v_id);
  end if;
  return v||jsonb_build_object('grand_total',v_final,'round_off',v_round,'rounding_engine','v4.8.9');
end $$;
grant execute on function public.purchases_create_v489(uuid,uuid,text,date,date,jsonb,numeric,numeric,numeric,text,text,uuid,uuid,text) to authenticated;

create or replace function public.expenses_create_v489(
  p_tenant_id uuid,p_category_id uuid,p_expense_date date,p_payee text,p_description text,p_amount numeric,p_tax_amount numeric,p_round_off numeric,
  p_payment_method text,p_reference_number text,p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v jsonb;v_id uuid;v_round numeric:=round(coalesce(p_round_off,0),2);v_final numeric:=round(coalesce(p_amount,0)+coalesce(p_tax_amount,0)+round(coalesce(p_round_off,0),2),2);v_old_round numeric;
begin
  if abs(v_round)>0.999999 then raise exception 'Round off must be between -1.00 and 1.00';end if;
  if v_final<=0 then raise exception 'Rounded expense total must be positive';end if;
  v:=public.expenses_create_v47(p_tenant_id,p_category_id,p_expense_date,p_payee,p_description,p_amount,p_tax_amount,p_payment_method,p_reference_number,p_notes,p_location_id,p_device_id,p_request_id);
  v_id:=nullif(v->>'expense_id','')::uuid;if v_id is null then return v;end if;
  select round_off into v_old_round from public.expenses where id=v_id and tenant_id=p_tenant_id for update;
  if abs(coalesce(v_old_round,0)-v_round)>0.000001 then
    update public.journal_entries set status='reversed' where tenant_id=p_tenant_id and source_type='expense' and source_id=v_id and status='posted';
    update public.expenses set round_off=v_round,total_amount=v_final where id=v_id and tenant_id=p_tenant_id;
    perform private.v4_accounting_post_document(p_tenant_id,'expense',v_id);
  end if;
  return v||jsonb_build_object('total_amount',v_final,'round_off',v_round,'rounding_engine','v4.8.9');
end $$;
grant execute on function public.expenses_create_v489(uuid,uuid,date,text,text,numeric,numeric,numeric,text,text,text,uuid,uuid,text) to authenticated;


create or replace function public.expenses_update_v489(
  p_tenant_id uuid,p_expense_id uuid,p_category_id uuid,p_expense_date date,p_payee text,p_description text,
  p_amount numeric,p_tax_amount numeric,p_round_off numeric,p_payment_method text,p_reference_number text,p_notes text
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_round numeric:=round(coalesce(p_round_off,0),2);v_loc uuid;
begin
  if abs(v_round)>0.999999 then raise exception 'Round off must be between -1.00 and 1.00';end if;
  select location_id into v_loc from public.document_origins where tenant_id=p_tenant_id and entity_type='expense' and entity_id=p_expense_id;
  if not private.erp_document_scope_allowed(p_tenant_id,v_loc,null,'operate') then raise exception 'Location access denied';end if;
  perform public.expenses_update(p_tenant_id,p_expense_id,p_category_id,p_expense_date,p_payee,p_description,p_amount,p_tax_amount,p_payment_method,p_reference_number,p_notes);
  -- Editing keeps the expense active. Retire the old source journal and post the new
  -- values once; do not leave a posted void-style reversal alongside the replacement.
  update public.journal_entries set status='reversed' where tenant_id=p_tenant_id and source_type='expense' and source_id=p_expense_id and status='posted';
  update public.expenses set round_off=v_round,updated_at=now() where id=p_expense_id and tenant_id=p_tenant_id;
  perform private.v4_accounting_post_document(p_tenant_id,'expense',p_expense_id);
end $$;
grant execute on function public.expenses_update_v489(uuid,uuid,uuid,date,text,text,numeric,numeric,numeric,text,text,text) to authenticated;

-- Purchasing V2: create a draft invoice with round-off without changing stock.
create or replace function public.purchase_invoice_create_v489(
 p_tenant_id uuid,p_purchase_order_id uuid,p_supplier_invoice_number text,p_invoice_date date,p_due_date date,p_items jsonb,p_additional_charges numeric,p_round_off numeric,p_notes text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v jsonb;v_id uuid;v_round numeric:=round(coalesce(p_round_off,0),2);v_add numeric:=greatest(coalesce(p_additional_charges,0),0);v_final numeric;
begin
  if abs(v_round)>0.999999 then raise exception 'Round off must be between -1.00 and 1.00';end if;
  v:=public.purchase_invoice_create_v484(p_tenant_id,p_purchase_order_id,p_supplier_invoice_number,p_invoice_date,p_due_date,p_items,v_add+greatest(v_round,0),p_notes);
  v_id:=nullif(v->>'purchase_invoice_id','')::uuid;if v_id is null then return v;end if;
  select round(coalesce(sum(ii.line_total),0)+v_add+v_round,2) into v_final from public.purchase_invoice_items_v484 ii where ii.purchase_invoice_id=v_id;
  if v_final<0 then raise exception 'Rounded purchase invoice total cannot be negative';end if;
  update public.purchase_invoices_v484 set additional_charges=v_add,round_off=v_round,grand_total=v_final,balance_due=greatest(v_final-paid_total,0),updated_at=now() where id=v_id and tenant_id=p_tenant_id;
  return v||jsonb_build_object('grand_total',v_final,'round_off',v_round,'rounding_engine','v4.8.9');
end $$;
grant execute on function public.purchase_invoice_create_v489(uuid,uuid,text,date,date,jsonb,numeric,numeric,text) to authenticated;

-- Keep the public post signature stable, but post round-off separately from inventory/input tax.
create or replace function public.purchase_invoice_post_v484(p_tenant_id uuid,p_purchase_invoice_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare i public.purchase_invoices_v484%rowtype;li record;v_lines jsonb:='[]'::jsonb;v_net numeric;begin
  select * into i from public.purchase_invoices_v484 where tenant_id=p_tenant_id and id=p_purchase_invoice_id for update;if not found then raise exception 'Purchase Invoice not found';end if;perform private.purchasing_v484_access(p_tenant_id,i.location_id,true);
  if i.status in('posted','part_paid','paid') then return jsonb_build_object('success',true,'purchase_invoice_id',i.id,'invoice_number',i.invoice_number,'status',i.status,'idempotent',true);end if;if i.status<>'draft' then raise exception 'Only Draft invoices can be posted';end if;
  if i.grand_total<=0 then raise exception 'Purchase Invoice total must be positive';end if;
  v_net:=greatest(i.subtotal+i.additional_charges,0);
  if v_net>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'inventory_asset'),'debit',v_net,'credit',0,'party_type','supplier','party_id',i.supplier_id,'description','Purchase invoice / inventory'));end if;
  if i.tax_total>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'input_gst'),'debit',i.tax_total,'credit',0,'description','Input GST'));end if;
  if i.round_off>0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',i.round_off,'credit',0,'description','Purchase invoice round off'));end if;
  if i.round_off< -0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',0,'credit',abs(i.round_off),'description','Purchase invoice round off'));end if;
  v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_payable'),'debit',0,'credit',i.grand_total,'party_type','supplier','party_id',i.supplier_id,'description','Supplier payable'));
  perform private.v4_journal_create(p_tenant_id,i.location_id,i.invoice_date,'Purchase Invoice '||i.invoice_number,'purchase_invoice_v484',i.id,i.invoice_number,v_lines);
  update public.purchase_invoices_v484 set status='posted',posted_by=auth.uid(),posted_at=now(),balance_due=grand_total-paid_total,updated_at=now() where id=i.id;
  for li in select purchase_order_item_id,sum(quantity) qty from public.purchase_invoice_items_v484 where purchase_invoice_id=i.id group by purchase_order_item_id loop update public.purchase_order_items_v480 set invoiced_quantity=invoiced_quantity+li.qty where id=li.purchase_order_item_id;end loop;
  perform private.thq_sync_bump_v480(p_tenant_id,'accounting','purchase_invoice',i.id::text,'post');
  return jsonb_build_object('success',true,'purchase_invoice_id',i.id,'invoice_number',i.invoice_number,'status','posted','grand_total',i.grand_total,'round_off',i.round_off);
end $$;
grant execute on function public.purchase_invoice_post_v484(uuid,uuid) to authenticated;

-- Offline POS keeps the v4.8.6 public endpoint but posts through the v4.8.9 rounded sale wrapper.
create or replace function public.pos_offline_sale_sync_v486(
  p_tenant_id uuid,p_device_id uuid,p_location_id uuid,p_request_id text,p_payload jsonb
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v_location uuid;v_existing jsonb;v_result jsonb;v_items jsonb;v_priced jsonb;v_client jsonb;v_server jsonb;
  v_i integer;v_client_price numeric;v_server_price numeric;v_client_tax numeric;v_server_tax numeric;v_variant uuid;
  v_customer uuid;v_sale_date date;v_due_date date;v_local text;v_message text;v_code text;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then raise exception 'Request ID is required';end if;
  v_location:=private.v486_pos_device_location(p_tenant_id,p_device_id,p_location_id);
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':offline:'||trim(p_request_id),0));
  select server_response into v_existing from public.pos_offline_sync_v486 where tenant_id=p_tenant_id and request_id=trim(p_request_id) and status='synced';
  if v_existing is not null then return v_existing||jsonb_build_object('idempotent_replay',true);end if;
  v_items:=coalesce(p_payload->'items','[]'::jsonb);
  if jsonb_typeof(v_items)<>'array' or jsonb_array_length(v_items)=0 then raise exception 'Offline invoice has no items';end if;
  v_customer:=nullif(p_payload->>'customer_id','')::uuid;v_local:=nullif(trim(coalesce(p_payload->>'local_invoice_number','')),'');
  if v_customer is null or not exists(select 1 from public.customers c where c.id=v_customer and c.tenant_id=p_tenant_id and c.status='active') then return private.v486_offline_conflict(p_tenant_id,p_device_id,v_location,p_request_id,v_local,'CUSTOMER_UNAVAILABLE','Customer is no longer available.',p_payload);end if;
  v_sale_date:=coalesce(nullif(p_payload->>'sale_date','')::date,current_date);v_due_date:=nullif(p_payload->>'due_date','')::date;
  v_priced:=private.v482_price_sale_items(p_tenant_id,v_customer,v_items,v_location);
  for v_i in 0..jsonb_array_length(v_items)-1 loop
    v_client:=v_items->v_i;v_server:=v_priced->v_i;v_variant:=nullif(v_client->>'variant_id','')::uuid;
    v_client_price:=coalesce(nullif(v_client->>'unit_price','')::numeric,0);v_server_price:=coalesce(nullif(v_server->>'unit_price','')::numeric,0);
    if abs(v_client_price-v_server_price)>0.005 then v_message:=format('Price changed for product %s. Offline %s, current %s.',v_variant,round(v_client_price,2),round(v_server_price,2));return private.v486_offline_conflict(p_tenant_id,p_device_id,v_location,p_request_id,v_local,'PRICE_CHANGED',v_message,p_payload);end if;
    select coalesce(pv.tax_rate,0) into v_server_tax from public.product_variants pv where pv.id=v_variant and pv.tenant_id=p_tenant_id;
    if not found then return private.v486_offline_conflict(p_tenant_id,p_device_id,v_location,p_request_id,v_local,'PRODUCT_UNAVAILABLE','A product on the offline invoice is no longer available.',p_payload);end if;
    v_client_tax:=coalesce(nullif(v_client->>'tax_rate','')::numeric,0);
    if abs(v_client_tax-v_server_tax)>0.0001 then v_message:=format('Tax changed for product %s. Offline %s, current %s.',v_variant,round(v_client_tax,4),round(v_server_tax,4));return private.v486_offline_conflict(p_tenant_id,p_device_id,v_location,p_request_id,v_local,'TAX_CHANGED',v_message,p_payload);end if;
  end loop;
  insert into public.pos_offline_sync_v486(tenant_id,request_id,device_id,location_id,local_invoice_number,status,payload_snapshot,attempts,last_attempt_at,created_by,updated_at)
  values(p_tenant_id,trim(p_request_id),p_device_id,v_location,v_local,'syncing',p_payload,1,now(),auth.uid(),now())
  on conflict(tenant_id,request_id) do update set status='syncing',payload_snapshot=excluded.payload_snapshot,attempts=public.pos_offline_sync_v486.attempts+1,last_attempt_at=now(),updated_at=now(),conflict_code=null,conflict_message=null;
  begin
    v_result:=public.sales_create_v489(p_tenant_id,v_customer,v_sale_date,v_due_date,v_items,
      coalesce(nullif(p_payload->>'additional_charges','')::numeric,0),coalesce(nullif(p_payload->>'round_off','')::numeric,0),
      coalesce(nullif(p_payload->>'initial_payment','')::numeric,0),coalesce(nullif(p_payload->>'payment_method',''),'cash'),coalesce(p_payload->>'payment_reference',''),
      trim(concat_ws(' • ',nullif(p_payload->>'notes',''),'Offline POS '||coalesce(v_local,''))),v_location,p_device_id,trim(p_request_id));
  exception when others then
    v_message:=sqlerrm;if v_message ilike '%stock%' or v_message ilike '%serial%' or v_message ilike '%batch%' or v_message ilike '%reconciled%' then v_code:='STOCK_CONFLICT';else v_code:='SERVER_VALIDATION';end if;
    return private.v486_offline_conflict(p_tenant_id,p_device_id,v_location,p_request_id,v_local,v_code,v_message,p_payload);
  end;
  v_result:=coalesce(v_result,'{}'::jsonb)||jsonb_build_object('ok',true,'status','synced','request_id',trim(p_request_id),'local_invoice_number',v_local,'offline_sync','v4.8.9');
  update public.pos_offline_sync_v486 set status='synced',server_response=v_result,conflict_code=null,conflict_message=null,synced_at=now(),last_attempt_at=now(),updated_at=now() where tenant_id=p_tenant_id and request_id=trim(p_request_id);
  return v_result;
end $$;
grant execute on function public.pos_offline_sale_sync_v486(uuid,uuid,uuid,text,jsonb) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(176,'4.8.9','Stabilization & Operations','Explicit post-tax round-off for sales, direct purchases, expenses, Purchase Invoices and offline POS with separate rounding-account journals.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.8.9 migration 176 round-off engine applied' as status;

-- ============================================================
-- 177_v489_restaurant_pricing_operations.sql
-- ============================================================
-- THQ ERP v4.8.9 — restaurant stabilization, unit-aware menu lines and authoritative pricing.
-- Restaurant order prices are resolved on the server using the v4.8.2 pricing engine.
begin;

alter table public.restaurant_order_items
  add column if not exists unit_id uuid references public.inventory_units_v481(id) on delete set null,
  add column if not exists conversion_to_base numeric not null default 1,
  add column if not exists pricing_source text,
  add column if not exists price_list_id uuid references public.price_lists_v482(id) on delete set null,
  add column if not exists pricing_metadata jsonb not null default '{}'::jsonb;

-- Backfill the historical lines with the product base/default sale unit where possible.
update public.restaurant_order_items i
set unit_id = coalesce(
      i.unit_id,
      (select pu.unit_id from public.product_units_v481 pu
       where pu.tenant_id=i.tenant_id and pu.variant_id=i.variant_id and pu.active and pu.is_default_sale limit 1),
      (select pu.unit_id from public.product_units_v481 pu
       where pu.tenant_id=i.tenant_id and pu.variant_id=i.variant_id and pu.active and pu.is_base limit 1)
    ),
    conversion_to_base = coalesce(
      (select pu.conversion_to_base from public.product_units_v481 pu
       where pu.tenant_id=i.tenant_id and pu.variant_id=i.variant_id
         and pu.unit_id=coalesce(
           i.unit_id,
           (select pu2.unit_id from public.product_units_v481 pu2 where pu2.tenant_id=i.tenant_id and pu2.variant_id=i.variant_id and pu2.active and pu2.is_default_sale limit 1),
           (select pu3.unit_id from public.product_units_v481 pu3 where pu3.tenant_id=i.tenant_id and pu3.variant_id=i.variant_id and pu3.active and pu3.is_base limit 1)
         ) and pu.active limit 1),
      1
    ),
    pricing_source=coalesce(i.pricing_source,'legacy_snapshot')
where i.unit_id is null or i.pricing_source is null;

create index if not exists idx_restaurant_order_items_unit_v489
  on public.restaurant_order_items(tenant_id,variant_id,unit_id);

-- Authoritative, location-scoped restaurant order creation. Client-provided price/tax
-- values are deliberately ignored; only product/unit/quantity/discount/note are accepted.
create or replace function public.restaurant_order_create_v32(
  p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_order_type text,p_table_id uuid,p_customer_id uuid,
  p_preparation_minutes integer,p_chef_note text,p_delivery_address text,p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_id uuid:=gen_random_uuid();
  v_order text;v_track text;
  x jsonb;v_priced jsonb;v_norm jsonb;
  v_variant uuid;v_unit uuid;v_qty numeric;v_factor numeric;v_unit_price numeric;v_tax numeric;
  v_discount numeric;v_source text;v_price_list uuid;v_price_name text;
begin
  perform private.erp_validate_vertical_device_scope(p_tenant_id,p_location_id,p_device_id,'restaurant','operate');
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'restaurant.order')
     and not private.erp_has_permission(p_tenant_id,'restaurant.manage') then
    raise exception 'Restaurant order permission denied';
  end if;
  if p_order_type not in ('dine_in','takeaway','delivery') then raise exception 'Invalid order type';end if;
  if p_order_type='dine_in' and p_table_id is null then raise exception 'Choose a table';end if;
  if p_table_id is not null and not exists(
    select 1 from public.restaurant_tables t
    where t.id=p_table_id and t.tenant_id=p_tenant_id and t.location_id=p_location_id and t.active
  ) then raise exception 'Choose a table from this store';end if;
  if p_customer_id is not null and not exists(
    select 1 from public.customers c where c.id=p_customer_id and c.tenant_id=p_tenant_id and coalesce(c.status,'active')='active'
  ) then raise exception 'Customer is not available';end if;
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then
    raise exception 'Add at least one item';
  end if;

  -- Resolve all prices first. The pricing helper also resolves a missing unit_id to the
  -- configured default sale/base unit.
  v_priced:=private.v482_price_sale_items(p_tenant_id,p_customer_id,p_items,p_location_id);

  insert into public.restaurant_orders(
    id,tenant_id,location_id,device_id,order_number,order_type,table_id,customer_id,
    preparation_minutes,chef_note,delivery_address,created_by
  ) values(
    v_id,p_tenant_id,p_location_id,p_device_id,'',p_order_type,p_table_id,p_customer_id,
    greatest(coalesce(p_preparation_minutes,15),0),nullif(trim(p_chef_note),''),nullif(trim(p_delivery_address),''),auth.uid()
  ) returning order_number,tracking_code into v_order,v_track;

  for x in select value from jsonb_array_elements(v_priced) loop
    -- Normalization validates unit enablement, quantity step/fraction rules and conversion.
    v_norm:=private.v481_normalize_line(p_tenant_id,x,'sale');
    v_variant:=nullif(x->>'variant_id','')::uuid;
    v_unit:=nullif(v_norm->>'_entered_unit_id','')::uuid;
    v_qty:=coalesce(nullif(v_norm->>'_entered_quantity','')::numeric,0);
    v_factor:=coalesce(nullif(v_norm->>'_conversion_to_base','')::numeric,1);
    v_unit_price:=coalesce(nullif(v_norm->>'_entered_unit_price','')::numeric,0);
    v_discount:=greatest(coalesce(nullif(x->>'discount_amount','')::numeric,0),0);
    v_source:=nullif(x->>'_pricing_source','');
    v_price_list:=nullif(x->>'_price_list_id','')::uuid;
    v_price_name:=nullif(x->>'_price_list_name','');

    select coalesce(pv.tax_rate,0) into v_tax
    from public.product_variants pv
    where pv.id=v_variant and pv.tenant_id=p_tenant_id;
    if not found then raise exception 'Product is not available for this business';end if;
    if v_discount > v_qty*v_unit_price then raise exception 'Restaurant item discount exceeds line value';end if;

    insert into public.restaurant_order_items(
      order_id,tenant_id,variant_id,quantity,unit_id,conversion_to_base,unit_price,
      discount_amount,tax_rate,item_note,pricing_source,price_list_id,pricing_metadata
    ) values(
      v_id,p_tenant_id,v_variant,v_qty,v_unit,v_factor,v_unit_price,
      v_discount,v_tax,nullif(trim(x->>'item_note'),''),coalesce(v_source,'product_price'),v_price_list,
      jsonb_strip_nulls(jsonb_build_object('price_list_name',v_price_name,'resolved_at',now(),'engine','v4.8.2'))
    );
  end loop;

  insert into public.document_origins(tenant_id,entity_type,entity_id,location_id,device_id,created_by)
  values(p_tenant_id,'restaurant_order',v_id,p_location_id,p_device_id,auth.uid())
  on conflict do nothing;
  perform private.thq_sync_bump_v480(p_tenant_id,'restaurant','restaurant_order',v_id::text,'create');
  return jsonb_build_object('order_id',v_id,'order_number',v_order,'tracking_code',v_track,'pricing_engine','v4.8.2','restaurant_engine','v4.8.9');
end $$;
grant execute on function public.restaurant_order_create_v32(uuid,uuid,uuid,text,uuid,uuid,integer,text,text,jsonb) to authenticated;

-- Bill a restaurant order atomically. A deterministic request ID makes retries safe if
-- the client loses connectivity after the sale is created but before it receives the response.
create or replace function public.restaurant_order_bill_v489(
  p_tenant_id uuid,p_order_id uuid,p_device_id uuid,p_customer_id uuid,p_due_date date,
  p_initial_payment numeric,p_payment_method text,p_payment_reference text,p_round_off numeric default 0
) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  o public.restaurant_orders%rowtype;v_customer uuid;v_items jsonb;v_sale jsonb;v_sale_id uuid;v_existing jsonb;
  v_total numeric;v_method text;
begin
  select * into o from public.restaurant_orders
  where id=p_order_id and tenant_id=p_tenant_id for update;
  if o.id is null then raise exception 'Restaurant order not found';end if;
  perform private.erp_validate_vertical_device_scope(p_tenant_id,o.location_id,p_device_id,'restaurant','operate');
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'restaurant.order')
     and not private.erp_has_permission(p_tenant_id,'restaurant.manage') then
    raise exception 'Restaurant billing permission denied';
  end if;
  if o.status='cancelled' then raise exception 'Cancelled restaurant order cannot be billed';end if;
  if o.status='billed' and o.sale_id is not null then
    select jsonb_build_object('success',true,'idempotent',true,'order_id',o.id,'sale_id',s.id,
      'sale_number',s.sale_number,'grand_total',s.grand_total,'round_off',coalesce(s.round_off,0))
      into v_existing from public.sales s where s.id=o.sale_id and s.tenant_id=p_tenant_id;
    if v_existing is not null then return v_existing;end if;
  end if;
  v_customer:=coalesce(o.customer_id,p_customer_id);
  if v_customer is null or not exists(
    select 1 from public.customers c where c.id=v_customer and c.tenant_id=p_tenant_id and coalesce(c.status,'active')='active'
  ) then raise exception 'Choose an active customer before billing';end if;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'variant_id',i.variant_id,'quantity',i.quantity,'unit_id',i.unit_id,
      'unit_price',i.unit_price,'discount_amount',i.discount_amount,'tax_rate',i.tax_rate
    )) order by i.created_at,i.id),'[]'::jsonb)
    into v_items from public.restaurant_order_items i where i.order_id=o.id and i.tenant_id=p_tenant_id;
  if jsonb_array_length(v_items)=0 then raise exception 'Restaurant order has no items';end if;
  v_method:=coalesce(nullif(lower(trim(p_payment_method)),''),'cash');
  -- Create the sale without a payment first. This lets the authoritative pricing engine
  -- determine the exact current total; non-credit restaurant bills are then settled for
  -- that server total in the same transaction, so a changed price cannot strand billing.
  v_sale:=public.sales_create_v489(
    p_tenant_id,v_customer,current_date,p_due_date,v_items,0,coalesce(p_round_off,0),
    0,v_method,coalesce(p_payment_reference,''),'Restaurant '||o.order_number,o.location_id,p_device_id,
    'restaurant-bill:'||o.id::text
  );
  v_sale_id:=nullif(v_sale->>'sale_id','')::uuid;
  if v_sale_id is null then raise exception 'Restaurant sale was not created';end if;
  v_total:=coalesce(nullif(v_sale->>'grand_total','')::numeric,0);
  if v_method<>'credit' and v_total>0.005 then
    perform public.sales_add_payment_v47(
      p_tenant_id,v_sale_id,v_total,v_method,coalesce(p_payment_reference,''),
      'Restaurant settlement '||o.order_number,'restaurant-payment:'||o.id::text
    );
    v_sale:=v_sale||jsonb_build_object('paid_total',v_total,'balance_due',0);
  end if;
  update public.restaurant_orders set status='billed',sale_id=v_sale_id,billed_at=coalesce(billed_at,now()),updated_at=now()
   where id=o.id and tenant_id=p_tenant_id;
  update public.restaurant_kots set status='served',served_at=coalesce(served_at,now())
   where tenant_id=p_tenant_id and order_id=o.id and status not in('served','cancelled');
  perform private.thq_sync_bump_v480(p_tenant_id,'restaurant','restaurant_order',o.id::text,'bill');
  return coalesce(v_sale,'{}'::jsonb)||jsonb_build_object('success',true,'order_id',o.id,'restaurant_billing','v4.8.9');
end $$;
grant execute on function public.restaurant_order_bill_v489(uuid,uuid,uuid,uuid,date,numeric,text,text,numeric) to authenticated;

-- Add concise restaurant operational metrics for the redesigned Floor / Orders / Kitchen workspace.
create or replace function public.restaurant_operations_summary_v489(
  p_tenant_id uuid,p_location_id uuid default null,p_device_id uuid default null
) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v_tables bigint:=0;v_occupied bigint:=0;v_open bigint:=0;v_queue bigint:=0;v_preparing bigint:=0;v_ready bigint:=0;v_sales numeric:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if p_device_id is not null and p_location_id is not null then
    perform private.erp_validate_vertical_device_scope(p_tenant_id,p_location_id,p_device_id,'restaurant','view');
  end if;
  select count(*) into v_tables from public.restaurant_tables t
   where t.tenant_id=p_tenant_id and t.active
     and (p_location_id is null or t.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,t.location_id,p_location_id,'view');
  select count(distinct r.table_id),count(*)
    into v_occupied,v_open
    from public.restaurant_orders r
   where r.tenant_id=p_tenant_id and r.status not in('billed','cancelled')
     and (p_location_id is null or r.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view');
  select count(*) filter(where k.status='queued'),count(*) filter(where k.status='preparing'),count(*) filter(where k.status='ready')
    into v_queue,v_preparing,v_ready
    from public.restaurant_kots k
   where k.tenant_id=p_tenant_id and k.status not in('served','cancelled')
     and (p_location_id is null or k.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,k.location_id,p_location_id,'view');
  select coalesce(sum(s.grand_total),0) into v_sales
    from public.restaurant_orders r join public.sales s on s.id=r.sale_id and s.tenant_id=r.tenant_id
   where r.tenant_id=p_tenant_id and r.status='billed' and s.sale_date=current_date
     and (p_location_id is null or r.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view');
  return jsonb_build_object(
    'tables',v_tables,'occupied_tables',v_occupied,'available_tables',greatest(v_tables-v_occupied,0),
    'open_orders',v_open,'kot_queued',v_queue,'kot_preparing',v_preparing,'kot_ready',v_ready,
    'restaurant_sales_today',round(v_sales,2)
  );
end $$;
grant execute on function public.restaurant_operations_summary_v489(uuid,uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(177,'4.8.9','Stabilization & Operations','Restaurant V2 stabilization: authoritative pricing/tax, unit-aware order lines and operations summary for Floor/Orders/Kitchen.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.8.9 migration 177 restaurant pricing and operations applied' as status;

-- ============================================================
-- 178_v489_runtime_hardening.sql
-- ============================================================
-- THQ ERP v4.8.9 — runtime compatibility and stabilization guardrails.
begin;

-- Keep all rounded document adjustments within the UI/accounting contract.
do $$ begin
  if not exists(select 1 from pg_constraint where conname='sales_round_off_v489_check') then
    alter table public.sales add constraint sales_round_off_v489_check check(abs(round_off)<=1.000001);
  end if;
  if not exists(select 1 from pg_constraint where conname='purchases_round_off_v489_check') then
    alter table public.purchases add constraint purchases_round_off_v489_check check(abs(round_off)<=1.000001);
  end if;
  if not exists(select 1 from pg_constraint where conname='expenses_round_off_v489_check') then
    alter table public.expenses add constraint expenses_round_off_v489_check check(abs(round_off)<=1.000001);
  end if;
  if not exists(select 1 from pg_constraint where conname='purchase_invoice_round_off_v489_check') then
    alter table public.purchase_invoices_v484 add constraint purchase_invoice_round_off_v489_check check(abs(round_off)<=1.000001);
  end if;
  if not exists(select 1 from pg_constraint where conname='restaurant_order_items_conversion_v489_check') then
    alter table public.restaurant_order_items add constraint restaurant_order_items_conversion_v489_check check(conversion_to_base>0);
  end if;
end $$;

create index if not exists idx_restaurant_orders_ops_v489
  on public.restaurant_orders(tenant_id,location_id,status,opened_at desc);
create index if not exists idx_purchase_invoices_ops_v489
  on public.purchase_invoices_v484(tenant_id,location_id,status,due_date,invoice_date desc);
create index if not exists idx_pos_offline_sync_ops_v489
  on public.pos_offline_sync_v486(tenant_id,location_id,status,updated_at desc);

-- A source/runtime audit endpoint. It deliberately reports missing baseline objects instead
-- of failing deployment, because the earliest ERP core tables/RPCs predate this migration set.
create or replace function public.erp_runtime_health_v489(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v_required_functions text[]:=array[
    'current_user_is_platform_admin',
    'customers_create','customers_update','suppliers_create','suppliers_update',
    'inventory_list_products','inventory_get_product_detail','inventory_create_product','inventory_update_product',
    'platform_create_business','platform_get_business_modules','platform_get_business_permissions',
    'platform_get_business_roles','platform_list_modules','platform_update_role_permissions',
    'sales_create_v489','purchases_create_v489','expenses_create_v489','expenses_update_v489',
    'inventory_product_units_v481','inventory_product_units_save_v481','pricing_resolve_v482',
    'purchase_invoice_create_v489','purchase_invoice_post_v484','purchase_order_decide_v484','operations_pipeline_v489',
    'sales_add_payment_v47','restaurant_order_create_v32','restaurant_order_bill_v489','restaurant_operations_summary_v489','pos_offline_sale_sync_v486',
    'mobile_client_context_v487','mobile_client_dashboard_v487','mobile_approvals_v487','mobile_customer_payment_v487',
    'mobile_pos_terminal_context_v488','mobile_pos_sale_sync_v488','mobile_pos_cache_manifest_v488','mobile_pos_sync_status_v488',
    'thq_backend_contract_v47','thq_api_contract_v480'
  ];
  v_required_tables text[]:=array[
    'tenants','tenant_memberships','tenant_modules','tenant_settings','modules','roles','role_permissions','user_roles',
    'products','product_variants','customers','suppliers',
    'sales','sale_items','purchases','purchase_items','expenses','business_locations','business_devices',
    'inventory_units_v481','product_units_v481','price_lists_v482','restaurant_orders','restaurant_order_items',
    'purchase_invoices_v484','pos_offline_sync_v486','thq_schema_releases'
  ];
  v_missing_functions text[]:='{}'::text[];v_missing_tables text[]:='{}'::text[];
  v text;v_release jsonb;v_pipeline jsonb:='{}'::jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  foreach v in array v_required_functions loop
    if not exists(
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v
    ) then v_missing_functions:=array_append(v_missing_functions,v);end if;
  end loop;
  foreach v in array v_required_tables loop
    if to_regclass('public.'||v) is null then v_missing_tables:=array_append(v_missing_tables,v);end if;
  end loop;
  select jsonb_build_object(
    'schema_version',schema_version,'migration_no',migration_no,'release_name',release_name
  ) into v_release from public.thq_schema_releases order by migration_no desc limit 1;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='operations_pipeline_v489') then
    begin v_pipeline:=public.operations_pipeline_v489(p_tenant_id,null); exception when others then v_pipeline:=jsonb_build_object('error',sqlerrm);end;
  end if;
  return jsonb_build_object(
    'ready',cardinality(v_missing_functions)=0 and cardinality(v_missing_tables)=0,
    'missing_functions',to_jsonb(v_missing_functions),'missing_tables',to_jsonb(v_missing_tables),
    'release',coalesce(v_release,'{}'::jsonb),'operations',v_pipeline,
    'pricing_engine','v4.8.2-authoritative','unit_engine','v4.8.1','tracking_engine','v4.8.3',
    'purchasing_engine','v4.8.4','warehouse_engine','v4.8.5','offline_pos_engine','v4.8.6',
    'client_mobile','v4.8.7','mobile_pos','v4.8.8','stabilization','v4.8.9'
  );
end $$;
grant execute on function public.erp_runtime_health_v489(uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(178,'4.8.9','Stabilization & Operations','Runtime compatibility audit, round-off constraints and operational indexes for critical cross-module workflows.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.8.9 migration 178 runtime hardening applied' as status;

-- ============================================================
-- 179_v489_api_contract.sql
-- ============================================================
-- THQ ERP v4.8.9 — stabilized THQ API contract metadata.
begin;

create or replace function public.thq_api_contract_v480()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
  select jsonb_build_object(
    'product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json',
    'resources',jsonb_build_array(
      'sync','attention','runtime-health','restaurant-operations',
      'inventory-intelligence','inventory-movements','units','product-units','pricing','product-identifiers','product-lookup','label-templates',
      'tracking-policy','serials','batches','batch-history','warranties','customer-credit','supplier-payables','reorder-suggestions',
      'purchase-requests','purchase-orders','goods-receipts','purchase-invoices','supplier-payments-v2','supplier-ledger-v2','purchase-price-history','purchasing-dashboard',
      'warehouses','warehouse-inventory','stock-transfers','stock-counts','stock-reconciliation','business-summary','store-summary',
      'offline-pos','client-mobile','mobile-pos'
    ),
    'core_financial_posting','direct_hardened_rpc',
    'unit_engine','v4.8.1','authoritative_sale_pricing','v4.8.2','inventory_tracking','v4.8.3',
    'purchasing_engine','v4.8.4','warehouse_engine','v4.8.5','offline_pos_engine','v4.8.6',
    'client_mobile_release','4.8.7','mobile_pos_release','4.8.8',
    'round_off_engine','v4.8.9','restaurant_engine','v4.8.9','operations_intelligence','v4.8.9',
    'mobile_ready',true
  )
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(179,'4.8.9','Stabilization & Operations','THQ API v1 contract expanded for v4.8.9 runtime health and restaurant operations; Purchasing V2 invoice create carries round-off.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.8.9 migration 179 API contract applied' as status;

-- ============================================================
-- 180_v489_release_contract.sql
-- ============================================================
-- THQ ERP v4.8.9 — Stabilization & Operations release contract.
begin;

create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
   'product','THQ ERP',
   'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
   'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
   'minimum_app_version','4.8.9',
   'release','Stabilization & Operations',
   'api_version','v1'
 )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v489_release_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  v_missing text[]:='{}'::text[];
  v_baseline text;
  v_baseline_required text[]:=array[
    'current_user_is_platform_admin',
    'customers_create','customers_update','suppliers_create','suppliers_update',
    'inventory_list_products','inventory_get_product_detail','inventory_create_product','inventory_update_product',
    'platform_create_business','platform_get_business_modules','platform_get_business_permissions',
    'platform_get_business_roles','platform_list_modules','platform_update_role_permissions'
  ];
begin
  -- These RPCs are part of the original ERP bootstrap and predate migration 001.
  -- A release must report them if the live Supabase project is missing one.
  foreach v_baseline in array v_baseline_required loop
    if not exists(
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_baseline
    ) then v_missing:=array_append(v_missing,'baseline.'||v_baseline);end if;
  end loop;
  if to_regclass('public.tenants') is null then v_missing:=array_append(v_missing,'baseline.tenants');end if;
  if to_regclass('public.tenant_memberships') is null then v_missing:=array_append(v_missing,'baseline.tenant_memberships');end if;
  if to_regclass('public.tenant_modules') is null then v_missing:=array_append(v_missing,'baseline.tenant_modules');end if;
  if to_regclass('public.tenant_settings') is null then v_missing:=array_append(v_missing,'baseline.tenant_settings');end if;
  if to_regclass('public.modules') is null then v_missing:=array_append(v_missing,'baseline.modules');end if;
  if to_regclass('public.roles') is null then v_missing:=array_append(v_missing,'baseline.roles');end if;
  if to_regclass('public.role_permissions') is null then v_missing:=array_append(v_missing,'baseline.role_permissions');end if;
  if to_regclass('public.user_roles') is null then v_missing:=array_append(v_missing,'baseline.user_roles');end if;
  if to_regprocedure('public.operations_pipeline_v489(uuid,uuid)') is null then v_missing:=array_append(v_missing,'operations_pipeline_v489');end if;
  if to_regprocedure('public.sales_create_v489(uuid,uuid,date,date,jsonb,numeric,numeric,numeric,text,text,text,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'sales_create_v489');end if;
  if to_regprocedure('public.purchases_create_v489(uuid,uuid,text,date,date,jsonb,numeric,numeric,numeric,text,text,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'purchases_create_v489');end if;
  if to_regprocedure('public.expenses_create_v489(uuid,uuid,date,text,text,numeric,numeric,numeric,text,text,text,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'expenses_create_v489');end if;
  if to_regprocedure('public.expenses_update_v489(uuid,uuid,uuid,date,text,text,numeric,numeric,numeric,text,text,text)') is null then v_missing:=array_append(v_missing,'expenses_update_v489');end if;
  if to_regprocedure('public.purchase_invoice_create_v489(uuid,uuid,text,date,date,jsonb,numeric,numeric,text)') is null then v_missing:=array_append(v_missing,'purchase_invoice_create_v489');end if;
  if to_regprocedure('public.purchase_order_decide_v484(uuid,uuid,boolean,text)') is null then v_missing:=array_append(v_missing,'purchase_order_decide_v484');end if;
  if to_regprocedure('public.sales_add_payment_v47(uuid,uuid,numeric,text,text,text,text)') is null then v_missing:=array_append(v_missing,'sales_add_payment_v47');end if;
  if to_regprocedure('public.restaurant_order_create_v32(uuid,uuid,uuid,text,uuid,uuid,integer,text,text,jsonb)') is null then v_missing:=array_append(v_missing,'restaurant_order_create_v32');end if;
  if to_regprocedure('public.restaurant_order_bill_v489(uuid,uuid,uuid,uuid,date,numeric,text,text,numeric)') is null then v_missing:=array_append(v_missing,'restaurant_order_bill_v489');end if;
  if to_regprocedure('public.restaurant_operations_summary_v489(uuid,uuid,uuid)') is null then v_missing:=array_append(v_missing,'restaurant_operations_summary_v489');end if;
  if to_regprocedure('public.erp_runtime_health_v489(uuid)') is null then v_missing:=array_append(v_missing,'erp_runtime_health_v489');end if;
  if to_regprocedure('public.thq_api_contract_v480()') is null then v_missing:=array_append(v_missing,'thq_api_contract_v480');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='sales' and column_name='round_off') then v_missing:=array_append(v_missing,'sales.round_off');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='purchases' and column_name='round_off') then v_missing:=array_append(v_missing,'purchases.round_off');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='expenses' and column_name='round_off') then v_missing:=array_append(v_missing,'expenses.round_off');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='purchase_invoices_v484' and column_name='round_off') then v_missing:=array_append(v_missing,'purchase_invoices_v484.round_off');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='restaurant_order_items' and column_name='unit_id') then v_missing:=array_append(v_missing,'restaurant_order_items.unit_id');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='restaurant_order_items' and column_name='conversion_to_base') then v_missing:=array_append(v_missing,'restaurant_order_items.conversion_to_base');end if;
  return jsonb_build_object(
    'ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),
    'schema_version','4.8.9','migration_no',180,'api_version','v1',
    'operations_intelligence',true,'product_units_in_add_edit',true,'billing_unit_selection',true,
    'authoritative_pricing',true,'round_off',true,'purchasing_v2_stabilized',true,
    'receivables_responsive',true,'restaurant_v2',true,'subscription_module_dropdown',true,
    'client_mobile_analyzer_fixes',true,'runtime_audit',true
  );
end $$;
grant execute on function public.thq_v489_release_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(180,'4.8.9','Stabilization & Operations','End-to-end stabilization release: units in product add/edit and billing, authoritative pricing, explicit round-off, Purchasing V2 fixes, responsive receivables, Restaurant V2, subscription module picker and runtime audit.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.8.9 migration 180 release contract applied' as status;
