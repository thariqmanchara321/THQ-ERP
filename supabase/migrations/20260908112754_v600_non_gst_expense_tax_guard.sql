-- THQ ERP v6.0
-- Non-GST businesses must not post GST tax on expenses.

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
     where tenant_id=p_tenant_id and source_type='expense'
       and source_id=v_id and status='posted';

    update public.expenses
       set round_off=v_round,total_amount=v_final
     where id=v_id and tenant_id=p_tenant_id;
  end if;

  select j.id into v_journal_id
  from public.journal_entries j
  where j.tenant_id=p_tenant_id and j.source_type='expense'
    and j.source_id=v_id and j.status='posted'
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
