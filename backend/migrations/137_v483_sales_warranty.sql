-- THQ ERP V4.8.3 — trace-aware sales, FEFO batch allocation and warranty creation.
begin;

create or replace function private.v483_assert_reconciled(p_tenant_id uuid,p_variant_id uuid,p_location_id uuid) returns void
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_mode text;v_stock numeric;v_tracked numeric;begin
 v_mode:=private.v483_tracking_mode(p_tenant_id,p_variant_id);if v_mode='none' then return;end if;
 select coalesce(quantity,0) into v_stock from public.location_stock_balances where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=p_variant_id;
 v_stock:=coalesce(v_stock,0);v_tracked:=private.v483_location_tracked_quantity(p_tenant_id,p_variant_id,p_location_id,v_mode);
 if abs(v_stock-v_tracked)>0.000001 then raise exception 'Tracked stock is not reconciled for product %. Ledger %, tracked %. Register/fix serial or batch opening stock before posting',p_variant_id,v_stock,v_tracked;end if;
end$$;
revoke all on function private.v483_assert_reconciled(uuid,uuid,uuid) from public;

create or replace function private.v483_create_warranty(
 p_tenant_id uuid,p_variant_id uuid,p_serial_id uuid,p_batch_id uuid,p_customer_id uuid,p_sale_id uuid,p_sale_item_id uuid,p_quantity numeric,p_sale_date date
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_enabled boolean;v_months integer;v_days integer;v_expiry date;begin
 select warranty_enabled,warranty_months,warranty_days into v_enabled,v_months,v_days from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id;
 if not coalesce(v_enabled,false) then return;end if;
 v_expiry:=(p_sale_date+make_interval(months=>coalesce(v_months,0),days=>coalesce(v_days,0)))::date;
 insert into public.product_warranties_v483(tenant_id,variant_id,serial_id,batch_id,customer_id,sale_id,sale_item_id,quantity,warranty_start,warranty_expiry,status,created_by)
 values(p_tenant_id,p_variant_id,p_serial_id,p_batch_id,p_customer_id,p_sale_id,p_sale_item_id,p_quantity,p_sale_date,v_expiry,'active',auth.uid()) on conflict do nothing;
end$$;
revoke all on function private.v483_create_warranty(uuid,uuid,uuid,uuid,uuid,uuid,uuid,numeric,date) from public;

create or replace function private.v483_apply_batch_sale(
 p_tenant_id uuid,p_variant_id uuid,p_sale_id uuid,p_sale_item_id uuid,p_customer_id uuid,p_location_id uuid,p_sale_date date,p_quantity numeric,p_requested jsonb
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_remaining numeric:=p_quantity;v_out jsonb:='[]'::jsonb;v_allow_expired boolean:=false;r record;x jsonb;v_batch_id uuid;v_take numeric;v_requested_qty numeric;v_batch_number text;v_seen uuid[]:='{}'::uuid[];v_ref text;begin
 select allow_expired_sale into v_allow_expired from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id;
 select sale_number into v_ref from public.sales where tenant_id=p_tenant_id and id=p_sale_id;
 if jsonb_array_length(coalesce(p_requested,'[]'::jsonb))>0 then
  for x in select value from jsonb_array_elements(p_requested) loop
   v_requested_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);if v_requested_qty<=0 then raise exception 'Requested batch quantity must be positive';end if;
   if nullif(x->>'batch_id','') is not null then v_batch_id:=(x->>'batch_id')::uuid;else
    v_batch_number:=trim(coalesce(x->>'batch_number',''));select id into v_batch_id from public.inventory_batches_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id and lower(trim(batch_number))=lower(v_batch_number);end if;
   if v_batch_id is null then raise exception 'Batch not found for tracked product';end if;
   if v_batch_id=any(v_seen) then raise exception 'The same batch cannot appear twice on one sale line';end if;v_seen:=array_append(v_seen,v_batch_id);
   select b.batch_number,b.expiry_on,bb.quantity into r from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id where b.tenant_id=p_tenant_id and b.id=v_batch_id and b.variant_id=p_variant_id and bb.location_id=p_location_id and b.status='active' for update of bb;
   if not found or coalesce(r.quantity,0)<v_requested_qty then raise exception 'Insufficient quantity in selected batch %',coalesce(r.batch_number,v_batch_number);end if;
   if not coalesce(v_allow_expired,false) and r.expiry_on is not null and r.expiry_on<p_sale_date then raise exception 'Batch % expired on %',r.batch_number,r.expiry_on;end if;
   update public.inventory_batch_balances_v483 set quantity=quantity-v_requested_qty,updated_at=now() where tenant_id=p_tenant_id and batch_id=v_batch_id and location_id=p_location_id;
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,customer_id,sale_id,sale_item_id,reference_number,source_key,created_by) values(p_tenant_id,p_variant_id,v_batch_id,'sale',v_requested_qty,p_location_id,p_customer_id,p_sale_id,p_sale_item_id,v_ref,'sale:'||p_sale_id::text||':item:'||p_sale_item_id::text||':batch:'||v_batch_id::text,auth.uid());
   perform private.v483_create_warranty(p_tenant_id,p_variant_id,null,v_batch_id,p_customer_id,p_sale_id,p_sale_item_id,v_requested_qty,p_sale_date);
   v_remaining:=v_remaining-v_requested_qty;v_out:=v_out||jsonb_build_array(jsonb_build_object('batch_id',v_batch_id,'batch_number',r.batch_number,'quantity',v_requested_qty,'expiry_on',r.expiry_on));
  end loop;
  if abs(v_remaining)>0.000001 then raise exception 'Selected batch quantities must equal required base quantity %',p_quantity;end if;
 else
  for r in select b.id batch_id,b.batch_number,b.expiry_on,bb.quantity from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and bb.location_id=p_location_id and bb.quantity>0 and b.status='active' and (coalesce(v_allow_expired,false) or b.expiry_on is null or b.expiry_on>=p_sale_date) order by (b.expiry_on is null),b.expiry_on,b.created_at,b.batch_number for update of bb loop
   exit when v_remaining<=0.000001;v_take:=least(v_remaining,r.quantity);
   update public.inventory_batch_balances_v483 set quantity=quantity-v_take,updated_at=now() where tenant_id=p_tenant_id and batch_id=r.batch_id and location_id=p_location_id;
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,customer_id,sale_id,sale_item_id,reference_number,source_key,metadata,created_by) values(p_tenant_id,p_variant_id,r.batch_id,'sale',v_take,p_location_id,p_customer_id,p_sale_id,p_sale_item_id,v_ref,'sale:'||p_sale_id::text||':item:'||p_sale_item_id::text||':batch:'||r.batch_id::text,jsonb_build_object('allocation','FEFO'),auth.uid());
   perform private.v483_create_warranty(p_tenant_id,p_variant_id,null,r.batch_id,p_customer_id,p_sale_id,p_sale_item_id,v_take,p_sale_date);
   v_remaining:=v_remaining-v_take;v_out:=v_out||jsonb_build_array(jsonb_build_object('batch_id',r.batch_id,'batch_number',r.batch_number,'quantity',v_take,'expiry_on',r.expiry_on));
  end loop;
  if v_remaining>0.000001 then raise exception 'Insufficient eligible batch stock. Required %, unavailable %',p_quantity,v_remaining;end if;
 end if;
 update public.inventory_batches_v483 b set status='exhausted',updated_at=now() where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and b.status='active' and not exists(select 1 from public.inventory_batch_balances_v483 bb where bb.tenant_id=b.tenant_id and bb.batch_id=b.id and bb.quantity>0);
 return v_out;
