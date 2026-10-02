begin;

alter table public.customer_receipts
  add column if not exists status text not null default 'posted',
  add column if not exists voided_at timestamptz,
  add column if not exists voided_by uuid references auth.users(id) on delete set null,
  add column if not exists void_reason text,
  add column if not exists reversal_journal_id uuid references public.journal_entries(id) on delete set null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.customer_receipts'::regclass
      and conname='customer_receipts_status_check'
  ) then
    alter table public.customer_receipts
      add constraint customer_receipts_status_check
      check (status in ('posted','void'));
  end if;
end $$;

create or replace function public.customer_receipt_void_v616(
  p_tenant_id uuid,
  p_receipt_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_receipt public.customer_receipts%rowtype;
  v_original_journal uuid;
  v_reversal_journal uuid;
  v_lines jsonb := '[]'::jsonb;
  v_payment_ids uuid[];
  v_outstanding numeric := 0;
  x record;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'payments.receive')
     and not private.erp_has_permission(p_tenant_id,'sales.manage') then
    raise exception 'Receive payment permission required';
  end if;

  if trim(coalesce(p_reason,'')) = '' then
    raise exception 'Void reason is required';
  end if;

  select *
  into v_receipt
  from public.customer_receipts
  where id=p_receipt_id
    and tenant_id=p_tenant_id
  for update;

  if not found then
    raise exception 'Customer receipt not found';
  end if;

  if v_receipt.status='void' then
    select coalesce(sum(greatest(
      s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0
    )),0)
    into v_outstanding
    from public.sales s
    left join (
      select sale_id,sum(amount) paid
      from public.sale_payments
      group by sale_id
    ) py on py.sale_id=s.id
    left join (
      select sale_id,sum(grand_total) returned
      from public.sales_returns
      where refund_status<>'waived'
      group by sale_id
    ) rt on rt.sale_id=s.id
    where s.tenant_id=p_tenant_id
      and s.customer_id=v_receipt.customer_id
      and coalesce(s.status,'') not in('void','cancelled');

    return jsonb_build_object(
      'success',true,
      'already_voided',true,
      'receipt_id',v_receipt.id,
      'receipt_number',v_receipt.receipt_number,
      'outstanding_after',v_outstanding,
      'reversal_journal_id',v_receipt.reversal_journal_id
    );
  end if;

  select j.id
  into v_original_journal
  from public.journal_entries j
  where j.tenant_id=p_tenant_id
    and j.source_type='customer_receipt'
    and j.source_id=v_receipt.id
    and j.status='posted'
  order by j.created_at
  limit 1
  for update;

  if v_original_journal is null then
    raise exception 'Posted customer receipt journal not found';
  end if;

  select array_agg(a.payment_id)
  into v_payment_ids
  from public.customer_receipt_allocations a
  where a.tenant_id=p_tenant_id
    and a.receipt_id=v_receipt.id
    and a.payment_id is not null;

  if v_payment_ids is not null and exists (
    select 1
    from public.journal_entries j
    where j.tenant_id=p_tenant_id
      and j.source_type='sale_payment'
      and j.source_id=any(v_payment_ids)
      and j.status='posted'
  ) then
    raise exception 'Receipt has independently posted sale-payment journals and cannot be voided automatically';
  end if;

  for x in
    select *
    from public.journal_lines
    where journal_entry_id=v_original_journal
    order by id
  loop
    v_lines := v_lines || jsonb_build_array(
      jsonb_build_object(
        'account_id',x.account_id,
        'debit',x.credit,
        'credit',x.debit,
        'party_type',x.party_type,
        'party_id',x.party_id,
        'description','Void '||v_receipt.receipt_number||' • '||coalesce(x.description,'Customer receipt')
      )
    );
  end loop;

  v_reversal_journal := private.v4_journal_create(
    p_tenant_id,
    v_receipt.location_id,
    current_date,
    'Void customer receipt • '||v_receipt.receipt_number||' • '||trim(p_reason),
    'customer_receipt_void',
    v_receipt.id,
    v_receipt.receipt_number,
    v_lines
  );

  update public.journal_entries
  set reversal_of=v_original_journal
  where id=v_reversal_journal;

  insert into public.cash_drawer_movements(
    tenant_id,shift_id,movement_type,amount,
    reference_type,reference_id,reference_number,note,created_by
  )
  select
    m.tenant_id,m.shift_id,'cash_out',m.amount,
    'customer_receipt_void',v_receipt.id,v_receipt.receipt_number,
    'Void customer receipt • '||trim(p_reason),auth.uid()
  from public.cash_drawer_movements m
  where m.tenant_id=p_tenant_id
    and m.reference_type='customer_receipt'
    and m.reference_id=v_receipt.id
    and not exists (
      select 1
      from public.cash_drawer_movements rv
      where rv.tenant_id=m.tenant_id
        and rv.shift_id=m.shift_id
        and rv.reference_type='customer_receipt_void'
        and rv.reference_id=v_receipt.id
    );

  update public.customer_receipt_allocations
  set payment_id=null
  where tenant_id=p_tenant_id
    and receipt_id=v_receipt.id;

  if v_payment_ids is not null then
    delete from public.sale_payments
    where tenant_id=p_tenant_id
      and id=any(v_payment_ids);
  end if;

  update public.customer_receipts
  set status='void',
      voided_at=now(),
      voided_by=auth.uid(),
      void_reason=trim(p_reason),
      reversal_journal_id=v_reversal_journal
  where id=v_receipt.id
    and tenant_id=p_tenant_id;

  perform private.business_audit_write_v471(
    p_tenant_id,
    'customer.payment.void',
    'customer',
    v_receipt.customer_id,
    v_receipt.receipt_number,
    jsonb_build_object(
      'receipt_id',v_receipt.id,
      'amount',v_receipt.amount,
      'status','posted'
    ),
    jsonb_build_object(
      'receipt_id',v_receipt.id,
      'amount',v_receipt.amount,
      'status','void',
      'reason',trim(p_reason),
      'reversal_journal_id',v_reversal_journal
    )
  );

  select coalesce(sum(greatest(
    s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0
  )),0)
  into v_outstanding
  from public.sales s
  left join (
    select sale_id,sum(amount) paid
    from public.sale_payments
    group by sale_id
  ) py on py.sale_id=s.id
  left join (
    select sale_id,sum(grand_total) returned
    from public.sales_returns
    where refund_status<>'waived'
    group by sale_id
  ) rt on rt.sale_id=s.id
  where s.tenant_id=p_tenant_id
    and s.customer_id=v_receipt.customer_id
    and coalesce(s.status,'') not in('void','cancelled');

  return jsonb_build_object(
    'success',true,
    'already_voided',false,
    'receipt_id',v_receipt.id,
    'receipt_number',v_receipt.receipt_number,
    'voided_amount',v_receipt.amount,
    'outstanding_after',v_outstanding,
    'reversal_journal_id',v_reversal_journal
  );
