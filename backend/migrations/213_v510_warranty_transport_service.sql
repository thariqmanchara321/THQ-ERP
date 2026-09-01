-- THQ ERP v5.1.0 Build 27 — warranty/trace compatibility + Transport/Service completion.
begin;

create or replace function public.inventory_serial_search_v483(
 p_tenant_id uuid,p_query text default '',p_location_id uuid default null,p_limit integer default 200
) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
 if not private.erp_user_has_tenant_access(p_tenant_id) or not private.v483_trace_view_allowed(p_tenant_id) then raise exception 'Traceability view permission required';end if;
 return query
 select jsonb_build_object(
  'serial_id',s.id,'serial_number',s.serial_number,'status',s.status,'variant_id',s.variant_id,
  'product_name',p.name,'variant_name',pv.name,'sku',pv.sku,
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
  'product_name',p.name,'variant_name',pv.name,'sku',pv.sku,
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
 group by b.id,p.name,pv.name,pv.sku,sup.name,pur.purchase_number
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
    'batch_id',b.id,'batch_number',b.batch_number,'variant_id',b.variant_id,'product_name',p.name,'variant_name',pv.name,
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
    'product_name',p.name,'variant_name',pv.name,'sku',pv.sku,
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
  'warranty_id',w.id,'variant_id',w.variant_id,'product_name',p.name,'variant_name',pv.name,'sku',pv.sku,
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
   'product_name',p.name,'variant_name',pv.name,'sku',pv.sku,'location_id',s.current_location_id
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

create or replace function public.selector_search_v495(
  p_tenant_id uuid,p_entity text,p_query text default '',p_location_id uuid default null,p_limit integer default 50
) returns table(id uuid,label text,subtitle text,search_code text,match_rank integer)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare q text:=lower(trim(coalesce(p_query,''))); lim integer:=greatest(1,least(coalesce(p_limit,50),200));
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if p_entity='customer' then
    return query
    select c.id,c.name,
      concat_ws(' • ',nullif(c.tracking_code,''),nullif(c.phone,''),nullif(c.tax_number,''))::text,
      concat_ws(' ',c.name,c.tracking_code,c.phone,c.email,c.tax_number)::text,
      case when q='' then 0 when lower(c.name) like q||'%' or lower(coalesce(c.tracking_code,'')) like q||'%' or lower(coalesce(c.phone,'')) like q||'%' then 0 else 1 end
    from public.customers c where c.tenant_id=p_tenant_id and coalesce(c.status,'active')='active'
      and (q='' or lower(concat_ws(' ',c.name,c.tracking_code,c.phone,c.email,c.tax_number)) like '%'||q||'%')
    order by 5,c.name limit lim;
  elsif p_entity='supplier' then
    return query
    select s.id,s.name,
      concat_ws(' • ',nullif(s.tracking_code,''),nullif(s.phone,''),nullif(s.tax_number,''))::text,
      concat_ws(' ',s.name,s.tracking_code,s.phone,s.email,s.tax_number)::text,
      case when q='' then 0 when lower(s.name) like q||'%' or lower(coalesce(s.tracking_code,'')) like q||'%' or lower(coalesce(s.phone,'')) like q||'%' then 0 else 1 end
    from public.suppliers s where s.tenant_id=p_tenant_id and coalesce(s.status,'active')='active'
      and (q='' or lower(concat_ws(' ',s.name,s.tracking_code,s.phone,s.email,s.tax_number)) like '%'||q||'%')
    order by 5,s.name limit lim;
  elsif p_entity='product' then
    return query
    select pv.id,p.name,
      concat_ws(' • ',nullif(pv.sku,''),nullif(pv.barcode,''),nullif(pv.part_number,''))::text,
      concat_ws(' ',p.name,pv.name,pv.sku,pv.barcode,pv.part_number)::text,
      case when q='' then 0 when lower(p.name) like q||'%' or lower(coalesce(pv.sku,'')) like q||'%' or lower(coalesce(pv.barcode,'')) like q||'%' or lower(coalesce(pv.part_number,'')) like q||'%' then 0 else 1 end
    from public.product_variants pv join public.products p on p.id=pv.product_id
    where p.tenant_id=p_tenant_id
      and (q='' or lower(concat_ws(' ',p.name,pv.name,pv.sku,pv.barcode,pv.part_number)) like '%'||q||'%')
    order by 5,p.name,pv.sku limit lim;
  elsif p_entity='account' then
    return query
    select a.id,a.name,concat_ws(' • ',a.code,a.account_type)::text,concat_ws(' ',a.code,a.name,a.account_type)::text,
      case when q='' then 0 when lower(a.code) like q||'%' or lower(a.name) like q||'%' then 0 else 1 end
    from public.accounting_accounts a where a.tenant_id=p_tenant_id and a.active
      and (q='' or lower(concat_ws(' ',a.code,a.name,a.account_type)) like '%'||q||'%')
    order by 5,a.code limit lim;
  elsif p_entity='location' then
    return query
    select l.id,l.name,concat_ws(' • ',l.location_code,l.city,l.state)::text,concat_ws(' ',l.location_code,l.name,l.city,l.state,l.postal_code)::text,
      case when q='' then 0 when lower(l.location_code) like q||'%' or lower(l.name) like q||'%' then 0 else 1 end
    from public.business_locations l where l.tenant_id=p_tenant_id and l.active
      and (private.erp_user_is_owner(p_tenant_id) or private.erp_user_location_allowed(p_tenant_id,l.id,'view'))
      and (q='' or lower(concat_ws(' ',l.location_code,l.name,l.city,l.state,l.postal_code)) like '%'||q||'%')
    order by 5,l.location_code limit lim;
  else
    raise exception 'Unsupported selector entity %',p_entity;
  end if;
end $$;
grant execute on function public.selector_search_v495(uuid,text,text,uuid,integer) to authenticated;

-- Keep warranty rows synchronized with posted/cancelled sales and current dates.
create or replace function public.warranty_sync_v51(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_expired integer:=0;v_reactivated integer:=0;v_voided integer:=0;v_serial_backfill integer:=0;v_batch_backfill integer:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) or not private.v483_trace_view_allowed(p_tenant_id) then
    raise exception 'Traceability view permission required';
  end if;

  update public.product_warranties_v483 w
  set status='void',updated_at=now()
  from public.sales s
  where w.tenant_id=p_tenant_id and s.id=w.sale_id and s.tenant_id=w.tenant_id
    and s.status='cancelled' and w.status in('active','expired');
  get diagnostics v_voided=row_count;

  update public.product_warranties_v483
  set status='expired',updated_at=now()
  where tenant_id=p_tenant_id and status='active' and warranty_expiry<current_date;
  get diagnostics v_expired=row_count;

  update public.product_warranties_v483 w
  set status='active',updated_at=now()
  from public.sales s
  where w.tenant_id=p_tenant_id and s.id=w.sale_id and s.status='posted'
    and w.status='expired' and w.warranty_expiry>=current_date;
  get diagnostics v_reactivated=row_count;

  insert into public.product_warranties_v483(
    tenant_id,variant_id,serial_id,batch_id,customer_id,sale_id,sale_item_id,quantity,
    warranty_start,warranty_expiry,status,created_by
  )
  select s.tenant_id,s.variant_id,s.id,null,s.customer_id,s.sale_id,s.sale_item_id,1,
         sa.sale_date,
         (sa.sale_date+make_interval(months=>coalesce(tp.warranty_months,0),days=>coalesce(tp.warranty_days,0)))::date,
         case when (sa.sale_date+make_interval(months=>coalesce(tp.warranty_months,0),days=>coalesce(tp.warranty_days,0)))::date<current_date then 'expired' else 'active' end,
         coalesce(s.created_by,sa.created_by)
  from public.inventory_serials_v483 s
  join public.sales sa on sa.id=s.sale_id and sa.tenant_id=s.tenant_id and sa.status='posted'
  join public.product_tracking_policies_v483 tp on tp.tenant_id=s.tenant_id and tp.variant_id=s.variant_id and tp.warranty_enabled
  where s.tenant_id=p_tenant_id and s.status='sold' and s.sale_id is not null and s.sale_item_id is not null
    and not exists(select 1 from public.product_warranties_v483 w where w.tenant_id=s.tenant_id and w.serial_id=s.id and w.sale_id=s.sale_id and w.status<>'void')
  on conflict do nothing;
  get diagnostics v_serial_backfill=row_count;

  insert into public.product_warranties_v483(
    tenant_id,variant_id,serial_id,batch_id,customer_id,sale_id,sale_item_id,quantity,
    warranty_start,warranty_expiry,status,created_by
  )
  select e.tenant_id,e.variant_id,null,e.batch_id,e.customer_id,e.sale_id,e.sale_item_id,sum(e.quantity),
         sa.sale_date,
         (sa.sale_date+make_interval(months=>coalesce(tp.warranty_months,0),days=>coalesce(tp.warranty_days,0)))::date,
         case when (sa.sale_date+make_interval(months=>coalesce(tp.warranty_months,0),days=>coalesce(tp.warranty_days,0)))::date<current_date then 'expired' else 'active' end,
         (array_agg(e.created_by) filter(where e.created_by is not null))[1]
  from public.inventory_trace_events_v483 e
  join public.sales sa on sa.id=e.sale_id and sa.tenant_id=e.tenant_id and sa.status='posted'
  join public.product_tracking_policies_v483 tp on tp.tenant_id=e.tenant_id and tp.variant_id=e.variant_id and tp.warranty_enabled
  where e.tenant_id=p_tenant_id and e.event_type='sale' and e.batch_id is not null and e.sale_id is not null and e.sale_item_id is not null
    and not exists(select 1 from public.product_warranties_v483 w where w.tenant_id=e.tenant_id and w.batch_id=e.batch_id and w.sale_id=e.sale_id and w.sale_item_id=e.sale_item_id and w.status<>'void')
  group by e.tenant_id,e.variant_id,e.batch_id,e.customer_id,e.sale_id,e.sale_item_id,sa.sale_date,tp.warranty_months,tp.warranty_days
  on conflict do nothing;
  get diagnostics v_batch_backfill=row_count;

  return jsonb_build_object('success',true,'expired',v_expired,'reactivated',v_reactivated,'voided',v_voided,'serial_backfilled',v_serial_backfill,'batch_backfilled',v_batch_backfill);
end $$;
revoke all on function public.warranty_sync_v51(uuid) from public,anon;
grant execute on function public.warranty_sync_v51(uuid) to authenticated;

-- Transport / Service v5.1: validated vehicle/job lifecycle and atomic billing.
create or replace function public.service_vehicles_list_v51(p_tenant_id uuid,p_location_id uuid default null)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'transport_service.view') or private.erp_has_permission(p_tenant_id,'transport_service.create') or private.erp_has_permission(p_tenant_id,'transport_service.manage')) then raise exception 'Permission denied';end if;
  return query
  select jsonb_build_object(
    'id',v.id,'tracking_code',v.tracking_code,'registration_number',v.registration_number,'vehicle_type',v.vehicle_type,
    'make_model',v.make_model,'capacity',v.capacity,'capacity_unit',v.capacity_unit,'driver_name',v.driver_name,'driver_phone',v.driver_phone,
    'active',v.active,'location_id',v.location_id,'location_name',l.name,
    'open_jobs',(select count(*) from public.service_jobs j where j.tenant_id=v.tenant_id and j.vehicle_id=v.id and j.status in('planned','in_progress')),
    'created_at',v.created_at,'updated_at',v.updated_at
  )
  from public.service_vehicles v
  left join public.business_locations l on l.id=v.location_id and l.tenant_id=v.tenant_id
  where v.tenant_id=p_tenant_id
    and private.erp_document_scope_allowed(p_tenant_id,v.location_id,p_location_id,'view')
  order by v.active desc,v.registration_number;
