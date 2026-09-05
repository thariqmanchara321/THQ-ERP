create or replace function private.gst_purchase_supply_type_resolve_v520(p_tenant_id uuid,p_supplier_id uuid,p_document_date date,p_requested text default null) returns text language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_requested text:=nullif(upper(trim(coalesce(p_requested,''))),'');v_regtype text;v_country text;
begin
 select upper(trim(coalesce(s.country,'INDIA'))) into v_country from public.suppliers s where s.tenant_id=p_tenant_id and s.id=p_supplier_id and s.status='active';
 if not found then raise exception 'Active supplier not found';end if;
 select g.registration_type into v_regtype from public.gst_party_registrations_v520 g where g.tenant_id=p_tenant_id and g.party_type='supplier' and g.party_id=p_supplier_id and g.active and coalesce(p_document_date,current_date) between g.effective_from and coalesce(g.effective_to,'infinity'::date) order by g.effective_from desc,g.created_at desc limit 1;
 if v_requested is null then if v_country<>'INDIA' or v_regtype='export' then return 'IMPG';end if;if v_regtype in('registered','composition','sez') then return 'B2B';end if;return 'B2C';end if;
 if v_requested not in('B2B','B2C','IMPG') then if v_requested='IMPS' then raise exception 'IMPS service purchases are not enabled on the inventory Purchase source; use the dedicated service/expense path when released';end if;raise exception 'Invalid inward GST supply type %',v_requested;end if;
 if v_requested='B2B' and coalesce(v_regtype,'') not in('registered','composition','sez') then raise exception 'B2B purchase requires a normalized registered/composition/SEZ supplier GST profile';end if;
 if v_requested='B2C' and coalesce(v_regtype,'unregistered') in('registered','composition','sez') then raise exception 'Registered GST supplier cannot be classified as B2C';end if;
 if v_requested='IMPG' and not(v_country<>'INDIA' or v_regtype='export') then raise exception 'IMPG requires a foreign/import supplier profile';end if;
 return v_requested;
end $$;

create or replace function private.gst_purchase_bridge_v520(p_input_items jsonb,p_normalized_items jsonb,p_target_total numeric) returns jsonb language plpgsql immutable security definer set search_path=public,private,pg_temp as $$
declare x jsonb;v_out jsonb:='[]'::jsonb;v_raw numeric:=0;v_delta numeric;v_remaining numeric;v_gross numeric;v_discount numeric;v_take numeric;
begin
 if jsonb_typeof(coalesce(p_input_items,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_normalized_items,'[]'::jsonb))<>'array' then raise exception 'GST Purchase bridge requires item arrays';end if;
 if jsonb_array_length(p_input_items)<>jsonb_array_length(p_normalized_items) then raise exception 'GST Purchase bridge item count mismatch';end if;
 select coalesce(sum(round(coalesce(nullif(j->>'quantity','')::numeric,0)*coalesce(nullif(j->>'unit_cost','')::numeric,0),4)-coalesce(nullif(j->>'discount_amount','')::numeric,0)),0) into v_raw from jsonb_array_elements(p_normalized_items) j;
 v_delta:=round(coalesce(p_target_total,0)-v_raw,4);v_remaining:=greatest(-v_delta,0);
 for x in select value from jsonb_array_elements(p_input_items) loop
  v_gross:=round(coalesce(nullif(x->>'quantity','')::numeric,0)*coalesce(nullif(x->>'unit_cost','')::numeric,0),4);v_discount:=coalesce(nullif(x->>'discount_amount','')::numeric,0);
  if v_remaining>0 then v_take:=least(v_remaining,greatest(v_gross-v_discount,0));v_discount:=v_discount+v_take;v_remaining:=v_remaining-v_take;end if;
  v_out:=v_out||jsonb_build_array(x||jsonb_build_object('tax_rate',0,'discount_amount',round(v_discount,4)));
 end loop;
 if v_remaining>0.0001 then raise exception 'GST Purchase bridge cannot represent the target total';end if;
 return jsonb_build_object('items',v_out,'additional_charges',case when v_delta>0 then v_delta else 0 end,'raw_total',round(v_raw,4),'bridge_delta',v_delta);
end $$;

