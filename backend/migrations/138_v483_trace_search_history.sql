-- THQ ERP V4.8.3 — serial search, batch history, warranty register and lookup APIs.
begin;

create or replace function private.v483_trace_view_allowed(p_tenant_id uuid) returns boolean
language sql stable security definer set search_path=public,private,pg_temp as $$
 select private.erp_user_is_owner(p_tenant_id)
     or private.erp_has_permission(p_tenant_id,'inventory.view')
     or private.erp_has_permission(p_tenant_id,'inventory.manage')
     or private.erp_has_permission(p_tenant_id,'sales.view')
     or private.erp_has_permission(p_tenant_id,'sales.manage')
     or private.erp_has_permission(p_tenant_id,'purchases.view')
     or private.erp_has_permission(p_tenant_id,'purchases.manage')
$$;
revoke all on function private.v483_trace_view_allowed(uuid) from public;

create or replace function public.inventory_serial_search_v483(
 p_tenant_id uuid,p_query text default '',p_location_id uuid default null,p_limit integer default 200
) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
 if not private.erp_user_has_tenant_access(p_tenant_id) or not private.v483_trace_view_allowed(p_tenant_id) then raise exception 'Traceability view permission required';end if;
 return query
 select jsonb_build_object(
  'serial_id',s.id,'serial_number',s.serial_number,'status',s.status,'variant_id',s.variant_id,
  'product_name',p.name,'variant_name',pv.variant_name,'sku',pv.sku,
  'location_id',coalesce(s.current_location_id,so.location_id,po.location_id),
  'location_name',coalesce(l.name,sl.name,pl.name),
  'supplier_id',s.supplier_id,'supplier_name',sup.name,'purchase_id',s.purchase_id,'purchase_number',pur.purchase_number,
  'customer_id',s.customer_id,'customer_name',c.name,'sale_id',s.sale_id,'sale_number',sa.sale_number,
  'received_at',s.received_at,'sold_at',s.sold_at,
  'warranty_start',w.warranty_start,'warranty_expiry',w.warranty_expiry,
  'warranty_status',case when w.status='active' and w.warranty_expiry<current_date then 'expired' else w.status end
 )
 from public.inventory_serials_v483 s
 join public.product_variants pv on pv.id=s.variant_id and pv.tenant_id=s.tenant_id
 join public.products p on p.id=pv.product_id
 left join public.business_locations l on l.id=s.current_location_id
 left join public.suppliers sup on sup.id=s.supplier_id
 left join public.purchases pur on pur.id=s.purchase_id
 left join public.customers c on c.id=s.customer_id
 left join public.sales sa on sa.id=s.sale_id
 left join public.document_origins so on so.tenant_id=s.tenant_id and so.entity_type='sale' and so.entity_id=s.sale_id
 left join public.document_origins po on po.tenant_id=s.tenant_id and po.entity_type='purchase' and po.entity_id=s.purchase_id
 left join public.business_locations sl on sl.id=so.location_id
 left join public.business_locations pl on pl.id=po.location_id
 left join lateral(
  select x.* from public.product_warranties_v483 x
  where x.tenant_id=s.tenant_id and x.serial_id=s.id and x.status<>'void'
  order by x.created_at desc limit 1
 ) w on true
 where s.tenant_id=p_tenant_id
 and private.erp_document_scope_allowed(p_tenant_id,coalesce(s.current_location_id,so.location_id,po.location_id),p_location_id,'view')
 and (
  trim(coalesce(p_query,''))='' or lower(s.serial_number) like q or lower(coalesce(p.name,'')) like q or
  lower(coalesce(pv.sku,'')) like q or lower(coalesce(sup.name,'')) like q or lower(coalesce(c.name,'')) like q or
  lower(coalesce(pur.purchase_number,'')) like q or lower(coalesce(sa.sale_number,'')) like q
 )
 order by s.updated_at desc
 limit greatest(1,least(coalesce(p_limit,200),1000));
end$$;
grant execute on function public.inventory_serial_search_v483(uuid,text,uuid,integer) to authenticated;

