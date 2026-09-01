-- THQ ERP v5.0.0 — CRM, supplier quotations/performance and smart reorder intelligence.
begin;

create table if not exists public.customer_groups_v500(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  description text,
  discount_percent numeric not null default 0 check(discount_percent between 0 and 100),
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(tenant_id,name)
);

create table if not exists public.customer_crm_profiles_v500(
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  group_id uuid references public.customer_groups_v500(id) on delete set null,
  salesperson_user_id uuid references auth.users(id) on delete set null,
  birthday date,
  anniversary date,
  loyalty_points numeric not null default 0,
  notes text,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key(tenant_id,customer_id)
);

create table if not exists public.customer_loyalty_ledger_v500(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  points numeric not null,
  source_type text not null,
  source_id uuid,
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create sequence if not exists public.purchase_quotation_number_seq_v500;
create table if not exists public.purchase_quotations_v500(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  request_id uuid references public.purchase_requests_v484(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  quotation_number text not null,
  supplier_quote_reference text,
  quote_date date not null default current_date,
  valid_until date,
  expected_delivery_date date,
  payment_terms text,
  subtotal numeric not null default 0,
  tax_total numeric not null default 0,
  grand_total numeric not null default 0,
  status text not null default 'received' check(status in('draft','received','selected','rejected','expired','converted')),
  notes text,
  converted_purchase_order_id uuid references public.purchase_orders_v480(id) on delete set null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,quotation_number)
);

create table if not exists public.purchase_quotation_items_v500(
  id uuid primary key default gen_random_uuid(),
  quotation_id uuid not null references public.purchase_quotations_v500(id) on delete cascade,
  request_item_id uuid references public.purchase_request_items_v484(id) on delete set null,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  quantity numeric not null check(quantity>0),
  unit_cost numeric not null default 0 check(unit_cost>=0),
  tax_rate numeric not null default 0 check(tax_rate>=0),
  line_total numeric not null default 0,
  note text
);

alter table public.customer_groups_v500 enable row level security;
alter table public.customer_crm_profiles_v500 enable row level security;
alter table public.customer_loyalty_ledger_v500 enable row level security;
alter table public.purchase_quotations_v500 enable row level security;
alter table public.purchase_quotation_items_v500 enable row level security;
revoke all on public.customer_groups_v500,public.customer_crm_profiles_v500,public.customer_loyalty_ledger_v500,public.purchase_quotations_v500,public.purchase_quotation_items_v500 from anon,authenticated;

create or replace function private.v500_customer_manage_access(p_tenant_id uuid)
returns void language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'customers.manage') and not private.erp_has_permission(p_tenant_id,'sales.manage') then raise exception 'Customer management permission required';end if;
end $$;
revoke all on function private.v500_customer_manage_access(uuid) from public;

create or replace function public.customer_groups_list_v500(p_tenant_id uuid)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$ declare r record;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  for r in select * from public.customer_groups_v500 where tenant_id=p_tenant_id order by active desc,name loop return next to_jsonb(r);end loop;return;
end $$;
grant execute on function public.customer_groups_list_v500(uuid) to authenticated;

create or replace function public.customer_group_save_v500(p_tenant_id uuid,p_group_id uuid,p_name text,p_description text,p_discount_percent numeric,p_active boolean)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$ declare v uuid;begin
  perform private.v500_customer_manage_access(p_tenant_id);
  if trim(coalesce(p_name,''))='' then raise exception 'Group name is required';end if;if coalesce(p_discount_percent,0)<0 or coalesce(p_discount_percent,0)>100 then raise exception 'Invalid group discount';end if;
  if p_group_id is null then insert into public.customer_groups_v500(tenant_id,name,description,discount_percent,active,created_by) values(p_tenant_id,trim(p_name),nullif(trim(coalesce(p_description,'')),''),coalesce(p_discount_percent,0),coalesce(p_active,true),auth.uid()) returning id into v;
  else update public.customer_groups_v500 set name=trim(p_name),description=nullif(trim(coalesce(p_description,'')),''),discount_percent=coalesce(p_discount_percent,0),active=coalesce(p_active,true) where id=p_group_id and tenant_id=p_tenant_id returning id into v;end if;
  if v is null then raise exception 'Customer group not found';end if;return v;
end $$;
grant execute on function public.customer_group_save_v500(uuid,uuid,text,text,numeric,boolean) to authenticated;