create or replace function private.gst_purchase_inventory_basis_capture_v520(p_tenant_id uuid,p_normalized_items jsonb) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare r record;v_cost numeric;v_qty numeric;v_item_type text;v_out jsonb:='[]'::jsonb;
begin
 if jsonb_typeof(coalesce(p_normalized_items,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_normalized_items,'[]'::jsonb))=0 then raise exception 'Purchase inventory basis requires items';end if;
 for r in select distinct (x.value->>'variant_id')::uuid as variant_id from jsonb_array_elements(p_normalized_items) x(value) order by 1 loop
  select pv.cost_price,p.item_type into v_cost,v_item_type from public.product_variants pv join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id where pv.tenant_id=p_tenant_id and pv.id=r.variant_id and pv.status='active' and p.status='active' for update of pv;
  if not found then raise exception 'Purchase item is invalid or inactive';end if;
  if v_item_type<>'stock' then raise exception 'Atomic GST Purchase currently supports stock items only; service/expense purchases require the dedicated source path';end if;
  select coalesce(sum(sb.quantity),0) into v_qty from public.stock_balances sb where sb.tenant_id=p_tenant_id and sb.variant_id=r.variant_id;
  v_out:=v_out||jsonb_build_array(jsonb_build_object('variant_id',r.variant_id,'prior_quantity',round(coalesce(v_qty,0),6),'prior_cost',round(coalesce(v_cost,0),6)));
 end loop;
 return v_out;
end $$;

create or replace function private.gst_purchase_reconcile_source_v520(p_tenant_id uuid,p_purchase_id uuid,p_location_id uuid,p_quote jsonb,p_inventory_basis jsonb,p_payment_reference text default null) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare qline jsonb;v_item public.purchase_items%rowtype;b jsonb;v_ids jsonb:='[]'::jsonb;v_costs jsonb:='[]'::jsonb;v_count integer;v_quote_count integer:=jsonb_array_length(coalesce(p_quote->'lines','[]'::jsonb));v_tax numeric:=coalesce((p_quote->'totals'->>'tax_collected_total')::numeric,0);v_sub numeric:=coalesce((p_quote->'totals'->>'subtotal')::numeric,0);v_disc numeric:=coalesce((p_quote->'totals'->>'discount')::numeric,0);v_taxable numeric:=coalesce((p_quote->'totals'->>'taxable_value')::numeric,0);v_round numeric:=coalesce((p_quote->'totals'->>'round_off')::numeric,0);v_grand numeric:=coalesce((p_quote->'totals'->>'grand_total')::numeric,0);v_supplier_gstin text:=nullif(p_quote->>'supplier_gstin','');v_prior_qty numeric;v_prior_cost numeric;v_after_qty numeric;v_qty numeric;v_asset_total numeric;v_receipt_unit_cost numeric;v_new_avg numeric;v_rows integer;
begin
 select count(*) into v_count from public.purchase_items pi where pi.tenant_id=p_tenant_id and pi.purchase_id=p_purchase_id;
 if v_count<>v_quote_count then raise exception 'Persisted Purchase line count does not match GST quote';end if;
 for qline in select value from jsonb_array_elements(p_quote->'lines') loop
  select * into v_item from public.purchase_items pi where pi.tenant_id=p_tenant_id and pi.purchase_id=p_purchase_id and pi.variant_id=(qline->>'variant_id')::uuid;
  if not found then raise exception 'Persisted Purchase line is missing for GST product %',qline->>'sku';end if;
  if coalesce(qline->>'supply_kind','')<>'goods' then raise exception 'Atomic GST Purchase inventory source requires a goods GST profile for %',qline->>'sku';end if;
  v_qty:=coalesce((qline->>'quantity')::numeric,0);
  if abs(v_item.quantity-v_qty)>0.000001 then raise exception 'Persisted Purchase quantity differs from GST quote for %',qline->>'sku';end if;
  if abs(v_item.unit_cost-coalesce((qline->>'unit_price')::numeric,0))>0.0001 then raise exception 'Persisted Purchase cost changed after GST quote for %; retry the transaction',qline->>'sku';end if;
  select value into b from jsonb_array_elements(coalesce(p_inventory_basis,'[]'::jsonb)) z(value) where z.value->>'variant_id'=qline->>'variant_id' limit 1;
  if b is null then raise exception 'Purchase inventory basis is missing for %',qline->>'sku';end if;
  v_prior_qty:=coalesce((b->>'prior_quantity')::numeric,0);v_prior_cost:=coalesce((b->>'prior_cost')::numeric,0);
  if v_prior_qty < -0.000001 then raise exception 'Negative pre-purchase stock basis is not supported for authoritative GST inventory costing';end if;
  select coalesce(sum(sb.quantity),0) into v_after_qty from public.stock_balances sb where sb.tenant_id=p_tenant_id and sb.variant_id=v_item.variant_id;
  if abs(v_after_qty-(v_prior_qty+v_qty))>0.000001 then raise exception 'Purchase stock quantity changed unexpectedly while authoritative GST costing was being finalized for %',qline->>'sku';end if;
  v_asset_total:=coalesce((qline->>'taxable_value')::numeric,0);v_receipt_unit_cost:=case when v_qty=0 then 0 else round(v_asset_total/v_qty,6) end;v_new_avg:=case when v_after_qty>0 then round(((v_prior_qty*v_prior_cost)+v_asset_total)/v_after_qty,4) else v_receipt_unit_cost end;
  update public.purchase_items set subtotal=round(v_qty*coalesce((qline->>'unit_price')::numeric,0),4),discount_amount=coalesce((qline->>'discount')::numeric,0),taxable_amount=v_asset_total,tax_rate=coalesce((qline->>'applied_gst_rate')::numeric,0),tax_amount=coalesce((qline->>'tax_amount')::numeric,0),line_total=coalesce((qline->>'line_total')::numeric,0) where id=v_item.id;
  update public.product_variants set cost_price=v_new_avg,updated_at=now() where tenant_id=p_tenant_id and id=v_item.variant_id;
  update public.stock_movements set unit_cost=v_receipt_unit_cost where tenant_id=p_tenant_id and reference_type='purchase' and reference_id=p_purchase_id and variant_id=v_item.variant_id and movement_type='purchase';get diagnostics v_rows=row_count;if v_rows<>1 then raise exception 'Authoritative Purchase expected exactly one core stock movement for %',qline->>'sku';end if;
  update public.location_stock_balances set average_cost=v_new_avg,updated_at=now() where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=v_item.variant_id;get diagnostics v_rows=row_count;if v_rows<>1 then raise exception 'Authoritative Purchase branch stock balance is missing for %',qline->>'sku';end if;
  update public.location_stock_movements set unit_cost=v_new_avg,metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('gst_v520_receipt_asset_total',round(v_asset_total,2),'gst_v520_receipt_unit_cost',v_receipt_unit_cost,'gst_v520_average_cost_after',v_new_avg) where tenant_id=p_tenant_id and location_id=p_location_id and reference_type='purchase' and reference_id=p_purchase_id and variant_id=v_item.variant_id and movement_type='purchase';get diagnostics v_rows=row_count;if v_rows<>1 then raise exception 'Authoritative Purchase expected exactly one branch stock movement for %',qline->>'sku';end if;
  v_ids:=v_ids||jsonb_build_array(v_item.id::text);v_costs:=v_costs||jsonb_build_array(jsonb_build_object('variant_id',v_item.variant_id,'prior_quantity',v_prior_qty,'prior_cost',v_prior_cost,'receipt_asset_total',round(v_asset_total,2),'receipt_unit_cost',v_receipt_unit_cost,'average_cost_after',v_new_avg));
 end loop;
 update public.purchases set subtotal=round(v_sub,4),discount_total=round(v_disc,4),taxable_total=round(v_taxable,4),tax_total=round(v_tax,4),additional_charges=0,round_off=round(v_round,2),grand_total=round(v_grand,2),supplier_tax_number=coalesce(v_supplier_gstin,supplier_tax_number),updated_at=now() where tenant_id=p_tenant_id and id=p_purchase_id and status='posted';
 if not found then raise exception 'Posted Purchase source disappeared during GST reconciliation';end if;
 if nullif(trim(coalesce(p_payment_reference,'')),'') is not null then update public.purchase_payments set reference_number=trim(p_payment_reference) where tenant_id=p_tenant_id and purchase_id=p_purchase_id;end if;
 return jsonb_build_object('line_ids',v_ids,'inventory_costs',v_costs);
