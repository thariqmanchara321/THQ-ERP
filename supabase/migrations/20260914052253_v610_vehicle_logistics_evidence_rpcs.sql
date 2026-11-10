create or replace function public.logistics_evidence_register_v1(
  p_tenant_id uuid,
  p_trip_id uuid,
  p_evidence_type text,
  p_file_name text,
  p_storage_path text,
  p_mime_type text,
  p_file_size bigint,
  p_note text default null,
  p_stock_transfer_id uuid default null,
  p_receipt_id uuid default null,
  p_captured_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','storage','pg_temp'
as $$
declare
  t public.transport_logistics_trips%rowtype;
  v_id uuid;
  v_type text:=lower(trim(coalesce(p_evidence_type,'')));
  v_path text:=trim(coalesce(p_storage_path,''));
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not (
    private.erp_user_is_owner(p_tenant_id,auth.uid())
    or private.erp_has_permission(p_tenant_id,'transport_service.create')
    or private.erp_has_permission(p_tenant_id,'transport_service.manage')
    or private.erp_has_permission(p_tenant_id,'inventory.transfer')
    or private.erp_has_permission(p_tenant_id,'inventory.manage')
  ) then raise exception 'Logistics evidence permission required'; end if;
  select * into t from public.transport_logistics_trips where id=p_trip_id and tenant_id=p_tenant_id;
  if not found then raise exception 'Trip not found'; end if;
  if v_type='dispatch_photo' then
    perform private.v4_location_access(p_tenant_id,t.from_location_id,'operate');
  else
    perform private.v4_location_access(p_tenant_id,t.to_location_id,'operate');
  end if;
  if v_type not in ('dispatch_photo','arrival_photo','delivery_photo','damage_photo','receiver_signature','other') then raise exception 'Invalid evidence type'; end if;
  if trim(coalesce(p_file_name,''))='' then raise exception 'File name is required'; end if;
  if lower(trim(coalesce(p_mime_type,''))) not in ('image/jpeg','image/png') then raise exception 'Only JPEG or PNG evidence is allowed'; end if;
  if coalesce(p_file_size,0)<=0 or p_file_size>5242880 then raise exception 'Evidence file must be between 1 byte and 5 MB'; end if;
  if v_path not like p_tenant_id::text||'/logistics/'||p_trip_id::text||'/%' then raise exception 'Invalid evidence storage path'; end if;
  if not exists(select 1 from storage.objects o where o.bucket_id='thq-assets' and o.name=v_path) then raise exception 'Evidence file was not uploaded'; end if;
  if p_stock_transfer_id is not null and not exists(select 1 from public.transport_logistics_trip_documents d where d.tenant_id=p_tenant_id and d.trip_id=p_trip_id and d.stock_transfer_id=p_stock_transfer_id and d.active) then raise exception 'Stock transfer is not linked to this trip'; end if;
  if p_receipt_id is not null and not exists(select 1 from public.transport_logistics_receipts r where r.tenant_id=p_tenant_id and r.trip_id=p_trip_id and r.id=p_receipt_id and (p_stock_transfer_id is null or r.stock_transfer_id=p_stock_transfer_id)) then raise exception 'Receipt is not linked to this trip'; end if;
  insert into public.transport_logistics_evidence(tenant_id,trip_id,stock_transfer_id,receipt_id,evidence_type,file_name,storage_path,mime_type,file_size,note,captured_at,created_by)
  values(p_tenant_id,p_trip_id,p_stock_transfer_id,p_receipt_id,v_type,trim(p_file_name),v_path,lower(trim(p_mime_type)),p_file_size,nullif(trim(coalesce(p_note,'')),''),coalesce(p_captured_at,now()),auth.uid())
  returning id into v_id;
  insert into public.transport_logistics_trip_events(tenant_id,trip_id,event_type,from_status,to_status,event_data,actor_user_id)
  values(p_tenant_id,p_trip_id,'evidence_added',t.status,t.status,jsonb_build_object('evidence_id',v_id,'evidence_type',v_type,'file_name',trim(p_file_name),'stock_transfer_id',p_stock_transfer_id,'receipt_id',p_receipt_id),auth.uid());
  perform private.business_audit_write_v471(p_tenant_id,'logistics.evidence.add','transport_logistics_evidence',v_id,t.trip_number,null,(select to_jsonb(e) from public.transport_logistics_evidence e where e.id=v_id));
  return jsonb_build_object('success',true,'evidence_id',v_id,'trip_id',p_trip_id,'evidence_type',v_type,'storage_path',v_path);
end
$$;

create or replace function public.logistics_evidence_list_v1(p_tenant_id uuid,p_trip_id uuid)
returns setof jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $$
declare t public.transport_logistics_trips%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not (
    private.erp_user_is_owner(p_tenant_id,auth.uid())
    or private.erp_has_permission(p_tenant_id,'transport_service.view')
    or private.erp_has_permission(p_tenant_id,'transport_service.create')
    or private.erp_has_permission(p_tenant_id,'transport_service.manage')
    or private.erp_has_permission(p_tenant_id,'inventory.transfer')
    or private.erp_has_permission(p_tenant_id,'inventory.manage')
  ) then raise exception 'Logistics view permission required'; end if;
  select * into t from public.transport_logistics_trips where id=p_trip_id and tenant_id=p_tenant_id;
  if not found then raise exception 'Trip not found'; end if;
  if not (private.erp_document_scope_allowed(p_tenant_id,t.from_location_id,null,'view') or private.erp_document_scope_allowed(p_tenant_id,t.to_location_id,null,'view')) then raise exception 'Location access denied'; end if;
  return query
  select jsonb_build_object('id',e.id,'trip_id',e.trip_id,'stock_transfer_id',e.stock_transfer_id,'receipt_id',e.receipt_id,'evidence_type',e.evidence_type,'file_name',e.file_name,'storage_path',e.storage_path,'mime_type',e.mime_type,'file_size',e.file_size,'note',e.note,'captured_at',e.captured_at,'created_by',e.created_by,'created_at',e.created_at)
  from public.transport_logistics_evidence e
  where e.tenant_id=p_tenant_id and e.trip_id=p_trip_id
  order by e.captured_at desc,e.created_at desc;
end
$$;

revoke all on function public.logistics_evidence_register_v1(uuid,uuid,text,text,text,text,bigint,text,uuid,uuid,timestamptz) from public, anon;
revoke all on function public.logistics_evidence_list_v1(uuid,uuid) from public, anon;
grant execute on function public.logistics_evidence_register_v1(uuid,uuid,text,text,text,text,bigint,text,uuid,uuid,timestamptz) to authenticated, service_role;
grant execute on function public.logistics_evidence_list_v1(uuid,uuid) to authenticated, service_role;;
