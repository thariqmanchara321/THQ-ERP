create or replace function private.v4_sale_payment_after_insert()
returns trigger
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_tenant uuid;
  v_loc uuid;
  v_ref text;
  v_customer uuid;
  v_lines jsonb;
  v_receipt text;
  v_authoritative boolean:=false;
begin
  v_receipt:=current_setting('thq.customer_receipt_id',true);
  if nullif(v_receipt,'') is not null then
    return new;
  end if;

  select s.tenant_id,s.sale_number,s.customer_id,o.location_id
    into v_tenant,v_ref,v_customer,v_loc
  from public.sales s
  left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
  where s.id=new.sale_id;

  if v_tenant is null or v_loc is null then
    return new;
  end if;

  v_authoritative:=private.gst_v520_authoritative_context_for_source(v_tenant,'sale',new.sale_id);

  -- A v5.2.2 sale journal already embeds its invoice-time payment allocations.
  -- Do not create a second AR/cash journal for those same payments.
  -- Later receipts, outside the authoritative sale transaction, still post normally.
  if not v_authoritative
     and not exists(
       select 1 from public.journal_entries
       where tenant_id=v_tenant and source_type='sale_payment' and source_id=new.id and status='posted'
     ) then
    v_lines:=jsonb_build_array(
      jsonb_build_object(
        'account_id',private.v4_payment_account(v_tenant,new.payment_method),
        'debit',new.amount,'credit',0,
        'party_type','customer','party_id',v_customer,
        'description','Customer receipt'
      ),
      jsonb_build_object(
        'account_id',private.v4_account_id(v_tenant,'accounts_receivable'),
        'debit',0,'credit',new.amount,
        'party_type','customer','party_id',v_customer,
        'description','Receivable settlement'
      )
    );
    perform private.v4_journal_create(
      v_tenant,v_loc,coalesce(new.paid_at::date,current_date),
      'Customer receipt • '||v_ref,'sale_payment',new.id,v_ref,v_lines
    );
  end if;

  -- Cash drawer movement is operational evidence and is still required for
  -- invoice-time cash allocations even though their GL effect is embedded
  -- in the authoritative Sale journal.
  if lower(coalesce(new.payment_method,''))='cash' then
    insert into public.cash_drawer_movements(
      tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by
    )
    select v_tenant,sh.id,'sale',new.amount,'sale_payment',new.id,v_ref,'Customer cash receipt',auth.uid()
    from public.document_origins o
    join public.cashier_shifts sh
      on sh.tenant_id=v_tenant and sh.device_id=o.device_id and sh.status='open'
    where o.entity_type='sale' and o.entity_id=new.sale_id
      and not exists(
        select 1 from public.cash_drawer_movements m
        where m.reference_type='sale_payment' and m.reference_id=new.id
      )
    limit 1;
  end if;

  return new;
end
$function$;

