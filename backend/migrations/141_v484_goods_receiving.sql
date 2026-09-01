-- THQ ERP V4.8.4 — Goods Received Note, partial receiving, damaged/rejected receiving.
begin;

create sequence if not exists public.goods_receipt_number_seq_v484;

create table if not exists public.goods_receipts_v484(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  purchase_order_id uuid not null references public.purchase_orders_v480(id) on delete restrict,
  grn_number text not null,
  receipt_date date not null default current_date,
  supplier_delivery_note text,
  status text not null default 'draft' check(status in('draft','posted','cancelled')),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  posted_by uuid references auth.users(id) on delete set null,
  posted_at timestamptz,
  cancelled_by uuid references auth.users(id) on delete set null,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,grn_number)
);
create index if not exists idx_goods_receipts_v484_lookup on public.goods_receipts_v484(tenant_id,location_id,status,receipt_date desc);
create index if not exists idx_goods_receipts_v484_po on public.goods_receipts_v484(purchase_order_id,status);
alter table public.goods_receipts_v484 enable row level security;
revoke all on public.goods_receipts_v484 from anon,authenticated;

create table if not exists public.goods_receipt_items_v484(
  id uuid primary key default gen_random_uuid(),
  goods_receipt_id uuid not null references public.goods_receipts_v484(id) on delete cascade,
  purchase_order_item_id uuid not null references public.purchase_order_items_v480(id) on delete restrict,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  received_quantity numeric not null check(received_quantity>0),
  accepted_quantity numeric not null default 0 check(accepted_quantity>=0),
  damaged_quantity numeric not null default 0 check(damaged_quantity>=0),
  rejected_quantity numeric not null default 0 check(rejected_quantity>=0),
  unit_cost numeric not null default 0 check(unit_cost>=0),
  tracking_payload jsonb not null default '{}'::jsonb,
  rejection_reason text,
  damage_note text,
  created_at timestamptz not null default now(),
  unique(goods_receipt_id,purchase_order_item_id),
  check(abs(received_quantity-(accepted_quantity+damaged_quantity+rejected_quantity))<=0.000001)
);
create index if not exists idx_goods_receipt_items_v484_variant on public.goods_receipt_items_v484(variant_id,goods_receipt_id);
alter table public.goods_receipt_items_v484 enable row level security;
revoke all on public.goods_receipt_items_v484 from anon,authenticated;

-- Batch balance now distinguishes saleable and damaged physical batch stock.
alter table public.inventory_batch_balances_v483 add column if not exists damaged_quantity numeric not null default 0 check(damaged_quantity>=0);

-- GRN linkage for serial/batch provenance without requiring a legacy Purchase row.
alter table public.inventory_serials_v483 add column if not exists goods_receipt_id uuid references public.goods_receipts_v484(id) on delete set null;
alter table public.inventory_serials_v483 add column if not exists goods_receipt_item_id uuid references public.goods_receipt_items_v484(id) on delete set null;
alter table public.inventory_batches_v483 add column if not exists first_goods_receipt_id uuid references public.goods_receipts_v484(id) on delete set null;
alter table public.inventory_batches_v483 add column if not exists first_goods_receipt_item_id uuid references public.goods_receipt_items_v484(id) on delete set null;

-- Reconciliation includes damaged/quarantined physical stock, while sale allocation continues to use only saleable batch quantity / in_stock serials.
create or replace function private.v483_location_tracked_quantity(p_tenant_id uuid,p_variant_id uuid,p_location_id uuid,p_mode text)
returns numeric language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v numeric;begin
 if p_mode='serial' then
  select count(*)::numeric into v from public.inventory_serials_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id and current_location_id=p_location_id and status in('in_stock','quarantine');
 elsif p_mode='batch' then
  select coalesce(sum(bb.quantity+coalesce(bb.damaged_quantity,0)),0) into v from public.inventory_batch_balances_v483 bb join public.inventory_batches_v483 b on b.id=bb.batch_id and b.tenant_id=bb.tenant_id where bb.tenant_id=p_tenant_id and bb.location_id=p_location_id and b.variant_id=p_variant_id;
 else v:=0;end if;return coalesce(v,0);
end$$;
revoke all on function private.v483_location_tracked_quantity(uuid,uuid,uuid,text) from public;

