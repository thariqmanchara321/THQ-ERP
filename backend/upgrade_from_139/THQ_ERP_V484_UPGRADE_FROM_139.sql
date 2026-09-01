-- THQ ERP V4.8.4 — Purchasing V2 foundation: Purchase Requests and Purchase Order V2 workflow.
begin;

create sequence if not exists public.purchase_request_number_seq_v484;

create table if not exists public.purchase_requests_v484(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete restrict,
  preferred_supplier_id uuid references public.suppliers(id) on delete set null,
  request_number text not null,
  request_date date not null default current_date,
  required_date date,
  priority text not null default 'normal' check(priority in('low','normal','high','urgent')),
  status text not null default 'draft' check(status in('draft','submitted','approved','rejected','converted','cancelled')),
  purpose text,
  notes text,
  requested_by uuid references auth.users(id) on delete set null,
  submitted_by uuid references auth.users(id) on delete set null,
  submitted_at timestamptz,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  rejected_by uuid references auth.users(id) on delete set null,
  rejected_at timestamptz,
  rejection_reason text,
  converted_purchase_order_id uuid references public.purchase_orders_v480(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,request_number)
);
create index if not exists idx_purchase_requests_v484_lookup on public.purchase_requests_v484(tenant_id,location_id,status,request_date desc);
alter table public.purchase_requests_v484 enable row level security;
revoke all on public.purchase_requests_v484 from anon,authenticated;

create table if not exists public.purchase_request_items_v484(
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.purchase_requests_v484(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  quantity numeric not null check(quantity>0),
  entered_quantity numeric,
  entered_unit_id uuid references public.inventory_units_v481(id) on delete set null,
  entered_unit_code text,
  conversion_to_base numeric not null default 1 check(conversion_to_base>0),
  estimated_unit_cost numeric not null default 0 check(estimated_unit_cost>=0),
  note text,
  unique(request_id,variant_id)
);
create index if not exists idx_purchase_request_items_v484_variant on public.purchase_request_items_v484(variant_id,request_id);
alter table public.purchase_request_items_v484 enable row level security;
revoke all on public.purchase_request_items_v484 from anon,authenticated;

create table if not exists public.purchase_request_history_v484(
  id bigint generated always as identity primary key,
  request_id uuid not null references public.purchase_requests_v484(id) on delete cascade,
  from_status text,
  to_status text not null,
  note text,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now()
);
create index if not exists idx_purchase_request_history_v484 on public.purchase_request_history_v484(request_id,id);
alter table public.purchase_request_history_v484 enable row level security;
revoke all on public.purchase_request_history_v484 from anon,authenticated;

-- Upgrade the existing non-posting V4.8.0 PO table rather than creating a second PO registry.
alter table public.purchase_orders_v480 add column if not exists request_id uuid references public.purchase_requests_v484(id) on delete set null;
alter table public.purchase_orders_v480 add column if not exists submitted_by uuid references auth.users(id) on delete set null;
alter table public.purchase_orders_v480 add column if not exists submitted_at timestamptz;
alter table public.purchase_orders_v480 add column if not exists rejected_by uuid references auth.users(id) on delete set null;
alter table public.purchase_orders_v480 add column if not exists rejected_at timestamptz;
alter table public.purchase_orders_v480 add column if not exists rejection_reason text;
alter table public.purchase_orders_v480 add column if not exists closed_at timestamptz;
alter table public.purchase_orders_v480 drop constraint if exists purchase_orders_v480_status_check;
alter table public.purchase_orders_v480 add constraint purchase_orders_v480_status_check check(status in('draft','submitted','approved','rejected','ordered','partially_received','received','closed','cancelled'));
create index if not exists idx_purchase_orders_v480_request on public.purchase_orders_v480(tenant_id,request_id);

alter table public.purchase_order_items_v480 add column if not exists request_item_id uuid references public.purchase_request_items_v484(id) on delete set null;
alter table public.purchase_order_items_v480 add column if not exists received_quantity numeric not null default 0 check(received_quantity>=0);
alter table public.purchase_order_items_v480 add column if not exists accepted_quantity numeric not null default 0 check(accepted_quantity>=0);
alter table public.purchase_order_items_v480 add column if not exists damaged_quantity numeric not null default 0 check(damaged_quantity>=0);
alter table public.purchase_order_items_v480 add column if not exists rejected_quantity numeric not null default 0 check(rejected_quantity>=0);
alter table public.purchase_order_items_v480 add column if not exists invoiced_quantity numeric not null default 0 check(invoiced_quantity>=0);

create or replace function private.purchasing_v484_permission(p_tenant_id uuid,p_manage boolean default false)
returns void language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id) then
    if p_manage and not private.erp_has_permission(p_tenant_id,'purchases.manage') then raise exception 'Purchase management permission required';end if;
    if not p_manage and not private.erp_has_permission(p_tenant_id,'purchases.view') and not private.erp_has_permission(p_tenant_id,'purchases.manage') then raise exception 'Purchase permission required';end if;
  end if;
