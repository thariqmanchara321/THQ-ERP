create or replace function public.logistics_exceptions_list_v1(p_tenant_id uuid,p_location_id uuid default null,p_status text default null,p_trip_id uuid default null,p_limit integer default 500)
returns setof jsonb language plpgsql stable security definer set search_path to 'public','private','pg_temp' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
 if not (private.erp_user_is_owner(p_tenant_id,auth.uid()) or private.erp_has_permission(p_tenant_id,'transport_service.view') or private.erp_has_permission(p_tenant_id,'transport_service.create') or private.erp_has_permission(p_tenant_id,'transport_service.manage') or private.erp_has_permission(p_tenant_id,'inventory.transfer') or private.erp_has_permission(p_tenant_id,'inventory.manage')) then raise exception 'Logistics view permission required'; end if;
 return query
 select jsonb_build_object(
  'id',e.id,'trip_id',e.trip_id,'trip_number',t.trip_number,
  'receipt_id',e.receipt_id,'receipt_number',r.receipt_number,
  'stock_transfer_id',e.stock_transfer_id,'transfer_number',st.transfer_number,
  'variant_id',e.variant_id,'product_name',p.name,'sku',pv.sku,
  'exception_type',e.exception_type,'quantity',e.quantity,'status',e.status,
  'resolution_code',e.resolution_code,'resolution_note',e.resolution_note,
  'external_reference',e.external_reference,'opened_at',e.opened_at,'resolved_at',e.resolved_at,
  'from_location',fl.location_code||' • '||fl.name,'to_location',tl.location_code||' • '||tl.name,
  'vehicle_registration',v.registration_number)
 from public.transport_logistics_exceptions e
 join public.transport_logistics_trips t on t.id=e.trip_id and t.tenant_id=e.tenant_id
 join public.transport_logistics_receipts r on r.id=e.receipt_id and r.tenant_id=e.tenant_id
 join public.stock_transfers st on st.id=e.stock_transfer_id and st.tenant_id=e.tenant_id
 join public.product_variants pv on pv.id=e.variant_id
 join public.products p on p.id=pv.product_id
 join public.service_vehicles v on v.id=t.vehicle_id and v.tenant_id=t.tenant_id
 join public.business_locations fl on fl.id=t.from_location_id and fl.tenant_id=t.tenant_id
 join public.business_locations tl on tl.id=t.to_location_id and tl.tenant_id=t.tenant_id
 where e.tenant_id=p_tenant_id
 and (p_trip_id is null or e.trip_id=p_trip_id)
 and (p_status is null or trim(p_status)='' or e.status=lower(trim(p_status)))
 and (p_location_id is null or t.from_location_id=p_location_id or t.to_location_id=p_location_id)
 and (private.erp_document_scope_allowed(p_tenant_id,t.from_location_id,p_location_id,'view') or private.erp_document_scope_allowed(p_tenant_id,t.to_location_id,p_location_id,'view'))
 order by case when e.status in ('open','investigating') then 0 else 1 end,e.opened_at desc
 limit greatest(1,least(coalesce(p_limit,500),2000));
end $$;;
