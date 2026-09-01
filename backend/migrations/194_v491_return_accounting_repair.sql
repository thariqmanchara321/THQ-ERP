-- THQ ERP v4.9.1 — financial mapping self-heal and Sales Return accounting repair.
begin;

create or replace function private.v491_ensure_financial_mappings(p_tenant_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid; begin
  perform private.v47_ensure_accounting_for_tenant(p_tenant_id);

  select id into v_id from public.accounting_accounts where tenant_id=p_tenant_id and system_key='customer_credits' limit 1;
  if v_id is null then
    insert into public.accounting_accounts(tenant_id,code,name,account_type,system_key,is_system,description)
    values(p_tenant_id,'2051','Customer Refunds / Credits','liability','customer_credits',true,'Amounts owed or credited to customers after returns')
    on conflict(tenant_id,code) do update set name=excluded.name,account_type=excluded.account_type,system_key=excluded.system_key,is_system=true,description=excluded.description
    returning id into v_id;
  end if;
  insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id) values(p_tenant_id,'customer_credits',v_id)
  on conflict(tenant_id,mapping_key) do update set account_id=excluded.account_id,updated_at=now();

  select id into v_id from public.accounting_accounts where tenant_id=p_tenant_id and system_key='supplier_credits' limit 1;
  if v_id is null then
    insert into public.accounting_accounts(tenant_id,code,name,account_type,system_key,is_system,description)
    values(p_tenant_id,'1151','Supplier Credits','asset','supplier_credits',true,'Credits/refunds due from suppliers after purchase returns')
    on conflict(tenant_id,code) do update set name=excluded.name,account_type=excluded.account_type,system_key=excluded.system_key,is_system=true,description=excluded.description
    returning id into v_id;
  end if;
  insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id) values(p_tenant_id,'supplier_credits',v_id)
  on conflict(tenant_id,mapping_key) do update set account_id=excluded.account_id,updated_at=now();

  -- Keep all loan accounting mappings available for both existing and newly-created tenants.
  insert into public.accounting_accounts(tenant_id,code,name,account_type,system_key,is_system,description)
  select p_tenant_id,x.code,x.name,x.typ,x.key,true,x.descr
  from (values
    ('1110','Loan Receivable','asset','loan_receivable','Outstanding principal advanced by the business'),
    ('4020','Loan Interest Income','income','loan_interest_income','Interest earned on loans given'),
    ('4030','Loan Penalty Income','income','loan_penalty_income','Penalty income on loans given'),
    ('2210','Loan Payable','liability','loan_payable','Principal borrowed by the business'),
    ('5210','Loan Interest Expense','expense','loan_interest_expense','Interest paid or accrued on loans taken'),
    ('5220','Loan Penalty Expense','expense','loan_penalty_expense','Penalty and late charges on loans taken')
  ) as x(code,name,typ,key,descr)
  on conflict(tenant_id,code) do update
  set name=excluded.name,account_type=excluded.account_type,system_key=excluded.system_key,is_system=true,description=excluded.description;

  insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id)
  select a.tenant_id,a.system_key,a.id
  from public.accounting_accounts a
  where a.tenant_id=p_tenant_id
    and a.system_key in ('loan_receivable','loan_interest_income','loan_penalty_income','loan_payable','loan_interest_expense','loan_penalty_expense')
  on conflict(tenant_id,mapping_key) do update set account_id=excluded.account_id,updated_at=now();
end $$;
revoke all on function private.v491_ensure_financial_mappings(uuid) from public;

do $$ declare r record; begin for r in select id from public.tenants loop perform private.v491_ensure_financial_mappings(r.id); end loop; end $$;

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
  perform private.v491_ensure_financial_mappings(r.tenant_id);

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
  perform private.v491_ensure_financial_mappings(r.tenant_id);

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

-- Re-run accounting for returns that were created successfully but whose journal failed because the mapping was absent.
do $$ declare r record; begin
  for r in select sr.id from public.sales_returns sr left join public.journal_entries j on j.tenant_id=sr.tenant_id and j.source_type='sales_return' and j.source_id=sr.id and j.status='posted' where coalesce(sr.grand_total,0)>0 and j.id is null loop
    begin perform private.v4_post_sales_return(r.id); exception when others then null; end;
  end loop;
end $$;

-- Do the same for purchase returns so supplier-credit mapping failures are repaired consistently.
do $$ declare r record; begin
  for r in select pr.id from public.purchase_returns pr left join public.journal_entries j on j.tenant_id=pr.tenant_id and j.source_type='purchase_return' and j.source_id=pr.id and j.status='posted' where coalesce(pr.grand_total,0)>0 and j.id is null loop
    begin perform private.v4_post_purchase_return(r.id); exception when others then null; end;
  end loop;
end $$;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(194,'4.9.1','Return Accounting Repair','Self-heals return and loan accounting mappings and repairs Sales/Purchase Return journal posting for existing tenants.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.9.1 migration 194 applied' as status;
