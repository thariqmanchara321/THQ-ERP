alter table public.purchase_invoice_items_v484 add column if not exists discount_amount numeric not null default 0;
alter table public.purchase_invoices_v484 add column if not exists discount_total numeric not null default 0;
do $ddl$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.purchase_invoice_items_v484'::regclass and conname='purchase_invoice_items_v484_discount_nonnegative_v520') then
  alter table public.purchase_invoice_items_v484 add constraint purchase_invoice_items_v484_discount_nonnegative_v520 check(discount_amount>=0);
 end if;
 if not exists(select 1 from pg_constraint where conrelid='public.purchase_invoices_v484'::regclass and conname='purchase_invoices_v484_discount_nonnegative_v520') then
  alter table public.purchase_invoices_v484 add constraint purchase_invoices_v484_discount_nonnegative_v520 check(discount_total>=0);
 end if;
end $ddl$;

create or replace function private.gst_v520_authoritative_context_for_source(p_tenant_id uuid,p_source_type text,p_source_id uuid) returns boolean
language sql stable security definer set search_path=public,private,pg_temp as $$
 select exists(
   select 1 from private.gst_authoritative_tx_context_v520 c
   where c.txid=txid_current()
     and c.tenant_id=p_tenant_id
     and c.source_type=lower(trim(coalesce(p_source_type,'')))
     and (c.source_id is null or c.source_id=p_source_id)
 );
$$;

create or replace function private.gst_v520_authoritative_bound_context(p_tenant_id uuid,p_source_type text,p_source_id uuid) returns boolean
language sql stable security definer set search_path=public,private,pg_temp as $$
 select exists(
   select 1 from private.gst_authoritative_tx_context_v520 c
   where c.txid=txid_current()
     and c.tenant_id=p_tenant_id
     and c.source_type=lower(trim(coalesce(p_source_type,'')))
     and c.source_id=p_source_id
 );
$$;

