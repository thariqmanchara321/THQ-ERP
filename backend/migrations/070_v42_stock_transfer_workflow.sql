-- FLEXI ERP V4.2
-- Reserved -> approved -> in-transit -> received stock transfer lifecycle.
begin;

alter table public.stock_transfers
  add column if not exists requested_by uuid references auth.users(id) on delete set null,
  add column if not exists requested_at timestamptz,
  add column if not exists rejected_by uuid references auth.users(id) on delete set null,
  add column if not exists rejected_at timestamptz,
  add column if not exists rejection_reason text,
  add column if not exists cancelled_by uuid references auth.users(id) on delete set null,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancel_reason text,
  add column if not exists reservation_applied boolean not null default false;

alter table public.stock_transfer_items
  add column if not exists dispatched_quantity numeric not null default 0 check(dispatched_quantity>=0);

do $$
declare c record;
begin
  for c in select conname from pg_constraint
    where conrelid='public.stock_transfers'::regclass and contype='c'
      and pg_get_constraintdef(oid) ilike '%status%'
      and pg_get_constraintdef(oid) ilike '%requested%'
  loop execute format('alter table public.stock_transfers drop constraint %I',c.conname); end loop;
end $$;

alter table public.stock_transfers
  add constraint stock_transfers_status_v42_check
  check(status in('draft','requested','approved','dispatched','received','rejected','cancelled'));

update public.stock_transfers
set requested_by=coalesce(requested_by,created_by),requested_at=coalesce(requested_at,created_at)
where status in('requested','approved','dispatched','received','rejected','cancelled');
update public.stock_transfer_items i set dispatched_quantity=i.quantity
from public.stock_transfers t where t.id=i.transfer_id and t.status in('dispatched','received') and i.dispatched_quantity=0;