end$$;
revoke all on function private.purchasing_v484_permission(uuid,boolean) from public;

create or replace function private.purchasing_v484_access(p_tenant_id uuid,p_location_id uuid,p_manage boolean default false)
returns void language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  perform private.purchasing_v484_permission(p_tenant_id,p_manage);
  if p_location_id is null or not private.erp_document_scope_allowed(p_tenant_id,p_location_id,p_location_id,case when p_manage then 'operate' else 'view' end) then raise exception 'Location access denied';end if;
end$$;
revoke all on function private.purchasing_v484_access(uuid,uuid,boolean) from public;

create or replace function private.purchasing_v484_approval_access(p_tenant_id uuid,p_location_id uuid)
returns void language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  perform private.purchasing_v484_access(p_tenant_id,p_location_id,false);
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'approvals.approve') then raise exception 'Approval permission required';end if;
end$$;
revoke all on function private.purchasing_v484_approval_access(uuid,uuid) from public;

create or replace function public.purchase_request_create_v484(
  p_tenant_id uuid,p_location_id uuid,p_items jsonb,p_required_date date default null,p_priority text default 'normal',
  p_preferred_supplier_id uuid default null,p_purpose text default null,p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid:=gen_random_uuid();v_no text;x jsonb;v_norm jsonb;v_variant uuid;v_qty numeric;begin
  perform private.purchasing_v484_access(p_tenant_id,p_location_id,true);
  if lower(coalesce(p_priority,'normal')) not in('low','normal','high','urgent') then raise exception 'Invalid priority';end if;
  if p_preferred_supplier_id is not null and not exists(select 1 from public.suppliers where tenant_id=p_tenant_id and id=p_preferred_supplier_id and coalesce(status,'active')='active') then raise exception 'Preferred supplier not found';end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'At least one item is required';end if;
  v_norm:=private.v481_normalize_items(p_tenant_id,p_items,'purchase');
  v_no:='PR-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.purchase_request_number_seq_v484')::text,6,'0');
  insert into public.purchase_requests_v484(id,tenant_id,location_id,preferred_supplier_id,request_number,required_date,priority,purpose,notes,requested_by)
  values(v_id,p_tenant_id,p_location_id,p_preferred_supplier_id,v_no,p_required_date,lower(coalesce(p_priority,'normal')),nullif(trim(coalesce(p_purpose,'')),''),nullif(trim(coalesce(p_notes,'')),''),auth.uid());
  for x in select value from jsonb_array_elements(v_norm) loop
    v_variant:=nullif(x->>'variant_id','')::uuid;v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);
    if v_variant is null or v_qty<=0 then raise exception 'Invalid purchase request item';end if;
    insert into public.purchase_request_items_v484(request_id,variant_id,quantity,entered_quantity,entered_unit_id,entered_unit_code,conversion_to_base,estimated_unit_cost,note)
    values(v_id,v_variant,v_qty,nullif(x->>'_entered_quantity','')::numeric,nullif(x->>'_entered_unit_id','')::uuid,nullif(x->>'_entered_unit_code',''),coalesce(nullif(x->>'_conversion_to_base','')::numeric,1),greatest(coalesce(nullif(x->>'_entered_unit_cost','')::numeric,nullif(x->>'unit_cost','')::numeric,0),0),nullif(trim(coalesce(x->>'note','')),''));
  end loop;
  insert into public.purchase_request_history_v484(request_id,to_status,note,changed_by) values(v_id,'draft','Purchase request created',auth.uid());
  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','purchase_request',v_id::text,'create');
  return jsonb_build_object('success',true,'request_id',v_id,'request_number',v_no,'status','draft');
end$$;
grant execute on function public.purchase_request_create_v484(uuid,uuid,jsonb,date,text,uuid,text,text) to authenticated;

