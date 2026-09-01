-- THQ ERP V4.8.5 — transfer request, reservation and approval.
begin;

create or replace function private.v485_transfer_history_add(
  p_tenant_id uuid,p_transfer_id uuid,p_event_type text,p_from_status text,p_to_status text,p_note text default null,p_metadata jsonb default '{}'::jsonb
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  insert into public.stock_transfer_history_v485(tenant_id,transfer_id,event_type,from_status,to_status,note,metadata,changed_by)
  values(p_tenant_id,p_transfer_id,p_event_type,nullif(p_from_status,''),nullif(p_to_status,''),nullif(trim(coalesce(p_note,'')),''),coalesce(p_metadata,'{}'::jsonb),auth.uid());
end$$;
revoke all on function private.v485_transfer_history_add(uuid,uuid,text,text,text,text,jsonb) from public;

create or replace function private.v485_transfer_release_reservation(p_transfer_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.stock_transfers%rowtype;r record;a record;
begin
  select * into v from public.stock_transfers where id=p_transfer_id for update;
  if not found or not coalesce(v.reservation_applied,false) then return;end if;

  for r in select * from public.stock_transfer_items where transfer_id=v.id order by id loop
    update public.location_stock_balances
      set reserved_quantity=greatest(0,reserved_quantity-r.quantity),updated_at=now()
    where tenant_id=v.tenant_id and location_id=v.from_location_id and variant_id=r.variant_id;
  end loop;

  for a in select * from public.stock_transfer_allocations_v485 where transfer_id=v.id and status='reserved' order by id loop
    if a.serial_id is not null then
      update public.inventory_serials_v483
        set reserved_transfer_id=null,updated_at=now()
      where id=a.serial_id and tenant_id=v.tenant_id and reserved_transfer_id=v.id;
    elsif a.batch_id is not null then
      update public.inventory_batch_balances_v483
        set reserved_quantity=greatest(0,reserved_quantity-a.quantity),updated_at=now()
      where tenant_id=v.tenant_id and batch_id=a.batch_id and location_id=v.from_location_id;
    end if;
    update public.stock_transfer_allocations_v485
      set status='released',released_at=now(),updated_at=now()
    where id=a.id;
  end loop;

  update public.stock_transfers set reservation_applied=false,updated_at=now() where id=v.id;
end$$;
revoke all on function private.v485_transfer_release_reservation(uuid,text) from public;

create or replace function public.inventory_transfer_request_v485(
  p_tenant_id uuid,p_from_location_id uuid,p_to_location_id uuid,p_items jsonb,p_notes text default null,
  p_expected_arrival_date date default null,p_transport_reference text default null,p_request_id text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v_existing jsonb;v_id uuid:=gen_random_uuid();v_no text;x jsonb;v_variant uuid;v_qty numeric;v_available numeric;v_mode text;
  v_item_id uuid;v_serials jsonb;s jsonb;v_serial text;v_serial_id uuid;v_serial_count numeric;v_seen_serial text[]:='{}'::text[];
  v_batches jsonb;b jsonb;v_batch_id uuid;v_batch_number text;v_batch_qty numeric;v_batch_available numeric;v_batch_sum numeric;v_seen_batch uuid[]:='{}'::uuid[];
  v_result jsonb;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is not null then
    v_existing:=private.v47_request_existing(p_tenant_id,p_request_id,'warehouse.transfer.request');
    if v_existing is not null then return v_existing;end if;
  end if;
  perform private.v4_location_access(p_tenant_id,p_from_location_id,'operate');
  perform private.v4_location_access(p_tenant_id,p_to_location_id,'view');
  perform private.warehouse_v485_permission(p_tenant_id,false);
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.transfer') and not private.erp_has_permission(p_tenant_id,'inventory.manage') then
    raise exception 'Stock transfer permission required';
  end if;
  if p_from_location_id=p_to_location_id then raise exception 'Source and destination must be different';end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Add at least one transfer item';end if;

  v_no:='TRF-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.stock_transfer_number_seq')::text,6,'0');
  insert into public.stock_transfers(
    id,tenant_id,transfer_number,from_location_id,to_location_id,status,notes,created_by,requested_by,requested_at,
    reservation_applied,expected_arrival_date,transport_reference,request_key,updated_at
  ) values(
    v_id,p_tenant_id,v_no,p_from_location_id,p_to_location_id,'requested',nullif(trim(coalesce(p_notes,'')),''),auth.uid(),auth.uid(),now(),
    true,p_expected_arrival_date,nullif(trim(coalesce(p_transport_reference,'')),''),nullif(trim(coalesce(p_request_id,'')),''),now()
  );

  for x in select value from jsonb_array_elements(p_items) loop
    v_variant:=nullif(x->>'variant_id','')::uuid;
    v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);
    if v_variant is null or not exists(select 1 from public.product_variants where tenant_id=p_tenant_id and id=v_variant) then raise exception 'Product does not belong to this business';end if;
    if v_qty<=0 then raise exception 'Transfer quantity must be positive';end if;
    v_mode:=private.v483_tracking_mode(p_tenant_id,v_variant);
    if v_mode='serial' and v_qty<>trunc(v_qty) then raise exception 'Serial-tracked transfer quantity must be whole base units';end if;
    perform private.v483_assert_reconciled(p_tenant_id,v_variant,p_from_location_id);

    insert into public.location_stock_balances(tenant_id,location_id,variant_id)
      values(p_tenant_id,p_from_location_id,v_variant) on conflict do nothing;
    select quantity-reserved_quantity-damaged_quantity-quarantine_quantity into v_available
      from public.location_stock_balances
      where tenant_id=p_tenant_id and location_id=p_from_location_id and variant_id=v_variant
      for update;
    if coalesce(v_available,0)+0.000001<v_qty then raise exception 'Insufficient available stock. Available: %, requested: %',coalesce(v_available,0),v_qty;end if;

    update public.location_stock_balances
      set reserved_quantity=reserved_quantity+v_qty,updated_at=now()
      where tenant_id=p_tenant_id and location_id=p_from_location_id and variant_id=v_variant;

    insert into public.stock_transfer_items(transfer_id,variant_id,quantity,note,tracking_mode,tracking_payload,updated_at)
      values(v_id,v_variant,v_qty,nullif(trim(coalesce(x->>'note','')),''),v_mode,coalesce(x->'tracking','{}'::jsonb),now())
      returning id into v_item_id;

    if v_mode='serial' then
      v_serials:=coalesce(x->'serial_numbers',x->'tracking'->'serial_numbers','[]'::jsonb);
      if jsonb_typeof(v_serials)<>'array' then raise exception 'serial_numbers must be an array';end if;
      select count(*)::numeric into v_serial_count from jsonb_array_elements(v_serials);
      if v_serial_count<>v_qty then raise exception 'Provide exactly % serial numbers for the transfer line',v_qty;end if;
      v_seen_serial:='{}'::text[];
      for s in select value from jsonb_array_elements(v_serials) loop
        v_serial:=trim(coalesce(case when jsonb_typeof(s)='string' then s#>>'{}' else s->>'serial_number' end,''));
        if v_serial='' then raise exception 'Serial number cannot be blank';end if;
        if lower(v_serial)=any(v_seen_serial) then raise exception 'Serial % is duplicated on the transfer',v_serial;end if;
        v_seen_serial:=array_append(v_seen_serial,lower(v_serial));
        select id into v_serial_id from public.inventory_serials_v483
          where tenant_id=p_tenant_id and variant_id=v_variant and current_location_id=p_from_location_id
            and status='in_stock' and reserved_transfer_id is null and lower(trim(serial_number))=lower(v_serial)
          for update;
        if v_serial_id is null then raise exception 'Serial % is not available at the source location',v_serial;end if;
        update public.inventory_serials_v483 set reserved_transfer_id=v_id,updated_at=now() where id=v_serial_id;
        insert into public.stock_transfer_allocations_v485(tenant_id,transfer_id,transfer_item_id,variant_id,serial_id,quantity,status,from_location_id,to_location_id,created_by)
          values(p_tenant_id,v_id,v_item_id,v_variant,v_serial_id,1,'reserved',p_from_location_id,p_to_location_id,auth.uid());
      end loop;
    elsif v_mode='batch' then
      v_batches:=coalesce(x->'batches',x->'tracking'->'batches','[]'::jsonb);
      if jsonb_typeof(v_batches)<>'array' or jsonb_array_length(v_batches)=0 then raise exception 'Batch-tracked transfers require batch allocations';end if;
      v_batch_sum:=0;v_seen_batch:='{}'::uuid[];
      for b in select value from jsonb_array_elements(v_batches) loop
        v_batch_qty:=coalesce(nullif(b->>'quantity','')::numeric,0);
        if v_batch_qty<=0 then raise exception 'Batch transfer quantity must be positive';end if;
        if nullif(b->>'batch_id','') is not null then
          v_batch_id:=(b->>'batch_id')::uuid;
        else
          v_batch_number:=trim(coalesce(b->>'batch_number',''));
          select id into v_batch_id from public.inventory_batches_v483
            where tenant_id=p_tenant_id and variant_id=v_variant and lower(trim(batch_number))=lower(v_batch_number);
        end if;
        if v_batch_id is null then raise exception 'Batch % was not found',coalesce(v_batch_number,'');end if;
        if not exists(
          select 1 from public.inventory_batches_v483 ib
          where ib.id=v_batch_id and ib.tenant_id=p_tenant_id and ib.variant_id=v_variant
        ) then raise exception 'Batch does not belong to the selected product/business';end if;
        if v_batch_id=any(v_seen_batch) then raise exception 'The same batch cannot appear twice on one transfer line';end if;
        v_seen_batch:=array_append(v_seen_batch,v_batch_id);
        select quantity-coalesce(reserved_quantity,0) into v_batch_available
          from public.inventory_batch_balances_v483
          where tenant_id=p_tenant_id and batch_id=v_batch_id and location_id=p_from_location_id
          for update;
        if coalesce(v_batch_available,0)+0.000001<v_batch_qty then raise exception 'Insufficient available quantity in batch %',coalesce(v_batch_number,v_batch_id::text);end if;
        update public.inventory_batch_balances_v483 set reserved_quantity=reserved_quantity+v_batch_qty,updated_at=now()
          where tenant_id=p_tenant_id and batch_id=v_batch_id and location_id=p_from_location_id;
        insert into public.stock_transfer_allocations_v485(tenant_id,transfer_id,transfer_item_id,variant_id,batch_id,quantity,status,from_location_id,to_location_id,created_by)
          values(p_tenant_id,v_id,v_item_id,v_variant,v_batch_id,v_batch_qty,'reserved',p_from_location_id,p_to_location_id,auth.uid());
        v_batch_sum:=v_batch_sum+v_batch_qty;
      end loop;
      if abs(v_batch_sum-v_qty)>0.000001 then raise exception 'Batch allocations % must equal transfer quantity %',v_batch_sum,v_qty;end if;
    end if;
  end loop;

  perform private.v485_transfer_history_add(p_tenant_id,v_id,'requested',null,'requested',p_notes,jsonb_build_object('expected_arrival_date',p_expected_arrival_date,'transport_reference',nullif(trim(coalesce(p_transport_reference,'')),'')));
  perform private.thq_sync_bump_v480(p_tenant_id,'inventory','stock_transfer',v_id::text,'requested');
  v_result:=jsonb_build_object('success',true,'transfer_id',v_id,'transfer_number',v_no,'status','requested','reservation_applied',true);
  if nullif(trim(coalesce(p_request_id,'')),'') is not null then
    v_result:=private.v47_request_complete(p_tenant_id,p_request_id,'warehouse.transfer.request',v_result);
  end if;
  return v_result;
end$$;
grant execute on function public.inventory_transfer_request_v485(uuid,uuid,uuid,jsonb,text,date,text,text) to authenticated;

create or replace function public.inventory_transfer_decide_v485(
  p_tenant_id uuid,p_transfer_id uuid,p_approve boolean,p_note text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.stock_transfers%rowtype;v_to text;
begin
  select * into v from public.stock_transfers where tenant_id=p_tenant_id and id=p_transfer_id for update;
  if not found then raise exception 'Transfer not found';end if;
  perform private.v4_location_access(p_tenant_id,v.from_location_id,'manage');
  perform private.warehouse_v485_permission(p_tenant_id,true);
  if v.status<>'requested' then raise exception 'Only requested transfers can be approved or rejected';end if;
  if coalesce(p_approve,false) then
    update public.stock_transfers set status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=v.id;
    v_to:='approved';
    perform private.v485_transfer_history_add(p_tenant_id,v.id,'approved','requested','approved',p_note);
  else
    if trim(coalesce(p_note,''))='' then raise exception 'Rejection reason is required';end if;
    perform private.v485_transfer_release_reservation(v.id,p_note);
    update public.stock_transfers set status='rejected',rejected_by=auth.uid(),rejected_at=now(),rejection_reason=trim(p_note),updated_at=now() where id=v.id;
    v_to:='rejected';
    perform private.v485_transfer_history_add(p_tenant_id,v.id,'rejected','requested','rejected',p_note);
  end if;
  perform private.thq_sync_bump_v480(p_tenant_id,'inventory','stock_transfer',v.id::text,v_to);
  return jsonb_build_object('success',true,'transfer_id',v.id,'transfer_number',v.transfer_number,'status',v_to);
end$$;
grant execute on function public.inventory_transfer_decide_v485(uuid,uuid,boolean,text) to authenticated;

create or replace function public.inventory_transfer_cancel_v485(
  p_tenant_id uuid,p_transfer_id uuid,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.stock_transfers%rowtype;
begin
  select * into v from public.stock_transfers where tenant_id=p_tenant_id and id=p_transfer_id for update;
  if not found then raise exception 'Transfer not found';end if;
  perform private.v4_location_access(p_tenant_id,v.from_location_id,'view');
  if v.status not in('draft','requested','approved') then raise exception 'In-transit/received transfers cannot be cancelled';end if;
  if auth.uid()<>v.created_by and not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Transfer cancel permission required';end if;
  perform private.v485_transfer_release_reservation(v.id,p_reason);
  update public.stock_transfers set status='cancelled',cancelled_by=auth.uid(),cancelled_at=now(),cancel_reason=nullif(trim(coalesce(p_reason,'')),''),updated_at=now() where id=v.id;
  perform private.v485_transfer_history_add(p_tenant_id,v.id,'cancelled',v.status,'cancelled',p_reason);
  perform private.thq_sync_bump_v480(p_tenant_id,'inventory','stock_transfer',v.id::text,'cancelled');
  return jsonb_build_object('success',true,'transfer_id',v.id,'transfer_number',v.transfer_number,'status','cancelled');
end$$;
grant execute on function public.inventory_transfer_cancel_v485(uuid,uuid,text) to authenticated;

-- Compatibility wrappers: clients still calling the older v4.8.3/v4.2 names get
-- the v4.8.5 tracked-safe reservation/approval behavior.
create or replace function public.inventory_transfer_create_v483(p_tenant_id uuid,p_from_location_id uuid,p_to_location_id uuid,p_items jsonb,p_notes text,p_request_id text)
returns jsonb language sql security definer set search_path=public,private,pg_temp as $$
  select public.inventory_transfer_request_v485($1,$2,$3,$4,$5,null,null,$6)
$$;
grant execute on function public.inventory_transfer_create_v483(uuid,uuid,uuid,jsonb,text,text) to authenticated;

create or replace function public.inventory_transfer_approve_v42(p_tenant_id uuid,p_transfer_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$begin
  perform public.inventory_transfer_decide_v485(p_tenant_id,p_transfer_id,true,null);
end$$;
grant execute on function public.inventory_transfer_approve_v42(uuid,uuid) to authenticated;

create or replace function public.inventory_transfer_reject_v42(p_tenant_id uuid,p_transfer_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$begin
  perform public.inventory_transfer_decide_v485(p_tenant_id,p_transfer_id,false,p_reason);
end$$;
grant execute on function public.inventory_transfer_reject_v42(uuid,uuid,text) to authenticated;

create or replace function public.inventory_transfer_cancel_v42(p_tenant_id uuid,p_transfer_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$begin
  perform public.inventory_transfer_cancel_v485(p_tenant_id,p_transfer_id,p_reason);
end$$;
grant execute on function public.inventory_transfer_cancel_v42(uuid,uuid,text) to authenticated;

-- Make customer sales reservation-aware. This preserves the v4.8.3 FEFO engine
-- but removes quantities/serials committed to warehouse transfers from saleable stock.
create or replace function private.v483_apply_batch_sale(
 p_tenant_id uuid,p_variant_id uuid,p_sale_id uuid,p_sale_item_id uuid,p_customer_id uuid,p_location_id uuid,p_sale_date date,p_quantity numeric,p_requested jsonb
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_remaining numeric:=p_quantity;v_out jsonb:='[]'::jsonb;v_allow_expired boolean:=false;r record;x jsonb;v_batch_id uuid;v_take numeric;v_requested_qty numeric;v_batch_number text;v_seen uuid[]:='{}'::uuid[];v_ref text;v_available numeric;
begin
 select allow_expired_sale into v_allow_expired from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id;
 select sale_number into v_ref from public.sales where tenant_id=p_tenant_id and id=p_sale_id;
 if jsonb_array_length(coalesce(p_requested,'[]'::jsonb))>0 then
  for x in select value from jsonb_array_elements(p_requested) loop
   v_requested_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);if v_requested_qty<=0 then raise exception 'Requested batch quantity must be positive';end if;
   v_batch_id:=null;
   if nullif(x->>'batch_id','') is not null then v_batch_id:=(x->>'batch_id')::uuid;else
    v_batch_number:=trim(coalesce(x->>'batch_number',''));select id into v_batch_id from public.inventory_batches_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id and lower(trim(batch_number))=lower(v_batch_number);end if;
   if v_batch_id is null then raise exception 'Batch not found for tracked product';end if;
   if v_batch_id=any(v_seen) then raise exception 'The same batch cannot appear twice on one sale line';end if;v_seen:=array_append(v_seen,v_batch_id);
   select b.batch_number,b.expiry_on,bb.quantity-coalesce(bb.reserved_quantity,0) available_quantity into r
     from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id
     where b.tenant_id=p_tenant_id and b.id=v_batch_id and b.variant_id=p_variant_id and bb.location_id=p_location_id and b.status='active' for update of bb;
   v_available:=coalesce(r.available_quantity,0);
   if not found or v_available+0.000001<v_requested_qty then raise exception 'Insufficient unreserved quantity in selected batch %',coalesce(r.batch_number,v_batch_number);end if;
   if not coalesce(v_allow_expired,false) and r.expiry_on is not null and r.expiry_on<p_sale_date then raise exception 'Batch % expired on %',r.batch_number,r.expiry_on;end if;
   update public.inventory_batch_balances_v483 set quantity=quantity-v_requested_qty,updated_at=now() where tenant_id=p_tenant_id and batch_id=v_batch_id and location_id=p_location_id;
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,customer_id,sale_id,sale_item_id,reference_number,source_key,created_by)
     values(p_tenant_id,p_variant_id,v_batch_id,'sale',v_requested_qty,p_location_id,p_customer_id,p_sale_id,p_sale_item_id,v_ref,'sale:'||p_sale_id::text||':item:'||p_sale_item_id::text||':batch:'||v_batch_id::text,auth.uid());
   perform private.v483_create_warranty(p_tenant_id,p_variant_id,null,v_batch_id,p_customer_id,p_sale_id,p_sale_item_id,v_requested_qty,p_sale_date);
   v_remaining:=v_remaining-v_requested_qty;v_out:=v_out||jsonb_build_array(jsonb_build_object('batch_id',v_batch_id,'batch_number',r.batch_number,'quantity',v_requested_qty,'expiry_on',r.expiry_on));
  end loop;
  if abs(v_remaining)>0.000001 then raise exception 'Selected batch quantities must equal required base quantity %',p_quantity;end if;
 else
  for r in
    select b.id batch_id,b.batch_number,b.expiry_on,bb.quantity-coalesce(bb.reserved_quantity,0) available_quantity
    from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id
    where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and bb.location_id=p_location_id
      and bb.quantity-coalesce(bb.reserved_quantity,0)>0 and b.status='active'
      and (coalesce(v_allow_expired,false) or b.expiry_on is null or b.expiry_on>=p_sale_date)
    order by (b.expiry_on is null),b.expiry_on,b.created_at,b.batch_number for update of bb
  loop
   exit when v_remaining<=0.000001;v_take:=least(v_remaining,r.available_quantity);
   update public.inventory_batch_balances_v483 set quantity=quantity-v_take,updated_at=now() where tenant_id=p_tenant_id and batch_id=r.batch_id and location_id=p_location_id;
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,customer_id,sale_id,sale_item_id,reference_number,source_key,metadata,created_by)
     values(p_tenant_id,p_variant_id,r.batch_id,'sale',v_take,p_location_id,p_customer_id,p_sale_id,p_sale_item_id,v_ref,'sale:'||p_sale_id::text||':item:'||p_sale_item_id::text||':batch:'||r.batch_id::text,jsonb_build_object('allocation','FEFO'),auth.uid());
   perform private.v483_create_warranty(p_tenant_id,p_variant_id,null,r.batch_id,p_customer_id,p_sale_id,p_sale_item_id,v_take,p_sale_date);
   v_remaining:=v_remaining-v_take;v_out:=v_out||jsonb_build_array(jsonb_build_object('batch_id',r.batch_id,'batch_number',r.batch_number,'quantity',v_take,'expiry_on',r.expiry_on));
  end loop;
  if v_remaining>0.000001 then raise exception 'Insufficient eligible unreserved batch stock. Required %, unavailable %',p_quantity,v_remaining;end if;
 end if;
 update public.inventory_batches_v483 b set status='exhausted',updated_at=now()
 where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and b.status='active'
   and not exists(select 1 from public.inventory_batch_balances_v483 bb where bb.tenant_id=b.tenant_id and bb.batch_id=b.id and bb.quantity>0);
 return v_out;
end$$;
revoke all on function private.v483_apply_batch_sale(uuid,uuid,uuid,uuid,uuid,uuid,date,numeric,jsonb) from public;

create or replace function private.v483_apply_sale_trace(
 p_tenant_id uuid,p_sale_id uuid,p_customer_id uuid,p_location_id uuid,p_sale_date date,p_items jsonb
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare x jsonb;v_mode text;v_variant uuid;v_qty numeric;v_item_id uuid;v_serials jsonb;v_count numeric;s jsonb;v_serial text;v_serial_id uuid;v_ref text;v_batches jsonb;
begin
 if exists(select 1 from public.inventory_trace_events_v483 where tenant_id=p_tenant_id and sale_id=p_sale_id) then return;end if;
 select sale_number into v_ref from public.sales where tenant_id=p_tenant_id and id=p_sale_id;
 for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
  v_variant:=(x->>'variant_id')::uuid;v_mode:=private.v483_tracking_mode(p_tenant_id,v_variant);if v_mode='none' then continue;end if;
  v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);select id into v_item_id from public.sale_items where sale_id=p_sale_id and variant_id=v_variant limit 1;if v_item_id is null then raise exception 'Sale line not found for tracked product';end if;
  if v_mode='serial' then
   if v_qty<>trunc(v_qty) then raise exception 'Serial-tracked product % requires whole base units',v_variant;end if;
   v_serials:=coalesce(x->'serial_numbers','[]'::jsonb);select count(*)::numeric into v_count from jsonb_array_elements(v_serials);if v_count<>v_qty then raise exception 'Provide exactly % serial numbers for tracked sale line',v_qty;end if;
   for s in select value from jsonb_array_elements(v_serials) loop
    v_serial:=trim(coalesce(case when jsonb_typeof(s)='string' then s#>>'{}' else s->>'serial_number' end,''));
    select id into v_serial_id from public.inventory_serials_v483
      where tenant_id=p_tenant_id and variant_id=v_variant and current_location_id=p_location_id and status='in_stock'
        and reserved_transfer_id is null and lower(trim(serial_number))=lower(v_serial) for update;
    if v_serial_id is null then raise exception 'Serial % is not available at the selected store (it may be reserved for transfer)',v_serial;end if;
    update public.inventory_serials_v483 set status='sold',current_location_id=null,customer_id=p_customer_id,sale_id=p_sale_id,sale_item_id=v_item_id,sold_at=now(),updated_at=now() where id=v_serial_id;
    insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,customer_id,sale_id,sale_item_id,reference_number,source_key,created_by)
      values(p_tenant_id,v_variant,v_serial_id,'sale',1,p_location_id,p_customer_id,p_sale_id,v_item_id,v_ref,'sale:'||p_sale_id::text||':serial:'||v_serial_id::text,auth.uid());
    perform private.v483_create_warranty(p_tenant_id,v_variant,v_serial_id,null,p_customer_id,p_sale_id,v_item_id,1,p_sale_date);
   end loop;
  else
   v_batches:=coalesce(x->'batches','[]'::jsonb);perform private.v483_apply_batch_sale(p_tenant_id,v_variant,p_sale_id,v_item_id,p_customer_id,p_location_id,p_sale_date,v_qty,v_batches);
  end if;
 end loop;
end$$;
revoke all on function private.v483_apply_sale_trace(uuid,uuid,uuid,uuid,date,jsonb) from public;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(148,'4.8.5','Warehouse & Transfers','Tracked-safe transfer requests reserve aggregate, serial and batch stock; PO-style approval/rejection/cancellation releases reservations safely; sales exclude transfer-reserved stock.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.5 migration 148 transfer request/approval applied' as status;
