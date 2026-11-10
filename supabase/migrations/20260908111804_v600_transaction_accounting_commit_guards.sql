create or replace function private.accounting_commit_guard_v600()
returns trigger
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_required boolean:=false;
  v_source_type text;
  v_source_id uuid;
  v_tenant_id uuid;
  v_count integer:=0;
begin
  v_source_id:=new.id;
  v_tenant_id:=new.tenant_id;

  case tg_table_name
    when 'sales' then
      v_source_type:='sale';
      select (status='posted') into v_required from public.sales where id=new.id and tenant_id=new.tenant_id;
    when 'purchases' then
      v_source_type:='purchase';
      select (status='posted') into v_required from public.purchases where id=new.id and tenant_id=new.tenant_id;
    when 'expenses' then
      v_source_type:='expense';
      select (status='posted') into v_required from public.expenses where id=new.id and tenant_id=new.tenant_id;
    when 'purchase_invoices_v484' then
      v_source_type:='purchase_invoice_v484';
      select (status in ('posted','part_paid','paid')) into v_required from public.purchase_invoices_v484 where id=new.id and tenant_id=new.tenant_id;
    when 'sales_returns' then
      v_source_type:='sales_return';
      select exists(select 1 from public.sales_returns where id=new.id and tenant_id=new.tenant_id) into v_required;
    when 'purchase_returns' then
      v_source_type:='purchase_return';
      select exists(select 1 from public.purchase_returns where id=new.id and tenant_id=new.tenant_id) into v_required;
    when 'supplier_payments_v484' then
      v_source_type:='supplier_payment_v484';
      select (status='posted') into v_required from public.supplier_payments_v484 where id=new.id and tenant_id=new.tenant_id;
    else
      return new;
  end case;

  if coalesce(v_required,false) is not true then
    return new;
  end if;

  select count(*) into v_count
  from public.journal_entries j
  where j.tenant_id=v_tenant_id
    and j.source_type=v_source_type
    and j.source_id=v_source_id
    and j.status='posted';

  if v_count=0 then
    raise exception 'Accounting integrity failure: % % has no posted journal',v_source_type,v_source_id;
  end if;
  if v_count>1 then
    raise exception 'Accounting integrity failure: % % has % posted journals',v_source_type,v_source_id,v_count;
  end if;

  return new;
end
$function$;

revoke all on function private.accounting_commit_guard_v600() from public,anon,authenticated;

do $ddl$
begin
  drop trigger if exists trg_accounting_guard_sales_v600 on public.sales;
  create constraint trigger trg_accounting_guard_sales_v600
    after insert or update on public.sales
    deferrable initially deferred
    for each row execute function private.accounting_commit_guard_v600();

  drop trigger if exists trg_accounting_guard_purchases_v600 on public.purchases;
  create constraint trigger trg_accounting_guard_purchases_v600
    after insert or update on public.purchases
    deferrable initially deferred
    for each row execute function private.accounting_commit_guard_v600();

  drop trigger if exists trg_accounting_guard_expenses_v600 on public.expenses;
  create constraint trigger trg_accounting_guard_expenses_v600
    after insert or update on public.expenses
    deferrable initially deferred
    for each row execute function private.accounting_commit_guard_v600();

  drop trigger if exists trg_accounting_guard_purchase_invoices_v600 on public.purchase_invoices_v484;
  create constraint trigger trg_accounting_guard_purchase_invoices_v600
    after insert or update on public.purchase_invoices_v484
    deferrable initially deferred
    for each row execute function private.accounting_commit_guard_v600();

  drop trigger if exists trg_accounting_guard_sales_returns_v600 on public.sales_returns;
  create constraint trigger trg_accounting_guard_sales_returns_v600
    after insert or update on public.sales_returns
    deferrable initially deferred
    for each row execute function private.accounting_commit_guard_v600();

  drop trigger if exists trg_accounting_guard_purchase_returns_v600 on public.purchase_returns;
  create constraint trigger trg_accounting_guard_purchase_returns_v600
    after insert or update on public.purchase_returns
    deferrable initially deferred
    for each row execute function private.accounting_commit_guard_v600();

  drop trigger if exists trg_accounting_guard_supplier_payments_v600 on public.supplier_payments_v484;
  create constraint trigger trg_accounting_guard_supplier_payments_v600
    after insert or update on public.supplier_payments_v484
    deferrable initially deferred
    for each row execute function private.accounting_commit_guard_v600();