end$$;
revoke all on function private.v483_apply_batch_sale(uuid,uuid,uuid,uuid,uuid,uuid,date,numeric,jsonb) from public;

create or replace function private.v483_apply_sale_trace(
 p_tenant_id uuid,p_sale_id uuid,p_customer_id uuid,p_location_id uuid,p_sale_date date,p_items jsonb
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare x jsonb;v_mode text;v_variant uuid;v_qty numeric;v_item_id uuid;v_serials jsonb;v_count numeric;s jsonb;v_serial text;v_serial_id uuid;v_ref text;v_batches jsonb;begin
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
    select id into v_serial_id from public.inventory_serials_v483 where tenant_id=p_tenant_id and variant_id=v_variant and current_location_id=p_location_id and status='in_stock' and lower(trim(serial_number))=lower(v_serial) for update;
    if v_serial_id is null then raise exception 'Serial % is not available at the selected store',v_serial;end if;
    update public.inventory_serials_v483 set status='sold',current_location_id=null,customer_id=p_customer_id,sale_id=p_sale_id,sale_item_id=v_item_id,sold_at=now(),updated_at=now() where id=v_serial_id;
    insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,customer_id,sale_id,sale_item_id,reference_number,source_key,created_by) values(p_tenant_id,v_variant,v_serial_id,'sale',1,p_location_id,p_customer_id,p_sale_id,v_item_id,v_ref,'sale:'||p_sale_id::text||':serial:'||v_serial_id::text,auth.uid());
    perform private.v483_create_warranty(p_tenant_id,v_variant,v_serial_id,null,p_customer_id,p_sale_id,v_item_id,1,p_sale_date);
   end loop;
  else
   v_batches:=coalesce(x->'batches','[]'::jsonb);perform private.v483_apply_batch_sale(p_tenant_id,v_variant,p_sale_id,v_item_id,p_customer_id,p_location_id,p_sale_date,v_qty,v_batches);
  end if;
 end loop;
