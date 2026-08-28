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
