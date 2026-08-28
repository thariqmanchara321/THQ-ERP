-- THQ ERP V4.7 — Foundation Lock & Production Stabilization
-- Release/schema contract. Requires migrations through 100_v46_core_fixes.sql.
begin;

create table if not exists public.thq_schema_releases(
  migration_no integer primary key,
  schema_version text not null,
  release_name text not null,
  applied_at timestamptz not null default now(),
  notes text
);

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(101,'4.7.0','Foundation Lock & Production Stabilization','V4.7 upgrade started from confirmed V4.6 migration 100 baseline.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

alter table public.thq_schema_releases enable row level security;
revoke all on public.thq_schema_releases from anon,authenticated;

create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp
as $$
  select jsonb_build_object(
    'product','THQ ERP',
    'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
    'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
    'minimum_app_version','4.7.0',
    'release','Foundation Lock & Production Stabilization'
  )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

commit;
select 'THQ ERP V4.7 migration 101 ready' as status;
-- THQ ERP V4.7 — accounting provisioning + strict posting.
begin;

create or replace function private.v47_ensure_accounting_for_tenant(p_tenant_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if not exists(select 1 from public.tenants where id=p_tenant_id) then
    raise exception 'Tenant not found';
  end if;

  insert into public.accounting_accounts(tenant_id,code,name,account_type,system_key,is_system,description)
  select p_tenant_id,x.code,x.name,x.type,x.key,true,x.description from (values
   ('1000','Cash in Hand','asset','cash','Cash received at counters'),
   ('1010','Bank Account','asset','bank','Primary bank account'),
   ('1020','UPI Clearing','asset','upi','UPI collections/settlements'),
   ('1030','Card Clearing','asset','card','Card collections/settlements'),
   ('1100','Accounts Receivable','asset','accounts_receivable','Customer credit outstanding'),
   ('1200','Inventory Asset','asset','inventory_asset','Stock value'),
   ('1300','Input GST Receivable','asset','input_gst','Input GST credit'),
   ('2000','Accounts Payable','liability','accounts_payable','Supplier outstanding'),
   ('2100','Output GST Payable','liability','output_gst','GST collected on sales'),
   ('3000','Owner Equity','equity','owner_equity','Owner/capital equity'),
   ('4000','Sales Revenue','income','sales_revenue','Product/service sales'),
   ('4010','Other Revenue','income','other_revenue','Other operating revenue'),
   ('5000','Cost of Goods Sold','cogs','cogs','Inventory cost of sold goods'),
   ('6000','Operating Expenses','expense','operating_expense','General operating expenses'),
   ('6010','Purchase / Direct Expense','expense','purchase_expense','Direct purchase expense for non-stock items'),
   ('6900','Rounding / Variance','expense','rounding','Small rounding and cash variances')
  ) x(code,name,type,key,description)
  on conflict(tenant_id,code) do nothing;

  insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id)
  select a.tenant_id,'payment.'||a.system_key,a.id
  from public.accounting_accounts a
  where a.tenant_id=p_tenant_id and a.system_key in('cash','bank','upi','card')
  on conflict(tenant_id,mapping_key) do nothing;

  insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id)
  select a.tenant_id,a.system_key,a.id
  from public.accounting_accounts a
  where a.tenant_id=p_tenant_id and a.system_key in(
    'accounts_receivable','accounts_payable','inventory_asset','input_gst','output_gst',
    'sales_revenue','cogs','operating_expense','purchase_expense','rounding'
  )
  on conflict(tenant_id,mapping_key) do nothing;
end $$;
revoke all on function private.v47_ensure_accounting_for_tenant(uuid) from public;

create or replace function private.v47_tenant_accounting_after_insert()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  perform private.v47_ensure_accounting_for_tenant(new.id);
  return new;
end $$;
revoke all on function private.v47_tenant_accounting_after_insert() from public;
drop trigger if exists trg_v47_tenant_accounting_after_insert on public.tenants;
create trigger trg_v47_tenant_accounting_after_insert
after insert on public.tenants for each row execute function private.v47_tenant_accounting_after_insert();

-- Backfill/repair mappings for every current business before strict posting is enabled.
do $$ declare r record; begin
  for r in select id from public.tenants loop
    perform private.v47_ensure_accounting_for_tenant(r.id);
  end loop;
end $$;

