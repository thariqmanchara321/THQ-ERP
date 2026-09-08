-- THQ ERP v6.0
-- Prevent duplicate GL posting for v5.2.2 invoice-time sale allocations.

create or replace function private.v4_sale_payment_after_insert()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
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

  if not v_authoritative
     and not exists(
       select 1 from public.journal_entries
       where tenant_id=v_tenant and source_type='sale_payment'
         and source_id=new.id and status='posted'
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

  if lower(coalesce(new.payment_method,''))='cash' then
    insert into public.cash_drawer_movements(
      tenant_id,shift_id,movement_type,amount,reference_type,reference_id,
      reference_number,note,created_by
    )
    select v_tenant,sh.id,'sale',new.amount,'sale_payment',new.id,v_ref,
           'Customer cash receipt',auth.uid()
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
