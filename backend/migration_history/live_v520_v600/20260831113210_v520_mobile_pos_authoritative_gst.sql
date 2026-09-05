create table if not exists private.mobile_pos_kot_requests_v520 (
  tenant_id uuid not null,
  request_id text not null,
  request_hash text not null,
  device_id uuid not null,
  location_id uuid not null,
  payload jsonb not null default '{}'::jsonb,
  order_id uuid,
  kot_id uuid,
  response jsonb,
  status text not null default 'processing' check (status in ('processing','sent')),
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, request_id),
  check (length(request_id) between 1 and 160)
);

revoke all on table private.mobile_pos_kot_requests_v520 from public, anon, authenticated, service_role;

create or replace function public.mobile_pos_product_cache_v520(
  p_tenant_id uuid,
  p_device_id uuid
) returns jsonb
language plpgsql
stable security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_base jsonb;
  v_result jsonb;
begin
  perform private.v488_mobile_pos_location(p_tenant_id,p_device_id);
  v_base:=public.pos_offline_product_cache_v486(p_tenant_id,p_device_id);

  select coalesce(jsonb_agg(
    case
      when nullif(e->'gst_profile'->>'profile_id','') is not null then
        e || jsonb_build_object(
          'tax_rate',case
            when lower(coalesce(e->'gst_profile'->>'taxability',''))='taxable'
              then coalesce(nullif(e->'gst_profile'->>'gst_rate','')::numeric,0)
            else 0
          end,
          'tax_source','gst_profile_v520'
        )
      else
        e || jsonb_build_object(
          'tax_rate',coalesce(nullif(e->>'tax_rate','')::numeric,0),
          'tax_source','legacy_fallback'
        )
    end
    order by e->>'product_name',e->>'sku'
  ),'[]'::jsonb)
  into v_result
  from jsonb_array_elements(coalesce(v_base,'[]'::jsonb)) e;

  return coalesce(v_result,'[]'::jsonb);
end
$function$;

create or replace function public.mobile_pos_terminal_context_v520(
  p_tenant_id uuid,
  p_device_id uuid
) returns jsonb
language plpgsql
stable security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_base jsonb;
  v_location uuid;
begin
  v_location:=private.v488_mobile_pos_location(p_tenant_id,p_device_id);
  v_base:=public.mobile_pos_terminal_context_v488(p_tenant_id,p_device_id);
  return coalesce(v_base,'{}'::jsonb) || jsonb_build_object(
    'release','5.2',
    'mobile_contract','v5.2',
    'location_id',v_location,
    'authoritative_gst',true,
    'offline_sync_contract','v5.2',
    'sale_sync_function','gst_mobile_pos_sale_sync_v520',
    'sync_status_function','mobile_pos_sync_status_v520',
    'receipt_event_function','mobile_pos_receipt_event_v520',
    'product_cache_function','mobile_pos_product_cache_v520',
    'restaurant_bill_function','mobile_pos_restaurant_bill_v520',
    'legacy_sale_sync_function','mobile_pos_sale_sync_v488',
    'legacy_sale_sync_authoritative_gst',false
  );
end
$function$;

create or replace function public.mobile_pos_cache_manifest_v520(
  p_tenant_id uuid,
  p_device_id uuid
) returns jsonb
language plpgsql
stable security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_base jsonb;
  v_settings jsonb;
  v_context jsonb;
begin
  perform private.v488_mobile_pos_location(p_tenant_id,p_device_id);
  v_base:=public.pos_offline_cache_manifest_v486(p_tenant_id,p_device_id);
  v_context:=public.mobile_pos_terminal_context_v520(p_tenant_id,p_device_id);
  select to_jsonb(s) into v_settings
  from public.mobile_pos_terminal_settings_v488 s
  where s.tenant_id=p_tenant_id and s.device_id=p_device_id;

  return coalesce(v_base,'{}'::jsonb) || jsonb_build_object(
    'schema_version','5.2',
    'mobile_pos',true,
    'mobile_contract','v5.2',
    'authoritative_gst',true,
    'product_cache_function','mobile_pos_product_cache_v520',
    'effective_tax_field','tax_rate',
    'gst_profile_field','gst_profile',
    'terminal_settings',coalesce(v_settings,'{}'::jsonb),
    'restaurant_enabled',coalesce((v_context->>'restaurant_enabled')::boolean,false)
  );
end
$function$;

