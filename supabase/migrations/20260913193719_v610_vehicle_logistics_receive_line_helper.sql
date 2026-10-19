create or replace function private.v610_logistics_receive_line(
  p_tenant_id uuid,
  p_receipt_id uuid,
  p_transfer_id uuid,
  p_from_location_id uuid,
  p_to_location_id uuid,
  p_transfer_number text,
  p_device_id uuid,
  p_transfer_item_id uuid,
  p_line jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = public, private, pg_temp
as $function$
declare
  r public.stock_transfer_items%rowtype;
  a public.stock_transfer_allocations_v485%rowtype;
  v_mode text;
  v_good numeric := 0;
  v_damaged numeric := 0;
  v_missing numeric := 0;
  v_returned numeric := 0;
  v_agood numeric;
  v_adamaged numeric;
  v_amissing numeric;
  v_areturned numeric;
  v_outcome text;
  v_alloc_input jsonb;
  v_details jsonb := '[]'::jsonb;
  v_alloc_count integer;
  v_input_count integer;
  v_serial_number text;
  v_batch_number text;
begin
  select * into r
  from public.stock_transfer_items
  where id=p_transfer_item_id and transfer_id=p_transfer_id
  for update;
  if not found then raise exception 'Transfer line not found'; end if;
  if r.dispatched_quantity<=0 then raise exception 'Transfer line % was not dispatched',r.id; end if;

  v_mode:=coalesce(r.tracking_mode,'none');

  if v_mode='none' then
    v_good:=coalesce(nullif(p_line->>'good_quantity','')::numeric,0);
    v_damaged:=coalesce(nullif(p_line->>'damaged_quantity','')::numeric,0);
    v_missing:=coalesce(nullif(p_line->>'missing_quantity','')::numeric,0);
    v_returned:=coalesce(nullif(p_line->>'returned_quantity','')::numeric,0);
    if least(v_good,v_damaged,v_missing,v_returned)<0 then raise exception 'Receipt quantities cannot be negative for transfer line %',r.id; end if;
    if abs((v_good+v_damaged+v_missing+v_returned)-r.dispatched_quantity)>0.000001 then raise exception 'Receipt quantities must equal dispatched quantity for transfer line %',r.id; end if;

  elsif v_mode in ('serial','batch') then
    if jsonb_typeof(coalesce(p_line->'allocations','[]'::jsonb))<>'array' then raise exception 'Tracked allocations must be a JSON array for transfer line %',r.id; end if;

    select count(*) into v_alloc_count from public.stock_transfer_allocations_v485 where transfer_item_id=r.id and status='in_transit';
    v_input_count:=jsonb_array_length(coalesce(p_line->'allocations','[]'::jsonb));
    if v_input_count<>v_alloc_count then raise exception 'Every tracked allocation must be included for transfer line %',r.id; end if;

    if exists(
      select 1 from (
        select x->>'allocation_id' as allocation_id,count(*) as c
        from jsonb_array_elements(coalesce(p_line->'allocations','[]'::jsonb)) x
        group by x->>'allocation_id' having count(*)<>1
      ) q
    ) then raise exception 'Each tracked allocation must appear exactly once for transfer line %',r.id; end if;

    for a in
      select * from public.stock_transfer_allocations_v485
      where transfer_item_id=r.id and status='in_transit'
      order by id for update
    loop
      select x into v_alloc_input
      from jsonb_array_elements(p_line->'allocations') x
      where x->>'allocation_id'=a.id::text limit 1;
      if v_alloc_input is null then raise exception 'Tracked allocation % is missing from receipt payload',a.id; end if;

      v_agood:=0;v_adamaged:=0;v_amissing:=0;v_areturned:=0;
      v_serial_number:=null;v_batch_number:=null;

      if a.serial_id is not null then
        v_outcome:=lower(trim(coalesce(v_alloc_input->>'outcome','')));
        if v_outcome not in ('good','damaged','missing','returned') then raise exception 'Serial allocation % requires outcome good, damaged, missing or returned',a.id; end if;
        if v_outcome='good' then v_agood:=a.quantity;
        elsif v_outcome='damaged' then v_adamaged:=a.quantity;
        elsif v_outcome='missing' then v_amissing:=a.quantity;
        else v_areturned:=a.quantity; end if;

        select serial_number into v_serial_number
        from public.inventory_serials_v483
        where id=a.serial_id and tenant_id=p_tenant_id and variant_id=r.variant_id and status='in_transit'
        for update;
        if v_serial_number is null then raise exception 'In-transit serial allocation is missing or already resolved: %',a.id; end if;

        if v_agood>0 then
          update public.inventory_serials_v483 set status='in_stock',current_location_id=p_to_location_id,reserved_transfer_id=null,updated_at=now() where id=a.serial_id;
          insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by)
          values(p_tenant_id,r.variant_id,a.serial_id,'transfer_in',a.quantity,p_to_location_id,p_transfer_number,'logistics_receipt:'||p_receipt_id::text||':serial:'||a.serial_id::text||':good',jsonb_build_object('receipt_id',p_receipt_id,'outcome','good','from_location_id',p_from_location_id,'to_location_id',p_to_location_id),p_transfer_id,r.id,auth.uid()) on conflict do nothing;
        elsif v_adamaged>0 then
          update public.inventory_serials_v483 set status='quarantine',current_location_id=p_to_location_id,reserved_transfer_id=null,updated_at=now() where id=a.serial_id;
          insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by)
          values(p_tenant_id,r.variant_id,a.serial_id,'quarantine',a.quantity,p_to_location_id,p_transfer_number,'logistics_receipt:'||p_receipt_id::text||':serial:'||a.serial_id::text||':damaged',jsonb_build_object('receipt_id',p_receipt_id,'outcome','damaged','from_location_id',p_from_location_id,'to_location_id',p_to_location_id),p_transfer_id,r.id,auth.uid()) on conflict do nothing;
        elsif v_amissing>0 then
          update public.inventory_serials_v483 set status='missing',current_location_id=null,reserved_transfer_id=null,updated_at=now() where id=a.serial_id;
          insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by)
          values(p_tenant_id,r.variant_id,a.serial_id,'adjustment',a.quantity,null,p_transfer_number,'logistics_receipt:'||p_receipt_id::text||':serial:'||a.serial_id::text||':missing',jsonb_build_object('receipt_id',p_receipt_id,'outcome','missing','from_location_id',p_from_location_id,'to_location_id',p_to_location_id),p_transfer_id,r.id,auth.uid()) on conflict do nothing;
        else
          update public.inventory_serials_v483 set status='in_stock',current_location_id=p_from_location_id,reserved_transfer_id=null,updated_at=now() where id=a.serial_id;
          insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by)
          values(p_tenant_id,r.variant_id,a.serial_id,'transfer_in',a.quantity,p_from_location_id,p_transfer_number,'logistics_receipt:'||p_receipt_id::text||':serial:'||a.serial_id::text||':returned',jsonb_build_object('receipt_id',p_receipt_id,'outcome','returned_to_origin','from_location_id',p_to_location_id,'to_location_id',p_from_location_id),p_transfer_id,r.id,auth.uid()) on conflict do nothing;
        end if;

      elsif a.batch_id is not null then
        v_agood:=coalesce(nullif(v_alloc_input->>'good_quantity','')::numeric,0);
        v_adamaged:=coalesce(nullif(v_alloc_input->>'damaged_quantity','')::numeric,0);
        v_amissing:=coalesce(nullif(v_alloc_input->>'missing_quantity','')::numeric,0);
        v_areturned:=coalesce(nullif(v_alloc_input->>'returned_quantity','')::numeric,0);
        if least(v_agood,v_adamaged,v_amissing,v_areturned)<0 then raise exception 'Batch quantities cannot be negative for allocation %',a.id; end if;
        if abs((v_agood+v_adamaged+v_amissing+v_areturned)-a.quantity)>0.000001 then raise exception 'Batch quantities must equal dispatched allocation quantity for allocation %',a.id; end if;

        select batch_number into v_batch_number from public.inventory_batches_v483 where id=a.batch_id and tenant_id=p_tenant_id and variant_id=r.variant_id for update;
        if v_batch_number is null then raise exception 'Batch allocation is missing: %',a.id; end if;

        if v_agood+v_adamaged>0 then
          insert into public.inventory_batch_balances_v483(tenant_id,batch_id,location_id,quantity,damaged_quantity,reserved_quantity,updated_at)
          values(p_tenant_id,a.batch_id,p_to_location_id,v_agood+v_adamaged,v_adamaged,0,now())
          on conflict(tenant_id,batch_id,location_id) do update set quantity=public.inventory_batch_balances_v483.quantity+excluded.quantity,damaged_quantity=public.inventory_batch_balances_v483.damaged_quantity+excluded.damaged_quantity,updated_at=now();
          update public.inventory_batches_v483 set status='active',updated_at=now() where id=a.batch_id and tenant_id=p_tenant_id and status='exhausted';
          if v_agood>0 then
            insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by)
            values(p_tenant_id,r.variant_id,a.batch_id,'transfer_in',v_agood,p_to_location_id,p_transfer_number,'logistics_receipt:'||p_receipt_id::text||':batch:'||a.batch_id::text||':good',jsonb_build_object('receipt_id',p_receipt_id,'outcome','good','batch_number',v_batch_number),p_transfer_id,r.id,auth.uid()) on conflict do nothing;
          end if;
          if v_adamaged>0 then
            insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by)
            values(p_tenant_id,r.variant_id,a.batch_id,'quarantine',v_adamaged,p_to_location_id,p_transfer_number,'logistics_receipt:'||p_receipt_id::text||':batch:'||a.batch_id::text||':damaged',jsonb_build_object('receipt_id',p_receipt_id,'outcome','damaged','batch_number',v_batch_number),p_transfer_id,r.id,auth.uid()) on conflict do nothing;
          end if;
        end if;

        if v_areturned>0 then
          insert into public.inventory_batch_balances_v483(tenant_id,batch_id,location_id,quantity,damaged_quantity,reserved_quantity,updated_at)
          values(p_tenant_id,a.batch_id,p_from_location_id,v_areturned,0,0,now())
          on conflict(tenant_id,batch_id,location_id) do update set quantity=public.inventory_batch_balances_v483.quantity+excluded.quantity,updated_at=now();
          update public.inventory_batches_v483 set status='active',updated_at=now() where id=a.batch_id and tenant_id=p_tenant_id and status='exhausted';
          insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by)
          values(p_tenant_id,r.variant_id,a.batch_id,'transfer_in',v_areturned,p_from_location_id,p_transfer_number,'logistics_receipt:'||p_receipt_id::text||':batch:'||a.batch_id::text||':returned',jsonb_build_object('receipt_id',p_receipt_id,'outcome','returned_to_origin','batch_number',v_batch_number),p_transfer_id,r.id,auth.uid()) on conflict do nothing;
        end if;

        if v_amissing>0 then
          insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,reference_number,source_key,metadata,transfer_id,transfer_item_id,created_by)
          values(p_tenant_id,r.variant_id,a.batch_id,'adjustment',v_amissing,null,p_transfer_number,'logistics_receipt:'||p_receipt_id::text||':batch:'||a.batch_id::text||':missing',jsonb_build_object('receipt_id',p_receipt_id,'outcome','missing','batch_number',v_batch_number),p_transfer_id,r.id,auth.uid()) on conflict do nothing;
        end if;

        v_outcome:=case when ((case when v_agood>0 then 1 else 0 end)+(case when v_adamaged>0 then 1 else 0 end)+(case when v_amissing>0 then 1 else 0 end)+(case when v_areturned>0 then 1 else 0 end))>1 then 'mixed' when v_agood>0 then 'good' when v_adamaged>0 then 'damaged' when v_amissing>0 then 'missing' else 'returned' end;
      else
        raise exception 'Tracked allocation % has no serial or batch',a.id;
      end if;

      v_good:=v_good+v_agood;
      v_damaged:=v_damaged+v_adamaged;
      v_missing:=v_missing+v_amissing;
      v_returned:=v_returned+v_areturned;
      v_details:=v_details||jsonb_build_array(jsonb_build_object('allocation_id',a.id,'quantity',a.quantity,'serial_id',a.serial_id,'serial_number',v_serial_number,'batch_id',a.batch_id,'batch_number',v_batch_number,'outcome',v_outcome,'good_quantity',v_agood,'damaged_quantity',v_adamaged,'missing_quantity',v_amissing,'returned_quantity',v_areturned));
    end loop;

    if abs((v_good+v_damaged+v_missing+v_returned)-r.dispatched_quantity)>0.000001 then raise exception 'Tracked receipt does not reconcile to dispatched quantity for transfer line %',r.id; end if;
  else
    raise exception 'Unsupported tracking mode % for transfer line %',v_mode,r.id;
  end if;

  if v_good+v_damaged>0 then
    perform public.inventory_location_assign_v4(p_tenant_id,p_to_location_id,r.variant_id,true,null,null,null);
    perform private.v4_location_stock_apply(p_tenant_id,p_to_location_id,r.variant_id,v_good+v_damaged,'transfer_in','stock_transfer',p_transfer_id,p_transfer_number,case when v_damaged>0 then 'Logistics receipt: good '||v_good::text||', damaged '||v_damaged::text else 'Logistics receipt' end,p_device_id,false);
    if v_damaged>0 then update public.location_stock_balances set damaged_quantity=damaged_quantity+v_damaged,updated_at=now() where tenant_id=p_tenant_id and location_id=p_to_location_id and variant_id=r.variant_id; end if;
  end if;

  if v_returned>0 then
    perform public.inventory_location_assign_v4(p_tenant_id,p_from_location_id,r.variant_id,true,null,null,null);
    perform private.v4_location_stock_apply(p_tenant_id,p_from_location_id,r.variant_id,v_returned,'transfer_in','stock_transfer',p_transfer_id,p_transfer_number,'Returned to origin during logistics receipt reconciliation',p_device_id,false);
  end if;

  insert into public.transport_logistics_receipt_lines(tenant_id,receipt_id,transfer_item_id,variant_id,tracking_mode,dispatched_quantity,good_quantity,damaged_quantity,missing_quantity,returned_quantity,details)
  values(p_tenant_id,p_receipt_id,r.id,r.variant_id,v_mode,r.dispatched_quantity,v_good,v_damaged,v_missing,v_returned,v_details);

  update public.stock_transfer_items set received_quantity=r.dispatched_quantity,updated_at=now() where id=r.id;

  return jsonb_build_object('transfer_item_id',r.id,'good_quantity',v_good,'damaged_quantity',v_damaged,'missing_quantity',v_missing,'returned_quantity',v_returned);
end
$function$;;