end;
$function$;

revoke all on function public.customer_receipt_void_v616(uuid,uuid,text) from public,anon;
grant execute on function public.customer_receipt_void_v616(uuid,uuid,text) to authenticated;

create or replace function public.customer_account_v471(
  p_tenant_id uuid,
  p_customer_id uuid
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_customer jsonb;
  v_invoices jsonb;
  v_receipts jsonb;
  v_outstanding numeric:=0;
  v_platform boolean:=private.platform_v2_is_admin();
begin
  if not v_platform and not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  if not v_platform
     and not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'customers.view')
     and not private.erp_has_permission(p_tenant_id,'customers.manage')
     and not private.erp_has_permission(p_tenant_id,'sales.view')
     and not private.erp_has_permission(p_tenant_id,'sales.manage')
     and not private.erp_has_permission(p_tenant_id,'payments.receive') then
    raise exception 'Customer account permission required';
  end if;

  select to_jsonb(c)
  into v_customer
  from public.customers c
  where c.id=p_customer_id and c.tenant_id=p_tenant_id;

  if v_customer is null then raise exception 'Customer not found'; end if;

  select
    coalesce(sum(greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)),0),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'sale_id',s.id,
          'sale_number',s.sale_number,
          'sale_date',s.sale_date,
          'due_date',s.due_date,
          'grand_total',s.grand_total,
          'paid',coalesce(py.paid,0),
          'returned',coalesce(rt.returned,0),
          'balance',greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0),
          'location_id',o.location_id,
          'location_name',l.name
        )
        order by coalesce(s.due_date,s.sale_date),s.created_at
      ) filter(
        where greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)>0.005
      ),
      '[]'::jsonb
    )
  into v_outstanding,v_invoices
  from public.sales s
  left join (
    select sale_id,sum(amount) paid
    from public.sale_payments
    group by sale_id
  ) py on py.sale_id=s.id
  left join (
    select sale_id,sum(grand_total) returned
    from public.sales_returns
    where refund_status<>'waived'
    group by sale_id
  ) rt on rt.sale_id=s.id
  left join public.document_origins o
    on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
  left join public.business_locations l on l.id=o.location_id
  where s.tenant_id=p_tenant_id
    and s.customer_id=p_customer_id
    and coalesce(s.status,'') not in('void','cancelled')
    and (v_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view'));

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'receipt_id',r.id,
        'receipt_number',r.receipt_number,
        'receipt_date',r.receipt_date,
        'amount',r.amount,
        'payment_method',r.payment_method,
        'reference_number',r.reference_number,
        'notes',r.notes,
        'status',r.status,
        'voided_at',r.voided_at,
        'void_reason',r.void_reason,
        'reversal_journal_id',r.reversal_journal_id,
        'location_id',r.location_id,
        'location_name',l.name,
        'device_id',r.device_id,
        'device_name',d.name,
        'created_at',r.created_at,
        'allocations',coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'sale_id',a.sale_id,
              'sale_number',s.sale_number,
              'amount',a.amount
            )
          )
          from public.customer_receipt_allocations a
          join public.sales s on s.id=a.sale_id
          where a.receipt_id=r.id
        ),'[]'::jsonb)
      )
      order by r.created_at desc
    ),
    '[]'::jsonb
  )
  into v_receipts
  from public.customer_receipts r
  left join public.business_locations l on l.id=r.location_id
  left join public.business_devices d on d.id=r.device_id
  where r.tenant_id=p_tenant_id
    and r.customer_id=p_customer_id
    and (v_platform or private.erp_document_scope_allowed(p_tenant_id,r.location_id,null,'view'));

  return jsonb_build_object(
    'customer',v_customer,
    'outstanding',v_outstanding,
    'open_invoices',coalesce(v_invoices,'[]'::jsonb),
    'receipts',coalesce(v_receipts,'[]'::jsonb)
  );