create or replace function public.gst_mobile_pos_sale_sync_v520(
  p_tenant_id uuid,
  p_device_id uuid,
  p_request_id text,
  p_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_location uuid;
  v_payload jsonb;
  v_result jsonb;
begin
  v_location:=private.v488_mobile_pos_location(p_tenant_id,p_device_id);
  v_payload:=coalesce(p_payload,'{}'::jsonb) || jsonb_build_object(
    'channel','mobile_pos',
    'mobile_release','5.2',
    'mobile_contract','v5.2'
  );

  v_result:=public.gst_pos_offline_sale_sync_v520(
    p_tenant_id,p_device_id,v_location,p_request_id,v_payload
  );

  return coalesce(v_result,'{}'::jsonb) || jsonb_build_object(
    'mobile_pos',true,
    'mobile_release','5.2',
    'mobile_contract','v5.2',
    'authoritative_gst',coalesce((v_result->>'authoritative_gst')::boolean,false)
  );
end
$function$;

create or replace function public.mobile_pos_sync_status_v520(
  p_tenant_id uuid,
  p_device_id uuid,
  p_limit integer default 100
) returns jsonb
language plpgsql
stable security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_location uuid;
  v_summary jsonb;
  v_recent jsonb;
begin
  v_location:=private.v488_mobile_pos_location(p_tenant_id,p_device_id);

  select jsonb_build_object(
    'pending',count(*) filter(where q.status in('pending','syncing')),
    'conflict',count(*) filter(where q.status='conflict'),
    'error',count(*) filter(where q.status='error'),
    'cancelled',count(*) filter(where q.status='cancelled'),
    'synced_today',count(*) filter(where q.status='synced' and q.synced_at::date=current_date),
    'last_synced_at',max(q.synced_at)
  )
  into v_summary
  from public.pos_offline_sync_v486 q
  where q.tenant_id=p_tenant_id
    and q.device_id=p_device_id
    and q.location_id=v_location
    and q.sync_contract_version='v5.2'
    and q.payload_snapshot->>'channel'='mobile_pos';

  select coalesce(jsonb_agg(to_jsonb(r) order by r.updated_at desc),'[]'::jsonb)
  into v_recent
  from (
    select
      q.request_id,q.local_invoice_number,q.status,q.conflict_code,q.conflict_message,
      q.attempts,q.first_seen_at,q.last_attempt_at,q.synced_at,q.updated_at,
      q.sale_id,q.gst_snapshot_id,q.gst_journal_id,q.server_response
    from public.pos_offline_sync_v486 q
    where q.tenant_id=p_tenant_id
      and q.device_id=p_device_id
      and q.location_id=v_location
      and q.sync_contract_version='v5.2'
      and q.payload_snapshot->>'channel'='mobile_pos'
    order by q.updated_at desc
    limit greatest(1,least(coalesce(p_limit,100),500))
  ) r;

  return jsonb_build_object(
    'release','5.2',
    'mobile_contract','v5.2',
    'device_id',p_device_id,
    'location_id',v_location,
    'summary',coalesce(v_summary,'{}'::jsonb),
    'recent',coalesce(v_recent,'[]'::jsonb)
  );
end
$function$;

create or replace function public.mobile_pos_receipt_event_v520(
  p_tenant_id uuid,
  p_device_id uuid,
  p_request_id text,
  p_event_type text,
  p_local_invoice_number text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_location uuid;
  v_request text:=nullif(trim(coalesce(p_request_id,'')),'');
  v_event text:=lower(trim(coalesce(p_event_type,'')));
  q public.pos_offline_sync_v486%rowtype;
  v_sale uuid;
  v_state text:='local';
  v_id uuid;
begin
  v_location:=private.v488_mobile_pos_location(p_tenant_id,p_device_id);
  if v_request is null then raise exception 'Request ID is required'; end if;
  if v_event not in('print','share') then raise exception 'Invalid receipt event'; end if;

  select * into q
  from public.pos_offline_sync_v486
  where tenant_id=p_tenant_id
    and request_id=v_request
    and device_id=p_device_id
    and location_id=v_location
    and sync_contract_version='v5.2'
    and payload_snapshot->>'channel'='mobile_pos';

  if found then
    if q.status='synced' then
      if q.sale_id is null or q.gst_snapshot_id is null or q.gst_journal_id is null then
        raise exception 'Synced Mobile POS request is missing authoritative GST recovery evidence';
      end if;
      v_sale:=q.sale_id;
      v_state:='synced';
    end if;
  elsif exists(
    select 1 from public.pos_offline_sync_v486 x
    where x.tenant_id=p_tenant_id and x.request_id=v_request
  ) then
    raise exception 'Request ID belongs to another POS device, location, or sync contract';
  end if;

  insert into public.mobile_pos_receipt_events_v488(
    tenant_id,device_id,location_id,request_id,local_invoice_number,
    sale_id,event_type,receipt_state,created_by
  ) values(
    p_tenant_id,p_device_id,v_location,v_request,
    nullif(trim(coalesce(p_local_invoice_number,'')),''),
    v_sale,v_event,v_state,auth.uid()
  ) returning id into v_id;

  return jsonb_build_object(
    'ok',true,
    'event_id',v_id,
    'receipt_state',v_state,
    'sale_id',v_sale,
    'mobile_contract','v5.2',
    'authoritative_gst',v_state='synced'
  );
end
$function$;

create or replace function public.mobile_pos_kot_create_v520(
  p_tenant_id uuid,
  p_device_id uuid,
  p_request_id text,
  p_order_type text,
  p_table_id uuid,
  p_customer_id uuid,
  p_items jsonb,
  p_note text default '',
  p_send_now boolean default true
) returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_location uuid;
  v_request text:=nullif(trim(coalesce(p_request_id,'')),'');
  v_payload jsonb;
  v_identity jsonb;
  v_hash text;
  r private.mobile_pos_kot_requests_v520%rowtype;
  v_order jsonb;
  v_kot jsonb:='{}'::jsonb;
  v_response jsonb;
  v_order_id uuid;
  v_kot_id uuid;
begin
  if v_request is null then raise exception 'Request ID is required'; end if;
  if length(v_request)>160 then raise exception 'Mobile KOT request ID is too long'; end if;
  v_location:=private.v488_mobile_pos_location(p_tenant_id,p_device_id);

  v_payload:=jsonb_build_object(
    'order_type',coalesce(nullif(trim(p_order_type),''),'takeaway'),
    'table_id',p_table_id,
    'customer_id',p_customer_id,
    'items',coalesce(p_items,'[]'::jsonb),
    'note',coalesce(p_note,''),
    'send_now',coalesce(p_send_now,true)
  );
  v_identity:=jsonb_build_object('device_id',p_device_id,'location_id',v_location,'payload',v_payload);
  v_hash:=private.gst_request_hash_v520(v_identity);

  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':mobile-kot-v520:'||v_request,0));
  select * into r
  from private.mobile_pos_kot_requests_v520
  where tenant_id=p_tenant_id and request_id=v_request
  for update;

  if found then
    if r.request_hash is distinct from v_hash
       or r.device_id is distinct from p_device_id
       or r.location_id is distinct from v_location
       or r.payload is distinct from v_payload then
      raise exception 'Request ID was already used with a different Mobile KOT payload';
    end if;
    if r.status='sent' and r.response is not null then
      return r.response || jsonb_build_object('idempotent_replay',true);
    end if;
    raise exception 'Existing Mobile KOT request is incomplete and requires reconciliation';
  end if;

  insert into private.mobile_pos_kot_requests_v520(
    tenant_id,request_id,request_hash,device_id,location_id,payload,status,created_by
  ) values(
    p_tenant_id,v_request,v_hash,p_device_id,v_location,v_payload,'processing',auth.uid()
  );

  v_order:=public.restaurant_order_create_v32(
    p_tenant_id,v_location,p_device_id,
    coalesce(nullif(trim(p_order_type),''),'takeaway'),
    p_table_id,p_customer_id,15,p_note,null,coalesce(p_items,'[]'::jsonb)
  );
  v_order_id:=nullif(v_order->>'order_id','')::uuid;
  if v_order_id is null then raise exception 'Restaurant order was not created'; end if;

  if coalesce(p_send_now,true) then
    v_kot:=public.restaurant_kot_send_v32(p_tenant_id,v_order_id,p_device_id,p_note);
    v_kot_id:=nullif(v_kot->>'kot_id','')::uuid;
    if v_kot_id is null then raise exception 'Restaurant KOT was not created'; end if;
  end if;

  v_response:=coalesce(v_order,'{}'::jsonb)||coalesce(v_kot,'{}'::jsonb)||jsonb_build_object(
    'ok',true,
    'request_id',v_request,
    'mobile_pos',true,
    'mobile_release','5.2',
    'mobile_contract','v5.2',
    'gst_authoritative',false,
    'gst_authority_at_billing','gst_restaurant_order_bill_v520'
  );

  update private.mobile_pos_kot_requests_v520
  set order_id=v_order_id,kot_id=v_kot_id,response=v_response,status='sent',updated_at=now()
  where tenant_id=p_tenant_id and request_id=v_request;

  return v_response;
