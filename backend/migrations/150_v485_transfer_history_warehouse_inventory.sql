-- THQ ERP V4.8.5 — transfer history and warehouse inventory reporting.
begin;

create or replace function public.inventory_transfers_list_v485(
  p_tenant_id uuid,p_location_id uuid default null,p_status text default null,p_query text default '',p_limit integer default 500
) returns table(
  id uuid,transfer_number text,from_location_id uuid,from_location text,from_is_warehouse boolean,
  to_location_id uuid,to_location text,to_is_warehouse boolean,status text,notes text,expected_arrival_date date,transport_reference text,
  created_at timestamptz,requested_at timestamptz,approved_at timestamptz,in_transit_at timestamptz,received_at timestamptz,
  item_count bigint,total_quantity numeric,serial_count bigint,batch_quantity numeric,in_transit_quantity numeric,reservation_applied boolean
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';
begin
  perform private.warehouse_v485_permission(p_tenant_id,false);
  return query
  select t.id,t.transfer_number,t.from_location_id,fl.location_code||' • '||fl.name,(fl.hierarchy_role='warehouse' or fl.location_type='warehouse'),
    t.to_location_id,tl.location_code||' • '||tl.name,(tl.hierarchy_role='warehouse' or tl.location_type='warehouse'),
    case when t.status='dispatched' then 'in_transit' else t.status end,t.notes,t.expected_arrival_date,t.transport_reference,
    t.created_at,t.requested_at,t.approved_at,coalesce(t.in_transit_at,t.dispatched_at),t.received_at,
    count(distinct i.id),coalesce(sum(i.quantity),0),
    coalesce((select count(*) from public.stock_transfer_allocations_v485 a where a.transfer_id=t.id and a.serial_id is not null and a.status<>'released'),0),
    coalesce((select sum(a.quantity) from public.stock_transfer_allocations_v485 a where a.transfer_id=t.id and a.batch_id is not null and a.status<>'released'),0),
    coalesce(sum(case when t.status in('dispatched','in_transit') then greatest(i.dispatched_quantity-i.received_quantity,0) else 0 end),0),t.reservation_applied
  from public.stock_transfers t
  join public.business_locations fl on fl.id=t.from_location_id
  join public.business_locations tl on tl.id=t.to_location_id
  left join public.stock_transfer_items i on i.transfer_id=t.id
  where t.tenant_id=p_tenant_id
    and (p_location_id is null or t.from_location_id=p_location_id or t.to_location_id=p_location_id)
    and (p_status is null or trim(p_status)='' or (case when t.status='dispatched' then 'in_transit' else t.status end)=lower(trim(p_status)))
    and (trim(coalesce(p_query,''))='' or lower(t.transfer_number) like q or lower(fl.name) like q or lower(tl.name) like q or lower(coalesce(t.transport_reference,'')) like q or lower(coalesce(t.notes,'')) like q)
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all') or private.erp_user_location_allowed(p_tenant_id,t.from_location_id,'view') or private.erp_user_location_allowed(p_tenant_id,t.to_location_id,'view'))
  group by t.id,fl.location_code,fl.name,fl.hierarchy_role,fl.location_type,tl.location_code,tl.name,tl.hierarchy_role,tl.location_type
  order by t.created_at desc
  limit greatest(1,least(coalesce(p_limit,500),2000));
end$$;
grant execute on function public.inventory_transfers_list_v485(uuid,uuid,text,text,integer) to authenticated;

create or replace function public.inventory_transfer_history_v485(p_tenant_id uuid,p_transfer_id uuid)
returns table(event_id uuid,event_type text,from_status text,to_status text,note text,metadata jsonb,changed_by uuid,occurred_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_from uuid;v_to uuid;
begin
  select from_location_id,to_location_id into v_from,v_to from public.stock_transfers where tenant_id=p_tenant_id and id=p_transfer_id;
  if v_from is null then raise exception 'Transfer not found';end if;
  if not (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all') or private.erp_user_location_allowed(p_tenant_id,v_from,'view') or private.erp_user_location_allowed(p_tenant_id,v_to,'view')) then raise exception 'Access denied';end if;
  return query select h.id,h.event_type,h.from_status,h.to_status,h.note,h.metadata,h.changed_by,h.created_at
    from public.stock_transfer_history_v485 h where h.tenant_id=p_tenant_id and h.transfer_id=p_transfer_id order by h.created_at,h.id;
end$$;
grant execute on function public.inventory_transfer_history_v485(uuid,uuid) to authenticated;

create or replace function public.inventory_transfer_detail_v485(p_tenant_id uuid,p_transfer_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v jsonb;v_from uuid;v_to uuid;
begin
  select from_location_id,to_location_id into v_from,v_to from public.stock_transfers where tenant_id=p_tenant_id and id=p_transfer_id;
  if v_from is null then raise exception 'Transfer not found';end if;
  if not (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all') or private.erp_user_location_allowed(p_tenant_id,v_from,'view') or private.erp_user_location_allowed(p_tenant_id,v_to,'view')) then raise exception 'Access denied';end if;
  select jsonb_build_object(
    'transfer',to_jsonb(t)||jsonb_build_object(
      'status',case when t.status='dispatched' then 'in_transit' else t.status end,
      'from_location',fl.location_code||' • '||fl.name,'to_location',tl.location_code||' • '||tl.name,
      'from_is_warehouse',(fl.hierarchy_role='warehouse' or fl.location_type='warehouse'),
      'to_is_warehouse',(tl.hierarchy_role='warehouse' or tl.location_type='warehouse')
    ),
    'items',coalesce((select jsonb_agg(
      to_jsonb(i)||jsonb_build_object('product_name',p.name,'sku',pv.sku,
        'allocations',coalesce((select jsonb_agg(jsonb_build_object(
          'id',a.id,'status',a.status,'quantity',a.quantity,'serial_id',a.serial_id,'serial_number',s.serial_number,
          'batch_id',a.batch_id,'batch_number',b.batch_number,'expiry_on',b.expiry_on
        ) order by coalesce(s.serial_number,b.batch_number),a.id)
        from public.stock_transfer_allocations_v485 a
        left join public.inventory_serials_v483 s on s.id=a.serial_id
        left join public.inventory_batches_v483 b on b.id=a.batch_id
        where a.transfer_item_id=i.id),'[]'::jsonb))
      ) order by p.name,pv.sku)
      from public.stock_transfer_items i join public.product_variants pv on pv.id=i.variant_id join public.products p on p.id=pv.product_id where i.transfer_id=t.id),'[]'::jsonb),
    'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.created_at,h.id) from public.stock_transfer_history_v485 h where h.transfer_id=t.id),'[]'::jsonb)
  ) into v
  from public.stock_transfers t join public.business_locations fl on fl.id=t.from_location_id join public.business_locations tl on tl.id=t.to_location_id
  where t.tenant_id=p_tenant_id and t.id=p_transfer_id;
  return v;
end$$;
grant execute on function public.inventory_transfer_detail_v485(uuid,uuid) to authenticated;

create or replace function public.inventory_transfer_tracking_options_v485(
  p_tenant_id uuid,p_location_id uuid,p_variant_id uuid
) returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_mode text;v jsonb;
begin
  perform private.v4_location_access(p_tenant_id,p_location_id,'view');
  v_mode:=private.v483_tracking_mode(p_tenant_id,p_variant_id);
  if v_mode='serial' then
    select jsonb_build_object('tracking_mode','serial','serials',coalesce(jsonb_agg(jsonb_build_object('id',s.id,'serial_number',s.serial_number,'status',s.status) order by s.serial_number),'[]'::jsonb)) into v
    from public.inventory_serials_v483 s
    where s.tenant_id=p_tenant_id and s.variant_id=p_variant_id and s.current_location_id=p_location_id and s.status='in_stock' and s.reserved_transfer_id is null;
  elsif v_mode='batch' then
    select jsonb_build_object('tracking_mode','batch','batches',coalesce(jsonb_agg(jsonb_build_object(
      'id',b.id,'batch_number',b.batch_number,'manufactured_on',b.manufactured_on,'expiry_on',b.expiry_on,
      'quantity',bb.quantity,'reserved_quantity',coalesce(bb.reserved_quantity,0),'available_quantity',greatest(bb.quantity-coalesce(bb.reserved_quantity,0),0)
    ) order by (b.expiry_on is null),b.expiry_on,b.batch_number),'[]'::jsonb)) into v
    from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id
    where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and bb.location_id=p_location_id and bb.quantity-coalesce(bb.reserved_quantity,0)>0 and b.status in('active','quarantine');
  else
    v:=jsonb_build_object('tracking_mode','none','serials','[]'::jsonb,'batches','[]'::jsonb);
  end if;
  return coalesce(v,jsonb_build_object('tracking_mode',v_mode,'serials','[]'::jsonb,'batches','[]'::jsonb));
end$$;
grant execute on function public.inventory_transfer_tracking_options_v485(uuid,uuid,uuid) to authenticated;

create or replace function public.warehouse_inventory_v485(
  p_tenant_id uuid,p_location_id uuid default null,p_query text default '',p_limit integer default 1000
) returns table(
  location_id uuid,location_code text,location_name text,variant_id uuid,product_name text,sku text,tracking_mode text,
  on_hand numeric,reserved numeric,available numeric,damaged numeric,quarantine numeric,in_transit_in numeric,in_transit_out numeric,average_cost numeric
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';
begin
  perform private.warehouse_v485_permission(p_tenant_id,false);
  return query
  select l.id,l.location_code,l.name,b.variant_id,p.name,pv.sku,private.v483_tracking_mode(p_tenant_id,b.variant_id),
    b.quantity,b.reserved_quantity,greatest(b.quantity-b.reserved_quantity-b.damaged_quantity-b.quarantine_quantity,0),b.damaged_quantity,b.quarantine_quantity,
    coalesce((select sum(greatest(i.dispatched_quantity-i.received_quantity,0)) from public.stock_transfers t join public.stock_transfer_items i on i.transfer_id=t.id where t.tenant_id=p_tenant_id and t.to_location_id=l.id and i.variant_id=b.variant_id and t.status in('dispatched','in_transit')),0),
    coalesce((select sum(greatest(i.dispatched_quantity-i.received_quantity,0)) from public.stock_transfers t join public.stock_transfer_items i on i.transfer_id=t.id where t.tenant_id=p_tenant_id and t.from_location_id=l.id and i.variant_id=b.variant_id and t.status in('dispatched','in_transit')),0),b.average_cost
  from public.location_stock_balances b
  join public.business_locations l on l.id=b.location_id and l.tenant_id=b.tenant_id
  join public.product_variants pv on pv.id=b.variant_id and pv.tenant_id=b.tenant_id
  join public.products p on p.id=pv.product_id
  where b.tenant_id=p_tenant_id and l.active and (l.hierarchy_role='warehouse' or l.location_type='warehouse')
    and (p_location_id is null or l.id=p_location_id)
    and (trim(coalesce(p_query,''))='' or lower(p.name) like q or lower(pv.sku) like q or lower(coalesce(pv.barcode,'')) like q)
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all') or private.erp_user_location_allowed(p_tenant_id,l.id,'view'))
  order by l.name,p.name,pv.sku
  limit greatest(1,least(coalesce(p_limit,1000),5000));
end$$;
grant execute on function public.warehouse_inventory_v485(uuid,uuid,text,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(150,'4.8.5','Warehouse & Transfers','Transfer list/detail/history, available serial/batch allocation options, warehouse stock summary and in-transit inventory visibility.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.5 migration 150 transfer history/warehouse inventory applied' as status;
