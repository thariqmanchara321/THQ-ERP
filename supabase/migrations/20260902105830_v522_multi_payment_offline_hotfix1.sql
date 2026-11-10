-- THQ ERP v5.2.2 Build 30 offline POS wire-compatibility hotfix.
-- Repository companion to 260_v522_multi_payment.sql.

create or replace function public.gst_pos_offline_sale_sync_v522(
  p_tenant_id uuid,
  p_device_id uuid,
  p_location_id uuid,
  p_request_id text,
  p_payload jsonb
) returns jsonb
language plpgsql security definer
set search_path=public,private,pg_temp
as $$
declare
  v_request text:=nullif(trim(coalesce(p_request_id,'')),'');
  v_location uuid;v_identity jsonb;v_hash text;q public.pos_offline_sync_v486%rowtype;
  v_items jsonb;v_priced jsonb;v_post_priced jsonb;v_client jsonb;v_server jsonb;
  v_i integer;v_client_price numeric;v_server_price numeric;v_client_tax numeric;v_server_tax numeric;
  v_variant uuid;v_customer uuid;v_sale_date date;v_due_date date;v_local text;v_message text;v_code text;
  v_profile public.gst_product_tax_profiles_v520%rowtype;v_product_tax numeric;
  v_result jsonb;v_sale_id uuid;v_snapshot uuid;v_journal uuid;v_sale_request text;
  v_allocations jsonb;
