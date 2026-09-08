-- THQ ERP v6.0
-- Accounting integrity guard and controlled repair surface.
-- Reconstructed from the live production schema after the migration was applied.

create or replace function public.expenses_create_v489(
  p_tenant_id uuid, p_category_id uuid, p_expense_date date, p_payee text,
  p_description text, p_amount numeric, p_tax_amount numeric, p_round_off numeric,
  p_payment_method text, p_reference_number text, p_notes text,
  p_location_id uuid, p_device_id uuid, p_request_id text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v jsonb;
  v_id uuid;
  v_round numeric:=round(coalesce(p_round_off,0),2);
  v_final numeric:=round(coalesce(p_amount,0)+coalesce(p_tax_amount,0)+round(coalesce(p_round_off,0),2),2);
  v_old_round numeric;
  v_journal_id uuid;
  v_mode text:=private.gst_tax_mode_resolve_v520(p_tenant_id,coalesce(p_expense_date,current_date));
begin
  if v_mode='unconfigured' then
    raise exception 'Business tax mode is not configured. Choose GST Registered or Non-GST before posting expenses.';
  end if;
  if v_mode='non_gst' and abs(coalesce(p_tax_amount,0))>0.0001 then
    raise exception 'Non-GST businesses cannot post GST tax on an expense. Set tax amount to zero.';
  end if;
  if coalesce(p_tax_amount,0)<0 then raise exception 'Tax cannot be negative'; end if;
  if abs(v_round)>0.999999 then raise exception 'Round off must be between -1.00 and 1.00'; end if;
  if v_final<=0 then raise exception 'Rounded expense total must be positive'; end if;

  v:=public.expenses_create_v47(
    p_tenant_id,p_category_id,p_expense_date,p_payee,p_description,p_amount,p_tax_amount,
    p_payment_method,p_reference_number,p_notes,p_location_id,p_device_id,p_request_id
  );

  v_id:=nullif(v->>'expense_id','')::uuid;
  if v_id is null then raise exception 'Expense transaction did not return an expense id'; end if;

  select round_off into v_old_round
  from public.expenses
  where id=v_id and tenant_id=p_tenant_id
  for update;
  if not found then raise exception 'Expense transaction was not persisted'; end if;

  if abs(coalesce(v_old_round,0)-v_round)>0.000001 then
    update public.journal_entries
       set status='reversed'
     where tenant_id=p_tenant_id and source_type='expense' and source_id=v_id and status='posted';

    update public.expenses
       set round_off=v_round,total_amount=v_final
     where id=v_id and tenant_id=p_tenant_id;
  end if;

  select j.id into v_journal_id
  from public.journal_entries j
  where j.tenant_id=p_tenant_id and j.source_type='expense' and j.source_id=v_id and j.status='posted'
  order by j.created_at limit 1;

  if v_journal_id is null then
    v_journal_id:=private.v4_accounting_post_document(p_tenant_id,'expense',v_id);
  end if;

  if v_journal_id is null or not exists(
    select 1 from public.journal_entries j
    where j.id=v_journal_id and j.tenant_id=p_tenant_id
      and j.source_type='expense' and j.source_id=v_id and j.status='posted'
  ) then
    raise exception 'Expense accounting journal was not created; transaction rolled back';
  end if;

  return v||jsonb_build_object(
    'total_amount',v_final,
    'round_off',v_round,
    'rounding_engine','v4.8.9',
    'tax_mode',v_mode,
    'gst_applicable',v_mode='gst_registered',
    'journal_id',v_journal_id,
    'accounting_integrity','verified'
  );
end
$function$;

create or replace function public.accounting_integrity_report_v600(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'private', 'pg_temp'
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
  if not (
    private.erp_has_permission(p_tenant_id,'accounting.view')
    or private.erp_has_permission(p_tenant_id,'accounting.manage')
    or private.erp_has_permission(p_tenant_id,'accounting.journal')
  ) then raise exception 'Accounting permission required'; end if;

  select count(*) into v_missing_sales
  from public.sales s
  where s.tenant_id=p_tenant_id and s.status='posted'
    and not exists(select 1 from public.journal_entries j
                   where j.tenant_id=s.tenant_id and j.source_type='sale'
                     and j.source_id=s.id and j.status='posted');

  select count(*) into v_missing_purchases
  from public.purchases p
  where p.tenant_id=p_tenant_id and p.status='posted'
    and not exists(select 1 from public.journal_entries j
                   where j.tenant_id=p.tenant_id and j.source_type='purchase'
                     and j.source_id=p.id and j.status='posted');

  select count(*) into v_missing_expenses
  from public.expenses e
  where e.tenant_id=p_tenant_id and e.status='posted'
    and not exists(select 1 from public.journal_entries j
                   where j.tenant_id=e.tenant_id and j.source_type='expense'
                     and j.source_id=e.id and j.status='posted');

  select count(*) into v_missing_purchase_invoices
  from public.purchase_invoices_v484 p
  where p.tenant_id=p_tenant_id and p.status in ('posted','part_paid','paid')
    and not exists(select 1 from public.journal_entries j
                   where j.tenant_id=p.tenant_id and j.source_type='purchase_invoice_v484'
                     and j.source_id=p.id and j.status='posted');

  select count(*) into v_missing_sales_returns
  from public.sales_returns r
  where r.tenant_id=p_tenant_id
    and not exists(select 1 from public.journal_entries j
                   where j.tenant_id=r.tenant_id and j.source_type='sales_return'
                     and j.source_id=r.id and j.status='posted');

  select count(*) into v_missing_purchase_returns
  from public.purchase_returns r
  where r.tenant_id=p_tenant_id
    and not exists(select 1 from public.journal_entries j
                   where j.tenant_id=r.tenant_id and j.source_type='purchase_return'
                     and j.source_id=r.id and j.status='posted');

  select count(*) into v_missing_supplier_payments
  from public.supplier_payments_v484 p
  where p.tenant_id=p_tenant_id and p.status='posted'
    and not exists(select 1 from public.journal_entries j
                   where j.tenant_id=p.tenant_id and j.source_type='supplier_payment_v484'
                     and j.source_id=p.id and j.status='posted');

  select count(*) into v_duplicate_sources
  from (
    select source_type,source_id
    from public.journal_entries
    where tenant_id=p_tenant_id and status='posted'
      and source_type in (
        'sale','purchase','expense','purchase_invoice_v484',
        'sales_return','purchase_return','supplier_payment_v484'
      )
      and source_id is not null
    group by source_type,source_id
    having count(*)>1
  ) d;

  select count(*) into v_unbalanced
  from (
    select j.id
    from public.journal_entries j
    join public.journal_lines l on l.journal_entry_id=j.id
    where j.tenant_id=p_tenant_id and j.status='posted'
    group by j.id
    having round(sum(l.debit),2)<>round(sum(l.credit),2)
       or round(sum(l.debit),2)<=0
       or round(sum(l.credit),2)<=0
  ) u;

  select coalesce(jsonb_agg(x order by x->>'source_type',x->>'source_reference'),'[]'::jsonb)
  into v_missing
  from (
    select jsonb_build_object('source_type','sale','source_id',s.id,'source_reference',s.sale_number,'date',s.sale_date) x
    from public.sales s
    where s.tenant_id=p_tenant_id and s.status='posted'
      and not exists(select 1 from public.journal_entries j where j.tenant_id=s.tenant_id and j.source_type='sale' and j.source_id=s.id and j.status='posted')
    union all
    select jsonb_build_object('source_type','purchase','source_id',p.id,'source_reference',p.purchase_number,'date',p.purchase_date)
    from public.purchases p
    where p.tenant_id=p_tenant_id and p.status='posted'
      and not exists(select 1 from public.journal_entries j where j.tenant_id=p.tenant_id and j.source_type='purchase' and j.source_id=p.id and j.status='posted')
    union all
    select jsonb_build_object('source_type','expense','source_id',e.id,'source_reference',e.expense_number,'date',e.expense_date)
    from public.expenses e
    where e.tenant_id=p_tenant_id and e.status='posted'
      and not exists(select 1 from public.journal_entries j where j.tenant_id=e.tenant_id and j.source_type='expense' and j.source_id=e.id and j.status='posted')
    union all
    select jsonb_build_object('source_type','purchase_invoice_v484','source_id',p.id,'source_reference',p.invoice_number,'date',p.invoice_date)
    from public.purchase_invoices_v484 p
    where p.tenant_id=p_tenant_id and p.status in ('posted','part_paid','paid')
      and not exists(select 1 from public.journal_entries j where j.tenant_id=p.tenant_id and j.source_type='purchase_invoice_v484' and j.source_id=p.id and j.status='posted')
    union all
    select jsonb_build_object('source_type','sales_return','source_id',r.id,'source_reference',r.return_number,'date',r.return_date)
    from public.sales_returns r
    where r.tenant_id=p_tenant_id
      and not exists(select 1 from public.journal_entries j where j.tenant_id=r.tenant_id and j.source_type='sales_return' and j.source_id=r.id and j.status='posted')
    union all
    select jsonb_build_object('source_type','purchase_return','source_id',r.id,'source_reference',r.return_number,'date',r.return_date)
    from public.purchase_returns r
    where r.tenant_id=p_tenant_id
      and not exists(select 1 from public.journal_entries j where j.tenant_id=r.tenant_id and j.source_type='purchase_return' and j.source_id=r.id and j.status='posted')
    union all
    select jsonb_build_object('source_type','supplier_payment_v484','source_id',p.id,'source_reference',p.payment_number,'date',p.payment_date)
    from public.supplier_payments_v484 p
    where p.tenant_id=p_tenant_id and p.status='posted'
      and not exists(select 1 from public.journal_entries j where j.tenant_id=p.tenant_id and j.source_type='supplier_payment_v484' and j.source_id=p.id and j.status='posted')
    limit 100
  ) q;

  return jsonb_build_object(
    'tenant_id',p_tenant_id,
    'healthy',(v_missing_sales+v_missing_purchases+v_missing_expenses+
               v_missing_purchase_invoices+v_missing_sales_returns+
               v_missing_purchase_returns+v_missing_supplier_payments+
               v_duplicate_sources+v_unbalanced)=0,
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

create or replace function public.accounting_repair_missing_journal_v600(
  p_tenant_id uuid, p_source_type text, p_source_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
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
  if not (
    private.erp_has_permission(p_tenant_id,'accounting.manage')
    or private.erp_has_permission(p_tenant_id,'accounting.journal')
  ) then raise exception 'Accounting repair permission required'; end if;

  if v_type not in (
    'sale','purchase','expense','purchase_invoice_v484',
    'sales_return','purchase_return','supplier_payment_v484'
  ) then raise exception 'Unsupported accounting repair source type'; end if;
  if p_source_id is null then raise exception 'Source id is required'; end if;

  if v_type='sale' then
    select sale_number,status into v_reference,v_status from public.sales
    where id=p_source_id and tenant_id=p_tenant_id;
    if v_status<>'posted' then raise exception 'Only posted Sale documents can be repaired'; end if;
  elsif v_type='purchase' then
    select purchase_number,status into v_reference,v_status from public.purchases
    where id=p_source_id and tenant_id=p_tenant_id;
    if v_status<>'posted' then raise exception 'Only posted Purchase documents can be repaired'; end if;
  elsif v_type='expense' then
    select expense_number,status into v_reference,v_status from public.expenses
    where id=p_source_id and tenant_id=p_tenant_id;
    if v_status<>'posted' then raise exception 'Only posted Expense documents can be repaired'; end if;
  elsif v_type='purchase_invoice_v484' then
    select invoice_number,status into v_reference,v_status from public.purchase_invoices_v484
    where id=p_source_id and tenant_id=p_tenant_id;
    if v_status not in ('posted','part_paid','paid') then
      raise exception 'Only posted Purchase Invoice documents can be repaired';
    end if;
  elsif v_type='sales_return' then
    select return_number into v_reference from public.sales_returns
    where id=p_source_id and tenant_id=p_tenant_id;
  elsif v_type='purchase_return' then
    select return_number into v_reference from public.purchase_returns
    where id=p_source_id and tenant_id=p_tenant_id;
  else
    select payment_number,status,supplier_id,location_id,payment_date,amount,payment_method
      into v_reference,v_status,v_supplier,v_location,v_date,v_amount,v_method
    from public.supplier_payments_v484
    where id=p_source_id and tenant_id=p_tenant_id;
    if v_status<>'posted' then raise exception 'Only posted Supplier Payments can be repaired'; end if;
  end if;

  if v_reference is null then raise exception 'Source document not found'; end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_tenant_id::text||':accounting-repair:'||v_type||':'||p_source_id::text,0)
  );

  select id into v_existing
  from public.journal_entries
  where tenant_id=p_tenant_id and source_type=v_type
    and source_id=p_source_id and status='posted'
  order by created_at limit 1;

  if v_existing is not null then
    return jsonb_build_object(
      'source_type',v_type,'source_id',p_source_id,
      'source_reference',v_reference,'journal_id',v_existing,
      'repaired',false,'reason','posted_journal_already_exists'
    );
  end if;

  if v_type='supplier_payment_v484' then
    v_lines:=jsonb_build_array(
      jsonb_build_object(
        'account_id',private.v4_account_id(p_tenant_id,'accounts_payable'),
        'debit',v_amount,'credit',0,'party_type','supplier','party_id',v_supplier,
        'description','Supplier payable settlement'
      ),
      jsonb_build_object(
        'account_id',private.v4_payment_account(p_tenant_id,lower(trim(v_method))),
        'debit',0,'credit',v_amount,'party_type','supplier','party_id',v_supplier,
        'description','Supplier payment'
      )
    );
    v_journal:=private.v4_journal_create(
      p_tenant_id,v_location,v_date,'Supplier Payment '||v_reference,
      'supplier_payment_v484',p_source_id,v_reference,v_lines
    );
  else
    select s.id into v_snapshot
    from public.gst_document_snapshots_v520 s
    where s.tenant_id=p_tenant_id and s.source_type=v_type and s.source_id=p_source_id
    order by s.created_at desc limit 1;

    if v_snapshot is not null then
      v_journal:=private.gst_authoritative_journal_post_v520(p_tenant_id,v_snapshot);
    elsif v_type in ('sale','purchase','expense') then
      v_journal:=private.v4_accounting_post_document(p_tenant_id,v_type,p_source_id);
    else
      raise exception
        'No authoritative GST snapshot exists for %. Automatic legacy repair is intentionally blocked; review this document manually.',
        v_type;
    end if;
  end if;

  if v_journal is null or not exists(
    select 1 from public.journal_entries j
    where j.id=v_journal and j.tenant_id=p_tenant_id
      and j.source_type=v_type and j.source_id=p_source_id and j.status='posted'
  ) then raise exception 'Accounting repair failed; no posted journal was created'; end if;

  return jsonb_build_object(
    'source_type',v_type,'source_id',p_source_id,'source_reference',v_reference,
    'journal_id',v_journal,'repaired',true,
    'accounting_route',
      case
        when v_type='supplier_payment_v484' then 'supplier_payment_reconstruction'
        when v_snapshot is not null then 'authoritative_gst_snapshot'
        else 'generic_accounting'
      end
  );
end
$function$;

revoke execute on function public.accounting_integrity_report_v600(uuid) from public, anon;
revoke execute on function public.accounting_repair_missing_journal_v600(uuid,text,uuid) from public, anon;
grant execute on function public.accounting_integrity_report_v600(uuid) to authenticated, service_role;
grant execute on function public.accounting_repair_missing_journal_v600(uuid,text,uuid) to authenticated, service_role;