end $$;
revoke all on function public.service_vehicles_list_v51(uuid,uuid) from public,anon;
grant execute on function public.service_vehicles_list_v51(uuid,uuid) to authenticated;

create or replace function public.service_vehicle_save_v51(
  p_tenant_id uuid,p_vehicle_id uuid,p_location_id uuid,p_registration_number text,p_vehicle_type text,p_make_model text,
  p_capacity numeric,p_capacity_unit text,p_driver_name text,p_driver_phone text,p_active boolean
) returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;v_old public.service_vehicles%rowtype;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'transport_service.manage')) then raise exception 'Transport service manage permission required';end if;
  if nullif(trim(coalesce(p_registration_number,'')),'') is null then raise exception 'Registration number is required';end if;
  if coalesce(p_capacity,0)<0 then raise exception 'Capacity cannot be negative';end if;
  if p_location_id is null or not exists(select 1 from public.business_locations l where l.id=p_location_id and l.tenant_id=p_tenant_id and l.active) then raise exception 'Active store/location is required';end if;
  if not private.erp_document_scope_allowed(p_tenant_id,p_location_id,p_location_id,'operate') then raise exception 'Location access denied';end if;
  if exists(select 1 from public.service_vehicles x where x.tenant_id=p_tenant_id and upper(trim(x.registration_number))=upper(trim(p_registration_number)) and x.id is distinct from p_vehicle_id) then raise exception 'Vehicle registration number already exists';end if;

  if p_vehicle_id is not null then
    select * into v_old from public.service_vehicles where id=p_vehicle_id and tenant_id=p_tenant_id for update;
    if not found then raise exception 'Vehicle not found';end if;
    if not private.erp_document_scope_allowed(p_tenant_id,v_old.location_id,v_old.location_id,'operate') then raise exception 'You cannot edit this vehicle';end if;
    if not coalesce(p_active,true) and exists(select 1 from public.service_jobs j where j.tenant_id=p_tenant_id and j.vehicle_id=p_vehicle_id and j.status in('planned','in_progress')) then raise exception 'Complete or cancel open service jobs before deactivating this vehicle';end if;
  end if;

  if p_vehicle_id is null then
    insert into public.service_vehicles(tenant_id,location_id,registration_number,vehicle_type,make_model,capacity,capacity_unit,driver_name,driver_phone,active)
    values(p_tenant_id,p_location_id,upper(trim(p_registration_number)),nullif(trim(coalesce(p_vehicle_type,'')),''),nullif(trim(coalesce(p_make_model,'')),''),coalesce(p_capacity,0),nullif(trim(coalesce(p_capacity_unit,'')),''),nullif(trim(coalesce(p_driver_name,'')),''),nullif(trim(coalesce(p_driver_phone,'')),''),coalesce(p_active,true))
    returning id into v_id;
  else
    update public.service_vehicles set location_id=p_location_id,registration_number=upper(trim(p_registration_number)),vehicle_type=nullif(trim(coalesce(p_vehicle_type,'')),''),make_model=nullif(trim(coalesce(p_make_model,'')),''),capacity=coalesce(p_capacity,0),capacity_unit=nullif(trim(coalesce(p_capacity_unit,'')),''),driver_name=nullif(trim(coalesce(p_driver_name,'')),''),driver_phone=nullif(trim(coalesce(p_driver_phone,'')),''),active=coalesce(p_active,true),updated_at=now()
    where id=p_vehicle_id and tenant_id=p_tenant_id returning id into v_id;
  end if;
  perform private.business_audit_write_v471(p_tenant_id,'service.vehicle.save','service_vehicle',v_id,upper(trim(p_registration_number)),case when p_vehicle_id is null then null else to_jsonb(v_old) end,jsonb_build_object('location_id',p_location_id,'active',coalesce(p_active,true)));
  return v_id;
