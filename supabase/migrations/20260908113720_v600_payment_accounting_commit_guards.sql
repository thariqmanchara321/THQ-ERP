-- THQ ERP v6.0
-- Deferred payment accounting ownership guards and integrity report.

create or replace function private.payment_accounting_commit_guard_v600()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_tenant uuid;
  v_parent uuid;
  v_origin_created timestamptz;
  v_source_journal boolean:=false;
  v_standalone_count integer:=0;
  v_embedded boolean:=false;
  v_receipt boolean:=false;
begin
  if tg_table_name='sale_payments' then
    v_tenant:=new.tenant_id;
    v_parent:=new.sale_id;

    select o.created_at into v_origin_created
    from public.document_origins o
    where o.tenant_id=v_tenant
      and o.entity_type='sale'
      and o.entity_id=v_parent
    order by o.created_at
    limit 1;

    select exists(
      select 1
      from public.journal_entries j
      where j.tenant_id=v_tenant
        and j.source_type='sale'
        and j.source_id=v_parent
        and j.status='posted'
    ) into v_source_journal;

    select count(*) into v_standalone_count
    from public.journal_entries j
    where j.tenant_id=v_tenant
      and j.source_type='sale_payment'
      and j.source_id=new.id
      and j.status='posted';

    if v_standalone_count>1 then
      raise exception
        'Accounting integrity failure: Sale payment % has multiple posted payment journals',
        new.id;
    end if;
    if v_standalone_count=1 then return new; end if;

    v_embedded:=
      v_source_journal
      and v_origin_created is not null
      and new.created_at<=v_origin_created;

    if not v_embedded then
      v_embedded:=v_source_journal and exists(
        select 1
        from public.sale_payment_allocations_v522 a
        join public.gst_document_snapshots_v520 s
          on s.tenant_id=a.tenant_id
         and s.source_type='sale'
         and s.source_id=a.sale_id
        where a.tenant_id=v_tenant
          and a.sale_id=v_parent
          and a.sale_payment_id=new.id
          and a.settlement_amount>0
      );
    end if;

    select exists(
      select 1
      from public.customer_receipt_allocations a
      join public.customer_receipts r
        on r.id=a.receipt_id
       and r.tenant_id=a.tenant_id
      join public.journal_entries j
        on j.tenant_id=a.tenant_id
       and j.source_type='customer_receipt'
       and j.source_id=r.id
       and j.status='posted'
      where a.tenant_id=v_tenant
        and a.payment_id=new.id
    ) into v_receipt;

    if not coalesce(v_embedded,false)
       and not coalesce(v_receipt,false) then
      raise exception
        'Accounting integrity failure: Sale payment % has no valid accounting owner',
        new.id;
    end if;

    return new;
  end if;

  if tg_table_name='purchase_payments' then
    v_tenant:=new.tenant_id;
    v_parent:=new.purchase_id;

    select o.created_at into v_origin_created
    from public.document_origins o
    where o.tenant_id=v_tenant
      and o.entity_type='purchase'
      and o.entity_id=v_parent
    order by o.created_at
    limit 1;

    select exists(
      select 1
      from public.journal_entries j
      where j.tenant_id=v_tenant
        and j.source_type='purchase'
        and j.source_id=v_parent
        and j.status='posted'
    ) into v_source_journal;

    select count(*) into v_standalone_count
    from public.journal_entries j
    where j.tenant_id=v_tenant
      and j.source_type='purchase_payment'
      and j.source_id=new.id
      and j.status='posted';

    if v_standalone_count>1 then
      raise exception
        'Accounting integrity failure: Purchase payment % has multiple posted payment journals',
        new.id;
    end if;
    if v_standalone_count=1 then return new; end if;

    v_embedded:=
      v_source_journal
      and v_origin_created is not null
      and new.created_at<=v_origin_created;

    if not coalesce(v_embedded,false) then
      raise exception
        'Accounting integrity failure: Purchase payment % has no valid accounting owner',
        new.id;
    end if;

    return new;
  end if;

  return new;
end
$function$;

drop trigger if exists trg_accounting_guard_sale_payments_v600
on public.sale_payments;
create constraint trigger trg_accounting_guard_sale_payments_v600
after insert or update on public.sale_payments
deferrable initially deferred
for each row
execute function private.payment_accounting_commit_guard_v600();

drop trigger if exists trg_accounting_guard_purchase_payments_v600
on public.purchase_payments;
create constraint trigger trg_accounting_guard_purchase_payments_v600
after insert or update on public.purchase_payments
deferrable initially deferred
for each row
execute function private.payment_accounting_commit_guard_v600();