end
$ddl$;

create or replace function public.accounting_integrity_report_v600(p_tenant_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_missing_sales int;
  v_missing_purchases int;
  v_missing_expenses int;
  v_missing_purchase_invoices int;
  v_missing_sales_returns int;
  v_missing_purchase_returns int;
  v_missing_supplier_payments int;
  v_duplicate_sources int;
  v_unbalanced int;
  v_missing jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not (private.erp_has_permission(p_tenant_id,'accounting.view') or private.erp_has_permission(p_tenant_id,'accounting.manage') or private.erp_has_permission(p_tenant_id,'accounting.journal')) then
    raise exception 'Accounting permission required';
  end if;

  select count(*) into v_missing_sales from public.sales s where s.tenant_id=p_tenant_id and s.status='posted'
    and not exists(select 1 from public.journal_entries j where j.tenant_id=s.tenant_id and j.source_type='sale' and j.source_id=s.id and j.status='posted');
  select count(*) into v_missing_purchases from public.purchases p where p.tenant_id=p_tenant_id and p.status='posted'
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p.tenant_id and j.source_type='purchase' and j.source_id=p.id and j.status='posted');
  select count(*) into v_missing_expenses from public.expenses e where e.tenant_id=p_tenant_id and e.status='posted'
    and not exists(select 1 from public.journal_entries j where j.tenant_id=e.tenant_id and j.source_type='expense' and j.source_id=e.id and j.status='posted');
  select count(*) into v_missing_purchase_invoices from public.purchase_invoices_v484 p where p.tenant_id=p_tenant_id and p.status in ('posted','part_paid','paid')
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p.tenant_id and j.source_type='purchase_invoice_v484' and j.source_id=p.id and j.status='posted');
  select count(*) into v_missing_sales_returns from public.sales_returns r where r.tenant_id=p_tenant_id
    and not exists(select 1 from public.journal_entries j where j.tenant_id=r.tenant_id and j.source_type='sales_return' and j.source_id=r.id and j.status='posted');
  select count(*) into v_missing_purchase_returns from public.purchase_returns r where r.tenant_id=p_tenant_id
    and not exists(select 1 from public.journal_entries j where j.tenant_id=r.tenant_id and j.source_type='purchase_return' and j.source_id=r.id and j.status='posted');
  select count(*) into v_missing_supplier_payments from public.supplier_payments_v484 p where p.tenant_id=p_tenant_id and p.status='posted'
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p.tenant_id and j.source_type='supplier_payment_v484' and j.source_id=p.id and j.status='posted');

  select count(*) into v_duplicate_sources
  from (
    select source_type,source_id from public.journal_entries
    where tenant_id=p_tenant_id and status='posted' and source_type in ('sale','purchase','expense','purchase_invoice_v484','sales_return','purchase_return','supplier_payment_v484') and source_id is not null
    group by source_type,source_id having count(*)>1
  ) d;

  select count(*) into v_unbalanced
  from (
    select j.id from public.journal_entries j join public.journal_lines l on l.journal_entry_id=j.id
    where j.tenant_id=p_tenant_id and j.status='posted'
    group by j.id
    having round(sum(l.debit),2)<>round(sum(l.credit),2) or round(sum(l.debit),2)<=0 or round(sum(l.credit),2)<=0
  ) u;

  select coalesce(jsonb_agg(x order by x->>'source_type',x->>'source_reference'),'[]'::jsonb) into v_missing
  from (
    select jsonb_build_object('source_type','sale','source_id',s.id,'source_reference',s.sale_number,'date',s.sale_date) x from public.sales s where s.tenant_id=p_tenant_id and s.status='posted' and not exists(select 1 from public.journal_entries j where j.tenant_id=s.tenant_id and j.source_type='sale' and j.source_id=s.id and j.status='posted')
    union all
    select jsonb_build_object('source_type','purchase','source_id',p.id,'source_reference',p.purchase_number,'date',p.purchase_date) from public.purchases p where p.tenant_id=p_tenant_id and p.status='posted' and not exists(select 1 from public.journal_entries j where j.tenant_id=p.tenant_id and j.source_type='purchase' and j.source_id=p.id and j.status='posted')
    union all
    select jsonb_build_object('source_type','expense','source_id',e.id,'source_reference',e.expense_number,'date',e.expense_date) from public.expenses e where e.tenant_id=p_tenant_id and e.status='posted' and not exists(select 1 from public.journal_entries j where j.tenant_id=e.tenant_id and j.source_type='expense' and j.source_id=e.id and j.status='posted')
    union all
    select jsonb_build_object('source_type','purchase_invoice_v484','source_id',p.id,'source_reference',p.invoice_number,'date',p.invoice_date) from public.purchase_invoices_v484 p where p.tenant_id=p_tenant_id and p.status in ('posted','part_paid','paid') and not exists(select 1 from public.journal_entries j where j.tenant_id=p.tenant_id and j.source_type='purchase_invoice_v484' and j.source_id=p.id and j.status='posted')
    union all
    select jsonb_build_object('source_type','sales_return','source_id',r.id,'source_reference',r.return_number,'date',r.return_date) from public.sales_returns r where r.tenant_id=p_tenant_id and not exists(select 1 from public.journal_entries j where j.tenant_id=r.tenant_id and j.source_type='sales_return' and j.source_id=r.id and j.status='posted')
    union all
    select jsonb_build_object('source_type','purchase_return','source_id',r.id,'source_reference',r.return_number,'date',r.return_date) from public.purchase_returns r where r.tenant_id=p_tenant_id and not exists(select 1 from public.journal_entries j where j.tenant_id=r.tenant_id and j.source_type='purchase_return' and j.source_id=r.id and j.status='posted')
    union all
    select jsonb_build_object('source_type','supplier_payment_v484','source_id',p.id,'source_reference',p.payment_number,'date',p.payment_date) from public.supplier_payments_v484 p where p.tenant_id=p_tenant_id and p.status='posted' and not exists(select 1 from public.journal_entries j where j.tenant_id=p.tenant_id and j.source_type='supplier_payment_v484' and j.source_id=p.id and j.status='posted')
    limit 100
  ) q;

  return jsonb_build_object(
    'tenant_id',p_tenant_id,
    'healthy',(v_missing_sales+v_missing_purchases+v_missing_expenses+v_missing_purchase_invoices+v_missing_sales_returns+v_missing_purchase_returns+v_missing_supplier_payments+v_duplicate_sources+v_unbalanced)=0,
    'missing_sales_journals',v_missing_sales,
    'missing_purchase_journals',v_missing_purchases,
    'missing_expense_journals',v_missing_expenses,
    'missing_purchase_invoice_journals',v_missing_purchase_invoices,
    'missing_sales_return_journals',v_missing_sales_returns,
    'missing_purchase_return_journals',v_missing_purchase_returns,
    'missing_supplier_payment_journals',v_missing_supplier_payments,
    'duplicate_posted_sources',v_duplicate_sources,
    'unbalanced_posted_journals',v_unbalanced,
    'missing_sources',v_missing
  );
