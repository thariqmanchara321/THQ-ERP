alter table public.pos_offline_sync_v486
  add column if not exists sync_contract_version text not null default 'v4.8.6',
  add column if not exists request_hash text,
  add column if not exists sale_id uuid,
  add column if not exists gst_snapshot_id uuid,
  add column if not exists gst_journal_id uuid;

create index if not exists idx_pos_offline_sync_v520_sale
  on public.pos_offline_sync_v486(tenant_id,sale_id)
  where sale_id is not null;

create or replace function private.v520_offline_sync_guard()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if tg_op='UPDATE' and old.sync_contract_version='v5.2' then
    if new.sync_contract_version is distinct from old.sync_contract_version
       or new.request_hash is distinct from old.request_hash
       or new.device_id is distinct from old.device_id
       or new.location_id is distinct from old.location_id
       or new.payload_snapshot is distinct from old.payload_snapshot then
      raise exception 'A v5.2 Offline POS request identity/payload is immutable; create a new request ID for an edited invoice';
    end if;
  end if;

  if new.sync_contract_version='v5.2' then
    if nullif(trim(coalesce(new.request_hash,'')),'') is null then
      raise exception 'v5.2 Offline POS request hash is required';
    end if;
    if new.status='synced' then
      if new.sale_id is null or new.gst_snapshot_id is null or new.gst_journal_id is null then
        raise exception 'v5.2 Offline POS cannot be marked synced without Sale/GST snapshot/journal evidence';
      end if;
      if not exists(
        select 1
        from public.gst_document_snapshots_v520 s
        where s.id=new.gst_snapshot_id
          and s.tenant_id=new.tenant_id
          and s.source_type='sale'
          and s.source_id=new.sale_id
      ) then
        raise exception 'v5.2 Offline POS GST snapshot does not match the synced Sale';
      end if;
      if not exists(
        select 1
        from public.journal_entries j
        where j.id=new.gst_journal_id
          and j.tenant_id=new.tenant_id
          and j.source_type='sale'
          and j.source_id=new.sale_id
          and j.status='posted'
      ) then
        raise exception 'v5.2 Offline POS authoritative Sale journal does not match the synced Sale';
      end if;
    end if;
  end if;
  return new;
end
$$;

revoke all on function private.v520_offline_sync_guard() from public,anon,authenticated;

drop trigger if exists trg_pos_offline_sync_v520_guard on public.pos_offline_sync_v486;
create trigger trg_pos_offline_sync_v520_guard
before insert or update on public.pos_offline_sync_v486
for each row execute function private.v520_offline_sync_guard();

