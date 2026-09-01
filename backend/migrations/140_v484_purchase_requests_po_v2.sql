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