create or replace function private.gst_mark_legacy_source_v520(p_tenant_id uuid,p_source_type text,p_source_id uuid) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_payload jsonb;v_id uuid;v_source_number text;v_document_date date;v_location_id uuid;v_taxable numeric;v_tax numeric;v_grand numeric;
begin
 if p_tenant_id is null or p_source_id is null then return null;end if;
 if private.gst_v520_authoritative_context_for_source(p_tenant_id,p_source_type,p_source_id) then return null;end if;
 if exists(select 1 from public.gst_document_snapshots_v520 s where s.tenant_id=p_tenant_id and s.source_type=p_source_type and s.source_id=p_source_id) then return null;end if;
 select m.id into v_id from public.gst_legacy_document_markers_v520 m where m.tenant_id=p_tenant_id and m.source_type=p_source_type and m.source_id=p_source_id;if v_id is not null then return v_id;end if;
 v_payload:=private.gst_legacy_source_payload_v520(p_tenant_id,p_source_type,p_source_id);if v_payload is null then return null;end if;
 v_source_number:=nullif(v_payload->>'number','');v_document_date:=nullif(v_payload->>'date','')::date;v_location_id:=nullif(v_payload->>'location_id','')::uuid;v_taxable:=coalesce(nullif(v_payload->>'taxable_total','')::numeric,nullif(v_payload->>'subtotal','')::numeric);v_tax:=coalesce(nullif(v_payload->>'tax_total','')::numeric,0);v_grand:=coalesce(nullif(v_payload->>'grand_total','')::numeric,0);
 if v_source_number is null or v_document_date is null then raise exception 'Legacy GST evidence source identity is incomplete for % %',p_source_type,p_source_id;end if;
 insert into public.gst_legacy_document_markers_v520(tenant_id,source_type,source_id,source_number,document_date,location_id,legacy_taxable_total,legacy_tax_total,legacy_grand_total,source_hash)
 values(p_tenant_id,p_source_type,p_source_id,v_source_number,v_document_date,v_location_id,v_taxable,v_tax,v_grand,encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex'))
 on conflict(tenant_id,source_type,source_id) do nothing returning id into v_id;
 if v_id is null then select m.id into v_id from public.gst_legacy_document_markers_v520 m where m.tenant_id=p_tenant_id and m.source_type=p_source_type and m.source_id=p_source_id;end if;
 return v_id;
end $$;

do $patch$
declare v_sql text;v_old text;v_new text;
begin
 select pg_get_functiondef(p.oid) into v_sql from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='v4_origin_after_insert' and p.prokind='f';
 v_old:='if not private.gst_v520_authoritative_context(new.tenant_id,new.entity_type) then perform private.v4_accounting_post_document(new.tenant_id,new.entity_type,new.entity_id);end if;';
 v_new:='if not private.gst_v520_authoritative_context_for_source(new.tenant_id,new.entity_type,new.entity_id) then perform private.v4_accounting_post_document(new.tenant_id,new.entity_type,new.entity_id);end if;';
 if position(v_old in v_sql)>0 then execute replace(v_sql,v_old,v_new);elsif position(v_new in v_sql)=0 then raise exception 'Could not safely patch v4_origin_after_insert authoritative guard';end if;

 select pg_get_functiondef(p.oid) into v_sql from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='v4_accounting_post_document' and p.prokind='f';
 v_old:='if private.gst_v520_authoritative_context(p_tenant_id,p_entity_type) then return null;end if;';
 v_new:='if private.gst_v520_authoritative_context_for_source(p_tenant_id,p_entity_type,p_entity_id) then return null;end if;';
 if position(v_old in v_sql)>0 then execute replace(v_sql,v_old,v_new);elsif position(v_new in v_sql)=0 then raise exception 'Could not safely patch v4_accounting_post_document authoritative guard';end if;

 select pg_get_functiondef(p.oid) into v_sql from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='purchase_invoice_post_v484' and p.prokind='f';
 v_old:='perform private.v4_journal_create(p_tenant_id,i.location_id,i.invoice_date,''Purchase Invoice ''||i.invoice_number,''purchase_invoice_v484'',i.id,i.invoice_number,v_lines);';
 v_new:='if not private.gst_v520_authoritative_bound_context(p_tenant_id,''purchase_invoice_v484'',i.id) then perform private.v4_journal_create(p_tenant_id,i.location_id,i.invoice_date,''Purchase Invoice ''||i.invoice_number,''purchase_invoice_v484'',i.id,i.invoice_number,v_lines);end if;';
 if position(v_old in v_sql)>0 then execute replace(v_sql,v_old,v_new);elsif position(v_new in v_sql)=0 then raise exception 'Could not safely patch purchase_invoice_post_v484 journal guard';end if;
end $patch$;

create or replace function private.gst_purchase_invoice_quote_items_v520(p_tenant_id uuid,p_purchase_order_id uuid,p_items jsonb) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp as $$
declare x jsonb;poi public.purchase_order_items_v480%rowtype;gi public.goods_receipt_items_v484%rowtype;g public.goods_receipts_v484%rowtype;v_gi_id uuid;v_qty numeric;v_cost numeric;v_discount numeric;v_invoiced numeric;v_remaining numeric;v_seen uuid[]:='{}'::uuid[];v_out jsonb:='[]'::jsonb;
begin
 if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception 'At least one Purchasing V2 invoice line is required';end if;
 for x in select value from jsonb_array_elements(p_items) loop
  select * into poi from public.purchase_order_items_v480 where id=nullif(x->>'purchase_order_item_id','')::uuid and purchase_order_id=p_purchase_order_id;
  if not found then raise exception 'PO line not found for authoritative GST Purchase Invoice';end if;
  v_gi_id:=nullif(x->>'goods_receipt_item_id','')::uuid;
  if v_gi_id is null then raise exception 'Authoritative GST Purchase Invoice requires an explicit posted GRN line for every invoice line';end if;
  if v_gi_id=any(v_seen) then raise exception 'The same GRN line cannot appear twice in one authoritative GST Purchase Invoice';end if;v_seen:=array_append(v_seen,v_gi_id);
  select * into gi from public.goods_receipt_items_v484 where id=v_gi_id and purchase_order_item_id=poi.id;
  if not found then raise exception 'GRN line does not belong to the selected PO line';end if;
  select * into g from public.goods_receipts_v484 where id=gi.goods_receipt_id and purchase_order_id=p_purchase_order_id and status='posted';
  if not found then raise exception 'Authoritative GST Purchase Invoice requires a posted GRN line';end if;
  if g.tenant_id<>p_tenant_id or gi.variant_id<>poi.variant_id then raise exception 'GRN/PO line identity mismatch';end if;
  v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);v_cost:=coalesce(nullif(x->>'unit_cost','')::numeric,gi.unit_cost,poi.unit_cost,0);v_discount:=coalesce(nullif(x->>'discount_amount','')::numeric,0);
  if v_qty<=0 then raise exception 'Invoice quantity must be positive';end if;if v_cost<0 then raise exception 'Invoice unit cost cannot be negative';end if;if v_discount<0 then raise exception 'Invoice line discount cannot be negative';end if;if v_discount>round(v_qty*v_cost,4)+0.0001 then raise exception 'Invoice line discount exceeds line value';end if;
  select coalesce(sum(ii.quantity),0) into v_invoiced from public.purchase_invoice_items_v484 ii join public.purchase_invoices_v484 ih on ih.id=ii.purchase_invoice_id where ii.goods_receipt_item_id=gi.id and ih.status<>'void';
  v_remaining:=greatest(gi.accepted_quantity+gi.damaged_quantity-v_invoiced,0);if v_qty-v_remaining>0.000001 then raise exception 'Invoice quantity exceeds accepted/damaged GRN quantity remaining';end if;
  v_out:=v_out||jsonb_build_array(jsonb_build_object('variant_id',poi.variant_id,'quantity',v_qty,'unit_cost',v_cost,'discount_amount',v_discount));
 end loop;
 return v_out;