create or replace function public.payment_accounting_integrity_report_v600(
  p_tenant_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_sale_missing integer:=0;
  v_purchase_missing integer:=0;
  v_duplicate integer:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if not (
    private.erp_has_permission(p_tenant_id,'accounting.view')
    or private.erp_has_permission(p_tenant_id,'accounting.manage')
    or private.erp_has_permission(p_tenant_id,'accounting.journal')
  ) then
    raise exception 'Accounting permission required';
  end if;

  select count(*) into v_sale_missing
  from public.sale_payments sp
  join public.sales s
    on s.id=sp.sale_id
   and s.tenant_id=sp.tenant_id
  left join lateral (
    select o.created_at
    from public.document_origins o
    where o.tenant_id=sp.tenant_id
      and o.entity_type='sale'
      and o.entity_id=sp.sale_id
    order by o.created_at
    limit 1
  ) o on true
  where sp.tenant_id=p_tenant_id
    and not exists(
      select 1 from public.journal_entries j
      where j.tenant_id=sp.tenant_id
        and j.source_type='sale_payment'
        and j.source_id=sp.id
        and j.status='posted'
    )
    and not (
      o.created_at is not null
      and sp.created_at<=o.created_at
      and exists(
        select 1 from public.journal_entries j
        where j.tenant_id=sp.tenant_id
          and j.source_type='sale'
          and j.source_id=sp.sale_id
          and j.status='posted'
      )
    )
    and not exists(
      select 1
      from public.sale_payment_allocations_v522 a
      join public.gst_document_snapshots_v520 gs
        on gs.tenant_id=a.tenant_id
       and gs.source_type='sale'
       and gs.source_id=a.sale_id
      join public.journal_entries j
        on j.tenant_id=a.tenant_id
       and j.source_type='sale'
       and j.source_id=a.sale_id
       and j.status='posted'
      where a.tenant_id=sp.tenant_id
        and a.sale_id=sp.sale_id
        and a.sale_payment_id=sp.id
        and a.settlement_amount>0
    )
    and not exists(
      select 1
      from public.customer_receipt_allocations a
      join public.customer_receipts r
        on r.id=a.receipt_id
       and r.tenant_id=a.tenant_id
      join public.journal_entries j
        on j.tenant_id=a.tenant_id
       and j.source_type='customer_receipt'
       and j.source_id=r.id
       and j.status='posted'
      where a.tenant_id=sp.tenant_id
        and a.payment_id=sp.id
    );

  select count(*) into v_purchase_missing
  from public.purchase_payments pp
  left join lateral (
    select o.created_at
    from public.document_origins o
    where o.tenant_id=pp.tenant_id
      and o.entity_type='purchase'
      and o.entity_id=pp.purchase_id
    order by o.created_at
    limit 1
  ) o on true
  where pp.tenant_id=p_tenant_id
    and not exists(
      select 1 from public.journal_entries j
      where j.tenant_id=pp.tenant_id
        and j.source_type='purchase_payment'
        and j.source_id=pp.id
        and j.status='posted'
    )
    and not (
      o.created_at is not null
      and pp.created_at<=o.created_at
      and exists(
        select 1 from public.journal_entries j
        where j.tenant_id=pp.tenant_id
          and j.source_type='purchase'
          and j.source_id=pp.purchase_id
          and j.status='posted'
      )
    );

  select count(*) into v_duplicate
  from (
    select tenant_id,source_type,source_id
    from public.journal_entries
    where tenant_id=p_tenant_id
      and status='posted'
      and source_type in ('sale_payment','purchase_payment','customer_receipt')
      and source_id is not null
    group by tenant_id,source_type,source_id
    having count(*)>1
  ) q;

  return jsonb_build_object(
    'tenant_id',p_tenant_id,
    'healthy',(v_sale_missing+v_purchase_missing+v_duplicate)=0,
    'sale_payments_without_accounting_owner',v_sale_missing,
    'purchase_payments_without_accounting_owner',v_purchase_missing,
    'duplicate_posted_payment_sources',v_duplicate
  );
end
$function$;

revoke execute on function private.payment_accounting_commit_guard_v600()
from public, anon, authenticated, service_role;

revoke execute on function public.payment_accounting_integrity_report_v600(uuid)
from public, anon;

grant execute on function public.payment_accounting_integrity_report_v600(uuid)
to authenticated, service_role;
