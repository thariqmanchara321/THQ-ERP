begin;

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
  if k in('cash') then k:='cash';
  elsif k in('upi') then k:='upi';
  elsif k in('card','credit_card','debit_card') then k:='card';
  else k:='bank';
  end if;
  return private.v4_account_id(p_tenant_id,'payment.'||k);
end;
$function$;

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
  if nullif(v_receipt,'') is not null then return new; end if;

  select s.tenant_id,s.sale_number,s.customer_id,o.location_id
    into v_tenant,v_ref,v_customer,v_loc
  from public.sales s
  left join public.document_origins o
    on o.entity_type='sale' and o.entity_id=s.id
  where s.id=new.sale_id;

  if v_tenant is null or v_loc is null then return new; end if;

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
        'description',case when lower(coalesce(new.payment_method,''))='rounding'
          then 'Small balance round-off' else 'Customer receipt' end
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
        select 1 from public.cash_drawer_movements m
        where m.reference_type='sale_payment'
          and m.reference_id=new.id
      )
    limit 1;
  end if;
  return new;
end;
$function$;

create or replace function private.v4_purchase_payment_after_insert()
returns trigger
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_tenant uuid;
  v_loc uuid;
  v_ref text;
  v_supplier uuid;
  v_lines jsonb;
begin
  select p.tenant_id,p.purchase_number,p.supplier_id,o.location_id
  into v_tenant,v_ref,v_supplier,v_loc
  from public.purchases p
  left join public.document_origins o
    on o.entity_type='purchase' and o.entity_id=p.id
  where p.id=new.purchase_id;
  if v_tenant is null or v_loc is null then return new; end if;
  if exists(
    select 1 from public.journal_entries
    where tenant_id=v_tenant
      and source_type='purchase_payment'
      and source_id=new.id
  ) then return new; end if;
  v_lines:=jsonb_build_array(
    jsonb_build_object(
      'account_id',private.v4_account_id(v_tenant,'accounts_payable'),
      'debit',new.amount,'credit',0,
      'party_type','supplier','party_id',v_supplier,
      'description','Payable settlement'
    ),
    jsonb_build_object(
      'account_id',private.v4_payment_account(v_tenant,new.payment_method),
      'debit',0,'credit',new.amount,
      'party_type','supplier','party_id',v_supplier,
      'description','Supplier payment'
    )
  );
  perform private.v4_journal_create(
    v_tenant,v_loc,coalesce(new.paid_at::date,current_date),
    'Supplier payment • '||v_ref,
    'purchase_payment',new.id,v_ref,v_lines
  );
  return new;
end;
$function$;

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
begin
  if v_kind not in ('sale','purchase') then
    raise exception 'Document type must be sale or purchase';
  end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  select o.location_id into v_location
  from public.document_origins o
  where o.tenant_id=p_tenant_id
    and o.entity_type=v_kind
    and o.entity_id=p_document_id
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
    where r.tenant_id=p_tenant_id and r.sale_id=p_document_id
      and r.refund_status<>'waived';
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
    where r.tenant_id=p_tenant_id and r.purchase_id=p_document_id
      and r.credit_status<>'waived';
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
      'Small balance round-off'||
        case when trim(coalesce(p_reason,''))='' then '' else ' • '||trim(p_reason) end,
      now(),auth.uid()
    ) returning id into v_payment;
  else
    insert into public.purchase_payments(
      tenant_id,purchase_id,amount,payment_method,reference_number,notes,paid_at,created_by
    ) values(
      p_tenant_id,p_document_id,v_balance,'rounding',v_reference,
      'Small balance round-off'||
        case when trim(coalesce(p_reason,''))='' then '' else ' • '||trim(p_reason) end,
      now(),auth.uid()
    ) returning id into v_payment;
  end if;

  perform private.business_audit_write_v471(
    p_tenant_id,v_kind||'.balance.rounding',v_kind,p_document_id,v_reference,
    jsonb_build_object('balance_before',v_balance),
    jsonb_build_object(
      'balance_after',0,
      'rounding_amount',v_balance,
      'rounding_account_id',v_rounding_account,
      'reason',nullif(trim(coalesce(p_reason,'')),'')
    )
  );
  perform private.thq_sync_bump_v480(
    p_tenant_id,'finance',v_kind||'_rounding',p_document_id::text,'post'
  );
  return jsonb_build_object(
    'success',true,'document_type',v_kind,'document_id',p_document_id,
    'payment_id',v_payment,'rounding_amount',v_balance,'outstanding_after',0,
    'reference_number',v_reference
  );
end;
$function$;