end
$function$;

revoke all on function public.accounting_integrity_report_v600(uuid) from public,anon;
grant execute on function public.accounting_integrity_report_v600(uuid) to authenticated,service_role;

create or replace function public.accounting_repair_missing_journal_v600(p_tenant_id uuid,p_source_type text,p_source_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_type text:=lower(trim(coalesce(p_source_type,'')));
  v_existing uuid;
  v_journal uuid;
  v_snapshot uuid;
  v_reference text;
  v_status text;
  v_supplier uuid;
  v_location uuid;
  v_date date;
  v_amount numeric;
  v_method text;
  v_lines jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not (private.erp_has_permission(p_tenant_id,'accounting.manage') or private.erp_has_permission(p_tenant_id,'accounting.journal')) then raise exception 'Accounting repair permission required'; end if;
  if v_type not in ('sale','purchase','expense','purchase_invoice_v484','sales_return','purchase_return','supplier_payment_v484') then
    raise exception 'Unsupported accounting repair source type';
  end if;
  if p_source_id is null then raise exception 'Source id is required'; end if;

  if v_type='sale' then
    select sale_number,status into v_reference,v_status from public.sales where id=p_source_id and tenant_id=p_tenant_id;
    if v_status<>'posted' then raise exception 'Only posted Sale documents can be repaired'; end if;
  elsif v_type='purchase' then
    select purchase_number,status into v_reference,v_status from public.purchases where id=p_source_id and tenant_id=p_tenant_id;
    if v_status<>'posted' then raise exception 'Only posted Purchase documents can be repaired'; end if;
  elsif v_type='expense' then
    select expense_number,status into v_reference,v_status from public.expenses where id=p_source_id and tenant_id=p_tenant_id;
    if v_status<>'posted' then raise exception 'Only posted Expense documents can be repaired'; end if;
  elsif v_type='purchase_invoice_v484' then
    select invoice_number,status into v_reference,v_status from public.purchase_invoices_v484 where id=p_source_id and tenant_id=p_tenant_id;
    if v_status not in ('posted','part_paid','paid') then raise exception 'Only posted Purchase Invoice documents can be repaired'; end if;
  elsif v_type='sales_return' then
    select return_number into v_reference from public.sales_returns where id=p_source_id and tenant_id=p_tenant_id;
  elsif v_type='purchase_return' then
    select return_number into v_reference from public.purchase_returns where id=p_source_id and tenant_id=p_tenant_id;
  else
    select payment_number,status,supplier_id,location_id,payment_date,amount,payment_method
      into v_reference,v_status,v_supplier,v_location,v_date,v_amount,v_method
    from public.supplier_payments_v484 where id=p_source_id and tenant_id=p_tenant_id;
    if v_status<>'posted' then raise exception 'Only posted Supplier Payments can be repaired'; end if;
  end if;

  if v_reference is null then raise exception 'Source document not found'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':accounting-repair:'||v_type||':'||p_source_id::text,0));

  select id into v_existing from public.journal_entries
  where tenant_id=p_tenant_id and source_type=v_type and source_id=p_source_id and status='posted'
  order by created_at limit 1;
  if v_existing is not null then
    return jsonb_build_object('source_type',v_type,'source_id',p_source_id,'source_reference',v_reference,'journal_id',v_existing,'repaired',false,'reason','posted_journal_already_exists');
  end if;

  if v_type='supplier_payment_v484' then
    v_lines:=jsonb_build_array(
      jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_payable'),'debit',v_amount,'credit',0,'party_type','supplier','party_id',v_supplier,'description','Supplier payable settlement'),
      jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,lower(trim(v_method))),'debit',0,'credit',v_amount,'party_type','supplier','party_id',v_supplier,'description','Supplier payment')
    );
    v_journal:=private.v4_journal_create(p_tenant_id,v_location,v_date,'Supplier Payment '||v_reference,'supplier_payment_v484',p_source_id,v_reference,v_lines);
  else
    select s.id into v_snapshot from public.gst_document_snapshots_v520 s
    where s.tenant_id=p_tenant_id and s.source_type=v_type and s.source_id=p_source_id
    order by s.created_at desc limit 1;

    if v_snapshot is not null then
      v_journal:=private.gst_authoritative_journal_post_v520(p_tenant_id,v_snapshot);
    elsif v_type in ('sale','purchase','expense') then
      v_journal:=private.v4_accounting_post_document(p_tenant_id,v_type,p_source_id);
    else
      raise exception 'No authoritative GST snapshot exists for %. Automatic legacy repair is intentionally blocked; review this document manually.',v_type;
    end if;
  end if;

  if v_journal is null or not exists(select 1 from public.journal_entries j where j.id=v_journal and j.tenant_id=p_tenant_id and j.source_type=v_type and j.source_id=p_source_id and j.status='posted') then
    raise exception 'Accounting repair failed; no posted journal was created';
  end if;

  return jsonb_build_object(
    'source_type',v_type,'source_id',p_source_id,'source_reference',v_reference,'journal_id',v_journal,'repaired',true,
    'accounting_route',case when v_type='supplier_payment_v484' then 'supplier_payment_reconstruction' when v_snapshot is not null then 'authoritative_gst_snapshot' else 'generic_accounting' end
  );
end
$function$;

revoke all on function public.accounting_repair_missing_journal_v600(uuid,text,uuid) from public,anon;
grant execute on function public.accounting_repair_missing_journal_v600(uuid,text,uuid) to authenticated,service_role;;
