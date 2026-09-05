create or replace function private.gst_v520_authoritative_snapshot_exists(
  p_tenant_id uuid,
  p_source_id uuid
) returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select exists(
    select 1
    from public.gst_document_snapshots_v520 s
    where s.tenant_id = p_tenant_id
      and s.source_id = p_source_id
  );
$$;

revoke all on function private.gst_v520_authoritative_snapshot_exists(uuid,uuid) from public;

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
  if v_tenant_id is null or v_source_id is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if not private.gst_v520_authoritative_snapshot_exists(v_tenant_id,v_source_id) then
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

revoke all on function private.gst_v520_guard_authoritative_header() from public;

create or replace function private.gst_v520_guard_authoritative_line()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_tenant_id uuid;
  v_source_id uuid;
begin
  case tg_table_name
    when 'sale_items' then
      v_source_id := nullif(v_row->>'sale_id','')::uuid;
      select s.tenant_id into v_tenant_id from public.sales s where s.id = v_source_id;
    when 'purchase_items' then
      v_source_id := nullif(v_row->>'purchase_id','')::uuid;
      select p.tenant_id into v_tenant_id from public.purchases p where p.id = v_source_id;
    when 'purchase_invoice_items_v484' then
      v_source_id := nullif(v_row->>'purchase_invoice_id','')::uuid;
      select i.tenant_id into v_tenant_id from public.purchase_invoices_v484 i where i.id = v_source_id;
    when 'sales_return_items' then
      v_source_id := nullif(v_row->>'sales_return_id','')::uuid;
      select r.tenant_id into v_tenant_id from public.sales_returns r where r.id = v_source_id;
    when 'purchase_return_items' then
      v_source_id := nullif(v_row->>'purchase_return_id','')::uuid;
      select r.tenant_id into v_tenant_id from public.purchase_returns r where r.id = v_source_id;
    else
      return case when tg_op = 'DELETE' then old else new end;
  end case;

  if v_tenant_id is not null
     and v_source_id is not null
     and private.gst_v520_authoritative_snapshot_exists(v_tenant_id,v_source_id) then
    raise exception 'Authoritative GST v5.2 line items are immutable after posting. Use the v5.2 return/credit-note or correction workflow.';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.gst_v520_guard_authoritative_line() from public;

do $$
declare
  t text;
begin
  foreach t in array array['sales','purchases','purchase_invoices_v484','sales_returns','purchase_returns'] loop
    execute format('drop trigger if exists trg_v520_authoritative_header_guard on public.%I', t);
    execute format(
      'create trigger trg_v520_authoritative_header_guard before update or delete on public.%I for each row execute function private.gst_v520_guard_authoritative_header()',
      t
    );
  end loop;

  foreach t in array array['sale_items','purchase_items','purchase_invoice_items_v484','sales_return_items','purchase_return_items'] loop
    execute format('drop trigger if exists trg_v520_authoritative_line_guard on public.%I', t);
    execute format(
      'create trigger trg_v520_authoritative_line_guard before insert or update or delete on public.%I for each row execute function private.gst_v520_guard_authoritative_line()',
      t
    );
  end loop;
end;
$$;