end$$;
revoke all on function private.v483_apply_sale_trace(uuid,uuid,uuid,uuid,date,jsonb) from public;

create or replace function public.sales_create_v483(
 p_tenant_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,p_items jsonb,p_additional_charges numeric,p_initial_payment numeric,p_payment_method text,p_payment_reference text,p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_normalized jsonb;v_result jsonb;v_sale uuid;x jsonb;v_variant uuid;v_mode text;v_serials jsonb;v_count numeric;v_qty numeric;begin
 v_normalized:=private.v481_normalize_items(p_tenant_id,p_items,'sale');
 for x in select value from jsonb_array_elements(v_normalized) loop
  v_variant:=(x->>'variant_id')::uuid;v_mode:=private.v483_tracking_mode(p_tenant_id,v_variant);if v_mode='none' then continue;end if;perform private.v483_assert_reconciled(p_tenant_id,v_variant,p_location_id);
  if v_mode='serial' then v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);v_serials:=coalesce(x->'serial_numbers','[]'::jsonb);select count(*)::numeric into v_count from jsonb_array_elements(v_serials);if v_count<>v_qty then raise exception 'Provide exactly % serial numbers for serial-tracked product',v_qty;end if;end if;
 end loop;
 v_result:=public.sales_create_v482(p_tenant_id,p_customer_id,p_sale_date,p_due_date,p_items,p_additional_charges,p_initial_payment,p_payment_method,p_payment_reference,p_notes,p_location_id,p_device_id,p_request_id);
 v_sale:=nullif(v_result->>'sale_id','')::uuid;if v_sale is not null then perform private.v483_apply_sale_trace(p_tenant_id,v_sale,p_customer_id,p_location_id,p_sale_date,v_normalized);end if;
 return v_result||jsonb_build_object('tracking_engine','v4.8.3');
end$$;
grant execute on function public.sales_create_v483(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text) to authenticated;