create or replace function public.inventory_batch_search_v483(
 p_tenant_id uuid,p_query text default '',p_location_id uuid default null,p_limit integer default 200
) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
 if not private.erp_user_has_tenant_access(p_tenant_id) or not private.v483_trace_view_allowed(p_tenant_id) then raise exception 'Traceability view permission required';end if;
 return query
 select jsonb_build_object(
  'batch_id',b.id,'batch_number',b.batch_number,'status',b.status,'variant_id',b.variant_id,
  'product_name',p.name,'variant_name',pv.variant_name,'sku',pv.sku,
  'manufactured_on',b.manufactured_on,'expiry_on',b.expiry_on,
  'expired',b.expiry_on is not null and b.expiry_on<current_date,
  'supplier_id',b.supplier_id,'supplier_name',sup.name,'purchase_id',b.first_purchase_id,'purchase_number',pur.purchase_number,
  'quantity',coalesce(sum(bb.quantity),0),
  'locations',coalesce(
    jsonb_agg(distinct jsonb_build_object('location_id',bb.location_id,'location_name',l.name,'quantity',bb.quantity))
      filter(where bb.location_id is not null),
    '[]'::jsonb
  )
 )
 from public.inventory_batches_v483 b
 join public.product_variants pv on pv.id=b.variant_id and pv.tenant_id=b.tenant_id
 join public.products p on p.id=pv.product_id
 left join public.inventory_batch_balances_v483 bb
   on bb.tenant_id=b.tenant_id and bb.batch_id=b.id
  and private.erp_document_scope_allowed(p_tenant_id,bb.location_id,p_location_id,'view')
 left join public.business_locations l on l.id=bb.location_id
 left join public.suppliers sup on sup.id=b.supplier_id
 left join public.purchases pur on pur.id=b.first_purchase_id
 where b.tenant_id=p_tenant_id
 and (
   exists(
    select 1 from public.inventory_batch_balances_v483 ab
    where ab.tenant_id=b.tenant_id and ab.batch_id=b.id
      and private.erp_document_scope_allowed(p_tenant_id,ab.location_id,p_location_id,'view')
   )
   or exists(
    select 1 from public.inventory_trace_events_v483 ae
    where ae.tenant_id=b.tenant_id and ae.batch_id=b.id
      and private.erp_document_scope_allowed(p_tenant_id,ae.location_id,p_location_id,'view')
   )
 )
 and (
  trim(coalesce(p_query,''))='' or lower(b.batch_number) like q or lower(coalesce(p.name,'')) like q or
  lower(coalesce(pv.sku,'')) like q or lower(coalesce(sup.name,'')) like q or exists(
   select 1
   from public.inventory_trace_events_v483 e
   left join public.customers c on c.id=e.customer_id
   left join public.sales s on s.id=e.sale_id
   left join public.purchases pp on pp.id=e.purchase_id
   where e.tenant_id=b.tenant_id and e.batch_id=b.id
     and private.erp_document_scope_allowed(p_tenant_id,e.location_id,p_location_id,'view')
     and (
       lower(coalesce(c.name,'')) like q or lower(coalesce(s.sale_number,'')) like q or
       lower(coalesce(pp.purchase_number,'')) like q or lower(coalesce(e.reference_number,'')) like q
     )
  )
 )
 group by b.id,p.name,pv.variant_name,pv.sku,sup.name,pur.purchase_number
 order by b.updated_at desc
 limit greatest(1,least(coalesce(p_limit,200),1000));
end$$;
grant execute on function public.inventory_batch_search_v483(uuid,text,uuid,integer) to authenticated;