end $$;

create or replace function private.gst_purchase_invoice_bridge_items_v520(p_items jsonb,p_quote jsonb) returns jsonb
language plpgsql immutable security definer set search_path=public,private,pg_temp as $$
declare r record;v_qty numeric;v_bridge_cost numeric;v_out jsonb:='[]'::jsonb;
begin
 if jsonb_array_length(coalesce(p_items,'[]'::jsonb))<>jsonb_array_length(coalesce(p_quote->'lines','[]'::jsonb)) then raise exception 'GST Purchase Invoice bridge item count mismatch';end if;
 for r in
  select i.value as input_line,q.value as quote_line,i.ord
  from jsonb_array_elements(p_items) with ordinality i(value,ord)
  join jsonb_array_elements(p_quote->'lines') with ordinality q(value,ord) using(ord)
  order by i.ord
 loop
  v_qty:=coalesce((r.quote_line->>'quantity')::numeric,0);if v_qty<=0 then raise exception 'GST Purchase Invoice bridge quantity is invalid';end if;
  v_bridge_cost:=coalesce((r.quote_line->>'line_total')::numeric,0)/v_qty;
  v_out:=v_out||jsonb_build_array(r.input_line||jsonb_build_object('unit_cost',v_bridge_cost,'tax_rate',0,'discount_amount',0));
 end loop;
 return v_out;
end $$;

