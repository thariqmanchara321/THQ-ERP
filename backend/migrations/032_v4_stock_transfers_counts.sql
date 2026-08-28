-- FLEXI ERP V4 stock transfers, counts, damaged/quarantine stock.
begin;

create table if not exists public.stock_transfers(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
  transfer_number text not null,from_location_id uuid not null references public.business_locations(id),to_location_id uuid not null references public.business_locations(id),
  status text not null default 'draft' check(status in('draft','requested','approved','dispatched','received','cancelled')),
  notes text,created_by uuid references auth.users(id),approved_by uuid references auth.users(id),dispatched_by uuid references auth.users(id),received_by uuid references auth.users(id),
  created_at timestamptz not null default now(),approved_at timestamptz,dispatched_at timestamptz,received_at timestamptz,
  unique(tenant_id,transfer_number),check(from_location_id<>to_location_id)
);
create table if not exists public.stock_transfer_items(
  id uuid primary key default gen_random_uuid(),transfer_id uuid not null references public.stock_transfers(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id),quantity numeric not null check(quantity>0),received_quantity numeric not null default 0 check(received_quantity>=0),note text
);
alter table public.stock_transfers enable row level security;alter table public.stock_transfer_items enable row level security;
revoke all on public.stock_transfers,public.stock_transfer_items from anon,authenticated;

create sequence if not exists public.stock_transfer_number_seq;