-- Critical change: accounting errors are no longer swallowed. A required journal failure
-- now aborts the surrounding sale/purchase/expense transaction.
create or replace function private.v4_origin_after_insert()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_shift uuid;v_cash numeric;v_ref text;v_method text;begin
  perform private.v4_accounting_post_document(new.tenant_id,new.entity_type,new.entity_id);

  if new.device_id is not null then
    select id into v_shift from public.cashier_shifts
    where tenant_id=new.tenant_id and device_id=new.device_id and status='open'
    order by opened_at desc limit 1;
  end if;

  if v_shift is not null and new.entity_type='sale' then
    select coalesce(sum(amount),0),max(s.sale_number) into v_cash,v_ref
    from public.sale_payments p join public.sales s on s.id=p.sale_id
    where p.sale_id=new.entity_id and lower(coalesce(p.payment_method,''))='cash';
    if v_cash>0 and not exists(select 1 from public.cash_drawer_movements where shift_id=v_shift and reference_type='sale' and reference_id=new.entity_id) then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(new.tenant_id,v_shift,'sale',v_cash,'sale',new.entity_id,v_ref,'Cash sale',new.created_by);
    end if;
  elsif v_shift is not null and new.entity_type='expense' then
    select payment_method,total_amount,expense_number into v_method,v_cash,v_ref
    from public.expenses where id=new.entity_id and tenant_id=new.tenant_id;
    if lower(coalesce(v_method,''))='cash' and coalesce(v_cash,0)>0 and not exists(select 1 from public.cash_drawer_movements where shift_id=v_shift and reference_type='expense' and reference_id=new.entity_id) then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(new.tenant_id,v_shift,'expense',-abs(v_cash),'expense',new.entity_id,v_ref,'Cash expense',new.created_by);
    end if;
  end if;
  return new;
end $$;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(102,'4.7.0','Foundation Lock & Production Stabilization','Strict automatic accounting posting and new-tenant accounting provisioning.')
on conflict(migration_no) do update set notes=excluded.notes;

commit;
select 'THQ ERP V4.7 migration 102 accounting integrity ready' as status;
-- THQ ERP V4.7 — idempotent transaction request foundation + sale/purchase wrappers.
begin;

create table if not exists public.transaction_requests_v47(
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  request_id text not null,
  operation text not null,
  response jsonb not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key(tenant_id,request_id)
);
create index if not exists idx_transaction_requests_v47_created on public.transaction_requests_v47(tenant_id,created_at desc);
alter table public.transaction_requests_v47 enable row level security;
revoke all on public.transaction_requests_v47 from anon,authenticated;

create or replace function private.v47_request_existing(p_tenant_id uuid,p_request_id text,p_operation text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_operation text;v_response jsonb;begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then raise exception 'Request ID is required';end if;
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||trim(p_request_id),0));
  select operation,response into v_operation,v_response
  from public.transaction_requests_v47
  where tenant_id=p_tenant_id and request_id=trim(p_request_id);
  if found then
    if v_operation<>p_operation then raise exception 'Request ID already used for a different operation';end if;
    return v_response;
  end if;
  return null;
end $$;
revoke all on function private.v47_request_existing(uuid,text,text) from public;

