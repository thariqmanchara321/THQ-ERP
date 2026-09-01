-- THQ ERP V4.8.3 — Serial / Batch / Warranty tracking foundation.
begin;

create table if not exists public.product_tracking_policies_v483(
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  tracking_mode text not null default 'none' check(tracking_mode in('none','serial','batch')),
  warranty_enabled boolean not null default false,
  warranty_months integer not null default 0 check(warranty_months>=0),
  warranty_days integer not null default 0 check(warranty_days>=0),
  require_batch_expiry boolean not null default false,
  allow_expired_sale boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(tenant_id,variant_id)
);
create index if not exists idx_product_tracking_policies_v483_mode on public.product_tracking_policies_v483(tenant_id,tracking_mode,variant_id);
alter table public.product_tracking_policies_v483 enable row level security;
drop policy if exists product_tracking_policies_v483_read on public.product_tracking_policies_v483;
create policy product_tracking_policies_v483_read on public.product_tracking_policies_v483 for select to authenticated using(private.erp_user_has_tenant_access(tenant_id));
revoke all on public.product_tracking_policies_v483 from anon,authenticated;

create table if not exists public.inventory_batches_v483(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  batch_number text not null,
  manufactured_on date,
  expiry_on date,
  supplier_id uuid references public.suppliers(id) on delete set null,
  first_purchase_id uuid references public.purchases(id) on delete set null,
  first_purchase_item_id uuid references public.purchase_items(id) on delete set null,
  status text not null default 'active' check(status in('active','exhausted','quarantine','recalled','archived')),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists ux_inventory_batches_v483_number on public.inventory_batches_v483(tenant_id,variant_id,lower(trim(batch_number)));
create index if not exists idx_inventory_batches_v483_expiry on public.inventory_batches_v483(tenant_id,expiry_on,variant_id) where status='active';
alter table public.inventory_batches_v483 enable row level security;
drop policy if exists inventory_batches_v483_read on public.inventory_batches_v483;
create policy inventory_batches_v483_read on public.inventory_batches_v483 for select to authenticated using(private.erp_user_has_tenant_access(tenant_id));
revoke all on public.inventory_batches_v483 from anon,authenticated;

create table if not exists public.inventory_batch_balances_v483(
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  batch_id uuid not null references public.inventory_batches_v483(id) on delete cascade,
  location_id uuid not null references public.business_locations(id) on delete cascade,
  quantity numeric not null default 0 check(quantity>=0),
  updated_at timestamptz not null default now(),
  primary key(tenant_id,batch_id,location_id)
);
create index if not exists idx_inventory_batch_balances_v483_location on public.inventory_batch_balances_v483(tenant_id,location_id,batch_id) where quantity>0;
alter table public.inventory_batch_balances_v483 enable row level security;
drop policy if exists inventory_batch_balances_v483_read on public.inventory_batch_balances_v483;
create policy inventory_batch_balances_v483_read on public.inventory_batch_balances_v483 for select to authenticated using(private.erp_user_has_tenant_access(tenant_id));
revoke all on public.inventory_batch_balances_v483 from anon,authenticated;

create table if not exists public.inventory_serials_v483(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  serial_number text not null,
  status text not null default 'in_stock' check(status in('in_stock','sold','returned','quarantine','recalled','void')),
  current_location_id uuid references public.business_locations(id) on delete set null,
  supplier_id uuid references public.suppliers(id) on delete set null,
  purchase_id uuid references public.purchases(id) on delete set null,
  purchase_item_id uuid references public.purchase_items(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  sale_id uuid references public.sales(id) on delete set null,
  sale_item_id uuid references public.sale_items(id) on delete set null,
  received_at timestamptz,
  sold_at timestamptz,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists ux_inventory_serials_v483_number on public.inventory_serials_v483(tenant_id,lower(trim(serial_number)));
create index if not exists idx_inventory_serials_v483_stock on public.inventory_serials_v483(tenant_id,current_location_id,variant_id,status);
create index if not exists idx_inventory_serials_v483_sale on public.inventory_serials_v483(tenant_id,sale_id,customer_id);
alter table public.inventory_serials_v483 enable row level security;
drop policy if exists inventory_serials_v483_read on public.inventory_serials_v483;
create policy inventory_serials_v483_read on public.inventory_serials_v483 for select to authenticated using(private.erp_user_has_tenant_access(tenant_id));
revoke all on public.inventory_serials_v483 from anon,authenticated;

create table if not exists public.inventory_trace_events_v483(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  serial_id uuid references public.inventory_serials_v483(id) on delete set null,
  batch_id uuid references public.inventory_batches_v483(id) on delete set null,
  event_type text not null check(event_type in('opening','purchase','sale','sale_return','purchase_return','transfer_in','transfer_out','adjustment','quarantine','release','void')),
  quantity numeric not null check(quantity>0),
  location_id uuid references public.business_locations(id) on delete set null,
  supplier_id uuid references public.suppliers(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  purchase_id uuid references public.purchases(id) on delete set null,
  purchase_item_id uuid references public.purchase_items(id) on delete set null,
  sale_id uuid references public.sales(id) on delete set null,
  sale_item_id uuid references public.sale_items(id) on delete set null,
  reference_number text,
  source_key text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check((serial_id is not null)::int + (batch_id is not null)::int = 1)
);
create unique index if not exists ux_inventory_trace_events_v483_source on public.inventory_trace_events_v483(tenant_id,source_key) where source_key is not null;
create index if not exists idx_inventory_trace_events_v483_serial on public.inventory_trace_events_v483(tenant_id,serial_id,created_at desc);
create index if not exists idx_inventory_trace_events_v483_batch on public.inventory_trace_events_v483(tenant_id,batch_id,created_at desc);
create index if not exists idx_inventory_trace_events_v483_document on public.inventory_trace_events_v483(tenant_id,sale_id,purchase_id,created_at desc);
alter table public.inventory_trace_events_v483 enable row level security;
drop policy if exists inventory_trace_events_v483_read on public.inventory_trace_events_v483;
create policy inventory_trace_events_v483_read on public.inventory_trace_events_v483 for select to authenticated using(private.erp_user_has_tenant_access(tenant_id));
revoke all on public.inventory_trace_events_v483 from anon,authenticated;

create table if not exists public.product_warranties_v483(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  serial_id uuid references public.inventory_serials_v483(id) on delete set null,
  batch_id uuid references public.inventory_batches_v483(id) on delete set null,
  customer_id uuid not null references public.customers(id) on delete restrict,
  sale_id uuid not null references public.sales(id) on delete restrict,
  sale_item_id uuid references public.sale_items(id) on delete set null,
  quantity numeric not null default 1 check(quantity>0),
  warranty_start date not null,
  warranty_expiry date not null,
  status text not null default 'active' check(status in('active','expired','void','replaced')),
  terms text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(serial_id is not null or batch_id is not null)
);
create unique index if not exists ux_product_warranties_v483_serial_sale on public.product_warranties_v483(tenant_id,serial_id,sale_id) where serial_id is not null and status<>'void';
create unique index if not exists ux_product_warranties_v483_batch_sale on public.product_warranties_v483(tenant_id,batch_id,sale_id,sale_item_id) where batch_id is not null and status<>'void';
create index if not exists idx_product_warranties_v483_expiry on public.product_warranties_v483(tenant_id,warranty_expiry,status);
alter table public.product_warranties_v483 enable row level security;
drop policy if exists product_warranties_v483_read on public.product_warranties_v483;
create policy product_warranties_v483_read on public.product_warranties_v483 for select to authenticated using(private.erp_user_has_tenant_access(tenant_id));
revoke all on public.product_warranties_v483 from anon,authenticated;

create or replace function private.v483_tracking_mode(p_tenant_id uuid,p_variant_id uuid) returns text
language sql stable security definer set search_path=public,private,pg_temp as $$
 select coalesce((select tracking_mode from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id),'none')
$$;
revoke all on function private.v483_tracking_mode(uuid,uuid) from public;

create or replace function public.inventory_tracking_policy_v483(p_tenant_id uuid,p_variant_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v public.product_tracking_policies_v483%rowtype;begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 if not exists(select 1 from public.product_variants where tenant_id=p_tenant_id and id=p_variant_id) then raise exception 'Product not found';end if;
 select * into v from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id;
 return jsonb_build_object(
  'variant_id',p_variant_id,'tracking_mode',coalesce(v.tracking_mode,'none'),
  'warranty_enabled',coalesce(v.warranty_enabled,false),'warranty_months',coalesce(v.warranty_months,0),'warranty_days',coalesce(v.warranty_days,0),
  'require_batch_expiry',coalesce(v.require_batch_expiry,false),'allow_expired_sale',coalesce(v.allow_expired_sale,false)
 );
end$$;
grant execute on function public.inventory_tracking_policy_v483(uuid,uuid) to authenticated;

create or replace function public.inventory_tracking_policy_save_v483(
 p_tenant_id uuid,p_variant_id uuid,p_tracking_mode text,p_warranty_enabled boolean,p_warranty_months integer,p_warranty_days integer,
 p_require_batch_expiry boolean default false,p_allow_expired_sale boolean default false
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_mode text:=lower(trim(coalesce(p_tracking_mode,'none')));v_current_mode text;begin
 if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Inventory manage permission required';end if;
 if v_mode not in('none','serial','batch') then raise exception 'Tracking mode must be none, serial or batch';end if;
 if not exists(select 1 from public.product_variants pv join public.products p on p.id=pv.product_id where pv.tenant_id=p_tenant_id and pv.id=p_variant_id and p.item_type='stock') then raise exception 'Serial/batch tracking is available only for stock products';end if;
 if coalesce(p_warranty_months,0)<0 or coalesce(p_warranty_days,0)<0 then raise exception 'Warranty period cannot be negative';end if;
 if coalesce(p_warranty_enabled,false) and v_mode='none' then raise exception 'Warranty tracking requires serial or batch tracking';end if;
 if coalesce(p_warranty_enabled,false) and coalesce(p_warranty_months,0)=0 and coalesce(p_warranty_days,0)=0 then raise exception 'Set a warranty period when warranty tracking is enabled';end if;
 select tracking_mode into v_current_mode from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id;
 if v_current_mode in('serial','batch') and v_current_mode<>v_mode and exists(select 1 from public.inventory_trace_events_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id) then
  raise exception 'Tracking mode cannot be changed after serial/batch history exists';
 end if;
 if v_mode='none' and exists(select 1 from public.inventory_serials_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id and status in('in_stock','sold','returned')) then raise exception 'Serial history exists for this product; tracking cannot be disabled';end if;
 if v_mode='none' and exists(select 1 from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.batch_id=b.id and bb.tenant_id=b.tenant_id where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and bb.quantity>0) then raise exception 'Batch stock exists for this product; tracking cannot be disabled';end if;
 insert into public.product_tracking_policies_v483(tenant_id,variant_id,tracking_mode,warranty_enabled,warranty_months,warranty_days,require_batch_expiry,allow_expired_sale,updated_at)
 values(p_tenant_id,p_variant_id,v_mode,coalesce(p_warranty_enabled,false),coalesce(p_warranty_months,0),coalesce(p_warranty_days,0),case when v_mode='batch' then coalesce(p_require_batch_expiry,false) else false end,case when v_mode='batch' then coalesce(p_allow_expired_sale,false) else false end,now())
 on conflict(tenant_id,variant_id) do update set tracking_mode=excluded.tracking_mode,warranty_enabled=excluded.warranty_enabled,warranty_months=excluded.warranty_months,warranty_days=excluded.warranty_days,require_batch_expiry=excluded.require_batch_expiry,allow_expired_sale=excluded.allow_expired_sale,updated_at=now();
 perform private.thq_sync_bump_v480(p_tenant_id,'catalogue','tracking_policy',p_variant_id::text,'save');
 return public.inventory_tracking_policy_v483(p_tenant_id,p_variant_id);
end$$;
grant execute on function public.inventory_tracking_policy_save_v483(uuid,uuid,text,boolean,integer,integer,boolean,boolean) to authenticated;

create or replace function public.inventory_list_products_v483(p_tenant_id uuid,p_location_id uuid default null) returns setof jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r jsonb;v_variant uuid;v_mode text;v_serial numeric;v_batch numeric;begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 for r in select * from public.inventory_list_products_v482(p_tenant_id,p_location_id) loop
  v_variant:=(r->>'variant_id')::uuid;v_mode:=private.v483_tracking_mode(p_tenant_id,v_variant);
  select count(*)::numeric into v_serial from public.inventory_serials_v483 s where s.tenant_id=p_tenant_id and s.variant_id=v_variant and s.status='in_stock' and (p_location_id is null or s.current_location_id=p_location_id);
  select coalesce(sum(bb.quantity),0) into v_batch from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id where b.tenant_id=p_tenant_id and b.variant_id=v_variant and (p_location_id is null or bb.location_id=p_location_id);
  return next r||jsonb_build_object('tracking_mode',v_mode,'tracked_stock_quantity',case when v_mode='serial' then coalesce(v_serial,0) when v_mode='batch' then coalesce(v_batch,0) else null end);
 end loop;
end$$;
grant execute on function public.inventory_list_products_v483(uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(135,'4.8.3','Serial / Batch / Warranty','Tracking policies, serial registry, batch registry/balances, trace event ledger and warranty register.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.3 migration 135 tracking foundation applied' as status;