begin
  if v_request is null then raise exception 'Request ID is required'; end if;
  if length(v_request)>160 then raise exception 'Offline v5.2.2 request ID is too long'; end if;
  v_location:=private.v486_pos_device_location(p_tenant_id,p_device_id,p_location_id);
  perform private.erp_validate_transaction_origin(p_tenant_id,v_location,p_device_id,'sales');

  if coalesce(nullif(p_payload->>'additional_charges','')::numeric,0)<>0 then
    return private.v520_offline_conflict(p_tenant_id,p_device_id,v_location,v_request,
      private.gst_request_hash_v520(jsonb_build_object('device_id',p_device_id,'location_id',v_location,'payload',coalesce(p_payload,'{}'::jsonb))),
      nullif(trim(coalesce(p_payload->>'local_invoice_number','')),''),
      'UNCLASSIFIED_CHARGE','Additional Charges are not supported. Add a GST-classified Service product instead.',p_payload);
  end if;

  v_identity:=jsonb_build_object('device_id',p_device_id,'location_id',v_location,'payload',coalesce(p_payload,'{}'::jsonb));
  v_hash:=private.gst_request_hash_v520(v_identity);
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':offline-v522:'||v_request,0));

  select * into q from public.pos_offline_sync_v486
  where tenant_id=p_tenant_id and request_id=v_request for update;
  if found then
    if coalesce(q.sync_contract_version,'v4.8.6') not in ('v5.2.2','v5.2') then
      raise exception 'Request ID already belongs to a legacy Offline POS sync contract';
    end if;
    if q.request_hash is distinct from v_hash or q.device_id is distinct from p_device_id or
       q.location_id is distinct from v_location or q.payload_snapshot is distinct from coalesce(p_payload,'{}'::jsonb) then
      raise exception 'Request ID was already used with a different Offline POS device, location, or payload';
    end if;
    if q.status='synced' then
      if q.server_response is null or q.sale_id is null or q.gst_snapshot_id is null or q.gst_journal_id is null then
        raise exception 'Synced v5.2.2 Offline POS request is missing authoritative recovery evidence';
      end if;
      return q.server_response||jsonb_build_object('idempotent_replay',true);
    end if;
    if q.status='cancelled' then raise exception 'Cancelled Offline POS request cannot be reused'; end if;
  end if;

  v_items:=coalesce(p_payload->'items','[]'::jsonb);
  if jsonb_typeof(v_items)<>'array' or jsonb_array_length(v_items)=0 then raise exception 'Offline invoice has no items'; end if;
  v_customer:=nullif(p_payload->>'customer_id','')::uuid;
  v_local:=nullif(trim(coalesce(p_payload->>'local_invoice_number','')),'');
  if v_customer is null or not exists(select 1 from public.customers c where c.id=v_customer and c.tenant_id=p_tenant_id and c.status='active') then
    return private.v520_offline_conflict(p_tenant_id,p_device_id,v_location,v_request,v_hash,v_local,'CUSTOMER_UNAVAILABLE','Customer is no longer available.',p_payload);
  end if;

  v_sale_date:=coalesce(nullif(p_payload->>'sale_date','')::date,current_date);
  v_due_date:=nullif(p_payload->>'due_date','')::date;
  v_allocations:=coalesce(p_payload->'payment_allocations','[]'::jsonb);
  if jsonb_typeof(v_allocations)<>'array' or jsonb_array_length(v_allocations)=0 then
    return private.v520_offline_conflict(p_tenant_id,p_device_id,v_location,v_request,v_hash,v_local,'PAYMENT_ALLOCATION_REQUIRED','Build 30 offline invoices require payment_allocations.',p_payload);
  end if;

  v_priced:=private.v482_price_sale_items(p_tenant_id,v_customer,v_items,v_location);
  for v_i in 0..jsonb_array_length(v_items)-1 loop
    v_client:=v_items->v_i;v_server:=v_priced->v_i;v_variant:=nullif(v_client->>'variant_id','')::uuid;
    v_client_price:=coalesce(nullif(v_client->>'unit_price','')::numeric,0);v_server_price:=coalesce(nullif(v_server->>'unit_price','')::numeric,0);
    if abs(v_client_price-v_server_price)>0.005 then
      v_message:=format('Price changed for product %s. Offline %s, current %s.',v_variant,round(v_client_price,2),round(v_server_price,2));
      return private.v520_offline_conflict(p_tenant_id,p_device_id,v_location,v_request,v_hash,v_local,'PRICE_CHANGED',v_message,p_payload);
    end if;
    select p.tax_rate into v_product_tax from public.product_variants pv join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id
    where pv.id=v_variant and pv.tenant_id=p_tenant_id;
    if not found then return private.v520_offline_conflict(p_tenant_id,p_device_id,v_location,v_request,v_hash,v_local,'PRODUCT_UNAVAILABLE','A product on the offline invoice is no longer available.',p_payload); end if;
    select * into v_profile from private.gst_profile_for_variant_v520(p_tenant_id,v_variant,v_sale_date);
    v_server_tax:=case when v_profile.id is null then coalesce(v_product_tax,0) when v_profile.taxability='taxable' then coalesce(v_profile.gst_rate,0) else 0 end;
    v_client_tax:=coalesce(nullif(v_client->>'tax_rate','')::numeric,0);
    if abs(v_client_tax-v_server_tax)>0.0001 then
      v_message:=format('Tax changed for product %s. Offline %s, current %s.',v_variant,round(v_client_tax,4),round(v_server_tax,4));
      return private.v520_offline_conflict(p_tenant_id,p_device_id,v_location,v_request,v_hash,v_local,'TAX_CHANGED',v_message,p_payload);
    end if;
  end loop;

  insert into public.pos_offline_sync_v486(tenant_id,request_id,device_id,location_id,local_invoice_number,status,payload_snapshot,attempts,last_attempt_at,created_by,updated_at,sync_contract_version,request_hash)
  values(p_tenant_id,v_request,p_device_id,v_location,v_local,'syncing',p_payload,1,now(),auth.uid(),now(),'v5.2.2',v_hash)
  on conflict(tenant_id,request_id) do update set status='syncing',attempts=public.pos_offline_sync_v486.attempts+1,last_attempt_at=now(),updated_at=now(),conflict_code=null,conflict_message=null;

  begin
    v_sale_request:='offline-v522:'||v_request;
    v_result:=public.gst_sale_create_v522(p_tenant_id,v_customer,v_sale_date,v_due_date,v_items,v_allocations,
      trim(concat_ws(' • ',nullif(p_payload->>'notes',''),'Offline POS '||coalesce(v_local,''))),v_location,p_device_id,v_sale_request,
      nullif(p_payload->>'supply_type',''),nullif(p_payload->>'place_of_supply_code',''));
    v_sale_id:=nullif(v_result->>'sale_id','')::uuid;v_snapshot:=nullif(v_result->>'gst_snapshot_id','')::uuid;v_journal:=nullif(v_result->>'journal_id','')::uuid;
    if v_sale_id is null or v_snapshot is null or v_journal is null then raise exception 'Authoritative GST Sale did not return complete evidence'; end if;

    v_post_priced:=private.v482_price_sale_items(p_tenant_id,v_customer,v_items,v_location);
    for v_i in 0..jsonb_array_length(v_items)-1 loop
      v_client:=v_items->v_i;v_server:=v_post_priced->v_i;v_variant:=nullif(v_client->>'variant_id','')::uuid;
      v_client_price:=coalesce(nullif(v_client->>'unit_price','')::numeric,0);v_server_price:=coalesce(nullif(v_server->>'unit_price','')::numeric,0);
      if abs(v_client_price-v_server_price)>0.005 then raise exception 'OFFLINE_PRICE_CHANGED: product % changed during sync',v_variant; end if;
      select p.tax_rate into v_product_tax from public.product_variants pv join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id where pv.id=v_variant and pv.tenant_id=p_tenant_id;
      select * into v_profile from private.gst_profile_for_variant_v520(p_tenant_id,v_variant,v_sale_date);
      v_server_tax:=case when v_profile.id is null then coalesce(v_product_tax,0) when v_profile.taxability='taxable' then coalesce(v_profile.gst_rate,0) else 0 end;
      v_client_tax:=coalesce(nullif(v_client->>'tax_rate','')::numeric,0);
      if abs(v_client_tax-v_server_tax)>0.0001 then raise exception 'OFFLINE_TAX_CHANGED: product % changed during sync',v_variant; end if;
    end loop;
  exception when others then
    v_message:=sqlerrm;
    if v_message like 'OFFLINE_PRICE_CHANGED:%' then v_code:='PRICE_CHANGED';
    elsif v_message like 'OFFLINE_TAX_CHANGED:%' then v_code:='TAX_CHANGED';
    elsif v_message ilike '%stock%' or v_message ilike '%serial%' or v_message ilike '%batch%' or v_message ilike '%reconciled%' then v_code:='STOCK_CONFLICT';
    elsif v_message ilike '%payment%' or v_message ilike '%credit%' or v_message ilike '%ledger%' then v_code:='PAYMENT_CONFLICT';
    else v_code:='SERVER_VALIDATION'; end if;
    return private.v520_offline_conflict(p_tenant_id,p_device_id,v_location,v_request,v_hash,v_local,v_code,v_message,p_payload);
  end;

  v_result:=coalesce(v_result,'{}'::jsonb)||jsonb_build_object('ok',true,'status','synced','request_id',v_request,'local_invoice_number',v_local,
    'offline_sync','v5.2.2','offline_contract','authoritative_gst_multi_payment','authoritative_gst',true,'gst_journal_id',v_journal);
  update public.pos_offline_sync_v486 set status='synced',server_response=v_result,conflict_code=null,conflict_message=null,sale_id=v_sale_id,
    gst_snapshot_id=v_snapshot,gst_journal_id=v_journal,synced_at=now(),last_attempt_at=now(),updated_at=now(),sync_contract_version='v5.2.2'
  where tenant_id=p_tenant_id and request_id=v_request;
  return v_result;