create or replace function private.v520_offline_conflict(
  p_tenant_id uuid,
  p_device_id uuid,
  p_location_id uuid,
  p_request_id text,
  p_request_hash text,
  p_local text,
  p_code text,
  p_message text,
  p_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  insert into public.pos_offline_sync_v486(
    tenant_id,request_id,device_id,location_id,local_invoice_number,status,
    conflict_code,conflict_message,payload_snapshot,attempts,last_attempt_at,
    created_by,updated_at,sync_contract_version,request_hash
  ) values(
    p_tenant_id,trim(p_request_id),p_device_id,p_location_id,p_local,'conflict',
    p_code,p_message,coalesce(p_payload,'{}'::jsonb),1,now(),auth.uid(),now(),'v5.2',p_request_hash
  )
  on conflict(tenant_id,request_id) do update set
    status='conflict',
    conflict_code=excluded.conflict_code,
    conflict_message=excluded.conflict_message,
    attempts=public.pos_offline_sync_v486.attempts+1,
    last_attempt_at=now(),
    updated_at=now();

  return jsonb_build_object(
    'ok',false,'status','conflict','code',p_code,'message',p_message,
    'request_id',trim(p_request_id),'local_invoice_number',p_local,
    'offline_sync','v5.2','authoritative_gst',false
  );
end
$$;

revoke all on function private.v520_offline_conflict(uuid,uuid,uuid,text,text,text,text,text,jsonb) from public,anon,authenticated;

create or replace function public.gst_pos_offline_sale_sync_v520(
  p_tenant_id uuid,
  p_device_id uuid,
  p_location_id uuid,
  p_request_id text,
  p_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_request text:=nullif(trim(coalesce(p_request_id,'')),'');
  v_location uuid;
  v_identity jsonb;
  v_hash text;
  q public.pos_offline_sync_v486%rowtype;
  v_items jsonb;
  v_priced jsonb;
  v_post_priced jsonb;
  v_client jsonb;
  v_server jsonb;
  v_i integer;
  v_client_price numeric;
  v_server_price numeric;
  v_client_tax numeric;
  v_server_tax numeric;
  v_variant uuid;
  v_customer uuid;
  v_sale_date date;
  v_due_date date;
  v_local text;
  v_message text;
  v_code text;
  v_profile public.gst_product_tax_profiles_v520%rowtype;
  v_product_tax numeric;
  v_result jsonb;
  v_sale_id uuid;
  v_snapshot uuid;
  v_journal uuid;
  v_sale_request text;
begin
  if v_request is null then raise exception 'Request ID is required'; end if;
  if length(v_request)>160 then raise exception 'Offline v5.2 request ID is too long'; end if;

  v_location:=private.v486_pos_device_location(p_tenant_id,p_device_id,p_location_id);
  perform private.erp_validate_transaction_origin(p_tenant_id,v_location,p_device_id,'sales');

  v_identity:=jsonb_build_object(
    'device_id',p_device_id,
    'location_id',v_location,
    'payload',coalesce(p_payload,'{}'::jsonb)
  );
  v_hash:=private.gst_request_hash_v520(v_identity);

  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':offline-v520:'||v_request,0));
  select * into q
  from public.pos_offline_sync_v486
  where tenant_id=p_tenant_id and request_id=v_request
  for update;

  if found then
    if coalesce(q.sync_contract_version,'v4.8.6')<>'v5.2' then
      raise exception 'Request ID already belongs to the legacy Offline POS sync contract';
    end if;
    if q.request_hash is distinct from v_hash
       or q.device_id is distinct from p_device_id
       or q.location_id is distinct from v_location
       or q.payload_snapshot is distinct from coalesce(p_payload,'{}'::jsonb) then
      raise exception 'Request ID was already used with a different Offline POS device, location, or payload';
    end if;
    if q.status='synced' then
      if q.server_response is null or q.sale_id is null or q.gst_snapshot_id is null or q.gst_journal_id is null then
        raise exception 'Synced v5.2 Offline POS request is missing authoritative recovery evidence';
      end if;
      return q.server_response||jsonb_build_object('idempotent_replay',true);
    end if;
    if q.status='cancelled' then
      raise exception 'Cancelled Offline POS request cannot be reused';
    end if;
  end if;

  v_items:=coalesce(p_payload->'items','[]'::jsonb);
  if jsonb_typeof(v_items)<>'array' or jsonb_array_length(v_items)=0 then
    raise exception 'Offline invoice has no items';
  end if;

  v_customer:=nullif(p_payload->>'customer_id','')::uuid;
  v_local:=nullif(trim(coalesce(p_payload->>'local_invoice_number','')),'');
  if v_customer is null or not exists(
    select 1 from public.customers c
    where c.id=v_customer and c.tenant_id=p_tenant_id and c.status='active'
  ) then
    return private.v520_offline_conflict(
      p_tenant_id,p_device_id,v_location,v_request,v_hash,v_local,
      'CUSTOMER_UNAVAILABLE','Customer is no longer available.',p_payload
    );
  end if;

  v_sale_date:=coalesce(nullif(p_payload->>'sale_date','')::date,current_date);
  v_due_date:=nullif(p_payload->>'due_date','')::date;
  v_priced:=private.v482_price_sale_items(p_tenant_id,v_customer,v_items,v_location);

  for v_i in 0..jsonb_array_length(v_items)-1 loop
    v_client:=v_items->v_i;
    v_server:=v_priced->v_i;
    v_variant:=nullif(v_client->>'variant_id','')::uuid;
    v_client_price:=coalesce(nullif(v_client->>'unit_price','')::numeric,0);
    v_server_price:=coalesce(nullif(v_server->>'unit_price','')::numeric,0);
    if abs(v_client_price-v_server_price)>0.005 then
      v_message:=format('Price changed for product %s. Offline %s, current %s.',v_variant,round(v_client_price,2),round(v_server_price,2));
      return private.v520_offline_conflict(
        p_tenant_id,p_device_id,v_location,v_request,v_hash,v_local,
        'PRICE_CHANGED',v_message,p_payload
      );
    end if;

    select p.tax_rate into v_product_tax
    from public.product_variants pv
    join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id
    where pv.id=v_variant and pv.tenant_id=p_tenant_id;
    if not found then
      return private.v520_offline_conflict(
        p_tenant_id,p_device_id,v_location,v_request,v_hash,v_local,
        'PRODUCT_UNAVAILABLE','A product on the offline invoice is no longer available.',p_payload
      );
    end if;

    select * into v_profile from private.gst_profile_for_variant_v520(p_tenant_id,v_variant,v_sale_date);
    v_server_tax:=case
      when v_profile.id is null then coalesce(v_product_tax,0)
      when v_profile.taxability='taxable' then coalesce(v_profile.gst_rate,0)
      else 0
    end;
    v_client_tax:=coalesce(nullif(v_client->>'tax_rate','')::numeric,0);
    if abs(v_client_tax-v_server_tax)>0.0001 then
      v_message:=format('Tax changed for product %s. Offline %s, current %s.',v_variant,round(v_client_tax,4),round(v_server_tax,4));
      return private.v520_offline_conflict(
        p_tenant_id,p_device_id,v_location,v_request,v_hash,v_local,
        'TAX_CHANGED',v_message,p_payload
      );
    end if;
  end loop;

  insert into public.pos_offline_sync_v486(
    tenant_id,request_id,device_id,location_id,local_invoice_number,status,
    payload_snapshot,attempts,last_attempt_at,created_by,updated_at,
    sync_contract_version,request_hash
  ) values(
    p_tenant_id,v_request,p_device_id,v_location,v_local,'syncing',
    p_payload,1,now(),auth.uid(),now(),'v5.2',v_hash
  )
  on conflict(tenant_id,request_id) do update set
    status='syncing',
    attempts=public.pos_offline_sync_v486.attempts+1,
    last_attempt_at=now(),
    updated_at=now(),
    conflict_code=null,
    conflict_message=null;

  begin
    v_sale_request:='offline-v520:'||v_request;
    v_result:=public.gst_sale_create_v520(
      p_tenant_id,
      v_customer,
      v_sale_date,
      v_due_date,
      v_items,
      coalesce(nullif(p_payload->>'additional_charges','')::numeric,0),
      coalesce(nullif(p_payload->>'round_off','')::numeric,0),
      coalesce(nullif(p_payload->>'initial_payment','')::numeric,0),
      coalesce(nullif(p_payload->>'payment_method',''),'cash'),
      coalesce(p_payload->>'payment_reference',''),
      trim(concat_ws(' • ',nullif(p_payload->>'notes',''),'Offline POS '||coalesce(v_local,''))),
      v_location,
      p_device_id,
      v_sale_request,
      nullif(p_payload->>'supply_type',''),
      nullif(p_payload->>'place_of_supply_code','')
    );

    v_sale_id:=nullif(v_result->>'sale_id','')::uuid;
    v_snapshot:=nullif(v_result->>'gst_snapshot_id','')::uuid;
    v_journal:=nullif(v_result->>'journal_id','')::uuid;
    if v_sale_id is null or v_snapshot is null or v_journal is null then
      raise exception 'Authoritative GST Sale did not return complete evidence';
    end if;

    -- Re-check after the authoritative Sale call. If price/tax changed concurrently
    -- between the initial conflict check and acceptance, roll the Sale back and leave
    -- the offline request as a conflict rather than accepting a different invoice.
    v_post_priced:=private.v482_price_sale_items(p_tenant_id,v_customer,v_items,v_location);
    for v_i in 0..jsonb_array_length(v_items)-1 loop
      v_client:=v_items->v_i;
      v_server:=v_post_priced->v_i;
      v_variant:=nullif(v_client->>'variant_id','')::uuid;
      v_client_price:=coalesce(nullif(v_client->>'unit_price','')::numeric,0);
      v_server_price:=coalesce(nullif(v_server->>'unit_price','')::numeric,0);
      if abs(v_client_price-v_server_price)>0.005 then
        raise exception 'OFFLINE_PRICE_CHANGED: product % changed during sync',v_variant;
      end if;
      select p.tax_rate into v_product_tax
      from public.product_variants pv
      join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id
      where pv.id=v_variant and pv.tenant_id=p_tenant_id;
      select * into v_profile from private.gst_profile_for_variant_v520(p_tenant_id,v_variant,v_sale_date);
      v_server_tax:=case
        when v_profile.id is null then coalesce(v_product_tax,0)
        when v_profile.taxability='taxable' then coalesce(v_profile.gst_rate,0)
        else 0
      end;
      v_client_tax:=coalesce(nullif(v_client->>'tax_rate','')::numeric,0);
      if abs(v_client_tax-v_server_tax)>0.0001 then
        raise exception 'OFFLINE_TAX_CHANGED: product % changed during sync',v_variant;
      end if;
    end loop;
  exception when others then
    v_message:=sqlerrm;
    if v_message like 'OFFLINE_PRICE_CHANGED:%' then
      v_code:='PRICE_CHANGED';
    elsif v_message like 'OFFLINE_TAX_CHANGED:%' then
      v_code:='TAX_CHANGED';
    elsif v_message ilike '%stock%' or v_message ilike '%serial%' or v_message ilike '%batch%' or v_message ilike '%reconciled%' then
      v_code:='STOCK_CONFLICT';
    else
      v_code:='SERVER_VALIDATION';
    end if;
    return private.v520_offline_conflict(
      p_tenant_id,p_device_id,v_location,v_request,v_hash,v_local,
      v_code,v_message,p_payload
    );
  end;

  v_result:=coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'ok',true,
    'status','synced',
    'request_id',v_request,
    'local_invoice_number',v_local,
    'offline_sync','v5.2',
    'offline_contract','authoritative_gst',
    'authoritative_gst',true
  );

  update public.pos_offline_sync_v486 set
    status='synced',
    server_response=v_result,
    conflict_code=null,
    conflict_message=null,
    sale_id=v_sale_id,
    gst_snapshot_id=v_snapshot,
    gst_journal_id=v_journal,
    synced_at=now(),
    last_attempt_at=now(),
    updated_at=now()
  where tenant_id=p_tenant_id and request_id=v_request;

  return v_result;
