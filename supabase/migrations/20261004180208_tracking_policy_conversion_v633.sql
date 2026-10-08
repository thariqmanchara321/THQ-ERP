begin;

-- A conversion changes trace allocation, never quantity, valuation or journals.
alter table public.product_tracking_policies_v483 add column if not exists tracking_revision integer not null default 0 check(tracking_revision>=0);
create table if not exists private.tracking_conversions_v633(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id),variant_id uuid not null references public.product_variants(id),
 request_id text not null,request_payload jsonb not null,from_mode text not null,to_mode text not null,revision integer not null,
 reason text not null,stock_snapshot jsonb not null,trace_snapshot jsonb not null,created_by uuid references auth.users(id),created_at timestamptz not null default now(),
 unique(tenant_id,request_id),unique(tenant_id,variant_id,revision)
);
create table if not exists private.tracking_document_lines_v633(
 tenant_id uuid not null,document_type text not null check(document_type in('sale','purchase')),item_id uuid not null,variant_id uuid not null,
 tracking_mode text not null,tracking_revision integer not null,primary key(tenant_id,document_type,item_id)
);
create table if not exists private.tracking_return_bridges_v633(
 tenant_id uuid not null,document_type text not null,item_id uuid not null,variant_id uuid not null,original_mode text not null,current_mode text not null,
 original_allocations jsonb not null,current_allocations jsonb not null,quantity numeric not null,created_by uuid,created_at timestamptz not null default now(),
 primary key(tenant_id,document_type,item_id)
);
alter table private.tracking_conversions_v633 enable row level security;
alter table private.tracking_document_lines_v633 enable row level security;
alter table private.tracking_return_bridges_v633 enable row level security;
revoke all on private.tracking_conversions_v633,private.tracking_document_lines_v633,private.tracking_return_bridges_v633 from public,anon,authenticated;

create or replace function private.tracking_lock_v633(p_tenant_id uuid) returns void language sql volatile security definer set search_path='' as $$
 select pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended(p_tenant_id::text||':tracking-policy',633));
$$;
revoke all on function private.tracking_lock_v633(uuid) from public,anon,authenticated;
create or replace function private.v483_tracking_mode(p_tenant_id uuid,p_variant_id uuid) returns text language plpgsql volatile security definer set search_path='' as $$
begin
 perform private.tracking_lock_v633(p_tenant_id);
 return coalesce((select tracking_mode from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id),'none');
end $$;
revoke all on function private.v483_tracking_mode(uuid,uuid) from public,anon,authenticated;

create or replace function private.tracking_write_guard_v633() returns trigger language plpgsql security definer set search_path='' as $$
declare t uuid;v uuid;m text;
begin
 if tg_table_name='goods_receipt_items_v484' then
  select tenant_id into t from public.goods_receipts_v484 where id=case when tg_op='DELETE' then old.goods_receipt_id else new.goods_receipt_id end;
 elsif tg_table_name='stock_transfer_items' then
  select tenant_id into t from public.stock_transfers where id=case when tg_op='DELETE' then old.transfer_id else new.transfer_id end;
 else
  if tg_op='DELETE' then t:=old.tenant_id;else t:=new.tenant_id;end if;
 end if;
 perform private.tracking_lock_v633(t);
 if tg_op='INSERT' and tg_table_name in('sale_items','purchase_items') then
  v:=new.variant_id;m:=private.v483_tracking_mode(t,v);
  insert into private.tracking_document_lines_v633(tenant_id,document_type,item_id,variant_id,tracking_mode,tracking_revision)
  values(t,case when tg_table_name='sale_items' then 'sale' else 'purchase' end,new.id,v,m,
   coalesce((select tracking_revision from public.product_tracking_policies_v483 where tenant_id=t and variant_id=v),0)) on conflict(tenant_id,document_type,item_id) do nothing;
 end if;
 if tg_op='DELETE' then return old;else return new;end if;
end $$;
revoke all on function private.tracking_write_guard_v633() from public,anon,authenticated;
do $$declare tbl text;begin
 foreach tbl in array array['location_stock_balances','stock_balances','inventory_batch_balances_v483','inventory_serials_v483','stock_transfers','stock_transfer_items','goods_receipts_v484','goods_receipt_items_v484','sale_items','purchase_items','product_tracking_policies_v483'] loop
  if to_regclass('public.'||tbl) is not null then
   execute format('drop trigger if exists tracking_write_guard_v633 on public.%I',tbl);
   execute format('create trigger tracking_write_guard_v633 before insert or update or delete on public.%I for each row execute function private.tracking_write_guard_v633()',tbl);
  end if;
 end loop;
end $$;