create or replace function private.v47_request_complete(p_tenant_id uuid,p_request_id text,p_operation text,p_response jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  insert into public.transaction_requests_v47(tenant_id,request_id,operation,response,created_by)
  values(p_tenant_id,trim(p_request_id),p_operation,coalesce(p_response,'{}'::jsonb),auth.uid())
  on conflict(tenant_id,request_id) do nothing;
  return coalesce(p_response,'{}'::jsonb);
end $$;
revoke all on function private.v47_request_complete(uuid,text,text,jsonb) from public;

create or replace function public.sales_create_v47(
  p_tenant_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,p_items jsonb,p_additional_charges numeric,
  p_initial_payment numeric,p_payment_method text,p_payment_reference text,p_notes text,p_location_id uuid,p_device_id uuid,
  p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v jsonb;begin
  v:=private.v47_request_existing(p_tenant_id,p_request_id,'sale.create'); if v is not null then return v;end if;
  v:=public.sales_create_v4(p_tenant_id,p_customer_id,p_sale_date,p_due_date,p_items,p_additional_charges,p_initial_payment,p_payment_method,p_payment_reference,p_notes,p_location_id,p_device_id);
  return private.v47_request_complete(p_tenant_id,p_request_id,'sale.create',v);
end $$;
grant execute on function public.sales_create_v47(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text) to authenticated;

create or replace function public.purchases_create_v47(
  p_tenant_id uuid,p_supplier_id uuid,p_supplier_invoice_number text,p_purchase_date date,p_due_date date,p_items jsonb,
  p_additional_charges numeric,p_initial_payment numeric,p_payment_method text,p_notes text,p_location_id uuid,p_device_id uuid,
  p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v jsonb;begin
  v:=private.v47_request_existing(p_tenant_id,p_request_id,'purchase.create'); if v is not null then return v;end if;
  v:=public.purchases_create_v4(p_tenant_id,p_supplier_id,p_supplier_invoice_number,p_purchase_date,p_due_date,p_items,p_additional_charges,p_initial_payment,p_payment_method,p_notes,p_location_id,p_device_id);
  return private.v47_request_complete(p_tenant_id,p_request_id,'purchase.create',v);
end $$;
grant execute on function public.purchases_create_v47(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(103,'4.7.0','Foundation Lock & Production Stabilization','Request-id idempotency foundation; retry-safe sales and purchases.')
on conflict(migration_no) do update set notes=excluded.notes;
commit;
select 'THQ ERP V4.7 migration 103 idempotent sales/purchases ready' as status;
-- THQ ERP V4.7 — retry-safe wrappers for other mutating core operations.
begin;

create or replace function public.expenses_create_v47(
  p_tenant_id uuid,p_category_id uuid,p_expense_date date,p_payee text,p_description text,p_amount numeric,p_tax_amount numeric,
  p_payment_method text,p_reference_number text,p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin
  v:=private.v47_request_existing(p_tenant_id,p_request_id,'expense.create');if v is not null then return v;end if;
  v:=public.expenses_create_v32(p_tenant_id,p_category_id,p_expense_date,p_payee,p_description,p_amount,p_tax_amount,p_payment_method,p_reference_number,p_notes,p_location_id,p_device_id);
  return private.v47_request_complete(p_tenant_id,p_request_id,'expense.create',v);
end$$;
grant execute on function public.expenses_create_v47(uuid,uuid,date,text,text,numeric,numeric,text,text,text,uuid,uuid,text) to authenticated;

create or replace function public.sales_add_payment_v47(p_tenant_id uuid,p_sale_id uuid,p_amount numeric,p_payment_method text,p_reference_number text,p_notes text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'sale.payment');if v is not null then return v;end if;v:=public.sales_add_payment_v32(p_tenant_id,p_sale_id,p_amount,p_payment_method,p_reference_number,p_notes);return private.v47_request_complete(p_tenant_id,p_request_id,'sale.payment',v);end$$;
grant execute on function public.sales_add_payment_v47(uuid,uuid,numeric,text,text,text,text) to authenticated;

create or replace function public.purchases_add_payment_v47(p_tenant_id uuid,p_purchase_id uuid,p_amount numeric,p_payment_method text,p_reference_number text,p_notes text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'purchase.payment');if v is not null then return v;end if;v:=public.purchases_add_payment_v32(p_tenant_id,p_purchase_id,p_amount,p_payment_method,p_reference_number,p_notes);return private.v47_request_complete(p_tenant_id,p_request_id,'purchase.payment',v);end$$;
grant execute on function public.purchases_add_payment_v47(uuid,uuid,numeric,text,text,text,text) to authenticated;

create or replace function public.sales_return_create_v47(p_tenant_id uuid,p_sale_id uuid,p_items jsonb,p_reason text,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'sale.return');if v is not null then return v;end if;v:=public.sales_return_create_v4(p_tenant_id,p_sale_id,p_items,p_reason,p_device_id);return private.v47_request_complete(p_tenant_id,p_request_id,'sale.return',v);end$$;
grant execute on function public.sales_return_create_v47(uuid,uuid,jsonb,text,uuid,text) to authenticated;

create or replace function public.purchase_return_create_v47(p_tenant_id uuid,p_purchase_id uuid,p_items jsonb,p_reason text,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'purchase.return');if v is not null then return v;end if;v:=public.purchase_return_create_v4(p_tenant_id,p_purchase_id,p_items,p_reason,p_device_id);return private.v47_request_complete(p_tenant_id,p_request_id,'purchase.return',v);end$$;
grant execute on function public.purchase_return_create_v47(uuid,uuid,jsonb,text,uuid,text) to authenticated;

create or replace function public.inventory_adjust_stock_v47(p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_variant_id uuid,p_quantity_delta numeric,p_note text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'inventory.adjust');if v is not null then return v;end if;v:=public.inventory_adjust_stock_v4(p_tenant_id,p_location_id,p_device_id,p_variant_id,p_quantity_delta,p_note);return private.v47_request_complete(p_tenant_id,p_request_id,'inventory.adjust',v);end$$;
grant execute on function public.inventory_adjust_stock_v47(uuid,uuid,uuid,uuid,numeric,text,text) to authenticated;

create or replace function public.inventory_transfer_create_v47(p_tenant_id uuid,p_from_location_id uuid,p_to_location_id uuid,p_items jsonb,p_notes text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'inventory.transfer');if v is not null then return v;end if;v:=public.inventory_transfer_create_v4(p_tenant_id,p_from_location_id,p_to_location_id,p_items,p_notes);return private.v47_request_complete(p_tenant_id,p_request_id,'inventory.transfer',v);end$$;
grant execute on function public.inventory_transfer_create_v47(uuid,uuid,uuid,jsonb,text,text) to authenticated;

create or replace function public.cashier_shift_open_v47(p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_opening_cash numeric,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'shift.open');if v is not null then return v;end if;v:=public.cashier_shift_open_v4(p_tenant_id,p_location_id,p_device_id,p_opening_cash);return private.v47_request_complete(p_tenant_id,p_request_id,'shift.open',v);end$$;
grant execute on function public.cashier_shift_open_v47(uuid,uuid,uuid,numeric,text) to authenticated;

create or replace function public.cashier_shift_close_v47(p_tenant_id uuid,p_shift_id uuid,p_declared_cash numeric,p_note text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'shift.close');if v is not null then return v;end if;v:=public.cashier_shift_close_v4(p_tenant_id,p_shift_id,p_declared_cash,p_note);return private.v47_request_complete(p_tenant_id,p_request_id,'shift.close',v);end$$;
grant execute on function public.cashier_shift_close_v47(uuid,uuid,numeric,text,text) to authenticated;


create or replace function public.sales_void_v47(p_tenant_id uuid,p_sale_id uuid,p_reason text,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'sale.void');if v is not null then return v;end if;perform public.sales_void_v4(p_tenant_id,p_sale_id,p_reason,p_device_id);v:=jsonb_build_object('success',true,'sale_id',p_sale_id);return private.v47_request_complete(p_tenant_id,p_request_id,'sale.void',v);end$$;
grant execute on function public.sales_void_v47(uuid,uuid,text,uuid,text) to authenticated;

create or replace function public.purchase_void_v47(p_tenant_id uuid,p_purchase_id uuid,p_reason text,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'purchase.void');if v is not null then return v;end if;perform public.purchase_void_v4(p_tenant_id,p_purchase_id,p_reason,p_device_id);v:=jsonb_build_object('success',true,'purchase_id',p_purchase_id);return private.v47_request_complete(p_tenant_id,p_request_id,'purchase.void',v);end$$;
grant execute on function public.purchase_void_v47(uuid,uuid,text,uuid,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(104,'4.7.0','Foundation Lock & Production Stabilization','Retry-safe wrappers for expenses, payments, returns, stock adjustments/transfers and shift open/close.')
on conflict(migration_no) do update set notes=excluded.notes;
commit;
select 'THQ ERP V4.7 migration 104 idempotent operations ready' as status;
-- THQ ERP V4.7 — logical system vs physical installation separation.
begin;

create table if not exists public.system_installations(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  system_id uuid not null references public.business_devices(id) on delete cascade,
  installation_id text not null,
  secret_hash text,
  status text not null default 'active' check(status in('active','inactive','revoked')),
  platform_hint text,
  app_version text,
  activated_at timestamptz not null default now(),
  last_seen_at timestamptz,
  deactivated_at timestamptz,
  deactivation_reason text,
  created_at timestamptz not null default now()
);
create unique index if not exists ux_system_installations_active_installation
  on public.system_installations(installation_id) where status='active';
create unique index if not exists ux_system_installations_active_system
  on public.system_installations(system_id) where status='active';
create index if not exists idx_system_installations_history
  on public.system_installations(tenant_id,system_id,activated_at desc);
alter table public.system_installations enable row level security;
revoke all on public.system_installations from anon,authenticated;

-- Preserve existing V4.6 active bindings as installation history.
insert into public.system_installations(tenant_id,system_id,installation_id,secret_hash,status,platform_hint,activated_at,last_seen_at)
select d.tenant_id,d.id,d.installation_id,d.device_secret_hash,'active',d.platform_hint,coalesce(d.activated_at,d.updated_at,d.created_at),d.last_seen_at
from public.business_devices d
where d.status='active' and nullif(d.installation_id,'') is not null
  and not exists(select 1 from public.system_installations si where si.system_id=d.id and si.status='active')
on conflict do nothing;

-- Called by the device-activate Edge Function using service role. The activation claim,
-- uniqueness checks, installation history and compatibility binding are one DB transaction.
create or replace function public.system_claim_activation_v47(
  p_business_code text,p_activation_hash text,p_installation_id text,p_app_key text,p_secret_hash text,
  p_platform_hint text default null,p_app_version text default null
) returns jsonb language plpgsql security definer
set search_path=public,private,extensions,pg_temp
as $$
declare d public.business_devices%rowtype;t public.tenants%rowtype;l public.business_locations%rowtype;v_installation uuid;
begin
  if nullif(trim(coalesce(p_business_code,'')),'') is null or nullif(trim(coalesce(p_activation_hash,'')),'') is null
     or nullif(trim(coalesce(p_installation_id,'')),'') is null or p_app_key not in('client','pos')
     or nullif(trim(coalesce(p_secret_hash,'')),'') is null then
    raise exception 'Invalid activation request';
  end if;

  select * into t from public.tenants where upper(business_code)=upper(trim(p_business_code));
  if not found then raise exception 'Invalid business or activation code';end if;

  select * into d
  from public.business_devices
  where tenant_id=t.id and app_type=p_app_key and status in('pending','inactive')
    and activation_hash=p_activation_hash
    and (activation_expires_at is null or activation_expires_at>=now())
  order by activation_issued_at desc nulls last,created_at desc
  limit 1 for update;
  if not found then raise exception 'Invalid or expired activation code';end if;

  if exists(select 1 from public.system_installations where installation_id=trim(p_installation_id) and status='active' and system_id<>d.id) then
    raise exception 'This installation is already registered to another system';
  end if;
  if exists(select 1 from public.business_devices where installation_id=trim(p_installation_id) and status='active' and id<>d.id) then
    raise exception 'This installation is already registered to another system';
  end if;

  update public.system_installations
  set status='inactive',deactivated_at=now(),deactivation_reason='Replaced by a new activation'
  where system_id=d.id and status='active';

  insert into public.system_installations(tenant_id,system_id,installation_id,secret_hash,status,platform_hint,app_version,activated_at,last_seen_at)
  values(t.id,d.id,trim(p_installation_id),p_secret_hash,'active',coalesce(nullif(trim(p_platform_hint),''),d.platform_hint),nullif(trim(coalesce(p_app_version,'')),''),now(),now())
  returning id into v_installation;

  update public.business_devices
  set status='active',installation_id=trim(p_installation_id),device_secret_hash=p_secret_hash,
      activation_hash=null,activation_expires_at=null,activated_at=now(),last_seen_at=now(),
      activation_count=coalesce(activation_count,0)+1,deactivated_at=null,deactivated_by=null,deactivation_reason=null,updated_at=now()
  where id=d.id;

  select * into l from public.business_locations where id=d.location_id;
  return jsonb_build_object(
    'success',true,'tenant_id',t.id,'tenant_name',t.name,'business_code',t.business_code,
    'device_id',d.id,'device_code',d.device_code,'device_name',d.name,'installation_record_id',v_installation,
    'location_id',l.id,'location_name',l.name,'location_code',l.location_code,'location_tracking_code',l.tracking_code
  );
end $$;
revoke all on function public.system_claim_activation_v47(text,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.system_claim_activation_v47(text,text,text,text,text,text,text) to service_role;

create or replace function public.system_installations_list_v47(p_tenant_id uuid,p_system_id uuid)
returns table(id uuid,installation_id text,status text,platform_hint text,app_version text,activated_at timestamptz,last_seen_at timestamptz,deactivated_at timestamptz,deactivation_reason text)
language plpgsql security definer set search_path=public,private,pg_temp
as $$begin
  if not private.platform_v2_is_admin()
     and not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'locations.manage') then raise exception 'Permission denied';end if;
  if not exists(select 1 from public.business_devices where id=p_system_id and tenant_id=p_tenant_id) then raise exception 'System not found';end if;
  return query select s.id,s.installation_id,s.status,s.platform_hint,s.app_version,s.activated_at,s.last_seen_at,s.deactivated_at,s.deactivation_reason
  from public.system_installations s where s.tenant_id=p_tenant_id and s.system_id=p_system_id order by s.activated_at desc;
end$$;
grant execute on function public.system_installations_list_v47(uuid,uuid) to authenticated;

-- Keep the V4.6 Admin API name stable but deactivate the physical binding as well.
create or replace function public.platform_system_deactivate_v46(p_tenant_id uuid,p_device_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v_code text;begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required';end if;
  select device_code into v_code from public.business_devices where id=p_device_id and tenant_id=p_tenant_id for update;
  if v_code is null then raise exception 'System not found';end if;
  update public.system_installations set status='inactive',deactivated_at=now(),deactivation_reason=nullif(trim(coalesce(p_reason,'')),'')
  where tenant_id=p_tenant_id and system_id=p_device_id and status='active';
  update public.business_devices set status='inactive',installation_id=null,device_secret_hash=null,last_seen_at=null,
    deactivated_at=now(),deactivated_by=auth.uid(),deactivation_reason=nullif(trim(coalesce(p_reason,'')),''),updated_at=now()
  where id=p_device_id and tenant_id=p_tenant_id and status='active';
  perform private.business_audit_write(p_tenant_id,'system.deactivate','business_device',p_device_id,v_code,null,jsonb_build_object('reason',nullif(trim(coalesce(p_reason,'')),'')));
end$$;
grant execute on function public.platform_system_deactivate_v46(uuid,uuid,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(105,'4.7.0','Foundation Lock & Production Stabilization','Separate physical installation history and atomic activation claim while preserving V4.6 system IDs.')
on conflict(migration_no) do update set notes=excluded.notes;
commit;
select 'THQ ERP V4.7 migration 105 system installations ready' as status;
-- THQ ERP V4.7 — enforce AVAILABLE stock under the row lock.
begin;

create or replace function private.v4_location_stock_apply(
  p_tenant_id uuid,p_location_id uuid,p_variant_id uuid,p_delta numeric,
  p_movement_type text,p_reference_type text default null,p_reference_id uuid default null,
  p_reference_number text default null,p_note text default null,p_device_id uuid default null,
  p_allow_negative boolean default false
) returns numeric
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_before numeric:=0;v_after numeric;v_cost numeric:=0;v_reserved numeric:=0;v_damaged numeric:=0;v_quarantine numeric:=0;v_available numeric:=0;
begin
  -- Ensure a row exists BEFORE FOR UPDATE so simultaneous first movements serialize.
  insert into public.location_stock_balances(tenant_id,location_id,variant_id,quantity,average_cost,updated_at)
  values(p_tenant_id,p_location_id,p_variant_id,0,0,now()) on conflict(tenant_id,location_id,variant_id) do nothing;

  select quantity,reserved_quantity,damaged_quantity,quarantine_quantity
    into v_before,v_reserved,v_damaged,v_quarantine
  from public.location_stock_balances
  where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=p_variant_id
  for update;

  v_before:=coalesce(v_before,0);v_reserved:=coalesce(v_reserved,0);v_damaged:=coalesce(v_damaged,0);v_quarantine:=coalesce(v_quarantine,0);
  v_available:=v_before-v_reserved-v_damaged-v_quarantine;
  v_after:=v_before+coalesce(p_delta,0);

  if not p_allow_negative and coalesce(p_delta,0)<0 and v_available+coalesce(p_delta,0)<-0.000001 then
    raise exception 'Insufficient available stock at selected store. Available: %, requested: %',v_available,abs(p_delta);
  end if;
  if not p_allow_negative and v_after<0 then raise exception 'Insufficient physical stock at selected store';end if;

  select coalesce(cost_price,0) into v_cost from public.product_variants where id=p_variant_id and tenant_id=p_tenant_id;
  insert into public.location_product_settings(tenant_id,location_id,variant_id,active)
  values(p_tenant_id,p_location_id,p_variant_id,true) on conflict(tenant_id,location_id,variant_id) do nothing;

  update public.location_stock_balances
  set quantity=v_after,average_cost=case when v_cost<>0 then v_cost else average_cost end,updated_at=now()
  where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=p_variant_id;

  insert into public.location_stock_movements(tenant_id,location_id,variant_id,movement_type,quantity_delta,unit_cost,reference_type,reference_id,reference_number,note,created_by,device_id)
  values(p_tenant_id,p_location_id,p_variant_id,p_movement_type,p_delta,v_cost,p_reference_type,p_reference_id,p_reference_number,nullif(trim(coalesce(p_note,'')),''),auth.uid(),p_device_id);
  return v_after;
end $$;
revoke all on function private.v4_location_stock_apply(uuid,uuid,uuid,numeric,text,text,uuid,text,text,uuid,boolean) from public;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(106,'4.7.0','Foundation Lock & Production Stabilization','Available-stock validation moved inside row-locked stock mutation; first-movement race removed.')
on conflict(migration_no) do update set notes=excluded.notes;
commit;
select 'THQ ERP V4.7 migration 106 inventory atomicity ready' as status;
-- THQ ERP V4.7 — integrity scanner used for release/support health checks.
begin;

create or replace function public.system_integrity_scan_v47(p_tenant_id uuid)
returns table(severity text,code text,issue_count bigint,description text)
language plpgsql security definer set search_path=public,private,pg_temp
as $$begin
  if not private.platform_v2_is_admin() and not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;

  return query
  select 'critical'::text,'UNBALANCED_POSTED_JOURNAL'::text,count(*)::bigint,'Posted journal debit and credit totals do not match.'::text
  from (
    select j.id from public.journal_entries j join public.journal_lines l on l.journal_entry_id=j.id
    where j.tenant_id=p_tenant_id and j.status='posted' group by j.id having abs(sum(l.debit)-sum(l.credit))>0.01
  ) q;

  return query
  select 'critical','NEGATIVE_AVAILABLE_STOCK',count(*)::bigint,'Location available stock is below zero.'
  from public.location_stock_balances b where b.tenant_id=p_tenant_id and (coalesce(b.quantity,0)-coalesce(b.reserved_quantity,0)-coalesce(b.damaged_quantity,0)-coalesce(b.quarantine_quantity,0)) < -0.000001;

  return query
  select 'critical','SALE_WITHOUT_JOURNAL',count(*)::bigint,'Non-void sale has no posted sale journal.'
  from public.sales s where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('void','cancelled')
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='sale' and j.source_id=s.id and j.status='posted');

  return query
  select 'critical','PURCHASE_WITHOUT_JOURNAL',count(*)::bigint,'Non-void purchase has no posted purchase journal.'
  from public.purchases p where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled')
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='purchase' and j.source_id=p.id and j.status='posted');

  return query
  select 'critical','EXPENSE_WITHOUT_JOURNAL',count(*)::bigint,'Posted expense has no posted expense journal.'
  from public.expenses e where e.tenant_id=p_tenant_id and e.status='posted'
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='expense' and j.source_id=e.id and j.status='posted');

  return query
  select 'warning','SALE_WITHOUT_ORIGIN',count(*)::bigint,'Sale has no store/system origin record.'
  from public.sales s where s.tenant_id=p_tenant_id and not exists(select 1 from public.document_origins o where o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id);

  return query
  select 'warning','PURCHASE_WITHOUT_ORIGIN',count(*)::bigint,'Purchase has no store/system origin record.'
  from public.purchases p where p.tenant_id=p_tenant_id and not exists(select 1 from public.document_origins o where o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id);

  return query
  select 'critical','ACTIVE_SYSTEM_WITHOUT_INSTALLATION',count(*)::bigint,'Active logical system does not have an active physical installation binding.'
  from public.business_devices d where d.tenant_id=p_tenant_id and d.status='active'
    and not exists(select 1 from public.system_installations si where si.system_id=d.id and si.status='active');

  return query
  select 'critical','INSTALLATION_BINDING_MISMATCH',count(*)::bigint,'Compatibility system binding and active installation history disagree.'
  from public.business_devices d join public.system_installations si on si.system_id=d.id and si.status='active'
  where d.tenant_id=p_tenant_id and (d.status<>'active' or coalesce(d.installation_id,'')<>coalesce(si.installation_id,''));

  return query
  select 'critical','SALE_OVERPAYMENT',count(*)::bigint,'Sale payments exceed the sale grand total.'
  from public.sales s where s.tenant_id=p_tenant_id and coalesce((select sum(sp.amount) from public.sale_payments sp where sp.sale_id=s.id),0) > s.grand_total+0.01;

  return query
  select 'critical','PURCHASE_OVERPAYMENT',count(*)::bigint,'Purchase payments exceed the purchase grand total.'
  from public.purchases p where p.tenant_id=p_tenant_id and coalesce((select sum(pp.amount) from public.purchase_payments pp where pp.purchase_id=p.id),0) > p.grand_total+0.01;
end $$;
grant execute on function public.system_integrity_scan_v47(uuid) to authenticated;

create or replace function public.system_health_summary_v47(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v_critical bigint;v_warning bigint;begin
  select coalesce(sum(issue_count) filter(where severity='critical'),0),coalesce(sum(issue_count) filter(where severity='warning'),0)
  into v_critical,v_warning from public.system_integrity_scan_v47(p_tenant_id);
  return jsonb_build_object('tenant_id',p_tenant_id,'schema',public.thq_backend_contract_v47(),'critical',v_critical,'warning',v_warning,'release_ready',v_critical=0,'checked_at',now());
end$$;
grant execute on function public.system_health_summary_v47(uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(107,'4.7.0','Foundation Lock & Production Stabilization','System integrity scanner for journals, stock, origins, activation bindings and overpayments.')
on conflict(migration_no) do update set notes=excluded.notes;
commit;
select 'THQ ERP V4.7 migration 107 integrity health ready' as status;
-- THQ ERP V4.7 — fail closed for Client/POS app authorization.
begin;

create or replace function private.erp_user_app_allowed(p_tenant_id uuid,p_app_key text,p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public,private,pg_temp
as $$
  select private.erp_user_is_owner(p_tenant_id,p_user_id)
      or coalesce((select a.enabled from public.business_user_app_access a where a.tenant_id=p_tenant_id and a.user_id=p_user_id and a.app_key=p_app_key),false);
$$;
revoke all on function private.erp_user_app_allowed(uuid,text,uuid) from public;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(108,'4.7.0','Foundation Lock & Production Stabilization','Application authorization is fail-closed when no explicit access record exists (owners remain allowed).')
on conflict(migration_no) do update set notes=excluded.notes;
commit;
select 'THQ ERP V4.7 migration 108 security access ready' as status;
-- THQ ERP V4.7 — release registration and upgrade verification.
begin;

insert into public.platform_app_releases(app_key,platform,version,build_number,status,minimum_supported,mandatory,release_notes)
select x.app_key,x.platform,'4.7.0',1,'stable',false,false,
  'THQ ERP V4.7 Foundation Lock: strict accounting posting, retry-safe transaction requests, installation history/atomic activation, row-locked available-stock enforcement, fail-closed app access and integrity health checks.'
from (values
 ('client','windows'),('client','android'),('client','web'),
 ('pos','windows'),('pos','android'),('admin','web')
) x(app_key,platform)
where not exists(select 1 from public.platform_app_releases r where r.app_key=x.app_key and r.platform=x.platform and r.version='4.7.0' and r.build_number=1);

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(109,'4.7.0','Foundation Lock & Production Stabilization','V4.7 release registered and required database objects verified.')
on conflict(migration_no) do update set notes=excluded.notes;

do $$begin
  if to_regclass('public.transaction_requests_v47') is null then raise exception 'V4.7 transaction request table missing';end if;
  if to_regclass('public.system_installations') is null then raise exception 'V4.7 system installations table missing';end if;
  if to_regprocedure('public.sales_create_v47(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text)') is null then raise exception 'V4.7 sales RPC missing';end if;
  if to_regprocedure('public.purchases_create_v47(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid,text)') is null then raise exception 'V4.7 purchase RPC missing';end if;
  if to_regprocedure('public.system_claim_activation_v47(text,text,text,text,text,text,text)') is null then raise exception 'V4.7 activation claim RPC missing';end if;
  if to_regprocedure('public.system_integrity_scan_v47(uuid)') is null then raise exception 'V4.7 integrity scanner missing';end if;
  if (select max(migration_no) from public.thq_schema_releases)<>109 then raise exception 'V4.7 schema release registration incomplete';end if;
end$$;

commit;
select 'THQ ERP V4.7 migrations 101-109 verified' as status;
-- THQ ERP V4.7 — runtime heartbeat keeps logical system + physical installation in sync.
begin;

create or replace function public.device_heartbeat_v4(p_tenant_id uuid,p_device_id uuid,p_app_key text,p_platform text,p_version text,p_build integer,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_latest record;v_installation text;begin
  select installation_id into v_installation from public.business_devices
  where id=p_device_id and tenant_id=p_tenant_id and status='active';
  if v_installation is null then raise exception 'System installation is not active';end if;

  update public.business_devices set last_seen_at=now() where id=p_device_id;
  update public.system_installations
  set last_seen_at=now(),platform_hint=coalesce(nullif(trim(p_platform),''),platform_hint),app_version=nullif(trim(coalesce(p_version,'')),'')
  where tenant_id=p_tenant_id and system_id=p_device_id and installation_id=v_installation and status='active';

  insert into public.device_app_status(device_id,tenant_id,app_key,platform,version,build_number,last_seen_at,metadata)
  values(p_device_id,p_tenant_id,p_app_key,p_platform,p_version,coalesce(p_build,0),now(),coalesce(p_metadata,'{}'::jsonb))
  on conflict(device_id) do update set app_key=excluded.app_key,platform=excluded.platform,version=excluded.version,build_number=excluded.build_number,last_seen_at=now(),metadata=excluded.metadata;

  select * into v_latest from public.platform_app_releases
  where app_key=p_app_key and platform=p_platform and status='stable' order by released_at desc limit 1;
  return jsonb_build_object(
    'latest_version',v_latest.version,'mandatory',coalesce(v_latest.mandatory,false),
    'status',case when v_latest.version is null or v_latest.version=p_version then 'latest' when coalesce(v_latest.mandatory,false) then 'update_required' else 'update_available' end,
    'release_notes',v_latest.release_notes,'download_url',v_latest.download_url,
    'backend',public.thq_backend_contract_v47()
  );
end $$;
grant execute on function public.device_heartbeat_v4(uuid,uuid,text,text,text,integer,jsonb) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(110,'4.7.0','Foundation Lock & Production Stabilization','Heartbeat updates both the logical system compatibility row and the active physical installation history.')
on conflict(migration_no) do update set notes=excluded.notes;

commit;
select 'THQ ERP V4.7 migration 110 runtime hardening ready' as status;
