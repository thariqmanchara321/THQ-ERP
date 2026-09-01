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
