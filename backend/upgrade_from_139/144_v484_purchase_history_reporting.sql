-- THQ ERP V4.8.4 — Purchasing V2 reporting, PO progress and purchase price history.
begin;

create or replace function public.purchase_order_list_v484(p_tenant_id uuid,p_location_id uuid default null,p_status text default null,p_query text default '',p_limit integer default 500)
returns table(
 id uuid,order_number text,order_date date,expected_date date,status text,request_id uuid,request_number text,
 supplier_id uuid,supplier_name text,location_id uuid,location_name text,item_count bigint,ordered_quantity numeric,received_quantity numeric,
 accepted_quantity numeric,damaged_quantity numeric,rejected_quantity numeric,invoiced_quantity numeric,remaining_receive_quantity numeric,remaining_invoice_quantity numeric,
 subtotal numeric,tax_total numeric,grand_total numeric,created_at timestamptz
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
 perform private.purchasing_v484_permission(p_tenant_id,false);
 return query select po.id,po.order_number,po.order_date,po.expected_date,po.status,po.request_id,pr.request_number,po.supplier_id,s.name,po.location_id,l.name,count(i.id),
  coalesce(sum(i.quantity),0),coalesce(sum(i.received_quantity),0),coalesce(sum(i.accepted_quantity),0),coalesce(sum(i.damaged_quantity),0),coalesce(sum(i.rejected_quantity),0),coalesce(sum(i.invoiced_quantity),0),
  coalesce(sum(greatest(i.quantity-i.received_quantity,0)),0),coalesce(sum(greatest(i.accepted_quantity+i.damaged_quantity-i.invoiced_quantity,0)),0),po.subtotal,po.tax_total,po.grand_total,po.created_at
 from public.purchase_orders_v480 po join public.suppliers s on s.id=po.supplier_id join public.business_locations l on l.id=po.location_id left join public.purchase_requests_v484 pr on pr.id=po.request_id left join public.purchase_order_items_v480 i on i.purchase_order_id=po.id left join public.product_variants pv on pv.id=i.variant_id left join public.products p on p.id=pv.product_id
 where po.tenant_id=p_tenant_id and (p_location_id is null or po.location_id=p_location_id) and (p_status is null or p_status='' or po.status=p_status) and private.erp_document_scope_allowed(p_tenant_id,po.location_id,p_location_id,'view')
 and (trim(coalesce(p_query,''))='' or lower(po.order_number) like q or lower(coalesce(pr.request_number,'')) like q or lower(s.name) like q or lower(coalesce(p.name,'')) like q or lower(coalesce(pv.sku,'')) like q)
 group by po.id,pr.request_number,s.name,l.name order by po.created_at desc limit greatest(1,least(coalesce(p_limit,500),2000));
end$$;
grant execute on function public.purchase_order_list_v484(uuid,uuid,text,text,integer) to authenticated;

create or replace function public.purchase_order_detail_v484(p_tenant_id uuid,p_purchase_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_loc uuid;v jsonb;begin
 select location_id into v_loc from public.purchase_orders_v480 where tenant_id=p_tenant_id and id=p_purchase_order_id;if v_loc is null then raise exception 'Purchase Order not found';end if;perform private.purchasing_v484_access(p_tenant_id,v_loc,false);
 select jsonb_build_object(
  'order',to_jsonb(po)||jsonb_build_object('supplier_name',s.name,'location_name',l.name,'request_number',pr.request_number),
  'items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('product_name',p.name,'sku',pv.sku,'remaining_receive_quantity',greatest(i.quantity-i.received_quantity,0),'remaining_invoice_quantity',greatest(i.accepted_quantity+i.damaged_quantity-i.invoiced_quantity,0),'tracking_mode',private.v483_tracking_mode(p_tenant_id,i.variant_id)) order by p.name) from public.purchase_order_items_v480 i join public.product_variants pv on pv.id=i.variant_id join public.products p on p.id=pv.product_id where i.purchase_order_id=po.id),'[]'::jsonb),
  'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.id) from public.purchase_order_status_history_v480 h where h.purchase_order_id=po.id),'[]'::jsonb),
  'grns',coalesce((select jsonb_agg(to_jsonb(g) order by g.created_at desc) from public.goods_receipts_v484 g where g.purchase_order_id=po.id),'[]'::jsonb),
  'invoices',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from public.purchase_invoices_v484 i where i.purchase_order_id=po.id),'[]'::jsonb)
 ) into v from public.purchase_orders_v480 po join public.suppliers s on s.id=po.supplier_id join public.business_locations l on l.id=po.location_id left join public.purchase_requests_v484 pr on pr.id=po.request_id where po.id=p_purchase_order_id and po.tenant_id=p_tenant_id;return v;
end$$;
grant execute on function public.purchase_order_detail_v484(uuid,uuid) to authenticated;

