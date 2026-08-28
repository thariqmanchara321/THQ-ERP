-- FLEXI ERP V3.2
-- Atomic location/device scoped transaction wrappers.
-- These wrappers call the already-proven core transaction RPCs, then attach the
-- branch/terminal origin in the SAME database transaction. If the origin or
-- location permission check fails, the core transaction is rolled back too.
begin;

create schema if not exists private;

create or replace function private.erp_validate_transaction_origin(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_required_pos_module text
)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_app text;
  v_device_location uuid;
  v_modules text[];
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if p_location_id is null then raise exception 'A business location is required'; end if;
  if not private.erp_user_location_allowed(p_tenant_id,p_location_id,'operate') then
    raise exception 'You cannot create records for this location';
  end if;

  if p_device_id is null then raise exception 'A registered system is required'; end if;
  select d.app_type,d.location_id,d.allowed_modules
    into v_app,v_device_location,v_modules
  from public.business_devices d
  where d.id=p_device_id and d.tenant_id=p_tenant_id and d.status='active';
  if not found then raise exception 'Registered system is invalid or revoked'; end if;

  -- A POS is fixed to its own store and its per-terminal module selection.
  if v_app='pos' then
    if v_device_location is distinct from p_location_id then
      raise exception 'POS terminals can only post to their assigned store';
    end if;
    if p_required_pos_module is not null and not (p_required_pos_module = any(coalesce(v_modules,'{}'::text[]))) then
      raise exception 'This POS terminal is not enabled for %',p_required_pos_module;
    end if;
  elsif v_app <> 'client' then
    raise exception 'Unsupported system type';
  end if;
end $$;
revoke all on function private.erp_validate_transaction_origin(uuid,uuid,uuid,text) from public;

