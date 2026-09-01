-- THQ ERP V4.8.5 — trace-aware physical stock count.
begin;

create or replace function public.inventory_stock_count_snapshot_v485(
  p_tenant_id uuid,p_location_id uuid,p_query text default ''
) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r record;q text:='%'||lower(trim(coalesce(p_query,'')))||'%';v_mode text;v_tracking jsonb;
begin
  perform private.v4_location_access(p_tenant_id,p_location_id,'view');
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.stock_count') and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Stock count permission required';end if;
  for r in
    select b.variant_id,p.name product_name,pv.sku,coalesce(b.quantity,0) system_quantity,coalesce(b.reserved_quantity,0) reserved_quantity,
      coalesce(b.damaged_quantity,0) damaged_quantity,coalesce(b.quarantine_quantity,0) quarantine_quantity
    from public.location_stock_balances b
    join public.product_variants pv on pv.id=b.variant_id and pv.tenant_id=b.tenant_id
    join public.products p on p.id=pv.product_id
    where b.tenant_id=p_tenant_id and b.location_id=p_location_id and p.item_type='stock'
      and (trim(coalesce(p_query,''))='' or lower(p.name) like q or lower(pv.sku) like q or lower(coalesce(pv.barcode,'')) like q)
    order by p.name,pv.sku
  loop
    v_mode:=private.v483_tracking_mode(p_tenant_id,r.variant_id);
    if v_mode='serial' then
      select jsonb_build_object('serial_numbers',coalesce(jsonb_agg(jsonb_build_object('serial_number',s.serial_number,'status',s.status) order by s.serial_number),'[]'::jsonb)) into v_tracking
      from public.inventory_serials_v483 s
      where s.tenant_id=p_tenant_id and s.variant_id=r.variant_id and s.current_location_id=p_location_id and s.status in('in_stock','quarantine');
    elsif v_mode='batch' then
      select jsonb_build_object('batches',coalesce(jsonb_agg(jsonb_build_object(
        'batch_id',b.id,'batch_number',b.batch_number,'manufactured_on',b.manufactured_on,'expiry_on',b.expiry_on,
        'quantity',bb.quantity,'damaged_quantity',coalesce(bb.damaged_quantity,0),'reserved_quantity',coalesce(bb.reserved_quantity,0)
      ) order by (b.expiry_on is null),b.expiry_on,b.batch_number),'[]'::jsonb)) into v_tracking
      from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id
      where b.tenant_id=p_tenant_id and b.variant_id=r.variant_id and bb.location_id=p_location_id and (bb.quantity<>0 or coalesce(bb.damaged_quantity,0)<>0 or coalesce(bb.reserved_quantity,0)<>0);
    else
      v_tracking:='{}'::jsonb;
    end if;
    return next jsonb_build_object(
      'variant_id',r.variant_id,'product_name',r.product_name,'sku',r.sku,'tracking_mode',v_mode,
      'system_quantity',r.system_quantity,'reserved_quantity',r.reserved_quantity,'damaged_quantity',r.damaged_quantity,'quarantine_quantity',r.quarantine_quantity,
      'available_quantity',greatest(r.system_quantity-r.reserved_quantity-r.damaged_quantity-r.quarantine_quantity,0),
      'count_blocked',r.reserved_quantity>0,'tracking',coalesce(v_tracking,'{}'::jsonb)
    );
  end loop;
end$$;
grant execute on function public.inventory_stock_count_snapshot_v485(uuid,uuid,text) to authenticated;