create or replace function public.goods_receipt_create_v484(
  p_tenant_id uuid,p_purchase_order_id uuid,p_receipt_date date,p_items jsonb,p_supplier_delivery_note text default null,p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_po public.purchase_orders_v480%rowtype;v_id uuid:=gen_random_uuid();v_no text;x jsonb;v_po_item public.purchase_order_items_v480%rowtype;v_received numeric;v_accepted numeric;v_damaged numeric;v_rejected numeric;v_remaining numeric;begin
  select * into v_po from public.purchase_orders_v480 where tenant_id=p_tenant_id and id=p_purchase_order_id for update;if not found then raise exception 'Purchase Order not found';end if;
  perform private.purchasing_v484_access(p_tenant_id,v_po.location_id,true);
  if v_po.status not in('approved','ordered','partially_received') then raise exception 'Only Approved/Ordered/Partially Received Purchase Orders can receive goods';end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'At least one receiving line is required';end if;
  v_no:='GRN-'||to_char(coalesce(p_receipt_date,current_date),'YYMMDD')||'-'||lpad(nextval('public.goods_receipt_number_seq_v484')::text,6,'0');
  insert into public.goods_receipts_v484(id,tenant_id,location_id,supplier_id,purchase_order_id,grn_number,receipt_date,supplier_delivery_note,notes,created_by)
  values(v_id,p_tenant_id,v_po.location_id,v_po.supplier_id,p_purchase_order_id,v_no,coalesce(p_receipt_date,current_date),nullif(trim(coalesce(p_supplier_delivery_note,'')),''),nullif(trim(coalesce(p_notes,'')),''),auth.uid());
  for x in select value from jsonb_array_elements(p_items) loop
    select * into v_po_item from public.purchase_order_items_v480 where id=nullif(x->>'purchase_order_item_id','')::uuid and purchase_order_id=p_purchase_order_id;if not found then raise exception 'PO line not found';end if;
    v_received:=coalesce(nullif(x->>'received_quantity','')::numeric,0);v_accepted:=coalesce(nullif(x->>'accepted_quantity','')::numeric,v_received);v_damaged:=coalesce(nullif(x->>'damaged_quantity','')::numeric,0);v_rejected:=coalesce(nullif(x->>'rejected_quantity','')::numeric,0);
    if v_received<=0 or v_accepted<0 or v_damaged<0 or v_rejected<0 or abs(v_received-(v_accepted+v_damaged+v_rejected))>0.000001 then raise exception 'Received quantity must equal accepted + damaged + rejected';end if;
    v_remaining:=greatest(v_po_item.quantity-coalesce(v_po_item.received_quantity,0),0);if v_received-v_remaining>0.000001 then raise exception 'Receiving quantity % exceeds remaining PO quantity %',v_received,v_remaining;end if;
    if v_rejected>0 and trim(coalesce(x->>'rejection_reason',''))='' then raise exception 'Rejected quantity requires a reason';end if;
    insert into public.goods_receipt_items_v484(goods_receipt_id,purchase_order_item_id,variant_id,received_quantity,accepted_quantity,damaged_quantity,rejected_quantity,unit_cost,tracking_payload,rejection_reason,damage_note)
    values(v_id,v_po_item.id,v_po_item.variant_id,v_received,v_accepted,v_damaged,v_rejected,v_po_item.unit_cost,coalesce(x->'tracking','{}'::jsonb),nullif(trim(coalesce(x->>'rejection_reason','')),''),nullif(trim(coalesce(x->>'damage_note','')),''));
  end loop;
  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','goods_receipt',v_id::text,'create');
  return jsonb_build_object('success',true,'goods_receipt_id',v_id,'grn_number',v_no,'status','draft');
end$$;
grant execute on function public.goods_receipt_create_v484(uuid,uuid,date,jsonb,text,text) to authenticated;

create or replace function private.goods_receipt_apply_tracking_v484(p_grn_item_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare gi public.goods_receipt_items_v484%rowtype;g public.goods_receipts_v484%rowtype;v_mode text;v_recon jsonb;v_serials jsonb;v_damaged_serials jsonb;v_batches jsonb;v_count numeric;s jsonb;v_serial text;v_serial_id uuid;b jsonb;v_batch text;v_a numeric;v_d numeric;v_mfg date;v_exp date;v_batch_id uuid;v_sum_a numeric:=0;v_sum_d numeric:=0;v_require boolean;v_seen text[]:='{}'::text[];begin
 select * into gi from public.goods_receipt_items_v484 where id=p_grn_item_id;if not found then raise exception 'GRN item not found';end if;select * into g from public.goods_receipts_v484 where id=gi.goods_receipt_id;
 v_mode:=private.v483_tracking_mode(g.tenant_id,gi.variant_id);if v_mode='none' then return;end if;
 v_recon:=public.inventory_tracking_reconciliation_v483(g.tenant_id,gi.variant_id,g.location_id);if not coalesce((v_recon->>'reconciled')::boolean,false) then raise exception 'Register/reconcile existing serial or batch stock before posting this GRN';end if;
 if v_mode='serial' then
   if gi.accepted_quantity<>trunc(gi.accepted_quantity) or gi.damaged_quantity<>trunc(gi.damaged_quantity) then raise exception 'Serial-tracked GRN quantities must be whole base units';end if;
   v_serials:=coalesce(gi.tracking_payload->'serial_numbers','[]'::jsonb);v_damaged_serials:=coalesce(gi.tracking_payload->'damaged_serial_numbers','[]'::jsonb);
   select count(*)::numeric into v_count from jsonb_array_elements(v_serials);if v_count<>gi.accepted_quantity then raise exception 'Provide exactly % accepted serial numbers',gi.accepted_quantity;end if;
   select count(*)::numeric into v_count from jsonb_array_elements(v_damaged_serials);if v_count<>gi.damaged_quantity then raise exception 'Provide exactly % damaged serial numbers',gi.damaged_quantity;end if;
   for s in select value from jsonb_array_elements(v_serials) loop
     v_serial:=trim(coalesce(case when jsonb_typeof(s)='string' then s#>>'{}' else s->>'serial_number' end,''));if v_serial='' then raise exception 'Serial number cannot be blank';end if;if lower(v_serial)=any(v_seen) then raise exception 'Duplicate serial number % in GRN',v_serial;end if;v_seen:=array_append(v_seen,lower(v_serial));
     insert into public.inventory_serials_v483(tenant_id,variant_id,serial_number,status,current_location_id,supplier_id,goods_receipt_id,goods_receipt_item_id,received_at,created_by)
     values(g.tenant_id,gi.variant_id,v_serial,'in_stock',g.location_id,g.supplier_id,g.id,gi.id,now(),auth.uid()) returning id into v_serial_id;
     insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,supplier_id,reference_number,source_key,metadata,created_by)
     values(g.tenant_id,gi.variant_id,v_serial_id,'purchase',1,g.location_id,g.supplier_id,g.grn_number,'grn:'||g.id::text||':serial:'||v_serial_id::text,jsonb_build_object('source_type','grn','goods_receipt_id',g.id,'goods_receipt_item_id',gi.id,'disposition','accepted'),auth.uid());
   end loop;
   for s in select value from jsonb_array_elements(v_damaged_serials) loop
     v_serial:=trim(coalesce(case when jsonb_typeof(s)='string' then s#>>'{}' else s->>'serial_number' end,''));if v_serial='' then raise exception 'Serial number cannot be blank';end if;if lower(v_serial)=any(v_seen) then raise exception 'Duplicate serial number % in GRN',v_serial;end if;v_seen:=array_append(v_seen,lower(v_serial));
     insert into public.inventory_serials_v483(tenant_id,variant_id,serial_number,status,current_location_id,supplier_id,goods_receipt_id,goods_receipt_item_id,received_at,created_by)
     values(g.tenant_id,gi.variant_id,v_serial,'quarantine',g.location_id,g.supplier_id,g.id,gi.id,now(),auth.uid()) returning id into v_serial_id;
     insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,supplier_id,reference_number,source_key,metadata,created_by)
     values(g.tenant_id,gi.variant_id,v_serial_id,'purchase',1,g.location_id,g.supplier_id,g.grn_number,'grn:'||g.id::text||':serial:'||v_serial_id::text,jsonb_build_object('source_type','grn','goods_receipt_id',g.id,'goods_receipt_item_id',gi.id,'disposition','damaged'),auth.uid());
   end loop;
 else
   v_batches:=coalesce(gi.tracking_payload->'batches','[]'::jsonb);select require_batch_expiry into v_require from public.product_tracking_policies_v483 where tenant_id=g.tenant_id and variant_id=gi.variant_id;
   for b in select value from jsonb_array_elements(v_batches) loop
     v_batch:=trim(coalesce(b->>'batch_number',''));v_a:=coalesce(nullif(b->>'accepted_quantity','')::numeric,0);v_d:=coalesce(nullif(b->>'damaged_quantity','')::numeric,0);v_mfg:=nullif(b->>'manufactured_on','')::date;v_exp:=nullif(b->>'expiry_on','')::date;
     if v_batch='' or v_a<0 or v_d<0 or v_a+v_d<=0 then raise exception 'Each batch requires a batch number and positive accepted/damaged quantity';end if;if lower(v_batch)=any(v_seen) then raise exception 'Duplicate batch % in GRN',v_batch;end if;v_seen:=array_append(v_seen,lower(v_batch));if coalesce(v_require,false) and v_exp is null then raise exception 'Expiry date is required for batch %',v_batch;end if;
     v_sum_a:=v_sum_a+v_a;v_sum_d:=v_sum_d+v_d;
     insert into public.inventory_batches_v483(tenant_id,variant_id,batch_number,manufactured_on,expiry_on,supplier_id,first_goods_receipt_id,first_goods_receipt_item_id,created_by)
     values(g.tenant_id,gi.variant_id,v_batch,v_mfg,v_exp,g.supplier_id,g.id,gi.id,auth.uid())
     on conflict(tenant_id,variant_id,lower(trim(batch_number))) do update set manufactured_on=coalesce(public.inventory_batches_v483.manufactured_on,excluded.manufactured_on),expiry_on=coalesce(public.inventory_batches_v483.expiry_on,excluded.expiry_on),supplier_id=coalesce(public.inventory_batches_v483.supplier_id,excluded.supplier_id),first_goods_receipt_id=coalesce(public.inventory_batches_v483.first_goods_receipt_id,excluded.first_goods_receipt_id),first_goods_receipt_item_id=coalesce(public.inventory_batches_v483.first_goods_receipt_item_id,excluded.first_goods_receipt_item_id),status='active',updated_at=now() returning id into v_batch_id;
     if exists(select 1 from public.inventory_batches_v483 where id=v_batch_id and ((manufactured_on is not null and v_mfg is not null and manufactured_on<>v_mfg) or (expiry_on is not null and v_exp is not null and expiry_on<>v_exp))) then raise exception 'Batch % already exists with different manufacture/expiry dates',v_batch;end if;
     insert into public.inventory_batch_balances_v483(tenant_id,batch_id,location_id,quantity,damaged_quantity) values(g.tenant_id,v_batch_id,g.location_id,v_a,v_d)
     on conflict(tenant_id,batch_id,location_id) do update set quantity=public.inventory_batch_balances_v483.quantity+excluded.quantity,damaged_quantity=public.inventory_batch_balances_v483.damaged_quantity+excluded.damaged_quantity,updated_at=now();
     insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,supplier_id,reference_number,source_key,metadata,created_by)
     values(g.tenant_id,gi.variant_id,v_batch_id,'purchase',v_a+v_d,g.location_id,g.supplier_id,g.grn_number,'grn:'||g.id::text||':item:'||gi.id::text||':batch:'||v_batch_id::text,jsonb_build_object('source_type','grn','goods_receipt_id',g.id,'goods_receipt_item_id',gi.id,'accepted_quantity',v_a,'damaged_quantity',v_d),auth.uid());
   end loop;
   if abs(v_sum_a-gi.accepted_quantity)>0.000001 or abs(v_sum_d-gi.damaged_quantity)>0.000001 then raise exception 'Batch accepted/damaged quantities must match the GRN line';end if;
 end if;
end$$;
revoke all on function private.goods_receipt_apply_tracking_v484(uuid) from public;

create or replace function public.goods_receipt_post_v484(p_tenant_id uuid,p_goods_receipt_id uuid,p_device_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare g public.goods_receipts_v484%rowtype;gi public.goods_receipt_items_v484%rowtype;v_item_type text;v_physical numeric;v_before numeric;v_after numeric;v_remaining numeric;v_any_open boolean:=false;v_old_po_status text;begin
  select * into g from public.goods_receipts_v484 where tenant_id=p_tenant_id and id=p_goods_receipt_id for update;if not found then raise exception 'GRN not found';end if;perform private.purchasing_v484_access(p_tenant_id,g.location_id,true);if g.status='posted' then return jsonb_build_object('success',true,'goods_receipt_id',g.id,'grn_number',g.grn_number,'status','posted','idempotent',true);end if;if g.status<>'draft' then raise exception 'Only Draft GRNs can be posted';end if;
  for gi in select * from public.goods_receipt_items_v484 where goods_receipt_id=g.id order by id loop
    select p.item_type into v_item_type from public.product_variants pv join public.products p on p.id=pv.product_id where pv.id=gi.variant_id and pv.tenant_id=p_tenant_id;if v_item_type is null then raise exception 'Product not found';end if;
    select greatest(quantity-coalesce(received_quantity,0),0) into v_remaining from public.purchase_order_items_v480 where id=gi.purchase_order_item_id for update;if gi.received_quantity-v_remaining>0.000001 then raise exception 'PO remaining quantity changed; reopen the GRN and receive only the remaining quantity';end if;
    if v_item_type='stock' then
      perform private.goods_receipt_apply_tracking_v484(gi.id);
      v_physical:=gi.accepted_quantity+gi.damaged_quantity;
      if v_physical>0 then
        perform public.inventory_adjust_stock(p_tenant_id,gi.variant_id,v_physical,'GRN '||g.grn_number);
        v_after:=private.v4_location_stock_apply(p_tenant_id,g.location_id,gi.variant_id,v_physical,'grn','goods_receipt',g.id,g.grn_number,'Goods received',p_device_id,false);
        if gi.damaged_quantity>0 then
          update public.location_stock_balances set damaged_quantity=coalesce(damaged_quantity,0)+gi.damaged_quantity,updated_at=now() where tenant_id=p_tenant_id and location_id=g.location_id and variant_id=gi.variant_id;
          select balance_before,balance_after into v_before,v_after from public.location_stock_movements where tenant_id=p_tenant_id and reference_type='goods_receipt' and reference_id=g.id and variant_id=gi.variant_id and movement_type='grn' order by created_at desc limit 1;
          insert into public.location_stock_movements(tenant_id,location_id,variant_id,movement_type,quantity_delta,base_quantity_delta,display_quantity,balance_before,balance_after,unit_cost,reference_type,reference_id,reference_number,note,created_by,device_id,movement_group,metadata)
          values(p_tenant_id,g.location_id,gi.variant_id,'damage',0,0,gi.damaged_quantity,coalesce(v_after-v_physical,0),coalesce(v_after,0),gi.unit_cost,'goods_receipt',g.id,g.grn_number,coalesce(gi.damage_note,'Damaged on receipt'),auth.uid(),p_device_id,'damage',jsonb_build_object('damaged_quantity',gi.damaged_quantity,'goods_receipt_item_id',gi.id));
        end if;
      end if;
    end if;
    update public.purchase_order_items_v480 set received_quantity=received_quantity+gi.received_quantity,accepted_quantity=accepted_quantity+gi.accepted_quantity,damaged_quantity=damaged_quantity+gi.damaged_quantity,rejected_quantity=rejected_quantity+gi.rejected_quantity where id=gi.purchase_order_item_id;
  end loop;
  select exists(select 1 from public.purchase_order_items_v480 where purchase_order_id=g.purchase_order_id and received_quantity+0.000001<quantity) into v_any_open;
  select status into v_old_po_status from public.purchase_orders_v480 where id=g.purchase_order_id for update;
  update public.purchase_orders_v480 set status=case when v_any_open then 'partially_received' else 'received' end,updated_at=now() where id=g.purchase_order_id;
  insert into public.purchase_order_status_history_v480(purchase_order_id,from_status,to_status,reason,changed_by)
  values(g.purchase_order_id,v_old_po_status,case when v_any_open then 'partially_received' else 'received' end,'GRN '||g.grn_number||' posted',auth.uid());
  update public.goods_receipts_v484 set status='posted',posted_by=auth.uid(),posted_at=now(),updated_at=now() where id=g.id;
  perform private.thq_sync_bump_v480(p_tenant_id,'inventory','goods_receipt',g.id::text,'post');
  return jsonb_build_object('success',true,'goods_receipt_id',g.id,'grn_number',g.grn_number,'status','posted','purchase_order_status',case when v_any_open then 'partially_received' else 'received' end);
end$$;
grant execute on function public.goods_receipt_post_v484(uuid,uuid,uuid) to authenticated;

create or replace function public.goods_receipt_list_v484(p_tenant_id uuid,p_location_id uuid default null,p_status text default null,p_query text default '',p_limit integer default 500)
returns table(id uuid,grn_number text,receipt_date date,status text,purchase_order_id uuid,order_number text,supplier_id uuid,supplier_name text,location_id uuid,location_name text,line_count bigint,received_quantity numeric,accepted_quantity numeric,damaged_quantity numeric,rejected_quantity numeric,created_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
 perform private.purchasing_v484_permission(p_tenant_id,false);
 return query select g.id,g.grn_number,g.receipt_date,g.status,g.purchase_order_id,po.order_number,g.supplier_id,s.name,g.location_id,l.name,count(i.id),coalesce(sum(i.received_quantity),0),coalesce(sum(i.accepted_quantity),0),coalesce(sum(i.damaged_quantity),0),coalesce(sum(i.rejected_quantity),0),g.created_at
 from public.goods_receipts_v484 g join public.purchase_orders_v480 po on po.id=g.purchase_order_id join public.suppliers s on s.id=g.supplier_id join public.business_locations l on l.id=g.location_id left join public.goods_receipt_items_v484 i on i.goods_receipt_id=g.id left join public.product_variants pv on pv.id=i.variant_id left join public.products p on p.id=pv.product_id
 where g.tenant_id=p_tenant_id and (p_location_id is null or g.location_id=p_location_id) and (p_status is null or p_status='' or g.status=p_status) and private.erp_document_scope_allowed(p_tenant_id,g.location_id,p_location_id,'view')
 and (trim(coalesce(p_query,''))='' or lower(g.grn_number) like q or lower(po.order_number) like q or lower(s.name) like q or lower(coalesce(g.supplier_delivery_note,'')) like q or lower(coalesce(p.name,'')) like q or lower(coalesce(pv.sku,'')) like q)
 group by g.id,po.order_number,s.name,l.name order by g.created_at desc limit greatest(1,least(coalesce(p_limit,500),2000));
end$$;
grant execute on function public.goods_receipt_list_v484(uuid,uuid,text,text,integer) to authenticated;

create or replace function public.goods_receipt_detail_v484(p_tenant_id uuid,p_goods_receipt_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_loc uuid;v jsonb;begin
 select location_id into v_loc from public.goods_receipts_v484 where tenant_id=p_tenant_id and id=p_goods_receipt_id;if v_loc is null then raise exception 'GRN not found';end if;perform private.purchasing_v484_access(p_tenant_id,v_loc,false);
 select jsonb_build_object('grn',to_jsonb(g)||jsonb_build_object('order_number',po.order_number,'supplier_name',s.name,'location_name',l.name),
 'items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('product_name',p.name,'sku',pv.sku,'ordered_quantity',poi.quantity,'po_received_quantity',poi.received_quantity) order by p.name) from public.goods_receipt_items_v484 i join public.purchase_order_items_v480 poi on poi.id=i.purchase_order_item_id join public.product_variants pv on pv.id=i.variant_id join public.products p on p.id=pv.product_id where i.goods_receipt_id=g.id),'[]'::jsonb)) into v
 from public.goods_receipts_v484 g join public.purchase_orders_v480 po on po.id=g.purchase_order_id join public.suppliers s on s.id=g.supplier_id join public.business_locations l on l.id=g.location_id where g.id=p_goods_receipt_id and g.tenant_id=p_tenant_id;return v;
end$$;
grant execute on function public.goods_receipt_detail_v484(uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(141,'4.8.4','Purchasing V2','GRN posting, partial receiving, damaged/quarantined stock, rejected receiving and serial/batch-aware receipt provenance.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.4 migration 141 GRN receiving applied' as status;