create or replace function public.purchase_request_list_v484(p_tenant_id uuid,p_location_id uuid default null,p_status text default null,p_query text default '',p_limit integer default 500)
returns table(id uuid,request_number text,request_date date,required_date date,priority text,status text,location_id uuid,location_name text,preferred_supplier_id uuid,preferred_supplier_name text,item_count bigint,total_quantity numeric,estimated_total numeric,purpose text,requested_by uuid,created_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
  perform private.purchasing_v484_permission(p_tenant_id,false);
  return query select r.id,r.request_number,r.request_date,r.required_date,r.priority,r.status,r.location_id,l.name,r.preferred_supplier_id,s.name,count(i.id),coalesce(sum(i.quantity),0),coalesce(sum(i.quantity*i.estimated_unit_cost),0),r.purpose,r.requested_by,r.created_at
  from public.purchase_requests_v484 r join public.business_locations l on l.id=r.location_id left join public.suppliers s on s.id=r.preferred_supplier_id left join public.purchase_request_items_v484 i on i.request_id=r.id left join public.product_variants pv on pv.id=i.variant_id left join public.products p on p.id=pv.product_id
  where r.tenant_id=p_tenant_id and (p_location_id is null or r.location_id=p_location_id) and (p_status is null or p_status='' or r.status=p_status)
    and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view')
    and (trim(coalesce(p_query,''))='' or lower(r.request_number) like q or lower(coalesce(r.purpose,'')) like q or lower(coalesce(s.name,'')) like q or lower(coalesce(p.name,'')) like q or lower(coalesce(pv.sku,'')) like q)
  group by r.id,l.name,s.name order by r.created_at desc limit greatest(1,least(coalesce(p_limit,500),2000));
end$$;
grant execute on function public.purchase_request_list_v484(uuid,uuid,text,text,integer) to authenticated;

create or replace function public.purchase_request_detail_v484(p_tenant_id uuid,p_request_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_loc uuid;v jsonb;begin
  select location_id into v_loc from public.purchase_requests_v484 where tenant_id=p_tenant_id and id=p_request_id;
  if v_loc is null then raise exception 'Purchase request not found';end if;perform private.purchasing_v484_access(p_tenant_id,v_loc,false);
  select jsonb_build_object('request',to_jsonb(r)||jsonb_build_object('location_name',l.name,'preferred_supplier_name',s.name),
    'items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('product_name',p.name,'sku',pv.sku) order by p.name) from public.purchase_request_items_v484 i join public.product_variants pv on pv.id=i.variant_id join public.products p on p.id=pv.product_id where i.request_id=r.id),'[]'::jsonb),
    'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.id) from public.purchase_request_history_v484 h where h.request_id=r.id),'[]'::jsonb)) into v
  from public.purchase_requests_v484 r join public.business_locations l on l.id=r.location_id left join public.suppliers s on s.id=r.preferred_supplier_id where r.id=p_request_id and r.tenant_id=p_tenant_id;
  return v;
end$$;
grant execute on function public.purchase_request_detail_v484(uuid,uuid) to authenticated;

create or replace function public.purchase_request_status_v484(p_tenant_id uuid,p_request_id uuid,p_status text,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_old text;v_loc uuid;v_status text:=lower(trim(coalesce(p_status,'')));begin
  select status,location_id into v_old,v_loc from public.purchase_requests_v484 where tenant_id=p_tenant_id and id=p_request_id for update;if v_loc is null then raise exception 'Purchase request not found';end if;
  if v_status in('approved','rejected') then perform private.purchasing_v484_approval_access(p_tenant_id,v_loc);else perform private.purchasing_v484_access(p_tenant_id,v_loc,true);end if;
  if v_status not in('submitted','approved','rejected','cancelled') then raise exception 'Unsupported Purchase Request status transition';end if;
  if v_status='submitted' and v_old<>'draft' then raise exception 'Only Draft requests can be submitted';end if;
  if v_status in('approved','rejected') and v_old<>'submitted' then raise exception 'Only Submitted requests can be approved or rejected';end if;
  if v_status='cancelled' and v_old not in('draft','submitted','approved') then raise exception 'This request cannot be cancelled';end if;
  if v_status='rejected' and trim(coalesce(p_note,''))='' then raise exception 'Rejection reason is required';end if;
  update public.purchase_requests_v484 set status=v_status,updated_at=now(),
    submitted_by=case when v_status='submitted' then auth.uid() else submitted_by end,submitted_at=case when v_status='submitted' then now() else submitted_at end,
    approved_by=case when v_status='approved' then auth.uid() else approved_by end,approved_at=case when v_status='approved' then now() else approved_at end,
    rejected_by=case when v_status='rejected' then auth.uid() else rejected_by end,rejected_at=case when v_status='rejected' then now() else rejected_at end,rejection_reason=case when v_status='rejected' then trim(p_note) else rejection_reason end
  where id=p_request_id;
  insert into public.purchase_request_history_v484(request_id,from_status,to_status,note,changed_by) values(p_request_id,v_old,v_status,nullif(trim(coalesce(p_note,'')),''),auth.uid());
  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','purchase_request',p_request_id::text,'status.'||v_status);
  return jsonb_build_object('success',true,'request_id',p_request_id,'from_status',v_old,'status',v_status);
end$$;
grant execute on function public.purchase_request_status_v484(uuid,uuid,text,text) to authenticated;

create or replace function public.purchase_order_create_v484(
  p_tenant_id uuid,p_location_id uuid,p_supplier_id uuid,p_items jsonb,p_expected_date date default null,p_notes text default null,p_request_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v jsonb;v_po uuid;v_req_loc uuid;v_req_status text;begin
  if p_request_id is not null then
    select location_id,status into v_req_loc,v_req_status from public.purchase_requests_v484 where tenant_id=p_tenant_id and id=p_request_id for update;
    if v_req_loc is null then raise exception 'Purchase request not found';end if;if v_req_loc<>p_location_id then raise exception 'PO location must match Purchase Request location';end if;if v_req_status<>'approved' then raise exception 'Purchase Request must be approved before conversion to a PO';end if;
  end if;
  v:=public.purchase_order_create_v480(p_tenant_id,p_location_id,p_supplier_id,p_items,p_expected_date,p_notes);
  v_po:=nullif(v->>'purchase_order_id','')::uuid;
  if v_po is not null then
    update public.purchase_orders_v480 set request_id=p_request_id where id=v_po;
    if p_request_id is not null then
      update public.purchase_requests_v484 set status='converted',converted_purchase_order_id=v_po,updated_at=now() where id=p_request_id;
      insert into public.purchase_request_history_v484(request_id,from_status,to_status,note,changed_by) values(p_request_id,'approved','converted','Converted to Purchase Order '||(v->>'order_number'),auth.uid());
      update public.purchase_order_items_v480 poi set request_item_id=ri.id from public.purchase_request_items_v484 ri where poi.purchase_order_id=v_po and ri.request_id=p_request_id and ri.variant_id=poi.variant_id;
    end if;
  end if;
  return v||jsonb_build_object('request_id',p_request_id,'purchasing_engine','v4.8.4');
end$$;
grant execute on function public.purchase_order_create_v484(uuid,uuid,uuid,jsonb,date,text,uuid) to authenticated;

create or replace function public.purchase_order_decide_v484(p_tenant_id uuid,p_purchase_order_id uuid,p_approve boolean,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_old text;v_loc uuid;v_status text;begin
  select status,location_id into v_old,v_loc from public.purchase_orders_v480 where tenant_id=p_tenant_id and id=p_purchase_order_id for update;if v_loc is null then raise exception 'Purchase Order not found';end if;
  perform private.purchasing_v484_approval_access(p_tenant_id,v_loc);if v_old<>'submitted' then raise exception 'Only Submitted Purchase Orders can be decided';end if;
  v_status:=case when p_approve then 'approved' else 'rejected' end;if not p_approve and trim(coalesce(p_note,''))='' then raise exception 'Rejection reason is required';end if;
  update public.purchase_orders_v480 set status=v_status,updated_at=now(),approved_by=case when p_approve then auth.uid() else approved_by end,approved_at=case when p_approve then now() else approved_at end,rejected_by=case when not p_approve then auth.uid() else rejected_by end,rejected_at=case when not p_approve then now() else rejected_at end,rejection_reason=case when not p_approve then trim(p_note) else rejection_reason end where id=p_purchase_order_id;
  insert into public.purchase_order_status_history_v480(purchase_order_id,from_status,to_status,reason,changed_by) values(p_purchase_order_id,v_old,v_status,nullif(trim(coalesce(p_note,'')),''),auth.uid());
  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','purchase_order',p_purchase_order_id::text,'decision.'||v_status);
  return jsonb_build_object('success',true,'purchase_order_id',p_purchase_order_id,'status',v_status);
end$$;
grant execute on function public.purchase_order_decide_v484(uuid,uuid,boolean,text) to authenticated;

-- Harden the old status transition RPC so V4.8.4 approval cannot be bypassed by calling it directly.
create or replace function public.purchase_order_status_v480(p_tenant_id uuid,p_purchase_order_id uuid,p_status text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_old text;v_loc uuid;v_status text:=lower(trim(coalesce(p_status,'')));begin
  select status,location_id into v_old,v_loc from public.purchase_orders_v480 where id=p_purchase_order_id and tenant_id=p_tenant_id for update;if v_loc is null then raise exception 'Purchase order not found';end if;
  perform private.purchase_planning_access_v480(p_tenant_id,v_loc,true);
  if v_status in('approved','rejected') then raise exception 'Use the V4.8.4 PO approval action';end if;
  if v_status='submitted' and v_old not in('draft','rejected') then raise exception 'Only Draft/Rejected purchase orders can be submitted';end if;
  if v_status='ordered' and v_old<>'approved' then raise exception 'Only Approved purchase orders can be marked Ordered';end if;
  if v_status='cancelled' and v_old in('received','closed','cancelled') then raise exception 'Purchase order cannot be cancelled in its current state';end if;
  if v_status not in('submitted','ordered','cancelled') then raise exception 'Unsupported manual PO status';end if;
  if v_status='cancelled' and exists(select 1 from public.purchase_order_items_v480 where purchase_order_id=p_purchase_order_id and received_quantity>0.000001) then raise exception 'A partially received Purchase Order cannot be cancelled; keep it open for remaining receipt/invoice processing';end if;
  update public.purchase_orders_v480 set status=v_status,updated_at=now(),submitted_by=case when v_status='submitted' then auth.uid() else submitted_by end,submitted_at=case when v_status='submitted' then now() else submitted_at end,ordered_at=case when v_status='ordered' then now() else ordered_at end,cancelled_at=case when v_status='cancelled' then now() else cancelled_at end where id=p_purchase_order_id;
  insert into public.purchase_order_status_history_v480(purchase_order_id,from_status,to_status,reason,changed_by) values(p_purchase_order_id,v_old,v_status,nullif(trim(coalesce(p_reason,'')),''),auth.uid());
  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','purchase_order',p_purchase_order_id::text,'status.'||v_status);
  return jsonb_build_object('success',true,'purchase_order_id',p_purchase_order_id,'from_status',v_old,'status',v_status);
end$$;
grant execute on function public.purchase_order_status_v480(uuid,uuid,text,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(140,'4.8.4','Purchasing V2','Purchase Requests, PR approval/conversion and strengthened Purchase Order V2 workflow.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.4 migration 140 Purchase Requests and PO V2 applied' as status;
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
-- THQ ERP V4.8.4 — Supplier payments, allocations and supplier ledger.
begin;

create sequence if not exists public.supplier_payment_number_seq_v484;

create table if not exists public.supplier_payments_v484(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  payment_number text not null,
  payment_date date not null default current_date,
  amount numeric not null check(amount>0),
  payment_method text not null,
  reference_number text,
  notes text,
  status text not null default 'posted' check(status in('posted','void')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  voided_by uuid references auth.users(id) on delete set null,
  voided_at timestamptz,
  void_reason text,
  unique(tenant_id,payment_number)
);
create index if not exists idx_supplier_payments_v484_supplier on public.supplier_payments_v484(tenant_id,supplier_id,payment_date desc);
alter table public.supplier_payments_v484 enable row level security;
revoke all on public.supplier_payments_v484 from anon,authenticated;

create table if not exists public.supplier_payment_allocations_v484(
  id uuid primary key default gen_random_uuid(),
  supplier_payment_id uuid not null references public.supplier_payments_v484(id) on delete cascade,
  purchase_invoice_id uuid not null references public.purchase_invoices_v484(id) on delete restrict,
  amount numeric not null check(amount>0),
  created_at timestamptz not null default now(),
  unique(supplier_payment_id,purchase_invoice_id)
);
create index if not exists idx_supplier_payment_allocations_v484_invoice on public.supplier_payment_allocations_v484(purchase_invoice_id,supplier_payment_id);
alter table public.supplier_payment_allocations_v484 enable row level security;
revoke all on public.supplier_payment_allocations_v484 from anon,authenticated;

create table if not exists public.supplier_ledger_entries_v484(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  location_id uuid references public.business_locations(id) on delete set null,
  entry_date date not null,
  entry_type text not null check(entry_type in('purchase_invoice','supplier_payment','adjustment','void')),
  source_id uuid not null,
  reference_number text,
  description text,
  debit numeric not null default 0 check(debit>=0),
  credit numeric not null default 0 check(credit>=0),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(tenant_id,entry_type,source_id)
);
create index if not exists idx_supplier_ledger_entries_v484_supplier on public.supplier_ledger_entries_v484(tenant_id,supplier_id,entry_date,created_at);
alter table public.supplier_ledger_entries_v484 enable row level security;
revoke all on public.supplier_ledger_entries_v484 from anon,authenticated;

create or replace function private.v484_invoice_ledger_after_status()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if new.status in('posted','part_paid','paid') and old.status='draft' then
    insert into public.supplier_ledger_entries_v484(tenant_id,supplier_id,location_id,entry_date,entry_type,source_id,reference_number,description,debit,credit,created_by)
    values(new.tenant_id,new.supplier_id,new.location_id,new.invoice_date,'purchase_invoice',new.id,new.invoice_number,'Purchase Invoice '||coalesce(new.supplier_invoice_number,new.invoice_number),new.grand_total,0,new.posted_by)
    on conflict(tenant_id,entry_type,source_id) do nothing;
  end if;
  return new;
end$$;
drop trigger if exists trg_v484_invoice_ledger_after_status on public.purchase_invoices_v484;
create trigger trg_v484_invoice_ledger_after_status after update of status on public.purchase_invoices_v484 for each row execute function private.v484_invoice_ledger_after_status();

create or replace function private.v484_refresh_invoice_payment_status(p_invoice_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_paid numeric;v_total numeric;v_status text;begin
 select grand_total,status into v_total,v_status from public.purchase_invoices_v484 where id=p_invoice_id for update;if not found or v_status='void' then return;end if;
 select coalesce(sum(a.amount),0) into v_paid from public.supplier_payment_allocations_v484 a join public.supplier_payments_v484 p on p.id=a.supplier_payment_id where a.purchase_invoice_id=p_invoice_id and p.status='posted';
 update public.purchase_invoices_v484 set paid_total=v_paid,balance_due=greatest(v_total-v_paid,0),status=case when v_paid>=v_total-0.005 then 'paid' when v_paid>0 then 'part_paid' else 'posted' end,updated_at=now() where id=p_invoice_id;
end$$;
revoke all on function private.v484_refresh_invoice_payment_status(uuid) from public;

create or replace function public.supplier_payment_create_v484(
  p_tenant_id uuid,p_location_id uuid,p_supplier_id uuid,p_payment_date date,p_amount numeric,p_payment_method text,
  p_allocations jsonb default '[]'::jsonb,p_reference_number text default null,p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid:=gen_random_uuid();v_no text;v_sum numeric:=0;x jsonb;v_invoice uuid;v_alloc numeric;i public.purchase_invoices_v484%rowtype;v_lines jsonb;begin
  perform private.purchasing_v484_access(p_tenant_id,p_location_id,true);
  if not exists(select 1 from public.suppliers where tenant_id=p_tenant_id and id=p_supplier_id and coalesce(status,'active')='active') then raise exception 'Supplier not found';end if;
  if coalesce(p_amount,0)<=0 then raise exception 'Payment amount must be positive';end if;if trim(coalesce(p_payment_method,''))='' then raise exception 'Payment method is required';end if;
  if jsonb_typeof(coalesce(p_allocations,'[]'::jsonb))<>'array' then raise exception 'Allocations must be an array';end if;
  for x in select value from jsonb_array_elements(coalesce(p_allocations,'[]'::jsonb)) loop
    v_invoice:=nullif(x->>'purchase_invoice_id','')::uuid;v_alloc:=coalesce(nullif(x->>'amount','')::numeric,0);if v_invoice is null or v_alloc<=0 then raise exception 'Each allocation requires an invoice and positive amount';end if;
    select * into i from public.purchase_invoices_v484 where tenant_id=p_tenant_id and id=v_invoice and supplier_id=p_supplier_id for update;if not found then raise exception 'Supplier invoice not found';end if;if i.status not in('posted','part_paid') then raise exception 'Invoice % is not open for payment',i.invoice_number;end if;if v_alloc-i.balance_due>0.005 then raise exception 'Allocation exceeds balance on invoice %',i.invoice_number;end if;v_sum:=v_sum+v_alloc;
  end loop;
  if v_sum-p_amount>0.005 then raise exception 'Allocated amount cannot exceed payment amount';end if;
  v_no:='SPAY-'||to_char(coalesce(p_payment_date,current_date),'YYMMDD')||'-'||lpad(nextval('public.supplier_payment_number_seq_v484')::text,6,'0');
  insert into public.supplier_payments_v484(id,tenant_id,location_id,supplier_id,payment_number,payment_date,amount,payment_method,reference_number,notes,created_by)
  values(v_id,p_tenant_id,p_location_id,p_supplier_id,v_no,coalesce(p_payment_date,current_date),p_amount,lower(trim(p_payment_method)),nullif(trim(coalesce(p_reference_number,'')),''),nullif(trim(coalesce(p_notes,'')),''),auth.uid());
  for x in select value from jsonb_array_elements(coalesce(p_allocations,'[]'::jsonb)) loop
    v_invoice:=(x->>'purchase_invoice_id')::uuid;v_alloc:=(x->>'amount')::numeric;
    insert into public.supplier_payment_allocations_v484(supplier_payment_id,purchase_invoice_id,amount) values(v_id,v_invoice,v_alloc);
    perform private.v484_refresh_invoice_payment_status(v_invoice);
  end loop;
  insert into public.supplier_ledger_entries_v484(tenant_id,supplier_id,location_id,entry_date,entry_type,source_id,reference_number,description,debit,credit,created_by)
  values(p_tenant_id,p_supplier_id,p_location_id,coalesce(p_payment_date,current_date),'supplier_payment',v_id,v_no,'Supplier payment'||case when v_sum<p_amount-0.005 then ' (includes unallocated credit)' else '' end,0,p_amount,auth.uid());
  v_lines:=jsonb_build_array(
    jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_payable'),'debit',p_amount,'credit',0,'party_type','supplier','party_id',p_supplier_id,'description','Supplier payable settlement'),
    jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,lower(trim(p_payment_method))),'debit',0,'credit',p_amount,'party_type','supplier','party_id',p_supplier_id,'description','Supplier payment')
  );
  perform private.v4_journal_create(p_tenant_id,p_location_id,coalesce(p_payment_date,current_date),'Supplier Payment '||v_no,'supplier_payment_v484',v_id,v_no,v_lines);
  perform private.thq_sync_bump_v480(p_tenant_id,'accounting','supplier_payment',v_id::text,'post');
  return jsonb_build_object('success',true,'supplier_payment_id',v_id,'payment_number',v_no,'amount',p_amount,'allocated_amount',v_sum,'unallocated_amount',greatest(p_amount-v_sum,0));
end$$;
grant execute on function public.supplier_payment_create_v484(uuid,uuid,uuid,date,numeric,text,jsonb,text,text) to authenticated;

create or replace function public.supplier_payment_list_v484(p_tenant_id uuid,p_location_id uuid default null,p_supplier_id uuid default null,p_query text default '',p_limit integer default 500)
returns table(id uuid,payment_number text,payment_date date,supplier_id uuid,supplier_name text,location_id uuid,location_name text,amount numeric,allocated_amount numeric,unallocated_amount numeric,payment_method text,reference_number text,status text,created_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
 perform private.purchasing_v484_permission(p_tenant_id,false);
 return query select p.id,p.payment_number,p.payment_date,p.supplier_id,s.name,p.location_id,l.name,p.amount,coalesce(sum(a.amount),0),greatest(p.amount-coalesce(sum(a.amount),0),0),p.payment_method,p.reference_number,p.status,p.created_at
 from public.supplier_payments_v484 p join public.suppliers s on s.id=p.supplier_id join public.business_locations l on l.id=p.location_id left join public.supplier_payment_allocations_v484 a on a.supplier_payment_id=p.id
 where p.tenant_id=p_tenant_id and (p_location_id is null or p.location_id=p_location_id) and (p_supplier_id is null or p.supplier_id=p_supplier_id) and private.erp_document_scope_allowed(p_tenant_id,p.location_id,p_location_id,'view')
 and (trim(coalesce(p_query,''))='' or lower(p.payment_number) like q or lower(s.name) like q or lower(coalesce(p.reference_number,'')) like q)
 group by p.id,s.name,l.name order by p.created_at desc limit greatest(1,least(coalesce(p_limit,500),2000));
end$$;
grant execute on function public.supplier_payment_list_v484(uuid,uuid,uuid,text,integer) to authenticated;

-- Complete supplier statement: legacy purchases/payments + Purchasing V2 invoices/payments.
create or replace function public.suppliers_get_statement_v484(p_tenant_id uuid,p_supplier_id uuid,p_from date default null,p_to date default null,p_location_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_name text;v_rows jsonb;v_debit numeric;v_credit numeric;begin
 perform private.purchasing_v484_permission(p_tenant_id,false);select name into v_name from public.suppliers where tenant_id=p_tenant_id and id=p_supplier_id;if v_name is null then raise exception 'Supplier not found';end if;
 with raw as (
   select p.purchase_date::timestamp as ts,p.purchase_date entry_date,'legacy_purchase'::text entry_type,p.purchase_number reference,'Legacy purchase bill'::text description,p.grand_total::numeric debit,0::numeric credit,o.location_id
   from public.purchases p left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id and o.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and p.supplier_id=p_supplier_id and coalesce(p.status,'') not in('cancelled','void')
   union all
   select coalesce(pp.paid_at,pp.created_at),coalesce(pp.paid_at,pp.created_at)::date,'legacy_payment',p.purchase_number,'Legacy supplier payment',0::numeric,pp.amount::numeric,o.location_id
   from public.purchase_payments pp join public.purchases p on p.id=pp.purchase_id left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id and o.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and p.supplier_id=p_supplier_id
   union all
   select e.created_at,e.entry_date,e.entry_type,e.reference_number,coalesce(e.description,''),e.debit,e.credit,e.location_id from public.supplier_ledger_entries_v484 e where e.tenant_id=p_tenant_id and e.supplier_id=p_supplier_id
 ), filtered as (
   select * from raw where (p_from is null or entry_date>=p_from) and (p_to is null or entry_date<=p_to) and (p_location_id is null or location_id=p_location_id) and (location_id is null or private.erp_document_scope_allowed(p_tenant_id,location_id,p_location_id,'view'))
 ), running as (
   select *,sum(debit-credit) over(order by ts,entry_type,reference rows unbounded preceding) balance from filtered
 )
 select coalesce(jsonb_agg(jsonb_build_object('entry_date',entry_date,'entry_type',entry_type,'reference',reference,'description',description,'debit',debit,'credit',credit,'balance',balance) order by ts,entry_type,reference),'[]'::jsonb),coalesce(sum(debit),0),coalesce(sum(credit),0) into v_rows,v_debit,v_credit from running;
 return jsonb_build_object('party_id',p_supplier_id,'party_name',v_name,'opening_balance',0,'total_debit',v_debit,'total_credit',v_credit,'closing_balance',v_debit-v_credit,'rows',v_rows);
end$$;
grant execute on function public.suppliers_get_statement_v484(uuid,uuid,date,date,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(143,'4.8.4','Purchasing V2','Supplier payments with invoice allocation, Accounts Payable journals and unified legacy + V2 supplier ledger.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.4 migration 143 supplier payments and ledger applied' as status;
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
-- THQ ERP V4.8.4 — THQ API v1 Purchasing V2 contract.
begin;

create or replace function public.thq_api_contract_v480() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
  'product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json',
  'resources',jsonb_build_array(
    'sync','attention','inventory-intelligence','inventory-movements','units','product-units','pricing','product-identifiers','product-lookup','label-templates',
    'tracking-policy','serials','batches','batch-history','warranties','customer-credit','supplier-payables','reorder-suggestions',
    'purchase-requests','purchase-orders','goods-receipts','purchase-invoices','supplier-payments-v2','supplier-ledger-v2','purchase-price-history','purchasing-dashboard',
    'business-summary','store-summary'
  ),
  'core_financial_posting','direct_hardened_rpc','authoritative_sale_pricing','pricing_resolve_v482','inventory_tracking','v4.8.3',
  'purchasing_engine','v4.8.4','stock_receipt_event','goods_receipt','supplier_liability_event','purchase_invoice','mobile_ready',true
 )
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(145,'4.8.4','Purchasing V2','THQ API v1 resources for Purchase Requests, Purchase Orders, GRNs, Purchase Invoices, Supplier Payments/Ledger and Purchase Price History.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.4 migration 145 API contract applied' as status;
-- THQ ERP V4.8.4 — release contract and verification.
begin;

create or replace function public.thq_backend_contract_v47() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object('product','THQ ERP','schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),'minimum_app_version','4.8.4','release','Purchasing V2','api_version','v1')
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v484_release_verify() returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_missing text[]:='{}'::text[];begin
 if to_regclass('public.purchase_requests_v484') is null then v_missing:=array_append(v_missing,'purchase_requests_v484');end if;
 if to_regclass('public.purchase_request_items_v484') is null then v_missing:=array_append(v_missing,'purchase_request_items_v484');end if;
 if to_regclass('public.goods_receipts_v484') is null then v_missing:=array_append(v_missing,'goods_receipts_v484');end if;
 if to_regclass('public.goods_receipt_items_v484') is null then v_missing:=array_append(v_missing,'goods_receipt_items_v484');end if;
 if to_regclass('public.purchase_invoices_v484') is null then v_missing:=array_append(v_missing,'purchase_invoices_v484');end if;
 if to_regclass('public.purchase_invoice_items_v484') is null then v_missing:=array_append(v_missing,'purchase_invoice_items_v484');end if;
 if to_regclass('public.supplier_payments_v484') is null then v_missing:=array_append(v_missing,'supplier_payments_v484');end if;
 if to_regclass('public.supplier_ledger_entries_v484') is null then v_missing:=array_append(v_missing,'supplier_ledger_entries_v484');end if;
 if to_regprocedure('public.purchase_request_create_v484(uuid,uuid,jsonb,date,text,uuid,text,text)') is null then v_missing:=array_append(v_missing,'purchase_request_create_v484');end if;
 if to_regprocedure('public.purchase_request_status_v484(uuid,uuid,text,text)') is null then v_missing:=array_append(v_missing,'purchase_request_status_v484');end if;
 if to_regprocedure('public.purchase_order_create_v484(uuid,uuid,uuid,jsonb,date,text,uuid)') is null then v_missing:=array_append(v_missing,'purchase_order_create_v484');end if;
 if to_regprocedure('public.purchase_order_decide_v484(uuid,uuid,boolean,text)') is null then v_missing:=array_append(v_missing,'purchase_order_decide_v484');end if;
 if to_regprocedure('public.goods_receipt_create_v484(uuid,uuid,date,jsonb,text,text)') is null then v_missing:=array_append(v_missing,'goods_receipt_create_v484');end if;
 if to_regprocedure('public.goods_receipt_post_v484(uuid,uuid,uuid)') is null then v_missing:=array_append(v_missing,'goods_receipt_post_v484');end if;
 if to_regprocedure('public.purchase_invoice_create_v484(uuid,uuid,text,date,date,jsonb,numeric,text)') is null then v_missing:=array_append(v_missing,'purchase_invoice_create_v484');end if;
 if to_regprocedure('public.purchase_invoice_post_v484(uuid,uuid)') is null then v_missing:=array_append(v_missing,'purchase_invoice_post_v484');end if;
 if to_regprocedure('public.supplier_payment_create_v484(uuid,uuid,uuid,date,numeric,text,jsonb,text,text)') is null then v_missing:=array_append(v_missing,'supplier_payment_create_v484');end if;
 if to_regprocedure('public.suppliers_get_statement_v484(uuid,uuid,date,date,uuid)') is null then v_missing:=array_append(v_missing,'suppliers_get_statement_v484');end if;
 if to_regprocedure('public.purchase_price_history_v484(uuid,uuid,uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'purchase_price_history_v484');end if;
 return jsonb_build_object('ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'schema_version','4.8.4','migration_no',146,'api_version','v1','purchase_request',true,'purchase_order_approval',true,'grn',true,'partial_receiving',true,'damaged_rejected_receiving',true,'purchase_invoice',true,'supplier_payment',true,'supplier_ledger',true,'purchase_price_history',true);
end$$;
grant execute on function public.thq_v484_release_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(146,'4.8.4','Purchasing V2','Purchase Request, Purchase Order approval, GRN/partial/damaged/rejected receiving, Purchase Invoice, Supplier Payment/Ledger and Purchase Price History.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.4 migration 146 release contract applied' as status;
