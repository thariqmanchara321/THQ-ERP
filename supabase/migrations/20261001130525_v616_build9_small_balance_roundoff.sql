
begin;

-- Allow a non-cash settlement row that is explicitly backed by the
-- Rounding / Variance GL account. Normal payment RPCs still do not accept it.
alter table public.sale_payments
  drop constraint if exists sale_payments_payment_method_check;
alter table public.sale_payments
  add constraint sale_payments_payment_method_check
  check (payment_method = any(array[
    'cash','bank','card','upi','cheque','wallet','other',
    'discount','write_off','rounding'
  ]::text[]));

alter table public.purchase_payments
  drop constraint if exists purchase_payments_payment_method_check;
alter table public.purchase_payments
  add constraint purchase_payments_payment_method_check
  check (payment_method = any(array[
    'cash','bank','card','upi','cheque','other',
    'discount','write_off','rounding'
  ]::text[]));

create or replace function private.v4_payment_account(
  p_tenant_id uuid,
  p_method text
)
returns uuid
language plpgsql
stable security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  k text:=lower(coalesce(p_method,'cash'));
begin
  if k='rounding' then
    return private.v4_account_id(p_tenant_id,'rounding');
  end if;

  if k in('cash') then
    k:='cash';
  elsif k in('upi') then
    k:='upi';
  elsif k in('card','credit_card','debit_card') then
    k:='card';
  else
    k:='bank';
  end if;

  return private.v4_account_id(p_tenant_id,'payment.'||k);
end;
$function$;

