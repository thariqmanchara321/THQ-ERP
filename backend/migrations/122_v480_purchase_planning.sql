-- THQ ERP V4.8.0
-- Purchase planning and non-posting Purchase Orders.
begin;

create sequence if not exists public.purchase_order_number_seq;

create table if not exists public.purchase_orders_v480(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  order_number text not null,
  order_date date not null default current_date,
  expected_date date,
  status text not null default 'draft' check(status in('draft','submitted','approved','ordered','cancelled')),
  notes text,
  subtotal numeric not null default 0,
  tax_total numeric not null default 0,
  grand_total numeric not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  ordered_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,order_number)
);
create index if not exists idx_purchase_orders_v480_lookup on public.purchase_orders_v480(tenant_id,location_id,status,order_date desc);
alter table public.purchase_orders_v480 enable row level security;
revoke all on public.purchase_orders_v480 from anon,authenticated;

create table if not exists public.purchase_order_items_v480(
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references public.purchase_orders_v480(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  quantity numeric not null check(quantity>0),
  unit_cost numeric not null default 0 check(unit_cost>=0),
  tax_rate numeric not null default 0,
  line_subtotal numeric not null default 0,
  tax_amount numeric not null default 0,
  line_total numeric not null default 0,
  note text,
  unique(purchase_order_id,variant_id)
);
create index if not exists idx_purchase_order_items_v480_variant on public.purchase_order_items_v480(variant_id,purchase_order_id);
alter table public.purchase_order_items_v480 enable row level security;
revoke all on public.purchase_order_items_v480 from anon,authenticated;

create table if not exists public.purchase_order_status_history_v480(
  id bigint generated always as identity primary key,
  purchase_order_id uuid not null references public.purchase_orders_v480(id) on delete cascade,
  from_status text,
  to_status text not null,
  reason text,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now()
);
create index if not exists idx_po_status_history_v480 on public.purchase_order_status_history_v480(purchase_order_id,id);
alter table public.purchase_order_status_history_v480 enable row level security;
revoke all on public.purchase_order_status_history_v480 from anon,authenticated;

create or replace function private.purchase_planning_access_v480(p_tenant_id uuid,p_location_id uuid,p_manage boolean default false)
returns void language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_document_scope_allowed(p_tenant_id,p_location_id,p_location_id,case when p_manage then 'operate' else 'view' end) then raise exception 'Location access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id) then
    if p_manage and not private.erp_has_permission(p_tenant_id,'purchases.manage') then raise exception 'Purchase management permission required';end if;
    if not p_manage and not private.erp_has_permission(p_tenant_id,'purchases.view') and not private.erp_has_permission(p_tenant_id,'purchases.manage') then raise exception 'Purchase permission required';end if;
  end if;
end $$;
revoke all on function private.purchase_planning_access_v480(uuid,uuid,boolean) from public;

create or replace function public.purchase_reorder_suggestions_v480(
  p_tenant_id uuid,p_location_id uuid default null,p_days integer default 30,p_query text default '',p_limit integer default 1000
)
returns table(
  location_id uuid,location_code text,location_name text,variant_id uuid,product_name text,sku text,current_stock numeric,reorder_level numeric,max_stock numeric,
  avg_daily_sales numeric,days_cover numeric,suggested_quantity numeric,last_supplier_id uuid,last_supplier_name text,last_unit_cost numeric,tax_rate numeric,last_purchase_date date
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  with intel as (
    select * from public.inventory_intelligence_v480(p_tenant_id,p_location_id,p_days,p_query,p_limit)
    where suggested_reorder>0
  ), last_buy as (
    select distinct on(o.location_id,pi.variant_id) o.location_id,pi.variant_id,p.supplier_id,s.name supplier_name,pi.unit_cost,p.purchase_date
    from public.purchase_items pi join public.purchases p on p.id=pi.purchase_id
    join public.suppliers s on s.id=p.supplier_id
    join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id
    where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled')
    order by o.location_id,pi.variant_id,p.purchase_date desc,p.created_at desc
  )
  select i.location_id,i.location_code,i.location_name,i.variant_id,i.product_name,i.sku,i.available,i.reorder_level,i.max_stock,
    i.avg_daily_sales,i.days_cover,i.suggested_reorder,lb.supplier_id,lb.supplier_name,coalesce(lb.unit_cost,i.average_cost,0),coalesce(pv.tax_rate,0),lb.purchase_date
  from intel i join public.product_variants pv on pv.id=i.variant_id left join last_buy lb on lb.location_id=i.location_id and lb.variant_id=i.variant_id
  order by i.location_name,i.status,i.product_name;
end $$;
grant execute on function public.purchase_reorder_suggestions_v480(uuid,uuid,integer,text,integer) to authenticated;

create or replace function public.purchase_order_create_v480(
  p_tenant_id uuid,p_location_id uuid,p_supplier_id uuid,p_items jsonb,p_expected_date date default null,p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_id uuid:=gen_random_uuid();v_no text;v_sub numeric:=0;v_tax numeric:=0;v_total numeric:=0;x jsonb;v_variant uuid;v_qty numeric;v_cost numeric;v_rate numeric;v_line numeric;v_line_tax numeric;begin
  perform private.purchase_planning_access_v480(p_tenant_id,p_location_id,true);
  if not exists(select 1 from public.suppliers where id=p_supplier_id and tenant_id=p_tenant_id and coalesce(status,'active')='active') then raise exception 'Active supplier not found';end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'At least one item is required';end if;
  v_no:='PO-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.purchase_order_number_seq')::text,6,'0');
  insert into public.purchase_orders_v480(id,tenant_id,location_id,supplier_id,order_number,expected_date,notes,created_by)
  values(v_id,p_tenant_id,p_location_id,p_supplier_id,v_no,p_expected_date,nullif(trim(coalesce(p_notes,'')),''),auth.uid());
  for x in select value from jsonb_array_elements(p_items)
  loop
    v_variant:=nullif(x->>'variant_id','')::uuid;v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);v_cost:=greatest(coalesce(nullif(x->>'unit_cost','')::numeric,0),0);v_rate:=greatest(coalesce(nullif(x->>'tax_rate','')::numeric,0),0);
    if v_variant is null or v_qty<=0 then raise exception 'Invalid purchase order item';end if;
    if not exists(select 1 from public.product_variants where id=v_variant and tenant_id=p_tenant_id) then raise exception 'Product variant not found';end if;
    v_line:=round(v_qty*v_cost,2);v_line_tax:=round(v_line*v_rate/100.0,2);
    insert into public.purchase_order_items_v480(purchase_order_id,variant_id,quantity,unit_cost,tax_rate,line_subtotal,tax_amount,line_total,note)
    values(v_id,v_variant,v_qty,v_cost,v_rate,v_line,v_line_tax,v_line+v_line_tax,nullif(trim(coalesce(x->>'note','')),''))
    on conflict(purchase_order_id,variant_id) do update set quantity=public.purchase_order_items_v480.quantity+excluded.quantity,
      unit_cost=excluded.unit_cost,tax_rate=excluded.tax_rate,
      line_subtotal=round((public.purchase_order_items_v480.quantity+excluded.quantity)*excluded.unit_cost,2),
      tax_amount=round((public.purchase_order_items_v480.quantity+excluded.quantity)*excluded.unit_cost*excluded.tax_rate/100.0,2),
      line_total=round((public.purchase_order_items_v480.quantity+excluded.quantity)*excluded.unit_cost*(1+excluded.tax_rate/100.0),2);
  end loop;
  select coalesce(sum(line_subtotal),0),coalesce(sum(tax_amount),0),coalesce(sum(line_total),0) into v_sub,v_tax,v_total from public.purchase_order_items_v480 where purchase_order_id=v_id;
  update public.purchase_orders_v480 set subtotal=v_sub,tax_total=v_tax,grand_total=v_total,updated_at=now() where id=v_id;
  insert into public.purchase_order_status_history_v480(purchase_order_id,to_status,reason,changed_by) values(v_id,'draft','Purchase order created',auth.uid());
  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','purchase_order',v_id::text,'create');
  return jsonb_build_object('success',true,'purchase_order_id',v_id,'order_number',v_no,'status','draft','grand_total',v_total);
