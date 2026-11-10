create or replace function public.logistics_transfer_receipt_context_v1(
  p_tenant_id uuid,
  p_trip_id uuid,
  p_transfer_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $function$
declare
  t public.transport_logistics_trips%rowtype;
  st public.stock_transfers%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;

  select * into t from public.transport_logistics_trips where id=p_trip_id and tenant_id=p_tenant_id;
  if not found then raise exception 'Trip not found'; end if;

  if not exists (
    select 1 from public.transport_logistics_trip_documents d
    where d.tenant_id=p_tenant_id and d.trip_id=p_trip_id and d.stock_transfer_id=p_transfer_id and d.active
  ) then raise exception 'Transfer is not linked to this trip'; end if;

  select * into st from public.stock_transfers where tenant_id=p_tenant_id and id=p_transfer_id;
  if not found then raise exception 'Transfer not found'; end if;

  if not (
    private.erp_document_scope_allowed(p_tenant_id,st.from_location_id,null,'view')
    or private.erp_document_scope_allowed(p_tenant_id,st.to_location_id,null,'view')
  ) then raise exception 'Location access denied'; end if;

  return jsonb_build_object(
    'trip_id',p_trip_id,
    'trip_number',t.trip_number,
    'trip_status',t.status,
    'transfer_id',st.id,
    'transfer_number',st.transfer_number,
    'transfer_status',case when st.status='dispatched' then 'in_transit' else st.status end,
    'from_location_id',st.from_location_id,
    'to_location_id',st.to_location_id,
    'items',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',i.id,
          'variant_id',i.variant_id,
          'product_name',p.name,
          'sku',pv.sku,
          'tracking_mode',i.tracking_mode,
          'dispatched_quantity',i.dispatched_quantity,
          'allocations',coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id',a.id,
                'quantity',a.quantity,
                'status',a.status,
                'serial_id',a.serial_id,
                'serial_number',s.serial_number,
                'batch_id',a.batch_id,
                'batch_number',b.batch_number
              ) order by coalesce(s.serial_number,b.batch_number,a.id::text)
            )
            from public.stock_transfer_allocations_v485 a
            left join public.inventory_serials_v483 s on s.id=a.serial_id
            left join public.inventory_batches_v483 b on b.id=a.batch_id
            where a.transfer_item_id=i.id and a.status='in_transit'
          ),'[]'::jsonb)
        ) order by p.name,pv.sku
      )
      from public.stock_transfer_items i
      join public.product_variants pv on pv.id=i.variant_id
      join public.products p on p.id=pv.product_id
      where i.transfer_id=st.id
    ),'[]'::jsonb)
  );
end
$function$;

revoke execute on function public.logistics_transfer_receipt_context_v1(uuid,uuid,uuid) from public, anon;
grant execute on function public.logistics_transfer_receipt_context_v1(uuid,uuid,uuid) to authenticated, service_role;;
