-- THQ ERP V4.8.6 — idempotent offline sale synchronization with price/tax conflict protection.
begin;

create or replace function private.v486_offline_conflict(
  p_tenant_id uuid,p_device_id uuid,p_location_id uuid,p_request_id text,p_local text,p_code text,p_message text,p_payload jsonb
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  insert into public.pos_offline_sync_v486(
    tenant_id,request_id,device_id,location_id,local_invoice_number,status,conflict_code,conflict_message,payload_snapshot,attempts,last_attempt_at,created_by,updated_at
  ) values(
    p_tenant_id,trim(p_request_id),p_device_id,p_location_id,p_local,'conflict',p_code,p_message,coalesce(p_payload,'{}'::jsonb),1,now(),auth.uid(),now()
  ) on conflict(tenant_id,request_id) do update set
    status='conflict',conflict_code=excluded.conflict_code,conflict_message=excluded.conflict_message,payload_snapshot=excluded.payload_snapshot,
    attempts=public.pos_offline_sync_v486.attempts+1,last_attempt_at=now(),updated_at=now();
  return jsonb_build_object('ok',false,'status','conflict','code',p_code,'message',p_message,'request_id',trim(p_request_id),'local_invoice_number',p_local);
end$$;
revoke all on function private.v486_offline_conflict(uuid,uuid,uuid,text,text,text,text,jsonb) from public;

create or replace function public.pos_offline_sale_sync_v486(
  p_tenant_id uuid,p_device_id uuid,p_location_id uuid,p_request_id text,p_payload jsonb
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v_location uuid;v_existing jsonb;v_result jsonb;v_items jsonb;v_priced jsonb;v_client jsonb;v_server jsonb;
  v_i integer;v_client_price numeric;v_server_price numeric;v_client_tax numeric;v_server_tax numeric;v_variant uuid;
  v_customer uuid;v_sale_date date;v_due_date date;v_local text;v_message text;v_code text;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then raise exception 'Request ID is required';end if;
  v_location:=private.v486_pos_device_location(p_tenant_id,p_device_id,p_location_id);
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':offline:'||trim(p_request_id),0));

  select server_response into v_existing from public.pos_offline_sync_v486
  where tenant_id=p_tenant_id and request_id=trim(p_request_id) and status='synced';
  if v_existing is not null then return v_existing||jsonb_build_object('idempotent_replay',true);end if;

  v_items:=coalesce(p_payload->'items','[]'::jsonb);
  if jsonb_typeof(v_items)<>'array' or jsonb_array_length(v_items)=0 then raise exception 'Offline invoice has no items';end if;
  v_customer:=nullif(p_payload->>'customer_id','')::uuid;
  v_local:=nullif(trim(coalesce(p_payload->>'local_invoice_number','')),'');
  if v_customer is null or not exists(select 1 from public.customers c where c.id=v_customer and c.tenant_id=p_tenant_id and c.status='active') then
    return private.v486_offline_conflict(p_tenant_id,p_device_id,v_location,p_request_id,v_local,'CUSTOMER_UNAVAILABLE','Customer is no longer available.',p_payload);
  end if;
  v_sale_date:=coalesce(nullif(p_payload->>'sale_date','')::date,current_date);
  v_due_date:=nullif(p_payload->>'due_date','')::date;

  -- Re-resolve authoritative prices before posting. An issued offline receipt may never be silently repriced.
  v_priced:=private.v482_price_sale_items(p_tenant_id,v_customer,v_items,v_location);
  for v_i in 0..jsonb_array_length(v_items)-1 loop
    v_client:=v_items->v_i;v_server:=v_priced->v_i;
    v_variant:=nullif(v_client->>'variant_id','')::uuid;
    v_client_price:=coalesce(nullif(v_client->>'unit_price','')::numeric,0);
    v_server_price:=coalesce(nullif(v_server->>'unit_price','')::numeric,0);
    if abs(v_client_price-v_server_price)>0.005 then
      v_message:=format('Price changed for product %s. Offline %s, current %s.',v_variant,round(v_client_price,2),round(v_server_price,2));
      return private.v486_offline_conflict(p_tenant_id,p_device_id,v_location,p_request_id,v_local,'PRICE_CHANGED',v_message,p_payload);
    end if;
    select coalesce(pv.tax_rate,0) into v_server_tax from public.product_variants pv where pv.id=v_variant and pv.tenant_id=p_tenant_id;
    if not found then
      return private.v486_offline_conflict(p_tenant_id,p_device_id,v_location,p_request_id,v_local,'PRODUCT_UNAVAILABLE','A product on the offline invoice is no longer available.',p_payload);
    end if;
    v_client_tax:=coalesce(nullif(v_client->>'tax_rate','')::numeric,0);
    if abs(v_client_tax-v_server_tax)>0.0001 then
      v_message:=format('Tax changed for product %s. Offline %s, current %s.',v_variant,round(v_client_tax,4),round(v_server_tax,4));
      return private.v486_offline_conflict(p_tenant_id,p_device_id,v_location,p_request_id,v_local,'TAX_CHANGED',v_message,p_payload);
    end if;
  end loop;

  insert into public.pos_offline_sync_v486(tenant_id,request_id,device_id,location_id,local_invoice_number,status,payload_snapshot,attempts,last_attempt_at,created_by,updated_at)
  values(p_tenant_id,trim(p_request_id),p_device_id,v_location,v_local,'syncing',p_payload,1,now(),auth.uid(),now())
  on conflict(tenant_id,request_id) do update set status='syncing',payload_snapshot=excluded.payload_snapshot,attempts=public.pos_offline_sync_v486.attempts+1,last_attempt_at=now(),updated_at=now(),conflict_code=null,conflict_message=null;

  begin
    v_result:=public.sales_create_v483(
      p_tenant_id,v_customer,v_sale_date,v_due_date,v_items,
      coalesce(nullif(p_payload->>'additional_charges','')::numeric,0),
      coalesce(nullif(p_payload->>'initial_payment','')::numeric,0),
      coalesce(nullif(p_payload->>'payment_method',''),'cash'),
      coalesce(p_payload->>'payment_reference',''),
      trim(concat_ws(' • ',nullif(p_payload->>'notes',''),'Offline POS '||coalesce(v_local,''))),
      v_location,p_device_id,trim(p_request_id)
    );
  exception when others then
    v_message:=sqlerrm;
    if v_message ilike '%stock%' or v_message ilike '%serial%' or v_message ilike '%batch%' or v_message ilike '%reconciled%' then v_code:='STOCK_CONFLICT';
    else v_code:='SERVER_VALIDATION';end if;
    return private.v486_offline_conflict(p_tenant_id,p_device_id,v_location,p_request_id,v_local,v_code,v_message,p_payload);
  end;

  v_result:=coalesce(v_result,'{}'::jsonb)||jsonb_build_object('ok',true,'status','synced','request_id',trim(p_request_id),'local_invoice_number',v_local,'offline_sync','v4.8.6');
  update public.pos_offline_sync_v486 set status='synced',server_response=v_result,conflict_code=null,conflict_message=null,synced_at=now(),last_attempt_at=now(),updated_at=now()
  where tenant_id=p_tenant_id and request_id=trim(p_request_id);
  return v_result;
end$$;
grant execute on function public.pos_offline_sale_sync_v486(uuid,uuid,uuid,text,jsonb) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(155,'4.8.6','Offline POS','Local invoice sync endpoint with request-id idempotency, authoritative price/tax conflict detection and trace-aware sale posting.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.6 migration 155 offline sale sync applied' as status;