create or replace function private.gst_purchase_invoice_reconcile_v520(p_tenant_id uuid,p_purchase_invoice_id uuid,p_input_items jsonb,p_quote jsonb) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp as $$
declare h public.purchase_invoices_v484%rowtype;r record;ii public.purchase_invoice_items_v484%rowtype;gi public.goods_receipt_items_v484%rowtype;g public.goods_receipts_v484%rowtype;mv public.location_stock_movements%rowtype;v_item_type text;v_line_ids jsonb:='[]'::jsonb;v_costs jsonb:='[]'::jsonb;v_qty numeric;v_taxable numeric;v_placeholder numeric;v_delta numeric;v_branch_qty numeric;v_branch_cost numeric;v_branch_after numeric;v_global_qty numeric;v_global_cost numeric;v_global_after numeric;v_totals jsonb:=coalesce(p_quote->'totals','{}'::jsonb);v_rows integer;
begin
 select * into h from public.purchase_invoices_v484 where tenant_id=p_tenant_id and id=p_purchase_invoice_id and status='draft' for update;if not found then raise exception 'Draft Purchase Invoice source not found for GST reconciliation';end if;
 if jsonb_array_length(coalesce(p_input_items,'[]'::jsonb))<>jsonb_array_length(coalesce(p_quote->'lines','[]'::jsonb)) then raise exception 'GST Purchase Invoice reconciliation line count mismatch';end if;
 for r in
  select i.value as input_line,q.value as quote_line,i.ord
  from jsonb_array_elements(p_input_items) with ordinality i(value,ord)
  join jsonb_array_elements(p_quote->'lines') with ordinality q(value,ord) using(ord)
  order by i.ord
 loop
  select * into ii from public.purchase_invoice_items_v484 where purchase_invoice_id=h.id and purchase_order_item_id=(r.input_line->>'purchase_order_item_id')::uuid and goods_receipt_item_id=(r.input_line->>'goods_receipt_item_id')::uuid;
  if not found then raise exception 'Persisted Purchase Invoice line could not be linked to GST quote line %',r.ord;end if;
  v_qty:=coalesce((r.quote_line->>'quantity')::numeric,0);v_taxable:=coalesce((r.quote_line->>'taxable_value')::numeric,0);
  if abs(ii.quantity-v_qty)>0.000001 or ii.variant_id<>(r.quote_line->>'variant_id')::uuid then raise exception 'Persisted Purchase Invoice line differs from authoritative GST quote';end if;
  update public.purchase_invoice_items_v484 set unit_cost=coalesce((r.quote_line->>'unit_price')::numeric,0),discount_amount=coalesce((r.quote_line->>'discount')::numeric,0),line_subtotal=v_taxable,tax_rate=coalesce((r.quote_line->>'applied_gst_rate')::numeric,0),tax_amount=coalesce((r.quote_line->>'tax_amount')::numeric,0),line_total=coalesce((r.quote_line->>'line_total')::numeric,0) where id=ii.id;
  v_line_ids:=v_line_ids||jsonb_build_array(ii.id::text);
  select p.item_type into v_item_type from public.product_variants pv join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id where pv.tenant_id=p_tenant_id and pv.id=ii.variant_id;
  if v_item_type is null then raise exception 'Purchase Invoice product disappeared during GST reconciliation';end if;
  if v_item_type='stock' then
   select * into gi from public.goods_receipt_items_v484 where id=ii.goods_receipt_item_id;if not found then raise exception 'Stock Purchase Invoice line requires its GRN line';end if;
   select * into g from public.goods_receipts_v484 where id=gi.goods_receipt_id and tenant_id=p_tenant_id and location_id=h.location_id and status='posted';if not found then raise exception 'Stock Purchase Invoice GRN is not a posted receipt at the invoice location';end if;
   select * into mv from public.location_stock_movements m where m.tenant_id=p_tenant_id and m.location_id=h.location_id and m.variant_id=ii.variant_id and m.reference_type='goods_receipt' and m.reference_id=g.id and m.movement_type='grn' order by m.created_at,m.id limit 1;
   if mv.id is null then raise exception 'Authoritative GST Purchase Invoice cannot identify the GRN stock-cost basis';end if;
   perform 1 from public.location_stock_balances b where b.tenant_id=p_tenant_id and b.location_id=h.location_id and b.variant_id=ii.variant_id for update;
   if not found then raise exception 'Branch stock balance is missing for Purchase Invoice costing';end if;
   perform 1 from public.stock_balances b where b.tenant_id=p_tenant_id and b.variant_id=ii.variant_id for update;
   select b.quantity,b.average_cost into v_branch_qty,v_branch_cost from public.location_stock_balances b where b.tenant_id=p_tenant_id and b.location_id=h.location_id and b.variant_id=ii.variant_id;
   select coalesce(sum(b.quantity),0) into v_global_qty from public.stock_balances b where b.tenant_id=p_tenant_id and b.variant_id=ii.variant_id;
   select coalesce(pv.cost_price,0) into v_global_cost from public.product_variants pv where pv.tenant_id=p_tenant_id and pv.id=ii.variant_id for update;
   if exists(select 1 from public.location_stock_movements m where m.tenant_id=p_tenant_id and m.location_id=h.location_id and m.variant_id=ii.variant_id and m.id<>mv.id and m.created_at>=mv.created_at and m.quantity_delta< -0.000001) then raise exception 'Stock from GRN % has outbound movement before authoritative supplier invoicing; post/reconcile this invoice through a future cost-variance allocation path instead of rewriting COGS',g.grn_number;end if;
   if coalesce(v_branch_qty,0)+0.000001<v_qty or coalesce(v_global_qty,0)+0.000001<v_qty then raise exception 'Received stock quantity is no longer fully available for authoritative Purchase Invoice costing';end if;
   v_placeholder:=coalesce(mv.unit_cost,0);v_delta:=round(v_taxable-(v_qty*v_placeholder),6);
   if v_branch_qty<=0 or v_global_qty<=0 then raise exception 'Purchase Invoice costing requires positive on-hand stock';end if;
   v_branch_after:=round(((v_branch_qty*coalesce(v_branch_cost,0))+v_delta)/v_branch_qty,4);v_global_after:=round(((v_global_qty*coalesce(v_global_cost,0))+v_delta)/v_global_qty,4);
   if v_branch_after<0 or v_global_after<0 then raise exception 'Authoritative Purchase Invoice cost adjustment would make inventory cost negative';end if;
   update public.location_stock_balances set average_cost=v_branch_after,updated_at=now() where tenant_id=p_tenant_id and location_id=h.location_id and variant_id=ii.variant_id;
   update public.product_variants set cost_price=v_global_after,updated_at=now() where tenant_id=p_tenant_id and id=ii.variant_id;
   update public.location_stock_movements set metadata=jsonb_set(coalesce(metadata,'{}'::jsonb),'{gst_v520_invoice_cost_adjustments}',coalesce(metadata->'gst_v520_invoice_cost_adjustments','[]'::jsonb)||jsonb_build_array(jsonb_build_object('purchase_invoice_id',h.id,'purchase_invoice_item_id',ii.id,'supplier_invoice_number',h.supplier_invoice_number,'quantity',v_qty,'placeholder_unit_cost',v_placeholder,'gst_taxable_value',round(v_taxable,2),'cost_value_delta',v_delta,'branch_average_cost_after',v_branch_after,'global_average_cost_after',v_global_after)),true) where id=mv.id;
   get diagnostics v_rows=row_count;if v_rows<>1 then raise exception 'GRN stock-cost audit movement could not be updated';end if;
   v_costs:=v_costs||jsonb_build_array(jsonb_build_object('variant_id',ii.variant_id,'goods_receipt_id',g.id,'goods_receipt_item_id',gi.id,'quantity',v_qty,'placeholder_unit_cost',v_placeholder,'gst_taxable_value',round(v_taxable,2),'cost_value_delta',v_delta,'branch_quantity',v_branch_qty,'branch_average_cost_before',v_branch_cost,'branch_average_cost_after',v_branch_after,'global_quantity',v_global_qty,'global_average_cost_before',v_global_cost,'global_average_cost_after',v_global_after));
  end if;
 end loop;
 update public.purchase_invoices_v484 set subtotal=coalesce((v_totals->>'taxable_value')::numeric,0),discount_total=coalesce((v_totals->>'discount')::numeric,0),tax_total=coalesce((v_totals->>'tax_collected_total')::numeric,0),additional_charges=0,round_off=coalesce((v_totals->>'round_off')::numeric,0),grand_total=coalesce((v_totals->>'grand_total')::numeric,0),balance_due=greatest(coalesce((v_totals->>'grand_total')::numeric,0)-paid_total,0),updated_at=now() where id=h.id and tenant_id=p_tenant_id and status='draft';
 if not found then raise exception 'Purchase Invoice header disappeared during GST reconciliation';end if;
 return jsonb_build_object('line_ids',v_line_ids,'inventory_costs',v_costs);
