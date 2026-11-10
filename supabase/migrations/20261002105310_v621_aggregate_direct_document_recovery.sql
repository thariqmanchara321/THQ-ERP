
create or replace function public.aggregate_direct_document_candidates_v621(
  p_tenant_id uuid,
  p_load_id uuid,
  p_document_type text,
  p_limit integer default 50
)
returns setof jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_type text:=lower(trim(coalesce(p_document_type,'')));
  v_load public.aggregate_loads_v617%rowtype;
  v_map public.aggregate_direct_transit_locations_v621%rowtype;
begin
  perform private.aggregate_direct_assert_manage_v621(p_tenant_id);

  select *
  into v_load
  from public.aggregate_loads_v617
  where id=p_load_id
    and tenant_id=p_tenant_id;

  if v_load.id is null
     or v_load.direction<>'direct_delivery'
     or v_load.status='cancelled' then
    raise exception 'Active Direct Supply load not found';
  end if;

  select *
  into v_map
  from public.aggregate_direct_transit_locations_v621 m
  where m.tenant_id=p_tenant_id
    and m.transit_location_id=v_load.location_id;

  if v_map.transit_location_id is null then
    raise exception 'Controlled transit mapping not found';
  end if;

  perform private.v4_location_access(
    p_tenant_id,v_map.operating_location_id,'operate'
  );

  if v_type='purchase' then
    return query
    with docs as (
      select
        p.id document_id,
        p.purchase_number document_number,
        p.purchase_date document_date,
        sp.name party_name,
        sum(
          case
            when upper(coalesce(pi.entered_unit_code,pi.unit_code,''))
                 =upper(v_load.unit_code)
            then coalesce(pi.entered_quantity,pi.quantity)
            else 0
          end
        )::numeric document_qty,
        p.created_at
      from public.purchases p
      join public.document_origins d
        on d.tenant_id=p.tenant_id
       and d.entity_type='purchase'
       and d.entity_id=p.id
       and d.location_id=v_map.transit_location_id
      join public.purchase_items pi
        on pi.tenant_id=p.tenant_id
       and pi.purchase_id=p.id
       and pi.variant_id=v_load.variant_id
      join public.suppliers sp
        on sp.id=p.supplier_id
       and sp.tenant_id=p.tenant_id
      where p.tenant_id=p_tenant_id
        and p.status='posted'
        and p.supplier_id=v_load.supplier_id
      group by p.id,p.purchase_number,p.purchase_date,sp.name,p.created_at
    ),
    allocations as (
      select
        x.purchase_id document_id,
        sum(x.quantity)::numeric allocated_qty
      from public.aggregate_loads_v617 x
      where x.tenant_id=p_tenant_id
        and x.id<>p_load_id
        and x.direction='direct_delivery'
        and x.purchase_id is not null
        and x.variant_id=v_load.variant_id
        and upper(x.unit_code)=upper(v_load.unit_code)
        and x.status<>'cancelled'
      group by x.purchase_id
    )
    select jsonb_build_object(
      'document_type','purchase',
      'document_id',d.document_id,
      'document_number',d.document_number,
      'document_date',d.document_date,
      'party_name',d.party_name,
      'document_quantity',d.document_qty,
      'allocated_quantity',coalesce(a.allocated_qty,0),
      'remaining_quantity',
        greatest(d.document_qty-coalesce(a.allocated_qty,0),0),
      'unit_code',v_load.unit_code,
      'already_linked',v_load.purchase_id=d.document_id,
      'created_at',d.created_at
    )
    from docs d
    left join allocations a on a.document_id=d.document_id
    where d.document_qty>0
      and (
        v_load.purchase_id=d.document_id
        or d.document_qty-coalesce(a.allocated_qty,0)
           >=v_load.quantity-0.0001
      )
    order by
      (v_load.purchase_id=d.document_id) desc,
      d.created_at desc
    limit greatest(1,least(coalesce(p_limit,50),200));

  elsif v_type='sale' then
    if v_load.purchase_id is null then
      raise exception 'Link the Direct Supply Purchase first';
    end if;

    return query
    with docs as (
      select
        s.id document_id,
        s.sale_number document_number,
        s.sale_date document_date,
        c.name party_name,
        sum(
          case
            when upper(coalesce(si.entered_unit_code,si.unit_code,''))
                 =upper(v_load.unit_code)
            then coalesce(si.entered_quantity,si.quantity)
            else 0
          end
        )::numeric document_qty,
        s.created_at
      from public.sales s
      join public.document_origins d
        on d.tenant_id=s.tenant_id
       and d.entity_type='sale'
       and d.entity_id=s.id
       and d.location_id=v_map.transit_location_id
      join public.sale_items si
        on si.tenant_id=s.tenant_id
       and si.sale_id=s.id
       and si.variant_id=v_load.variant_id
      join public.customers c
        on c.id=s.customer_id
       and c.tenant_id=s.tenant_id
      where s.tenant_id=p_tenant_id
        and s.status='posted'
        and s.customer_id=v_load.customer_id
      group by s.id,s.sale_number,s.sale_date,c.name,s.created_at
    ),
    allocations as (
      select
        x.sale_id document_id,
        sum(x.quantity)::numeric allocated_qty
      from public.aggregate_loads_v617 x
      where x.tenant_id=p_tenant_id
        and x.id<>p_load_id
        and x.direction='direct_delivery'
        and x.sale_id is not null
        and x.variant_id=v_load.variant_id
        and upper(x.unit_code)=upper(v_load.unit_code)
        and x.status<>'cancelled'
      group by x.sale_id
    )
    select jsonb_build_object(
      'document_type','sale',
      'document_id',d.document_id,
      'document_number',d.document_number,
      'document_date',d.document_date,
      'party_name',d.party_name,
      'document_quantity',d.document_qty,
      'allocated_quantity',coalesce(a.allocated_qty,0),
      'remaining_quantity',
        greatest(d.document_qty-coalesce(a.allocated_qty,0),0),
      'unit_code',v_load.unit_code,
      'already_linked',v_load.sale_id=d.document_id,
      'created_at',d.created_at
    )
    from docs d
    left join allocations a on a.document_id=d.document_id
    where d.document_qty>0
      and (
        v_load.sale_id=d.document_id
        or d.document_qty-coalesce(a.allocated_qty,0)
           >=v_load.quantity-0.0001
      )
    order by
      (v_load.sale_id=d.document_id) desc,
      d.created_at desc
    limit greatest(1,least(coalesce(p_limit,50),200));

  else
    raise exception 'Document type must be purchase or sale';
  end if;
end
$$;

revoke all
on function public.aggregate_direct_document_candidates_v621(
  uuid,uuid,text,integer
)
from public,anon;

grant execute
on function public.aggregate_direct_document_candidates_v621(
  uuid,uuid,text,integer
)
to authenticated,service_role;

insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  315,
  '6.2.1-aggregate-direct-recovery',
  'Aggregate Direct Supply Document Recovery',
  'Adds a permission- and location-scoped candidate lookup for already-posted Direct Supply Purchases/Sales so interrupted client linking can recover safely without reposting financial documents.'
);;
