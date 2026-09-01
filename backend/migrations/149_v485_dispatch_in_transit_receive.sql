-- THQ ERP V4.8.5 — dispatch, in-transit and receive.
begin;

create or replace function public.inventory_transfer_dispatch_v485(
  p_tenant_id uuid,p_transfer_id uuid,p_device_id uuid default null,p_dispatch_note text default null,p_transport_reference text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.stock_transfers%rowtype;r public.stock_transfer_items%rowtype;a record;v_reserved numeric;v_serial text;v_batch text;
begin
  select * into v from public.stock_transfers where tenant_id=p_tenant_id and id=p_transfer_id for update;
  if not found then raise exception 'Transfer not found';end if;
  perform private.v4_location_access(p_tenant_id,v.from_location_id,'operate');
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.transfer') and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Stock transfer permission required';end if;
  if v.status in('in_transit','dispatched') then
    return jsonb_build_object('success',true,'transfer_id',v.id,'transfer_number',v.transfer_number,'status','in_transit','idempotent',true);
  end if;
  if v.status<>'approved' then raise exception 'Only approved transfers can be dispatched';end if;
  if not coalesce(v.reservation_applied,false) then raise exception 'Transfer reservation is missing; cancel and recreate this transfer';end if;

  for r in select * from public.stock_transfer_items where transfer_id=v.id order by id loop
    select reserved_quantity into v_reserved from public.location_stock_balances
      where tenant_id=p_tenant_id and location_id=v.from_location_id and variant_id=r.variant_id for update;
    if coalesce(v_reserved,0)+0.000001<r.quantity then raise exception 'Reserved stock is inconsistent for transfer line %',r.id;end if;

    if r.tracking_mode='serial' then
      if (select count(*) from public.stock_transfer_allocations_v485 where transfer_item_id=r.id and status='reserved' and serial_id is not null)<>r.quantity::bigint then
        raise exception 'Serial allocation is incomplete for transfer line %',r.id;
      end if;
    elsif r.tracking_mode='batch' then
      if abs(coalesce((select sum(quantity) from public.stock_transfer_allocations_v485 where transfer_item_id=r.id and status='reserved' and batch_id is not null),0)-r.quantity)>0.000001 then
        raise exception 'Batch allocation is incomplete for transfer line %',r.id;
      end if;
    end if;

    -- Release the aggregate reservation immediately before removing the source stock.
    update public.location_stock_balances set reserved_quantity=greatest(0,reserved_quantity-r.quantity),updated_at=now()
      where tenant_id=p_tenant_id and location_id=v.from_location_id and variant_id=r.variant_id;
    perform private.v4_location_stock_apply(p_tenant_id,v.from_location_id,r.variant_id,-r.quantity,'transfer_out','stock_transfer',v.id,v.transfer_number,'Dispatched / in transit',p_device_id,false);
    update public.stock_transfer_items set dispatched_quantity=r.quantity,updated_at=now() where id=r.id;

    for a in select * from public.stock_transfer_allocations_v485 where transfer_item_id=r.id and status='reserved' order by id loop
      if a.serial_id is not null then
        select serial_number into v_serial from public.inventory_serials_v483
          where id=a.serial_id and tenant_id=p_tenant_id and status='in_stock' and current_location_id=v.from_location_id and reserved_transfer_id=v.id for update;
        if v_serial is null then raise exception 'Reserved serial allocation changed before dispatch';end if;
        update public.inventory_serials_v483
          set status='in_transit',current_location_id=null,reserved_transfer_id=null,updated_at=now()
          where id=a.serial_id;
        insert into public.inventory_trace_events_v483(
          tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by
        ) values(
          p_tenant_id,r.variant_id,a.serial_id,'transfer_out',1,v.from_location_id,v.transfer_number,
          'transfer:'||v.id::text||':out:serial:'||a.serial_id::text,
          jsonb_build_object('from_location_id',v.from_location_id,'to_location_id',v.to_location_id,'serial_number',v_serial),v.id,r.id,auth.uid()
        ) on conflict do nothing;
      elsif a.batch_id is not null then
        select b.batch_number into v_batch from public.inventory_batches_v483 b where b.id=a.batch_id and b.tenant_id=p_tenant_id;
        update public.inventory_batch_balances_v483
          set reserved_quantity=greatest(0,reserved_quantity-a.quantity),quantity=quantity-a.quantity,updated_at=now()
          where tenant_id=p_tenant_id and batch_id=a.batch_id and location_id=v.from_location_id
            and reserved_quantity+0.000001>=a.quantity and quantity+0.000001>=a.quantity;
        if not found then raise exception 'Reserved batch allocation changed before dispatch: %',coalesce(v_batch,a.batch_id::text);end if;
        insert into public.inventory_trace_events_v483(
          tenant_id,variant_id,batch_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by
        ) values(
          p_tenant_id,r.variant_id,a.batch_id,'transfer_out',a.quantity,v.from_location_id,v.transfer_number,
          'transfer:'||v.id::text||':out:batch:'||a.batch_id::text,
          jsonb_build_object('from_location_id',v.from_location_id,'to_location_id',v.to_location_id,'batch_number',v_batch),v.id,r.id,auth.uid()
        ) on conflict do nothing;
      end if;
      update public.stock_transfer_allocations_v485 set status='in_transit',dispatched_at=now(),updated_at=now() where id=a.id;
    end loop;
  end loop;

  update public.stock_transfers
    set status='in_transit',reservation_applied=false,dispatched_by=auth.uid(),dispatched_at=now(),in_transit_at=now(),
        dispatch_note=nullif(trim(coalesce(p_dispatch_note,'')),''),
        transport_reference=coalesce(nullif(trim(coalesce(p_transport_reference,'')),''),transport_reference),updated_at=now()
    where id=v.id;
  perform private.v485_transfer_history_add(p_tenant_id,v.id,'dispatched','approved','in_transit',p_dispatch_note,jsonb_build_object('transport_reference',coalesce(nullif(trim(coalesce(p_transport_reference,'')),''),v.transport_reference)));
  perform private.thq_sync_bump_v480(p_tenant_id,'inventory','stock_transfer',v.id::text,'in_transit');
  return jsonb_build_object('success',true,'transfer_id',v.id,'transfer_number',v.transfer_number,'status','in_transit');
end$$;
grant execute on function public.inventory_transfer_dispatch_v485(uuid,uuid,uuid,text,text) to authenticated;

create or replace function public.inventory_transfer_receive_v485(
  p_tenant_id uuid,p_transfer_id uuid,p_device_id uuid default null,p_receive_note text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.stock_transfers%rowtype;r public.stock_transfer_items%rowtype;a record;v_serial text;v_batch text;
begin
  select * into v from public.stock_transfers where tenant_id=p_tenant_id and id=p_transfer_id for update;
  if not found then raise exception 'Transfer not found';end if;
  perform private.v4_location_access(p_tenant_id,v.to_location_id,'operate');
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.transfer') and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Stock transfer permission required';end if;
  if v.status='received' then
    return jsonb_build_object('success',true,'transfer_id',v.id,'transfer_number',v.transfer_number,'status','received','idempotent',true);
  end if;
  if v.status not in('in_transit','dispatched') then raise exception 'Only in-transit transfers can be received';end if;

  for r in select * from public.stock_transfer_items where transfer_id=v.id order by id loop
    if r.dispatched_quantity<=0 then raise exception 'Transfer line % was not dispatched',r.id;end if;
    perform public.inventory_location_assign_v4(p_tenant_id,v.to_location_id,r.variant_id,true,null,null,null);
    perform private.v4_location_stock_apply(p_tenant_id,v.to_location_id,r.variant_id,r.dispatched_quantity,'transfer_in','stock_transfer',v.id,v.transfer_number,'Received from transfer',p_device_id,false);

    for a in select * from public.stock_transfer_allocations_v485 where transfer_item_id=r.id and status='in_transit' order by id loop
      if a.serial_id is not null then
        select serial_number into v_serial from public.inventory_serials_v483 where id=a.serial_id and tenant_id=p_tenant_id and status='in_transit' for update;
        if v_serial is null then raise exception 'In-transit serial allocation is missing';end if;
        update public.inventory_serials_v483
          set status='in_stock',current_location_id=v.to_location_id,reserved_transfer_id=null,updated_at=now()
          where id=a.serial_id;
        insert into public.inventory_trace_events_v483(
          tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by
        ) values(
          p_tenant_id,r.variant_id,a.serial_id,'transfer_in',1,v.to_location_id,v.transfer_number,
          'transfer:'||v.id::text||':in:serial:'||a.serial_id::text,
          jsonb_build_object('from_location_id',v.from_location_id,'to_location_id',v.to_location_id,'serial_number',v_serial),v.id,r.id,auth.uid()
        ) on conflict do nothing;
      elsif a.batch_id is not null then
        select batch_number into v_batch from public.inventory_batches_v483 where id=a.batch_id and tenant_id=p_tenant_id;
        insert into public.inventory_batch_balances_v483(tenant_id,batch_id,location_id,quantity,damaged_quantity,reserved_quantity,updated_at)
          values(p_tenant_id,a.batch_id,v.to_location_id,a.quantity,0,0,now())
          on conflict(tenant_id,batch_id,location_id) do update set quantity=public.inventory_batch_balances_v483.quantity+excluded.quantity,updated_at=now();
        update public.inventory_batches_v483 set status='active',updated_at=now() where id=a.batch_id and tenant_id=p_tenant_id and status='exhausted';
        insert into public.inventory_trace_events_v483(
          tenant_id,variant_id,batch_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by
        ) values(
          p_tenant_id,r.variant_id,a.batch_id,'transfer_in',a.quantity,v.to_location_id,v.transfer_number,
          'transfer:'||v.id::text||':in:batch:'||a.batch_id::text,
          jsonb_build_object('from_location_id',v.from_location_id,'to_location_id',v.to_location_id,'batch_number',v_batch),v.id,r.id,auth.uid()
        ) on conflict do nothing;
      end if;
      update public.stock_transfer_allocations_v485 set status='received',received_at=now(),updated_at=now() where id=a.id;
    end loop;
    update public.stock_transfer_items set received_quantity=r.dispatched_quantity,updated_at=now() where id=r.id;
  end loop;

  update public.stock_transfers set status='received',received_by=auth.uid(),received_at=now(),receive_note=nullif(trim(coalesce(p_receive_note,'')),''),updated_at=now() where id=v.id;
  perform private.v485_transfer_history_add(p_tenant_id,v.id,'received',v.status,'received',p_receive_note);
  perform private.thq_sync_bump_v480(p_tenant_id,'inventory','stock_transfer',v.id::text,'received');
  return jsonb_build_object('success',true,'transfer_id',v.id,'transfer_number',v.transfer_number,'status','received');
end$$;
grant execute on function public.inventory_transfer_receive_v485(uuid,uuid,uuid,text) to authenticated;

-- Keep legacy RPC names safe while old clients are phased out.
create or replace function public.inventory_transfer_dispatch_v4(p_tenant_id uuid,p_transfer_id uuid,p_device_id uuid default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$begin
  perform public.inventory_transfer_dispatch_v485(p_tenant_id,p_transfer_id,p_device_id,null,null);
end$$;
grant execute on function public.inventory_transfer_dispatch_v4(uuid,uuid,uuid) to authenticated;

create or replace function public.inventory_transfer_receive_v4(p_tenant_id uuid,p_transfer_id uuid,p_device_id uuid default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$begin
  perform public.inventory_transfer_receive_v485(p_tenant_id,p_transfer_id,p_device_id,null);
end$$;
grant execute on function public.inventory_transfer_receive_v4(uuid,uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(149,'4.8.5','Warehouse & Transfers','Dispatch removes source stock and moves allocated serials/batches to In Transit; receive alone adds destination stock and completes tracked provenance.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.5 migration 149 dispatch/in-transit/receive applied' as status;