end $$;

create or replace function public.gst_purchase_invoice_create_v520(p_tenant_id uuid,p_purchase_order_id uuid,p_supplier_invoice_number text,p_invoice_date date,p_due_date date,p_items jsonb,p_additional_charges numeric default 0,p_round_off numeric default 0,p_notes text default null,p_request_id text default null,p_supply_type text default null,p_place_of_supply_code text default null) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp as $$
declare po public.purchase_orders_v480%rowtype;v_supplier_invoice text:=nullif(trim(coalesce(p_supplier_invoice_number,'')),'');v_payload jsonb;v_req jsonb;v_supply text;v_quote_items jsonb;v_quote jsonb;v_bridge_items jsonb;v_create jsonb;v_post jsonb;v_recon jsonb;v_id uuid;v_internal_number text;v_snapshot uuid;v_journal uuid;v_document_number text;v_totals jsonb;v_response jsonb;
begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 if not(private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate') or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')) then raise exception 'GST calculation permission required';end if;
 select * into po from public.purchase_orders_v480 where tenant_id=p_tenant_id and id=p_purchase_order_id for update;if not found then raise exception 'Purchase Order not found';end if;
 perform private.purchasing_v484_access(p_tenant_id,po.location_id,true);
 if po.status not in('partially_received','received','closed') then raise exception 'Authoritative GST Purchase Invoice requires posted GRN quantities';end if;
 if v_supplier_invoice is null then raise exception 'Supplier invoice number is required';end if;
 if p_invoice_date is null then raise exception 'Supplier invoice date is required';end if;if p_due_date is not null and p_due_date<p_invoice_date then raise exception 'Due date cannot be before supplier invoice date';end if;
 if coalesce(p_additional_charges,0)<>0 then raise exception 'Additional charges are not enabled for authoritative GST Purchase Invoices until charge-level GST classification is configured';end if;
 if abs(coalesce(p_round_off,0))>1.000001 then raise exception 'Round-off cannot exceed 1.00 in either direction';end if;
 v_payload:=jsonb_build_object('purchase_order_id',p_purchase_order_id,'supplier_invoice_number',v_supplier_invoice,'invoice_date',p_invoice_date,'due_date',p_due_date,'items',coalesce(p_items,'[]'::jsonb),'additional_charges',coalesce(p_additional_charges,0),'round_off',coalesce(p_round_off,0),'notes',nullif(trim(coalesce(p_notes,'')),''),'supply_type',nullif(upper(trim(coalesce(p_supply_type,''))),''),'place_of_supply_code',nullif(trim(coalesce(p_place_of_supply_code,'')),''));
 v_req:=private.gst_request_begin_v520(p_tenant_id,p_request_id,'gst.purchase_invoice_v484.create.v520',v_payload);if coalesce((v_req->>'existing')::boolean,false) then return v_req->'response';end if;
 v_supply:=private.gst_purchase_supply_type_resolve_v520(p_tenant_id,po.supplier_id,p_invoice_date,p_supply_type);
 v_quote_items:=private.gst_purchase_invoice_quote_items_v520(p_tenant_id,p_purchase_order_id,p_items);
 v_quote:=public.gst_purchase_quote_v520(p_tenant_id,po.location_id,po.supplier_id,p_invoice_date,v_supply,p_place_of_supply_code,v_quote_items,0,p_round_off);
 if coalesce((v_quote->>'ready_for_compliance')::boolean,false) is not true then raise exception 'GST Purchase Invoice is not compliance-ready: %',coalesce(v_quote->'errors','[]'::jsonb)::text;end if;
 v_totals:=v_quote->'totals';if coalesce((v_totals->>'grand_total')::numeric,0)<=0 then raise exception 'Authoritative GST Purchase Invoice total must be positive';end if;
 v_bridge_items:=private.gst_purchase_invoice_bridge_items_v520(p_items,v_quote);
 perform private.gst_authoritative_context_enter_v520(p_tenant_id,'purchase_invoice_v484');
 v_create:=public.purchase_invoice_create_v489(p_tenant_id,p_purchase_order_id,v_supplier_invoice,p_invoice_date,p_due_date,v_bridge_items,0,p_round_off,p_notes);
 v_id:=nullif(v_create->>'purchase_invoice_id','')::uuid;if v_id is null then raise exception 'GST Purchase Invoice source could not be created';end if;perform private.gst_authoritative_context_bind_v520(v_id);
 select invoice_number into v_internal_number from public.purchase_invoices_v484 where tenant_id=p_tenant_id and id=v_id and status='draft' and lower(trim(supplier_invoice_number))=lower(v_supplier_invoice) for update;if v_internal_number is null then raise exception 'GST Purchase Invoice source identity changed during creation';end if;
 if exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='purchase_invoice_v484' and j.source_id=v_id and j.status='posted') then raise exception 'Legacy Purchase Invoice journal was created before authoritative posting';end if;
 if exists(select 1 from public.gst_legacy_document_markers_v520 m where m.tenant_id=p_tenant_id and m.source_type='purchase_invoice_v484' and m.source_id=v_id) then raise exception 'Legacy GST evidence was created before authoritative Purchase Invoice posting';end if;
 v_recon:=private.gst_purchase_invoice_reconcile_v520(p_tenant_id,v_id,p_items,v_quote);
 v_post:=public.purchase_invoice_post_v484(p_tenant_id,v_id);
 if coalesce(v_post->>'status','') not in('posted','part_paid','paid') then raise exception 'GST Purchase Invoice did not reach a posted state';end if;
 if exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='purchase_invoice_v484' and j.source_id=v_id and j.status='posted') then raise exception 'Legacy Purchase Invoice journal was created inside authoritative GST context';end if;
 if exists(select 1 from public.gst_legacy_document_markers_v520 m where m.tenant_id=p_tenant_id and m.source_type='purchase_invoice_v484' and m.source_id=v_id) then raise exception 'Legacy GST evidence was created inside authoritative GST context';end if;
 v_snapshot:=private.gst_snapshot_create_v520(p_tenant_id,'purchase_invoice_v484',v_id,v_internal_number,po.location_id,p_invoice_date,v_quote,v_recon->'line_ids');
 v_journal:=private.gst_authoritative_journal_post_v520(p_tenant_id,v_snapshot);
 select document_number into v_document_number from public.gst_document_snapshots_v520 where tenant_id=p_tenant_id and id=v_snapshot;if v_document_number is null or lower(trim(v_document_number))<>lower(v_supplier_invoice) then raise exception 'GST Purchase Invoice legal supplier invoice number was not captured';end if;
 v_response:=coalesce(v_post,'{}'::jsonb)||jsonb_build_object('success',true,'gst_engine',v_quote->>'engine','gst_status','POSTED','gst_supply_type',v_supply,'place_of_supply_code',v_quote->>'place_of_supply_code','purchase_invoice_id',v_id,'invoice_number',v_internal_number,'supplier_invoice_number',v_document_number,'grand_total',(v_totals->>'grand_total')::numeric,'taxable_total',(v_totals->>'taxable_value')::numeric,'discount_total',(v_totals->>'discount')::numeric,'tax_total',(v_totals->>'tax_collected_total')::numeric,'cgst',(v_totals->>'cgst')::numeric,'sgst',(v_totals->>'sgst')::numeric,'utgst',(v_totals->>'utgst')::numeric,'igst',(v_totals->>'igst')::numeric,'cess',(v_totals->>'cess')::numeric,'thq_rcm_tax_payable_total',coalesce((v_totals->>'thq_rcm_tax_payable_total')::numeric,0),'gst_snapshot_id',v_snapshot,'journal_id',v_journal,'inventory_costs',v_recon->'inventory_costs','gst_ready_for_compliance',true);
 v_response:=private.gst_request_complete_v520(p_tenant_id,p_request_id,'gst.purchase_invoice_v484.create.v520','purchase_invoice_v484',v_id,v_snapshot,v_journal,v_response);
 perform private.gst_authoritative_context_exit_v520();return v_response;
