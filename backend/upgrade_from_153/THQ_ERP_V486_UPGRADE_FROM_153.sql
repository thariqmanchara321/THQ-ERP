-- THQ ERP v4.8.6 Build 14 — combined database upgrade from migration 153 to 160.
-- Run only on a database whose current THQ migration is 153. Each migration is transaction-wrapped.

-- ============================================================================
-- 154_v486_offline_pos_foundation.sql
-- ============================================================================
-- THQ ERP V4.8.6 — Offline POS server audit foundation.
begin;

create table if not exists public.pos_offline_sync_v486(
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  request_id text not null,
  device_id uuid not null references public.business_devices(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete cascade,
  local_invoice_number text,
  status text not null default 'pending' check(status in('pending','syncing','synced','conflict','error','cancelled')),
  conflict_code text,
  conflict_message text,
  payload_snapshot jsonb not null default '{}'::jsonb,
  server_response jsonb,
  attempts integer not null default 0,
  first_seen_at timestamptz not null default now(),
  last_attempt_at timestamptz,
  synced_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key(tenant_id,request_id)
);
create index if not exists idx_pos_offline_sync_v486_device on public.pos_offline_sync_v486(tenant_id,device_id,status,updated_at desc);
create index if not exists idx_pos_offline_sync_v486_location on public.pos_offline_sync_v486(tenant_id,location_id,status,updated_at desc);
alter table public.pos_offline_sync_v486 enable row level security;
revoke all on public.pos_offline_sync_v486 from anon,authenticated;

create or replace function private.v486_pos_device_location(p_tenant_id uuid,p_device_id uuid,p_location_id uuid)
returns uuid language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;v_type text;v_status text;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select d.location_id,d.app_type,d.status into v_location,v_type,v_status
  from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id;
  if v_location is null then raise exception 'POS terminal not found';end if;
  if v_status<>'active' then raise exception 'POS terminal is not active';end if;
  if v_type<>'pos' then raise exception 'Offline POS sync requires a POS terminal';end if;
  if p_location_id is not null and p_location_id<>v_location then raise exception 'POS terminal location mismatch';end if;
  return v_location;
end$$;
revoke all on function private.v486_pos_device_location(uuid,uuid,uuid) from public;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(154,'4.8.6','Offline POS','Server-side offline POS sync audit foundation and active-terminal validation.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.6 migration 154 offline POS foundation applied' as status;


-- ============================================================================
-- 155_v486_offline_sale_sync.sql
-- ============================================================================
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


-- ============================================================================
-- 156_v486_sync_status_conflicts.sql
-- ============================================================================
-- THQ ERP V4.8.6 — offline sync status, conflict visibility and audit summaries.
begin;

create or replace function public.pos_offline_sync_list_v486(
  p_tenant_id uuid,p_device_id uuid default null,p_status text default null,p_limit integer default 500
) returns table(
  request_id text,device_id uuid,device_code text,location_id uuid,location_name text,local_invoice_number text,status text,
  conflict_code text,conflict_message text,attempts integer,first_seen_at timestamptz,last_attempt_at timestamptz,synced_at timestamptz,server_response jsonb
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  select q.request_id,q.device_id,d.device_code,q.location_id,l.location_code||' • '||l.name,q.local_invoice_number,q.status,
         q.conflict_code,q.conflict_message,q.attempts,q.first_seen_at,q.last_attempt_at,q.synced_at,q.server_response
  from public.pos_offline_sync_v486 q
  join public.business_devices d on d.id=q.device_id
  join public.business_locations l on l.id=q.location_id
  where q.tenant_id=p_tenant_id and (p_device_id is null or q.device_id=p_device_id)
    and (p_status is null or p_status='' or q.status=p_status)
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_user_location_allowed(p_tenant_id,q.location_id,'view'))
  order by q.updated_at desc limit greatest(1,least(coalesce(p_limit,500),2000));
end$$;
grant execute on function public.pos_offline_sync_list_v486(uuid,uuid,text,integer) to authenticated;

create or replace function public.pos_offline_sync_summary_v486(p_tenant_id uuid,p_device_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return (select jsonb_build_object(
    'pending',count(*) filter(where status in('pending','syncing')),
    'conflict',count(*) filter(where status='conflict'),
    'error',count(*) filter(where status='error'),
    'synced_today',count(*) filter(where status='synced' and synced_at::date=current_date),
    'last_synced_at',max(synced_at)
  ) from public.pos_offline_sync_v486 where tenant_id=p_tenant_id and (p_device_id is null or device_id=p_device_id));
end$$;
grant execute on function public.pos_offline_sync_summary_v486(uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(156,'4.8.6','Offline POS','Server audit list and summary for pending/synced/conflicted offline POS requests.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.6 migration 156 sync status/conflicts applied' as status;


-- ============================================================================
-- 157_v486_offline_cache_contract.sql
-- ============================================================================
-- THQ ERP V4.8.6 — offline product/customer/serial cache contract.
begin;

create or replace function public.pos_offline_product_cache_v486(p_tenant_id uuid,p_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;v jsonb;
begin
  v_location:=private.v486_pos_device_location(p_tenant_id,p_device_id,null);
  select coalesce(jsonb_agg(
    x||jsonb_build_object(
      'stock_quantity',case when x->>'item_type'='stock' then greatest(coalesce(lb.quantity,0)-coalesce(lb.reserved_quantity,0)-coalesce(lb.damaged_quantity,0)-coalesce(lb.quarantine_quantity,0),0) else coalesce(nullif(x->>'stock_quantity','')::numeric,0) end,
      'offline_available_quantity',case when x->>'item_type'='stock' then greatest(coalesce(lb.quantity,0)-coalesce(lb.reserved_quantity,0)-coalesce(lb.damaged_quantity,0)-coalesce(lb.quarantine_quantity,0),0) else coalesce(nullif(x->>'stock_quantity','')::numeric,0) end
    ) order by x->>'product_name',x->>'sku'
  ),'[]'::jsonb) into v
  from public.inventory_list_products_v483(p_tenant_id,v_location) as t(x)
  left join public.location_stock_balances lb on lb.tenant_id=p_tenant_id and lb.location_id=v_location and lb.variant_id=nullif(x->>'variant_id','')::uuid
  left join public.location_product_settings lps on lps.tenant_id=p_tenant_id and lps.location_id=v_location and lps.variant_id=nullif(x->>'variant_id','')::uuid
  where x->>'product_status'='active' and x->>'variant_status'='active' and coalesce(lps.active,true);
  return coalesce(v,'[]'::jsonb);
end$$;
grant execute on function public.pos_offline_product_cache_v486(uuid,uuid) to authenticated;

create or replace function public.pos_offline_customer_cache_v486(p_tenant_id uuid,p_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v jsonb;
begin
  perform private.v486_pos_device_location(p_tenant_id,p_device_id,null);
  select coalesce(jsonb_agg(x order by x->>'customer_name'),'[]'::jsonb) into v from public.customers_list_v482(p_tenant_id) as t(x) where x->>'status'='active';
  return coalesce(v,'[]'::jsonb);
end$$;
grant execute on function public.pos_offline_customer_cache_v486(uuid,uuid) to authenticated;

create or replace function public.pos_offline_available_serials_v486(
  p_tenant_id uuid,p_device_id uuid,p_after text default '',p_limit integer default 1000
) returns table(serial_id uuid,serial_number text,variant_id uuid,updated_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;v_after text:=lower(trim(coalesce(p_after,'')));
begin
  v_location:=private.v486_pos_device_location(p_tenant_id,p_device_id,null);
  return query
  select s.id,s.serial_number,s.variant_id,s.updated_at
  from public.inventory_serials_v483 s
  where s.tenant_id=p_tenant_id and s.current_location_id=v_location and s.status='in_stock'
    and lower(s.serial_number)>v_after
    and not exists(select 1 from public.stock_transfer_allocations_v485 a join public.stock_transfers t on t.id=a.transfer_id where a.tenant_id=p_tenant_id and a.serial_id=s.id and t.status in('requested','approved','in_transit'))
  order by lower(s.serial_number),s.id limit greatest(1,least(coalesce(p_limit,1000),2000));
end$$;
grant execute on function public.pos_offline_available_serials_v486(uuid,uuid,text,integer) to authenticated;

create or replace function public.pos_offline_cache_manifest_v486(p_tenant_id uuid,p_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;v_shift jsonb;
begin
  v_location:=private.v486_pos_device_location(p_tenant_id,p_device_id,null);
  begin v_shift:=public.cashier_shift_current_v472(p_tenant_id,p_device_id);exception when others then v_shift:=null;end;
  return jsonb_build_object(
    'tenant_id',p_tenant_id,'device_id',p_device_id,'location_id',v_location,'generated_at',now(),
    'schema_version','4.8.6','migration_no',157,'current_shift',v_shift
  );
end$$;
grant execute on function public.pos_offline_cache_manifest_v486(uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(157,'4.8.6','Offline POS','Offline product/customer cache and paged available-serial cache using true available location stock.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.6 migration 157 offline cache contract applied' as status;


-- ============================================================================
-- 158_v486_api_contract.sql
-- ============================================================================
-- THQ ERP V4.8.6 — THQ API offline POS contract metadata.
begin;

create or replace function public.pos_offline_api_contract_v486(p_tenant_id uuid,p_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;
begin
  v_location:=private.v486_pos_device_location(p_tenant_id,p_device_id,null);
  return jsonb_build_object(
    'api_version','v1','release','4.8.6','resource','offline-pos','device_id',p_device_id,'location_id',v_location,
    'local_first',true,'idempotent_request_id',true,'automatic_sync',true,'price_conflict_protection',true,
    'serial_cache_paged',true,'supported_states',jsonb_build_array('pending','syncing','synced','conflict','error','cancelled')
  );
end$$;
grant execute on function public.pos_offline_api_contract_v486(uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(158,'4.8.6','Offline POS','THQ API contract for offline POS cache, sync, status and conflicts.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.6 migration 158 API contract applied' as status;


-- ============================================================================
-- 159_v486_offline_hardening.sql
-- ============================================================================
-- THQ ERP V4.8.6 — offline POS hardening helpers.
begin;

create or replace function public.pos_offline_request_lookup_v486(p_tenant_id uuid,p_request_id text)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v public.pos_offline_sync_v486%rowtype;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select * into v from public.pos_offline_sync_v486 where tenant_id=p_tenant_id and request_id=trim(p_request_id);
  if not found then return null;end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_user_location_allowed(p_tenant_id,v.location_id,'view') then raise exception 'Location access denied';end if;
  return jsonb_build_object('request_id',v.request_id,'device_id',v.device_id,'location_id',v.location_id,'local_invoice_number',v.local_invoice_number,'status',v.status,'conflict_code',v.conflict_code,'conflict_message',v.conflict_message,'attempts',v.attempts,'first_seen_at',v.first_seen_at,'last_attempt_at',v.last_attempt_at,'synced_at',v.synced_at,'server_response',v.server_response);
end$$;
grant execute on function public.pos_offline_request_lookup_v486(uuid,text) to authenticated;

-- Keep server audit immutable from ordinary clients; only RPCs above may write it.
revoke insert,update,delete on public.pos_offline_sync_v486 from authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(159,'4.8.6','Offline POS','Offline request lookup, RPC-only audit writes and release hardening.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.6 migration 159 offline hardening applied' as status;


-- ============================================================================
-- 160_v486_release_contract.sql
-- ============================================================================
-- THQ ERP V4.8.6 — release contract and verification.
begin;

create or replace function public.thq_backend_contract_v47() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
  'product','THQ ERP',
  'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
  'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
  'minimum_app_version','4.8.6','release','Offline POS','api_version','v1'
 )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v486_release_verify() returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_missing text[]:='{}'::text[];
begin
  if to_regclass('public.pos_offline_sync_v486') is null then v_missing:=array_append(v_missing,'pos_offline_sync_v486');end if;
  if to_regprocedure('public.pos_offline_sale_sync_v486(uuid,uuid,uuid,text,jsonb)') is null then v_missing:=array_append(v_missing,'pos_offline_sale_sync_v486');end if;
  if to_regprocedure('public.pos_offline_sync_list_v486(uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'pos_offline_sync_list_v486');end if;
  if to_regprocedure('public.pos_offline_sync_summary_v486(uuid,uuid)') is null then v_missing:=array_append(v_missing,'pos_offline_sync_summary_v486');end if;
  if to_regprocedure('public.pos_offline_product_cache_v486(uuid,uuid)') is null then v_missing:=array_append(v_missing,'pos_offline_product_cache_v486');end if;
  if to_regprocedure('public.pos_offline_customer_cache_v486(uuid,uuid)') is null then v_missing:=array_append(v_missing,'pos_offline_customer_cache_v486');end if;
  if to_regprocedure('public.pos_offline_available_serials_v486(uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'pos_offline_available_serials_v486');end if;
  if to_regprocedure('public.pos_offline_cache_manifest_v486(uuid,uuid)') is null then v_missing:=array_append(v_missing,'pos_offline_cache_manifest_v486');end if;
  if to_regprocedure('public.pos_offline_api_contract_v486(uuid,uuid)') is null then v_missing:=array_append(v_missing,'pos_offline_api_contract_v486');end if;
  if to_regprocedure('public.pos_offline_request_lookup_v486(uuid,text)') is null then v_missing:=array_append(v_missing,'pos_offline_request_lookup_v486');end if;
  return jsonb_build_object(
    'ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'schema_version','4.8.6','migration_no',160,'api_version','v1',
    'local_pos_database',true,'offline_billing',true,'offline_invoice_queue',true,'automatic_sync',true,'safe_retry_idempotency',true,
    'offline_product_customer_cache',true,'serial_cache',true,'sync_status_conflicts',true,'price_tax_conflict_protection',true
  );
end$$;
grant execute on function public.thq_v486_release_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(160,'4.8.6','Offline POS','Local-first POS billing, SQLite queue/cache, automatic idempotent sync, offline product/customer/serial cache, and conflict handling.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.6 migration 160 release contract applied' as status;