end $$;
revoke all on function public.service_vehicle_save_v51(uuid,uuid,uuid,text,text,text,numeric,text,text,text,boolean) from public,anon;
grant execute on function public.service_vehicle_save_v51(uuid,uuid,uuid,text,text,text,numeric,text,text,text,boolean) to authenticated;

create or replace function public.service_jobs_list_v51(p_tenant_id uuid,p_location_id uuid default null,p_status text default null,p_limit integer default 500)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'transport_service.view') or private.erp_has_permission(p_tenant_id,'transport_service.create') or private.erp_has_permission(p_tenant_id,'transport_service.manage')) then raise exception 'Permission denied';end if;
  return query
  select jsonb_build_object(
    'id',j.id,'tracking_code',j.tracking_code,'job_number',j.job_number,'service_date',j.service_date,'location_id',j.location_id,'location_name',l.name,
    'customer_id',j.customer_id,'customer_name',c.name,'customer_phone',c.phone,'vehicle_id',j.vehicle_id,'registration_number',v.registration_number,
    'vehicle_type',v.vehicle_type,'driver_name',v.driver_name,'from_location',j.from_location,'to_location',j.to_location,'distance_km',j.distance_km,
    'quantity',j.quantity,'quantity_unit',j.quantity_unit,'rate',j.rate,'total_amount',j.total_amount,'notes',j.notes,'status',j.status,
    'sale_id',j.sale_id,'sale_number',s.sale_number,'sale_status',s.status,'billed',j.sale_id is not null,'created_at',j.created_at,'updated_at',j.updated_at
  )
  from public.service_jobs j
  left join public.business_locations l on l.id=j.location_id and l.tenant_id=j.tenant_id
  left join public.customers c on c.id=j.customer_id and c.tenant_id=j.tenant_id
  left join public.service_vehicles v on v.id=j.vehicle_id and v.tenant_id=j.tenant_id
  left join public.sales s on s.id=j.sale_id and s.tenant_id=j.tenant_id
  where j.tenant_id=p_tenant_id and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
    and (p_status is null or trim(p_status)='' or j.status=lower(trim(p_status)))
  order by j.service_date desc,j.created_at desc
  limit greatest(1,least(coalesce(p_limit,500),2000));