end;
$$;

drop function if exists public.gst_pos_offline_sale_sync_v522(jsonb);
create or replace function public.gst_mobile_pos_sale_sync_v522(
  p_tenant_id uuid,p_device_id uuid,p_location_id uuid,p_request_id text,p_payload jsonb
) returns jsonb language sql security definer set search_path=public,pg_temp as $$
  select public.gst_pos_offline_sale_sync_v522(p_tenant_id,p_device_id,p_location_id,p_request_id,p_payload);
$$;
drop function if exists public.gst_mobile_pos_sale_sync_v522(jsonb);

create or replace function public.gst_transaction_cutover_contract_v522(p_tenant_id uuid,p_channel text default 'client',p_device_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v jsonb;v_channel text:=lower(trim(coalesce(p_channel,'client')));
begin
  v:=public.gst_transaction_cutover_contract_v520(p_tenant_id,p_channel,p_device_id);
  if v_channel='client' then
    v:=jsonb_set(v,'{channel_routes}',coalesce(v->'channel_routes','{}'::jsonb)||jsonb_build_object('sale','gst_sale_create_v522'),true);
  elsif v_channel='pos' then
    v:=jsonb_set(v,'{channel_routes}',coalesce(v->'channel_routes','{}'::jsonb)||jsonb_build_object('sale','gst_pos_sale_create_v522'),true);
  elsif v_channel in ('pos_offline','offline_pos') then
    v:=jsonb_set(v,'{channel_routes}',coalesce(v->'channel_routes','{}'::jsonb)||jsonb_build_object('sale_sync','gst_pos_offline_sale_sync_v522'),true);
  elsif v_channel='mobile_pos' then
    v:=jsonb_set(v,'{channel_routes}',coalesce(v->'channel_routes','{}'::jsonb)||jsonb_build_object('sale_sync','gst_mobile_pos_sale_sync_v522'),true);
  end if;
  v:=v||jsonb_build_object('version','5.2.2','build',30,'multi_payment',true,'automatic_round_off',true,
    'legacy_fallback_after_v522_failure',false,'additional_charges','service_products_only',
    'payment_methods',jsonb_build_array('cash','upi','card','bank','cheque','wallet','credit','other'));
  return v;
end;
$$;

grant execute on function public.gst_pos_offline_sale_sync_v522(uuid,uuid,uuid,text,jsonb) to authenticated;
grant execute on function public.gst_mobile_pos_sale_sync_v522(uuid,uuid,uuid,text,jsonb) to authenticated;
;