create or replace function private.tracking_source_v633(t uuid,k text,i uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s private.tracking_document_lines_v633%rowtype;m text;v uuid;
begin
 select * into s from private.tracking_document_lines_v633 where tenant_id=t and document_type=k and item_id=i;
 if found then return jsonb_build_object('mode',s.tracking_mode,'revision',s.tracking_revision,'variant_id',s.variant_id);end if;
 if k='sale' then select variant_id into v from public.sale_items where tenant_id=t and id=i;
 else select variant_id into v from public.purchase_items where tenant_id=t and id=i;end if;
 if v is null then raise exception 'Original invoice item was not found' using errcode='42501';end if;
 select case when bool_or(serial_id is not null) then 'serial' when bool_or(batch_id is not null) then 'batch' else 'none' end into m
 from public.inventory_trace_events_v483 where tenant_id=t and ((k='sale' and sale_item_id=i and event_type='sale') or (k='purchase' and purchase_item_id=i and event_type='purchase'));
 return jsonb_build_object('mode',coalesce(m,'none'),'revision',0,'variant_id',v);
end $$;
revoke all on function private.tracking_source_v633(uuid,text,uuid) from public,anon,authenticated;

create or replace function public.inventory_tracking_conversion_preview_v633(p_tenant_id uuid,p_variant_id uuid) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare m text;locations jsonb;blockers jsonb:='[]';r record;tracked numeric;
begin
 if auth.uid() is null or (not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage')) then raise exception 'Inventory manage permission required' using errcode='42501';end if;
 m:=private.v483_tracking_mode(p_tenant_id,p_variant_id);
 if not exists(select 1 from public.product_variants v join public.products p on p.id=v.product_id and p.tenant_id=v.tenant_id where v.tenant_id=p_tenant_id and v.id=p_variant_id and p.item_type='stock') then raise exception 'Choose a stock product';end if;
 for r in select b.*,l.name from public.location_stock_balances b join public.business_locations l on l.id=b.location_id and l.tenant_id=b.tenant_id where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id order by b.location_id loop
  perform private.v4_location_access(p_tenant_id,r.location_id,'manage');
  if r.quantity<0 or r.reserved_quantity<>0 or r.damaged_quantity<>0 or r.quarantine_quantity<>0 then blockers:=blockers||jsonb_build_array(r.name||': resolve reservations, damaged/quarantined or negative stock first.');end if;
  tracked:=private.v483_location_tracked_quantity(p_tenant_id,p_variant_id,r.location_id,m);
  if m<>'none' and abs(tracked-r.quantity)>0.000001 then blockers:=blockers||jsonb_build_array(r.name||': reconcile tracking and stock quantities first.');end if;
 end loop;
 if exists(select 1 from public.stock_transfer_items i join public.stock_transfers s on s.id=i.transfer_id where s.tenant_id=p_tenant_id and i.variant_id=p_variant_id and s.status in('draft','requested','approved','dispatched','in_transit')) then blockers:=blockers||'"Finish or cancel outstanding stock transfers."'::jsonb;end if;
 if exists(select 1 from public.inventory_serials_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id and (status in('quarantine','recalled','in_transit') or reserved_transfer_id is not null)) then blockers:=blockers||'"Resolve reserved or quarantined serials first."'::jsonb;end if;
 if exists(select 1 from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.batch_id=b.id and bb.tenant_id=b.tenant_id where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and (bb.reserved_quantity<>0 or bb.damaged_quantity<>0 or (bb.quantity>0 and b.status in('quarantine','recalled')))) then blockers:=blockers||'"Resolve reserved, damaged or quarantined batches first."'::jsonb;end if;
 if exists(select 1 from public.goods_receipt_items_v484 i join public.goods_receipts_v484 g on g.id=i.goods_receipt_id where g.tenant_id=p_tenant_id and i.variant_id=p_variant_id and g.status='draft') then blockers:=blockers||'"Post or cancel draft goods receipts first."'::jsonb;end if;
 if exists(select 1 from public.goods_receipt_items_v484 i join public.goods_receipts_v484 g on g.id=i.goods_receipt_id where g.tenant_id=p_tenant_id and i.variant_id=p_variant_id and g.status='posted' and i.accepted_quantity>coalesce((select sum(ii.quantity) from public.purchase_invoice_items_v484 ii join public.purchase_invoices_v484 h on h.id=ii.purchase_invoice_id where ii.goods_receipt_item_id=i.id and h.status<>'void'),0)+0.000001) then blockers:=blockers||'"Invoice or cancel outstanding goods receipts before changing tracking."'::jsonb;end if;
 if exists(select 1 from public.inventory_serials_v483 s where s.tenant_id=p_tenant_id and s.variant_id=p_variant_id and s.status='in_stock' and not exists(select 1 from public.location_stock_balances lb where lb.tenant_id=p_tenant_id and lb.variant_id=p_variant_id and lb.location_id=s.current_location_id)) or exists(select 1 from public.inventory_batch_balances_v483 bb join public.inventory_batches_v483 b on b.id=bb.batch_id where bb.tenant_id=p_tenant_id and b.variant_id=p_variant_id and bb.quantity>0 and not exists(select 1 from public.location_stock_balances lb where lb.tenant_id=p_tenant_id and lb.variant_id=p_variant_id and lb.location_id=bb.location_id)) then blockers:=blockers||'"Reconcile tracking at missing stock locations first."'::jsonb;end if;
 if m='batch' and exists(select 1 from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.batch_id=b.id where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and bb.quantity>0 and b.expiry_on<current_date) and not coalesce((select allow_expired_sale from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id),false) then blockers:=blockers||'"Resolve expired stock before changing tracking."'::jsonb;end if;
 if exists(select 1 from public.stock_adjustment_requests_v500 where tenant_id=p_tenant_id and variant_id=p_variant_id and status in('pending','requested')) then blockers:=blockers||'"Resolve pending stock adjustments first."'::jsonb;end if;
 if exists(select 1 from public.pos_offline_sync_v486 s cross join lateral jsonb_array_elements(coalesce(s.payload_snapshot->'items','[]')) x where s.tenant_id=p_tenant_id and s.status<>'synced' and x->>'variant_id'=p_variant_id::text) then blockers:=blockers||'"Resolve pending offline invoices containing this product."'::jsonb;end if;
 select coalesce(jsonb_agg(jsonb_build_object('location_id',b.location_id,'name',l.name,'quantity',b.quantity,'average_cost',b.average_cost) order by b.location_id),'[]') into locations from public.location_stock_balances b join public.business_locations l on l.id=b.location_id where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id;
 return jsonb_build_object('mode',m,'revision',coalesce((select tracking_revision from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id),0),'locations',locations,'blockers',blockers,'ready',jsonb_array_length(blockers)=0,
 'history',coalesce((select jsonb_agg(jsonb_build_object('from',from_mode,'to',to_mode,'reason',reason,'at',created_at,'revision',revision) order by revision desc) from private.tracking_conversions_v633 where tenant_id=p_tenant_id and variant_id=p_variant_id),'[]'));
end $$;
revoke all on function public.inventory_tracking_conversion_preview_v633(uuid,uuid) from public,anon;
grant execute on function public.inventory_tracking_conversion_preview_v633(uuid,uuid) to authenticated;

create or replace function public.inventory_tracking_convert_v633(p_tenant_id uuid,p_variant_id uuid,p_mode text,p_expected_revision integer,p_locations jsonb,p_reason text,p_request_id text,p_devices_synced boolean,p_policy jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare preview jsonb;existing private.tracking_conversions_v633%rowtype;payload jsonb;cid uuid:=gen_random_uuid();rev integer;old_mode text;trace jsonb;loc jsonb;a jsonb;r record;bid uuid;sid uuid;n text;qty numeric;total numeric;seen text[]:='{}';
begin
 if auth.uid() is null or (not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage')) then raise exception 'Inventory manage permission required' using errcode='42501';end if;
 if p_mode not in('none','serial','batch') or length(trim(coalesce(p_reason,'')))<5 or nullif(trim(p_request_id),'') is null then raise exception 'Choose a tracking method, give a reason and retry identifier';end if;
 if p_devices_synced is distinct from true then raise exception 'Sync all POS/mobile devices before changing tracking';end if;
 perform set_config('lock_timeout','5s',true);
 if not pg_try_advisory_xact_lock(hashtextextended(p_tenant_id::text||':tracking-policy',633)) then raise exception 'Stock is being posted. Retry the tracking conversion after it finishes.';end if;
 -- Fail immediately if an older writer already holds a row lock before reaching its tracking guard.
 perform 1 from public.location_stock_balances where tenant_id=p_tenant_id and variant_id=p_variant_id for update nowait;
 perform 1 from public.inventory_serials_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id for update nowait;
 perform 1 from public.inventory_batch_balances_v483 bb join public.inventory_batches_v483 b on b.id=bb.batch_id where bb.tenant_id=p_tenant_id and b.variant_id=p_variant_id for update of bb nowait;
 payload:=jsonb_build_object('variant_id',p_variant_id,'mode',p_mode,'revision',p_expected_revision,'locations',p_locations,'reason',trim(p_reason),'policy',p_policy);
 select * into existing from private.tracking_conversions_v633 where tenant_id=p_tenant_id and request_id=trim(p_request_id);
 if found then
  if existing.request_payload<>payload then raise exception 'This retry identifier was used for a different conversion';end if;
  return jsonb_build_object('converted',true,'idempotent_replay',true,'conversion_id',existing.id,'revision',existing.revision,'mode',existing.to_mode);
 end if;
 preview:=public.inventory_tracking_conversion_preview_v633(p_tenant_id,p_variant_id);
 if not (preview->>'ready')::boolean then raise exception '%',preview->'blockers';end if;
 rev:=(preview->>'revision')::integer;old_mode:=preview->>'mode';
 if rev<>p_expected_revision then raise exception 'Tracking changed while this page was open. Reload before converting.';end if;
 if old_mode=p_mode then raise exception 'This tracking method is already active';end if;
 if jsonb_typeof(p_locations)<>'array' or jsonb_array_length(p_locations)<>jsonb_array_length(preview->'locations') then raise exception 'Include every stock location in the conversion';end if;
 select jsonb_build_object('serials',coalesce((select jsonb_agg(to_jsonb(s)) from public.inventory_serials_v483 s where s.tenant_id=p_tenant_id and s.variant_id=p_variant_id and s.status='in_stock'),'[]'),
 'batches',coalesce((select jsonb_agg(to_jsonb(bb)||jsonb_build_object('batch_number',b.batch_number)) from public.inventory_batch_balances_v483 bb join public.inventory_batches_v483 b on b.id=bb.batch_id where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and bb.quantity>0),'[]')) into trace;
 for loc in select value from jsonb_array_elements(p_locations) loop
  n:=loc->>'location_id';if n=any(seen) then raise exception 'A stock location appears twice';end if;seen:=array_append(seen,n);
  select * into r from public.location_stock_balances where tenant_id=p_tenant_id and variant_id=p_variant_id and location_id=n::uuid for update;
  if not found or r.quantity<>coalesce((loc->>'expected_quantity')::numeric,-1) then raise exception 'Stock changed or a location is missing. Reload the conversion.';end if;
  if p_mode='serial' then
   if r.quantity<>trunc(r.quantity) or jsonb_typeof(loc->'serial_numbers')<>'array' or jsonb_array_length(loc->'serial_numbers')<>r.quantity then raise exception 'Enter one serial number per whole base unit at every location';end if;
  elsif p_mode='batch' then
   if jsonb_typeof(loc->'batches')<>'array' then raise exception 'Enter batch allocations at every location';end if;
   select coalesce(sum((x->>'quantity')::numeric),0) into total from jsonb_array_elements(loc->'batches') x;
   if abs(total-r.quantity)>0.000001 then raise exception 'Batch allocations must equal the location stock quantity';end if;
  end if;
 end loop;
 update public.inventory_serials_v483 set status='void',current_location_id=null,updated_at=now() where tenant_id=p_tenant_id and variant_id=p_variant_id and status='in_stock';
 update public.inventory_batch_balances_v483 bb set quantity=0,updated_at=now() from public.inventory_batches_v483 b where bb.batch_id=b.id and bb.tenant_id=p_tenant_id and b.tenant_id=p_tenant_id and b.variant_id=p_variant_id;
 insert into public.product_tracking_policies_v483(tenant_id,variant_id,tracking_mode,tracking_revision) values(p_tenant_id,p_variant_id,p_mode,rev+1)
 on conflict(tenant_id,variant_id) do update set tracking_mode=excluded.tracking_mode,tracking_revision=excluded.tracking_revision,warranty_enabled=case when excluded.tracking_mode='none' then false else public.product_tracking_policies_v483.warranty_enabled end,require_batch_expiry=false,allow_expired_sale=false,updated_at=now();
 perform public.inventory_tracking_policy_save_v483(p_tenant_id,p_variant_id,p_mode,case when p_mode='none' then false else coalesce((p_policy->>'warranty_enabled')::boolean,(select warranty_enabled from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id),false) end,coalesce((p_policy->>'warranty_months')::integer,(select warranty_months from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id),0),coalesce((p_policy->>'warranty_days')::integer,(select warranty_days from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id),0),coalesce((p_policy->>'require_batch_expiry')::boolean,false),coalesce((p_policy->>'allow_expired_sale')::boolean,false));
 seen:='{}';
 for loc in select value from jsonb_array_elements(p_locations) loop
  if p_mode='serial' then
   for a in select value from jsonb_array_elements(loc->'serial_numbers') loop
    n:=trim(a#>>'{}');if n='' or lower(n)=any(seen) then raise exception 'Serial numbers must be nonempty and unique';end if;seen:=array_append(seen,lower(n));
    select id into sid from public.inventory_serials_v483 where tenant_id=p_tenant_id and lower(trim(serial_number))=lower(n);
    if sid is not null then
     if not exists(select 1 from public.inventory_serials_v483 where id=sid and variant_id=p_variant_id and status='void') then raise exception 'Serial % is already assigned to another unit',n;end if;
     update public.inventory_serials_v483 set status='in_stock',current_location_id=(loc->>'location_id')::uuid,updated_at=now() where id=sid;
    else insert into public.inventory_serials_v483(tenant_id,variant_id,serial_number,status,current_location_id,received_at,created_by) values(p_tenant_id,p_variant_id,n,'in_stock',(loc->>'location_id')::uuid,now(),auth.uid()) returning id into sid;end if;
    insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,source_key,metadata,created_by) values(p_tenant_id,p_variant_id,sid,'opening',1,(loc->>'location_id')::uuid,'conversion:'||cid||':'||sid,jsonb_build_object('conversion_id',cid,'trace_only',true),auth.uid());
   end loop;
  elsif p_mode='batch' then
   for a in select value from jsonb_array_elements(loc->'batches') loop
    n:=trim(a->>'batch_number');qty:=(a->>'quantity')::numeric;
    if n is null or n='' or qty<=0 then raise exception 'Each batch needs a number and positive quantity';end if;
    if (loc->>'location_id')||':'||lower(n)=any(seen) then raise exception 'A batch appears twice at the same location';end if;seen:=array_append(seen,(loc->>'location_id')||':'||lower(n));
    select id into bid from public.inventory_batches_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id and lower(trim(batch_number))=lower(n);
    if bid is not null and not exists(select 1 from public.inventory_batches_v483 where id=bid and notes='Tracking conversion '||cid) then raise exception 'Use a new batch number for converted stock; existing batch history is preserved';end if;
    if exists(select 1 from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id and require_batch_expiry) and nullif(a->>'expiry_on','') is null then raise exception 'Enter expiry dates for every conversion batch';end if;
    if bid is null then
    insert into public.inventory_batches_v483(tenant_id,variant_id,batch_number,expiry_on,manufactured_on,notes,created_by) values(p_tenant_id,p_variant_id,n,nullif(a->>'expiry_on','')::date,nullif(a->>'manufactured_on','')::date,'Tracking conversion '||cid,auth.uid()) returning id into bid;else
     if exists(select 1 from public.inventory_batches_v483 where id=bid and (expiry_on is distinct from nullif(a->>'expiry_on','')::date or manufactured_on is distinct from nullif(a->>'manufactured_on','')::date)) then raise exception 'The same batch must have matching dates at every location';end if;
    end if;
    insert into public.inventory_batch_balances_v483(tenant_id,batch_id,location_id,quantity) values(p_tenant_id,bid,(loc->>'location_id')::uuid,qty);
    insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,source_key,metadata,created_by) values(p_tenant_id,p_variant_id,bid,'opening',qty,(loc->>'location_id')::uuid,'conversion:'||cid||':'||bid||':'||(loc->>'location_id'),jsonb_build_object('conversion_id',cid,'trace_only',true),auth.uid());
   end loop;
  end if;
 end loop;
 for r in select * from public.location_stock_balances where tenant_id=p_tenant_id and variant_id=p_variant_id loop perform private.v483_assert_reconciled(p_tenant_id,p_variant_id,r.location_id);end loop;
 insert into private.tracking_conversions_v633(id,tenant_id,variant_id,request_id,request_payload,from_mode,to_mode,revision,reason,stock_snapshot,trace_snapshot,created_by) values(cid,p_tenant_id,p_variant_id,trim(p_request_id),payload,old_mode,p_mode,rev+1,trim(p_reason),preview->'locations',trace,auth.uid());
 perform private.thq_sync_bump_v480(p_tenant_id,'catalogue','tracking_policy',p_variant_id::text,'convert');
 perform private.business_audit_write_v471(p_tenant_id,'inventory.tracking.convert','product_variant',p_variant_id,null,jsonb_build_object('mode',old_mode,'revision',rev),jsonb_build_object('mode',p_mode,'revision',rev+1,'conversion_id',cid,'reason',trim(p_reason),'stock',preview->'locations'));
 return jsonb_build_object('converted',true,'conversion_id',cid,'mode',p_mode,'revision',rev+1);
end $$;
revoke all on function public.inventory_tracking_convert_v633(uuid,uuid,text,integer,jsonb,text,text,boolean,jsonb) from public,anon;
grant execute on function public.inventory_tracking_convert_v633(uuid,uuid,text,integer,jsonb,text,text,boolean,jsonb) to authenticated;

create or replace function public.inventory_return_tracking_context_v633(p_tenant_id uuid,p_kind text,p_item_id uuid) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare src jsonb;v uuid;l uuid;doc uuid;m text;original jsonb;current_options jsonb;
begin
 if auth.uid() is null or not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied' using errcode='42501';end if;
 if p_kind='sale' then select i.variant_id,s.location_id,s.id into v,l,doc from public.sale_items i join public.sales s on s.id=i.sale_id where i.tenant_id=p_tenant_id and i.id=p_item_id;
 elsif p_kind='purchase' then select i.variant_id,p.location_id,p.id into v,l,doc from public.purchase_items i join public.purchases p on p.id=i.purchase_id where i.tenant_id=p_tenant_id and i.id=p_item_id;
 else raise exception 'Choose a sale or purchase return';end if;
 if v is null then raise exception 'Original invoice item not found' using errcode='42501';end if;
 perform private.v4_location_access(p_tenant_id,l,'view');
 src:=private.tracking_source_v633(p_tenant_id,p_kind,p_item_id);m:=private.v483_tracking_mode(p_tenant_id,v);
 select coalesce(jsonb_agg(jsonb_build_object('serial_number',s.serial_number) order by s.serial_number),'[]') into original
 from public.inventory_serials_v483 s where s.tenant_id=p_tenant_id and exists(select 1 from public.inventory_trace_events_v483 e where e.tenant_id=p_tenant_id and e.serial_id=s.id and ((p_kind='sale' and e.sale_item_id=p_item_id and e.event_type='sale') or (p_kind='purchase' and e.purchase_item_id=p_item_id and e.event_type='purchase'))) and not exists(select 1 from public.inventory_trace_events_v483 ret where ret.tenant_id=p_tenant_id and ret.serial_id=s.id and ((p_kind='sale' and ret.sale_item_id=p_item_id and ret.event_type='sale_return') or (p_kind='purchase' and ret.purchase_item_id=p_item_id and ret.event_type='purchase_return')) and not coalesce((ret.metadata->>'tracking_bridge_current')::boolean,false));
 src:=src||jsonb_build_object('serials',original);
 select coalesce(jsonb_agg(jsonb_build_object('batch_id',x.batch_id,'batch_number',b.batch_number,'remaining_quantity',greatest(x.received-x.returned,0)) order by b.batch_number),'[]') into original
 from (select e.batch_id,sum(case when e.event_type in('sale','purchase') then e.quantity else 0 end) received,sum(case when e.event_type in('sale_return','purchase_return') then e.quantity else 0 end) returned
 from public.inventory_trace_events_v483 e where e.tenant_id=p_tenant_id and e.batch_id is not null and not coalesce((e.metadata->>'tracking_bridge_current')::boolean,false)
 and ((p_kind='sale' and e.sale_item_id=p_item_id and e.event_type in('sale','sale_return')) or (p_kind='purchase' and e.purchase_item_id=p_item_id and e.event_type in('purchase','purchase_return'))) group by e.batch_id) x join public.inventory_batches_v483 b on b.id=x.batch_id;
 current_options:=public.inventory_transfer_tracking_options_v485(p_tenant_id,l,v);
 return src||jsonb_build_object('batches',original,'current_mode',m,'current_revision',coalesce((select tracking_revision from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=v),0),'current_options',current_options,'location_id',l,'document_id',doc);
end $$;
revoke all on function public.inventory_return_tracking_context_v633(uuid,text,uuid) from public,anon;
grant execute on function public.inventory_return_tracking_context_v633(uuid,text,uuid) to authenticated;

create or replace function private.tracking_bridge_return_v633(t uuid,k text,return_id uuid,return_item uuid,input jsonb) returns boolean language plpgsql security definer set search_path='' as $$
declare original_item uuid;v uuid;doc uuid;l uuid;ref text;party uuid;qty numeric;src jsonb;orig text;cur text;rev integer;
 allocations jsonb:='[]';targets jsonb:='[]';a jsonb;n text;sid uuid;bid uuid;received numeric;returned numeric;total numeric:=0;q numeric;w record;left_qty numeric;take_qty numeric;seen text[]:='{}';ev text;
begin
 if k='sale' then
  select i.sale_item_id,i.variant_id,r.sale_id,r.location_id,r.return_number,s.customer_id,i.quantity into original_item,v,doc,l,ref,party,qty from public.sales_return_items i join public.sales_returns r on r.id=i.sales_return_id join public.sales s on s.id=r.sale_id where r.tenant_id=t and r.id=return_id and i.id=return_item;
 else
  select i.purchase_item_id,i.variant_id,r.purchase_id,r.location_id,r.return_number,p.supplier_id,i.quantity into original_item,v,doc,l,ref,party,qty from public.purchase_return_items i join public.purchase_returns r on r.id=i.purchase_return_id join public.purchases p on p.id=r.purchase_id where r.tenant_id=t and r.id=return_id and i.id=return_item;
 end if;
 if v is null then raise exception 'Return item not found';end if;
 src:=private.tracking_source_v633(t,k,original_item);orig:=src->>'mode';cur:=private.v483_tracking_mode(t,v);
 rev:=coalesce((select tracking_revision from public.product_tracking_policies_v483 where tenant_id=t and variant_id=v),0);
 if rev=(src->>'revision')::integer then return false;end if;
 ev:=case when k='sale' then 'sale_return' else 'purchase_return' end;
 if orig='serial' then
  allocations:=coalesce(input->'serial_numbers','[]');
  if jsonb_typeof(allocations)<>'array' or qty<>trunc(qty) or jsonb_array_length(allocations)<>qty then raise exception 'Select exactly % original serial numbers for this return',qty;end if;
  for a in select value from jsonb_array_elements(allocations) loop
   n:=trim(case when jsonb_typeof(a)='string' then a#>>'{}' else a->>'serial_number' end);
   if n is null or n='' or lower(n)=any(seen) then raise exception 'Original serial numbers must be unique';end if;seen:=array_append(seen,lower(n));
   select id into sid from public.inventory_serials_v483 where tenant_id=t and variant_id=v and lower(trim(serial_number))=lower(n);
   if sid is null or not exists(select 1 from public.inventory_trace_events_v483 e where e.tenant_id=t and e.serial_id=sid and ((k='sale' and e.sale_item_id=original_item and e.event_type='sale') or (k='purchase' and e.purchase_item_id=original_item and e.event_type='purchase'))) then raise exception 'Serial % does not belong to the original invoice',n;end if;
   if exists(select 1 from public.inventory_trace_events_v483 e where e.tenant_id=t and e.serial_id=sid and e.event_type=ev and ((k='sale' and e.sale_item_id=original_item) or (k='purchase' and e.purchase_item_id=original_item)) and not coalesce((e.metadata->>'tracking_bridge_current')::boolean,false)) then raise exception 'Serial % was already returned on this invoice',n;end if;
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,sale_id,sale_item_id,purchase_id,purchase_item_id,reference_number,source_key,metadata,created_by)
   values(t,v,sid,ev,1,l,case when k='sale' then doc end,case when k='sale' then original_item end,case when k='purchase' then doc end,case when k='purchase' then original_item end,ref,'bridge-original:'||k||':'||return_item||':'||sid,jsonb_build_object('return_id',return_id,'return_item_id',return_item,'original_tracking',true),auth.uid());
   if cur<>'serial' then update public.inventory_serials_v483 set status=case when k='sale' then 'void' else 'returned' end,current_location_id=null,updated_at=now() where id=sid and status in('sold','void','returned');end if;
   if k='sale' then update public.product_warranties_v483 set status='void',updated_at=now() where tenant_id=t and sale_item_id=original_item and serial_id=sid and status='active';end if;
  end loop;
 elsif orig='batch' then
  allocations:=coalesce(input->'batches','[]');
  if jsonb_typeof(allocations)<>'array' or jsonb_array_length(allocations)=0 then raise exception 'Select original invoice batches for this return';end if;
  for a in select value from jsonb_array_elements(allocations) loop
   q:=coalesce((a->>'quantity')::numeric,0);bid:=null;
   select id into bid from public.inventory_batches_v483 where tenant_id=t and variant_id=v and ((nullif(a->>'batch_id','') is not null and id=(a->>'batch_id')::uuid) or (nullif(a->>'batch_id','') is null and lower(trim(batch_number))=lower(trim(a->>'batch_number'))));
   if bid is null or q<=0 or bid::text=any(seen) then raise exception 'Choose unique original batches and positive quantities';end if;seen:=array_append(seen,bid::text);
   select coalesce(sum(case when e.event_type=k then e.quantity else 0 end),0),coalesce(sum(case when e.event_type=ev then e.quantity else 0 end),0) into received,returned
   from public.inventory_trace_events_v483 e where e.tenant_id=t and e.batch_id=bid and not coalesce((e.metadata->>'tracking_bridge_current')::boolean,false) and ((k='sale' and e.sale_item_id=original_item) or (k='purchase' and e.purchase_item_id=original_item));
   if returned+q>received+0.000001 then raise exception 'Batch return exceeds the quantity on the original invoice';end if;
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,sale_id,sale_item_id,purchase_id,purchase_item_id,reference_number,source_key,metadata,created_by)
   values(t,v,bid,ev,q,l,case when k='sale' then doc end,case when k='sale' then original_item end,case when k='purchase' then doc end,case when k='purchase' then original_item end,ref,'bridge-original:'||k||':'||return_item||':'||bid,jsonb_build_object('return_id',return_id,'return_item_id',return_item,'original_tracking',true),auth.uid());
   if k='sale' then
    left_qty:=q;
    for w in select id,quantity from public.product_warranties_v483 where tenant_id=t and sale_item_id=original_item and batch_id=bid and status='active' order by created_at,id for update loop
     exit when left_qty<=0.000001;take_qty:=least(left_qty,w.quantity);
     if take_qty>=w.quantity-0.000001 then update public.product_warranties_v483 set status='void',updated_at=now() where id=w.id;
     else update public.product_warranties_v483 set quantity=quantity-take_qty,updated_at=now() where id=w.id;end if;
     left_qty:=left_qty-take_qty;
    end loop;
   end if;
   total:=total+q;
  end loop;
  if abs(total-qty)>0.000001 then raise exception 'Original batch allocations must equal the return base quantity';end if;
 end if;
 -- The authoritative return writer has already changed the stock ledger once.
 -- This section updates only the current trace representation.
 seen:='{}';total:=0;
 if cur='serial' then
  targets:=coalesce(input->'current_serial_numbers',case when orig in('serial','none') then input->'serial_numbers' end,'[]');
  if jsonb_typeof(targets)<>'array' or qty<>trunc(qty) or jsonb_array_length(targets)<>qty then raise exception 'Provide exactly % current serial numbers for returned stock',qty;end if;
  for a in select value from jsonb_array_elements(targets) loop
   n:=trim(case when jsonb_typeof(a)='string' then a#>>'{}' else a->>'serial_number' end);
   if n is null or n='' or lower(n)=any(seen) then raise exception 'Current serial numbers must be unique';end if;seen:=array_append(seen,lower(n));
   select id into sid from public.inventory_serials_v483 where tenant_id=t and lower(trim(serial_number))=lower(n) for update;
   if k='purchase' then
    if sid is null or not exists(select 1 from public.inventory_serials_v483 where id=sid and variant_id=v and status='in_stock' and current_location_id=l and reserved_transfer_id is null) then raise exception 'Current serial % is not available at this location',n;end if;
    update public.inventory_serials_v483 set status='returned',current_location_id=null,updated_at=now() where id=sid;
   else
    if sid is null then insert into public.inventory_serials_v483(tenant_id,variant_id,serial_number,status,current_location_id,received_at,created_by) values(t,v,n,'in_stock',l,now(),auth.uid()) returning id into sid;
    else
     if not exists(select 1 from public.inventory_serials_v483 where id=sid and variant_id=v and status in('void','sold','returned')) then raise exception 'Serial % is already in stock or belongs to another product',n;end if;
     if exists(select 1 from public.inventory_serials_v483 where id=sid and status='sold' and (sale_id is distinct from doc or sale_item_id is distinct from original_item)) then raise exception 'Serial % belongs to a different sale',n;end if;
     update public.inventory_serials_v483 set status='in_stock',current_location_id=l,customer_id=null,sale_id=null,sale_item_id=null,sold_at=null,updated_at=now() where id=sid;
    end if;
   end if;
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,reference_number,source_key,metadata,created_by) values(t,v,sid,ev,1,l,ref,'bridge-current:'||k||':'||return_item||':'||sid,jsonb_build_object('tracking_bridge_current',true,'return_id',return_id,'return_item_id',return_item,'original_document_id',doc),auth.uid());
  end loop;
 elsif cur='batch' then
  targets:=coalesce(input->'current_batches',case when orig='batch' then allocations when orig='none' then input->'batches' end);
  if targets is null or jsonb_array_length(targets)=0 then
   if k='purchase' then raise exception 'Select available current batches for the supplier return';end if;
   targets:=jsonb_build_array(jsonb_build_object('batch_number','RET-'||return_item::text,'quantity',qty));
  end if;
  for a in select value from jsonb_array_elements(targets) loop
   q:=coalesce((a->>'quantity')::numeric,0);n:=trim(a->>'batch_number');bid:=null;
   select id into bid from public.inventory_batches_v483 where tenant_id=t and variant_id=v and ((nullif(a->>'batch_id','') is not null and id=(a->>'batch_id')::uuid) or (nullif(a->>'batch_id','') is null and lower(trim(batch_number))=lower(n)));
   if q<=0 then raise exception 'Current batch quantities must be positive';end if;
   if bid is null then
    if k='purchase' or n is null or n='' then raise exception 'Select a current batch number';end if;
    if exists(select 1 from public.product_tracking_policies_v483 where tenant_id=t and variant_id=v and require_batch_expiry) and nullif(a->>'expiry_on','') is null then raise exception 'Enter expiry dates for return batches';end if;
    insert into public.inventory_batches_v483(tenant_id,variant_id,batch_number,expiry_on,manufactured_on,notes,created_by) values(t,v,n,nullif(a->>'expiry_on','')::date,nullif(a->>'manufactured_on','')::date,'Received from return '||ref,auth.uid()) returning id into bid;
   end if;
   if bid::text=any(seen) then raise exception 'A current batch appears twice';end if;seen:=array_append(seen,bid::text);
   if k='purchase' then
    update public.inventory_batch_balances_v483 set quantity=quantity-q,updated_at=now() where tenant_id=t and batch_id=bid and location_id=l and quantity-reserved_quantity-damaged_quantity+0.000001>=q;
    if not found then raise exception 'Insufficient available quantity in the current batch';end if;
   else
    insert into public.inventory_batch_balances_v483(tenant_id,batch_id,location_id,quantity) values(t,bid,l,q) on conflict(tenant_id,batch_id,location_id) do update set quantity=public.inventory_batch_balances_v483.quantity+excluded.quantity,updated_at=now();
    update public.inventory_batches_v483 set status='active',updated_at=now() where id=bid and status='exhausted';
   end if;
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,reference_number,source_key,metadata,created_by) values(t,v,bid,ev,q,l,ref,'bridge-current:'||k||':'||return_item||':'||bid,jsonb_build_object('tracking_bridge_current',true,'return_id',return_id,'return_item_id',return_item,'original_document_id',doc),auth.uid());
   total:=total+q;
  end loop;
  if abs(total-qty)>0.000001 then raise exception 'Current batch allocations must equal return base quantity';end if;
 end if;
 insert into private.tracking_return_bridges_v633(tenant_id,document_type,item_id,variant_id,original_mode,current_mode,original_allocations,current_allocations,quantity,created_by) values(t,k,return_item,v,orig,cur,allocations,coalesce(targets,'[]'),qty,auth.uid());
 return true;
end $$;
revoke all on function private.tracking_bridge_return_v633(uuid,text,uuid,uuid,jsonb) from public,anon,authenticated;

-- Extend the existing writers in place; their accounting/GST implementation stays authoritative.
do $$declare k text;sig text;d text;needle text;begin
 foreach k in array array['sale','purchase'] loop
  sig:=case when k='sale' then 'private.gst_sales_return_tracking_apply_v520(uuid,uuid,uuid,jsonb)' else 'private.gst_purchase_return_tracking_apply_v520(uuid,uuid,uuid,jsonb)' end;
  d:=pg_get_functiondef(to_regprocedure(sig));
  needle:='v_mode:=private.v483_tracking_mode(p_tenant_id,ri.variant_id);';
  if strpos(d,'tracking_bridge_return_v633')=0 then
   if strpos(d,needle)=0 then raise exception 'Return writer changed: %',sig;end if;
   d:=replace(d,needle,format('if private.tracking_bridge_return_v633(p_tenant_id,%L,p_return_id,p_return_item_id,p_input) then return;end if; v_mode:=private.tracking_source_v633(p_tenant_id,%L,%s)->>''mode'';',k,k,case when k='sale' then 'ri.sale_item_id' else 'ri.purchase_item_id' end));
   execute d;
  end if;
 end loop;
end $$;

create or replace function private.tracking_assert_payload_v633(t uuid,items jsonb,offline boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare x jsonb;v uuid;r integer;m text;begin
 perform private.tracking_lock_v633(t);
 for x in select value from jsonb_array_elements(coalesce(items,'[]')) loop
  v:=nullif(x->>'variant_id','')::uuid;if v is null then continue;end if;
  select tracking_revision,tracking_mode into r,m from public.product_tracking_policies_v483 where tenant_id=t and variant_id=v;r:=coalesce(r,0);m:=coalesce(m,'none');
  if (x ? 'tracking_revision' and (x->>'tracking_revision')::integer is distinct from r) or (offline and r>0 and not (x ? 'tracking_revision')) or (x ? 'tracking_mode' and x->>'tracking_mode' is distinct from m) then raise exception 'Tracking changed for a product on this invoice. Refresh the catalogue and review its tracking allocations.';end if;
  if m='none' and (jsonb_array_length(coalesce(x->'serial_numbers','[]'))>0 or jsonb_array_length(coalesce(x->'batches','[]'))>0) then raise exception 'Tracking changed. Refresh the product and remove obsolete allocations before posting.';end if;
 end loop;
end $$;
revoke all on function private.tracking_assert_payload_v633(uuid,jsonb,boolean) from public,anon,authenticated;
do $$declare sig text;d text;begin
 foreach sig in array array['private.v483_apply_sale_trace(uuid,uuid,uuid,uuid,date,jsonb)','private.v483_apply_purchase_trace(uuid,uuid,uuid,uuid,jsonb)'] loop
  d:=pg_get_functiondef(to_regprocedure(sig));
  if strpos(d,'tracking_assert_payload_v633')=0 then d:=regexp_replace(d,'\mbegin\M','begin perform private.tracking_assert_payload_v633(p_tenant_id,p_items,false);','i');execute d;end if;
 end loop;
end $$;
do $$declare r record;d text;begin
 for r in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in('pos_offline_sale_sync_v486','gst_pos_offline_sale_sync_v520','gst_pos_offline_sale_sync_v522') loop
  d:=pg_get_functiondef(r.oid);
  if strpos(d,'tracking_assert_payload_v633')=0 then
   if strpos(d,'p_payload')=0 then raise exception 'Offline writer signature changed: %',r.proname;end if;
   if strpos(d,'v_items:=coalesce(p_payload')=0 then raise exception 'Offline writer layout changed: %',r.proname;end if;
   d:=replace(d,'v_items:=coalesce(p_payload','perform private.tracking_assert_payload_v633(p_tenant_id,p_payload->''items'',true); v_items:=coalesce(p_payload');execute d;
  end if;
 end loop;
 d:=pg_get_functiondef('public.inventory_list_products_v483(uuid,uuid)'::regprocedure);
 if strpos(d,'''tracking_revision''')=0 then d:=replace(d,'''tracking_mode'',v_mode', '''tracking_revision'',coalesce((select tracking_revision from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=v_variant),0),''tracking_mode'',v_mode');execute d;end if;
 d:=pg_get_functiondef('public.inventory_tracking_policy_save_v483(uuid,uuid,text,boolean,integer,integer,boolean,boolean)'::regprocedure);
 if strpos(d,'Use Change Tracking Method')=0 then
  d:=replace(d,'if v_current_mode in(''serial'',''batch'')', 'if coalesce(v_current_mode,''none'')<>v_mode then raise exception ''Use Change Tracking Method to reconcile existing stock and preserve invoice history.'';end if; if v_current_mode in(''serial'',''batch'')');
  d:=replace(d,'if v_mode=''none'' and exists','if coalesce(v_current_mode,''none'')<>v_mode and v_mode=''none'' and exists');
  d:=regexp_replace(d,'\mbegin\M','begin perform private.tracking_lock_v633(p_tenant_id);','i');execute d;
 end if;
 d:=pg_get_functiondef('public.inventory_tracking_policy_v483(uuid,uuid)'::regprocedure);
 if strpos(d,'''tracking_revision''')=0 then d:=replace(d,'''variant_id'',p_variant_id', '''tracking_revision'',coalesce(v.tracking_revision,0),''variant_id'',p_variant_id');execute d;end if;
end $$;

-- Legacy returns/voids cannot silently bypass original trace validation after conversion.
do $$declare r record;d text;begin
 for r in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in('sales_return_create_v483','purchase_return_create_v483','sales_void_v483','purchase_void_v483') loop
  d:=pg_get_functiondef(r.oid);
  if strpos(d,'tracking_revision')=0 then
   d:=replace(d,'private.v483_tracking_mode(p_tenant_id,v_variant)<>''none''','(private.v483_tracking_mode(p_tenant_id,v_variant)<>''none'' or exists(select 1 from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=v_variant and tracking_revision>0))');
   d:=replace(d,'private.v483_tracking_mode(p_tenant_id,si.variant_id)<>''none''','(private.v483_tracking_mode(p_tenant_id,si.variant_id)<>''none'' or exists(select 1 from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=si.variant_id and tracking_revision>0))');
   d:=replace(d,'private.v483_tracking_mode(p_tenant_id,pi.variant_id)<>''none''','(private.v483_tracking_mode(p_tenant_id,pi.variant_id)<>''none'' or exists(select 1 from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=pi.variant_id and tracking_revision>0))');
   execute d;
  end if;
 end loop;
end $$;

create index if not exists tracking_trace_sale_item_v633 on public.inventory_trace_events_v483(tenant_id,sale_item_id,event_type) where sale_item_id is not null;
create index if not exists tracking_trace_purchase_item_v633 on public.inventory_trace_events_v483(tenant_id,purchase_item_id,event_type) where purchase_item_id is not null;
commit;
