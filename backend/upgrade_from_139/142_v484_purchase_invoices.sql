-- THQ ERP V4.8.4 — Purchase Invoice V2. Invoices post supplier/AP accounting but do not receive stock.
begin;

create sequence if not exists public.purchase_invoice_number_seq_v484;

create table if not exists public.purchase_invoices_v484(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  purchase_order_id uuid references public.purchase_orders_v480(id) on delete restrict,
  invoice_number text not null,
  supplier_invoice_number text,
  invoice_date date not null default current_date,
  due_date date,
  status text not null default 'draft' check(status in('draft','posted','part_paid','paid','void')),
  subtotal numeric not null default 0,
  tax_total numeric not null default 0,
  additional_charges numeric not null default 0,
  grand_total numeric not null default 0,
  paid_total numeric not null default 0,
  balance_due numeric not null default 0,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  posted_by uuid references auth.users(id) on delete set null,
  posted_at timestamptz,
  voided_by uuid references auth.users(id) on delete set null,
  voided_at timestamptz,
  void_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,invoice_number)
);
create unique index if not exists ux_purchase_invoices_v484_supplier_invoice on public.purchase_invoices_v484(tenant_id,supplier_id,lower(trim(supplier_invoice_number))) where supplier_invoice_number is not null and trim(supplier_invoice_number)<>'' and status<>'void';
create index if not exists idx_purchase_invoices_v484_lookup on public.purchase_invoices_v484(tenant_id,location_id,status,invoice_date desc);
create index if not exists idx_purchase_invoices_v484_supplier on public.purchase_invoices_v484(tenant_id,supplier_id,status,due_date);
alter table public.purchase_invoices_v484 enable row level security;
revoke all on public.purchase_invoices_v484 from anon,authenticated;