end $$;

create or replace function public.gst_purchase_create_v520(p_tenant_id uuid,p_supplier_id uuid,p_supplier_invoice_number text,p_purchase_date date,p_due_date date,p_items jsonb,p_additional_charges numeric default 0,p_round_off numeric default 0,p_initial_payment numeric default 0,p_payment_method text default 'cash',p_payment_reference text default null,p_notes text default null,p_location_id uuid default null,p_device_id uuid default null,p_request_id text default null,p_supply_type text default null,p_place_of_supply_code text default null) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_req_payload jsonb;v_req_state jsonb;v_old_req jsonb;v_supply text;v_normalized jsonb;v_quote jsonb;v_bridge jsonb;v_basis jsonb;v_recon jsonb;v_source jsonb;v_purchase_id uuid;v_purchase_number text;v_snapshot uuid;v_journal uuid;v_document_number text;v_response jsonb;v_totals jsonb;v_supplier_invoice text:=nullif(trim(coalesce(p_supplier_invoice_number,'')),'');
begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 if not(private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'purchases.manage')) then raise exception 'Purchases permission required';end if;
 if not(private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate') or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')) then raise exception 'GST calculation permission required';end if;
 if p_location_id is null then raise exception 'Business location is required';end if;
 if v_supplier_invoice is null then raise exception 'Supplier invoice number is required for an authoritative GST Purchase';end if;
 if coalesce(p_additional_charges,0)<>0 then raise exception 'Additional charges are not enabled for authoritative GST Purchases until charge-level GST classification is configured';end if;
 if p_purchase_date is null then raise exception 'Purchase date is required';end if;if p_due_date is not null and p_due_date<p_purchase_date then raise exception 'Due date cannot be before purchase date';end if;if coalesce(p_initial_payment,0)<0 then raise exception 'Initial payment cannot be negative';end if;
 v_req_payload:=jsonb_build_object('supplier_id',p_supplier_id,'supplier_invoice_number',v_supplier_invoice,'purchase_date',p_purchase_date,'due_date',p_due_date,'items',coalesce(p_items,'[]'::jsonb),'additional_charges',coalesce(p_additional_charges,0),'round_off',coalesce(p_round_off,0),'initial_payment',coalesce(p_initial_payment,0),'payment_method',lower(trim(coalesce(p_payment_method,''))),'payment_reference',nullif(trim(coalesce(p_payment_reference,'')),''),'notes',nullif(trim(coalesce(p_notes,'')),''),'location_id',p_location_id,'device_id',p_device_id,'supply_type',nullif(upper(trim(coalesce(p_supply_type,''))),''),'place_of_supply_code',nullif(trim(coalesce(p_place_of_supply_code,'')),''));
 v_req_state:=private.gst_request_begin_v520(p_tenant_id,p_request_id,'gst.purchase.create.v520',v_req_payload);if coalesce((v_req_state->>'existing')::boolean,false) then return v_req_state->'response';end if;
 v_old_req:=private.v47_request_existing(p_tenant_id,p_request_id,'purchase.create');if v_old_req is not null then raise exception 'Request ID is already used by the legacy Purchase path';end if;
 v_normalized:=private.v481_normalize_items(p_tenant_id,p_items,'purchase');v_basis:=private.gst_purchase_inventory_basis_capture_v520(p_tenant_id,v_normalized);v_supply:=private.gst_purchase_supply_type_resolve_v520(p_tenant_id,p_supplier_id,p_purchase_date,p_supply_type);
 v_quote:=public.gst_purchase_quote_v520(p_tenant_id,p_location_id,p_supplier_id,p_purchase_date,v_supply,p_place_of_supply_code,v_normalized,0,p_round_off);
 if coalesce((v_quote->>'ready_for_compliance')::boolean,false) is not true then raise exception 'GST Purchase is not compliance-ready: %',coalesce(v_quote->'errors','[]'::jsonb)::text;end if;
 v_totals:=v_quote->'totals';if coalesce(p_initial_payment,0)>coalesce((v_totals->>'grand_total')::numeric,0)+0.005 then raise exception 'Payment cannot exceed GST Purchase total';end if;
 v_bridge:=private.gst_purchase_bridge_v520(p_items,v_normalized,(v_totals->>'grand_total')::numeric);
 perform private.gst_authoritative_context_enter_v520(p_tenant_id,'purchase');
 v_source:=public.purchases_create_v483(p_tenant_id,p_supplier_id,v_supplier_invoice,p_purchase_date,p_due_date,v_bridge->'items',(v_bridge->>'additional_charges')::numeric,p_initial_payment,p_payment_method,p_notes,p_location_id,p_device_id,p_request_id);
 v_purchase_id:=nullif(v_source->>'purchase_id','')::uuid;if v_purchase_id is null then raise exception 'GST Purchase source could not be resolved';end if;perform private.gst_authoritative_context_bind_v520(v_purchase_id);
 select p.purchase_number into v_purchase_number from public.purchases p where p.tenant_id=p_tenant_id and p.id=v_purchase_id and p.status='posted' and lower(trim(coalesce(p.supplier_invoice_number,'')))=lower(v_supplier_invoice) for update;
 if v_purchase_number is null then raise exception 'GST Purchase source is not posted or supplier invoice identity changed';end if;
 if exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='purchase' and j.source_id=v_purchase_id and j.status='posted') then raise exception 'Legacy Purchase journal was created inside authoritative GST context';end if;
 if exists(select 1 from public.gst_legacy_document_markers_v520 m where m.tenant_id=p_tenant_id and m.source_type='purchase' and m.source_id=v_purchase_id) then raise exception 'Legacy GST evidence was created inside authoritative GST context';end if;
 if exists(select 1 from public.journal_entries j join public.purchase_payments pp on pp.id=j.source_id and pp.purchase_id=v_purchase_id where j.tenant_id=p_tenant_id and j.source_type='purchase_payment' and j.status='posted') then raise exception 'Standalone initial Purchase payment journal was created inside authoritative GST context';end if;
 v_recon:=private.gst_purchase_reconcile_source_v520(p_tenant_id,v_purchase_id,p_location_id,v_quote,v_basis,p_payment_reference);
 v_snapshot:=private.gst_snapshot_create_v520(p_tenant_id,'purchase',v_purchase_id,v_purchase_number,p_location_id,p_purchase_date,v_quote,v_recon->'line_ids');v_journal:=private.gst_authoritative_journal_post_v520(p_tenant_id,v_snapshot);
 select s.document_number into v_document_number from public.gst_document_snapshots_v520 s where s.id=v_snapshot and s.tenant_id=p_tenant_id;
 if v_document_number is null or lower(trim(v_document_number))<>lower(v_supplier_invoice) then raise exception 'GST Purchase legal supplier invoice number was not captured';end if;
 v_response:=coalesce(v_source,'{}'::jsonb)||jsonb_build_object('success',true,'gst_engine',v_quote->>'engine','gst_status','POSTED','gst_supply_type',v_supply,'place_of_supply_code',v_quote->>'place_of_supply_code','purchase_id',v_purchase_id,'purchase_number',v_purchase_number,'supplier_invoice_number',v_document_number,'grand_total',(v_totals->>'grand_total')::numeric,'taxable_total',(v_totals->>'taxable_value')::numeric,'tax_total',(v_totals->>'tax_collected_total')::numeric,'cgst',(v_totals->>'cgst')::numeric,'sgst',(v_totals->>'sgst')::numeric,'utgst',(v_totals->>'utgst')::numeric,'igst',(v_totals->>'igst')::numeric,'cess',(v_totals->>'cess')::numeric,'thq_rcm_tax_payable_total',coalesce((v_totals->>'thq_rcm_tax_payable_total')::numeric,0),'gst_snapshot_id',v_snapshot,'journal_id',v_journal,'inventory_costs',v_recon->'inventory_costs','gst_ready_for_compliance',true);
 v_response:=private.gst_request_complete_v520(p_tenant_id,p_request_id,'gst.purchase.create.v520','purchase',v_purchase_id,v_snapshot,v_journal,v_response);
 update public.transaction_requests_v47 set response=v_response where tenant_id=p_tenant_id and request_id=trim(p_request_id) and operation='purchase.create';
 perform private.gst_authoritative_context_exit_v520();return v_response;