end $$;
revoke all on function public.service_jobs_list_v51(uuid,uuid,text,integer) from public,anon;
grant execute on function public.service_jobs_list_v51(uuid,uuid,text,integer) to authenticated;

create or replace function public.service_job_save_v51(
  p_tenant_id uuid,p_job_id uuid,p_location_id uuid,p_customer_id uuid,p_vehicle_id uuid,p_service_date date,
  p_from_location text,p_to_location text,p_distance_km numeric,p_quantity numeric,p_quantity_unit text,p_rate numeric,p_notes text,p_status text default 'planned'
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;v_job text;v_tracking text;v_total numeric;v_status text:=lower(coalesce(nullif(trim(p_status),''),'planned'));v_old public.service_jobs%rowtype;v_vehicle_location uuid;v_vehicle_active boolean;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if p_job_id is null then
    if not (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'transport_service.create') or private.erp_has_permission(p_tenant_id,'transport_service.manage')) then raise exception 'Transport service create permission required';end if;
  else
    if not (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'transport_service.manage')) then raise exception 'Transport service manage permission required';end if;
  end if;
  if v_status not in('planned','in_progress','completed','cancelled') then raise exception 'Invalid service job status';end if;
  if p_location_id is null or not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active) then raise exception 'Active store/location is required';end if;
  if not private.erp_document_scope_allowed(p_tenant_id,p_location_id,p_location_id,'operate') then raise exception 'Location access denied';end if;
  if p_customer_id is not null and not exists(select 1 from public.customers where id=p_customer_id and tenant_id=p_tenant_id and status='active') then raise exception 'Active customer not found';end if;
  if p_vehicle_id is not null then
    select location_id,active into v_vehicle_location,v_vehicle_active from public.service_vehicles where id=p_vehicle_id and tenant_id=p_tenant_id;
    if v_vehicle_location is null then raise exception 'Vehicle not found';end if;
    if not coalesce(v_vehicle_active,false) then raise exception 'Selected vehicle is inactive';end if;
    if v_vehicle_location is distinct from p_location_id then raise exception 'Choose a vehicle assigned to this store';end if;
  end if;
  if coalesce(p_distance_km,0)<0 then raise exception 'Distance cannot be negative';end if;
  if coalesce(p_quantity,0)<=0 then raise exception 'Quantity must be greater than zero';end if;
  if coalesce(p_rate,0)<0 then raise exception 'Rate cannot be negative';end if;
  if nullif(trim(coalesce(p_quantity_unit,'')),'') is null then raise exception 'Quantity unit is required';end if;
  v_total:=round(coalesce(p_quantity,0)*coalesce(p_rate,0),2);

  if p_job_id is not null then
    select * into v_old from public.service_jobs where id=p_job_id and tenant_id=p_tenant_id for update;
    if not found then raise exception 'Service job not found';end if;
    if v_old.sale_id is not null and (p_location_id is distinct from v_old.location_id or p_customer_id is distinct from v_old.customer_id or p_vehicle_id is distinct from v_old.vehicle_id or coalesce(p_quantity,0)<>v_old.quantity or coalesce(p_rate,0)<>v_old.rate) then raise exception 'Billed service jobs cannot change store, customer, vehicle, quantity or rate';end if;
    if v_old.sale_id is not null and v_status='cancelled' then raise exception 'Billed service job cannot be cancelled; reverse the linked sale first';end if;
  end if;

  if p_job_id is null then
    v_id:=gen_random_uuid();
    insert into public.service_jobs(id,tenant_id,job_number,location_id,customer_id,vehicle_id,service_date,from_location,to_location,distance_km,quantity,quantity_unit,rate,total_amount,notes,status,created_by)
    values(v_id,p_tenant_id,'',p_location_id,p_customer_id,p_vehicle_id,coalesce(p_service_date,current_date),nullif(trim(coalesce(p_from_location,'')),''),nullif(trim(coalesce(p_to_location,'')),''),coalesce(p_distance_km,0),p_quantity,trim(p_quantity_unit),p_rate,v_total,nullif(trim(coalesce(p_notes,'')),''),v_status,auth.uid())
    returning job_number,tracking_code into v_job,v_tracking;
    insert into public.document_origins(tenant_id,entity_type,entity_id,location_id,created_by) values(p_tenant_id,'service_job',v_id,p_location_id,auth.uid()) on conflict do nothing;
  else
    v_id:=p_job_id;
    update public.service_jobs set location_id=p_location_id,customer_id=p_customer_id,vehicle_id=p_vehicle_id,service_date=coalesce(p_service_date,service_date),from_location=nullif(trim(coalesce(p_from_location,'')),''),to_location=nullif(trim(coalesce(p_to_location,'')),''),distance_km=coalesce(p_distance_km,0),quantity=p_quantity,quantity_unit=trim(p_quantity_unit),rate=p_rate,total_amount=v_total,notes=nullif(trim(coalesce(p_notes,'')),''),status=v_status,updated_at=now()
    where id=v_id and tenant_id=p_tenant_id returning job_number,tracking_code into v_job,v_tracking;
    update public.document_origins set location_id=p_location_id where tenant_id=p_tenant_id and entity_type='service_job' and entity_id=v_id;
  end if;
  perform private.business_audit_write_v471(p_tenant_id,'service.job.save','service_job',v_id,v_job,case when p_job_id is null then null else to_jsonb(v_old) end,jsonb_build_object('location_id',p_location_id,'status',v_status,'total_amount',v_total));
  return jsonb_build_object('job_id',v_id,'job_number',v_job,'tracking_code',v_tracking,'total_amount',v_total,'status',v_status);