-- Preserve the v5.2 rule that invoice-time payments are already embedded in
-- the authoritative sale journal, but allow a later ROUNDING row to post its
-- own AR/Rounding settlement journal.
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
  left join public.document_origins o
    on o.entity_type='sale' and o.entity_id=s.id
  where s.id=new.sale_id;

  if v_tenant is null or v_loc is null then
    return new;
  end if;

  v_authoritative:=private.gst_v520_authoritative_context_for_source(
    v_tenant,'sale',new.sale_id
  );

  if (not v_authoritative or lower(coalesce(new.payment_method,''))='rounding')
     and not exists(
       select 1 from public.journal_entries
       where tenant_id=v_tenant
         and source_type='sale_payment'
         and source_id=new.id
         and status='posted'
     ) then
    v_lines:=jsonb_build_array(
      jsonb_build_object(
        'account_id',private.v4_payment_account(v_tenant,new.payment_method),
        'debit',new.amount,'credit',0,
        'party_type','customer','party_id',v_customer,
        'description',
          case when lower(coalesce(new.payment_method,''))='rounding'
            then 'Small balance round-off'
            else 'Customer receipt'
          end
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
      case when lower(coalesce(new.payment_method,''))='rounding'
        then 'Customer small balance round-off • '
        else 'Customer receipt • '
      end||v_ref,
      'sale_payment',new.id,v_ref,v_lines
    );
  end if;

  if lower(coalesce(new.payment_method,''))='cash' then
    insert into public.cash_drawer_movements(
      tenant_id,shift_id,movement_type,amount,reference_type,
      reference_id,reference_number,note,created_by
    )
    select
      v_tenant,sh.id,'sale',new.amount,'sale_payment',new.id,v_ref,
      'Customer cash receipt',auth.uid()
    from public.document_origins o
    join public.cashier_shifts sh
      on sh.tenant_id=v_tenant
     and sh.device_id=o.device_id
     and sh.status='open'
    where o.entity_type='sale'
      and o.entity_id=new.sale_id
      and not exists(
        select 1
        from public.cash_drawer_movements m
        where m.reference_type='sale_payment'
          and m.reference_id=new.id
      )
    limit 1;
  end if;

  return new;
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
  v_amount numeric:=round(coalesce(p_amount,0),2);
  v_result jsonb:='{}'::jsonb;
  v_balance numeric;
  v_rounding numeric:=0;
  v_rounding_payment uuid;
  v_location uuid;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then
    raise exception 'Request ID is required';
  end if;

  v_existing:=private.v47_request_existing(
    p_tenant_id,p_request_id,'sale.payment.v616'
  );
  if v_existing is not null then return v_existing; end if;

  if v_amount<0 then
    raise exception 'Payment amount cannot be negative';
  end if;
  if v_amount<=0 and not coalesce(p_close_small_balance,false) then
    raise exception 'Enter a payment amount or choose to close a small balance';
  end if;

  if v_amount>0 then
    v_result:=public.sales_add_payment_v32(
      p_tenant_id,p_sale_id,v_amount,p_payment_method,
      p_reference_number,p_notes
    );
  else
    perform 1
    from public.sales
    where id=p_sale_id and tenant_id=p_tenant_id and status='posted'
    for update;
    if not found then raise exception 'Sale not found or is not active'; end if;
  end if;

  select
    round(greatest(s.grand_total-coalesce(py.paid,0),0),2),
    o.location_id
  into v_balance,v_location
  from public.sales s
  left join (
    select sale_id,sum(amount) paid
    from public.sale_payments
    where tenant_id=p_tenant_id
    group by sale_id
  ) py on py.sale_id=s.id
  left join public.document_origins o
    on o.tenant_id=s.tenant_id and o.entity_type='sale' and o.entity_id=s.id
  where s.id=p_sale_id and s.tenant_id=p_tenant_id;

  if v_balance is null then raise exception 'Sale not found'; end if;

  if coalesce(p_close_small_balance,false) and v_balance>0.005 then
    if v_balance>=1.00 then
      raise exception
        'Round-off close is only allowed when the remaining balance is below 1.00. Remaining %',
        v_balance;
    end if;

    if v_location is null then
      raise exception 'Could not determine sale location for round-off';
    end if;

    insert into public.sale_payments(
      tenant_id,sale_id,amount,payment_method,
      reference_number,notes,paid_at,created_by
    )
    values(
      p_tenant_id,p_sale_id,v_balance,'rounding',
      'ROUND-OFF',
      concat(
        'Small balance round-off',
        case when trim(coalesce(p_notes,''))=''
          then '' else ' • '||trim(p_notes) end
      ),
      now(),auth.uid()
    )
    returning id into v_rounding_payment;

    v_rounding:=v_balance;
    v_balance:=0;

    perform private.business_audit_write_v471(
      p_tenant_id,'sale.balance.roundoff','sale',p_sale_id,
      'ROUND-OFF',null::jsonb,
      jsonb_build_object(
        'amount',v_rounding,
        'payment_id',v_rounding_payment,
        'threshold',1.00,
        'gst_unchanged',true
      )
    );
  end if;

  v_result:=coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'success',true,
    'amount',v_amount,
    'balance_due',v_balance,
    'payment_status',case when v_balance<=0.005 then 'paid' else 'partial' end,
    'rounding_closed',v_rounding>0,
    'rounding_amount',v_rounding,
    'rounding_payment_id',v_rounding_payment
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
  v_amount numeric:=round(coalesce(p_amount,0),2);
  v_result jsonb:='{}'::jsonb;
  v_balance numeric;
  v_rounding numeric:=0;
  v_rounding_payment uuid;
  v_location uuid;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then
    raise exception 'Request ID is required';
  end if;

  v_existing:=private.v47_request_existing(
    p_tenant_id,p_request_id,'purchase.payment.v616'
  );
  if v_existing is not null then return v_existing; end if;

  if v_amount<0 then
    raise exception 'Payment amount cannot be negative';
  end if;
  if v_amount<=0 and not coalesce(p_close_small_balance,false) then
    raise exception 'Enter a payment amount or choose to close a small balance';
  end if;

  if v_amount>0 then
    v_result:=public.purchases_add_payment_v32(
      p_tenant_id,p_purchase_id,v_amount,p_payment_method,
      p_reference_number,p_notes
    );
  else
    perform 1
    from public.purchases
    where id=p_purchase_id and tenant_id=p_tenant_id and status='posted'
    for update;
    if not found then raise exception 'Purchase not found or is not active'; end if;
  end if;

  select
    round(greatest(p.grand_total-coalesce(py.paid,0),0),2),
    o.location_id
  into v_balance,v_location
  from public.purchases p
  left join (
    select purchase_id,sum(amount) paid
    from public.purchase_payments
    where tenant_id=p_tenant_id
    group by purchase_id
  ) py on py.purchase_id=p.id
  left join public.document_origins o
    on o.tenant_id=p.tenant_id
   and o.entity_type='purchase'
   and o.entity_id=p.id
  where p.id=p_purchase_id and p.tenant_id=p_tenant_id;

  if v_balance is null then raise exception 'Purchase not found'; end if;

  if coalesce(p_close_small_balance,false) and v_balance>0.005 then
    if v_balance>=1.00 then
      raise exception
        'Round-off close is only allowed when the remaining balance is below 1.00. Remaining %',
        v_balance;
    end if;

    if v_location is null then
      raise exception 'Could not determine purchase location for round-off';
    end if;

    insert into public.purchase_payments(
      tenant_id,purchase_id,amount,payment_method,
      reference_number,notes,paid_at,created_by
    )
    values(
      p_tenant_id,p_purchase_id,v_balance,'rounding',
      'ROUND-OFF',
      concat(
        'Small balance round-off',
        case when trim(coalesce(p_notes,''))=''
          then '' else ' • '||trim(p_notes) end
      ),
      now(),auth.uid()
    )
    returning id into v_rounding_payment;

    v_rounding:=v_balance;
    v_balance:=0;

    perform private.business_audit_write_v471(
      p_tenant_id,'purchase.balance.roundoff','purchase',p_purchase_id,
      'ROUND-OFF',null::jsonb,
      jsonb_build_object(
        'amount',v_rounding,
        'payment_id',v_rounding_payment,
        'threshold',1.00,
        'gst_unchanged',true
      )
    );
  end if;

  v_result:=coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'success',true,
    'amount',v_amount,
    'balance_due',v_balance,
    'payment_status',case when v_balance<=0.005 then 'paid' else 'partial' end,
    'rounding_closed',v_rounding>0,
    'rounding_amount',v_rounding,
    'rounding_payment_id',v_rounding_payment
  );

  return private.v47_request_complete(
    p_tenant_id,p_request_id,'purchase.payment.v616',v_result
  );
