create or replace function public.sales_add_payment_v32(
  p_tenant_id uuid,
  p_sale_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_reference_number text,
  p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_loc uuid;
  v_total numeric:=0;
  v_paid numeric:=0;
  v_returned numeric:=0;
  v_balance numeric:=0;
  v_amount numeric:=round(coalesce(p_amount,0),2);
  v_method text:=lower(trim(coalesce(p_payment_method,'')));
  v jsonb;
begin
  select o.location_id into v_loc
  from public.document_origins o
  where o.entity_type='sale'
    and o.entity_id=p_sale_id
    and o.tenant_id=p_tenant_id
  order by o.created_at
  limit 1;

  if not private.erp_document_scope_allowed(
    p_tenant_id,v_loc,null,'operate'
  ) then
    raise exception 'Location access denied';
  end if;

  if v_method='bank_transfer' then
    v_method:='bank';
  end if;

  if v_amount<=0 then
    raise exception 'Payment amount must be greater than zero';
  end if;

  select s.grand_total into v_total
  from public.sales s
  where s.id=p_sale_id
    and s.tenant_id=p_tenant_id
    and s.status='posted'
  for update;

  if not found then
    raise exception 'Sale not found or is not active';
  end if;

  select coalesce(sum(sp.amount),0)
    into v_paid
  from public.sale_payments sp
  where sp.tenant_id=p_tenant_id
    and sp.sale_id=p_sale_id;

  select coalesce(sum(sr.grand_total),0)
    into v_returned
  from public.sales_returns sr
  where sr.tenant_id=p_tenant_id
    and sr.sale_id=p_sale_id
    and sr.refund_status<>'waived';

  v_balance:=round(greatest(v_total-v_paid-v_returned,0),2);

  if v_balance<=0.005 then
    raise exception 'This sale is already fully settled after returns';
  end if;

  if v_amount>v_balance+0.005 then
    raise exception
      'Payment % exceeds return-adjusted remaining balance %',
      v_amount,v_balance;
  end if;

  v:=public.sales_add_payment(
    p_tenant_id,
    p_sale_id,
    v_amount,
    v_method,
    p_reference_number,
    p_notes
  );

  return coalesce(v,'{}'::jsonb)||jsonb_build_object(
    'returned_amount',round(v_returned,2),
    'return_adjusted',true,
    'balance_due',round(greatest(v_balance-v_amount,0),2)
  );
end;
$function$;

create or replace function public.purchases_add_payment_v32(
  p_tenant_id uuid,
  p_purchase_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_reference_number text,
  p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_loc uuid;
  v_total numeric:=0;
  v_paid numeric:=0;
  v_returned numeric:=0;
  v_balance numeric:=0;
  v_amount numeric:=round(coalesce(p_amount,0),2);
  v_method text:=lower(trim(coalesce(p_payment_method,'')));
  v jsonb;
begin
  select o.location_id into v_loc
  from public.document_origins o
  where o.entity_type='purchase'
    and o.entity_id=p_purchase_id
    and o.tenant_id=p_tenant_id
  order by o.created_at
  limit 1;

  if not private.erp_document_scope_allowed(
    p_tenant_id,v_loc,null,'operate'
  ) then
    raise exception 'Location access denied';
  end if;

  if v_method='bank_transfer' then
    v_method:='bank';
  end if;

  if v_amount<=0 then
    raise exception 'Payment amount must be greater than zero';
  end if;

  select p.grand_total into v_total
  from public.purchases p
  where p.id=p_purchase_id
    and p.tenant_id=p_tenant_id
    and p.status='posted'
  for update;

  if not found then
    raise exception 'Purchase not found or is not active';
  end if;

  select coalesce(sum(pp.amount),0)
    into v_paid
  from public.purchase_payments pp
  where pp.tenant_id=p_tenant_id
    and pp.purchase_id=p_purchase_id;

  select coalesce(sum(pr.grand_total),0)
    into v_returned
  from public.purchase_returns pr
  where pr.tenant_id=p_tenant_id
    and pr.purchase_id=p_purchase_id
    and pr.credit_status<>'waived';

  v_balance:=round(greatest(v_total-v_paid-v_returned,0),2);

  if v_balance<=0.005 then
    raise exception 'This purchase is already fully settled after returns';
  end if;

  if v_amount>v_balance+0.005 then
    raise exception
      'Payment % exceeds return-adjusted remaining balance %',
      v_amount,v_balance;
  end if;

  v:=public.purchases_add_payment(
    p_tenant_id,
    p_purchase_id,
    v_amount,
    v_method,
    p_reference_number,
    p_notes
  );

  return coalesce(v,'{}'::jsonb)||jsonb_build_object(
    'returned_amount',round(v_returned,2),
    'return_adjusted',true,
    'balance_due',round(greatest(v_balance-v_amount,0),2)
  );
end;
$function$;

create or replace function public.sales_add_payment_v616(
  p_tenant_id uuid,
  p_sale_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_reference_number text,
  p_notes text,
  p_close_small_balance boolean default false,
  p_request_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_existing jsonb;
  v_payment jsonb;
  v_rounding jsonb:='{}'::jsonb;
  v_result jsonb;
  v_balance numeric:=0;
  v_method text:=lower(trim(coalesce(p_payment_method,'')));
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then
    raise exception 'Request ID is required';
  end if;

  v_existing:=private.v47_request_existing(
    p_tenant_id,p_request_id,'sale.payment.v616'
  );
  if v_existing is not null then return v_existing; end if;

  if v_method='bank_transfer' then
    v_method:='bank';
  end if;

  v_payment:=public.sales_add_payment_v47(
    p_tenant_id,p_sale_id,p_amount,v_method,
    p_reference_number,p_notes,p_request_id||':payment'
  );

  begin
    v_balance:=round(coalesce((v_payment->>'balance_due')::numeric,0),2);
  exception when others then
    v_balance:=0;
  end;

  if coalesce(p_close_small_balance,false) and v_balance>0.005 then
    if v_balance>=1.00 then
      raise exception
        'Only a remaining balance below 1.00 can be closed as round-off. Current balance %',
        v_balance;
    end if;

    v_rounding:=public.document_small_balance_close_v616(
      p_tenant_id,'sale',p_sale_id,
      'Close residual during payment',
      p_request_id||':rounding'
    );
    v_balance:=0;
  end if;

  v_result:=coalesce(v_payment,'{}'::jsonb)||jsonb_build_object(
    'close_small_balance',coalesce(p_close_small_balance,false),
    'rounding',v_rounding,
    'balance_due',v_balance
  );

  return private.v47_request_complete(
    p_tenant_id,p_request_id,'sale.payment.v616',v_result
  );
end;
$function$;

create or replace function public.purchases_add_payment_v616(
  p_tenant_id uuid,
  p_purchase_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_reference_number text,
  p_notes text,
  p_close_small_balance boolean default false,
  p_request_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_existing jsonb;
  v_payment jsonb;
  v_rounding jsonb:='{}'::jsonb;
  v_result jsonb;
  v_balance numeric:=0;
  v_method text:=lower(trim(coalesce(p_payment_method,'')));
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then
    raise exception 'Request ID is required';
  end if;

  v_existing:=private.v47_request_existing(
    p_tenant_id,p_request_id,'purchase.payment.v616'
  );
  if v_existing is not null then return v_existing; end if;

  if v_method='bank_transfer' then
    v_method:='bank';
  end if;

  v_payment:=public.purchases_add_payment_v47(
    p_tenant_id,p_purchase_id,p_amount,v_method,
    p_reference_number,p_notes,p_request_id||':payment'
  );

  begin
    v_balance:=round(coalesce((v_payment->>'balance_due')::numeric,0),2);
  exception when others then
    v_balance:=0;
  end;

  if coalesce(p_close_small_balance,false) and v_balance>0.005 then
    if v_balance>=1.00 then
      raise exception
        'Only a remaining balance below 1.00 can be closed as round-off. Current balance %',
        v_balance;
    end if;

    v_rounding:=public.document_small_balance_close_v616(
      p_tenant_id,'purchase',p_purchase_id,
      'Close residual during payment',
      p_request_id||':rounding'
    );
    v_balance:=0;
  end if;

  v_result:=coalesce(v_payment,'{}'::jsonb)||jsonb_build_object(
    'close_small_balance',coalesce(p_close_small_balance,false),
    'rounding',v_rounding,
    'balance_due',v_balance
  );

  return private.v47_request_complete(
    p_tenant_id,p_request_id,'purchase.payment.v616',v_result
  );
end;
$function$;

create or replace function public.sales_get_detail_v520(
  p_tenant_id uuid,
  p_sale_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_result jsonb;
  v_gst jsonb;
  v_total numeric:=0;
  v_paid numeric:=0;
  v_returned numeric:=0;
  v_balance numeric:=0;
begin
  v_result:=public.sales_get_detail_v495(p_tenant_id,p_sale_id);

  select s.grand_total into v_total
  from public.sales s
  where s.tenant_id=p_tenant_id and s.id=p_sale_id;

  select coalesce(sum(sp.amount),0) into v_paid
  from public.sale_payments sp
  where sp.tenant_id=p_tenant_id and sp.sale_id=p_sale_id;

  select coalesce(sum(sr.grand_total),0) into v_returned
  from public.sales_returns sr
  where sr.tenant_id=p_tenant_id
    and sr.sale_id=p_sale_id
    and sr.refund_status<>'waived';

  v_balance:=round(greatest(v_total-v_paid-v_returned,0),2);

  v_result:=v_result||jsonb_build_object(
    'paid_amount',round(v_paid,2),
    'returned_amount',round(v_returned,2),
    'net_document_total',round(greatest(v_total-v_returned,0),2),
    'balance_due',v_balance,
    'return_adjusted',true
  );

  select jsonb_build_object(
    'authoritative',true,
    'snapshot_id',s.id,
    'document_class',s.document_class,
    'tax_mode',s.tax_mode,
    'supply_type',s.supply_type,
    'interstate',s.interstate,
    'place_of_supply_code',s.place_of_supply_code,
    'supplier_gstin',s.supplier_gstin,
    'recipient_gstin',s.recipient_gstin,
    'taxable_total',s.taxable_total,
    'cgst_total',s.cgst_total,
    'sgst_total',s.sgst_total,
    'utgst_total',s.utgst_total,
    'igst_total',s.igst_total,
    'cess_total',s.cess_total,
    'tax_collected_total',s.tax_collected_total,
    'government_tax_total',s.government_tax_total,
    'lines',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'source_line_id',l.source_line_id,
          'line_no',l.line_no,
          'hsn_sac',l.hsn_sac,
          'gst_rate',l.applied_gst_rate,
          'taxable_value',l.taxable_value,
          'cgst',l.cgst,
          'sgst',l.sgst,
          'utgst',l.utgst,
          'igst',l.igst,
          'cess',l.cess,
          'tax_amount',l.tax_amount
        ) order by l.line_no
      )
      from public.gst_document_line_snapshots_v520 l
      where l.snapshot_id=s.id
    ),'[]'::jsonb)
  )
  into v_gst
  from public.gst_document_snapshots_v520 s
  where s.tenant_id=p_tenant_id
    and s.source_type='sale'
    and s.source_id=p_sale_id
  order by s.created_at desc
  limit 1;

  return v_result||jsonb_build_object('gst',v_gst);
end;
$function$;

create or replace function public.purchases_get_detail_v520(
  p_tenant_id uuid,
  p_purchase_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_result jsonb;
  v_gst jsonb;
  v_total numeric:=0;
  v_paid numeric:=0;
  v_returned numeric:=0;
  v_balance numeric:=0;
begin
  v_result:=public.purchases_get_detail_v32(p_tenant_id,p_purchase_id);

  select p.grand_total into v_total
  from public.purchases p
  where p.tenant_id=p_tenant_id and p.id=p_purchase_id;

  select coalesce(sum(pp.amount),0) into v_paid
  from public.purchase_payments pp
  where pp.tenant_id=p_tenant_id and pp.purchase_id=p_purchase_id;

  select coalesce(sum(pr.grand_total),0) into v_returned
  from public.purchase_returns pr
  where pr.tenant_id=p_tenant_id
    and pr.purchase_id=p_purchase_id
    and pr.credit_status<>'waived';

  v_balance:=round(greatest(v_total-v_paid-v_returned,0),2);

  v_result:=v_result||jsonb_build_object(
    'paid_amount',round(v_paid,2),
    'returned_amount',round(v_returned,2),
    'net_document_total',round(greatest(v_total-v_returned,0),2),
    'balance_due',v_balance,
    'return_adjusted',true
  );

  select jsonb_build_object(
    'authoritative',true,
    'snapshot_id',s.id,
    'document_class',s.document_class,
    'tax_mode',s.tax_mode,
    'supply_type',s.supply_type,
    'interstate',s.interstate,
    'place_of_supply_code',s.place_of_supply_code,
    'supplier_gstin',s.supplier_gstin,
    'recipient_gstin',s.recipient_gstin,
    'taxable_total',s.taxable_total,
    'cgst_total',s.cgst_total,
    'sgst_total',s.sgst_total,
    'utgst_total',s.utgst_total,
    'igst_total',s.igst_total,
    'cess_total',s.cess_total,
    'tax_collected_total',s.tax_collected_total,
    'government_tax_total',s.government_tax_total,
    'lines',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'source_line_id',l.source_line_id,
          'line_no',l.line_no,
          'hsn_sac',l.hsn_sac,
          'gst_rate',l.applied_gst_rate,
          'taxable_value',l.taxable_value,
          'cgst',l.cgst,
          'sgst',l.sgst,
          'utgst',l.utgst,
          'igst',l.igst,
          'cess',l.cess,
          'tax_amount',l.tax_amount
        ) order by l.line_no
      )
      from public.gst_document_line_snapshots_v520 l
      where l.snapshot_id=s.id
    ),'[]'::jsonb)
  )
  into v_gst
  from public.gst_document_snapshots_v520 s
  where s.tenant_id=p_tenant_id
    and s.source_type='purchase'
    and s.source_id=p_purchase_id
  order by s.created_at desc
  limit 1;

  return v_result||jsonb_build_object('gst',v_gst);
end;
$function$;

insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  323,
  '6.2.1-return-aware-payment-detail-hardening',
  'Return-aware Payment and Detail Hardening',
  'Makes direct Sale/Purchase payments and detail balances return-aware, normalizes the legacy bank_transfer alias to bank, and keeps small-balance round-off limited to actual residuals below 1.00. GST snapshots and original document values remain immutable.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;