end $$;
revoke all on function public.service_job_save_v51(uuid,uuid,uuid,uuid,uuid,date,text,text,numeric,numeric,text,numeric,text,text) from public,anon;
grant execute on function public.service_job_save_v51(uuid,uuid,uuid,uuid,uuid,date,text,text,numeric,numeric,text,numeric,text,text) to authenticated;

create or replace function public.service_job_status_v51(p_tenant_id uuid,p_job_id uuid,p_status text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare j public.service_jobs%rowtype;v_status text:=lower(trim(coalesce(p_status,'')));
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'transport_service.create') or private.erp_has_permission(p_tenant_id,'transport_service.manage')) then raise exception 'Transport service permission required';end if;
  if v_status not in('planned','in_progress','completed','cancelled') then raise exception 'Invalid service job status';end if;
  select * into j from public.service_jobs where id=p_job_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Service job not found';end if;
  if not private.erp_document_scope_allowed(p_tenant_id,j.location_id,j.location_id,'operate') then raise exception 'Location access denied';end if;
  if j.sale_id is not null and v_status='cancelled' then raise exception 'Billed service job cannot be cancelled; reverse the linked sale first';end if;
  update public.service_jobs set status=case when sale_id is not null then 'completed' else v_status end,updated_at=now() where id=p_job_id;
  perform private.business_audit_write_v471(p_tenant_id,'service.job.status','service_job',p_job_id,j.job_number,to_jsonb(j),jsonb_build_object('status',case when j.sale_id is not null then 'completed' else v_status end));
  return jsonb_build_object('success',true,'job_id',p_job_id,'status',case when j.sale_id is not null then 'completed' else v_status end);