create table if not exists public.purchase_invoice_items_v484(
  id uuid primary key default gen_random_uuid(),
  purchase_invoice_id uuid not null references public.purchase_invoices_v484(id) on delete cascade,
  purchase_order_item_id uuid not null references public.purchase_order_items_v480(id) on delete restrict,
  goods_receipt_item_id uuid references public.goods_receipt_items_v484(id) on delete restrict,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  quantity numeric not null check(quantity>0),
  unit_cost numeric not null default 0 check(unit_cost>=0),
  tax_rate numeric not null default 0 check(tax_rate>=0),
  line_subtotal numeric not null default 0,
  tax_amount numeric not null default 0,
  line_total numeric not null default 0,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists idx_purchase_invoice_items_v484_variant on public.purchase_invoice_items_v484(variant_id,purchase_invoice_id);
create index if not exists idx_purchase_invoice_items_v484_po_item on public.purchase_invoice_items_v484(purchase_order_item_id,purchase_invoice_id);
create index if not exists idx_purchase_invoice_items_v484_grn_item on public.purchase_invoice_items_v484(goods_receipt_item_id,purchase_invoice_id);
alter table public.purchase_invoice_items_v484 enable row level security;
revoke all on public.purchase_invoice_items_v484 from anon,authenticated;

create or replace function public.purchase_invoice_create_v484(
  p_tenant_id uuid,p_purchase_order_id uuid,p_supplier_invoice_number text,p_invoice_date date,p_due_date date,p_items jsonb,
  p_additional_charges numeric default 0,p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare po public.purchase_orders_v480%rowtype;v_id uuid:=gen_random_uuid();v_no text;x jsonb;poi public.purchase_order_items_v480%rowtype;gi public.goods_receipt_items_v484%rowtype;v_qty numeric;v_cost numeric;v_rate numeric;v_line numeric;v_tax numeric;v_sub numeric:=0;v_tax_total numeric:=0;v_total numeric:=0;v_invoiced numeric;v_received_payable numeric;begin
  select * into po from public.purchase_orders_v480 where tenant_id=p_tenant_id and id=p_purchase_order_id for update;if not found then raise exception 'Purchase Order not found';end if;perform private.purchasing_v484_access(p_tenant_id,po.location_id,true);
  if po.status not in('partially_received','received','closed') then raise exception 'Purchase Invoice requires posted GRN quantities';end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'At least one invoice line is required';end if;
  if trim(coalesce(p_supplier_invoice_number,''))='' then raise exception 'Supplier invoice number is required';end if;
  v_no:='PINV-'||to_char(coalesce(p_invoice_date,current_date),'YYMMDD')||'-'||lpad(nextval('public.purchase_invoice_number_seq_v484')::text,6,'0');
  insert into public.purchase_invoices_v484(id,tenant_id,location_id,supplier_id,purchase_order_id,invoice_number,supplier_invoice_number,invoice_date,due_date,additional_charges,notes,created_by)
  values(v_id,p_tenant_id,po.location_id,po.supplier_id,po.id,v_no,trim(p_supplier_invoice_number),coalesce(p_invoice_date,current_date),p_due_date,greatest(coalesce(p_additional_charges,0),0),nullif(trim(coalesce(p_notes,'')),''),auth.uid());
  for x in select value from jsonb_array_elements(p_items) loop
    select * into poi from public.purchase_order_items_v480 where id=nullif(x->>'purchase_order_item_id','')::uuid and purchase_order_id=po.id for update;if not found then raise exception 'PO line not found';end if;
    v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);v_cost:=greatest(coalesce(nullif(x->>'unit_cost','')::numeric,poi.unit_cost,0),0);v_rate:=greatest(coalesce(nullif(x->>'tax_rate','')::numeric,poi.tax_rate,0),0);if v_qty<=0 then raise exception 'Invoice quantity must be positive';end if;
    if nullif(x->>'goods_receipt_item_id','') is not null then
      select * into gi from public.goods_receipt_items_v484 where id=(x->>'goods_receipt_item_id')::uuid and purchase_order_item_id=poi.id;if not found then raise exception 'GRN line does not belong to this PO line';end if;
      select coalesce(sum(ii.quantity),0) into v_invoiced from public.purchase_invoice_items_v484 ii join public.purchase_invoices_v484 ih on ih.id=ii.purchase_invoice_id where ii.goods_receipt_item_id=gi.id and ih.status<>'void';
      v_received_payable:=gi.accepted_quantity+gi.damaged_quantity;if v_qty+v_invoiced-v_received_payable>0.000001 then raise exception 'Invoice quantity exceeds accepted/damaged GRN quantity remaining';end if;
    else
      select coalesce(sum(ii.quantity),0) into v_invoiced from public.purchase_invoice_items_v484 ii join public.purchase_invoices_v484 ih on ih.id=ii.purchase_invoice_id where ii.purchase_order_item_id=poi.id and ih.status<>'void';
      v_received_payable:=coalesce(poi.accepted_quantity,0)+coalesce(poi.damaged_quantity,0);if v_qty+v_invoiced-v_received_payable>0.000001 then raise exception 'Invoice quantity exceeds received payable PO quantity remaining';end if;
    end if;
    v_line:=round(v_qty*v_cost,2);v_tax:=round(v_line*v_rate/100.0,2);v_sub:=v_sub+v_line;v_tax_total:=v_tax_total+v_tax;
    insert into public.purchase_invoice_items_v484(purchase_invoice_id,purchase_order_item_id,goods_receipt_item_id,variant_id,quantity,unit_cost,tax_rate,line_subtotal,tax_amount,line_total,note)
    values(v_id,poi.id,nullif(x->>'goods_receipt_item_id','')::uuid,poi.variant_id,v_qty,v_cost,v_rate,v_line,v_tax,v_line+v_tax,nullif(trim(coalesce(x->>'note','')),''));
  end loop;
  v_total:=round(v_sub+v_tax_total+greatest(coalesce(p_additional_charges,0),0),2);
  update public.purchase_invoices_v484 set subtotal=v_sub,tax_total=v_tax_total,grand_total=v_total,balance_due=v_total,updated_at=now() where id=v_id;
  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','purchase_invoice',v_id::text,'create');
  return jsonb_build_object('success',true,'purchase_invoice_id',v_id,'invoice_number',v_no,'supplier_invoice_number',trim(p_supplier_invoice_number),'status','draft','grand_total',v_total);
end$$;
grant execute on function public.purchase_invoice_create_v484(uuid,uuid,text,date,date,jsonb,numeric,text) to authenticated;

create or replace function public.purchase_invoice_post_v484(p_tenant_id uuid,p_purchase_invoice_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare i public.purchase_invoices_v484%rowtype;li record;v_lines jsonb:='[]'::jsonb;v_net numeric;begin
  select * into i from public.purchase_invoices_v484 where tenant_id=p_tenant_id and id=p_purchase_invoice_id for update;if not found then raise exception 'Purchase Invoice not found';end if;perform private.purchasing_v484_access(p_tenant_id,i.location_id,true);
  if i.status in('posted','part_paid','paid') then return jsonb_build_object('success',true,'purchase_invoice_id',i.id,'invoice_number',i.invoice_number,'status',i.status,'idempotent',true);end if;if i.status<>'draft' then raise exception 'Only Draft invoices can be posted';end if;
  if i.grand_total<=0 then raise exception 'Purchase Invoice total must be positive';end if;
  v_net:=greatest(i.subtotal+i.additional_charges,0);
  if v_net>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'inventory_asset'),'debit',v_net,'credit',0,'party_type','supplier','party_id',i.supplier_id,'description','Purchase invoice / inventory'));end if;
  if i.tax_total>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'input_gst'),'debit',i.tax_total,'credit',0,'description','Input GST'));end if;
  v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_payable'),'debit',0,'credit',i.grand_total,'party_type','supplier','party_id',i.supplier_id,'description','Supplier payable'));
  perform private.v4_journal_create(p_tenant_id,i.location_id,i.invoice_date,'Purchase Invoice '||i.invoice_number,'purchase_invoice_v484',i.id,i.invoice_number,v_lines);
  update public.purchase_invoices_v484 set status='posted',posted_by=auth.uid(),posted_at=now(),balance_due=grand_total-paid_total,updated_at=now() where id=i.id;
  for li in select purchase_order_item_id,sum(quantity) qty from public.purchase_invoice_items_v484 where purchase_invoice_id=i.id group by purchase_order_item_id loop update public.purchase_order_items_v480 set invoiced_quantity=invoiced_quantity+li.qty where id=li.purchase_order_item_id;end loop;
  perform private.thq_sync_bump_v480(p_tenant_id,'accounting','purchase_invoice',i.id::text,'post');
  return jsonb_build_object('success',true,'purchase_invoice_id',i.id,'invoice_number',i.invoice_number,'status','posted','grand_total',i.grand_total);