create or replace function public.sales_create_v32(
  p_tenant_id uuid,
  p_customer_id uuid,
  p_sale_date date,
  p_due_date date,
  p_items jsonb,
  p_additional_charges numeric,
  p_initial_payment numeric,
  p_payment_method text,
  p_payment_reference text,
  p_notes text,
  p_location_id uuid,
  p_device_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_result jsonb;
  v_ref text;
  v_id uuid;
  v_origin jsonb;
begin
  perform private.erp_validate_transaction_origin(p_tenant_id,p_location_id,p_device_id,'sales');

  select public.sales_create(
    p_tenant_id=>p_tenant_id,
    p_customer_id=>p_customer_id,
    p_sale_date=>p_sale_date,
    p_due_date=>p_due_date,
    p_items=>p_items,
    p_additional_charges=>p_additional_charges,
    p_initial_payment=>p_initial_payment,
    p_payment_method=>p_payment_method,
    p_payment_reference=>p_payment_reference,
    p_notes=>p_notes
  ) into v_result;

  v_ref:=coalesce(v_result->>'sale_number',v_result->>'number');
  if nullif(v_ref,'') is null then raise exception 'Sale transaction did not return a sale number'; end if;
  v_id:=public.document_origin_attach_by_reference(p_tenant_id,'sale',v_ref,p_location_id,p_device_id);
  v_origin:=public.document_origin_get(p_tenant_id,'sale',v_id);
  return coalesce(v_result,'{}'::jsonb) || jsonb_build_object(
    'sale_id',coalesce(v_result->>'sale_id',v_id::text),
    'invoice_number',v_origin->>'invoice_number',
    'location_id',p_location_id,
    'device_id',p_device_id
  );
end $$;
grant execute on function public.sales_create_v32(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid) to authenticated;

create or replace function public.purchases_create_v32(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_supplier_invoice_number text,
  p_purchase_date date,
  p_due_date date,
  p_items jsonb,
  p_additional_charges numeric,
  p_initial_payment numeric,
  p_payment_method text,
  p_notes text,
  p_location_id uuid,
  p_device_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_result jsonb;
  v_ref text;
  v_id uuid;
  v_origin jsonb;
begin
  perform private.erp_validate_transaction_origin(p_tenant_id,p_location_id,p_device_id,'purchases');

  select public.purchases_create(
    p_tenant_id=>p_tenant_id,
    p_supplier_id=>p_supplier_id,
    p_supplier_invoice_number=>p_supplier_invoice_number,
    p_purchase_date=>p_purchase_date,
    p_due_date=>p_due_date,
    p_items=>p_items,
    p_additional_charges=>p_additional_charges,
    p_initial_payment=>p_initial_payment,
    p_payment_method=>p_payment_method,
    p_notes=>p_notes
  ) into v_result;

  v_ref:=coalesce(v_result->>'purchase_number',v_result->>'number');
  if nullif(v_ref,'') is null then raise exception 'Purchase transaction did not return a purchase number'; end if;
  v_id:=public.document_origin_attach_by_reference(p_tenant_id,'purchase',v_ref,p_location_id,p_device_id);
  v_origin:=public.document_origin_get(p_tenant_id,'purchase',v_id);
  return coalesce(v_result,'{}'::jsonb) || jsonb_build_object(
    'purchase_id',coalesce(v_result->>'purchase_id',v_id::text),
    'invoice_number',v_origin->>'invoice_number',
    'location_id',p_location_id,
    'device_id',p_device_id
  );
end $$;
grant execute on function public.purchases_create_v32(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid) to authenticated;

create or replace function public.expenses_create_v32(
  p_tenant_id uuid,
  p_category_id uuid,
  p_expense_date date,
  p_payee text,
  p_description text,
  p_amount numeric,
  p_tax_amount numeric,
  p_payment_method text,
  p_reference_number text,
  p_notes text,
  p_location_id uuid,
  p_device_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_result jsonb;
  v_ref text;
  v_id uuid;
  v_origin jsonb;
begin
  perform private.erp_validate_transaction_origin(p_tenant_id,p_location_id,p_device_id,'expenses');

  select public.expenses_create(
    p_tenant_id=>p_tenant_id,
    p_category_id=>p_category_id,
    p_expense_date=>p_expense_date,
    p_payee=>p_payee,
    p_description=>p_description,
    p_amount=>p_amount,
    p_tax_amount=>p_tax_amount,
    p_payment_method=>p_payment_method,
    p_reference_number=>p_reference_number,
    p_notes=>p_notes
  ) into v_result;

  v_ref:=coalesce(v_result->>'expense_number',v_result->>'number');
  if nullif(v_ref,'') is null then raise exception 'Expense transaction did not return an expense number'; end if;
  v_id:=public.document_origin_attach_by_reference(p_tenant_id,'expense',v_ref,p_location_id,p_device_id);
  v_origin:=public.document_origin_get(p_tenant_id,'expense',v_id);
  return coalesce(v_result,'{}'::jsonb) || jsonb_build_object(
    'expense_id',coalesce(v_result->>'expense_id',v_id::text),
    'invoice_number',v_origin->>'invoice_number',
    'location_id',p_location_id,
    'device_id',p_device_id
  );
end $$;
grant execute on function public.expenses_create_v32(uuid,uuid,date,text,text,numeric,numeric,text,text,text,uuid,uuid) to authenticated;


-- Friendly immutable IDs while preserving the existing permission-aware list RPCs.
create or replace function public.customers_list_v32(p_tenant_id uuid)
returns setof jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_row jsonb;v_id uuid;v_code text;
begin
  for v_row in select to_jsonb(x) from public.customers_list(p_tenant_id) x loop
    begin v_id:=coalesce(nullif(v_row->>'customer_id',''),nullif(v_row->>'id',''))::uuid; exception when others then v_id:=null; end;
    if v_id is not null then select tracking_code into v_code from public.customers where tenant_id=p_tenant_id and id=v_id; end if;
    return next v_row || jsonb_build_object('tracking_code',v_code,'public_id',v_code);
  end loop;
  return;
end $$;
grant execute on function public.customers_list_v32(uuid) to authenticated;

create or replace function public.suppliers_list_v32(p_tenant_id uuid)
returns setof jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_row jsonb;v_id uuid;v_code text;
begin
  for v_row in select to_jsonb(x) from public.suppliers_list(p_tenant_id) x loop
    begin v_id:=coalesce(nullif(v_row->>'supplier_id',''),nullif(v_row->>'id',''))::uuid; exception when others then v_id:=null; end;
    if v_id is not null then select tracking_code into v_code from public.suppliers where tenant_id=p_tenant_id and id=v_id; end if;
    return next v_row || jsonb_build_object('tracking_code',v_code,'public_id',v_code);
  end loop;
  return;
end $$;
grant execute on function public.suppliers_list_v32(uuid) to authenticated;

commit;
select 'V3.2 atomic scoped transaction wrappers ready' as status;