create or replace function public.inventory_batch_history_v483(p_tenant_id uuid,p_batch_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v jsonb;begin
 if not private.erp_user_has_tenant_access(p_tenant_id) or not private.v483_trace_view_allowed(p_tenant_id) then raise exception 'Traceability view permission required';end if;
 if not exists(
  select 1 from public.inventory_batch_balances_v483 bb
  where bb.tenant_id=p_tenant_id and bb.batch_id=p_batch_id
    and private.erp_document_scope_allowed(p_tenant_id,bb.location_id,null,'view')
  union all
  select 1 from public.inventory_trace_events_v483 e
  where e.tenant_id=p_tenant_id and e.batch_id=p_batch_id
    and private.erp_document_scope_allowed(p_tenant_id,e.location_id,null,'view')
 ) then raise exception 'Batch not found or location access denied';end if;
 select jsonb_build_object(
  'batch',jsonb_build_object(
    'batch_id',b.id,'batch_number',b.batch_number,'variant_id',b.variant_id,'product_name',p.name,'variant_name',pv.variant_name,
    'sku',pv.sku,'manufactured_on',b.manufactured_on,'expiry_on',b.expiry_on,'status',b.status,'supplier_name',sup.name
  ),
  'balances',coalesce((
    select jsonb_agg(jsonb_build_object('location_id',bb.location_id,'location_name',l.name,'quantity',bb.quantity) order by l.name)
    from public.inventory_batch_balances_v483 bb
    left join public.business_locations l on l.id=bb.location_id
    where bb.tenant_id=p_tenant_id and bb.batch_id=b.id
      and private.erp_document_scope_allowed(p_tenant_id,bb.location_id,null,'view')
  ),'[]'::jsonb),
  'events',coalesce((
    select jsonb_agg(jsonb_build_object(
      'event_id',e.id,'event_type',e.event_type,'quantity',e.quantity,'location_name',l2.name,
      'supplier_name',s.name,'customer_name',c.name,'purchase_number',pur.purchase_number,'sale_number',sa.sale_number,
      'reference_number',e.reference_number,'metadata',e.metadata,'created_at',e.created_at
    ) order by e.created_at desc)
    from public.inventory_trace_events_v483 e
    left join public.business_locations l2 on l2.id=e.location_id
    left join public.suppliers s on s.id=e.supplier_id
    left join public.customers c on c.id=e.customer_id
    left join public.purchases pur on pur.id=e.purchase_id
    left join public.sales sa on sa.id=e.sale_id
    where e.tenant_id=p_tenant_id and e.batch_id=b.id
      and private.erp_document_scope_allowed(p_tenant_id,e.location_id,null,'view')
  ),'[]'::jsonb)
 ) into v
 from public.inventory_batches_v483 b
 join public.product_variants pv on pv.id=b.variant_id and pv.tenant_id=b.tenant_id
 join public.products p on p.id=pv.product_id
 left join public.suppliers sup on sup.id=b.supplier_id
 where b.tenant_id=p_tenant_id and b.id=p_batch_id;
 if v is null then raise exception 'Batch not found';end if;
 return v;
end$$;
grant execute on function public.inventory_batch_history_v483(uuid,uuid) to authenticated;

create or replace function public.inventory_serial_history_v483(p_tenant_id uuid,p_serial_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v jsonb;begin
 if not private.erp_user_has_tenant_access(p_tenant_id) or not private.v483_trace_view_allowed(p_tenant_id) then raise exception 'Traceability view permission required';end if;
 select jsonb_build_object(
  'serial',jsonb_build_object(
    'serial_id',s.id,'serial_number',s.serial_number,'status',s.status,'variant_id',s.variant_id,
    'product_name',p.name,'variant_name',pv.variant_name,'sku',pv.sku,
    'location_name',coalesce(l.name,sl.name,pl.name),'supplier_name',sup.name,'customer_name',c.name,
    'purchase_number',pur.purchase_number,'sale_number',sa.sale_number,'received_at',s.received_at,'sold_at',s.sold_at
  ),
  'warranties',coalesce((
    select jsonb_agg(jsonb_build_object(
      'warranty_id',w.id,'customer_name',cw.name,'sale_number',sw.sale_number,
      'warranty_start',w.warranty_start,'warranty_expiry',w.warranty_expiry,
      'status',case when w.status='active' and w.warranty_expiry<current_date then 'expired' else w.status end
    ) order by w.created_at desc)
    from public.product_warranties_v483 w
    left join public.customers cw on cw.id=w.customer_id
    left join public.sales sw on sw.id=w.sale_id
    where w.tenant_id=p_tenant_id and w.serial_id=s.id
  ),'[]'::jsonb),
  'events',coalesce((
    select jsonb_agg(jsonb_build_object(
      'event_id',e.id,'event_type',e.event_type,'quantity',e.quantity,'location_name',el.name,
      'supplier_name',es.name,'customer_name',ec.name,'purchase_number',ep.purchase_number,'sale_number',esa.sale_number,
      'reference_number',e.reference_number,'created_at',e.created_at
    ) order by e.created_at desc)
    from public.inventory_trace_events_v483 e
    left join public.business_locations el on el.id=e.location_id
    left join public.suppliers es on es.id=e.supplier_id
    left join public.customers ec on ec.id=e.customer_id
    left join public.purchases ep on ep.id=e.purchase_id
    left join public.sales esa on esa.id=e.sale_id
    where e.tenant_id=p_tenant_id and e.serial_id=s.id
      and private.erp_document_scope_allowed(p_tenant_id,e.location_id,null,'view')
  ),'[]'::jsonb)
 ) into v
 from public.inventory_serials_v483 s
 join public.product_variants pv on pv.id=s.variant_id and pv.tenant_id=s.tenant_id
 join public.products p on p.id=pv.product_id
 left join public.business_locations l on l.id=s.current_location_id
 left join public.suppliers sup on sup.id=s.supplier_id
 left join public.customers c on c.id=s.customer_id
 left join public.purchases pur on pur.id=s.purchase_id
 left join public.sales sa on sa.id=s.sale_id
 left join public.document_origins so on so.tenant_id=s.tenant_id and so.entity_type='sale' and so.entity_id=s.sale_id
 left join public.document_origins po on po.tenant_id=s.tenant_id and po.entity_type='purchase' and po.entity_id=s.purchase_id
 left join public.business_locations sl on sl.id=so.location_id
 left join public.business_locations pl on pl.id=po.location_id
 where s.tenant_id=p_tenant_id and s.id=p_serial_id
   and private.erp_document_scope_allowed(p_tenant_id,coalesce(s.current_location_id,so.location_id,po.location_id),null,'view');
 if v is null then raise exception 'Serial not found or location access denied';end if;
 return v;
end$$;
grant execute on function public.inventory_serial_history_v483(uuid,uuid) to authenticated;

create or replace function public.warranty_register_v483(
 p_tenant_id uuid,p_query text default '',p_status text default null,p_expiring_days integer default null,p_limit integer default 300,p_location_id uuid default null
) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
 if not private.erp_user_has_tenant_access(p_tenant_id) or not private.v483_trace_view_allowed(p_tenant_id) then raise exception 'Traceability view permission required';end if;
 return query
 select jsonb_build_object(
  'warranty_id',w.id,'variant_id',w.variant_id,'product_name',p.name,'variant_name',pv.variant_name,'sku',pv.sku,
  'serial_number',s.serial_number,'batch_number',b.batch_number,'customer_id',w.customer_id,'customer_name',c.name,
  'sale_id',w.sale_id,'sale_number',sa.sale_number,'quantity',w.quantity,'warranty_start',w.warranty_start,
  'warranty_expiry',w.warranty_expiry,'days_remaining',w.warranty_expiry-current_date,
  'status',case when w.status='active' and w.warranty_expiry<current_date then 'expired' else w.status end,
  'location_id',o.location_id,'location_name',l.name
 )
 from public.product_warranties_v483 w
 join public.product_variants pv on pv.id=w.variant_id and pv.tenant_id=w.tenant_id
 join public.products p on p.id=pv.product_id
 left join public.inventory_serials_v483 s on s.id=w.serial_id
 left join public.inventory_batches_v483 b on b.id=w.batch_id
 join public.customers c on c.id=w.customer_id
 join public.sales sa on sa.id=w.sale_id
 left join public.document_origins o on o.tenant_id=w.tenant_id and o.entity_type='sale' and o.entity_id=w.sale_id
 left join public.business_locations l on l.id=o.location_id
 where w.tenant_id=p_tenant_id
 and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
 and (
  trim(coalesce(p_query,''))='' or lower(coalesce(s.serial_number,'')) like q or lower(coalesce(b.batch_number,'')) like q or
  lower(coalesce(p.name,'')) like q or lower(coalesce(pv.sku,'')) like q or lower(coalesce(c.name,'')) like q or
  lower(coalesce(sa.sale_number,'')) like q
 )
 and (
  p_status is null or lower(p_status)=case when w.status='active' and w.warranty_expiry<current_date then 'expired' else lower(w.status) end
 )
 and (
  p_expiring_days is null or (w.status='active' and w.warranty_expiry between current_date and current_date+greatest(p_expiring_days,0))
 )
 order by w.warranty_expiry,w.created_at desc
 limit greatest(1,least(coalesce(p_limit,300),1000));
end$$;
grant execute on function public.warranty_register_v483(uuid,text,text,integer,integer,uuid) to authenticated;

create or replace function public.inventory_serial_resolve_v483(p_tenant_id uuid,p_serial_number text,p_location_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v jsonb;begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 select jsonb_build_object(
   'serial_id',s.id,'serial_number',s.serial_number,'status',s.status,'variant_id',s.variant_id,
   'product_name',p.name,'variant_name',pv.variant_name,'sku',pv.sku,'location_id',s.current_location_id
 ) into v
 from public.inventory_serials_v483 s
 join public.product_variants pv on pv.id=s.variant_id and pv.tenant_id=s.tenant_id
 join public.products p on p.id=pv.product_id
 where s.tenant_id=p_tenant_id
   and lower(trim(s.serial_number))=lower(trim(p_serial_number))
   and (p_location_id is null or s.current_location_id=p_location_id)
   and private.erp_document_scope_allowed(p_tenant_id,s.current_location_id,p_location_id,'view')
 limit 1;
 return v;
end$$;
grant execute on function public.inventory_serial_resolve_v483(uuid,text,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(138,'4.8.3','Serial / Batch / Warranty','Location-scoped serial search/history, batch search/history, warranty register and serial resolution APIs.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.3 migration 138 trace search/history applied' as status;
