-- THQ ERP Migration 20261013110000_transaction_void_authorization_v711.sql
-- Fix Purchase and Sale void workflows:
-- 1. Update purchases_status_check and sales_status_check to allow 'void' and 'draft'
-- 2. Allow authorized void operations in private.gst_v520_guard_authoritative_header via session setting
-- 3. Enhance public.purchase_void_v4 and public.sales_void_v4 to set flexi.allow_document_void,
--    unlink linked aggregate material loads, and support manager permissions.

-- 1. Status constraints
alter table public.purchases drop constraint if exists purchases_status_check;
alter table public.purchases add constraint purchases_status_check
  check (status = any (array['posted'::text, 'cancelled'::text, 'void'::text, 'draft'::text]));

alter table public.sales drop constraint if exists sales_status_check;
alter table public.sales add constraint sales_status_check
  check (status = any (array['posted'::text, 'cancelled'::text, 'void'::text, 'draft'::text]));

-- 2. Update authoritative header guard to allow authorized void workflows
create or replace function private.gst_v520_guard_authoritative_header()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_row_old jsonb := case when tg_op = 'INSERT' then '{}'::jsonb else to_jsonb(old) end;
  v_row_new jsonb := case when tg_op = 'DELETE' then '{}'::jsonb else to_jsonb(new) end;
  v_tenant_id uuid := nullif(v_row_old->>'tenant_id','')::uuid;
  v_source_id uuid := nullif(v_row_old->>'id','')::uuid;
  v_key text;
  v_new_status text;
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if current_setting('flexi.allow_document_void', true) = 'true' then
    return new;
  end if;

  if v_tenant_id is null or v_source_id is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if not private.gst_v520_authoritative_snapshot_exists(v_tenant_id, v_source_id) then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'DELETE' then
    raise exception 'Authoritative GST v5.2 document cannot be deleted. Use the v5.2 return/credit-note or correction workflow.';
  end if;

  v_new_status := lower(coalesce(v_row_new->>'status',''));
  if v_new_status in ('void','voided','cancel','cancelled','canceled')
     and lower(coalesce(v_row_old->>'status','')) is distinct from v_new_status then
    raise exception 'Authoritative GST v5.2 document cannot use a legacy void/cancel path. Use the v5.2 return/credit-note workflow.';
  end if;

  foreach v_key in array array[
    'customer_id','supplier_id','sale_date','purchase_date','invoice_date','return_date',
    'location_id','sale_number','purchase_number','invoice_number','supplier_invoice_number',
    'subtotal','discount_total','tax_total','additional_charges','round_off','grand_total',
    'sale_id','purchase_id','purchase_order_id'
  ] loop
    if (v_row_old ? v_key or v_row_new ? v_key)
       and (v_row_old->v_key) is distinct from (v_row_new->v_key) then
      raise exception 'Authoritative GST v5.2 document field "%" is immutable after posting. Use a v5.2 correction/return workflow.', v_key;
    end if;
  end loop;

  return new;
end;
$$;

-- 3. Enhance purchase_void_v4
create or replace function public.purchase_void_v4(
  p_tenant_id uuid,
  p_purchase_id uuid,
  p_reason text,
  p_device_id uuid default null
) returns void
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_loc uuid;
  v_ref text;
  r record;