end;
$function$;

revoke all on function public.sales_add_payment_v616(
  uuid,uuid,numeric,text,text,text,boolean,text
) from public,anon;
grant execute on function public.sales_add_payment_v616(
  uuid,uuid,numeric,text,text,text,boolean,text
) to authenticated;

revoke all on function public.purchases_add_payment_v616(
  uuid,uuid,numeric,text,text,text,boolean,text
) from public,anon;
grant execute on function public.purchases_add_payment_v616(
  uuid,uuid,numeric,text,text,text,boolean,text
) to authenticated;

insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  301,
  '6.1.6-build9-roundoff',
  'v6.1.6 Build 9 Small Balance Round-off',
  'Adds explicit document-level Sales/Purchase balance closure below 1.00 using the mapped Rounding / Variance account. Real payment amount remains separate; GST invoice values/snapshots are unchanged.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

update public.platform_app_releases
set release_notes =
  'THQ ERP v6.1.6 Build 9 — Customer Receipt Safety + Small Balance Round-off. '
  'Prevents customer receipt amount overwrite, adds auditable receipt voiding, fixes serial-item dialog overflow, '
  'and allows explicitly closing Sales/Purchase residual balances below 1.00 to Rounding / Variance without changing GST invoice values.'
where version='6.1.6' and build_number=9
  and app_key in('client','pos','admin');

commit;
;