create or replace function public.accounting_v522_embedded_payment_report_v600(p_tenant_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_count integer;
  v_rows jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not (private.erp_has_permission(p_tenant_id,'accounting.view') or private.erp_has_permission(p_tenant_id,'accounting.manage') or private.erp_has_permission(p_tenant_id,'accounting.journal')) then
    raise exception 'Accounting permission required';
  end if;

  select count(*) into v_count
  from public.sale_payment_allocations_v522 a
  join public.sale_payments sp on sp.id=a.sale_payment_id and sp.tenant_id=a.tenant_id
  join public.gst_document_snapshots_v520 s on s.tenant_id=a.tenant_id and s.source_type='sale' and s.source_id=a.sale_id
  join public.journal_entries j on j.tenant_id=a.tenant_id and j.source_type='sale_payment' and j.source_id=sp.id and j.status='posted'
  where a.tenant_id=p_tenant_id and a.settlement_amount>0;

  select coalesce(jsonb_agg(x order by x->>'sale_number',x->>'payment_id'),'[]'::jsonb) into v_rows
  from (
    select jsonb_build_object(
      'sale_id',sa.id,
      'sale_number',sa.sale_number,
      'payment_id',sp.id,
      'amount',sp.amount,
      'method',sp.payment_method,
      'payment_journal_id',j.id
    ) x
    from public.sale_payment_allocations_v522 a
    join public.sale_payments sp on sp.id=a.sale_payment_id and sp.tenant_id=a.tenant_id
    join public.sales sa on sa.id=a.sale_id and sa.tenant_id=a.tenant_id
    join public.gst_document_snapshots_v520 s on s.tenant_id=a.tenant_id and s.source_type='sale' and s.source_id=a.sale_id
    join public.journal_entries j on j.tenant_id=a.tenant_id and j.source_type='sale_payment' and j.source_id=sp.id and j.status='posted'
    where a.tenant_id=p_tenant_id and a.settlement_amount>0
    limit 100
  ) q;

  return jsonb_build_object(
    'tenant_id',p_tenant_id,
    'healthy',v_count=0,
    'embedded_payment_duplicate_journals',v_count,
    'items',v_rows
  );
end
$function$;

revoke all on function public.accounting_v522_embedded_payment_report_v600(uuid) from public,anon;
grant execute on function public.accounting_v522_embedded_payment_report_v600(uuid) to authenticated,service_role;

create or replace function public.accounting_repair_v522_embedded_payment_journals_v600(p_tenant_id uuid,p_sale_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_snapshot uuid;
  v_sale_journal uuid;
  v_expected jsonb;
  v_count integer:=0;
  v_sale_number text;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not (private.erp_has_permission(p_tenant_id,'accounting.manage') or private.erp_has_permission(p_tenant_id,'accounting.journal')) then
    raise exception 'Accounting repair permission required';
  end if;

  select sale_number into v_sale_number
  from public.sales where tenant_id=p_tenant_id and id=p_sale_id and status='posted';
  if v_sale_number is null then raise exception 'Posted Sale not found'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':v522-payment-repair:'||p_sale_id::text,0));

  select id into v_snapshot
  from public.gst_document_snapshots_v520
  where tenant_id=p_tenant_id and source_type='sale' and source_id=p_sale_id
  order by created_at desc limit 1;
  if v_snapshot is null then raise exception 'Authoritative GST Sale snapshot not found'; end if;

  v_expected:=private.gst_snapshot_sale_journal_lines_v522(p_tenant_id,v_snapshot);
  select id into v_sale_journal
  from public.journal_entries
  where tenant_id=p_tenant_id and source_type='sale' and source_id=p_sale_id and status='posted'
  order by created_at limit 1;
  if v_sale_journal is null or not private.gst_journal_matches_expected_v520(p_tenant_id,v_sale_journal,v_expected) then
    raise exception 'Authoritative Sale journal is missing or does not match the snapshot; payment repair is blocked';
  end if;

  with target as (
    select distinct j.id
    from public.sale_payment_allocations_v522 a
    join public.sale_payments sp on sp.id=a.sale_payment_id and sp.tenant_id=a.tenant_id
    join public.journal_entries j on j.tenant_id=a.tenant_id and j.source_type='sale_payment' and j.source_id=sp.id and j.status='posted'
    where a.tenant_id=p_tenant_id and a.sale_id=p_sale_id and a.settlement_amount>0
  ), upd as (
    update public.journal_entries j
       set status='reversed'
     where j.id in (select id from target)
     returning j.id
  )
  select count(*) into v_count from upd;

  return jsonb_build_object(
    'tenant_id',p_tenant_id,
    'sale_id',p_sale_id,
    'sale_number',v_sale_number,
    'authoritative_sale_journal_id',v_sale_journal,
    'reversed_duplicate_payment_journals',v_count,
    'repaired',v_count>0
  );
end
$function$;

revoke all on function public.accounting_repair_v522_embedded_payment_journals_v600(uuid,uuid) from public,anon;
grant execute on function public.accounting_repair_v522_embedded_payment_journals_v600(uuid,uuid) to authenticated,service_role;;