create or replace function public.document_small_balance_close_v616(
  p_tenant_id uuid,
  p_document_type text,
  p_document_id uuid,
  p_reason text default '',
  p_request_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_existing jsonb;
  v_result jsonb;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then
    raise exception 'Request ID is required';
  end if;
  v_existing:=private.v47_request_existing(
    p_tenant_id,p_request_id,'document.small.rounding.v616'
  );
  if v_existing is not null then return v_existing; end if;
  v_result:=private.document_small_balance_round_v616(
    p_tenant_id,p_document_type,p_document_id,p_reason
  );
  return private.v47_request_complete(
    p_tenant_id,p_request_id,'document.small.rounding.v616',v_result
  );
end;
$function$;

revoke all on function public.document_small_balance_close_v616(uuid,text,uuid,text,text) from public,anon;
grant execute on function public.document_small_balance_close_v616(uuid,text,uuid,text,text) to authenticated;

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
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then
    raise exception 'Request ID is required';
  end if;
  v_existing:=private.v47_request_existing(p_tenant_id,p_request_id,'sale.payment.v616');
  if v_existing is not null then return v_existing; end if;
  v_payment:=public.sales_add_payment_v47(
    p_tenant_id,p_sale_id,p_amount,p_payment_method,
    p_reference_number,p_notes,p_request_id||':payment'
  );
  if coalesce(p_close_small_balance,false) then
    v_rounding:=public.document_small_balance_close_v616(
      p_tenant_id,'sale',p_sale_id,'Close residual during payment',p_request_id||':rounding'
    );
  end if;
  v_result:=coalesce(v_payment,'{}'::jsonb)||jsonb_build_object(
    'close_small_balance',coalesce(p_close_small_balance,false),'rounding',v_rounding
  );
  return private.v47_request_complete(p_tenant_id,p_request_id,'sale.payment.v616',v_result);
end;
$function$;

revoke all on function public.sales_add_payment_v616(uuid,uuid,numeric,text,text,text,boolean,text) from public,anon;
grant execute on function public.sales_add_payment_v616(uuid,uuid,numeric,text,text,text,boolean,text) to authenticated;

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
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then
    raise exception 'Request ID is required';
  end if;
  v_existing:=private.v47_request_existing(p_tenant_id,p_request_id,'purchase.payment.v616');
  if v_existing is not null then return v_existing; end if;
  v_payment:=public.purchases_add_payment_v47(
    p_tenant_id,p_purchase_id,p_amount,p_payment_method,
    p_reference_number,p_notes,p_request_id||':payment'
  );
  if coalesce(p_close_small_balance,false) then
    v_rounding:=public.document_small_balance_close_v616(
      p_tenant_id,'purchase',p_purchase_id,'Close residual during payment',p_request_id||':rounding'
    );
  end if;
  v_result:=coalesce(v_payment,'{}'::jsonb)||jsonb_build_object(
    'close_small_balance',coalesce(p_close_small_balance,false),'rounding',v_rounding
  );
  return private.v47_request_complete(p_tenant_id,p_request_id,'purchase.payment.v616',v_result);
end;
$function$;

revoke all on function public.purchases_add_payment_v616(uuid,uuid,numeric,text,text,text,boolean,text) from public,anon;
grant execute on function public.purchases_add_payment_v616(uuid,uuid,numeric,text,text,text,boolean,text) to authenticated;

update public.platform_app_releases
set release_notes=case
  when app_key='client' and platform='windows' then
    'THQ ERP v6.1.6 Build 9 — Customer Receipt Safety & Small Balance Round-off. Prevents receive-payment amount overwrite, adds auditable receipt voiding, fixes serial-item dialog overflow, and allows explicit sub-1.00 Sales/Purchase residual closure to Rounding / Variance.'
  when app_key='pos' and platform='windows' then
    'THQ ERP v6.1.6 Build 9 — desktop release contract synchronization. Small-balance round-off backend authority is available; no POS transaction-writer change.'
  when app_key='admin' and platform='web' then
    'THQ ERP v6.1.6 Build 9 — desktop release contract synchronization. No Admin transaction-authority change.'
  else release_notes
end
where version='6.1.6' and build_number=9;

insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  301,'6.1.6-build9-final',
  'v6.1.6 Build 9 Small Balance Round-off',
  'Adds explicit invoice-level residual closure below 1.00 for Sales and Purchases using accounting mapping rounding / Rounding & Variance. Payment plus residual closure is atomic through v616 payment wrappers. Expenses continue using the existing expense round_off field. No GST snapshot or authoritative sale/purchase writer semantics changed.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
