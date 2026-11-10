create or replace function public.logistics_exception_update_v1(p_tenant_id uuid,p_exception_id uuid,p_status text,p_resolution_code text default null,p_resolution_note text default null,p_external_reference text default null)
returns jsonb language plpgsql security definer set search_path to 'public','private','pg_temp' as $$
declare
 e public.transport_logistics_exceptions%rowtype;
 a public.transport_logistics_exceptions%rowtype;
 t public.transport_logistics_trips%rowtype;
 s text:=lower(trim(coalesce(p_status,'')));
 b jsonb;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
 if not (private.erp_user_is_owner(p_tenant_id,auth.uid()) or private.erp_has_permission(p_tenant_id,'transport_service.manage') or private.erp_has_permission(p_tenant_id,'inventory.manage')) then raise exception 'Logistics exception management permission required'; end if;
 select * into e from public.transport_logistics_exceptions where id=p_exception_id and tenant_id=p_tenant_id for update;
 if not found then raise exception 'Logistics exception not found'; end if;
 select * into t from public.transport_logistics_trips where id=e.trip_id and tenant_id=p_tenant_id;
 if not found then raise exception 'Trip not found'; end if;
 perform private.v4_location_access(p_tenant_id,t.to_location_id,'operate');
 if s not in ('open','investigating','resolved','waived') then raise exception 'Invalid exception status'; end if;
 if s in ('resolved','waived') and trim(coalesce(p_resolution_code,''))='' then raise exception 'Resolution code is required'; end if;
 if s in ('resolved','waived') and trim(coalesce(p_resolution_note,''))='' then raise exception 'Resolution note is required'; end if;
 b:=to_jsonb(e);
 update public.transport_logistics_exceptions set status=s,resolution_code=nullif(trim(coalesce(p_resolution_code,'')),''),resolution_note=nullif(trim(coalesce(p_resolution_note,'')),''),external_reference=nullif(trim(coalesce(p_external_reference,'')),''),resolved_at=case when s in ('resolved','waived') then coalesce(resolved_at,now()) else null end,resolved_by=case when s in ('resolved','waived') then auth.uid() else null end,updated_at=now(),updated_by=auth.uid() where id=e.id returning * into a;
 insert into public.transport_logistics_trip_events(tenant_id,trip_id,event_type,from_status,to_status,event_data,actor_user_id) values(p_tenant_id,e.trip_id,'exception_status_changed',t.status,t.status,jsonb_build_object('exception_id',e.id,'exception_type',e.exception_type,'quantity',e.quantity,'from_exception_status',e.status,'to_exception_status',a.status,'resolution_code',a.resolution_code,'external_reference',a.external_reference),auth.uid());
 perform private.business_audit_write_v471(p_tenant_id,'logistics.exception.update','transport_logistics_exception',e.id,t.trip_number,b,to_jsonb(a));
 return jsonb_build_object('success',true,'exception_id',a.id,'trip_id',a.trip_id,'status',a.status,'resolution_code',a.resolution_code,'resolved_at',a.resolved_at);
end $$;
revoke all on function public.logistics_exception_update_v1(uuid,uuid,text,text,text,text) from public, anon;
grant execute on function public.logistics_exception_update_v1(uuid,uuid,text,text,text,text) to authenticated, service_role;;