create or replace function public.purchase_price_history_v484(
 p_tenant_id uuid,p_variant_id uuid default null,p_supplier_id uuid default null,p_location_id uuid default null,p_query text default '',p_limit integer default 1000
) returns table(
 source_type text,document_id uuid,document_number text,purchase_date date,location_id uuid,location_name text,supplier_id uuid,supplier_name text,
 variant_id uuid,product_name text,sku text,quantity numeric,unit_cost numeric,tax_rate numeric,line_total numeric
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
 perform private.purchasing_v484_permission(p_tenant_id,false);
 return query
 select * from (
   select 'purchase_invoice_v484'::text, ih.id,ih.invoice_number,ih.invoice_date,ih.location_id,l.name,ih.supplier_id,s.name,ii.variant_id,p.name,pv.sku,ii.quantity,ii.unit_cost,ii.tax_rate,ii.line_total
   from public.purchase_invoices_v484 ih join public.purchase_invoice_items_v484 ii on ii.purchase_invoice_id=ih.id join public.product_variants pv on pv.id=ii.variant_id join public.products p on p.id=pv.product_id join public.suppliers s on s.id=ih.supplier_id join public.business_locations l on l.id=ih.location_id
   where ih.tenant_id=p_tenant_id and ih.status in('posted','part_paid','paid')
   union all
   select 'legacy_purchase'::text,ph.id,ph.purchase_number,ph.purchase_date,o.location_id,l.name,ph.supplier_id,s.name,pi.variant_id,p.name,pv.sku,coalesce(pi.entered_quantity,pi.quantity),coalesce(pi.entered_unit_cost,pi.unit_cost),pi.tax_rate,pi.line_total
   from public.purchases ph join public.purchase_items pi on pi.purchase_id=ph.id join public.product_variants pv on pv.id=pi.variant_id join public.products p on p.id=pv.product_id join public.suppliers s on s.id=ph.supplier_id left join public.document_origins o on o.entity_type='purchase' and o.entity_id=ph.id and o.tenant_id=ph.tenant_id left join public.business_locations l on l.id=o.location_id
   where ph.tenant_id=p_tenant_id and coalesce(ph.status,'') not in('cancelled','void')
 ) h
 where (p_variant_id is null or h.variant_id=p_variant_id) and (p_supplier_id is null or h.supplier_id=p_supplier_id) and (p_location_id is null or h.location_id=p_location_id)
   and (h.location_id is null or private.erp_document_scope_allowed(p_tenant_id,h.location_id,p_location_id,'view'))
   and (trim(coalesce(p_query,''))='' or lower(h.document_number) like q or lower(h.supplier_name) like q or lower(h.product_name) like q or lower(coalesce(h.sku,'')) like q)
 order by h.purchase_date desc,h.document_number desc limit greatest(1,least(coalesce(p_limit,1000),5000));
end$$;
grant execute on function public.purchase_price_history_v484(uuid,uuid,uuid,uuid,text,integer) to authenticated;

create or replace function public.purchasing_dashboard_v484(p_tenant_id uuid,p_location_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_requests bigint;v_approval bigint;v_open_po bigint;v_partial bigint;v_unposted_grn bigint;v_open_invoices bigint;v_payable numeric;begin
 perform private.purchasing_v484_permission(p_tenant_id,false);
 select count(*) into v_requests from public.purchase_requests_v484 r where r.tenant_id=p_tenant_id and r.status in('draft','submitted') and (p_location_id is null or r.location_id=p_location_id) and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view');
 select count(*) into v_approval from public.purchase_orders_v480 p where p.tenant_id=p_tenant_id and p.status='submitted' and (p_location_id is null or p.location_id=p_location_id) and private.erp_document_scope_allowed(p_tenant_id,p.location_id,p_location_id,'view');
 select count(*) into v_open_po from public.purchase_orders_v480 p where p.tenant_id=p_tenant_id and p.status in('approved','ordered','partially_received') and (p_location_id is null or p.location_id=p_location_id) and private.erp_document_scope_allowed(p_tenant_id,p.location_id,p_location_id,'view');
 select count(*) into v_partial from public.purchase_orders_v480 p where p.tenant_id=p_tenant_id and p.status='partially_received' and (p_location_id is null or p.location_id=p_location_id) and private.erp_document_scope_allowed(p_tenant_id,p.location_id,p_location_id,'view');
 select count(*) into v_unposted_grn from public.goods_receipts_v484 g where g.tenant_id=p_tenant_id and g.status='draft' and (p_location_id is null or g.location_id=p_location_id) and private.erp_document_scope_allowed(p_tenant_id,g.location_id,p_location_id,'view');
 select count(*),coalesce(sum(balance_due),0) into v_open_invoices,v_payable from public.purchase_invoices_v484 i where i.tenant_id=p_tenant_id and i.status in('posted','part_paid') and (p_location_id is null or i.location_id=p_location_id) and private.erp_document_scope_allowed(p_tenant_id,i.location_id,p_location_id,'view');
 return jsonb_build_object('open_requests',v_requests,'po_awaiting_approval',v_approval,'open_purchase_orders',v_open_po,'partial_purchase_orders',v_partial,'draft_grns',v_unposted_grn,'open_supplier_invoices',v_open_invoices,'v2_payable_balance',v_payable);
end$$;
grant execute on function public.purchasing_dashboard_v484(uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(144,'4.8.4','Purchasing V2','PO progress reporting, Purchasing dashboard and unified V2 + legacy purchase price history.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.4 migration 144 purchasing history/reporting applied' as status;
