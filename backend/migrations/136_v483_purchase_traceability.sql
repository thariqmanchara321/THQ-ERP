-- THQ ERP V4.8.3 — tracked opening stock and purchase receipts.
begin;

create or replace function private.v483_location_tracked_quantity(p_tenant_id uuid,p_variant_id uuid,p_location_id uuid,p_mode text) returns numeric
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v numeric;begin
 if p_mode='serial' then
  select count(*)::numeric into v from public.inventory_serials_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id and current_location_id=p_location_id and status='in_stock';
 elsif p_mode='batch' then
  select coalesce(sum(bb.quantity),0) into v from public.inventory_batch_balances_v483 bb join public.inventory_batches_v483 b on b.id=bb.batch_id and b.tenant_id=bb.tenant_id where bb.tenant_id=p_tenant_id and bb.location_id=p_location_id and b.variant_id=p_variant_id;
 else v:=0;end if;
 return coalesce(v,0);
end$$;
revoke all on function private.v483_location_tracked_quantity(uuid,uuid,uuid,text) from public;

create or replace function public.inventory_tracking_reconciliation_v483(p_tenant_id uuid,p_variant_id uuid,p_location_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_mode text;v_stock numeric;v_tracked numeric;begin
 perform private.v4_location_access(p_tenant_id,p_location_id,'view');
 if not exists(select 1 from public.product_variants where tenant_id=p_tenant_id and id=p_variant_id) then raise exception 'Product not found';end if;
 v_mode:=private.v483_tracking_mode(p_tenant_id,p_variant_id);
 select coalesce(quantity,0) into v_stock from public.location_stock_balances where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=p_variant_id;
 v_stock:=coalesce(v_stock,0);v_tracked:=private.v483_location_tracked_quantity(p_tenant_id,p_variant_id,p_location_id,v_mode);
 return jsonb_build_object('tracking_mode',v_mode,'stock_quantity',v_stock,'tracked_quantity',v_tracked,'difference',v_stock-v_tracked,'reconciled',v_mode='none' or abs(v_stock-v_tracked)<=0.000001);
end$$;
grant execute on function public.inventory_tracking_reconciliation_v483(uuid,uuid,uuid) to authenticated;

create or replace function public.inventory_tracking_register_opening_v483(
 p_tenant_id uuid,p_variant_id uuid,p_location_id uuid,p_serial_numbers jsonb default '[]'::jsonb,p_batches jsonb default '[]'::jsonb,p_note text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_mode text;v_stock numeric;v_existing numeric;v_count numeric;v_sum numeric;x jsonb;v_serial text;v_batch text;v_qty numeric;v_batch_id uuid;v_serial_id uuid;v_expiry date;v_mfg date;v_seen_serials text[]:='{}'::text[];v_seen_batches text[]:='{}'::text[];begin
 if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Inventory manage permission required';end if;
 perform private.v4_location_access(p_tenant_id,p_location_id,'manage');
 v_mode:=private.v483_tracking_mode(p_tenant_id,p_variant_id);if v_mode='none' then raise exception 'Enable serial or batch tracking first';end if;
 select coalesce(quantity,0) into v_stock from public.location_stock_balances where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=p_variant_id for update;v_stock:=coalesce(v_stock,0);
 v_existing:=private.v483_location_tracked_quantity(p_tenant_id,p_variant_id,p_location_id,v_mode);
 if abs(v_existing-v_stock)<=0.000001 then return jsonb_build_object('registered',0,'reconciled',true,'stock_quantity',v_stock,'tracked_quantity',v_existing);end if;
 if v_existing<>0 then raise exception 'Existing tracked quantity (%) does not match stock (%). Opening registration is only allowed from zero tracked quantity',v_existing,v_stock;end if;
 if v_mode='serial' then
  if v_stock<>trunc(v_stock) then raise exception 'Serial-tracked stock must be a whole base-unit quantity';end if;
  select count(*)::numeric into v_count from jsonb_array_elements(coalesce(p_serial_numbers,'[]'::jsonb));if v_count<>v_stock then raise exception 'Register exactly % serial numbers to match current stock',v_stock;end if;
  for x in select value from jsonb_array_elements(coalesce(p_serial_numbers,'[]'::jsonb)) loop
   v_serial:=trim(coalesce(case when jsonb_typeof(x)='string' then x#>>'{}' else x->>'serial_number' end,''));if v_serial='' then raise exception 'Serial number cannot be blank';end if;
   if lower(v_serial)=any(v_seen_serials) then raise exception 'Duplicate serial number % in opening registration',v_serial;end if;v_seen_serials:=array_append(v_seen_serials,lower(v_serial));
   insert into public.inventory_serials_v483(tenant_id,variant_id,serial_number,status,current_location_id,received_at,notes,created_by) values(p_tenant_id,p_variant_id,v_serial,'in_stock',p_location_id,now(),nullif(trim(coalesce(p_note,'')),''),auth.uid()) returning id into v_serial_id;
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,source_key,metadata,created_by) values(p_tenant_id,p_variant_id,v_serial_id,'opening',1,p_location_id,'opening:'||p_location_id::text||':serial:'||v_serial_id::text,jsonb_build_object('note',nullif(trim(coalesce(p_note,'')),'')),auth.uid());
  end loop;
 else
  select coalesce(sum(coalesce(nullif(value->>'quantity','')::numeric,0)),0) into v_sum from jsonb_array_elements(coalesce(p_batches,'[]'::jsonb));if abs(v_sum-v_stock)>0.000001 then raise exception 'Batch quantities must total current stock %; received %',v_stock,v_sum;end if;
  for x in select value from jsonb_array_elements(coalesce(p_batches,'[]'::jsonb)) loop
   v_batch:=trim(coalesce(x->>'batch_number',''));v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);v_expiry:=nullif(x->>'expiry_on','')::date;v_mfg:=nullif(x->>'manufactured_on','')::date;
   if v_batch='' or v_qty<=0 then raise exception 'Each batch requires a batch number and positive quantity';end if;
   if lower(v_batch)=any(v_seen_batches) then raise exception 'Duplicate batch % in opening registration',v_batch;end if;v_seen_batches:=array_append(v_seen_batches,lower(v_batch));
   if coalesce((select require_batch_expiry from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id),false) and v_expiry is null then raise exception 'Expiry date is required for batch %',v_batch;end if;
   insert into public.inventory_batches_v483(tenant_id,variant_id,batch_number,manufactured_on,expiry_on,notes,created_by) values(p_tenant_id,p_variant_id,v_batch,v_mfg,v_expiry,nullif(trim(coalesce(p_note,'')),''),auth.uid()) on conflict(tenant_id,variant_id,lower(trim(batch_number))) do update set manufactured_on=coalesce(public.inventory_batches_v483.manufactured_on,excluded.manufactured_on),expiry_on=coalesce(public.inventory_batches_v483.expiry_on,excluded.expiry_on),status='active',updated_at=now() returning id into v_batch_id;
   if exists(select 1 from public.inventory_batches_v483 where id=v_batch_id and ((manufactured_on is not null and v_mfg is not null and manufactured_on<>v_mfg) or (expiry_on is not null and v_expiry is not null and expiry_on<>v_expiry))) then raise exception 'Batch % already exists with different manufacture/expiry dates',v_batch;end if;
   insert into public.inventory_batch_balances_v483(tenant_id,batch_id,location_id,quantity) values(p_tenant_id,v_batch_id,p_location_id,v_qty) on conflict(tenant_id,batch_id,location_id) do update set quantity=public.inventory_batch_balances_v483.quantity+excluded.quantity,updated_at=now();
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,source_key,metadata,created_by) values(p_tenant_id,p_variant_id,v_batch_id,'opening',v_qty,p_location_id,'opening:'||p_location_id::text||':batch:'||v_batch_id::text,jsonb_build_object('note',nullif(trim(coalesce(p_note,'')),'')),auth.uid());
  end loop;
 end if;
 perform private.thq_sync_bump_v480(p_tenant_id,'inventory','tracking_opening',p_variant_id::text,'register');
 return public.inventory_tracking_reconciliation_v483(p_tenant_id,p_variant_id,p_location_id);
end$$;
grant execute on function public.inventory_tracking_register_opening_v483(uuid,uuid,uuid,jsonb,jsonb,text) to authenticated;

create or replace function private.v483_apply_purchase_trace(
 p_tenant_id uuid,p_purchase_id uuid,p_supplier_id uuid,p_location_id uuid,p_items jsonb
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare x jsonb;v_mode text;v_variant uuid;v_qty numeric;v_item_id uuid;v_serials jsonb;v_batches jsonb;v_count numeric;v_sum numeric;s jsonb;v_serial text;b jsonb;v_batch text;v_bqty numeric;v_mfg date;v_exp date;v_batch_id uuid;v_serial_id uuid;v_ref text;v_require boolean;v_seen_serials text[];v_seen_batches text[];begin
 if exists(select 1 from public.inventory_trace_events_v483 where tenant_id=p_tenant_id and purchase_id=p_purchase_id) then return;end if;
 select purchase_number into v_ref from public.purchases where tenant_id=p_tenant_id and id=p_purchase_id;
 for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
  v_variant:=(x->>'variant_id')::uuid;v_mode:=private.v483_tracking_mode(p_tenant_id,v_variant);if v_mode='none' then continue;end if;v_seen_serials:='{}'::text[];v_seen_batches:='{}'::text[];
  v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);select id into v_item_id from public.purchase_items where purchase_id=p_purchase_id and variant_id=v_variant limit 1;if v_item_id is null then raise exception 'Purchase line not found for tracked product';end if;
  if v_mode='serial' then
   if v_qty<>trunc(v_qty) then raise exception 'Serial-tracked product % requires whole base units',v_variant;end if;
   v_serials:=coalesce(x->'serial_numbers','[]'::jsonb);select count(*)::numeric into v_count from jsonb_array_elements(v_serials);if v_count<>v_qty then raise exception 'Provide exactly % serial numbers for tracked purchase line',v_qty;end if;
   for s in select value from jsonb_array_elements(v_serials) loop
    v_serial:=trim(coalesce(case when jsonb_typeof(s)='string' then s#>>'{}' else s->>'serial_number' end,''));if v_serial='' then raise exception 'Serial number cannot be blank';end if;
    if lower(v_serial)=any(v_seen_serials) then raise exception 'Duplicate serial number % on tracked purchase line',v_serial;end if;v_seen_serials:=array_append(v_seen_serials,lower(v_serial));
    insert into public.inventory_serials_v483(tenant_id,variant_id,serial_number,status,current_location_id,supplier_id,purchase_id,purchase_item_id,received_at,created_by) values(p_tenant_id,v_variant,v_serial,'in_stock',p_location_id,p_supplier_id,p_purchase_id,v_item_id,now(),auth.uid()) returning id into v_serial_id;
    insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,supplier_id,purchase_id,purchase_item_id,reference_number,source_key,created_by) values(p_tenant_id,v_variant,v_serial_id,'purchase',1,p_location_id,p_supplier_id,p_purchase_id,v_item_id,v_ref,'purchase:'||p_purchase_id::text||':serial:'||v_serial_id::text,auth.uid());
   end loop;
  else
   v_batches:=coalesce(x->'batches','[]'::jsonb);select coalesce(sum(coalesce(nullif(value->>'quantity','')::numeric,0)),0) into v_sum from jsonb_array_elements(v_batches);if abs(v_sum-v_qty)>0.000001 then raise exception 'Batch quantities must total base quantity %; received %',v_qty,v_sum;end if;
   select require_batch_expiry into v_require from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=v_variant;
   for b in select value from jsonb_array_elements(v_batches) loop
    v_batch:=trim(coalesce(b->>'batch_number',''));v_bqty:=coalesce(nullif(b->>'quantity','')::numeric,0);v_mfg:=nullif(b->>'manufactured_on','')::date;v_exp:=nullif(b->>'expiry_on','')::date;
    if v_batch='' or v_bqty<=0 then raise exception 'Each batch requires a batch number and positive quantity';end if;if lower(v_batch)=any(v_seen_batches) then raise exception 'Duplicate batch % on tracked purchase line',v_batch;end if;v_seen_batches:=array_append(v_seen_batches,lower(v_batch));if coalesce(v_require,false) and v_exp is null then raise exception 'Expiry date is required for batch %',v_batch;end if;
    insert into public.inventory_batches_v483(tenant_id,variant_id,batch_number,manufactured_on,expiry_on,supplier_id,first_purchase_id,first_purchase_item_id,created_by) values(p_tenant_id,v_variant,v_batch,v_mfg,v_exp,p_supplier_id,p_purchase_id,v_item_id,auth.uid())
    on conflict(tenant_id,variant_id,lower(trim(batch_number))) do update set manufactured_on=coalesce(public.inventory_batches_v483.manufactured_on,excluded.manufactured_on),expiry_on=coalesce(public.inventory_batches_v483.expiry_on,excluded.expiry_on),supplier_id=coalesce(public.inventory_batches_v483.supplier_id,excluded.supplier_id),status='active',updated_at=now() returning id into v_batch_id;
    if exists(select 1 from public.inventory_batches_v483 where id=v_batch_id and ((manufactured_on is not null and v_mfg is not null and manufactured_on<>v_mfg) or (expiry_on is not null and v_exp is not null and expiry_on<>v_exp))) then raise exception 'Batch % already exists with different manufacture/expiry dates',v_batch;end if;
    insert into public.inventory_batch_balances_v483(tenant_id,batch_id,location_id,quantity) values(p_tenant_id,v_batch_id,p_location_id,v_bqty) on conflict(tenant_id,batch_id,location_id) do update set quantity=public.inventory_batch_balances_v483.quantity+excluded.quantity,updated_at=now();
    insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,supplier_id,purchase_id,purchase_item_id,reference_number,source_key,created_by) values(p_tenant_id,v_variant,v_batch_id,'purchase',v_bqty,p_location_id,p_supplier_id,p_purchase_id,v_item_id,v_ref,'purchase:'||p_purchase_id::text||':item:'||v_item_id::text||':batch:'||v_batch_id::text,auth.uid());
   end loop;
  end if;
 end loop;
end$$;
revoke all on function private.v483_apply_purchase_trace(uuid,uuid,uuid,uuid,jsonb) from public;

create or replace function public.purchases_create_v483(
 p_tenant_id uuid,p_supplier_id uuid,p_supplier_invoice_number text,p_purchase_date date,p_due_date date,p_items jsonb,p_additional_charges numeric,p_initial_payment numeric,p_payment_method text,p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_normalized jsonb;v_result jsonb;v_purchase uuid;x jsonb;v_variant uuid;v_mode text;v_recon jsonb;begin
 v_normalized:=private.v481_normalize_items(p_tenant_id,p_items,'purchase');
 -- A tracking policy may be enabled while legacy stock is still unregistered. Do not
 -- receive more tracked stock until the current location is reconciled, otherwise the
 -- opening quantity can no longer be registered unambiguously.
 for x in select value from jsonb_array_elements(v_normalized) loop
  v_variant:=(x->>'variant_id')::uuid;v_mode:=private.v483_tracking_mode(p_tenant_id,v_variant);
  if v_mode<>'none' then
   v_recon:=public.inventory_tracking_reconciliation_v483(p_tenant_id,v_variant,p_location_id);
   if not coalesce((v_recon->>'reconciled')::boolean,false) then
    raise exception 'Register existing serial/batch opening stock before receiving product % at this store',v_variant;
   end if;
  end if;
 end loop;
 v_result:=public.purchases_create_v481(p_tenant_id,p_supplier_id,p_supplier_invoice_number,p_purchase_date,p_due_date,p_items,p_additional_charges,p_initial_payment,p_payment_method,p_notes,p_location_id,p_device_id,p_request_id);
 v_purchase:=nullif(v_result->>'purchase_id','')::uuid;
 if v_purchase is not null then perform private.v483_apply_purchase_trace(p_tenant_id,v_purchase,p_supplier_id,p_location_id,v_normalized);end if;
 return v_result||jsonb_build_object('tracking_engine','v4.8.3');
end$$;
grant execute on function public.purchases_create_v483(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(136,'4.8.3','Serial / Batch / Warranty','Opening-stock trace registration and trace-aware purchase receipt posting.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.3 migration 136 purchase traceability applied' as status;
