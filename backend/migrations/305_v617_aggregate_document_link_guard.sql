-- THQ ERP — Aggregate Document Link Guard
-- Schema release 305.
--
-- This migration does not write a Sale, Purchase, stock movement, GST snapshot
-- or journal. It only hardens the relation between an already-posted THQ
-- document and an operational Aggregate Load Ticket.

begin;

create or replace function public.aggregate_load_link_document_v617(
  p_tenant_id uuid,
  p_load_id uuid,
  p_document_type text,
  p_document_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_type text:=lower(trim(coalesce(p_document_type,'')));
  v_ref text;
  v_load public.aggregate_loads_v617%rowtype;
  v_document_qty numeric:=0;
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  select *
  into v_load
  from public.aggregate_loads_v617
  where id=p_load_id
    and tenant_id=p_tenant_id
  for update;

  if v_load.id is null then
    raise exception 'Load not found';
  end if;

  if v_load.status='cancelled' then
    raise exception 'Cancelled load cannot be linked to a transaction';
  end if;

  if v_type='purchase' then
    if v_load.direction not in('inbound','direct_delivery') then
      raise exception
        'Only inbound or direct-delivery loads may link a Purchase';
    end if;

    if v_load.purchase_id is not null
       and v_load.purchase_id<>p_document_id then
      raise exception 'Load is already linked to another Purchase';
    end if;

    select
      p.purchase_number,
      coalesce(
        sum(
          case
            when upper(
              coalesce(pi.entered_unit_code,pi.unit_code,'')
            )=upper(v_load.unit_code)
            then coalesce(pi.entered_quantity,pi.quantity)
            else 0
          end
        ),
        0
      )
    into v_ref,v_document_qty
    from public.purchases p
    join public.purchase_items pi
      on pi.purchase_id=p.id
     and pi.tenant_id=p.tenant_id
     and pi.variant_id=v_load.variant_id
    where p.id=p_document_id
      and p.tenant_id=p_tenant_id
    group by p.purchase_number;

    if v_ref is null then
      raise exception
        'Purchase not found or does not contain the load material';
    end if;

    if v_document_qty+0.0001<v_load.quantity then
      raise exception
        'Purchase quantity for this material/unit (%) is lower than load quantity (%)',
        v_document_qty,
        v_load.quantity;
    end if;

    update public.aggregate_loads_v617
    set purchase_id=p_document_id,
        updated_by=auth.uid(),
        updated_at=now()
    where id=p_load_id
      and tenant_id=p_tenant_id;

  elsif v_type='sale' then
    if v_load.direction not in('outbound','direct_delivery') then
      raise exception
        'Only outbound or direct-delivery loads may link a Sale';
    end if;

    if v_load.sale_id is not null
       and v_load.sale_id<>p_document_id then
      raise exception 'Load is already linked to another Sale';
    end if;

    select
      s.sale_number,
      coalesce(
        sum(
          case
            when upper(
              coalesce(si.entered_unit_code,si.unit_code,'')
            )=upper(v_load.unit_code)
            then coalesce(si.entered_quantity,si.quantity)
            else 0
          end
        ),
        0
      )
    into v_ref,v_document_qty
    from public.sales s
    join public.sale_items si
      on si.sale_id=s.id
     and si.tenant_id=s.tenant_id
     and si.variant_id=v_load.variant_id
    where s.id=p_document_id
      and s.tenant_id=p_tenant_id
    group by s.sale_number;

    if v_ref is null then
      raise exception
        'Sale not found or does not contain the load material';
    end if;

    if v_document_qty+0.0001<v_load.quantity then
      raise exception
        'Sale quantity for this material/unit (%) is lower than load quantity (%)',
        v_document_qty,
        v_load.quantity;
    end if;

    update public.aggregate_loads_v617
    set sale_id=p_document_id,
        updated_by=auth.uid(),
        updated_at=now()
    where id=p_load_id
      and tenant_id=p_tenant_id;

  else
    raise exception 'Document type must be purchase or sale';
  end if;

  if not exists(
    select 1
    from public.aggregate_load_events_v617 e
    where e.tenant_id=p_tenant_id
      and e.load_id=p_load_id
      and e.event_type='document_linked'
      and e.metadata->>'document_type'=v_type
      and e.metadata->>'document_id'=p_document_id::text
  ) then
    insert into public.aggregate_load_events_v617(
      tenant_id,
      load_id,
      event_type,
      note,
      metadata,
      created_by
    )
    values(
      p_tenant_id,
      p_load_id,
      'document_linked',
      initcap(v_type)||' '||v_ref||' linked',
      jsonb_build_object(
        'document_type',v_type,
        'document_id',p_document_id,
        'reference',v_ref,
        'validated_quantity',v_document_qty,
        'load_quantity',v_load.quantity,
        'unit_code',v_load.unit_code
      ),
      auth.uid()
    );
  end if;

  return jsonb_build_object(
    'load_id',p_load_id,
    'load_number',v_load.load_number,
    'document_type',v_type,
    'document_id',p_document_id,
    'reference',v_ref,
    'validated_quantity',v_document_qty,
    'load_quantity',v_load.quantity,
    'unit_code',v_load.unit_code
  );
end
$$;

revoke all
on function public.aggregate_load_link_document_v617(uuid,uuid,text,uuid)
from public,anon;

grant execute
on function public.aggregate_load_link_document_v617(uuid,uuid,text,uuid)
to authenticated,service_role;

insert into public.thq_schema_releases(
  migration_no,
  schema_version,
  release_name,
  notes
)
values(
  305,
  '6.1.7-aggregate-document-link-guard',
  'Aggregate Document Link Guard',
  'Hardens operational Load Ticket links so inbound loads only link matching Purchases, outbound loads only link matching Sales, direct-delivery loads may link both, material/unit quantities are validated, cancelled loads are blocked, and link events are idempotent. No Sales/Purchase/GST/stock writer changes.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