create or replace function public.customer_crm_profile_v500(p_tenant_id uuid,p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare c jsonb;crm jsonb;v_sales numeric:=0;v_returns numeric:=0;v_paid numeric:=0;v_outstanding numeric:=0;v_loans_given numeric:=0;v_loans_taken numeric:=0;v_last_sale date;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select to_jsonb(x) into c from public.customers x where x.tenant_id=p_tenant_id and x.id=p_customer_id;if c is null then raise exception 'Customer not found';end if;
  select jsonb_build_object('group_id',p.group_id,'group_name',g.name,'group_discount_percent',coalesce(g.discount_percent,0),'salesperson_user_id',p.salesperson_user_id,'birthday',p.birthday,'anniversary',p.anniversary,'loyalty_points',coalesce(p.loyalty_points,0),'notes',p.notes) into crm from public.customer_crm_profiles_v500 p left join public.customer_groups_v500 g on g.id=p.group_id where p.tenant_id=p_tenant_id and p.customer_id=p_customer_id;
  select coalesce(sum(s.grand_total),0),max(s.sale_date) into v_sales,v_last_sale from public.sales s where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') not in('void','cancelled');
  select coalesce(sum(r.grand_total),0) into v_returns from public.sales_returns r join public.sales s on s.id=r.sale_id where r.tenant_id=p_tenant_id and s.customer_id=p_customer_id and r.refund_status<>'waived';
  select coalesce(sum(sp.amount),0) into v_paid from public.sale_payments sp join public.sales s on s.id=sp.sale_id where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id;
  v_outstanding:=greatest(v_sales-v_returns-v_paid,0);
  if to_regclass('public.loan_accounts_v490') is not null then
    select coalesce(sum(principal_outstanding+interest_outstanding+penalty_outstanding),0) into v_loans_given from public.loan_accounts_v490 where tenant_id=p_tenant_id and client_id=p_customer_id and direction='given' and status in('active','defaulted');
    select coalesce(sum(principal_outstanding+interest_outstanding+penalty_outstanding),0) into v_loans_taken from public.loan_accounts_v490 where tenant_id=p_tenant_id and client_id=p_customer_id and direction='taken' and status in('active','defaulted');
  end if;
  return jsonb_build_object('customer',c,'crm',coalesce(crm,'{}'::jsonb),'summary',jsonb_build_object('gross_sales',v_sales,'returns',v_returns,'payments',v_paid,'outstanding_sales',v_outstanding,'loan_receivable',v_loans_given,'loan_payable',v_loans_taken,'last_sale_date',v_last_sale));
end $$;
grant execute on function public.customer_crm_profile_v500(uuid,uuid) to authenticated;

create or replace function public.customer_crm_save_v500(p_tenant_id uuid,p_customer_id uuid,p_group_id uuid,p_salesperson_user_id uuid,p_birthday date,p_anniversary date,p_notes text)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
  perform private.v500_customer_manage_access(p_tenant_id);if not exists(select 1 from public.customers where tenant_id=p_tenant_id and id=p_customer_id) then raise exception 'Customer not found';end if;
  if p_group_id is not null and not exists(select 1 from public.customer_groups_v500 where tenant_id=p_tenant_id and id=p_group_id and active) then raise exception 'Customer group not found';end if;
  insert into public.customer_crm_profiles_v500(tenant_id,customer_id,group_id,salesperson_user_id,birthday,anniversary,notes,updated_by,updated_at) values(p_tenant_id,p_customer_id,p_group_id,p_salesperson_user_id,p_birthday,p_anniversary,nullif(trim(coalesce(p_notes,'')),''),auth.uid(),now()) on conflict(tenant_id,customer_id) do update set group_id=excluded.group_id,salesperson_user_id=excluded.salesperson_user_id,birthday=excluded.birthday,anniversary=excluded.anniversary,notes=excluded.notes,updated_by=auth.uid(),updated_at=now();
end $$;
grant execute on function public.customer_crm_save_v500(uuid,uuid,uuid,uuid,date,date,text) to authenticated;

create or replace function public.customer_loyalty_adjust_v500(p_tenant_id uuid,p_customer_id uuid,p_points numeric,p_source_type text,p_source_id uuid,p_note text)
returns numeric language plpgsql security definer set search_path=public,private,pg_temp as $$ declare v numeric;begin
  perform private.v500_customer_manage_access(p_tenant_id);if coalesce(p_points,0)=0 then raise exception 'Points adjustment cannot be zero';end if;
  insert into public.customer_crm_profiles_v500(tenant_id,customer_id,loyalty_points,updated_by) values(p_tenant_id,p_customer_id,0,auth.uid()) on conflict(tenant_id,customer_id) do nothing;
  update public.customer_crm_profiles_v500 set loyalty_points=greatest(loyalty_points+p_points,0),updated_by=auth.uid(),updated_at=now() where tenant_id=p_tenant_id and customer_id=p_customer_id returning loyalty_points into v;
  insert into public.customer_loyalty_ledger_v500(tenant_id,customer_id,points,source_type,source_id,note,created_by) values(p_tenant_id,p_customer_id,p_points,coalesce(nullif(trim(p_source_type),''),'manual'),p_source_id,nullif(trim(coalesce(p_note,'')),''),auth.uid());return v;
end $$;
grant execute on function public.customer_loyalty_adjust_v500(uuid,uuid,numeric,text,uuid,text) to authenticated;

create or replace function public.purchase_quotation_save_v500(p_tenant_id uuid,p_quotation_id uuid,p_request_id uuid,p_location_id uuid,p_supplier_id uuid,p_supplier_quote_reference text,p_quote_date date,p_valid_until date,p_expected_delivery_date date,p_payment_terms text,p_items jsonb,p_notes text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;v_no text;x jsonb;v_qty numeric;v_cost numeric;v_tax numeric;v_sub numeric:=0;v_tax_total numeric:=0;v_line numeric;begin
  perform private.purchasing_v484_access(p_tenant_id,p_location_id,true);
  if not exists(select 1 from public.suppliers where id=p_supplier_id and tenant_id=p_tenant_id and coalesce(status,'active')='active') then raise exception 'Active supplier not found';end if;
  if p_request_id is not null and not exists(select 1 from public.purchase_requests_v484 where id=p_request_id and tenant_id=p_tenant_id and location_id=p_location_id and status in('submitted','approved')) then raise exception 'Eligible purchase request not found';end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Quotation items are required';end if;
  if p_quotation_id is null then v_id:=gen_random_uuid();v_no:='PQT-'||to_char(coalesce(p_quote_date,current_date),'YYMMDD')||'-'||lpad(nextval('public.purchase_quotation_number_seq_v500')::text,6,'0');insert into public.purchase_quotations_v500(id,tenant_id,request_id,location_id,supplier_id,quotation_number,supplier_quote_reference,quote_date,valid_until,expected_delivery_date,payment_terms,notes,created_by) values(v_id,p_tenant_id,p_request_id,p_location_id,p_supplier_id,v_no,nullif(trim(coalesce(p_supplier_quote_reference,'')),''),coalesce(p_quote_date,current_date),p_valid_until,p_expected_delivery_date,nullif(trim(coalesce(p_payment_terms,'')),''),nullif(trim(coalesce(p_notes,'')),''),auth.uid());
  else select id,quotation_number into v_id,v_no from public.purchase_quotations_v500 where id=p_quotation_id and tenant_id=p_tenant_id and status in('draft','received') for update;if v_id is null then raise exception 'Editable quotation not found';end if;delete from public.purchase_quotation_items_v500 where quotation_id=v_id;update public.purchase_quotations_v500 set request_id=p_request_id,location_id=p_location_id,supplier_id=p_supplier_id,supplier_quote_reference=nullif(trim(coalesce(p_supplier_quote_reference,'')),''),quote_date=coalesce(p_quote_date,current_date),valid_until=p_valid_until,expected_delivery_date=p_expected_delivery_date,payment_terms=nullif(trim(coalesce(p_payment_terms,'')),''),notes=nullif(trim(coalesce(p_notes,'')),''),updated_at=now() where id=v_id;end if;
  for x in select value from jsonb_array_elements(p_items) loop v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);v_cost:=greatest(coalesce(nullif(x->>'unit_cost','')::numeric,0),0);v_tax:=greatest(coalesce(nullif(x->>'tax_rate','')::numeric,0),0);if v_qty<=0 or nullif(x->>'variant_id','') is null then raise exception 'Invalid quotation item';end if;v_line:=round(v_qty*v_cost,2);v_sub:=v_sub+v_line;v_tax_total:=v_tax_total+round(v_line*v_tax/100,2);insert into public.purchase_quotation_items_v500(quotation_id,request_item_id,variant_id,quantity,unit_cost,tax_rate,line_total,note) values(v_id,nullif(x->>'request_item_id','')::uuid,(x->>'variant_id')::uuid,v_qty,v_cost,v_tax,round(v_line+v_line*v_tax/100,2),nullif(trim(coalesce(x->>'note','')),''));end loop;
  update public.purchase_quotations_v500 set subtotal=v_sub,tax_total=v_tax_total,grand_total=round(v_sub+v_tax_total,2),status='received',updated_at=now() where id=v_id;return jsonb_build_object('quotation_id',v_id,'quotation_number',v_no,'grand_total',round(v_sub+v_tax_total,2));
end $$;
grant execute on function public.purchase_quotation_save_v500(uuid,uuid,uuid,uuid,uuid,text,date,date,date,text,jsonb,text) to authenticated;

create or replace function public.purchase_quotations_list_v500(p_tenant_id uuid,p_request_id uuid default null,p_status text default null,p_query text default '')
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$ declare r record;q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin perform private.purchasing_v484_permission(p_tenant_id,false);
  for r in select qh.*,s.name supplier_name,s.phone supplier_phone,pr.request_number,po.order_number converted_order_number from public.purchase_quotations_v500 qh join public.suppliers s on s.id=qh.supplier_id left join public.purchase_requests_v484 pr on pr.id=qh.request_id left join public.purchase_orders_v480 po on po.id=qh.converted_purchase_order_id where qh.tenant_id=p_tenant_id and (p_request_id is null or qh.request_id=p_request_id) and (p_status is null or qh.status=p_status) and (trim(coalesce(p_query,''))='' or lower(qh.quotation_number) like q or lower(s.name) like q or lower(coalesce(qh.supplier_quote_reference,'')) like q) order by qh.quote_date desc,qh.created_at desc loop return next to_jsonb(r);end loop;return;
end $$;
grant execute on function public.purchase_quotations_list_v500(uuid,uuid,text,text) to authenticated;

create or replace function public.purchase_quotation_detail_v500(p_tenant_id uuid,p_quotation_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$ declare h jsonb;i jsonb;begin perform private.purchasing_v484_permission(p_tenant_id,false);select to_jsonb(q) into h from public.purchase_quotations_v500 q where q.id=p_quotation_id and q.tenant_id=p_tenant_id;if h is null then raise exception 'Quotation not found';end if;select coalesce(jsonb_agg(jsonb_build_object('id',qi.id,'variant_id',qi.variant_id,'product_name',p.name,'sku',pv.sku,'quantity',qi.quantity,'unit_cost',qi.unit_cost,'tax_rate',qi.tax_rate,'line_total',qi.line_total,'request_item_id',qi.request_item_id,'note',qi.note) order by p.name),'[]'::jsonb) into i from public.purchase_quotation_items_v500 qi join public.product_variants pv on pv.id=qi.variant_id join public.products p on p.id=pv.product_id where qi.quotation_id=p_quotation_id;return jsonb_build_object('quotation',h,'items',i);end $$;
grant execute on function public.purchase_quotation_detail_v500(uuid,uuid) to authenticated;

create or replace function public.purchase_quotation_convert_v500(p_tenant_id uuid,p_quotation_id uuid,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$ declare q public.purchase_quotations_v500%rowtype;v_items jsonb;v_po jsonb;v_po_id uuid;begin
  select * into q from public.purchase_quotations_v500 where id=p_quotation_id and tenant_id=p_tenant_id for update;if not found then raise exception 'Quotation not found';end if;perform private.purchasing_v484_access(p_tenant_id,q.location_id,true);if q.status not in('received','selected') then raise exception 'Only received/selected quotation can be converted';end if;
  select coalesce(jsonb_agg(jsonb_build_object('variant_id',i.variant_id,'quantity',i.quantity,'unit_cost',i.unit_cost,'tax_rate',i.tax_rate,'note',i.note)),'[]'::jsonb) into v_items from public.purchase_quotation_items_v500 i where i.quotation_id=q.id;
  v_po:=public.purchase_order_create_v484(p_tenant_id,q.location_id,q.supplier_id,v_items,q.expected_delivery_date,concat_ws(' • ',nullif(trim(coalesce(p_notes,'')),''),'Quotation '||q.quotation_number),q.request_id);v_po_id:=nullif(v_po->>'purchase_order_id','')::uuid;
  update public.purchase_quotations_v500 set status='converted',converted_purchase_order_id=v_po_id,updated_at=now() where id=q.id;update public.purchase_quotations_v500 set status='rejected',updated_at=now() where tenant_id=p_tenant_id and request_id=q.request_id and id<>q.id and status in('received','selected');return v_po||jsonb_build_object('quotation_id',q.id,'quotation_number',q.quotation_number);
end $$;
grant execute on function public.purchase_quotation_convert_v500(uuid,uuid,text) to authenticated;

create or replace function public.supplier_performance_v500(p_tenant_id uuid,p_from date default null,p_to date default null,p_limit integer default 500)
returns table(supplier_id uuid,supplier_name text,purchase_value numeric,po_count bigint,grn_count bigint,accepted_qty numeric,damaged_qty numeric,rejected_qty numeric,damage_reject_pct numeric,on_time_pct numeric,avg_delivery_days numeric,last_purchase_date date)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin perform private.purchasing_v484_permission(p_tenant_id,false);
  return query with po as(select p.supplier_id,count(*) po_count,max(p.order_date) last_purchase,coalesce(sum(p.grand_total),0) value from public.purchase_orders_v480 p where p.tenant_id=p_tenant_id and p.status<>'cancelled' and (p_from is null or p.order_date>=p_from) and (p_to is null or p.order_date<=p_to) group by p.supplier_id),gr as(select g.supplier_id,count(distinct g.id) grn_count,coalesce(sum(i.accepted_quantity),0) accepted,coalesce(sum(i.damaged_quantity),0) damaged,coalesce(sum(i.rejected_quantity),0) rejected,avg(g.receipt_date-po2.order_date)::numeric avg_days,avg(case when po2.expected_date is null or g.receipt_date<=po2.expected_date then 100 else 0 end)::numeric ontime from public.goods_receipts_v484 g join public.goods_receipt_items_v484 i on i.goods_receipt_id=g.id join public.purchase_orders_v480 po2 on po2.id=g.purchase_order_id where g.tenant_id=p_tenant_id and g.status='posted' and (p_from is null or g.receipt_date>=p_from) and (p_to is null or g.receipt_date<=p_to) group by g.supplier_id) select s.id,s.name,coalesce(po.value,0)::numeric,coalesce(po.po_count,0),coalesce(gr.grn_count,0),coalesce(gr.accepted,0)::numeric,coalesce(gr.damaged,0)::numeric,coalesce(gr.rejected,0)::numeric,case when coalesce(gr.accepted,0)+coalesce(gr.damaged,0)+coalesce(gr.rejected,0)>0 then round((coalesce(gr.damaged,0)+coalesce(gr.rejected,0))*100/(coalesce(gr.accepted,0)+coalesce(gr.damaged,0)+coalesce(gr.rejected,0)),2) else 0 end::numeric,round(coalesce(gr.ontime,0),2)::numeric,round(coalesce(gr.avg_days,0),2)::numeric,po.last_purchase from public.suppliers s left join po on po.supplier_id=s.id left join gr on gr.supplier_id=s.id where s.tenant_id=p_tenant_id and coalesce(s.status,'active')='active' order by coalesce(po.value,0) desc,s.name limit greatest(1,least(coalesce(p_limit,500),5000));
end $$;
grant execute on function public.supplier_performance_v500(uuid,date,date,integer) to authenticated;

create or replace function public.reorder_suggestions_v500(p_tenant_id uuid,p_location_id uuid default null,p_days integer default 30,p_query text default '',p_limit integer default 1000)
returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$ declare r record;v_supplier uuid;v_supplier_name text;v_last_cost numeric;begin
  for r in select * from public.inventory_intelligence_v480(p_tenant_id,p_location_id,p_days,p_query,p_limit) where status in('out_of_stock','low_stock') and suggested_reorder>0 loop
    select p.supplier_id,s.name,pi.unit_cost into v_supplier,v_supplier_name,v_last_cost from public.purchase_items pi join public.purchases p on p.id=pi.purchase_id join public.suppliers s on s.id=p.supplier_id where p.tenant_id=p_tenant_id and pi.variant_id=r.variant_id and coalesce(p.status,'') not in('void','cancelled') order by p.purchase_date desc,p.created_at desc limit 1;
    return next to_jsonb(r)||jsonb_build_object('suggested_supplier_id',v_supplier,'suggested_supplier_name',v_supplier_name,'last_unit_cost',coalesce(v_last_cost,r.average_cost));
  end loop;return;
end $$;
grant execute on function public.reorder_suggestions_v500(uuid,uuid,integer,text,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(203,'5.0.0','CRM & Purchasing Intelligence','Customer groups/CRM/loyalty, supplier quotation comparison and conversion, supplier performance and smart reorder recommendations.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v5.0.0 migration 203 applied' as status;