end $$;

revoke all on function private.gst_v520_authoritative_context_for_source(uuid,text,uuid) from public,anon,authenticated;
revoke all on function private.gst_v520_authoritative_bound_context(uuid,text,uuid) from public,anon,authenticated;
revoke all on function private.gst_purchase_invoice_quote_items_v520(uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function private.gst_purchase_invoice_bridge_items_v520(jsonb,jsonb) from public,anon,authenticated;
revoke all on function private.gst_purchase_invoice_reconcile_v520(uuid,uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function private.gst_v520_authoritative_context_for_source(uuid,text,uuid) to service_role;
grant execute on function private.gst_v520_authoritative_bound_context(uuid,text,uuid) to service_role;
grant execute on function private.gst_purchase_invoice_quote_items_v520(uuid,uuid,jsonb) to service_role;
grant execute on function private.gst_purchase_invoice_bridge_items_v520(jsonb,jsonb) to service_role;
grant execute on function private.gst_purchase_invoice_reconcile_v520(uuid,uuid,jsonb,jsonb) to service_role;
revoke all on function public.gst_purchase_invoice_create_v520(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,text,text) from public,anon;
grant execute on function public.gst_purchase_invoice_create_v520(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,text,text) to authenticated,service_role;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(243,'5.2.0-foundation','Atomic Authoritative GST Purchasing V2 Invoice','Adds the atomic v5.2 Purchasing V2 supplier-invoice path over posted GRN quantities. It preserves normal v5.1 direct journal + legacy_unverified evidence outside the private transaction context, strengthens bound-source suppression after the atomic source is known, blocks unclassified additional charges, uses the central GST engine as the only tax calculator, preserves supplier invoice legal identity, posts component GST/RCM accounting and supplier payable atomically, and adjusts stock acquisition cost only while linked GRN stock remains unconsumed so historical COGS is never silently rewritten. GRN-linked stock, supplier ledger, PO invoiced quantities, immutable GST snapshot and authoritative journal roll back together on failure.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;