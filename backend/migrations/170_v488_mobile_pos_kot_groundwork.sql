-- THQ ERP V4.8.8 — idempotent Mobile POS KOT groundwork.
begin;
create table if not exists public.mobile_pos_kot_requests_v488(
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  request_id text not null,
  device_id uuid not null references public.business_devices(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete cascade,
  order_id uuid references public.restaurant_orders(id) on delete set null,
  kot_id uuid references public.restaurant_kots(id) on delete set null,
  payload jsonb not null default '{}'::jsonb,
  response jsonb,
  status text not null default 'processing' check(status in('processing','sent','error')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(tenant_id,request_id)
);
alter table public.mobile_pos_kot_requests_v488 enable row level security;
revoke all on public.mobile_pos_kot_requests_v488 from anon,authenticated;

create or replace function public.mobile_pos_kot_create_v488(
  p_tenant_id uuid,p_device_id uuid,p_request_id text,p_order_type text,p_table_id uuid,p_customer_id uuid,p_items jsonb,p_note text default '',p_send_now boolean default true
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;v_existing jsonb;v_order jsonb;v_kot jsonb;v_response jsonb;v_order_id uuid;v_kot_id uuid;v_payload jsonb;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then raise exception 'Request ID is required';end if;
  v_location:=private.v488_mobile_pos_location(p_tenant_id,p_device_id);
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':mobile-kot:'||trim(p_request_id),0));
  select response into v_existing from public.mobile_pos_kot_requests_v488 where tenant_id=p_tenant_id and request_id=trim(p_request_id) and status='sent';
  if v_existing is not null then return v_existing||jsonb_build_object('idempotent_replay',true);end if;
  v_payload:=jsonb_build_object('order_type',p_order_type,'table_id',p_table_id,'customer_id',p_customer_id,'items',coalesce(p_items,'[]'::jsonb),'note',coalesce(p_note,''),'send_now',coalesce(p_send_now,true));
  insert into public.mobile_pos_kot_requests_v488(tenant_id,request_id,device_id,location_id,payload,status,created_by,updated_at)
  values(p_tenant_id,trim(p_request_id),p_device_id,v_location,v_payload,'processing',auth.uid(),now())
  on conflict(tenant_id,request_id) do update set payload=excluded.payload,status='processing',updated_at=now();
  begin
    v_order:=public.restaurant_order_create_v32(p_tenant_id,v_location,p_device_id,coalesce(nullif(trim(p_order_type),''),'takeaway'),p_table_id,p_customer_id,15,p_note,null,coalesce(p_items,'[]'::jsonb));
    v_order_id:=nullif(v_order->>'order_id','')::uuid;
    if coalesce(p_send_now,true) then
      v_kot:=public.restaurant_kot_send_v32(p_tenant_id,v_order_id,p_device_id,p_note);
      v_kot_id:=nullif(v_kot->>'kot_id','')::uuid;
    else v_kot:='{}'::jsonb;end if;
    v_response:=coalesce(v_order,'{}'::jsonb)||coalesce(v_kot,'{}'::jsonb)||jsonb_build_object('ok',true,'request_id',trim(p_request_id),'mobile_pos',true);
    update public.mobile_pos_kot_requests_v488 set order_id=v_order_id,kot_id=v_kot_id,response=v_response,status='sent',updated_at=now() where tenant_id=p_tenant_id and request_id=trim(p_request_id);
    return v_response;
  exception when others then
    update public.mobile_pos_kot_requests_v488 set response=jsonb_build_object('ok',false,'message',sqlerrm),status='error',updated_at=now() where tenant_id=p_tenant_id and request_id=trim(p_request_id);
    raise;
  end;
end$$;
grant execute on function public.mobile_pos_kot_create_v488(uuid,uuid,text,text,uuid,uuid,jsonb,text,boolean) to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(170,'4.8.8','Mobile POS Foundation','Idempotent mobile restaurant order/KOT creation groundwork on the existing restaurant workflow and device/location security.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.8 migration 170 KOT groundwork applied' as status;