end
$$;

revoke all on function public.gst_pos_offline_sale_sync_v520(uuid,uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.gst_pos_offline_sale_sync_v520(uuid,uuid,uuid,text,jsonb) to authenticated,service_role;

create or replace function public.pos_offline_api_contract_v520(
  p_tenant_id uuid,
  p_device_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare v_location uuid;
begin
  v_location:=private.v486_pos_device_location(p_tenant_id,p_device_id,null);
  return jsonb_build_object(
    'api_version','v2',
    'release','5.2',
    'resource','offline-pos',
    'device_id',p_device_id,
    'location_id',v_location,
    'local_first',true,
    'automatic_sync',true,
    'immutable_request_payload',true,
    'new_request_id_required_after_invoice_edit',true,
    'price_conflict_protection',true,
    'tax_conflict_protection',true,
    'authoritative_gst_on_server_acceptance',true,
    'gst_on_pending_or_conflict',false,
    'sync_function','gst_pos_offline_sale_sync_v520',
    'supported_states',jsonb_build_array('pending','syncing','synced','conflict','error','cancelled')
  );
end
$$;

revoke all on function public.pos_offline_api_contract_v520(uuid,uuid) from public,anon;
grant execute on function public.pos_offline_api_contract_v520(uuid,uuid) to authenticated,service_role;