end $$;
revoke all on function public.service_job_status_v51(uuid,uuid,text) from public,anon;
grant execute on function public.service_job_status_v51(uuid,uuid,text) to authenticated;

create or replace function public.service_job_link_sale_by_reference_v51(p_tenant_id uuid,p_job_id uuid,p_sale_number text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare j public.service_jobs%rowtype;v_sale_id uuid;v_sale_location uuid;v_sale_customer uuid;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'transport_service.create') or private.erp_has_permission(p_tenant_id,'transport_service.manage')) then raise exception 'Transport service permission required';end if;
  select * into j from public.service_jobs where id=p_job_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Service job not found';end if;
  if j.sale_id is not null then raise exception 'Service job is already billed';end if;
  select s.id,o.location_id,s.customer_id into v_sale_id,v_sale_location,v_sale_customer
  from public.sales s left join public.document_origins o on o.tenant_id=s.tenant_id and o.entity_type='sale' and o.entity_id=s.id
  where s.tenant_id=p_tenant_id and s.sale_number=trim(p_sale_number) and s.status='posted';
  if v_sale_id is null then raise exception 'Posted sale not found';end if;
  if v_sale_location is distinct from j.location_id then raise exception 'Service job and sale must belong to the same store';end if;
  if j.customer_id is not null and v_sale_customer is distinct from j.customer_id then raise exception 'Sale customer does not match service job customer';end if;
  update public.service_jobs set sale_id=v_sale_id,status='completed',updated_at=now() where id=j.id;
  perform private.business_audit_write_v471(p_tenant_id,'service.job.link_sale','service_job',j.id,j.job_number,to_jsonb(j),jsonb_build_object('sale_id',v_sale_id,'sale_number',p_sale_number));
  return jsonb_build_object('success',true,'job_id',j.id,'sale_id',v_sale_id,'sale_number',trim(p_sale_number));