end $$;
grant execute on function public.purchase_order_create_v480(uuid,uuid,uuid,jsonb,date,text) to authenticated;

create or replace function public.purchase_order_list_v480(p_tenant_id uuid,p_location_id uuid default null,p_status text default null,p_query text default '',p_limit integer default 500)
returns table(id uuid,order_number text,order_date date,expected_date date,status text,location_id uuid,location_name text,supplier_id uuid,supplier_name text,grand_total numeric,item_count bigint,created_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select po.id,po.order_number,po.order_date,po.expected_date,po.status,po.location_id,l.name,po.supplier_id,s.name,po.grand_total,count(i.id),po.created_at
  from public.purchase_orders_v480 po join public.business_locations l on l.id=po.location_id join public.suppliers s on s.id=po.supplier_id
  left join public.purchase_order_items_v480 i on i.purchase_order_id=po.id
  where po.tenant_id=p_tenant_id and (p_location_id is null or po.location_id=p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id,po.location_id,p_location_id,'view')
    and (nullif(trim(coalesce(p_status,'')),'') is null or po.status=p_status)
    and (trim(coalesce(p_query,''))='' or lower(po.order_number) like q or lower(s.name) like q)
  group by po.id,l.name,s.name order by po.created_at desc limit greatest(1,least(coalesce(p_limit,500),2000));
end $$;
grant execute on function public.purchase_order_list_v480(uuid,uuid,text,text,integer) to authenticated;

create or replace function public.purchase_order_detail_v480(p_tenant_id uuid,p_purchase_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare v jsonb;v_location uuid;begin
  select location_id into v_location from public.purchase_orders_v480 where id=p_purchase_order_id and tenant_id=p_tenant_id;
  if v_location is null then raise exception 'Purchase order not found';end if;perform private.purchase_planning_access_v480(p_tenant_id,v_location,false);
  select jsonb_build_object(
    'order',to_jsonb(po)||jsonb_build_object('location_name',l.name,'supplier_name',s.name),
    'items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('product_name',p.name,'sku',pv.sku) order by p.name) from public.purchase_order_items_v480 i join public.product_variants pv on pv.id=i.variant_id join public.products p on p.id=pv.product_id where i.purchase_order_id=po.id),'[]'::jsonb),
    'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.id) from public.purchase_order_status_history_v480 h where h.purchase_order_id=po.id),'[]'::jsonb)
  ) into v
  from public.purchase_orders_v480 po join public.business_locations l on l.id=po.location_id join public.suppliers s on s.id=po.supplier_id
  where po.id=p_purchase_order_id and po.tenant_id=p_tenant_id;
  return v;
end $$;
grant execute on function public.purchase_order_detail_v480(uuid,uuid) to authenticated;

create or replace function public.purchase_order_status_v480(p_tenant_id uuid,p_purchase_order_id uuid,p_status text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_old text;v_loc uuid;v_allowed boolean:=false;begin
  select status,location_id into v_old,v_loc from public.purchase_orders_v480 where id=p_purchase_order_id and tenant_id=p_tenant_id for update;
  if v_old is null then raise exception 'Purchase order not found';end if;perform private.purchase_planning_access_v480(p_tenant_id,v_loc,true);
  if p_status=v_old then return jsonb_build_object('success',true,'status',v_old);end if;
  v_allowed:=case v_old when 'draft' then p_status in('submitted','cancelled') when 'submitted' then p_status in('approved','draft','cancelled') when 'approved' then p_status in('ordered','cancelled') when 'ordered' then p_status='cancelled' else false end;
  if not v_allowed then raise exception 'Invalid purchase order transition: % -> %',v_old,p_status;end if;
  if p_status='cancelled' and trim(coalesce(p_reason,''))='' then raise exception 'Cancellation reason is required';end if;
  update public.purchase_orders_v480 set status=p_status,updated_at=now(),
    approved_by=case when p_status='approved' then auth.uid() else approved_by end,
    approved_at=case when p_status='approved' then now() else approved_at end,
    ordered_at=case when p_status='ordered' then now() else ordered_at end,
    cancelled_at=case when p_status='cancelled' then now() else cancelled_at end
  where id=p_purchase_order_id;
  insert into public.purchase_order_status_history_v480(purchase_order_id,from_status,to_status,reason,changed_by)
  values(p_purchase_order_id,v_old,p_status,nullif(trim(coalesce(p_reason,'')),''),auth.uid());
  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','purchase_order',p_purchase_order_id::text,'status.'||p_status);
  return jsonb_build_object('success',true,'purchase_order_id',p_purchase_order_id,'from_status',v_old,'status',p_status);
end $$;
grant execute on function public.purchase_order_status_v480(uuid,uuid,text,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(122,'4.8.0','Operational Intelligence & Connectivity','Store-specific reorder suggestions and non-posting Purchase Orders with controlled workflow/history.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP V4.8.0 migration 122 purchase planning ready' as status;