end;
$function$;

insert into public.platform_app_releases(
  id,app_key,platform,version,build_number,status,minimum_supported,mandatory,
  release_notes,download_url,released_at
)
values
(
  gen_random_uuid(),'client','windows','6.1.6',9,'stable',false,false,
  'THQ ERP v6.1.6 Build 9 — Customer Receipt Safety & Small Balance Round-off. Prevents receive-payment amount overwrite, adds auditable receipt voiding, fixes serial-item dialog overflow, and allows explicit sub-1.00 Sales/Purchase residual closure to Rounding / Variance.',
  null,now()
),
(
  gen_random_uuid(),'pos','windows','6.1.6',9,'stable',false,false,
  'THQ ERP v6.1.6 Build 9 — desktop release contract synchronization. Small-balance round-off backend authority is available; no POS transaction-writer change.',
  null,now()
),
(
  gen_random_uuid(),'admin','web','6.1.6',9,'stable',false,false,
  'THQ ERP v6.1.6 Build 9 — desktop release contract synchronization. No Admin transaction-authority change.',
  null,now()
)
on conflict(app_key,platform,version) do update
set build_number=excluded.build_number,
    status=excluded.status,
    minimum_supported=excluded.minimum_supported,
    mandatory=excluded.mandatory,
    release_notes=excluded.release_notes;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  300,'6.1.6-build9',
  'v6.1.6 Build 9 Customer Receipt Safety',
  'Adds auditable customer receipt voiding and receipt status metadata. Client UI prevents silent receive-payment amount replacement and fixes serial sale-item dialog overflow. Authoritative GST sale writers remain unchanged.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