create or replace function public.inventory_stock_count_post_v485(
  p_tenant_id uuid,p_location_id uuid,p_items jsonb,p_notes text default null,p_device_id uuid default null,p_request_id text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v_existing jsonb;v_id uuid:=gen_random_uuid();v_no text;x jsonb;v_variant uuid;v_mode text;v_system numeric;v_reserved numeric;v_damage numeric;v_quarantine numeric;
  v_counted numeric;v_delta numeric;v_any_variance boolean:=false;v_tracking jsonb;
  v_serials jsonb;s jsonb;v_serial text;v_serial_row public.inventory_serials_v483%rowtype;v_seen_serial uuid[]:='{}'::uuid[];sr record;v_serial_damage numeric:=0;
  v_batches jsonb;b jsonb;v_batch_id uuid;v_batch_no text;v_batch_qty numeric;v_batch_damage numeric;v_old_qty numeric;v_old_damage numeric;v_old_reserved numeric;
  v_batch_total numeric;v_batch_damage_total numeric;v_seen_batch uuid[]:='{}'::uuid[];br record;v_mfg date;v_exp date;v_event_qty numeric;v_require_expiry boolean:=false;
  v_result jsonb;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is not null then
    v_existing:=private.v47_request_existing(p_tenant_id,p_request_id,'warehouse.stock_count');
    if v_existing is not null then return v_existing;end if;
  end if;
  perform private.v4_location_access(p_tenant_id,p_location_id,'manage');
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.stock_count') and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Stock count permission required';end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Add at least one counted product';end if;

  v_no:='CNT-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.stock_count_number_seq')::text,6,'0');
  insert into public.stock_counts(id,tenant_id,location_id,count_number,status,notes,created_by,request_key,reconciliation_status,updated_at)
  values(v_id,p_tenant_id,p_location_id,v_no,'draft',nullif(trim(coalesce(p_notes,'')),''),auth.uid(),nullif(trim(coalesce(p_request_id,'')),''),'pending',now());

  for x in select value from jsonb_array_elements(p_items) loop
    v_variant:=nullif(x->>'variant_id','')::uuid;
    if v_variant is null or not exists(select 1 from public.product_variants pv join public.products p on p.id=pv.product_id where pv.tenant_id=p_tenant_id and pv.id=v_variant and p.item_type='stock') then raise exception 'Stock-count product is invalid';end if;
    insert into public.location_stock_balances(tenant_id,location_id,variant_id) values(p_tenant_id,p_location_id,v_variant) on conflict do nothing;
    select quantity,reserved_quantity,damaged_quantity,quarantine_quantity into v_system,v_reserved,v_damage,v_quarantine
      from public.location_stock_balances where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=v_variant for update;
    v_system:=coalesce(v_system,0);v_reserved:=coalesce(v_reserved,0);v_damage:=coalesce(v_damage,0);v_quarantine:=coalesce(v_quarantine,0);
    if v_reserved>0.000001 then raise exception 'Cannot post a stock count while product % has reserved transfer stock. Dispatch/cancel the transfer first.',v_variant;end if;
    v_mode:=private.v483_tracking_mode(p_tenant_id,v_variant);
    v_tracking:=coalesce(x->'tracking','{}'::jsonb);

    if v_mode='none' then
      v_counted:=coalesce(nullif(x->>'counted_quantity','')::numeric,-1);
      if v_counted<0 then raise exception 'Counted quantity cannot be negative';end if;

    elsif v_mode='serial' then
      v_serials:=coalesce(x->'serial_numbers',v_tracking->'serial_numbers','[]'::jsonb);
      if jsonb_typeof(v_serials)<>'array' then raise exception 'Serial count must provide serial_numbers as an array';end if;
      v_seen_serial:='{}'::uuid[];
      for s in select value from jsonb_array_elements(v_serials) loop
        v_serial:=trim(coalesce(case when jsonb_typeof(s)='string' then s#>>'{}' else s->>'serial_number' end,''));
        if v_serial='' then raise exception 'Serial number cannot be blank';end if;
        select * into v_serial_row from public.inventory_serials_v483 where tenant_id=p_tenant_id and lower(trim(serial_number))=lower(v_serial) for update;
        if found then
          if v_serial_row.variant_id<>v_variant then raise exception 'Serial % belongs to another product',v_serial;end if;
          if v_serial_row.id=any(v_seen_serial) then raise exception 'Serial % is duplicated in this stock count',v_serial;end if;
          if v_serial_row.reserved_transfer_id is not null then raise exception 'Serial % is reserved for transfer and cannot be counted now',v_serial;end if;
          if v_serial_row.status in('sold','in_transit','recalled','void') then raise exception 'Serial % has status % and cannot be counted as local stock',v_serial,v_serial_row.status;end if;
          if v_serial_row.current_location_id is not null and v_serial_row.current_location_id<>p_location_id then raise exception 'Serial % is registered at another location',v_serial;end if;
          if v_serial_row.status='missing' or v_serial_row.current_location_id is null then
            update public.inventory_serials_v483 set status='in_stock',current_location_id=p_location_id,updated_at=now() where id=v_serial_row.id;
            insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,created_by)
            values(p_tenant_id,v_variant,v_serial_row.id,'adjustment',1,p_location_id,v_no,'stock-count:'||v_id::text||':serial-in:'||v_serial_row.id::text,jsonb_build_object('direction','in','reason','serial recovered/found during count'),auth.uid()) on conflict do nothing;
          end if;
          v_seen_serial:=array_append(v_seen_serial,v_serial_row.id);
        else
          insert into public.inventory_serials_v483(tenant_id,variant_id,serial_number,status,current_location_id,received_at,notes,created_by)
          values(p_tenant_id,v_variant,v_serial,'in_stock',p_location_id,now(),'Created by physical stock count '||v_no,auth.uid()) returning * into v_serial_row;
          v_seen_serial:=array_append(v_seen_serial,v_serial_row.id);
          insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,created_by)
          values(p_tenant_id,v_variant,v_serial_row.id,'adjustment',1,p_location_id,v_no,'stock-count:'||v_id::text||':serial-new:'||v_serial_row.id::text,jsonb_build_object('direction','in','reason','unregistered serial found during count'),auth.uid());
        end if;
      end loop;
      for sr in
        select id,serial_number,status from public.inventory_serials_v483
        where tenant_id=p_tenant_id and variant_id=v_variant and current_location_id=p_location_id and status in('in_stock','quarantine')
          and not (id=any(v_seen_serial)) for update
      loop
        update public.inventory_serials_v483 set status='missing',current_location_id=null,reserved_transfer_id=null,updated_at=now() where id=sr.id;
        insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,created_by)
        values(p_tenant_id,v_variant,sr.id,'adjustment',1,p_location_id,v_no,'stock-count:'||v_id::text||':serial-out:'||sr.id::text,jsonb_build_object('direction','out','reason','serial missing during count','serial_number',sr.serial_number),auth.uid()) on conflict do nothing;
      end loop;
      v_counted:=coalesce(cardinality(v_seen_serial),0);
      select count(*)::numeric into v_serial_damage from public.inventory_serials_v483 where tenant_id=p_tenant_id and variant_id=v_variant and current_location_id=p_location_id and status='quarantine';
      v_tracking:=jsonb_build_object('serial_numbers',v_serials,'counted_serials',v_counted);

    else
      v_batches:=coalesce(x->'batches',v_tracking->'batches','[]'::jsonb);
      if jsonb_typeof(v_batches)<>'array' then raise exception 'Batch count must provide batches as an array';end if;
      v_batch_total:=0;v_batch_damage_total:=0;v_seen_batch:='{}'::uuid[];
      for b in select value from jsonb_array_elements(v_batches) loop
        v_batch_id:=null;v_batch_no:=trim(coalesce(b->>'batch_number',''));
        v_batch_qty:=coalesce(nullif(b->>'quantity','')::numeric,0);v_batch_damage:=coalesce(nullif(b->>'damaged_quantity','')::numeric,0);
        if v_batch_qty<0 or v_batch_damage<0 then raise exception 'Batch counted quantities cannot be negative';end if;
        if nullif(b->>'batch_id','') is not null then v_batch_id:=(b->>'batch_id')::uuid;end if;
        if v_batch_id is not null and not exists(
          select 1 from public.inventory_batches_v483 ib where ib.id=v_batch_id and ib.tenant_id=p_tenant_id and ib.variant_id=v_variant
        ) then raise exception 'Batch does not belong to the selected product/business';end if;
        if v_batch_id is null and v_batch_no<>'' then select id into v_batch_id from public.inventory_batches_v483 where tenant_id=p_tenant_id and variant_id=v_variant and lower(trim(batch_number))=lower(v_batch_no);end if;
        if v_batch_id is null then
          if v_batch_no='' then raise exception 'Batch number is required';end if;
          v_mfg:=nullif(b->>'manufactured_on','')::date;v_exp:=nullif(b->>'expiry_on','')::date;
          select coalesce(require_batch_expiry,false) into v_require_expiry from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=v_variant;
          if coalesce(v_require_expiry,false) and v_exp is null then raise exception 'Expiry date is required for batch %',v_batch_no;end if;
          insert into public.inventory_batches_v483(tenant_id,variant_id,batch_number,manufactured_on,expiry_on,status,notes,created_by)
          values(p_tenant_id,v_variant,v_batch_no,v_mfg,v_exp,'active','Created by physical stock count '||v_no,auth.uid()) returning id into v_batch_id;
        else
          v_mfg:=nullif(b->>'manufactured_on','')::date;v_exp:=nullif(b->>'expiry_on','')::date;
          if exists(
            select 1 from public.inventory_batches_v483 ib where ib.id=v_batch_id
              and ((v_mfg is not null and ib.manufactured_on is distinct from v_mfg) or (v_exp is not null and ib.expiry_on is distinct from v_exp))
          ) then raise exception 'Batch dates conflict with the registered batch';end if;
        end if;
        if v_batch_id=any(v_seen_batch) then raise exception 'The same batch cannot appear twice in a stock count';end if;
        v_seen_batch:=array_append(v_seen_batch,v_batch_id);
        select coalesce(quantity,0),coalesce(damaged_quantity,0),coalesce(reserved_quantity,0) into v_old_qty,v_old_damage,v_old_reserved
          from public.inventory_batch_balances_v483 where tenant_id=p_tenant_id and batch_id=v_batch_id and location_id=p_location_id for update;
        v_old_qty:=coalesce(v_old_qty,0);v_old_damage:=coalesce(v_old_damage,0);v_old_reserved:=coalesce(v_old_reserved,0);
        if v_old_reserved>0.000001 then raise exception 'Batch % is reserved for transfer and cannot be counted now',coalesce(v_batch_no,v_batch_id::text);end if;
        insert into public.inventory_batch_balances_v483(tenant_id,batch_id,location_id,quantity,damaged_quantity,reserved_quantity,updated_at)
        values(p_tenant_id,v_batch_id,p_location_id,v_batch_qty,v_batch_damage,0,now())
        on conflict(tenant_id,batch_id,location_id) do update set quantity=excluded.quantity,damaged_quantity=excluded.damaged_quantity,reserved_quantity=0,updated_at=now();
        v_event_qty:=abs(v_batch_qty-v_old_qty)+abs(v_batch_damage-v_old_damage);
        if v_event_qty>0.000001 then
          insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,reference_number,source_key,metadata,created_by)
          values(p_tenant_id,v_variant,v_batch_id,'adjustment',v_event_qty,p_location_id,v_no,'stock-count:'||v_id::text||':batch:'||v_batch_id::text,
            jsonb_build_object('before_quantity',v_old_qty,'before_damaged',v_old_damage,'after_quantity',v_batch_qty,'after_damaged',v_batch_damage,'direction',case when v_batch_qty+v_batch_damage>=v_old_qty+v_old_damage then 'in' else 'out' end),auth.uid()) on conflict do nothing;
        end if;
        v_batch_total:=v_batch_total+v_batch_qty;v_batch_damage_total:=v_batch_damage_total+v_batch_damage;
      end loop;
      for br in
        select bb.batch_id,bb.quantity,coalesce(bb.damaged_quantity,0) damaged_quantity,b.batch_number
        from public.inventory_batch_balances_v483 bb join public.inventory_batches_v483 b on b.id=bb.batch_id and b.tenant_id=bb.tenant_id
        where bb.tenant_id=p_tenant_id and bb.location_id=p_location_id and b.variant_id=v_variant and (bb.quantity<>0 or coalesce(bb.damaged_quantity,0)<>0)
          and not (bb.batch_id=any(v_seen_batch)) for update of bb
      loop
        v_event_qty:=br.quantity+br.damaged_quantity;
        update public.inventory_batch_balances_v483 set quantity=0,damaged_quantity=0,reserved_quantity=0,updated_at=now() where tenant_id=p_tenant_id and batch_id=br.batch_id and location_id=p_location_id;
        if v_event_qty>0.000001 then
          insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,reference_number,source_key,metadata,created_by)
          values(p_tenant_id,v_variant,br.batch_id,'adjustment',v_event_qty,p_location_id,v_no,'stock-count:'||v_id::text||':batch-zero:'||br.batch_id::text,jsonb_build_object('direction','out','reason','batch missing during count','batch_number',br.batch_number),auth.uid()) on conflict do nothing;
        end if;
      end loop;
      update public.inventory_batches_v483 ib set status=case when exists(select 1 from public.inventory_batch_balances_v483 bb where bb.tenant_id=ib.tenant_id and bb.batch_id=ib.id and bb.quantity+coalesce(bb.damaged_quantity,0)>0) then 'active' else 'exhausted' end,updated_at=now()
      where ib.tenant_id=p_tenant_id and ib.variant_id=v_variant and ib.status in('active','exhausted');
      v_counted:=v_batch_total+v_batch_damage_total;
      v_tracking:=jsonb_build_object('batches',v_batches,'counted_saleable_quantity',v_batch_total,'counted_damaged_quantity',v_batch_damage_total);
    end if;

    v_delta:=v_counted-v_system;
    if abs(v_delta)>0.000001 then v_any_variance:=true;end if;
    insert into public.stock_count_items(count_id,variant_id,system_quantity,counted_quantity,tracking_mode,tracking_payload,system_reserved_quantity,system_damaged_quantity,system_quarantine_quantity,reconciliation_note)
    values(v_id,v_variant,v_system,v_counted,v_mode,coalesce(v_tracking,'{}'::jsonb),v_reserved,v_damage,v_quarantine,
      case when abs(v_delta)<=0.000001 then 'No quantity variance' else 'Ledger adjusted by '||v_delta::text end);

    if abs(v_delta)>0.000001 then
      perform public.inventory_adjust_stock(p_tenant_id,v_variant,v_delta,'Stock count • '||v_no);
      perform private.v4_location_stock_apply(p_tenant_id,p_location_id,v_variant,v_delta,'stock_count','stock_count',v_id,v_no,'Physical stock reconciliation',p_device_id,true);
    end if;
    if v_mode='serial' then
      update public.location_stock_balances set damaged_quantity=coalesce(v_serial_damage,0),quarantine_quantity=0,updated_at=now()
      where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=v_variant;
    elsif v_mode='batch' then
      update public.location_stock_balances set damaged_quantity=coalesce(v_batch_damage_total,0),quarantine_quantity=0,updated_at=now()
      where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=v_variant;
    end if;
  end loop;

  update public.stock_counts set status='posted',posted_by=auth.uid(),posted_at=now(),reconciliation_status=case when v_any_variance then 'variance' else 'reconciled' end,updated_at=now() where id=v_id;
  perform private.thq_sync_bump_v480(p_tenant_id,'inventory','stock_count',v_id::text,'posted');
  v_result:=jsonb_build_object('success',true,'count_id',v_id,'count_number',v_no,'status','posted','had_variance',v_any_variance);
  if nullif(trim(coalesce(p_request_id,'')),'') is not null then v_result:=private.v47_request_complete(p_tenant_id,p_request_id,'warehouse.stock_count',v_result);end if;
  return v_result;
end$$;
grant execute on function public.inventory_stock_count_post_v485(uuid,uuid,jsonb,text,uuid,text) to authenticated;

-- Compatibility: the pre-v4.8.5 name now uses the trace-aware count engine.
create or replace function public.inventory_stock_count_post_v483(p_tenant_id uuid,p_location_id uuid,p_items jsonb,p_notes text,p_device_id uuid)
returns jsonb language sql security definer set search_path=public,private,pg_temp as $$
  select public.inventory_stock_count_post_v485($1,$2,$3,$4,$5,null)
$$;
grant execute on function public.inventory_stock_count_post_v483(uuid,uuid,jsonb,text,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(151,'4.8.5','Warehouse & Transfers','Physical stock count now reconciles aggregate inventory together with exact serial lists or per-batch saleable/damaged quantities; reserved transfer stock blocks unsafe counting.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.5 migration 151 trace-aware stock count applied' as status;
