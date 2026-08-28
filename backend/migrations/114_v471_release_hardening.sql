-- THQ ERP V4.7.1 — operational stabilization release hardening and verification.
begin;

-- One create contract for every logical system type. app_type remains the runtime
-- compatibility contract (pos/client); system_role describes how the installation is used.
create or replace function public.platform_system_create_v471(
  p_tenant_id uuid,p_location_id uuid,p_name text,p_app_type text,
  p_platform_hint text default null,p_module_keys text[] default '{}'::text[],
  p_invoice_prefix text default null,p_system_role text default null
)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v jsonb;v_id uuid;v_role text;
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then
    raise exception 'Platform admin required';
  end if;
  v_role:=coalesce(nullif(trim(p_system_role),''),case when p_app_type='pos' then 'pos' else 'office' end);
  if p_app_type='pos' and v_role<>'pos' then raise exception 'POS systems must use POS role';end if;
  if p_app_type='client' and v_role not in('back_office','office','inventory') then raise exception 'Invalid Client system role';end if;
  v:=public.platform_system_create_v46(p_tenant_id,p_location_id,p_name,p_app_type,p_platform_hint,p_module_keys,p_invoice_prefix);
  v_id:=nullif(v->>'device_id','')::uuid;
  update public.business_devices set system_role=v_role,updated_at=now() where id=v_id and tenant_id=p_tenant_id;
  return v||jsonb_build_object('system_role',v_role,'location_id',p_location_id);
end $$;
grant execute on function public.platform_system_create_v471(uuid,uuid,text,text,text,text[],text,text) to authenticated;

-- If Cashier Shift is enabled on a POS, a sale cannot bypass it. Existing idempotent
-- results are returned before this check, so a lost-response retry remains safe even
-- if the shift was closed after the original transaction committed.
create or replace function public.sales_create_v47(
  p_tenant_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,p_items jsonb,p_additional_charges numeric,
  p_initial_payment numeric,p_payment_method text,p_payment_reference text,p_notes text,p_location_id uuid,p_device_id uuid,
  p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v jsonb;v_type text;v_modules text[];begin
  v:=private.v47_request_existing(p_tenant_id,p_request_id,'sale.create'); if v is not null then return v;end if;
  if p_device_id is not null then
    select app_type,coalesce(allowed_modules,'{}'::text[]) into v_type,v_modules
    from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active';
    if v_type='pos' and 'cashier_shifts'=any(v_modules)
       and not exists(select 1 from public.cashier_shifts s where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open') then
      raise exception 'Open cashier shift before billing on this POS';
    end if;
  end if;
  v:=public.sales_create_v4(p_tenant_id,p_customer_id,p_sale_date,p_due_date,p_items,p_additional_charges,p_initial_payment,p_payment_method,p_payment_reference,p_notes,p_location_id,p_device_id);
  return private.v47_request_complete(p_tenant_id,p_request_id,'sale.create',v);
end $$;
grant execute on function public.sales_create_v47(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text) to authenticated;

-- Service-role-only deletion endpoint used after the Edge Function has reauthenticated
-- the Platform Super Admin and validated the immutable business code.
create or replace function public.platform_business_delete_v471(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v_name text;begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required';end if;
  select name into v_name from public.tenants where id=p_tenant_id for update;
  if v_name is null then raise exception 'Business not found';end if;
  delete from public.tenants where id=p_tenant_id;
  if found then return jsonb_build_object('success',true,'tenant_id',p_tenant_id,'business_name',v_name);end if;
  raise exception 'Business delete did not complete';
end $$;
revoke all on function public.platform_business_delete_v471(uuid) from public,anon,authenticated;
grant execute on function public.platform_business_delete_v471(uuid) to service_role;

-- Update backend compatibility contract for patched apps.
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp
as $$
  select jsonb_build_object(
    'product','THQ ERP',
    'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
    'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
    'minimum_app_version','4.7.1',
    'release','Operational Stabilization Patch'
  )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

insert into public.platform_app_releases(app_key,platform,version,build_number,status,minimum_supported,mandatory,release_notes)
select x.app_key,x.platform,'4.7.1',2,'stable',false,false,
  'THQ ERP V4.7.1: held-sale resume feed, customer receivables/partial payments, system reassignment/deletion, POS module fixes, cashier shift enforcement and Terminal Daily completion.'
from (values
 ('client','windows'),('client','android'),('client','web'),
 ('pos','windows'),('pos','android'),('admin','web')
) x(app_key,platform)
where not exists(select 1 from public.platform_app_releases r where r.app_key=x.app_key and r.platform=x.platform and r.version='4.7.1' and r.build_number=2);

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(114,'4.7.1','Operational Stabilization Patch','Release verification: customer receivables, held sale feed, system hierarchy/admin fixes, cashier/day controls and app compatibility contract.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

do $$begin
  if to_regclass('public.customer_receipts') is null then raise exception 'Customer receipts table missing';end if;
  if to_regclass('public.customer_receipt_allocations') is null then raise exception 'Customer receipt allocations table missing';end if;
  if to_regprocedure('public.customer_receive_payment_v471(uuid,uuid,numeric,text,text,text,uuid,uuid,uuid,text)') is null then raise exception 'Customer receive-payment RPC missing';end if;
  if to_regprocedure('public.customer_account_v471(uuid,uuid)') is null then raise exception 'Customer account RPC missing';end if;
  if to_regprocedure('public.pos_held_sales_feed_v471(uuid,uuid)') is null then raise exception 'Held-sale feed missing';end if;
  if to_regprocedure('public.pos_terminal_day_v471(uuid,uuid,date)') is null then raise exception 'Terminal Daily V4.7.1 RPC missing';end if;
  if to_regprocedure('public.platform_system_create_v471(uuid,uuid,text,text,text,text[],text,text)') is null then raise exception 'System create V4.7.1 RPC missing';end if;
  if to_regprocedure('public.platform_system_update_v471(uuid,uuid,uuid,text,text[],text,text)') is null then raise exception 'System update V4.7.1 RPC missing';end if;
  if to_regprocedure('public.platform_system_delete_v471(uuid,uuid,text)') is null then raise exception 'System delete V4.7.1 RPC missing';end if;
  if to_regprocedure('public.platform_location_delete_v471(uuid,uuid,text)') is null then raise exception 'Location delete V4.7.1 RPC missing';end if;
  if to_regprocedure('public.tenant_system_create_v471(uuid,uuid,text,text,text,text[],text,text)') is null then raise exception 'Tenant system create V4.7.1 RPC missing';end if;
  if to_regprocedure('public.tenant_system_update_v471(uuid,uuid,uuid,text,text[],text,text)') is null then raise exception 'Tenant system update V4.7.1 RPC missing';end if;
  if to_regprocedure('public.tenant_system_revoke_v471(uuid,uuid,text)') is null then raise exception 'Tenant system revoke V4.7.1 RPC missing';end if;
  if to_regprocedure('public.platform_business_delete_v471(uuid)') is null then raise exception 'Business delete V4.7.1 RPC missing';end if;
  if (select max(migration_no) from public.thq_schema_releases)<>114 then raise exception 'V4.7.1 schema release registration incomplete';end if;
end$$;

commit;
select 'THQ ERP V4.7.1 migrations 111-114 verified' as status;
