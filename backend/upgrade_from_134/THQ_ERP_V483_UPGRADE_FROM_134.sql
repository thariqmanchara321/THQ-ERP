-- THQ ERP V4.8.3 — UPGRADE FROM MIGRATION 134 TO 139
-- Apply only to a database already at THQ ERP v4.8.2 / migration 134.
-- Take a database backup first. Migrations are individually transactional.

-- ============================================================================
-- 135_v483_tracking_foundation.sql
-- ============================================================================

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

-- ============================================================================
-- 136_v483_purchase_traceability.sql
-- ============================================================================

-- THQ ERP V4.8.3 — tracked opening stock and purchase receipts.
begin;

create or replace function private.v483_location_tracked_quantity(p_tenant_id uuid,p_variant_id uuid,p_location_id uuid,p_mode text) returns numeric
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v numeric;begin
 if p_mode='serial' then
  select count(*)::numeric into v from public.inventory_serials_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id and current_location_id=p_location_id and status='in_stock';
 elsif p_mode='batch' then
  select coalesce(sum(bb.quantity),0) into v from public.inventory_batch_balances_v483 bb join public.inventory_batches_v483 b on b.id=bb.batch_id and b.tenant_id=bb.tenant_id where bb.tenant_id=p_tenant_id and bb.location_id=p_location_id and b.variant_id=p_variant_id;
 else v:=0;end if;
 return coalesce(v,0);
end$$;
revoke all on function private.v483_location_tracked_quantity(uuid,uuid,uuid,text) from public;