end$$;
grant execute on function public.purchase_invoice_post_v484(uuid,uuid) to authenticated;

create or replace function public.purchase_invoice_list_v484(p_tenant_id uuid,p_location_id uuid default null,p_status text default null,p_query text default '',p_limit integer default 500)
returns table(id uuid,invoice_number text,supplier_invoice_number text,invoice_date date,due_date date,status text,purchase_order_id uuid,order_number text,supplier_id uuid,supplier_name text,location_id uuid,location_name text,subtotal numeric,tax_total numeric,grand_total numeric,paid_total numeric,balance_due numeric,line_count bigint,created_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
 perform private.purchasing_v484_permission(p_tenant_id,false);
 return query select i.id,i.invoice_number,i.supplier_invoice_number,i.invoice_date,i.due_date,i.status,i.purchase_order_id,po.order_number,i.supplier_id,s.name,i.location_id,l.name,i.subtotal,i.tax_total,i.grand_total,i.paid_total,i.balance_due,count(ii.id),i.created_at
 from public.purchase_invoices_v484 i left join public.purchase_orders_v480 po on po.id=i.purchase_order_id join public.suppliers s on s.id=i.supplier_id join public.business_locations l on l.id=i.location_id left join public.purchase_invoice_items_v484 ii on ii.purchase_invoice_id=i.id left join public.product_variants pv on pv.id=ii.variant_id left join public.products p on p.id=pv.product_id
 where i.tenant_id=p_tenant_id and (p_location_id is null or i.location_id=p_location_id) and (p_status is null or p_status='' or i.status=p_status) and private.erp_document_scope_allowed(p_tenant_id,i.location_id,p_location_id,'view')
 and (trim(coalesce(p_query,''))='' or lower(i.invoice_number) like q or lower(coalesce(i.supplier_invoice_number,'')) like q or lower(coalesce(po.order_number,'')) like q or lower(s.name) like q or lower(coalesce(p.name,'')) like q or lower(coalesce(pv.sku,'')) like q)
 group by i.id,po.order_number,s.name,l.name order by i.created_at desc limit greatest(1,least(coalesce(p_limit,500),2000));
end$$;
grant execute on function public.purchase_invoice_list_v484(uuid,uuid,text,text,integer) to authenticated;

create or replace function public.purchase_invoice_detail_v484(p_tenant_id uuid,p_purchase_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_loc uuid;v jsonb;begin
 select location_id into v_loc from public.purchase_invoices_v484 where tenant_id=p_tenant_id and id=p_purchase_invoice_id;if v_loc is null then raise exception 'Purchase Invoice not found';end if;perform private.purchasing_v484_access(p_tenant_id,v_loc,false);
 select jsonb_build_object('invoice',to_jsonb(i)||jsonb_build_object('supplier_name',s.name,'location_name',l.name,'order_number',po.order_number),
 'items',coalesce((select jsonb_agg(to_jsonb(ii)||jsonb_build_object('product_name',p.name,'sku',pv.sku,'grn_number',g.grn_number) order by p.name) from public.purchase_invoice_items_v484 ii join public.product_variants pv on pv.id=ii.variant_id join public.products p on p.id=pv.product_id left join public.goods_receipt_items_v484 gi on gi.id=ii.goods_receipt_item_id left join public.goods_receipts_v484 g on g.id=gi.goods_receipt_id where ii.purchase_invoice_id=i.id),'[]'::jsonb)) into v
 from public.purchase_invoices_v484 i join public.suppliers s on s.id=i.supplier_id join public.business_locations l on l.id=i.location_id left join public.purchase_orders_v480 po on po.id=i.purchase_order_id where i.id=p_purchase_invoice_id and i.tenant_id=p_tenant_id;return v;
end$$;
grant execute on function public.purchase_invoice_detail_v484(uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(142,'4.8.4','Purchasing V2','Purchase Invoice V2 with GRN/PO quantity matching, no duplicate stock posting, and Accounts Payable/Input Tax accounting.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.4 migration 142 Purchase Invoices applied' as status;