begin
  if trim(coalesce(p_reason,'')) = '' then
    raise exception 'Void reason is required';
  end if;

  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id, 'purchases.void')
     and not private.erp_has_permission(p_tenant_id, 'purchases.manage') then
    raise exception 'Purchase void permission required';
  end if;

  if exists(select 1 from public.purchase_payments where purchase_id = p_purchase_id and amount <> 0) then
    raise exception 'Paid purchase cannot be voided directly. Use purchase return/refund workflow.';
  end if;

  if exists(select 1 from public.purchase_returns where purchase_id = p_purchase_id) then
    raise exception 'Purchase with returns cannot be voided';
  end if;

  select o.location_id, p.purchase_number
  into v_loc, v_ref
  from public.purchases p
  join public.document_origins o on o.entity_type = 'purchase' and o.entity_id = p.id
  where p.id = p_purchase_id and p.tenant_id = p_tenant_id
  for update;

  if v_loc is null then
    raise exception 'Purchase not found or has no branch origin';
  end if;

  perform private.v4_location_access(p_tenant_id, v_loc, 'operate');

  for r in select pi.variant_id, pi.quantity, pr.item_type
           from public.purchase_items pi
           join public.product_variants pv on pv.id = pi.variant_id
           join public.products pr on pr.id = pv.product_id
           where pi.purchase_id = p_purchase_id loop
    if r.item_type = 'stock' then
      if coalesce((select quantity from public.location_stock_balances where tenant_id = p_tenant_id and location_id = v_loc and variant_id = r.variant_id), 0) < r.quantity then
        raise exception 'Cannot void purchase because branch stock has already been consumed';
      end if;
      perform public.inventory_adjust_stock(p_tenant_id, r.variant_id, -r.quantity, 'Void purchase • ' || v_ref);
      perform private.v4_location_stock_apply(p_tenant_id, v_loc, r.variant_id, -r.quantity, 'purchase_return', 'purchase', p_purchase_id, v_ref, 'Void • ' || trim(p_reason), p_device_id, false);
    end if;
  end loop;

  perform set_config('flexi.allow_document_void', 'true', true);

  update public.purchases
  set status = 'void'
  where id = p_purchase_id and tenant_id = p_tenant_id;

  -- Unlink any associated material yard load
  update public.aggregate_loads_v617
  set purchase_id = null
  where tenant_id = p_tenant_id and purchase_id = p_purchase_id;

  insert into public.transaction_corrections(
    tenant_id, entity_type, entity_id, correction_type, reason, created_by
  ) values(
    p_tenant_id, 'purchase', p_purchase_id, 'void', trim(p_reason), auth.uid()
  );
end;
$$;

-- 4. Enhance sales_void_v4
create or replace function public.sales_void_v4(
  p_tenant_id uuid,
  p_sale_id uuid,
  p_reason text,
  p_device_id uuid default null
) returns void
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_loc uuid;
  v_ref text;
  r record;
begin
  if trim(coalesce(p_reason,'')) = '' then
    raise exception 'Void reason is required';
  end if;

  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id, 'sales.void')
     and not private.erp_has_permission(p_tenant_id, 'sales.manage') then
    raise exception 'Sales void permission required';
  end if;

  if exists(select 1 from public.sale_payments where sale_id = p_sale_id and amount <> 0) then
    raise exception 'Paid sale cannot be voided directly. Use return/refund workflow.';
  end if;

  if exists(select 1 from public.sales_returns where sale_id = p_sale_id) then
    raise exception 'Sale with returns cannot be voided';
  end if;

  select o.location_id, s.sale_number
  into v_loc, v_ref
  from public.sales s
  join public.document_origins o on o.entity_type = 'sale' and o.entity_id = s.id
  where s.id = p_sale_id and s.tenant_id = p_tenant_id
  for update;

  if v_loc is null then
    raise exception 'Sale not found or has no branch origin';
  end if;

  perform private.v4_location_access(p_tenant_id, v_loc, 'operate');

  for r in select si.variant_id, si.quantity, p.item_type
           from public.sale_items si
           join public.product_variants pv on pv.id = si.variant_id
           join public.products p on p.id = pv.product_id
           where si.sale_id = p_sale_id loop
    if r.item_type = 'stock' then
      perform public.inventory_adjust_stock(p_tenant_id, r.variant_id, r.quantity, 'Void sale • ' || v_ref);
      perform private.v4_location_stock_apply(p_tenant_id, v_loc, r.variant_id, r.quantity, 'sale_return', 'sale', p_sale_id, v_ref, 'Void • ' || trim(p_reason), p_device_id, false);
    end if;
  end loop;

  perform set_config('flexi.allow_document_void', 'true', true);

  update public.sales
  set status = 'void'
  where id = p_sale_id and tenant_id = p_tenant_id;

  -- Unlink any associated material yard load
  update public.aggregate_loads_v617
  set sale_id = null
  where tenant_id = p_tenant_id and sale_id = p_sale_id;

  insert into public.transaction_corrections(
    tenant_id, entity_type, entity_id, correction_type, reason, created_by
  ) values(
    p_tenant_id, 'sale', p_sale_id, 'void', trim(p_reason), auth.uid()
  );
end;
$$;

revoke all on function public.purchase_void_v4(uuid, uuid, text, uuid) from public, anon;
grant execute on function public.purchase_void_v4(uuid, uuid, text, uuid) to authenticated, service_role;

revoke all on function public.sales_void_v4(uuid, uuid, text, uuid) from public, anon;
grant execute on function public.sales_void_v4(uuid, uuid, text, uuid) to authenticated, service_role;
