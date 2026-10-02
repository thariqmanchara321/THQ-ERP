-- THQ ERP — Aggregate Prefill & Direct Delivery Safety
-- Schema release 306.
--
-- Adds a richer load-list API for safe Purchase/Sale prefilling and blocks
-- direct-delivery commercial linking until a transit-stock authority exists.

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

  if v_load.direction='direct_delivery' then
    raise exception
      'Direct-delivery commercial posting is disabled until the transit-stock workflow is installed';
  end if;

  if v_type='purchase' then
    if v_load.direction<>'inbound' then
      raise exception 'Only inbound loads may link a Purchase';
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
    if v_load.direction<>'outbound' then
      raise exception 'Only outbound loads may link a Sale';
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

create or replace function public.aggregate_load_list_v618(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_status text default null,
  p_query text default null,
  p_limit integer default 300
)
returns table(
  load_id uuid,
  load_number text,
  load_date date,
  direction text,
  status text,
  location_id uuid,
  variant_id uuid,
  supplier_id uuid,
  customer_id uuid,
  product_name text,
  quantity numeric,
  unit_code text,
  measurement_method text,
  vehicle_id uuid,
  vehicle_registration text,
  driver_name text,
  supplier_name text,
  customer_name text,
  source_name text,
  destination_name text,
  source_reference text,
  freight_mode text,
  freight_amount numeric,
  purchase_id uuid,
  sale_id uuid,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  return query
  select
    l.id,
    l.load_number,
    l.load_date,
    l.direction,
    l.status,
    l.location_id,
    l.variant_id,
    l.supplier_id,
    l.customer_id,
    l.product_name_snapshot,
    l.quantity,
    l.unit_code,
    l.measurement_method,
    l.vehicle_id,
    l.vehicle_registration_snapshot,
    l.driver_name_snapshot,
    s.name,
    c.name,
    l.source_name,
    l.destination_name,
    l.source_reference,
    l.freight_mode,
    l.freight_amount,
    l.purchase_id,
    l.sale_id,
    l.created_at
  from public.aggregate_loads_v617 l
  left join public.suppliers s
    on s.id=l.supplier_id
   and s.tenant_id=l.tenant_id
  left join public.customers c
    on c.id=l.customer_id
   and c.tenant_id=l.tenant_id
  where l.tenant_id=p_tenant_id
    and (p_location_id is null or l.location_id=p_location_id)
    and (
      p_status is null
      or trim(p_status)=''
      or l.status=lower(trim(p_status))
    )
    and (
      p_query is null
      or trim(p_query)=''
      or l.load_number ilike '%'||trim(p_query)||'%'
      or l.product_name_snapshot ilike '%'||trim(p_query)||'%'
      or coalesce(l.vehicle_registration_snapshot,'')
           ilike '%'||trim(p_query)||'%'
      or coalesce(l.driver_name_snapshot,'')
           ilike '%'||trim(p_query)||'%'
      or coalesce(s.name,'')
           ilike '%'||trim(p_query)||'%'
      or coalesce(c.name,'')
           ilike '%'||trim(p_query)||'%'
    )
  order by l.created_at desc
  limit greatest(1,least(coalesce(p_limit,300),1000));
end
$$;

revoke all
on function public.aggregate_load_list_v618(uuid,uuid,text,text,integer)
from public,anon;

grant execute
on function public.aggregate_load_list_v618(uuid,uuid,text,text,integer)
to authenticated,service_role;

insert into public.thq_schema_releases(
  migration_no,
  schema_version,
  release_name,
  notes
)
values(
  306,
  '6.1.7-aggregate-prefill-safety',
  'Aggregate Prefill & Direct Delivery Safety',
  'Adds a load-list API with authoritative variant/supplier/customer IDs for transaction prefill and blocks direct-delivery commercial linking until a transit-stock authority is installed. Existing Sales/Purchase/GST/stock writers are unchanged.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