create or replace function public.inventory_adjust_stock_v483(p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_variant_id uuid,p_quantity_delta numeric,p_note text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$begin
 if private.v483_tracking_mode(p_tenant_id,p_variant_id)<>'none' then raise exception 'Use serial/batch trace operations for tracked products. Generic stock adjustment is blocked in v4.8.3';end if;
 return public.inventory_adjust_stock_v47(p_tenant_id,p_location_id,p_device_id,p_variant_id,p_quantity_delta,p_note,p_request_id);
end$$;
grant execute on function public.inventory_adjust_stock_v483(uuid,uuid,uuid,uuid,numeric,text,text) to authenticated;

create or replace function public.inventory_stock_count_post_v483(p_tenant_id uuid,p_location_id uuid,p_items jsonb,p_notes text,p_device_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$declare x jsonb;begin
 for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop if private.v483_tracking_mode(p_tenant_id,(x->>'variant_id')::uuid)<>'none' then raise exception 'Stock count for serial/batch products requires trace allocation and is blocked in v4.8.3';end if;end loop;
 return public.inventory_stock_count_post_v4(p_tenant_id,p_location_id,p_items,p_notes,p_device_id);
end$$;
grant execute on function public.inventory_stock_count_post_v483(uuid,uuid,jsonb,text,uuid) to authenticated;


create or replace function public.inventory_transfer_create_v483(p_tenant_id uuid,p_from_location_id uuid,p_to_location_id uuid,p_items jsonb,p_notes text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$declare x jsonb;begin
 for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
  if private.v483_tracking_mode(p_tenant_id,(x->>'variant_id')::uuid)<>'none' then raise exception 'Transfers for serial/batch products require trace allocation and are blocked in v4.8.3';end if;
 end loop;
 return public.inventory_transfer_create_v47(p_tenant_id,p_from_location_id,p_to_location_id,p_items,p_notes,p_request_id);
end$$;
grant execute on function public.inventory_transfer_create_v483(uuid,uuid,uuid,jsonb,text,text) to authenticated;

create or replace function public.sales_return_create_v483(p_tenant_id uuid,p_sale_id uuid,p_items jsonb,p_reason text,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$declare x jsonb;v_variant uuid;begin
 for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
  select variant_id into v_variant from public.sale_items where id=(x->>'sale_item_id')::uuid and sale_id=p_sale_id;
  if v_variant is null then raise exception 'Sale item not found';end if;
  if private.v483_tracking_mode(p_tenant_id,v_variant)<>'none' then raise exception 'Returns for serial/batch products require trace allocation and are blocked in v4.8.3';end if;
 end loop;
 return public.sales_return_create_v481(p_tenant_id,p_sale_id,p_items,p_reason,p_device_id,p_request_id);
end$$;
grant execute on function public.sales_return_create_v483(uuid,uuid,jsonb,text,uuid,text) to authenticated;

create or replace function public.purchase_return_create_v483(p_tenant_id uuid,p_purchase_id uuid,p_items jsonb,p_reason text,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$declare x jsonb;v_variant uuid;begin
 for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
  select variant_id into v_variant from public.purchase_items where id=(x->>'purchase_item_id')::uuid and purchase_id=p_purchase_id;
  if v_variant is null then raise exception 'Purchase item not found';end if;
  if private.v483_tracking_mode(p_tenant_id,v_variant)<>'none' then raise exception 'Returns for serial/batch products require trace allocation and are blocked in v4.8.3';end if;
 end loop;
 return public.purchase_return_create_v481(p_tenant_id,p_purchase_id,p_items,p_reason,p_device_id,p_request_id);
end$$;
grant execute on function public.purchase_return_create_v483(uuid,uuid,jsonb,text,uuid,text) to authenticated;

create or replace function public.sales_void_v483(p_tenant_id uuid,p_sale_id uuid,p_reason text,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$begin
 if exists(select 1 from public.sale_items si where si.sale_id=p_sale_id and private.v483_tracking_mode(p_tenant_id,si.variant_id)<>'none') then raise exception 'Voiding a sale containing serial/batch products requires trace reversal and is blocked in v4.8.3';end if;
 return public.sales_void_v47(p_tenant_id,p_sale_id,p_reason,p_device_id,p_request_id);
end$$;
grant execute on function public.sales_void_v483(uuid,uuid,text,uuid,text) to authenticated;

create or replace function public.purchase_void_v483(p_tenant_id uuid,p_purchase_id uuid,p_reason text,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$begin
 if exists(select 1 from public.purchase_items pi where pi.purchase_id=p_purchase_id and private.v483_tracking_mode(p_tenant_id,pi.variant_id)<>'none') then raise exception 'Voiding a purchase containing serial/batch products requires trace reversal and is blocked in v4.8.3';end if;
 return public.purchase_void_v47(p_tenant_id,p_purchase_id,p_reason,p_device_id,p_request_id);
end$$;
grant execute on function public.purchase_void_v483(uuid,uuid,text,uuid,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(137,'4.8.3','Serial / Batch / Warranty','Trace-aware sales, FEFO batch allocation, warranty creation and safe guardrails for generic inventory edits.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.3 migration 137 sales and warranty applied' as status;