end
$function$;

create or replace function public.mobile_pos_restaurant_bill_v520(
  p_tenant_id uuid,
  p_order_id uuid,
  p_device_id uuid,
  p_customer_id uuid,
  p_due_date date,
  p_initial_payment numeric,
  p_payment_method text,
  p_payment_reference text,
  p_round_off numeric default 0,
  p_supply_type text default null,
  p_place_of_supply_code text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_result jsonb;
begin
  perform private.v488_mobile_pos_location(p_tenant_id,p_device_id);
  v_result:=public.gst_restaurant_order_bill_v520(
    p_tenant_id,p_order_id,p_device_id,p_customer_id,p_due_date,p_initial_payment,
    p_payment_method,p_payment_reference,p_round_off,p_supply_type,p_place_of_supply_code
  );
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'mobile_pos',true,
    'mobile_release','5.2',
    'mobile_contract','v5.2',
    'authoritative_gst',true
  );
end
$function$;

create or replace function public.mobile_pos_api_contract_v520(
  p_tenant_id uuid,
  p_device_id uuid
) returns jsonb
language plpgsql
stable security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_location uuid;
begin
  v_location:=private.v488_mobile_pos_location(p_tenant_id,p_device_id);
  return jsonb_build_object(
    'api_version','v2',
    'release','5.2',
    'resource','mobile-pos',
    'device_id',p_device_id,
    'location_id',v_location,
    'terminal_activation',true,
    'billing',true,
    'barcode_scan','device_camera',
    'customers','offline_cache',
    'offline_queue','v5.2-authoritative-gst',
    'immutable_sale_request_payload',true,
    'new_request_id_required_after_invoice_edit',true,
    'authoritative_gst_on_server_acceptance',true,
    'gst_on_pending_or_conflict',false,
    'sale_sync_function','gst_mobile_pos_sale_sync_v520',
    'sync_status_function','mobile_pos_sync_status_v520',
    'receipt_event_function','mobile_pos_receipt_event_v520',
    'cache_manifest_function','mobile_pos_cache_manifest_v520',
    'product_cache_function','mobile_pos_product_cache_v520',
    'kot_create_function','mobile_pos_kot_create_v520',
    'restaurant_bill_function','mobile_pos_restaurant_bill_v520',
    'restaurant_final_tax_authority','gst_restaurant_order_bill_v520',
    'legacy_v488_available',true,
    'legacy_sale_sync_authoritative_gst',false
  );
