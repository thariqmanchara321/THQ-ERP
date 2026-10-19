create or replace function public.logistics_operations_trips_v1(p_tenant_id uuid,p_location_id uuid default null,p_limit integer default 500)
returns setof jsonb language plpgsql stable security definer set search_path to 'public','private','pg_temp' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
 if not (private.erp_user_is_owner(p_tenant_id,auth.uid()) or private.erp_has_permission(p_tenant_id,'transport_service.view') or private.erp_has_permission(p_tenant_id,'transport_service.create') or private.erp_has_permission(p_tenant_id,'transport_service.manage') or private.erp_has_permission(p_tenant_id,'inventory.transfer') or private.erp_has_permission(p_tenant_id,'inventory.manage')) then raise exception 'Logistics view permission required'; end if;
 return query
 select jsonb_build_object(
  'id',t.id,'trip_number',t.trip_number,'status',t.status,
  'vehicle_registration',v.registration_number,'driver_name',t.driver_name,
  'from_location',fl.location_code||' • '||fl.name,'to_location',tl.location_code||' • '||tl.name,
  'planned_departure_at',t.planned_departure_at,'expected_arrival_date',eta.expected_arrival_date,
  'is_overdue',case when t.status in ('planned','loading') and t.planned_departure_at is not null and t.planned_departure_at<now() then true when t.status='in_transit' and eta.expected_arrival_date is not null and eta.expected_arrival_date<current_date then true else false end,
  'overdue_kind',case when t.status in ('planned','loading') and t.planned_departure_at is not null and t.planned_departure_at<now() then 'departure' when t.status='in_transit' and eta.expected_arrival_date is not null and eta.expected_arrival_date<current_date then 'arrival' else null end,
  'evidence_count',(select count(*) from public.transport_logistics_evidence x where x.tenant_id=t.tenant_id and x.trip_id=t.id),
  'open_exception_count',(select count(*) from public.transport_logistics_exceptions x where x.tenant_id=t.tenant_id and x.trip_id=t.id and x.status in ('open','investigating'))
 )
 from public.transport_logistics_trips t
 join public.service_vehicles v on v.id=t.vehicle_id and v.tenant_id=t.tenant_id
 join public.business_locations fl on fl.id=t.from_location_id and fl.tenant_id=t.tenant_id
 join public.business_locations tl on tl.id=t.to_location_id and tl.tenant_id=t.tenant_id
 left join lateral (select min(st.expected_arrival_date) expected_arrival_date from public.transport_logistics_trip_documents d join public.stock_transfers st on st.id=d.stock_transfer_id and st.tenant_id=d.tenant_id where d.trip_id=t.id and d.active and st.expected_arrival_date is not null) eta on true
 where t.tenant_id=p_tenant_id
 and (p_location_id is null or t.from_location_id=p_location_id or t.to_location_id=p_location_id)
 and (private.erp_document_scope_allowed(p_tenant_id,t.from_location_id,p_location_id,'view') or private.erp_document_scope_allowed(p_tenant_id,t.to_location_id,p_location_id,'view'))
 order by case when ((t.status in ('planned','loading') and t.planned_departure_at is not null and t.planned_departure_at<now()) or (t.status='in_transit' and eta.expected_arrival_date is not null and eta.expected_arrival_date<current_date)) then 0 else 1 end,t.created_at desc
 limit greatest(1,least(coalesce(p_limit,500),2000));
end $$;
revoke all on function public.logistics_operations_trips_v1(uuid,uuid,integer) from public, anon;
grant execute on function public.logistics_operations_trips_v1(uuid,uuid,integer) to authenticated, service_role;;