end $$;
revoke all on function public.service_job_link_sale_by_reference_v51(uuid,uuid,text) from public,anon;
grant execute on function public.service_job_link_sale_by_reference_v51(uuid,uuid,text) to authenticated;

create or replace function public.service_job_bill_v51(
  p_tenant_id uuid,p_job_id uuid,p_billing_variant_id uuid,p_due_date date,p_initial_payment numeric,p_payment_method text,
  p_payment_reference text,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare j public.service_jobs%rowtype;v_tax numeric;v_item_type text;v_variant_status text;v_product_status text;v_expected numeric;v_result jsonb;v_sale_id uuid;v_sale_number text;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'transport_service.create') or private.erp_has_permission(p_tenant_id,'transport_service.manage')) then raise exception 'Transport service permission required';end if;
  select * into j from public.service_jobs where id=p_job_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Service job not found';end if;
  if j.sale_id is not null then raise exception 'Service job is already billed';end if;
  if j.status='cancelled' then raise exception 'Cancelled service job cannot be billed';end if;
  if j.customer_id is null then raise exception 'Assign a customer before billing';end if;
  if not private.erp_document_scope_allowed(p_tenant_id,j.location_id,j.location_id,'operate') then raise exception 'Location access denied';end if;
  select p.tax_rate,p.item_type,p.status,pv.status into v_tax,v_item_type,v_product_status,v_variant_status
  from public.product_variants pv join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id
  where pv.id=p_billing_variant_id and pv.tenant_id=p_tenant_id;
  if v_item_type is null or v_product_status<>'active' or v_variant_status<>'active' then raise exception 'Billing service item is invalid or inactive';end if;
  if v_item_type='stock' then raise exception 'Transport billing requires a Service or Non-stock item';end if;
  v_expected:=round(j.quantity*j.rate*(1+coalesce(v_tax,0)/100.0),2);
  if coalesce(p_initial_payment,0)<0 or coalesce(p_initial_payment,0)>v_expected+0.005 then raise exception 'Initial payment cannot exceed service invoice total';end if;
  if coalesce(p_initial_payment,0)>0 and lower(trim(coalesce(p_payment_method,''))) not in('cash','bank','card','upi','cheque','other') then raise exception 'Invalid payment method';end if;

  v_result:=public.sales_create_v481(
    p_tenant_id,j.customer_id,j.service_date,p_due_date,
    jsonb_build_array(jsonb_build_object('variant_id',p_billing_variant_id,'quantity',j.quantity,'unit_price',j.rate,'discount_amount',0,'tax_rate',coalesce(v_tax,0))),
    0,coalesce(p_initial_payment,0),case when coalesce(p_initial_payment,0)>0 then lower(trim(p_payment_method)) else 'credit' end,
    coalesce(p_payment_reference,''),'Transport service '||j.job_number||' • '||coalesce(j.tracking_code,''),j.location_id,p_device_id,p_request_id
  );
  v_sale_id:=nullif(v_result->>'sale_id','')::uuid;v_sale_number:=v_result->>'sale_number';
  if v_sale_id is null then raise exception 'Sale was not created';end if;
  update public.sale_items set pricing_source='service_job',pricing_metadata=coalesce(pricing_metadata,'{}'::jsonb)||jsonb_build_object('service_job_id',j.id,'service_job_number',j.job_number,'service_rate',j.rate)
  where sale_id=v_sale_id and variant_id=p_billing_variant_id;
  update public.service_jobs set sale_id=v_sale_id,status='completed',updated_at=now() where id=j.id;
  perform private.business_audit_write_v471(p_tenant_id,'service.job.bill','service_job',j.id,j.job_number,to_jsonb(j),jsonb_build_object('sale_id',v_sale_id,'sale_number',v_sale_number,'total',v_result->'grand_total'));
  return v_result||jsonb_build_object('job_id',j.id,'job_number',j.job_number,'service_total',j.total_amount,'billing_source','service_job_v51');