create or replace function private.v42_transfer_release_reservation(p_transfer_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v record;r record;begin
  select * into v from public.stock_transfers where id=p_transfer_id for update;
  if not found or not v.reservation_applied then return;end if;
  for r in select * from public.stock_transfer_items where transfer_id=v.id loop
    if coalesce((select reserved_quantity from public.location_stock_balances
      where tenant_id=v.tenant_id and location_id=v.from_location_id and variant_id=r.variant_id for update),0)<r.quantity then
      raise exception 'Reserved transfer stock is inconsistent';
    end if;
    update public.location_stock_balances
    set reserved_quantity=reserved_quantity-r.quantity,updated_at=now()
    where tenant_id=v.tenant_id and location_id=v.from_location_id and variant_id=r.variant_id;
  end loop;
  update public.stock_transfers set reservation_applied=false where id=v.id;
end $$;
revoke all on function private.v42_transfer_release_reservation(uuid) from public;

create or replace function public.inventory_transfer_create_v42(
  p_tenant_id uuid,p_from_location_id uuid,p_to_location_id uuid,p_items jsonb,p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v_id uuid:=gen_random_uuid();v_no text;x jsonb;v_qty numeric;v_available numeric;begin
  perform private.v4_location_access(p_tenant_id,p_from_location_id,'operate');
  perform private.v4_location_access(p_tenant_id,p_to_location_id,'view');
  if p_from_location_id=p_to_location_id then raise exception 'Source and destination must be different';end if;
  if not private.erp_has_permission(p_tenant_id,'inventory.transfer') and not private.erp_has_permission(p_tenant_id,'inventory.manage') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Stock transfer permission required';end if;
  if jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception 'Add at least one transfer item';end if;

  v_no:='TRF-'||lpad(nextval('public.stock_transfer_number_seq')::text,6,'0');
  insert into public.stock_transfers(id,tenant_id,transfer_number,from_location_id,to_location_id,status,notes,created_by,requested_by,requested_at,reservation_applied)
  values(v_id,p_tenant_id,v_no,p_from_location_id,p_to_location_id,'requested',nullif(trim(coalesce(p_notes,'')),''),auth.uid(),auth.uid(),now(),true);

  for x in select value from jsonb_array_elements(p_items) loop
    v_qty:=coalesce((x->>'quantity')::numeric,0);
    if v_qty<=0 then raise exception 'Transfer quantity must be positive';end if;
    if not exists(select 1 from public.product_variants where id=(x->>'variant_id')::uuid and tenant_id=p_tenant_id) then raise exception 'Product does not belong to this business';end if;

    insert into public.location_stock_balances(tenant_id,location_id,variant_id)
    values(p_tenant_id,p_from_location_id,(x->>'variant_id')::uuid) on conflict do nothing;

    select quantity-reserved_quantity-damaged_quantity-quarantine_quantity into v_available
    from public.location_stock_balances
    where tenant_id=p_tenant_id and location_id=p_from_location_id and variant_id=(x->>'variant_id')::uuid
    for update;
    if coalesce(v_available,0)<v_qty then raise exception 'Insufficient available stock. Available: %, requested: %',coalesce(v_available,0),v_qty;end if;

    update public.location_stock_balances set reserved_quantity=reserved_quantity+v_qty,updated_at=now()
    where tenant_id=p_tenant_id and location_id=p_from_location_id and variant_id=(x->>'variant_id')::uuid;
    insert into public.stock_transfer_items(transfer_id,variant_id,quantity,note)
    values(v_id,(x->>'variant_id')::uuid,v_qty,nullif(trim(coalesce(x->>'note','')),''));
  end loop;
  return jsonb_build_object('transfer_id',v_id,'transfer_number',v_no,'status','requested');
exception when others then
  -- The surrounding transaction rolls back reservations/items automatically.
  raise;
end $$;
grant execute on function public.inventory_transfer_create_v42(uuid,uuid,uuid,jsonb,text) to authenticated;

-- Keep old clients safe: V4 calls receive the V4.2 reservation behavior.
create or replace function public.inventory_transfer_create_v4(p_tenant_id uuid,p_from_location_id uuid,p_to_location_id uuid,p_items jsonb,p_notes text default null)
returns jsonb language sql security definer set search_path=public,private,pg_temp
as $$select public.inventory_transfer_create_v42($1,$2,$3,$4,$5)$$;
grant execute on function public.inventory_transfer_create_v4(uuid,uuid,uuid,jsonb,text) to authenticated;

create or replace function public.inventory_transfer_approve_v42(p_tenant_id uuid,p_transfer_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v public.stock_transfers%rowtype;begin
  select * into v from public.stock_transfers where id=p_transfer_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Transfer not found';end if;
  perform private.v4_location_access(p_tenant_id,v.from_location_id,'manage');
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') and not private.erp_has_permission(p_tenant_id,'approvals.approve') then raise exception 'Transfer approval permission required';end if;
  if v.status<>'requested' then raise exception 'Only requested transfers can be approved';end if;
  update public.stock_transfers set status='approved',approved_by=auth.uid(),approved_at=now() where id=v.id;
end $$;
grant execute on function public.inventory_transfer_approve_v42(uuid,uuid) to authenticated;

create or replace function public.inventory_transfer_reject_v42(p_tenant_id uuid,p_transfer_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v public.stock_transfers%rowtype;begin
  select * into v from public.stock_transfers where id=p_transfer_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Transfer not found';end if;
  perform private.v4_location_access(p_tenant_id,v.from_location_id,'manage');
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') and not private.erp_has_permission(p_tenant_id,'approvals.approve') then raise exception 'Transfer approval permission required';end if;
  if v.status not in('requested','approved') then raise exception 'Transfer cannot be rejected from status %',v.status;end if;
  perform private.v42_transfer_release_reservation(v.id);
  update public.stock_transfers set status='rejected',rejected_by=auth.uid(),rejected_at=now(),rejection_reason=nullif(trim(coalesce(p_reason,'')),'') where id=v.id;
end $$;
grant execute on function public.inventory_transfer_reject_v42(uuid,uuid,text) to authenticated;

create or replace function public.inventory_transfer_cancel_v42(p_tenant_id uuid,p_transfer_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v public.stock_transfers%rowtype;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select * into v from public.stock_transfers where id=p_transfer_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Transfer not found';end if;
  perform private.v4_location_access(p_tenant_id,v.from_location_id,'view');
  if v.status not in('draft','requested','approved') then raise exception 'Dispatched/received transfers cannot be cancelled';end if;
  if auth.uid()<>v.created_by and not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Transfer cancel permission required';end if;
  perform private.v42_transfer_release_reservation(v.id);
  update public.stock_transfers set status='cancelled',cancelled_by=auth.uid(),cancelled_at=now(),cancel_reason=nullif(trim(coalesce(p_reason,'')),'') where id=v.id;
end $$;
grant execute on function public.inventory_transfer_cancel_v42(uuid,uuid,text) to authenticated;

create or replace function public.inventory_transfer_dispatch_v4(p_tenant_id uuid,p_transfer_id uuid,p_device_id uuid default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v public.stock_transfers%rowtype;r record;v_available numeric;begin
  select * into v from public.stock_transfers where id=p_transfer_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Transfer not found';end if;
  perform private.v4_location_access(p_tenant_id,v.from_location_id,'operate');
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.transfer') and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Stock transfer permission required';end if;
  if v.status<>'approved' then raise exception 'Only approved transfers can be dispatched';end if;
  for r in select * from public.stock_transfer_items where transfer_id=v.id loop
    if v.reservation_applied then
      select quantity-damaged_quantity-quarantine_quantity into v_available
      from public.location_stock_balances where tenant_id=p_tenant_id and location_id=v.from_location_id and variant_id=r.variant_id for update;
      if coalesce(v_available,0)<r.quantity then raise exception 'Insufficient source stock for dispatch';end if;
      if coalesce((select reserved_quantity from public.location_stock_balances where tenant_id=p_tenant_id and location_id=v.from_location_id and variant_id=r.variant_id),0)<r.quantity then raise exception 'Reserved transfer stock is inconsistent';end if;
      update public.location_stock_balances set reserved_quantity=greatest(0,reserved_quantity-r.quantity),updated_at=now()
      where tenant_id=p_tenant_id and location_id=v.from_location_id and variant_id=r.variant_id;
    else
      select quantity-reserved_quantity-damaged_quantity-quarantine_quantity into v_available
      from public.location_stock_balances where tenant_id=p_tenant_id and location_id=v.from_location_id and variant_id=r.variant_id for update;
      if coalesce(v_available,0)<r.quantity then raise exception 'Insufficient unreserved source stock for dispatch';end if;
    end if;
    perform private.v4_location_stock_apply(p_tenant_id,v.from_location_id,r.variant_id,-r.quantity,'transfer_out','stock_transfer',v.id,v.transfer_number,'Dispatched / in transit',p_device_id,false);
    update public.stock_transfer_items set dispatched_quantity=quantity where id=r.id;
  end loop;
  update public.stock_transfers set status='dispatched',reservation_applied=false,dispatched_by=auth.uid(),dispatched_at=now() where id=v.id;
end $$;
grant execute on function public.inventory_transfer_dispatch_v4(uuid,uuid,uuid) to authenticated;

create or replace function public.inventory_transfer_receive_v4(p_tenant_id uuid,p_transfer_id uuid,p_device_id uuid default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v public.stock_transfers%rowtype;r record;begin
  select * into v from public.stock_transfers where id=p_transfer_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Transfer not found';end if;
  perform private.v4_location_access(p_tenant_id,v.to_location_id,'operate');
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.transfer') and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Stock transfer permission required';end if;
  if v.status<>'dispatched' then raise exception 'Only dispatched transfers can be received';end if;
  for r in select * from public.stock_transfer_items where transfer_id=v.id loop
    perform private.v4_location_stock_apply(p_tenant_id,v.to_location_id,r.variant_id,r.dispatched_quantity,'transfer_in','stock_transfer',v.id,v.transfer_number,'Received',p_device_id,false);
    update public.stock_transfer_items set received_quantity=dispatched_quantity where id=r.id;
  end loop;
  update public.stock_transfers set status='received',received_by=auth.uid(),received_at=now() where id=v.id;
end $$;
grant execute on function public.inventory_transfer_receive_v4(uuid,uuid,uuid) to authenticated;

create or replace function public.inventory_transfers_list_v42(p_tenant_id uuid,p_location_id uuid default null,p_limit integer default 100)
returns table(
  id uuid,transfer_number text,from_location_id uuid,from_location text,to_location_id uuid,to_location text,status text,notes text,
  created_at timestamptz,requested_at timestamptz,approved_at timestamptz,dispatched_at timestamptz,received_at timestamptz,
  item_count bigint,total_quantity numeric,in_transit_quantity numeric,reservation_applied boolean
) language plpgsql security definer set search_path=public,private,pg_temp
as $$begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  select t.id,t.transfer_number,t.from_location_id,fl.location_code||' • '||fl.name,t.to_location_id,tl.location_code||' • '||tl.name,
    t.status,t.notes,t.created_at,t.requested_at,t.approved_at,t.dispatched_at,t.received_at,count(i.id),coalesce(sum(i.quantity),0),
    coalesce(sum(case when t.status='dispatched' then greatest(i.dispatched_quantity-i.received_quantity,0) else 0 end),0),t.reservation_applied
  from public.stock_transfers t
  join public.business_locations fl on fl.id=t.from_location_id
  join public.business_locations tl on tl.id=t.to_location_id
  left join public.stock_transfer_items i on i.transfer_id=t.id
  where t.tenant_id=p_tenant_id and (p_location_id is null or t.from_location_id=p_location_id or t.to_location_id=p_location_id)
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all') or private.erp_user_location_allowed(p_tenant_id,t.from_location_id,'view') or private.erp_user_location_allowed(p_tenant_id,t.to_location_id,'view'))
  group by t.id,fl.location_code,fl.name,tl.location_code,tl.name
  order by t.created_at desc limit greatest(1,least(coalesce(p_limit,100),500));
end $$;
grant execute on function public.inventory_transfers_list_v42(uuid,uuid,integer) to authenticated;

create or replace function public.inventory_transfer_detail_v42(p_tenant_id uuid,p_transfer_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select jsonb_build_object(
    'id',t.id,'transfer_number',t.transfer_number,'status',t.status,'notes',t.notes,
    'from_location_id',t.from_location_id,'from_location',fl.location_code||' • '||fl.name,
    'to_location_id',t.to_location_id,'to_location',tl.location_code||' • '||tl.name,
    'requested_at',t.requested_at,'approved_at',t.approved_at,'dispatched_at',t.dispatched_at,'received_at',t.received_at,
    'rejected_at',t.rejected_at,'rejection_reason',t.rejection_reason,'cancelled_at',t.cancelled_at,'cancel_reason',t.cancel_reason,
    'items',coalesce((select jsonb_agg(jsonb_build_object('variant_id',i.variant_id,'sku',pv.sku,'product_name',p.name,'quantity',i.quantity,'dispatched_quantity',i.dispatched_quantity,'received_quantity',i.received_quantity,'note',i.note) order by p.name,pv.sku)
      from public.stock_transfer_items i join public.product_variants pv on pv.id=i.variant_id join public.products p on p.id=pv.product_id where i.transfer_id=t.id),'[]'::jsonb)
  ) into v
  from public.stock_transfers t join public.business_locations fl on fl.id=t.from_location_id join public.business_locations tl on tl.id=t.to_location_id
  where t.id=p_transfer_id and t.tenant_id=p_tenant_id
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all') or private.erp_user_location_allowed(p_tenant_id,t.from_location_id,'view') or private.erp_user_location_allowed(p_tenant_id,t.to_location_id,'view'));
  if v is null then raise exception 'Transfer not found or access denied';end if;
  return v;
end $$;
grant execute on function public.inventory_transfer_detail_v42(uuid,uuid) to authenticated;

commit;
select 'Flexi ERP V4.2 stock transfer workflow ready' as status;
