create or replace function public.logistics_trip_receive_transfer_reconciled_v1(
  p_tenant_id uuid,
  p_trip_id uuid,
  p_transfer_id uuid,
  p_device_id uuid default null,
  p_lines jsonb default '[]'::jsonb,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $function$
declare
  t public.transport_logistics_trips%rowtype;
  st public.stock_transfers%rowtype;
  rr public.transport_logistics_receipts%rowtype;
  r public.stock_transfer_items%rowtype;
  v_line jsonb;
  v_result jsonb;
  v_receipt_id uuid := gen_random_uuid();
  v_receipt_number text;
  v_good numeric := 0;
  v_damaged numeric := 0;
  v_missing numeric := 0;
  v_returned numeric := 0;
  v_all_received boolean;
  v_event_type text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;

  select * into t from public.transport_logistics_trips where id=p_trip_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Trip not found'; end if;

  select * into rr from public.transport_logistics_receipts where tenant_id=p_tenant_id and trip_id=p_trip_id and stock_transfer_id=p_transfer_id;
  if found then
    return jsonb_build_object('success',true,'idempotent',true,'status','received','trip_id',p_trip_id,'transfer_id',p_transfer_id,'receipt_id',rr.id,'receipt_number',rr.receipt_number,'good_quantity',rr.good_quantity,'damaged_quantity',rr.damaged_quantity,'missing_quantity',rr.missing_quantity,'returned_quantity',rr.returned_quantity);
  end if;

  if t.status<>'arrived' then raise exception 'Trip must be ARRIVED before receiving stock'; end if;

  if not exists(select 1 from public.transport_logistics_trip_documents d where d.tenant_id=p_tenant_id and d.trip_id=p_trip_id and d.stock_transfer_id=p_transfer_id and d.active) then raise exception 'Transfer is not linked to this trip'; end if;

  select * into st from public.stock_transfers where tenant_id=p_tenant_id and id=p_transfer_id for update;
  if not found then raise exception 'Transfer not found'; end if;

  perform private.v4_location_access(p_tenant_id,st.to_location_id,'operate');
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.transfer') and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Stock transfer permission required'; end if;

  if st.status not in ('in_transit','dispatched') then raise exception 'Only in-transit transfers can be reconciled'; end if;
  if jsonb_typeof(coalesce(p_lines,'[]'::jsonb))<>'array' then raise exception 'Receipt lines must be a JSON array'; end if;
  if jsonb_array_length(coalesce(p_lines,'[]'::jsonb))<>(select count(*) from public.stock_transfer_items where transfer_id=p_transfer_id) then raise exception 'Every dispatched transfer line must be included exactly once'; end if;

  if exists(
    select 1 from jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) x
    where nullif(x->>'transfer_item_id','') is null
       or not exists(select 1 from public.stock_transfer_items i where i.transfer_id=p_transfer_id and i.id::text=x->>'transfer_item_id')
  ) then raise exception 'Receipt contains an invalid transfer item'; end if;

  if exists(
    select 1 from (
      select x->>'transfer_item_id' as item_id,count(*) as c
      from jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) x
      group by x->>'transfer_item_id' having count(*)<>1
    ) q
  ) then raise exception 'Each transfer item must appear exactly once'; end if;

  v_receipt_number:='RCV-'||to_char(current_date,'YYYYMMDD')||'-'||upper(substr(replace(v_receipt_id::text,'-',''),1,8));
  insert into public.transport_logistics_receipts(id,tenant_id,trip_id,stock_transfer_id,receipt_number,status,note)
  values(v_receipt_id,p_tenant_id,p_trip_id,p_transfer_id,v_receipt_number,'finalized',nullif(trim(coalesce(p_note,'')),''));

  for r in select * from public.stock_transfer_items where transfer_id=p_transfer_id order by id loop
    select x into v_line from jsonb_array_elements(p_lines) x where x->>'transfer_item_id'=r.id::text limit 1;
    v_result:=private.v610_logistics_receive_line(p_tenant_id,v_receipt_id,p_transfer_id,st.from_location_id,st.to_location_id,st.transfer_number,p_device_id,r.id,v_line);
    v_good:=v_good+coalesce((v_result->>'good_quantity')::numeric,0);
    v_damaged:=v_damaged+coalesce((v_result->>'damaged_quantity')::numeric,0);
    v_missing:=v_missing+coalesce((v_result->>'missing_quantity')::numeric,0);
    v_returned:=v_returned+coalesce((v_result->>'returned_quantity')::numeric,0);
  end loop;

  update public.stock_transfer_allocations_v485 set status='received',received_at=now(),updated_at=now() where tenant_id=p_tenant_id and transfer_id=p_transfer_id and status='in_transit';
  update public.transport_logistics_receipts set good_quantity=v_good,damaged_quantity=v_damaged,missing_quantity=v_missing,returned_quantity=v_returned where id=v_receipt_id;
  update public.stock_transfers set status='received',received_by=auth.uid(),received_at=now(),receive_note=nullif(trim(coalesce(p_note,'')),''),updated_at=now() where id=p_transfer_id;

  v_event_type:=case when v_damaged+v_missing+v_returned>0 then 'received_with_variance' else 'received' end;
  perform private.v485_transfer_history_add(p_tenant_id,p_transfer_id,v_event_type,case when st.status='dispatched' then 'in_transit' else st.status end,'received',p_note,jsonb_build_object('receipt_id',v_receipt_id,'receipt_number',v_receipt_number,'good_quantity',v_good,'damaged_quantity',v_damaged,'missing_quantity',v_missing,'returned_quantity',v_returned));
  perform private.thq_sync_bump_v480(p_tenant_id,'inventory','stock_transfer',p_transfer_id::text,'received');

  insert into public.transport_logistics_trip_events(tenant_id,trip_id,event_type,from_status,to_status,event_data,actor_user_id)
  values(p_tenant_id,p_trip_id,case when v_event_type='received' then 'transfer_received' else 'transfer_received_with_variance' end,t.status,t.status,jsonb_build_object('transfer_id',p_transfer_id,'transfer_number',st.transfer_number,'receipt_id',v_receipt_id,'receipt_number',v_receipt_number,'good_quantity',v_good,'damaged_quantity',v_damaged,'missing_quantity',v_missing,'returned_quantity',v_returned),auth.uid());

  select not exists(
    select 1 from public.transport_logistics_trip_documents d
    join public.stock_transfers x on x.id=d.stock_transfer_id and x.tenant_id=d.tenant_id
    where d.tenant_id=p_tenant_id and d.trip_id=p_trip_id and d.active and x.status<>'received'
  ) into v_all_received;

  if v_all_received then
    update public.transport_logistics_trips set status='received',received_at=coalesce(received_at,now()),updated_by=auth.uid(),updated_at=now() where id=p_trip_id;
    insert into public.transport_logistics_trip_events(tenant_id,trip_id,event_type,from_status,to_status,event_data,actor_user_id)
    values(p_tenant_id,p_trip_id,'trip_received',t.status,'received',jsonb_build_object('receipt_id',v_receipt_id,'last_transfer_id',p_transfer_id),auth.uid());
  end if;

  perform private.business_audit_write_v471(p_tenant_id,'logistics_receipt_finalized','transport_logistics_receipt',v_receipt_id,v_receipt_number,null,jsonb_build_object('trip_id',p_trip_id,'transfer_id',p_transfer_id,'transfer_number',st.transfer_number,'good_quantity',v_good,'damaged_quantity',v_damaged,'missing_quantity',v_missing,'returned_quantity',v_returned));

  return jsonb_build_object('success',true,'status','received','trip_status',case when v_all_received then 'received' else t.status end,'trip_id',p_trip_id,'transfer_id',p_transfer_id,'transfer_number',st.transfer_number,'receipt_id',v_receipt_id,'receipt_number',v_receipt_number,'good_quantity',v_good,'damaged_quantity',v_damaged,'missing_quantity',v_missing,'returned_quantity',v_returned,'has_variance',(v_damaged+v_missing+v_returned)>0);
end
$function$;

revoke execute on function public.logistics_trip_receive_transfer_reconciled_v1(uuid,uuid,uuid,uuid,jsonb,text) from public, anon;
grant execute on function public.logistics_trip_receive_transfer_reconciled_v1(uuid,uuid,uuid,uuid,jsonb,text) to authenticated, service_role;;
