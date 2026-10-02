begin;

create or replace function private.document_small_balance_round_v616(
  p_tenant_id uuid,
  p_document_type text,
  p_document_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_kind text:=lower(trim(coalesce(p_document_type,'')));
  v_location uuid;
  v_party uuid;
  v_total numeric:=0;
  v_paid numeric:=0;
  v_returned numeric:=0;
  v_balance numeric:=0;
  v_payment uuid;
  v_rounding_account uuid;
  v_reference text;
  v_journal_id uuid;
  v_journal_count integer:=0;
begin
  if v_kind not in ('sale','purchase') then raise exception 'Document type must be sale or purchase'; end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  select o.location_id into v_location
  from public.document_origins o
  where o.tenant_id=p_tenant_id and o.entity_type=v_kind and o.entity_id=p_document_id
  order by o.created_at limit 1;
  if v_location is null then raise exception 'Document origin/location not found'; end if;
  if not private.erp_document_scope_allowed(p_tenant_id,v_location,v_location,'operate') then
    raise exception 'Location access denied';
  end if;

  if v_kind='sale' then
    if not private.erp_user_is_owner(p_tenant_id)
       and not private.erp_has_permission(p_tenant_id,'sales.manage')
       and not private.erp_has_permission(p_tenant_id,'accounting.manage') then
      raise exception 'Sales manage or accounting manage permission required';
    end if;
    select s.customer_id,s.grand_total into v_party,v_total
    from public.sales s
    where s.tenant_id=p_tenant_id and s.id=p_document_id
      and coalesce(s.status,'') not in ('void','cancelled')
    for update;
    if not found then raise exception 'Sale not found or not eligible'; end if;
    select coalesce(sum(p.amount),0) into v_paid
    from public.sale_payments p
    where p.tenant_id=p_tenant_id and p.sale_id=p_document_id;
    select coalesce(sum(r.grand_total),0) into v_returned
    from public.sales_returns r
    where r.tenant_id=p_tenant_id and r.sale_id=p_document_id and r.refund_status<>'waived';
    v_balance:=round(greatest(v_total-v_paid-v_returned,0),2);
  else
    if not private.erp_user_is_owner(p_tenant_id)
       and not private.erp_has_permission(p_tenant_id,'purchases.manage')
       and not private.erp_has_permission(p_tenant_id,'accounting.manage') then
      raise exception 'Purchases manage or accounting manage permission required';
    end if;
    select p.supplier_id,p.grand_total into v_party,v_total
    from public.purchases p
    where p.tenant_id=p_tenant_id and p.id=p_document_id and p.status='posted'
    for update;
    if not found then raise exception 'Purchase not found or not eligible'; end if;
    select coalesce(sum(pp.amount),0) into v_paid
    from public.purchase_payments pp
    where pp.tenant_id=p_tenant_id and pp.purchase_id=p_document_id;
    select coalesce(sum(r.grand_total),0) into v_returned
    from public.purchase_returns r
    where r.tenant_id=p_tenant_id and r.purchase_id=p_document_id and r.credit_status<>'waived';
    v_balance:=round(greatest(v_total-v_paid-v_returned,0),2);
  end if;

  if v_balance<=0.005 then raise exception 'Document has no remaining balance to close'; end if;
  if v_balance>=1.00 then
    raise exception 'Only a remaining balance below 1.00 can be closed as round-off. Current balance %',v_balance;
  end if;

  v_rounding_account:=private.v4_account_id(p_tenant_id,'rounding');
  v_reference:='RO-'||to_char(current_date,'YYMMDD')||'-'||
    upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));

  if v_kind='sale' then
    insert into public.sale_payments(
      tenant_id,sale_id,amount,payment_method,reference_number,notes,paid_at,created_by
    ) values(
      p_tenant_id,p_document_id,v_balance,'rounding',v_reference,
      'Small balance round-off'||case when trim(coalesce(p_reason,''))='' then '' else ' • '||trim(p_reason) end,
      now(),auth.uid()
    ) returning id into v_payment;
  else
    insert into public.purchase_payments(
      tenant_id,purchase_id,amount,payment_method,reference_number,notes,paid_at,created_by
    ) values(
      p_tenant_id,p_document_id,v_balance,'rounding',v_reference,
      'Small balance round-off'||case when trim(coalesce(p_reason,''))='' then '' else ' • '||trim(p_reason) end,
      now(),auth.uid()
    ) returning id into v_payment;
  end if;

  select count(*),min(j.id)
    into v_journal_count,v_journal_id
  from public.journal_entries j
  where j.tenant_id=p_tenant_id
    and j.source_type=case when v_kind='sale' then 'sale_payment' else 'purchase_payment' end
    and j.source_id=v_payment
    and j.status='posted';

  if v_journal_count<>1 then
    raise exception 'Accounting integrity failure: expected one rounding journal, found %',v_journal_count;
  end if;

  perform private.business_audit_write_v471(
    p_tenant_id,v_kind||'.balance.rounding',v_kind,p_document_id,v_reference,
    jsonb_build_object('balance_before',v_balance),
    jsonb_build_object(
      'balance_after',0,'rounding_amount',v_balance,
      'rounding_account_id',v_rounding_account,'journal_id',v_journal_id,
      'reason',nullif(trim(coalesce(p_reason,'')),'')
    )
  );
  perform private.thq_sync_bump_v480(
    p_tenant_id,'finance',v_kind||'_rounding',p_document_id::text,'post'
  );
  return jsonb_build_object(
    'success',true,'document_type',v_kind,'document_id',p_document_id,
    'payment_id',v_payment,'journal_id',v_journal_id,'rounding_amount',v_balance,
    'outstanding_after',0,'reference_number',v_reference
  );
end;
$function$;

insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  302,
  '6.1.6-build9-roundoff-guard',
  'v6.1.6 Build 9 Round-off Accounting Guard',
  'Makes existing sale/purchase payment triggers the sole accounting owner for small-balance round-off payments and verifies exactly one posted rounding journal. No GST or invoice-value semantics changed.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