end $$;

revoke all on function private.gst_purchase_supply_type_resolve_v520(uuid,uuid,date,text) from public,anon,authenticated;
revoke all on function private.gst_purchase_bridge_v520(jsonb,jsonb,numeric) from public,anon,authenticated;
revoke all on function private.gst_purchase_inventory_basis_capture_v520(uuid,jsonb) from public,anon,authenticated;
revoke all on function private.gst_purchase_reconcile_source_v520(uuid,uuid,uuid,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function private.gst_purchase_supply_type_resolve_v520(uuid,uuid,date,text) to service_role;
grant execute on function private.gst_purchase_bridge_v520(jsonb,jsonb,numeric) to service_role;
grant execute on function private.gst_purchase_inventory_basis_capture_v520(uuid,jsonb) to service_role;
grant execute on function private.gst_purchase_reconcile_source_v520(uuid,uuid,uuid,jsonb,jsonb,text) to service_role;
revoke all on function public.gst_purchase_create_v520(uuid,uuid,text,date,date,jsonb,numeric,numeric,numeric,text,text,text,uuid,uuid,text,text,text) from public,anon;
grant execute on function public.gst_purchase_create_v520(uuid,uuid,text,date,date,jsonb,numeric,numeric,numeric,text,text,text,uuid,uuid,text,text,text) to authenticated,service_role;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(242,'5.2.0-foundation','Atomic Authoritative GST Purchase','Adds the v5.2 atomic inventory Purchase endpoint. The Purchase source, immutable GST snapshot, component journal, supplier payable/payment split, RCM liability and inventory costing commit as one transaction. Central GST is the only tax calculator; recoverable supplier GST is excluded from inventory cost, line discounts reduce inventory basis, and RCM tax remains a THQ liability/pending-input component rather than supplier payable. Legacy generic accounting/evidence remains untouched for v5.1 and is suppressed only inside the private matching authoritative transaction context. Additional charges and service purchases remain blocked until their dedicated GST-classified source paths are introduced.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;