create or replace function public.inventory_tracking_reconciliation_v483(p_tenant_id uuid,p_variant_id uuid,p_location_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_mode text;v_stock numeric;v_tracked numeric;begin
 perform private.v4_location_access(p_tenant_id,p_location_id,'view');
 if not exists(select 1 from public.product_variants where tenant_id=p_tenant_id and id=p_variant_id) then raise exception 'Product not found';end if;
 v_mode:=private.v483_tracking_mode(p_tenant_id,p_variant_id);
 select coalesce(quantity,0) into v_stock from public.location_stock_balances where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=p_variant_id;
 v_stock:=coalesce(v_stock,0);v_tracked:=private.v483_location_tracked_quantity(p_tenant_id,p_variant_id,p_location_id,v_mode);
 return jsonb_build_object('tracking_mode',v_mode,'stock_quantity',v_stock,'tracked_quantity',v_tracked,'difference',v_stock-v_tracked,'reconciled',v_mode='none' or abs(v_stock-v_tracked)<=0.000001);
end$$;
grant execute on function public.inventory_tracking_reconciliation_v483(uuid,uuid,uuid) to authenticated;

create or replace function public.inventory_tracking_register_opening_v483(
 p_tenant_id uuid,p_variant_id uuid,p_location_id uuid,p_serial_numbers jsonb default '[]'::jsonb,p_batches jsonb default '[]'::jsonb,p_note text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_mode text;v_stock numeric;v_existing numeric;v_count numeric;v_sum numeric;x jsonb;v_serial text;v_batch text;v_qty numeric;v_batch_id uuid;v_serial_id uuid;v_expiry date;v_mfg date;v_seen_serials text[]:='{}'::text[];v_seen_batches text[]:='{}'::text[];begin
 if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Inventory manage permission required';end if;
 perform private.v4_location_access(p_tenant_id,p_location_id,'manage');
 v_mode:=private.v483_tracking_mode(p_tenant_id,p_variant_id);if v_mode='none' then raise exception 'Enable serial or batch tracking first';end if;
 select coalesce(quantity,0) into v_stock from public.location_stock_balances where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=p_variant_id for update;v_stock:=coalesce(v_stock,0);
 v_existing:=private.v483_location_tracked_quantity(p_tenant_id,p_variant_id,p_location_id,v_mode);
 if abs(v_existing-v_stock)<=0.000001 then return jsonb_build_object('registered',0,'reconciled',true,'stock_quantity',v_stock,'tracked_quantity',v_existing);end if;
 if v_existing<>0 then raise exception 'Existing tracked quantity (%) does not match stock (%). Opening registration is only allowed from zero tracked quantity',v_existing,v_stock;end if;
 if v_mode='serial' then
  if v_stock<>trunc(v_stock) then raise exception 'Serial-tracked stock must be a whole base-unit quantity';end if;
  select count(*)::numeric into v_count from jsonb_array_elements(coalesce(p_serial_numbers,'[]'::jsonb));if v_count<>v_stock then raise exception 'Register exactly % serial numbers to match current stock',v_stock;end if;
  for x in select value from jsonb_array_elements(coalesce(p_serial_numbers,'[]'::jsonb)) loop
   v_serial:=trim(coalesce(case when jsonb_typeof(x)='string' then x#>>'{}' else x->>'serial_number' end,''));if v_serial='' then raise exception 'Serial number cannot be blank';end if;
   if lower(v_serial)=any(v_seen_serials) then raise exception 'Duplicate serial number % in opening registration',v_serial;end if;v_seen_serials:=array_append(v_seen_serials,lower(v_serial));
   insert into public.inventory_serials_v483(tenant_id,variant_id,serial_number,status,current_location_id,received_at,notes,created_by) values(p_tenant_id,p_variant_id,v_serial,'in_stock',p_location_id,now(),nullif(trim(coalesce(p_note,'')),''),auth.uid()) returning id into v_serial_id;
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,source_key,metadata,created_by) values(p_tenant_id,p_variant_id,v_serial_id,'opening',1,p_location_id,'opening:'||p_location_id::text||':serial:'||v_serial_id::text,jsonb_build_object('note',nullif(trim(coalesce(p_note,'')),'')),auth.uid());
  end loop;
 else
  select coalesce(sum(coalesce(nullif(value->>'quantity','')::numeric,0)),0) into v_sum from jsonb_array_elements(coalesce(p_batches,'[]'::jsonb));if abs(v_sum-v_stock)>0.000001 then raise exception 'Batch quantities must total current stock %; received %',v_stock,v_sum;end if;
  for x in select value from jsonb_array_elements(coalesce(p_batches,'[]'::jsonb)) loop
   v_batch:=trim(coalesce(x->>'batch_number',''));v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);v_expiry:=nullif(x->>'expiry_on','')::date;v_mfg:=nullif(x->>'manufactured_on','')::date;
   if v_batch='' or v_qty<=0 then raise exception 'Each batch requires a batch number and positive quantity';end if;
   if lower(v_batch)=any(v_seen_batches) then raise exception 'Duplicate batch % in opening registration',v_batch;end if;v_seen_batches:=array_append(v_seen_batches,lower(v_batch));
   if coalesce((select require_batch_expiry from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id),false) and v_expiry is null then raise exception 'Expiry date is required for batch %',v_batch;end if;
   insert into public.inventory_batches_v483(tenant_id,variant_id,batch_number,manufactured_on,expiry_on,notes,created_by) values(p_tenant_id,p_variant_id,v_batch,v_mfg,v_expiry,nullif(trim(coalesce(p_note,'')),''),auth.uid()) on conflict(tenant_id,variant_id,lower(trim(batch_number))) do update set manufactured_on=coalesce(public.inventory_batches_v483.manufactured_on,excluded.manufactured_on),expiry_on=coalesce(public.inventory_batches_v483.expiry_on,excluded.expiry_on),status='active',updated_at=now() returning id into v_batch_id;
   if exists(select 1 from public.inventory_batches_v483 where id=v_batch_id and ((manufactured_on is not null and v_mfg is not null and manufactured_on<>v_mfg) or (expiry_on is not null and v_expiry is not null and expiry_on<>v_expiry))) then raise exception 'Batch % already exists with different manufacture/expiry dates',v_batch;end if;
   insert into public.inventory_batch_balances_v483(tenant_id,batch_id,location_id,quantity) values(p_tenant_id,v_batch_id,p_location_id,v_qty) on conflict(tenant_id,batch_id,location_id) do update set quantity=public.inventory_batch_balances_v483.quantity+excluded.quantity,updated_at=now();
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,source_key,metadata,created_by) values(p_tenant_id,p_variant_id,v_batch_id,'opening',v_qty,p_location_id,'opening:'||p_location_id::text||':batch:'||v_batch_id::text,jsonb_build_object('note',nullif(trim(coalesce(p_note,'')),'')),auth.uid());
  end loop;
 end if;
 perform private.thq_sync_bump_v480(p_tenant_id,'inventory','tracking_opening',p_variant_id::text,'register');
 return public.inventory_tracking_reconciliation_v483(p_tenant_id,p_variant_id,p_location_id);
end$$;
grant execute on function public.inventory_tracking_register_opening_v483(uuid,uuid,uuid,jsonb,jsonb,text) to authenticated;

create or replace function private.v483_apply_purchase_trace(
 p_tenant_id uuid,p_purchase_id uuid,p_supplier_id uuid,p_location_id uuid,p_items jsonb
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare x jsonb;v_mode text;v_variant uuid;v_qty numeric;v_item_id uuid;v_serials jsonb;v_batches jsonb;v_count numeric;v_sum numeric;s jsonb;v_serial text;b jsonb;v_batch text;v_bqty numeric;v_mfg date;v_exp date;v_batch_id uuid;v_serial_id uuid;v_ref text;v_require boolean;v_seen_serials text[];v_seen_batches text[];begin
 if exists(select 1 from public.inventory_trace_events_v483 where tenant_id=p_tenant_id and purchase_id=p_purchase_id) then return;end if;
 select purchase_number into v_ref from public.purchases where tenant_id=p_tenant_id and id=p_purchase_id;
 for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
  v_variant:=(x->>'variant_id')::uuid;v_mode:=private.v483_tracking_mode(p_tenant_id,v_variant);if v_mode='none' then continue;end if;v_seen_serials:='{}'::text[];v_seen_batches:='{}'::text[];
  v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);select id into v_item_id from public.purchase_items where purchase_id=p_purchase_id and variant_id=v_variant limit 1;if v_item_id is null then raise exception 'Purchase line not found for tracked product';end if;
  if v_mode='serial' then
   if v_qty<>trunc(v_qty) then raise exception 'Serial-tracked product % requires whole base units',v_variant;end if;
   v_serials:=coalesce(x->'serial_numbers','[]'::jsonb);select count(*)::numeric into v_count from jsonb_array_elements(v_serials);if v_count<>v_qty then raise exception 'Provide exactly % serial numbers for tracked purchase line',v_qty;end if;
   for s in select value from jsonb_array_elements(v_serials) loop
    v_serial:=trim(coalesce(case when jsonb_typeof(s)='string' then s#>>'{}' else s->>'serial_number' end,''));if v_serial='' then raise exception 'Serial number cannot be blank';end if;
    if lower(v_serial)=any(v_seen_serials) then raise exception 'Duplicate serial number % on tracked purchase line',v_serial;end if;v_seen_serials:=array_append(v_seen_serials,lower(v_serial));
    insert into public.inventory_serials_v483(tenant_id,variant_id,serial_number,status,current_location_id,supplier_id,purchase_id,purchase_item_id,received_at,created_by) values(p_tenant_id,v_variant,v_serial,'in_stock',p_location_id,p_supplier_id,p_purchase_id,v_item_id,now(),auth.uid()) returning id into v_serial_id;
    insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,supplier_id,purchase_id,purchase_item_id,reference_number,source_key,created_by) values(p_tenant_id,v_variant,v_serial_id,'purchase',1,p_location_id,p_supplier_id,p_purchase_id,v_item_id,v_ref,'purchase:'||p_purchase_id::text||':serial:'||v_serial_id::text,auth.uid());
   end loop;
  else
   v_batches:=coalesce(x->'batches','[]'::jsonb);select coalesce(sum(coalesce(nullif(value->>'quantity','')::numeric,0)),0) into v_sum from jsonb_array_elements(v_batches);if abs(v_sum-v_qty)>0.000001 then raise exception 'Batch quantities must total base quantity %; received %',v_qty,v_sum;end if;
   select require_batch_expiry into v_require from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=v_variant;
   for b in select value from jsonb_array_elements(v_batches) loop
    v_batch:=trim(coalesce(b->>'batch_number',''));v_bqty:=coalesce(nullif(b->>'quantity','')::numeric,0);v_mfg:=nullif(b->>'manufactured_on','')::date;v_exp:=nullif(b->>'expiry_on','')::date;
    if v_batch='' or v_bqty<=0 then raise exception 'Each batch requires a batch number and positive quantity';end if;if lower(v_batch)=any(v_seen_batches) then raise exception 'Duplicate batch % on tracked purchase line',v_batch;end if;v_seen_batches:=array_append(v_seen_batches,lower(v_batch));if coalesce(v_require,false) and v_exp is null then raise exception 'Expiry date is required for batch %',v_batch;end if;
    insert into public.inventory_batches_v483(tenant_id,variant_id,batch_number,manufactured_on,expiry_on,supplier_id,first_purchase_id,first_purchase_item_id,created_by) values(p_tenant_id,v_variant,v_batch,v_mfg,v_exp,p_supplier_id,p_purchase_id,v_item_id,auth.uid())
    on conflict(tenant_id,variant_id,lower(trim(batch_number))) do update set manufactured_on=coalesce(public.inventory_batches_v483.manufactured_on,excluded.manufactured_on),expiry_on=coalesce(public.inventory_batches_v483.expiry_on,excluded.expiry_on),supplier_id=coalesce(public.inventory_batches_v483.supplier_id,excluded.supplier_id),status='active',updated_at=now() returning id into v_batch_id;
    if exists(select 1 from public.inventory_batches_v483 where id=v_batch_id and ((manufactured_on is not null and v_mfg is not null and manufactured_on<>v_mfg) or (expiry_on is not null and v_exp is not null and expiry_on<>v_exp))) then raise exception 'Batch % already exists with different manufacture/expiry dates',v_batch;end if;
    insert into public.inventory_batch_balances_v483(tenant_id,batch_id,location_id,quantity) values(p_tenant_id,v_batch_id,p_location_id,v_bqty) on conflict(tenant_id,batch_id,location_id) do update set quantity=public.inventory_batch_balances_v483.quantity+excluded.quantity,updated_at=now();
    insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,supplier_id,purchase_id,purchase_item_id,reference_number,source_key,created_by) values(p_tenant_id,v_variant,v_batch_id,'purchase',v_bqty,p_location_id,p_supplier_id,p_purchase_id,v_item_id,v_ref,'purchase:'||p_purchase_id::text||':item:'||v_item_id::text||':batch:'||v_batch_id::text,auth.uid());
   end loop;
  end if;
 end loop;
end$$;
revoke all on function private.v483_apply_purchase_trace(uuid,uuid,uuid,uuid,jsonb) from public;

create or replace function public.purchases_create_v483(
 p_tenant_id uuid,p_supplier_id uuid,p_supplier_invoice_number text,p_purchase_date date,p_due_date date,p_items jsonb,p_additional_charges numeric,p_initial_payment numeric,p_payment_method text,p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_normalized jsonb;v_result jsonb;v_purchase uuid;x jsonb;v_variant uuid;v_mode text;v_recon jsonb;begin
 v_normalized:=private.v481_normalize_items(p_tenant_id,p_items,'purchase');
 -- A tracking policy may be enabled while legacy stock is still unregistered. Do not
 -- receive more tracked stock until the current location is reconciled, otherwise the
 -- opening quantity can no longer be registered unambiguously.
 for x in select value from jsonb_array_elements(v_normalized) loop
  v_variant:=(x->>'variant_id')::uuid;v_mode:=private.v483_tracking_mode(p_tenant_id,v_variant);
  if v_mode<>'none' then
   v_recon:=public.inventory_tracking_reconciliation_v483(p_tenant_id,v_variant,p_location_id);
   if not coalesce((v_recon->>'reconciled')::boolean,false) then
    raise exception 'Register existing serial/batch opening stock before receiving product % at this store',v_variant;
   end if;
  end if;
 end loop;
 v_result:=public.purchases_create_v481(p_tenant_id,p_supplier_id,p_supplier_invoice_number,p_purchase_date,p_due_date,p_items,p_additional_charges,p_initial_payment,p_payment_method,p_notes,p_location_id,p_device_id,p_request_id);
 v_purchase:=nullif(v_result->>'purchase_id','')::uuid;
 if v_purchase is not null then perform private.v483_apply_purchase_trace(p_tenant_id,v_purchase,p_supplier_id,p_location_id,v_normalized);end if;
 return v_result||jsonb_build_object('tracking_engine','v4.8.3');
end$$;
grant execute on function public.purchases_create_v483(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(136,'4.8.3','Serial / Batch / Warranty','Opening-stock trace registration and trace-aware purchase receipt posting.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.3 migration 136 purchase traceability applied' as status;

-- ============================================================================
-- 137_v483_sales_warranty.sql
-- ============================================================================

-- THQ ERP V4.8.3 — trace-aware sales, FEFO batch allocation and warranty creation.
begin;

create or replace function private.v483_assert_reconciled(p_tenant_id uuid,p_variant_id uuid,p_location_id uuid) returns void
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_mode text;v_stock numeric;v_tracked numeric;begin
 v_mode:=private.v483_tracking_mode(p_tenant_id,p_variant_id);if v_mode='none' then return;end if;
 select coalesce(quantity,0) into v_stock from public.location_stock_balances where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=p_variant_id;
 v_stock:=coalesce(v_stock,0);v_tracked:=private.v483_location_tracked_quantity(p_tenant_id,p_variant_id,p_location_id,v_mode);
 if abs(v_stock-v_tracked)>0.000001 then raise exception 'Tracked stock is not reconciled for product %. Ledger %, tracked %. Register/fix serial or batch opening stock before posting',p_variant_id,v_stock,v_tracked;end if;
end$$;
revoke all on function private.v483_assert_reconciled(uuid,uuid,uuid) from public;

create or replace function private.v483_create_warranty(
 p_tenant_id uuid,p_variant_id uuid,p_serial_id uuid,p_batch_id uuid,p_customer_id uuid,p_sale_id uuid,p_sale_item_id uuid,p_quantity numeric,p_sale_date date
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_enabled boolean;v_months integer;v_days integer;v_expiry date;begin
 select warranty_enabled,warranty_months,warranty_days into v_enabled,v_months,v_days from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id;
 if not coalesce(v_enabled,false) then return;end if;
 v_expiry:=(p_sale_date+make_interval(months=>coalesce(v_months,0),days=>coalesce(v_days,0)))::date;
 insert into public.product_warranties_v483(tenant_id,variant_id,serial_id,batch_id,customer_id,sale_id,sale_item_id,quantity,warranty_start,warranty_expiry,status,created_by)
 values(p_tenant_id,p_variant_id,p_serial_id,p_batch_id,p_customer_id,p_sale_id,p_sale_item_id,p_quantity,p_sale_date,v_expiry,'active',auth.uid()) on conflict do nothing;
end$$;
revoke all on function private.v483_create_warranty(uuid,uuid,uuid,uuid,uuid,uuid,uuid,numeric,date) from public;

create or replace function private.v483_apply_batch_sale(
 p_tenant_id uuid,p_variant_id uuid,p_sale_id uuid,p_sale_item_id uuid,p_customer_id uuid,p_location_id uuid,p_sale_date date,p_quantity numeric,p_requested jsonb
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_remaining numeric:=p_quantity;v_out jsonb:='[]'::jsonb;v_allow_expired boolean:=false;r record;x jsonb;v_batch_id uuid;v_take numeric;v_requested_qty numeric;v_batch_number text;v_seen uuid[]:='{}'::uuid[];v_ref text;begin
 select allow_expired_sale into v_allow_expired from public.product_tracking_policies_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id;
 select sale_number into v_ref from public.sales where tenant_id=p_tenant_id and id=p_sale_id;
 if jsonb_array_length(coalesce(p_requested,'[]'::jsonb))>0 then
  for x in select value from jsonb_array_elements(p_requested) loop
   v_requested_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);if v_requested_qty<=0 then raise exception 'Requested batch quantity must be positive';end if;
   if nullif(x->>'batch_id','') is not null then v_batch_id:=(x->>'batch_id')::uuid;else
    v_batch_number:=trim(coalesce(x->>'batch_number',''));select id into v_batch_id from public.inventory_batches_v483 where tenant_id=p_tenant_id and variant_id=p_variant_id and lower(trim(batch_number))=lower(v_batch_number);end if;
   if v_batch_id is null then raise exception 'Batch not found for tracked product';end if;
   if v_batch_id=any(v_seen) then raise exception 'The same batch cannot appear twice on one sale line';end if;v_seen:=array_append(v_seen,v_batch_id);
   select b.batch_number,b.expiry_on,bb.quantity into r from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id where b.tenant_id=p_tenant_id and b.id=v_batch_id and b.variant_id=p_variant_id and bb.location_id=p_location_id and b.status='active' for update of bb;
   if not found or coalesce(r.quantity,0)<v_requested_qty then raise exception 'Insufficient quantity in selected batch %',coalesce(r.batch_number,v_batch_number);end if;
   if not coalesce(v_allow_expired,false) and r.expiry_on is not null and r.expiry_on<p_sale_date then raise exception 'Batch % expired on %',r.batch_number,r.expiry_on;end if;
   update public.inventory_batch_balances_v483 set quantity=quantity-v_requested_qty,updated_at=now() where tenant_id=p_tenant_id and batch_id=v_batch_id and location_id=p_location_id;
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,customer_id,sale_id,sale_item_id,reference_number,source_key,created_by) values(p_tenant_id,p_variant_id,v_batch_id,'sale',v_requested_qty,p_location_id,p_customer_id,p_sale_id,p_sale_item_id,v_ref,'sale:'||p_sale_id::text||':item:'||p_sale_item_id::text||':batch:'||v_batch_id::text,auth.uid());
   perform private.v483_create_warranty(p_tenant_id,p_variant_id,null,v_batch_id,p_customer_id,p_sale_id,p_sale_item_id,v_requested_qty,p_sale_date);
   v_remaining:=v_remaining-v_requested_qty;v_out:=v_out||jsonb_build_array(jsonb_build_object('batch_id',v_batch_id,'batch_number',r.batch_number,'quantity',v_requested_qty,'expiry_on',r.expiry_on));
  end loop;
  if abs(v_remaining)>0.000001 then raise exception 'Selected batch quantities must equal required base quantity %',p_quantity;end if;
 else
  for r in select b.id batch_id,b.batch_number,b.expiry_on,bb.quantity from public.inventory_batches_v483 b join public.inventory_batch_balances_v483 bb on bb.tenant_id=b.tenant_id and bb.batch_id=b.id where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and bb.location_id=p_location_id and bb.quantity>0 and b.status='active' and (coalesce(v_allow_expired,false) or b.expiry_on is null or b.expiry_on>=p_sale_date) order by (b.expiry_on is null),b.expiry_on,b.created_at,b.batch_number for update of bb loop
   exit when v_remaining<=0.000001;v_take:=least(v_remaining,r.quantity);
   update public.inventory_batch_balances_v483 set quantity=quantity-v_take,updated_at=now() where tenant_id=p_tenant_id and batch_id=r.batch_id and location_id=p_location_id;
   insert into public.inventory_trace_events_v483(tenant_id,variant_id,batch_id,event_type,quantity,location_id,customer_id,sale_id,sale_item_id,reference_number,source_key,metadata,created_by) values(p_tenant_id,p_variant_id,r.batch_id,'sale',v_take,p_location_id,p_customer_id,p_sale_id,p_sale_item_id,v_ref,'sale:'||p_sale_id::text||':item:'||p_sale_item_id::text||':batch:'||r.batch_id::text,jsonb_build_object('allocation','FEFO'),auth.uid());
   perform private.v483_create_warranty(p_tenant_id,p_variant_id,null,r.batch_id,p_customer_id,p_sale_id,p_sale_item_id,v_take,p_sale_date);
   v_remaining:=v_remaining-v_take;v_out:=v_out||jsonb_build_array(jsonb_build_object('batch_id',r.batch_id,'batch_number',r.batch_number,'quantity',v_take,'expiry_on',r.expiry_on));
  end loop;
  if v_remaining>0.000001 then raise exception 'Insufficient eligible batch stock. Required %, unavailable %',p_quantity,v_remaining;end if;
 end if;
 update public.inventory_batches_v483 b set status='exhausted',updated_at=now() where b.tenant_id=p_tenant_id and b.variant_id=p_variant_id and b.status='active' and not exists(select 1 from public.inventory_batch_balances_v483 bb where bb.tenant_id=b.tenant_id and bb.batch_id=b.id and bb.quantity>0);
 return v_out;
end$$;
revoke all on function private.v483_apply_batch_sale(uuid,uuid,uuid,uuid,uuid,uuid,date,numeric,jsonb) from public;

create or replace function private.v483_apply_sale_trace(
 p_tenant_id uuid,p_sale_id uuid,p_customer_id uuid,p_location_id uuid,p_sale_date date,p_items jsonb
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare x jsonb;v_mode text;v_variant uuid;v_qty numeric;v_item_id uuid;v_serials jsonb;v_count numeric;s jsonb;v_serial text;v_serial_id uuid;v_ref text;v_batches jsonb;begin
 if exists(select 1 from public.inventory_trace_events_v483 where tenant_id=p_tenant_id and sale_id=p_sale_id) then return;end if;
 select sale_number into v_ref from public.sales where tenant_id=p_tenant_id and id=p_sale_id;
 for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
  v_variant:=(x->>'variant_id')::uuid;v_mode:=private.v483_tracking_mode(p_tenant_id,v_variant);if v_mode='none' then continue;end if;
  v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);select id into v_item_id from public.sale_items where sale_id=p_sale_id and variant_id=v_variant limit 1;if v_item_id is null then raise exception 'Sale line not found for tracked product';end if;
  if v_mode='serial' then
   if v_qty<>trunc(v_qty) then raise exception 'Serial-tracked product % requires whole base units',v_variant;end if;
   v_serials:=coalesce(x->'serial_numbers','[]'::jsonb);select count(*)::numeric into v_count from jsonb_array_elements(v_serials);if v_count<>v_qty then raise exception 'Provide exactly % serial numbers for tracked sale line',v_qty;end if;
   for s in select value from jsonb_array_elements(v_serials) loop
    v_serial:=trim(coalesce(case when jsonb_typeof(s)='string' then s#>>'{}' else s->>'serial_number' end,''));
    select id into v_serial_id from public.inventory_serials_v483 where tenant_id=p_tenant_id and variant_id=v_variant and current_location_id=p_location_id and status='in_stock' and lower(trim(serial_number))=lower(v_serial) for update;
    if v_serial_id is null then raise exception 'Serial % is not available at the selected store',v_serial;end if;
    update public.inventory_serials_v483 set status='sold',current_location_id=null,customer_id=p_customer_id,sale_id=p_sale_id,sale_item_id=v_item_id,sold_at=now(),updated_at=now() where id=v_serial_id;
    insert into public.inventory_trace_events_v483(tenant_id,variant_id,serial_id,event_type,quantity,location_id,customer_id,sale_id,sale_item_id,reference_number,source_key,created_by) values(p_tenant_id,v_variant,v_serial_id,'sale',1,p_location_id,p_customer_id,p_sale_id,v_item_id,v_ref,'sale:'||p_sale_id::text||':serial:'||v_serial_id::text,auth.uid());
    perform private.v483_create_warranty(p_tenant_id,v_variant,v_serial_id,null,p_customer_id,p_sale_id,v_item_id,1,p_sale_date);
   end loop;
  else
   v_batches:=coalesce(x->'batches','[]'::jsonb);perform private.v483_apply_batch_sale(p_tenant_id,v_variant,p_sale_id,v_item_id,p_customer_id,p_location_id,p_sale_date,v_qty,v_batches);
  end if;
 end loop;
end$$;
revoke all on function private.v483_apply_sale_trace(uuid,uuid,uuid,uuid,date,jsonb) from public;

create or replace function public.sales_create_v483(
 p_tenant_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,p_items jsonb,p_additional_charges numeric,p_initial_payment numeric,p_payment_method text,p_payment_reference text,p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_normalized jsonb;v_result jsonb;v_sale uuid;x jsonb;v_variant uuid;v_mode text;v_serials jsonb;v_count numeric;v_qty numeric;begin
 v_normalized:=private.v481_normalize_items(p_tenant_id,p_items,'sale');
 for x in select value from jsonb_array_elements(v_normalized) loop
  v_variant:=(x->>'variant_id')::uuid;v_mode:=private.v483_tracking_mode(p_tenant_id,v_variant);if v_mode='none' then continue;end if;perform private.v483_assert_reconciled(p_tenant_id,v_variant,p_location_id);
  if v_mode='serial' then v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);v_serials:=coalesce(x->'serial_numbers','[]'::jsonb);select count(*)::numeric into v_count from jsonb_array_elements(v_serials);if v_count<>v_qty then raise exception 'Provide exactly % serial numbers for serial-tracked product',v_qty;end if;end if;
 end loop;
 v_result:=public.sales_create_v482(p_tenant_id,p_customer_id,p_sale_date,p_due_date,p_items,p_additional_charges,p_initial_payment,p_payment_method,p_payment_reference,p_notes,p_location_id,p_device_id,p_request_id);
 v_sale:=nullif(v_result->>'sale_id','')::uuid;if v_sale is not null then perform private.v483_apply_sale_trace(p_tenant_id,v_sale,p_customer_id,p_location_id,p_sale_date,v_normalized);end if;
 return v_result||jsonb_build_object('tracking_engine','v4.8.3');
end$$;
grant execute on function public.sales_create_v483(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text) to authenticated;

create or replace function public.inventory_adjust_stock_v483(p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_variant_id uuid,p_quantity_delta numeric,p_note text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$begin
 if private.v483_tracking_mode(p_tenant_id,p_variant_id)<>'none' then raise exception 'Use serial/batch trace operations for tracked products. Generic stock adjustment is blocked in v4.8.3';end if;
 return public.inventory_adjust_stock_v47(p_tenant_id,p_location_id,p_device_id,p_variant_id,p_quantity_delta,p_note,p_request_id);
end$$;
grant execute on function public.inventory_adjust_stock_v483(uuid,uuid,uuid,uuid,numeric,text,text) to authenticated;

create or replace function public.inventory_stock_count_post_v483(p_tenant_id uuid,p_location_id uuid,p_items jsonb,p_notes text,p_device_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$declare x jsonb;begin
 for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop if private.v483_tracking_mode(p_tenant_id,(x->>'variant_id')::uuid)<>'none' then raise exception 'Stock count for serial/batch products requires trace allocation and is blocked in v4.8.3';end if;end loop;
 return public.inventory_stock_count_post_v4(p_tenant_id,p_location_id,p_items,p_notes,p_device_id);
end$$;
grant execute on function public.inventory_stock_count_post_v483(uuid,uuid,jsonb,text,uuid) to authenticated;


create or replace function public.inventory_transfer_create_v483(p_tenant_id uuid,p_from_location_id uuid,p_to_location_id uuid,p_items jsonb,p_notes text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$declare x jsonb;begin
 for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
  if private.v483_tracking_mode(p_tenant_id,(x->>'variant_id')::uuid)<>'none' then raise exception 'Transfers for serial/batch products require trace allocation and are blocked in v4.8.3';end if;
 end loop;
 return public.inventory_transfer_create_v47(p_tenant_id,p_from_location_id,p_to_location_id,p_items,p_notes,p_request_id);
end$$;
grant execute on function public.inventory_transfer_create_v483(uuid,uuid,uuid,jsonb,text,text) to authenticated;

create or replace function public.sales_return_create_v483(p_tenant_id uuid,p_sale_id uuid,p_items jsonb,p_reason text,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$declare x jsonb;v_variant uuid;begin
 for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
  select variant_id into v_variant from public.sale_items where id=(x->>'sale_item_id')::uuid and sale_id=p_sale_id;
  if v_variant is null then raise exception 'Sale item not found';end if;
  if private.v483_tracking_mode(p_tenant_id,v_variant)<>'none' then raise exception 'Returns for serial/batch products require trace allocation and are blocked in v4.8.3';end if;
 end loop;
 return public.sales_return_create_v481(p_tenant_id,p_sale_id,p_items,p_reason,p_device_id,p_request_id);
end$$;
grant execute on function public.sales_return_create_v483(uuid,uuid,jsonb,text,uuid,text) to authenticated;

create or replace function public.purchase_return_create_v483(p_tenant_id uuid,p_purchase_id uuid,p_items jsonb,p_reason text,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$declare x jsonb;v_variant uuid;begin
 for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
  select variant_id into v_variant from public.purchase_items where id=(x->>'purchase_item_id')::uuid and purchase_id=p_purchase_id;
  if v_variant is null then raise exception 'Purchase item not found';end if;
  if private.v483_tracking_mode(p_tenant_id,v_variant)<>'none' then raise exception 'Returns for serial/batch products require trace allocation and are blocked in v4.8.3';end if;
 end loop;
 return public.purchase_return_create_v481(p_tenant_id,p_purchase_id,p_items,p_reason,p_device_id,p_request_id);
end$$;
grant execute on function public.purchase_return_create_v483(uuid,uuid,jsonb,text,uuid,text) to authenticated;

create or replace function public.sales_void_v483(p_tenant_id uuid,p_sale_id uuid,p_reason text,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$begin
 if exists(select 1 from public.sale_items si where si.sale_id=p_sale_id and private.v483_tracking_mode(p_tenant_id,si.variant_id)<>'none') then raise exception 'Voiding a sale containing serial/batch products requires trace reversal and is blocked in v4.8.3';end if;
 return public.sales_void_v47(p_tenant_id,p_sale_id,p_reason,p_device_id,p_request_id);
end$$;
grant execute on function public.sales_void_v483(uuid,uuid,text,uuid,text) to authenticated;

create or replace function public.purchase_void_v483(p_tenant_id uuid,p_purchase_id uuid,p_reason text,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$begin
 if exists(select 1 from public.purchase_items pi where pi.purchase_id=p_purchase_id and private.v483_tracking_mode(p_tenant_id,pi.variant_id)<>'none') then raise exception 'Voiding a purchase containing serial/batch products requires trace reversal and is blocked in v4.8.3';end if;
 return public.purchase_void_v47(p_tenant_id,p_purchase_id,p_reason,p_device_id,p_request_id);
end$$;
grant execute on function public.purchase_void_v483(uuid,uuid,text,uuid,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(137,'4.8.3','Serial / Batch / Warranty','Trace-aware sales, FEFO batch allocation, warranty creation and safe guardrails for generic inventory edits.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.3 migration 137 sales and warranty applied' as status;

-- ============================================================================
-- 138_v483_trace_search_history.sql
-- ============================================================================

-- THQ ERP V4.8.3 — serial search, batch history, warranty register and lookup APIs.
begin;

create or replace function private.v483_trace_view_allowed(p_tenant_id uuid) returns boolean
language sql stable security definer set search_path=public,private,pg_temp as $$
 select private.erp_user_is_owner(p_tenant_id)
     or private.erp_has_permission(p_tenant_id,'inventory.view')
     or private.erp_has_permission(p_tenant_id,'inventory.manage')
     or private.erp_has_permission(p_tenant_id,'sales.view')
     or private.erp_has_permission(p_tenant_id,'sales.manage')
     or private.erp_has_permission(p_tenant_id,'purchases.view')
     or private.erp_has_permission(p_tenant_id,'purchases.manage')
$$;
revoke all on function private.v483_trace_view_allowed(uuid) from public;

create or replace function public.inventory_serial_search_v483(
 p_tenant_id uuid,p_query text default '',p_location_id uuid default null,p_limit integer default 200
) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
 if not private.erp_user_has_tenant_access(p_tenant_id) or not private.v483_trace_view_allowed(p_tenant_id) then raise exception 'Traceability view permission required';end if;
 return query
 select jsonb_build_object(
  'serial_id',s.id,'serial_number',s.serial_number,'status',s.status,'variant_id',s.variant_id,
  'product_name',p.name,'variant_name',pv.variant_name,'sku',pv.sku,
  'location_id',coalesce(s.current_location_id,so.location_id,po.location_id),
  'location_name',coalesce(l.name,sl.name,pl.name),
  'supplier_id',s.supplier_id,'supplier_name',sup.name,'purchase_id',s.purchase_id,'purchase_number',pur.purchase_number,
  'customer_id',s.customer_id,'customer_name',c.name,'sale_id',s.sale_id,'sale_number',sa.sale_number,
  'received_at',s.received_at,'sold_at',s.sold_at,
  'warranty_start',w.warranty_start,'warranty_expiry',w.warranty_expiry,
  'warranty_status',case when w.status='active' and w.warranty_expiry<current_date then 'expired' else w.status end
 )
 from public.inventory_serials_v483 s
 join public.product_variants pv on pv.id=s.variant_id and pv.tenant_id=s.tenant_id
 join public.products p on p.id=pv.product_id
 left join public.business_locations l on l.id=s.current_location_id
 left join public.suppliers sup on sup.id=s.supplier_id
 left join public.purchases pur on pur.id=s.purchase_id
 left join public.customers c on c.id=s.customer_id
 left join public.sales sa on sa.id=s.sale_id
 left join public.document_origins so on so.tenant_id=s.tenant_id and so.entity_type='sale' and so.entity_id=s.sale_id
 left join public.document_origins po on po.tenant_id=s.tenant_id and po.entity_type='purchase' and po.entity_id=s.purchase_id
 left join public.business_locations sl on sl.id=so.location_id
 left join public.business_locations pl on pl.id=po.location_id
 left join lateral(
  select x.* from public.product_warranties_v483 x
  where x.tenant_id=s.tenant_id and x.serial_id=s.id and x.status<>'void'
  order by x.created_at desc limit 1
 ) w on true
 where s.tenant_id=p_tenant_id
 and private.erp_document_scope_allowed(p_tenant_id,coalesce(s.current_location_id,so.location_id,po.location_id),p_location_id,'view')
 and (
  trim(coalesce(p_query,''))='' or lower(s.serial_number) like q or lower(coalesce(p.name,'')) like q or
  lower(coalesce(pv.sku,'')) like q or lower(coalesce(sup.name,'')) like q or lower(coalesce(c.name,'')) like q or
  lower(coalesce(pur.purchase_number,'')) like q or lower(coalesce(sa.sale_number,'')) like q
 )
 order by s.updated_at desc
 limit greatest(1,least(coalesce(p_limit,200),1000));
end$$;
grant execute on function public.inventory_serial_search_v483(uuid,text,uuid,integer) to authenticated;

create or replace function public.inventory_batch_search_v483(
 p_tenant_id uuid,p_query text default '',p_location_id uuid default null,p_limit integer default 200
) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
 if not private.erp_user_has_tenant_access(p_tenant_id) or not private.v483_trace_view_allowed(p_tenant_id) then raise exception 'Traceability view permission required';end if;
 return query
 select jsonb_build_object(
  'batch_id',b.id,'batch_number',b.batch_number,'status',b.status,'variant_id',b.variant_id,
  'product_name',p.name,'variant_name',pv.variant_name,'sku',pv.sku,
  'manufactured_on',b.manufactured_on,'expiry_on',b.expiry_on,
  'expired',b.expiry_on is not null and b.expiry_on<current_date,
  'supplier_id',b.supplier_id,'supplier_name',sup.name,'purchase_id',b.first_purchase_id,'purchase_number',pur.purchase_number,
  'quantity',coalesce(sum(bb.quantity),0),
  'locations',coalesce(
    jsonb_agg(distinct jsonb_build_object('location_id',bb.location_id,'location_name',l.name,'quantity',bb.quantity))
      filter(where bb.location_id is not null),
    '[]'::jsonb
  )
 )
 from public.inventory_batches_v483 b
 join public.product_variants pv on pv.id=b.variant_id and pv.tenant_id=b.tenant_id
 join public.products p on p.id=pv.product_id
 left join public.inventory_batch_balances_v483 bb
   on bb.tenant_id=b.tenant_id and bb.batch_id=b.id
  and private.erp_document_scope_allowed(p_tenant_id,bb.location_id,p_location_id,'view')
 left join public.business_locations l on l.id=bb.location_id
 left join public.suppliers sup on sup.id=b.supplier_id
 left join public.purchases pur on pur.id=b.first_purchase_id
 where b.tenant_id=p_tenant_id
 and (
   exists(
    select 1 from public.inventory_batch_balances_v483 ab
    where ab.tenant_id=b.tenant_id and ab.batch_id=b.id
      and private.erp_document_scope_allowed(p_tenant_id,ab.location_id,p_location_id,'view')
   )
   or exists(
    select 1 from public.inventory_trace_events_v483 ae
    where ae.tenant_id=b.tenant_id and ae.batch_id=b.id
      and private.erp_document_scope_allowed(p_tenant_id,ae.location_id,p_location_id,'view')
   )
 )
 and (
  trim(coalesce(p_query,''))='' or lower(b.batch_number) like q or lower(coalesce(p.name,'')) like q or
  lower(coalesce(pv.sku,'')) like q or lower(coalesce(sup.name,'')) like q or exists(
   select 1
   from public.inventory_trace_events_v483 e
   left join public.customers c on c.id=e.customer_id
   left join public.sales s on s.id=e.sale_id
   left join public.purchases pp on pp.id=e.purchase_id
   where e.tenant_id=b.tenant_id and e.batch_id=b.id
     and private.erp_document_scope_allowed(p_tenant_id,e.location_id,p_location_id,'view')
     and (
       lower(coalesce(c.name,'')) like q or lower(coalesce(s.sale_number,'')) like q or
       lower(coalesce(pp.purchase_number,'')) like q or lower(coalesce(e.reference_number,'')) like q
     )
  )
 )
 group by b.id,p.name,pv.variant_name,pv.sku,sup.name,pur.purchase_number
 order by b.updated_at desc
 limit greatest(1,least(coalesce(p_limit,200),1000));
end$$;
grant execute on function public.inventory_batch_search_v483(uuid,text,uuid,integer) to authenticated;

create or replace function public.inventory_batch_history_v483(p_tenant_id uuid,p_batch_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v jsonb;begin
 if not private.erp_user_has_tenant_access(p_tenant_id) or not private.v483_trace_view_allowed(p_tenant_id) then raise exception 'Traceability view permission required';end if;
 if not exists(
  select 1 from public.inventory_batch_balances_v483 bb
  where bb.tenant_id=p_tenant_id and bb.batch_id=p_batch_id
    and private.erp_document_scope_allowed(p_tenant_id,bb.location_id,null,'view')
  union all
  select 1 from public.inventory_trace_events_v483 e
  where e.tenant_id=p_tenant_id and e.batch_id=p_batch_id
    and private.erp_document_scope_allowed(p_tenant_id,e.location_id,null,'view')
 ) then raise exception 'Batch not found or location access denied';end if;
 select jsonb_build_object(
  'batch',jsonb_build_object(
    'batch_id',b.id,'batch_number',b.batch_number,'variant_id',b.variant_id,'product_name',p.name,'variant_name',pv.variant_name,
    'sku',pv.sku,'manufactured_on',b.manufactured_on,'expiry_on',b.expiry_on,'status',b.status,'supplier_name',sup.name
  ),
  'balances',coalesce((
    select jsonb_agg(jsonb_build_object('location_id',bb.location_id,'location_name',l.name,'quantity',bb.quantity) order by l.name)
    from public.inventory_batch_balances_v483 bb
    left join public.business_locations l on l.id=bb.location_id
    where bb.tenant_id=p_tenant_id and bb.batch_id=b.id
      and private.erp_document_scope_allowed(p_tenant_id,bb.location_id,null,'view')
  ),'[]'::jsonb),
  'events',coalesce((
    select jsonb_agg(jsonb_build_object(
      'event_id',e.id,'event_type',e.event_type,'quantity',e.quantity,'location_name',l2.name,
      'supplier_name',s.name,'customer_name',c.name,'purchase_number',pur.purchase_number,'sale_number',sa.sale_number,
      'reference_number',e.reference_number,'metadata',e.metadata,'created_at',e.created_at
    ) order by e.created_at desc)
    from public.inventory_trace_events_v483 e
    left join public.business_locations l2 on l2.id=e.location_id
    left join public.suppliers s on s.id=e.supplier_id
    left join public.customers c on c.id=e.customer_id
    left join public.purchases pur on pur.id=e.purchase_id
    left join public.sales sa on sa.id=e.sale_id
    where e.tenant_id=p_tenant_id and e.batch_id=b.id
      and private.erp_document_scope_allowed(p_tenant_id,e.location_id,null,'view')
  ),'[]'::jsonb)
 ) into v
 from public.inventory_batches_v483 b
 join public.product_variants pv on pv.id=b.variant_id and pv.tenant_id=b.tenant_id
 join public.products p on p.id=pv.product_id
 left join public.suppliers sup on sup.id=b.supplier_id
 where b.tenant_id=p_tenant_id and b.id=p_batch_id;
 if v is null then raise exception 'Batch not found';end if;
 return v;
end$$;
grant execute on function public.inventory_batch_history_v483(uuid,uuid) to authenticated;

create or replace function public.inventory_serial_history_v483(p_tenant_id uuid,p_serial_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v jsonb;begin
 if not private.erp_user_has_tenant_access(p_tenant_id) or not private.v483_trace_view_allowed(p_tenant_id) then raise exception 'Traceability view permission required';end if;
 select jsonb_build_object(
  'serial',jsonb_build_object(
    'serial_id',s.id,'serial_number',s.serial_number,'status',s.status,'variant_id',s.variant_id,
    'product_name',p.name,'variant_name',pv.variant_name,'sku',pv.sku,
    'location_name',coalesce(l.name,sl.name,pl.name),'supplier_name',sup.name,'customer_name',c.name,
    'purchase_number',pur.purchase_number,'sale_number',sa.sale_number,'received_at',s.received_at,'sold_at',s.sold_at
  ),
  'warranties',coalesce((
    select jsonb_agg(jsonb_build_object(
      'warranty_id',w.id,'customer_name',cw.name,'sale_number',sw.sale_number,
      'warranty_start',w.warranty_start,'warranty_expiry',w.warranty_expiry,
      'status',case when w.status='active' and w.warranty_expiry<current_date then 'expired' else w.status end
    ) order by w.created_at desc)
    from public.product_warranties_v483 w
    left join public.customers cw on cw.id=w.customer_id
    left join public.sales sw on sw.id=w.sale_id
    where w.tenant_id=p_tenant_id and w.serial_id=s.id
  ),'[]'::jsonb),
  'events',coalesce((
    select jsonb_agg(jsonb_build_object(
      'event_id',e.id,'event_type',e.event_type,'quantity',e.quantity,'location_name',el.name,
      'supplier_name',es.name,'customer_name',ec.name,'purchase_number',ep.purchase_number,'sale_number',esa.sale_number,
      'reference_number',e.reference_number,'created_at',e.created_at
    ) order by e.created_at desc)
    from public.inventory_trace_events_v483 e
    left join public.business_locations el on el.id=e.location_id
    left join public.suppliers es on es.id=e.supplier_id
    left join public.customers ec on ec.id=e.customer_id
    left join public.purchases ep on ep.id=e.purchase_id
    left join public.sales esa on esa.id=e.sale_id
    where e.tenant_id=p_tenant_id and e.serial_id=s.id
      and private.erp_document_scope_allowed(p_tenant_id,e.location_id,null,'view')
  ),'[]'::jsonb)
 ) into v
 from public.inventory_serials_v483 s
 join public.product_variants pv on pv.id=s.variant_id and pv.tenant_id=s.tenant_id
 join public.products p on p.id=pv.product_id
 left join public.business_locations l on l.id=s.current_location_id
 left join public.suppliers sup on sup.id=s.supplier_id
 left join public.customers c on c.id=s.customer_id
 left join public.purchases pur on pur.id=s.purchase_id
 left join public.sales sa on sa.id=s.sale_id
 left join public.document_origins so on so.tenant_id=s.tenant_id and so.entity_type='sale' and so.entity_id=s.sale_id
 left join public.document_origins po on po.tenant_id=s.tenant_id and po.entity_type='purchase' and po.entity_id=s.purchase_id
 left join public.business_locations sl on sl.id=so.location_id
 left join public.business_locations pl on pl.id=po.location_id
 where s.tenant_id=p_tenant_id and s.id=p_serial_id
   and private.erp_document_scope_allowed(p_tenant_id,coalesce(s.current_location_id,so.location_id,po.location_id),null,'view');
 if v is null then raise exception 'Serial not found or location access denied';end if;
 return v;
end$$;
grant execute on function public.inventory_serial_history_v483(uuid,uuid) to authenticated;

create or replace function public.warranty_register_v483(
 p_tenant_id uuid,p_query text default '',p_status text default null,p_expiring_days integer default null,p_limit integer default 300,p_location_id uuid default null
) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
 if not private.erp_user_has_tenant_access(p_tenant_id) or not private.v483_trace_view_allowed(p_tenant_id) then raise exception 'Traceability view permission required';end if;
 return query
 select jsonb_build_object(
  'warranty_id',w.id,'variant_id',w.variant_id,'product_name',p.name,'variant_name',pv.variant_name,'sku',pv.sku,
  'serial_number',s.serial_number,'batch_number',b.batch_number,'customer_id',w.customer_id,'customer_name',c.name,
  'sale_id',w.sale_id,'sale_number',sa.sale_number,'quantity',w.quantity,'warranty_start',w.warranty_start,
  'warranty_expiry',w.warranty_expiry,'days_remaining',w.warranty_expiry-current_date,
  'status',case when w.status='active' and w.warranty_expiry<current_date then 'expired' else w.status end,
  'location_id',o.location_id,'location_name',l.name
 )
 from public.product_warranties_v483 w
 join public.product_variants pv on pv.id=w.variant_id and pv.tenant_id=w.tenant_id
 join public.products p on p.id=pv.product_id
 left join public.inventory_serials_v483 s on s.id=w.serial_id
 left join public.inventory_batches_v483 b on b.id=w.batch_id
 join public.customers c on c.id=w.customer_id
 join public.sales sa on sa.id=w.sale_id
 left join public.document_origins o on o.tenant_id=w.tenant_id and o.entity_type='sale' and o.entity_id=w.sale_id
 left join public.business_locations l on l.id=o.location_id
 where w.tenant_id=p_tenant_id
 and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
 and (
  trim(coalesce(p_query,''))='' or lower(coalesce(s.serial_number,'')) like q or lower(coalesce(b.batch_number,'')) like q or
  lower(coalesce(p.name,'')) like q or lower(coalesce(pv.sku,'')) like q or lower(coalesce(c.name,'')) like q or
  lower(coalesce(sa.sale_number,'')) like q
 )
 and (
  p_status is null or lower(p_status)=case when w.status='active' and w.warranty_expiry<current_date then 'expired' else lower(w.status) end
 )
 and (
  p_expiring_days is null or (w.status='active' and w.warranty_expiry between current_date and current_date+greatest(p_expiring_days,0))
 )
 order by w.warranty_expiry,w.created_at desc
 limit greatest(1,least(coalesce(p_limit,300),1000));
end$$;
grant execute on function public.warranty_register_v483(uuid,text,text,integer,integer,uuid) to authenticated;

create or replace function public.inventory_serial_resolve_v483(p_tenant_id uuid,p_serial_number text,p_location_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v jsonb;begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 select jsonb_build_object(
   'serial_id',s.id,'serial_number',s.serial_number,'status',s.status,'variant_id',s.variant_id,
   'product_name',p.name,'variant_name',pv.variant_name,'sku',pv.sku,'location_id',s.current_location_id
 ) into v
 from public.inventory_serials_v483 s
 join public.product_variants pv on pv.id=s.variant_id and pv.tenant_id=s.tenant_id
 join public.products p on p.id=pv.product_id
 where s.tenant_id=p_tenant_id
   and lower(trim(s.serial_number))=lower(trim(p_serial_number))
   and (p_location_id is null or s.current_location_id=p_location_id)
   and private.erp_document_scope_allowed(p_tenant_id,s.current_location_id,p_location_id,'view')
 limit 1;
 return v;
end$$;
grant execute on function public.inventory_serial_resolve_v483(uuid,text,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(138,'4.8.3','Serial / Batch / Warranty','Location-scoped serial search/history, batch search/history, warranty register and serial resolution APIs.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.3 migration 138 trace search/history applied' as status;

-- ============================================================================
-- 139_v483_release_contract.sql
-- ============================================================================

-- THQ ERP V4.8.3 — release contract.
begin;
create or replace function public.thq_api_contract_v480() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object('product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json','resources',jsonb_build_array('sync','attention','inventory-intelligence','inventory-movements','units','product-units','pricing','product-identifiers','product-lookup','label-templates','tracking-policy','serials','batches','batch-history','warranties','customer-credit','supplier-payables','reorder-suggestions','purchase-orders','business-summary','store-summary'),'core_financial_posting','direct_hardened_rpc','authoritative_sale_pricing','pricing_resolve_v482','inventory_tracking','v4.8.3','mobile_ready',true)
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;
create or replace function public.thq_backend_contract_v47() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object('product','THQ ERP','schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),'minimum_app_version','4.8.3','release','Serial / Batch / Warranty','api_version','v1')
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;
create or replace function public.thq_v483_release_verify() returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$declare v_missing text[]:='{}'::text[];begin
 if to_regclass('public.product_tracking_policies_v483') is null then v_missing:=array_append(v_missing,'product_tracking_policies_v483');end if;
 if to_regclass('public.inventory_serials_v483') is null then v_missing:=array_append(v_missing,'inventory_serials_v483');end if;
 if to_regclass('public.inventory_batches_v483') is null then v_missing:=array_append(v_missing,'inventory_batches_v483');end if;
 if to_regclass('public.inventory_batch_balances_v483') is null then v_missing:=array_append(v_missing,'inventory_batch_balances_v483');end if;
 if to_regclass('public.inventory_trace_events_v483') is null then v_missing:=array_append(v_missing,'inventory_trace_events_v483');end if;
 if to_regclass('public.product_warranties_v483') is null then v_missing:=array_append(v_missing,'product_warranties_v483');end if;
 if to_regprocedure('public.inventory_tracking_policy_v483(uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_tracking_policy_v483');end if;
 if to_regprocedure('public.inventory_tracking_policy_save_v483(uuid,uuid,text,boolean,integer,integer,boolean,boolean)') is null then v_missing:=array_append(v_missing,'inventory_tracking_policy_save_v483');end if;
 if to_regprocedure('public.inventory_tracking_register_opening_v483(uuid,uuid,uuid,jsonb,jsonb,text)') is null then v_missing:=array_append(v_missing,'inventory_tracking_register_opening_v483');end if;
 if to_regprocedure('public.inventory_list_products_v483(uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_list_products_v483');end if;
 if to_regprocedure('public.purchases_create_v483(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'purchases_create_v483');end if;
 if to_regprocedure('public.sales_create_v483(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text)') is null then v_missing:=array_append(v_missing,'sales_create_v483');end if;
 if to_regprocedure('public.inventory_serial_search_v483(uuid,text,uuid,integer)') is null then v_missing:=array_append(v_missing,'inventory_serial_search_v483');end if;
 if to_regprocedure('public.inventory_batch_search_v483(uuid,text,uuid,integer)') is null then v_missing:=array_append(v_missing,'inventory_batch_search_v483');end if;
 if to_regprocedure('public.inventory_batch_history_v483(uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_batch_history_v483');end if;
 if to_regprocedure('public.inventory_serial_history_v483(uuid,uuid)') is null then v_missing:=array_append(v_missing,'inventory_serial_history_v483');end if;
 if to_regprocedure('public.warranty_register_v483(uuid,text,text,integer,integer,uuid)') is null then v_missing:=array_append(v_missing,'warranty_register_v483');end if;
 return jsonb_build_object('ready',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'schema_version','4.8.3','migration_no',139,'api_version','v1','serial_tracking',true,'batch_tracking',true,'warranty_tracking',true,'batch_fefo',true);
end$$;
grant execute on function public.thq_v483_release_verify() to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(139,'4.8.3','Serial / Batch / Warranty','Serial number tracking, batch/expiry tracking, warranty expiry, supplier/customer traceability, serial search and batch history.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.3 migration 139 release contract applied' as status;