end $$;
revoke all on function public.service_job_bill_v51(uuid,uuid,uuid,date,numeric,text,text,uuid,text) from public,anon;
grant execute on function public.service_job_bill_v51(uuid,uuid,uuid,date,numeric,text,text,uuid,text) to authenticated;

-- Release registry and contract.
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(213,'5.1.0','Warranty & Transport Service','Repairs serial/batch/warranty lookup compatibility, warranty synchronization, and completes validated Transport/Service vehicle-job-billing lifecycle.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

insert into public.platform_app_releases(app_key,platform,version,build_number,status,minimum_supported,mandatory,release_notes,download_url,released_at)
select x.app_key,x.platform,'5.1.0',27,'stable',false,false,'THQ ERP v5.1: warranty synchronization, transport/service completion, desktop release/time placement and reliability fixes.',null,now()
from (values ('client','windows'),('client','web'),('client','android'),('pos','windows'),('pos','android'),('admin','web')) x(app_key,platform)
on conflict(app_key,platform,version) do update set build_number=excluded.build_number,status=excluded.status,release_notes=excluded.release_notes,released_at=excluded.released_at;

create or replace function public.thq_v510_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare miss text[]:='{}';r record;begin
  for r in select * from (values
    ('warranty_sync_v51','public.warranty_sync_v51(uuid)'),
    ('inventory_serial_search_v483','public.inventory_serial_search_v483(uuid,text,uuid,integer)'),
    ('inventory_serial_history_v483','public.inventory_serial_history_v483(uuid,uuid)'),
    ('inventory_serial_resolve_v483','public.inventory_serial_resolve_v483(uuid,text,uuid)'),
    ('inventory_batch_search_v483','public.inventory_batch_search_v483(uuid,text,uuid,integer)'),
    ('inventory_batch_history_v483','public.inventory_batch_history_v483(uuid,uuid)'),
    ('warranty_register_v483','public.warranty_register_v483(uuid,text,text,integer,integer,uuid)'),
    ('selector_search_v495','public.selector_search_v495(uuid,text,text,uuid,integer)'),
    ('service_vehicles_list_v51','public.service_vehicles_list_v51(uuid,uuid)'),
    ('service_vehicle_save_v51','public.service_vehicle_save_v51(uuid,uuid,uuid,text,text,text,numeric,text,text,text,boolean)'),
    ('service_jobs_list_v51','public.service_jobs_list_v51(uuid,uuid,text,integer)'),
    ('service_job_save_v51','public.service_job_save_v51(uuid,uuid,uuid,uuid,uuid,date,text,text,numeric,numeric,text,numeric,text,text)'),
    ('service_job_status_v51','public.service_job_status_v51(uuid,uuid,text)'),
    ('service_job_link_sale_by_reference_v51','public.service_job_link_sale_by_reference_v51(uuid,uuid,text)'),
    ('service_job_bill_v51','public.service_job_bill_v51(uuid,uuid,uuid,date,numeric,text,text,uuid,text)')
  ) v(name,sig) loop if to_regprocedure(r.sig) is null then miss:=array_append(miss,r.name);end if;end loop;
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='product_variants' and column_name='variant_name') then miss:=array_append(miss,'product_variants.variant_name_legacy_column');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='product_variants' and column_name='name') then miss:=array_append(miss,'product_variants.name');end if;
  if not exists(select 1 from public.thq_schema_releases where migration_no=213 and schema_version='5.1.0') then miss:=array_append(miss,'migration.213');end if;
  return jsonb_build_object('ready',cardinality(miss)=0,'missing',to_jsonb(miss),'schema_version','5.1.0','migration_no',213,'build',27,'capabilities',public.thq_v500_capabilities()||jsonb_build_object('warranty_sync',true,'transport_service_v51',true));
end $$;
grant execute on function public.thq_v510_verify() to authenticated;

create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
select jsonb_build_object('product','THQ ERP','schema_version','5.1.0','migration_no',213,'minimum_app_version','5.1.0','minimum_client_migration',213,'build',27,'release','Warranty & Transport Service','api_version','v1','backward_compatible',true,'verified_by','thq_v510_verify') $$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_api_contract_v480()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
select public.thq_backend_contract_v47()||jsonb_build_object('app_version','5.1.0','build',27,'minimum_migration',213,'capabilities',public.thq_v500_capabilities()||jsonb_build_object('warranty_sync',true,'transport_service_v51',true)) $$;
grant execute on function public.thq_api_contract_v480() to authenticated;

commit;
select 'THQ ERP v5.1 migration 213 warranty and transport service applied' as status;