create or replace function public.inventory_transfer_create_v4(p_tenant_id uuid,p_from_location_id uuid,p_to_location_id uuid,p_items jsonb,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid:=gen_random_uuid();v_no text;x jsonb;begin
  perform private.v4_location_access(p_tenant_id,p_from_location_id,'operate');perform private.v4_location_access(p_tenant_id,p_to_location_id,'view');
  if not private.erp_has_permission(p_tenant_id,'inventory.transfer') and not private.erp_has_permission(p_tenant_id,'inventory.manage') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Stock transfer permission required';end if;
  v_no:='TRF-'||lpad(nextval('public.stock_transfer_number_seq')::text,6,'0');
  insert into public.stock_transfers(id,tenant_id,transfer_number,from_location_id,to_location_id,status,notes,created_by) values(v_id,p_tenant_id,v_no,p_from_location_id,p_to_location_id,'requested',nullif(trim(coalesce(p_notes,'')),''),auth.uid());
  for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    if coalesce((x->>'quantity')::numeric,0)<=0 then raise exception 'Transfer quantity must be positive';end if;
    if coalesce((select quantity-reserved_quantity-damaged_quantity-quarantine_quantity from public.location_stock_balances where tenant_id=p_tenant_id and location_id=p_from_location_id and variant_id=(x->>'variant_id')::uuid),0)<(x->>'quantity')::numeric then raise exception 'Insufficient source stock';end if;
    insert into public.stock_transfer_items(transfer_id,variant_id,quantity,note) values(v_id,(x->>'variant_id')::uuid,(x->>'quantity')::numeric,x->>'note');
  end loop;
  return jsonb_build_object('transfer_id',v_id,'transfer_number',v_no,'status','requested');
end $$;
grant execute on function public.inventory_transfer_create_v4(uuid,uuid,uuid,jsonb,text) to authenticated;

create or replace function public.inventory_transfer_dispatch_v4(p_tenant_id uuid,p_transfer_id uuid,p_device_id uuid default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v public.stock_transfers%rowtype;r record;begin
  select * into v from public.stock_transfers where id=p_transfer_id and tenant_id=p_tenant_id for update;if not found then raise exception 'Transfer not found';end if;
  perform private.v4_location_access(p_tenant_id,v.from_location_id,'operate');
  if v.status not in('requested','approved') then raise exception 'Transfer cannot be dispatched from status %',v.status;end if;
  for r in select * from public.stock_transfer_items where transfer_id=v.id loop
    -- Inter-branch transfer does not change company-wide stock; only location ledgers move.
    perform private.v4_location_stock_apply(p_tenant_id,v.from_location_id,r.variant_id,-r.quantity,'transfer_out','stock_transfer',v.id,v.transfer_number,'Dispatched',p_device_id,false);
  end loop;
  update public.stock_transfers set status='dispatched',dispatched_by=auth.uid(),dispatched_at=now() where id=v.id;
end $$;
grant execute on function public.inventory_transfer_dispatch_v4(uuid,uuid,uuid) to authenticated;

create or replace function public.inventory_transfer_receive_v4(p_tenant_id uuid,p_transfer_id uuid,p_device_id uuid default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v public.stock_transfers%rowtype;r record;begin
  select * into v from public.stock_transfers where id=p_transfer_id and tenant_id=p_tenant_id for update;if not found then raise exception 'Transfer not found';end if;
  perform private.v4_location_access(p_tenant_id,v.to_location_id,'operate');
  if v.status<>'dispatched' then raise exception 'Only dispatched transfers can be received';end if;
  for r in select * from public.stock_transfer_items where transfer_id=v.id loop
    -- Receiving completes the location-to-location move without changing global stock.
    perform public.inventory_location_assign_v4(p_tenant_id,v.to_location_id,r.variant_id,true,null,null,null);
    perform private.v4_location_stock_apply(p_tenant_id,v.to_location_id,r.variant_id,r.quantity,'transfer_in','stock_transfer',v.id,v.transfer_number,'Received',p_device_id,false);
    update public.stock_transfer_items set received_quantity=quantity where id=r.id;
  end loop;
  update public.stock_transfers set status='received',received_by=auth.uid(),received_at=now() where id=v.id;
end $$;
grant execute on function public.inventory_transfer_receive_v4(uuid,uuid,uuid) to authenticated;

create table if not exists public.stock_counts(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,location_id uuid not null references public.business_locations(id),
  count_number text not null,status text not null default 'draft' check(status in('draft','posted','cancelled')),notes text,created_by uuid references auth.users(id),posted_by uuid references auth.users(id),created_at timestamptz not null default now(),posted_at timestamptz,
  unique(tenant_id,count_number)
);
create table if not exists public.stock_count_items(
  id uuid primary key default gen_random_uuid(),count_id uuid not null references public.stock_counts(id) on delete cascade,variant_id uuid not null references public.product_variants(id),system_quantity numeric not null,counted_quantity numeric not null,variance numeric generated always as (counted_quantity-system_quantity) stored
);
alter table public.stock_counts enable row level security;alter table public.stock_count_items enable row level security;revoke all on public.stock_counts,public.stock_count_items from anon,authenticated;
create sequence if not exists public.stock_count_number_seq;

create or replace function public.inventory_stock_count_post_v4(p_tenant_id uuid,p_location_id uuid,p_items jsonb,p_notes text default null,p_device_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid:=gen_random_uuid();v_no text;x jsonb;v_current numeric;v_counted numeric;v_delta numeric;begin
  perform private.v4_location_access(p_tenant_id,p_location_id,'manage');
  if not private.erp_has_permission(p_tenant_id,'inventory.stock_count') and not private.erp_has_permission(p_tenant_id,'inventory.manage') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Stock count permission required';end if;
  v_no:='CNT-'||lpad(nextval('public.stock_count_number_seq')::text,6,'0');
  insert into public.stock_counts(id,tenant_id,location_id,count_number,status,notes,created_by) values(v_id,p_tenant_id,p_location_id,v_no,'draft',nullif(trim(coalesce(p_notes,'')),''),auth.uid());
  for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    select coalesce(quantity,0) into v_current from public.location_stock_balances where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=(x->>'variant_id')::uuid;
    v_current:=coalesce(v_current,0);v_counted:=coalesce((x->>'counted_quantity')::numeric,0);if v_counted<0 then raise exception 'Counted quantity cannot be negative';end if;v_delta:=v_counted-v_current;
    insert into public.stock_count_items(count_id,variant_id,system_quantity,counted_quantity) values(v_id,(x->>'variant_id')::uuid,v_current,v_counted);
    if v_delta<>0 then
      perform public.inventory_adjust_stock(p_tenant_id,(x->>'variant_id')::uuid,v_delta,'Stock count • '||v_no);
      perform private.v4_location_stock_apply(p_tenant_id,p_location_id,(x->>'variant_id')::uuid,v_delta,'stock_count','stock_count',v_id,v_no,'Physical stock count',p_device_id,true);
    end if;
  end loop;
  update public.stock_counts set status='posted',posted_by=auth.uid(),posted_at=now() where id=v_id;
  return jsonb_build_object('count_id',v_id,'count_number',v_no,'status','posted');
end $$;
grant execute on function public.inventory_stock_count_post_v4(uuid,uuid,jsonb,text,uuid) to authenticated;


create or replace function public.inventory_transfers_list_v4(p_tenant_id uuid,p_location_id uuid default null,p_limit integer default 100)
returns table(id uuid,transfer_number text,from_location_id uuid,from_location text,to_location_id uuid,to_location text,status text,notes text,created_at timestamptz,approved_at timestamptz,dispatched_at timestamptz,received_at timestamptz,item_count bigint,total_quantity numeric)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select t.id,t.transfer_number,t.from_location_id,fl.location_code||' • '||fl.name,t.to_location_id,tl.location_code||' • '||tl.name,t.status,t.notes,t.created_at,t.approved_at,t.dispatched_at,t.received_at,count(i.id),coalesce(sum(i.quantity),0)
  from public.stock_transfers t join public.business_locations fl on fl.id=t.from_location_id join public.business_locations tl on tl.id=t.to_location_id left join public.stock_transfer_items i on i.transfer_id=t.id
  where t.tenant_id=p_tenant_id and (p_location_id is null or t.from_location_id=p_location_id or t.to_location_id=p_location_id)
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_user_location_allowed(p_tenant_id,t.from_location_id,'view') or private.erp_user_location_allowed(p_tenant_id,t.to_location_id,'view'))
  group by t.id,fl.location_code,fl.name,tl.location_code,tl.name order by t.created_at desc limit greatest(1,least(coalesce(p_limit,100),500));
end $$;
grant execute on function public.inventory_transfers_list_v4(uuid,uuid,integer) to authenticated;

commit;
select 'Flexi ERP V4 stock transfers and counts ready' as status;