end
$function$;

revoke all on function public.mobile_pos_product_cache_v520(uuid,uuid) from public, anon;
revoke all on function public.mobile_pos_terminal_context_v520(uuid,uuid) from public, anon;
revoke all on function public.mobile_pos_cache_manifest_v520(uuid,uuid) from public, anon;
revoke all on function public.gst_mobile_pos_sale_sync_v520(uuid,uuid,text,jsonb) from public, anon;
revoke all on function public.mobile_pos_sync_status_v520(uuid,uuid,integer) from public, anon;
revoke all on function public.mobile_pos_receipt_event_v520(uuid,uuid,text,text,text) from public, anon;
revoke all on function public.mobile_pos_kot_create_v520(uuid,uuid,text,text,uuid,uuid,jsonb,text,boolean) from public, anon;
revoke all on function public.mobile_pos_restaurant_bill_v520(uuid,uuid,uuid,uuid,date,numeric,text,text,numeric,text,text) from public, anon;
revoke all on function public.mobile_pos_api_contract_v520(uuid,uuid) from public, anon;

grant execute on function public.mobile_pos_product_cache_v520(uuid,uuid) to authenticated, service_role, postgres;
grant execute on function public.mobile_pos_terminal_context_v520(uuid,uuid) to authenticated, service_role, postgres;
grant execute on function public.mobile_pos_cache_manifest_v520(uuid,uuid) to authenticated, service_role, postgres;
grant execute on function public.gst_mobile_pos_sale_sync_v520(uuid,uuid,text,jsonb) to authenticated, service_role, postgres;
grant execute on function public.mobile_pos_sync_status_v520(uuid,uuid,integer) to authenticated, service_role, postgres;
grant execute on function public.mobile_pos_receipt_event_v520(uuid,uuid,text,text,text) to authenticated, service_role, postgres;
grant execute on function public.mobile_pos_kot_create_v520(uuid,uuid,text,text,uuid,uuid,jsonb,text,boolean) to authenticated, service_role, postgres;
grant execute on function public.mobile_pos_restaurant_bill_v520(uuid,uuid,uuid,uuid,date,numeric,text,text,numeric,text,text) to authenticated, service_role, postgres;
grant execute on function public.mobile_pos_api_contract_v520(uuid,uuid) to authenticated, service_role, postgres;