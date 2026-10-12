-- Migration: 20261012170500_unrestricted_platform_business_delete_v705.sql
-- Description: Unrestricted, complete business deletion from Admin Panel.
-- Bypasses accounting, inventory, and location integrity guards when flexi.platform_business_delete = 'true'.
-- Implements leaf-to-root cascaded deletion of all operational, accounting, GST, and hardware entities.

-- 1. Trigger functions with platform business delete bypass

create or replace function private.payment_accounting_commit_guard_v600()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_tenant uuid;
  v_parent uuid;
  v_origin_created timestamptz;
  v_source_journal boolean:=false;
  v_standalone_count integer:=0;
  v_embedded boolean:=false;
  v_receipt boolean:=false;
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    return new;
  end if;

  if tg_table_name='sale_payments' then
    v_tenant:=new.tenant_id;
    v_parent:=new.sale_id;

    select o.created_at into v_origin_created
    from public.document_origins o
    where o.tenant_id=v_tenant and o.entity_type='sale' and o.entity_id=v_parent
    order by o.created_at limit 1;

    select exists(
      select 1 from public.journal_entries j
      where j.tenant_id=v_tenant and j.source_type='sale' and j.source_id=v_parent and j.status='posted'
    ) into v_source_journal;

    select count(*) into v_standalone_count
    from public.journal_entries j
    where j.tenant_id=v_tenant and j.source_type='sale_payment' and j.source_id=new.id and j.status='posted';

    if v_standalone_count>1 then
      raise exception 'Accounting integrity failure: Sale payment % has multiple posted payment journals', new.id;
    end if;
    if v_standalone_count=1 then return new; end if;

    v_embedded:= v_source_journal and v_origin_created is not null and new.created_at<=v_origin_created;

    if not v_embedded then
      v_embedded:=v_source_journal and exists(
        select 1 from public.sale_payment_allocations_v522 a
        join public.gst_document_snapshots_v520 s
          on s.tenant_id=a.tenant_id and s.source_type='sale' and s.source_id=a.sale_id
        where a.tenant_id=v_tenant and a.sale_id=v_parent and a.sale_payment_id=new.id and a.settlement_amount>0
      );
    end if;

    select exists(
      select 1 from public.customer_receipt_allocations a
      join public.customer_receipts r on r.id=a.receipt_id and r.tenant_id=a.tenant_id
      join public.journal_entries j on j.tenant_id=a.tenant_id and j.source_type='customer_receipt' and j.source_id=r.id and j.status='posted'
      where a.tenant_id=v_tenant and a.payment_id=new.id
    ) into v_receipt;

    if not coalesce(v_embedded,false) and not coalesce(v_receipt,false) then
      raise exception 'Accounting integrity failure: Sale payment % has no valid accounting owner', new.id;
    end if;

    return new;
  end if;

  if tg_table_name='purchase_payments' then
    v_tenant:=new.tenant_id;
    v_parent:=new.purchase_id;

    select o.created_at into v_origin_created
    from public.document_origins o
    where o.tenant_id=v_tenant and o.entity_type='purchase' and o.entity_id=v_parent
    order by o.created_at limit 1;

    select exists(
      select 1 from public.journal_entries j
      where j.tenant_id=v_tenant and j.source_type='purchase' and j.source_id=v_parent and j.status='posted'
    ) into v_source_journal;

    select count(*) into v_standalone_count
    from public.journal_entries j
    where j.tenant_id=v_tenant and j.source_type='purchase_payment' and j.source_id=new.id and j.status='posted';

    if v_standalone_count>1 then
      raise exception 'Accounting integrity failure: Purchase payment % has multiple posted payment journals', new.id;
    end if;
    if v_standalone_count=1 then return new; end if;

    v_embedded:= v_source_journal and v_origin_created is not null and new.created_at<=v_origin_created;

    if not coalesce(v_embedded,false) then
      raise exception 'Accounting integrity failure: Purchase payment % has no valid accounting owner', new.id;
    end if;

    return new;
  end if;

  return new;
end
$function$;

create or replace function private.accounting_commit_guard_v600()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_required boolean:=false;
  v_source_type text;
  v_source_id uuid;
  v_tenant_id uuid;
  v_count integer:=0;
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    return new;
  end if;

  v_source_id:=new.id;
  v_tenant_id:=new.tenant_id;

  case tg_table_name
    when 'sales' then
      v_source_type:='sale';
      select (status='posted') into v_required from public.sales where id=new.id and tenant_id=new.tenant_id;
    when 'purchases' then
      v_source_type:='purchase';
      select (status='posted') into v_required from public.purchases where id=new.id and tenant_id=new.tenant_id;
    when 'expenses' then
      v_source_type:='expense';
      select (status='posted') into v_required from public.expenses where id=new.id and tenant_id=new.tenant_id;
    when 'purchase_invoices_v484' then
      v_source_type:='purchase_invoice_v484';
      select (status in ('posted','part_paid','paid')) into v_required from public.purchase_invoices_v484 where id=new.id and tenant_id=new.tenant_id;
    when 'sales_returns' then
      v_source_type:='sales_return';
      select exists(select 1 from public.sales_returns where id=new.id and tenant_id=new.tenant_id) into v_required;
    when 'purchase_returns' then
      v_source_type:='purchase_return';
      select exists(select 1 from public.purchase_returns where id=new.id and tenant_id=new.tenant_id) into v_required;
    when 'supplier_payments_v484' then
      v_source_type:='supplier_payment_v484';
      select (status='posted') into v_required from public.supplier_payments_v484 where id=new.id and tenant_id=new.tenant_id;
    else
      return new;
  end case;

  if coalesce(v_required,false) is not true then return new; end if;

  select count(*) into v_count
  from public.journal_entries j
  where j.tenant_id=v_tenant_id and j.source_type=v_source_type and j.source_id=v_source_id and j.status='posted';

  if v_count=0 then
    raise exception 'Accounting integrity failure: % % has no posted journal',v_source_type,v_source_id;
  end if;
  if v_count>1 then
    raise exception 'Accounting integrity failure: % % has % posted journals',v_source_type,v_source_id,v_count;
  end if;

  return new;
end
$function$;

create or replace function private.location_stock_integrity_guard_v600()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_tenant uuid;
  v_location uuid;
  v_variant uuid;
  v_balance numeric:=0;
  v_movements numeric:=0;
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    return coalesce(new,old);
  end if;

  if tg_op='DELETE' then
    v_tenant:=old.tenant_id; v_location:=old.location_id; v_variant:=old.variant_id;
  else
    v_tenant:=new.tenant_id; v_location:=new.location_id; v_variant:=new.variant_id;
  end if;

  select coalesce(quantity,0) into v_balance
  from public.location_stock_balances
  where tenant_id=v_tenant and location_id=v_location and variant_id=v_variant;

  if not found then v_balance:=0; end if;

  select coalesce(sum(quantity_delta),0) into v_movements
  from public.location_stock_movements
  where tenant_id=v_tenant and location_id=v_location and variant_id=v_variant;

  if abs(round(v_balance-v_movements,6))>0.0001 then
    raise exception 'Inventory integrity failure: location balance % does not match movement ledger % for variant %',
      v_balance,v_movements,v_variant;
  end if;

  return coalesce(new,old);
end
$function$;

create or replace function private.business_location_active_system_guard_v601()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;

  if old.active and not new.active and exists(
       select 1 from public.business_devices d
       where d.tenant_id=new.tenant_id and d.location_id=new.id and d.status='active'
     ) then
    raise exception 'Deactivate or move active Client/POS systems before deactivating this store';
  end if;
  return new;
end
$function$;

create or replace function public.business_location_active_system_guard_v601()
returns trigger
language plpgsql
as $$
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;
  if old.active and not new.active and exists(
       select 1 from public.business_devices d
       where d.tenant_id=new.tenant_id and d.location_id=new.id and d.status='active'
     ) then
    raise exception 'Deactivate or move active Client/POS systems before deactivating this store';
  end if;
  return new;
end;
$$;

create or replace function private.business_device_active_location_guard_v600()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;

  if new.status='active' then
    if not exists(select 1 from public.tenants t where t.id=new.tenant_id and t.status='active') then
      raise exception 'Cannot activate a system for an inactive business';
    end if;

    if new.location_id is null or not exists(
      select 1 from public.business_locations l
      where l.id=new.location_id and l.tenant_id=new.tenant_id and l.active
    ) then
      raise exception 'Cannot activate a system on an inactive or invalid store';
    end if;
  end if;
  return new;
end
$function$;

create or replace function private.v472_guard_operational_module_change()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;

  if old.app_type='pos'
     and 'cashier_shifts'=any(coalesce(old.allowed_modules,'{}'::text[]))
     and not ('cashier_shifts'=any(coalesce(new.allowed_modules,'{}'::text[])))
     and exists(select 1 from public.cashier_shifts s where s.device_id=old.id and s.status='open') then
    raise exception 'End the open Cashier Shift before deactivating Cashier Shift for this POS';
  end if;
  return new;
end
$function$;

create or replace function private.v472_guard_tenant_operational_module_change()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_tenant_id uuid:=old.tenant_id;
  v_key text:=old.module_key;
  v_was_enabled boolean:=coalesce(old.enabled,false);
  v_will_enabled boolean:=case when tg_op='DELETE' then false else coalesce(new.enabled,false) end;
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;

  if v_key='cashier_shifts' and v_was_enabled and not v_will_enabled
     and exists(select 1 from public.cashier_shifts s where s.tenant_id=v_tenant_id and s.status='open') then
    raise exception 'End all open Cashier Shifts before deactivating Cashier Shift for this business';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end
$function$;

create or replace function public.v472_guard_tenant_operational_module_change()
returns trigger
language plpgsql
as $$
declare
  v_tenant_id uuid:=old.tenant_id;
  v_key text:=old.module_key;
  v_was_enabled boolean:=coalesce(old.enabled,false);
  v_will_enabled boolean:=case when tg_op='DELETE' then false else coalesce(new.enabled,false) end;
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;
  if v_key='cashier_shifts' and v_was_enabled and not v_will_enabled
     and exists(
       select 1 from public.cashier_shifts s
       where s.tenant_id=v_tenant_id and s.status='open'
     ) then
    raise exception 'End all open Cashier Shifts before deactivating Cashier Shift for this business';
  end if;
  if tg_op='DELETE' then return old;end if;
  return new;
end;
$$;

create or replace function private.v600_guard_finding_evidence()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;

  if old.tenant_id is distinct from new.tenant_id
    or old.source_event_id is distinct from new.source_event_id
    or old.correlation_id is distinct from new.correlation_id
    or old.severity is distinct from new.severity
    or old.rule_code is distinct from new.rule_code
    or old.title is distinct from new.title
    or old.description is distinct from new.description
    or old.risk_score is distinct from new.risk_score
    or old.entity_type is distinct from new.entity_type
    or old.entity_id is distinct from new.entity_id
    or old.entity_reference is distinct from new.entity_reference
    or old.location_id is distinct from new.location_id
    or old.device_id is distinct from new.device_id
    or old.actor_user_id is distinct from new.actor_user_id
    or old.detected_at is distinct from new.detected_at
    or old.evidence is distinct from new.evidence then
      raise exception 'Audit finding evidence is immutable; only review lifecycle fields may change' using errcode='55000';
  end if;
  new.updated_at := now();
  return new;
end;
$function$;

create or replace function private.v600_capture_business_row()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_new jsonb := case when tg_op='DELETE' then null else to_jsonb(new) end;
  v_old jsonb := case when tg_op='INSERT' then null else to_jsonb(old) end;
  v_row jsonb := coalesce(v_new,v_old,'{}'::jsonb);
  v_tenant uuid;
  v_entity_type text;
  v_entity_id uuid;
  v_reference text;
  v_root_type text;
  v_root_id uuid;
  v_action text;
  v_actor uuid;
  v_location uuid;
  v_device uuid;
  v_reason text;
  v_approval uuid;
  v_event_time timestamptz;
  v_source_module text;
  v_related jsonb := '[]'::jsonb;
  v_parent jsonb;
  v_changed text[];
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;

  v_changed := private.v600_changed_fields(v_old,v_new);
  if tg_op='UPDATE' and coalesce(array_length(v_changed,1),0)=0 then
    return new;
  end if;

  begin v_tenant := nullif(v_row->>'tenant_id','')::uuid; exception when others then v_tenant := null; end;
  begin v_entity_id := nullif(v_row->>'id','')::uuid; exception when others then v_entity_id := null; end;
  begin v_location := nullif(v_row->>'location_id','')::uuid; exception when others then v_location := null; end;
  begin v_device := nullif(v_row->>'device_id','')::uuid; exception when others then v_device := null; end;
  begin v_approval := nullif(v_row->>'approval_request_id','')::uuid; exception when others then v_approval := null; end;

  v_action := case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'modified' else 'deleted' end;
  v_actor := coalesce(
    nullif(v_row->>'updated_by','')::uuid,
    nullif(v_row->>'decided_by','')::uuid,
    nullif(v_row->>'created_by','')::uuid,
    nullif(v_row->>'requested_by','')::uuid,
    auth.uid()
  );
  v_reason := nullif(trim(coalesce(v_row->>'reason',v_row->>'void_reason',v_row->>'decision_note',v_row->>'note',v_row->>'notes','')),'');
  v_event_time := coalesce(
    nullif(v_row->>'updated_at','')::timestamptz,
    nullif(v_row->>'decided_at','')::timestamptz,
    nullif(v_row->>'paid_at','')::timestamptz,
    nullif(v_row->>'occurred_at','')::timestamptz,
    nullif(v_row->>'posted_at','')::timestamptz,
    nullif(v_row->>'requested_at','')::timestamptz,
    nullif(v_row->>'created_at','')::timestamptz,
    now()
  );

  if tg_table_name='sales' then
    v_entity_type := 'sale'; v_root_type := 'sale'; v_root_id := v_entity_id;
    v_reference := v_row->>'sale_number'; v_source_module := 'sales';
    if tg_op='INSERT' then v_action := 'sale_created';
    elsif tg_op='DELETE' then v_action := 'sale_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'sale_status_changed';
    else v_action := 'sale_modified'; end if;

  elsif tg_table_name='sale_items' then
    v_entity_type := 'sale_item';
    v_root_type := 'sale'; v_root_id := nullif(v_row->>'sale_id','')::uuid;
    v_reference := coalesce(v_row->>'sku',v_row->>'product_name'); v_source_module := 'sales';
    v_related := jsonb_build_array(jsonb_build_object('type','sale','id',v_root_id));
    if tg_op='INSERT' then v_action := 'sale_item_added';
    elsif tg_op='DELETE' then v_action := 'sale_item_removed'; else v_action := 'sale_item_modified'; end if;

  elsif tg_table_name='sale_payments' then
    v_entity_type := 'sale_payment';
    v_root_type := 'sale'; v_root_id := nullif(v_row->>'sale_id','')::uuid;
    select s.sale_number into v_reference from public.sales s where s.tenant_id=v_tenant and s.id=v_root_id;
    v_source_module := 'payments';
    v_related := jsonb_build_array(jsonb_build_object('type','sale','id',v_root_id));
    if tg_op='INSERT' then v_action := 'payment_recorded';
    elsif tg_op='DELETE' then v_action := 'payment_deleted'; else v_action := 'payment_modified'; end if;

  elsif tg_table_name='sales_returns' then
    v_entity_type := 'sales_return';
    v_root_type := 'sale'; v_root_id := nullif(v_row->>'sale_id','')::uuid;
    v_reference := v_row->>'return_number'; v_source_module := 'returns';
    v_related := jsonb_build_array(jsonb_build_object('type','sale','id',v_root_id),jsonb_build_object('type','sales_return','id',v_entity_id));
    if tg_op='INSERT' then v_action := 'sales_return_created';
    elsif tg_op='DELETE' then v_action := 'sales_return_deleted'; else v_action := 'sales_return_modified'; end if;

  elsif tg_table_name='sales_return_items' then
    select to_jsonb(sr) into v_parent
    from public.sales_returns sr where sr.id=nullif(v_row->>'sales_return_id','')::uuid;
    v_tenant := nullif(v_parent->>'tenant_id','')::uuid;
    v_entity_type := 'sales_return_item';
    v_root_type := 'sale'; v_root_id := nullif(v_parent->>'sale_id','')::uuid;
    v_reference := coalesce(v_row->>'sku',v_row->>'product_name'); v_source_module := 'returns';
    v_related := jsonb_build_array(
      jsonb_build_object('type','sale','id',v_root_id),
      jsonb_build_object('type','sales_return','id',nullif(v_row->>'sales_return_id','')::uuid)
    );
    if tg_op='INSERT' then v_action := 'sales_return_item_added';
    elsif tg_op='DELETE' then v_action := 'sales_return_item_removed'; else v_action := 'sales_return_item_modified'; end if;

  elsif tg_table_name='purchases' then
    v_entity_type := 'purchase'; v_root_type := 'purchase'; v_root_id := v_entity_id;
    v_reference := v_row->>'purchase_number'; v_source_module := 'purchases';
    if tg_op='INSERT' then v_action := 'purchase_created';
    elsif tg_op='DELETE' then v_action := 'purchase_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'purchase_status_changed';
    else v_action := 'purchase_modified'; end if;

  elsif tg_table_name='purchase_items' then
    v_entity_type := 'purchase_item';
    v_root_type := 'purchase'; v_root_id := nullif(v_row->>'purchase_id','')::uuid;
    v_reference := coalesce(v_row->>'sku',v_row->>'product_name'); v_source_module := 'purchases';
    v_related := jsonb_build_array(jsonb_build_object('type','purchase','id',v_root_id));
    if tg_op='INSERT' then v_action := 'purchase_item_added';
    elsif tg_op='DELETE' then v_action := 'purchase_item_removed'; else v_action := 'purchase_item_modified'; end if;

  elsif tg_table_name='purchase_payments' then
    v_entity_type := 'purchase_payment';
    v_root_type := 'purchase'; v_root_id := nullif(v_row->>'purchase_id','')::uuid;
    select p.purchase_number into v_reference from public.purchases p where p.tenant_id=v_tenant and p.id=v_root_id;
    v_source_module := 'payments';
    v_related := jsonb_build_array(jsonb_build_object('type','purchase','id',v_root_id));
    if tg_op='INSERT' then v_action := 'payment_recorded';
    elsif tg_op='DELETE' then v_action := 'payment_deleted'; else v_action := 'payment_modified'; end if;

  elsif tg_table_name='purchase_invoices_v484' then
    v_entity_type := 'purchase_invoice'; v_root_type := 'purchase_invoice'; v_root_id := v_entity_id;
    v_reference := coalesce(v_row->>'invoice_number',v_row->>'supplier_invoice_number'); v_source_module := 'invoices';
    if tg_op='INSERT' then v_action := 'invoice_created';
    elsif tg_op='DELETE' then v_action := 'invoice_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'invoice_status_changed';
    else v_action := 'invoice_modified'; end if;

  elsif tg_table_name='purchase_invoice_items_v484' then
    select to_jsonb(pi) into v_parent
    from public.purchase_invoices_v484 pi where pi.id=nullif(v_row->>'purchase_invoice_id','')::uuid;
    v_tenant := nullif(v_parent->>'tenant_id','')::uuid;
    v_entity_type := 'purchase_invoice_item';
    v_root_type := 'purchase_invoice'; v_root_id := nullif(v_row->>'purchase_invoice_id','')::uuid;
    v_reference := coalesce(v_row->>'sku',v_row->>'product_name'); v_source_module := 'invoices';
    v_related := jsonb_build_array(jsonb_build_object('type','purchase_invoice','id',v_root_id));
    if tg_op='INSERT' then v_action := 'invoice_item_added';
    elsif tg_op='DELETE' then v_action := 'invoice_item_removed'; else v_action := 'invoice_item_modified'; end if;

  elsif tg_table_name='supplier_payments_v484' then
    v_entity_type := 'supplier_payment'; v_root_type := 'supplier_payment'; v_root_id := v_entity_id;
    v_reference := v_row->>'payment_number'; v_source_module := 'payments';
    if tg_op='INSERT' then v_action := 'payment_created';
    elsif tg_op='DELETE' then v_action := 'payment_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'payment_status_changed';
    else v_action := 'payment_modified'; end if;

  elsif tg_table_name='document_origins' then
    v_entity_type := 'document_origin';
    v_root_type := v_row->>'entity_type'; v_root_id := nullif(v_row->>'entity_id','')::uuid;
    v_reference := v_row->>'entity_reference'; v_source_module := 'origins';
    v_related := jsonb_build_array(jsonb_build_object('type',v_root_type,'id',v_root_id));
    if tg_op='INSERT' then v_action := 'origin_attached';
    elsif tg_op='DELETE' then v_action := 'origin_detached'; else v_action := 'origin_modified'; end if;

  elsif tg_table_name='approval_requests' then
    v_entity_type := 'approval_request';
    v_root_type := v_row->>'entity_type'; v_root_id := nullif(v_row->>'entity_id','')::uuid;
    v_reference := coalesce(v_row->>'request_number',v_row->>'action'); v_source_module := 'approvals';
    v_related := jsonb_build_array(jsonb_build_object('type',v_root_type,'id',v_root_id));
    if tg_op='INSERT' then v_action := 'approval_requested';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then
      v_action := case v_new->>'status' when 'approved' then 'approval_granted' when 'rejected' then 'approval_rejected' else 'approval_status_changed' end;
    else v_action := 'approval_modified'; end if;

  elsif tg_table_name='journal_entries' then
    v_entity_type := 'journal_entry';
    v_root_type := coalesce(nullif(v_row->>'source_type',''),'journal');
    v_root_id := coalesce(nullif(v_row->>'source_id','')::uuid,v_entity_id);
    v_reference := v_row->>'entry_number'; v_source_module := 'accounting';
    if v_root_type<>'journal' then
      v_related := jsonb_build_array(jsonb_build_object('type',v_root_type,'id',v_root_id));
    end if;
    if tg_op='INSERT' then v_action := 'journal_created';
    elsif tg_op='DELETE' then v_action := 'journal_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'journal_status_changed';
    else v_action := 'journal_modified'; end if;

  elsif tg_table_name='journal_lines' then
    select to_jsonb(j) into v_parent
    from public.journal_entries j where j.id=nullif(v_row->>'journal_entry_id','')::uuid;
    v_tenant := nullif(v_parent->>'tenant_id','')::uuid;
    v_entity_type := 'journal_line';
    v_root_type := coalesce(nullif(v_parent->>'source_type',''),'journal');
    v_root_id := coalesce(nullif(v_parent->>'source_id','')::uuid,nullif(v_row->>'journal_entry_id','')::uuid);
    v_reference := v_parent->>'entry_number'; v_source_module := 'accounting';
    v_related := jsonb_build_array(
      jsonb_build_object('type','journal_entry','id',nullif(v_row->>'journal_entry_id','')::uuid),
      jsonb_build_object('type',v_root_type,'id',v_root_id)
    );
    if tg_op='INSERT' then v_action := 'journal_line_added';
    elsif tg_op='DELETE' then v_action := 'journal_line_removed'; else v_action := 'journal_line_modified'; end if;

  elsif tg_table_name='location_stock_movements' then
    v_entity_type := 'stock_movement';
    v_root_type := coalesce(nullif(v_row->>'source_type',''),'stock_movement');
    v_root_id := coalesce(nullif(v_row->>'source_id','')::uuid,v_entity_id);
    v_reference := coalesce(v_row->>'reference_number',v_row->>'source_type'); v_source_module := 'inventory';
    if v_root_type<>'stock_movement' then
      v_related := jsonb_build_array(jsonb_build_object('type',v_root_type,'id',v_root_id));
    end if;
    if tg_op='INSERT' then v_action := 'movement_recorded';
    elsif tg_op='DELETE' then v_action := 'movement_deleted'; else v_action := 'movement_modified'; end if;

  elsif tg_table_name='stock_adjustment_requests_v500' then
    v_entity_type := 'stock_adjustment'; v_root_type := 'stock_adjustment'; v_root_id := v_entity_id;
    v_reference := v_row->>'request_number'; v_source_module := 'inventory';
    if tg_op='INSERT' then v_action := 'adjustment_requested';
    elsif tg_op='DELETE' then v_action := 'adjustment_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'adjustment_status_changed';
    else v_action := 'adjustment_modified'; end if;

  else
    return coalesce(new,old);
  end if;

  perform private.v600_story_write(
    p_tenant_id => v_tenant,
    p_entity_type => v_entity_type,
    p_entity_id => v_entity_id,
    p_entity_reference => v_reference,
    p_action => v_action,
    p_event_time => v_event_time,
    p_actor_user_id => v_actor,
    p_location_id => v_location,
    p_device_id => v_device,
    p_approval_request_id => v_approval,
    p_before => v_old,
    p_after => v_new,
    p_reason => v_reason,
    p_source_module => v_source_module,
    p_source_function => 'v600_capture_business_row',
    p_root_entity_type => v_root_type,
    p_root_entity_id => v_root_id,
    p_related_entities => v_related,
    p_metadata => jsonb_build_object('table',tg_table_name,'op',tg_op)
  );

  return coalesce(new,old);
end;
$function$;

create or replace function private.aggregate_direct_load_lifecycle_guard_v621()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;

  if tg_op='DELETE' then
    raise exception 'Aggregate loads cannot be deleted directly';
  end if;
  return new;
end;
$function$;

create or replace function private.aggregate_direct_sale_post_guard_v621()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;

  return new;
end;
$function$;

create or replace function private.gst_period_lock_guard_v600()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;

  return new;
end;
$function$;

create or replace function private.gst_provider_job_guard_v600()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;

  if new.tenant_id is distinct from old.tenant_id
     or new.registration_id is distinct from old.registration_id
     or new.snapshot_id is distinct from old.snapshot_id
     or new.return_period_id is distinct from old.return_period_id
     or new.related_job_id is distinct from old.related_job_id
     or new.operation is distinct from old.operation
     or new.request_id is distinct from old.request_id
     or new.provider_key is distinct from old.provider_key
     or new.request_payload is distinct from old.request_payload
     or new.request_hash is distinct from old.request_hash
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'GST provider job immutable request fields cannot be changed';
  end if;
  new.updated_at:=now();
  return new;
end;
$function$;

create or replace function private.v42_validate_location_hierarchy()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare v_parent_tenant uuid; v_found boolean;
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    return new;
  end if;

  if upper(coalesce(new.location_code,''))='MAIN' then
    new.hierarchy_role:='main_store';
  end if;

  if new.hierarchy_role='main_store' then
    new.parent_location_id:=null;
    new.location_type:='head_office';
    new.active:=true;
    new.sort_order:=0;
  elsif new.parent_location_id is null then
    new.parent_location_id:=private.v42_main_location(new.tenant_id);
  end if;

  if new.parent_location_id is not null then
    if new.parent_location_id=new.id then raise exception 'A location cannot be its own parent'; end if;
    select tenant_id into v_parent_tenant from public.business_locations where id=new.parent_location_id;
    if v_parent_tenant is null or v_parent_tenant<>new.tenant_id then raise exception 'Parent location must belong to the same business'; end if;

    with recursive ancestors as (
      select id,parent_location_id from public.business_locations where id=new.parent_location_id
      union all
      select l.id,l.parent_location_id from public.business_locations l join ancestors a on l.id=a.parent_location_id
    )
    select exists(select 1 from ancestors where id=new.id) into v_found;
    if coalesce(v_found,false) then raise exception 'Location hierarchy cycle detected'; end if;
  end if;
  return new;
end;
$function$;


-- 2. Clean preparation function for deleting a business without blocking reservations

create or replace function public.platform_business_prepare_delete_v41(
  p_tenant_id uuid,
  p_confirm_code text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_tenant record;
  v_member record;
begin
  if not private.platform_v2_has_role('super_admin') then
    raise exception 'Super Admin required';
  end if;

  select id,name,business_code,status into v_tenant from public.tenants where id=p_tenant_id;
  if v_tenant.id is null then raise exception 'Business not found'; end if;

  if upper(trim(coalesce(p_confirm_code,'')))<>upper(coalesce(v_tenant.business_code,'')) then
    raise exception 'Business code confirmation does not match';
  end if;

  select division_id,member_type into v_member from public.business_division_members where tenant_id=p_tenant_id;
  if v_member.member_type='main' then
    -- Promote the next child business to 'main' so deletion is never blocked by child businesses
    update public.business_division_members
    set member_type = 'main'
    where id = (
      select id from public.business_division_members
      where division_id = v_member.division_id and tenant_id <> p_tenant_id
      order by joined_at asc, id asc
      limit 1
    );
  end if;

  perform private.platform_audit_write(
    'business.permanent_delete_requested','tenant',p_tenant_id::text,p_tenant_id,
    jsonb_build_object('name',v_tenant.name,'business_code',v_tenant.business_code)
  );

  return jsonb_build_object(
    'tenant_id',v_tenant.id,'name',v_tenant.name,'business_code',v_tenant.business_code,
    'status',v_tenant.status,'division_id',v_member.division_id,'division_role',v_member.member_type
  );
end $function$;


-- 3. Unrestricted leaf-to-root platform_business_delete_v471 implementation

create or replace function public.platform_business_delete_v471(p_tenant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_name text;
  v_division_id uuid;
begin
  if coalesce(auth.role(),'')<>'service_role' and current_user<>'postgres' then
    raise exception 'Service role required';
  end if;
  select name into v_name from public.tenants where id=p_tenant_id for update;
  if v_name is null then raise exception 'Business not found'; end if;

  select division_id into v_division_id from public.business_division_members where tenant_id=p_tenant_id;

  -- Transaction-scoped bypass for immutability and integrity guards
  perform set_config('flexi.platform_business_delete', 'true', true);

  -- 1. Break circular / cross references on staff, load costs, inventory, and accounts
  update public.staff_earnings_v630 set load_cost_id = null where tenant_id=p_tenant_id;
  update public.material_load_costs_v630 set staff_earning_id = null where tenant_id=p_tenant_id;
  update public.inventory_batches_v483 set first_purchase_id = null where tenant_id=p_tenant_id;
  update public.accounting_accounts set parent_id = null where tenant_id=p_tenant_id;
  update public.business_locations set parent_location_id = null where tenant_id=p_tenant_id;
  update public.sale_payments set payment_allocation_id = null where tenant_id=p_tenant_id;

  -- 2. Staff and workforce allocations
  delete from public.staff_payment_allocations_v630 where payment_id in (select id from public.staff_payments_v630 where tenant_id=p_tenant_id);
  delete from public.staff_payments_v630 where tenant_id=p_tenant_id;
  delete from public.material_load_cost_payments_v630 where tenant_id=p_tenant_id;
  delete from public.material_load_costs_v630 where tenant_id=p_tenant_id;
  delete from public.material_load_delivery_v630 where tenant_id=p_tenant_id;
  delete from public.material_load_sale_snapshots_v630 where tenant_id=p_tenant_id;
  delete from public.material_load_requests_v630 where tenant_id=p_tenant_id;
  delete from public.staff_earnings_v630 where tenant_id=p_tenant_id;
  delete from public.staff_attendance_v630 where tenant_id=p_tenant_id;
  delete from public.workforce_audit_v630 where tenant_id=p_tenant_id;
  delete from public.staff_members_v630 where tenant_id=p_tenant_id;

  -- 3. Party settlements and freight
  delete from public.party_settlement_allocations_v626 where tenant_id=p_tenant_id;
  delete from public.party_settlements_v626 where tenant_id=p_tenant_id;
  delete from public.aggregate_freight_settlements_v620 where tenant_id=p_tenant_id;
  delete from public.aggregate_load_events_v617 where load_id in (select id from public.aggregate_loads_v617 where tenant_id=p_tenant_id);
  delete from public.aggregate_order_events_v618 where tenant_id=p_tenant_id;
  delete from public.aggregate_order_lines_v618 where tenant_id=p_tenant_id;
  delete from public.aggregate_orders_v618 where tenant_id=p_tenant_id;
  delete from public.aggregate_loads_v617 where tenant_id=p_tenant_id;
  delete from public.aggregate_vehicle_profiles_v617 where tenant_id=p_tenant_id;
  delete from public.aggregate_direct_transit_locations_v621 where tenant_id=p_tenant_id;

  -- 4. Dependent operational records referencing sales and purchases
  delete from public.product_warranties_v483 where tenant_id=p_tenant_id;
  delete from public.inventory_trace_events_v483 where tenant_id=p_tenant_id;
  delete from public.inventory_serials_v483 where tenant_id=p_tenant_id;
  delete from public.inventory_batches_v483 where tenant_id=p_tenant_id;
  delete from public.inventory_batch_balances_v483 where tenant_id=p_tenant_id;
  delete from public.mobile_pos_receipt_events_v488 where tenant_id=p_tenant_id;
  delete from public.mobile_pos_kot_requests_v488 where tenant_id=p_tenant_id;
  delete from public.mobile_pos_terminal_settings_v488 where tenant_id=p_tenant_id;
  delete from public.sale_commercial_summary_v610 where tenant_id=p_tenant_id;
  delete from public.workshop_job_items where job_id in (select id from public.workshop_job_cards where tenant_id=p_tenant_id);
  delete from public.workshop_job_cards where tenant_id=p_tenant_id;
  delete from public.workshop_vehicles where tenant_id=p_tenant_id;
  delete from public.service_jobs where tenant_id=p_tenant_id;
  delete from public.service_vehicles where tenant_id=p_tenant_id;

  -- 5. Customer receipts & allocations
  delete from public.customer_receipt_allocations where tenant_id=p_tenant_id;
  delete from public.customer_receipts where tenant_id=p_tenant_id;

  -- 6. Supplier payments & invoices
  delete from public.supplier_payment_allocations_v484 where supplier_payment_id in (select id from public.supplier_payments_v484 where tenant_id=p_tenant_id);
  delete from public.supplier_payments_v484 where tenant_id=p_tenant_id;
  delete from public.supplier_ledger_entries_v484 where tenant_id=p_tenant_id;

  -- 7. Sales & Returns
  delete from public.sales_return_items where sales_return_id in (select id from public.sales_returns where tenant_id=p_tenant_id);
  delete from public.sales_returns where tenant_id=p_tenant_id;
  delete from public.sale_payment_allocations_v522 where tenant_id=p_tenant_id;
  delete from public.sale_payments where tenant_id=p_tenant_id;
  delete from public.sale_items where tenant_id=p_tenant_id;
  delete from public.sales where tenant_id=p_tenant_id;

  -- 8. Purchases & Returns
  delete from public.purchase_return_items where purchase_return_id in (select id from public.purchase_returns where tenant_id=p_tenant_id);
  delete from public.purchase_returns where tenant_id=p_tenant_id;
  delete from public.purchase_payments where tenant_id=p_tenant_id;
  delete from public.purchase_invoice_items_v484 where purchase_invoice_id in (select id from public.purchase_invoices_v484 where tenant_id=p_tenant_id);
  delete from public.purchase_invoices_v484 where tenant_id=p_tenant_id;
  delete from public.goods_receipt_items_v484 where goods_receipt_id in (select id from public.goods_receipts_v484 where tenant_id=p_tenant_id);
  delete from public.goods_receipts_v484 where tenant_id=p_tenant_id;
  delete from public.purchase_order_items_v480 where purchase_order_id in (select id from public.purchase_orders_v480 where tenant_id=p_tenant_id);
  delete from public.purchase_orders_v480 where tenant_id=p_tenant_id;
  delete from public.purchase_quotation_items_v500 where quotation_id in (select id from public.purchase_quotations_v500 where tenant_id=p_tenant_id);
  delete from public.purchase_quotations_v500 where tenant_id=p_tenant_id;
  delete from public.purchase_request_items_v484 where request_id in (select id from public.purchase_requests_v484 where tenant_id=p_tenant_id);
  delete from public.purchase_requests_v484 where tenant_id=p_tenant_id;
  delete from public.purchase_items where tenant_id=p_tenant_id;
  delete from public.purchases where tenant_id=p_tenant_id;

  -- 9. GST snapshots and evidence
  delete from public.gst_document_line_snapshots_v520 where tenant_id=p_tenant_id;
  delete from public.gst_document_snapshots_v520 where tenant_id=p_tenant_id;
  delete from public.gst_legacy_document_markers_v520 where tenant_id=p_tenant_id;
  delete from public.gst_portal_itc_documents_v600 where tenant_id=p_tenant_id;
  delete from public.gst_portal_import_batches_v600 where tenant_id=p_tenant_id;
  delete from public.gst_provider_jobs_v600 where tenant_id=p_tenant_id;
  delete from public.gst_return_periods_v600 where tenant_id=p_tenant_id;
  delete from public.gst_turnover_profiles_v600 where tenant_id=p_tenant_id;
  delete from public.gst_invoice_series_v632 where tenant_id=p_tenant_id;
  delete from public.gst_tenant_tax_modes_v520 where tenant_id=p_tenant_id;
  delete from public.gst_registration_versions_v520 where tenant_id=p_tenant_id;
  delete from public.gst_product_tax_profiles_v520 where tenant_id=p_tenant_id;

  -- 10. Audit and story
  delete from public.transaction_story_events_v600 where tenant_id=p_tenant_id;
  delete from public.audit_findings_v600 where tenant_id=p_tenant_id;
  delete from public.transaction_corrections where tenant_id=p_tenant_id;
  delete from public.transaction_requests_v47 where tenant_id=p_tenant_id;

  -- 11. Logistics
  delete from public.transport_logistics_receipt_lines where tenant_id=p_tenant_id;
  delete from public.transport_logistics_receipts where tenant_id=p_tenant_id;
  delete from public.transport_trip_hub_v611 where tenant_id=p_tenant_id;
  delete from public.transport_logistics_trips where tenant_id=p_tenant_id;
  delete from public.transport_logistics_trip_events where tenant_id=p_tenant_id;
  delete from public.transport_logistics_trip_documents where tenant_id=p_tenant_id;
  delete from public.transport_logistics_exceptions where tenant_id=p_tenant_id;
  delete from public.transport_logistics_evidence where tenant_id=p_tenant_id;
  delete from public.logistics_run_stops_v61 where tenant_id=p_tenant_id;
  delete from public.logistics_vehicle_runs_v61 where tenant_id=p_tenant_id;
  delete from public.logistics_operations_v61 where tenant_id=p_tenant_id;
  delete from public.logistics_drivers_v61 where tenant_id=p_tenant_id;
  delete from public.logistics_destinations_v61 where tenant_id=p_tenant_id;
  delete from public.logistics_operation_events_v61 where tenant_id=p_tenant_id;
  delete from public.logistics_stop_evidence where tenant_id=p_tenant_id;
  delete from public.logistics_variances where tenant_id=p_tenant_id;
  delete from public.logistics_document_links where tenant_id=p_tenant_id;
  delete from public.logistics_stops where tenant_id=p_tenant_id;
  delete from public.logistics_vehicle_runs where tenant_id=p_tenant_id;
  delete from public.logistics_drivers where tenant_id=p_tenant_id;
  delete from public.logistics_destinations where tenant_id=p_tenant_id;
  delete from public.logistics_operations where tenant_id=p_tenant_id;

  -- 12. Loans
  delete from public.loan_payment_allocations_v490 where tenant_id=p_tenant_id;
  delete from public.loan_payments_v490 where tenant_id=p_tenant_id;
  delete from public.loan_schedule_v490 where tenant_id=p_tenant_id;
  delete from public.loan_rate_history_v490 where tenant_id=p_tenant_id;
  delete from public.loan_guarantors_v490 where tenant_id=p_tenant_id;
  delete from public.loan_collateral_v490 where tenant_id=p_tenant_id;
  delete from public.loan_events_v490 where tenant_id=p_tenant_id;
  delete from public.loan_accounts_v490 where tenant_id=p_tenant_id;

  -- 13. Finance and accounts
  delete from public.finance_vouchers_v500 where tenant_id=p_tenant_id;
  delete from public.bank_statement_lines_v500 where tenant_id=p_tenant_id;
  delete from public.bank_accounts_v500 where tenant_id=p_tenant_id;
  delete from public.opening_balance_batches_v500 where tenant_id=p_tenant_id;
  delete from public.recurring_expenses_v500 where tenant_id=p_tenant_id;
  delete from public.expenses where tenant_id=p_tenant_id;
  delete from public.journal_lines where journal_entry_id in (select id from public.journal_entries where tenant_id=p_tenant_id);
  delete from public.journal_entries where tenant_id=p_tenant_id;
  delete from public.document_origins where tenant_id=p_tenant_id;
  delete from public.accounting_account_mappings where tenant_id=p_tenant_id;
  delete from public.payment_methods_v522 where tenant_id=p_tenant_id;
  delete from public.financial_years_v500 where tenant_id=p_tenant_id;
  update public.accounting_accounts set parent_id = null where tenant_id=p_tenant_id;
  delete from public.accounting_accounts where tenant_id=p_tenant_id;

  -- 14. Stock & inventory
  delete from public.stock_transfer_allocations_v485 where tenant_id=p_tenant_id;
  delete from public.stock_transfer_history_v485 where tenant_id=p_tenant_id;
  delete from public.stock_transfer_items where transfer_id in (select id from public.stock_transfers where tenant_id=p_tenant_id);
  delete from public.stock_transfers where tenant_id=p_tenant_id;
  delete from public.stock_adjustment_requests_v500 where tenant_id=p_tenant_id;
  delete from public.stock_count_items where count_id in (select id from public.stock_counts where tenant_id=p_tenant_id);
  delete from public.stock_counts where tenant_id=p_tenant_id;
  delete from public.location_stock_movements where tenant_id=p_tenant_id;
  delete from public.location_stock_balances where tenant_id=p_tenant_id;
  delete from public.stock_movements where tenant_id=p_tenant_id;
  delete from public.stock_balances where tenant_id=p_tenant_id;
  delete from public.product_identifiers_v482 where tenant_id=p_tenant_id;
  delete from public.product_identifier_sequences_v482 where tenant_id=p_tenant_id;
  delete from public.product_tracking_policies_v483 where tenant_id=p_tenant_id;
  delete from private.tracking_conversions_v633 where tenant_id=p_tenant_id;

  -- 15. Production & restaurant
  delete from public.production_material_reservations where tenant_id=p_tenant_id;
  delete from public.production_runs where tenant_id=p_tenant_id;
  delete from public.production_recipe_items where tenant_id=p_tenant_id;
  delete from public.production_recipes where tenant_id=p_tenant_id;
  delete from public.production_bom_items where bom_id in (select id from public.production_boms where tenant_id=p_tenant_id);
  delete from public.production_boms where tenant_id=p_tenant_id;

  delete from public.restaurant_kot_items where tenant_id=p_tenant_id;
  delete from public.restaurant_kots where tenant_id=p_tenant_id;
  delete from public.restaurant_order_modifiers where tenant_id=p_tenant_id;
  delete from public.restaurant_order_items where tenant_id=p_tenant_id;
  delete from public.restaurant_orders where tenant_id=p_tenant_id;
  delete from public.restaurant_waiter_assignments where tenant_id=p_tenant_id;
  delete from public.restaurant_table_events where tenant_id=p_tenant_id;
  delete from public.restaurant_tables where tenant_id=p_tenant_id;
  delete from public.restaurant_waitlist where tenant_id=p_tenant_id;

  -- 16. POS & Cashiers
  delete from public.cashier_shifts where tenant_id=p_tenant_id;
  delete from public.pos_offline_sync_v486 where tenant_id=p_tenant_id;
  delete from public.pos_held_sales where tenant_id=p_tenant_id;
  delete from public.pos_device_preferences where tenant_id=p_tenant_id;

  -- 17. Systems & devices
  delete from public.system_installations where tenant_id=p_tenant_id or system_id in (select id from public.business_devices where tenant_id=p_tenant_id);
  delete from public.device_app_status where tenant_id=p_tenant_id;
  delete from public.business_devices where tenant_id=p_tenant_id;

  -- 18. Users & Memberships
  delete from public.user_login_names where tenant_id=p_tenant_id;
  delete from public.user_roles where tenant_id=p_tenant_id;
  delete from public.user_preferences_v4 where tenant_id=p_tenant_id;
  delete from public.user_saved_views where tenant_id=p_tenant_id;
  delete from public.business_user_location_access where tenant_id=p_tenant_id;
  delete from public.business_user_app_access where tenant_id=p_tenant_id;
  delete from public.business_division_members where tenant_id=p_tenant_id;
  delete from public.tenant_memberships where tenant_id=p_tenant_id;

  -- 19. Catalogue, CRM & locations
  delete from public.price_list_items_v482 where tenant_id=p_tenant_id;
  delete from public.price_lists_v482 where tenant_id=p_tenant_id;
  delete from public.customer_pricing_profiles_v482 where tenant_id=p_tenant_id;
  delete from public.customer_prices_v482 where tenant_id=p_tenant_id;
  delete from public.customer_crm_profiles_v500 where tenant_id=p_tenant_id;
  delete from public.customer_loyalty_ledger_v500 where tenant_id=p_tenant_id;
  delete from public.customer_groups_v500 where tenant_id=p_tenant_id;
  delete from public.product_variants where tenant_id=p_tenant_id;
  delete from public.products where tenant_id=p_tenant_id;
  delete from public.product_brands where tenant_id=p_tenant_id;
  delete from public.product_categories where tenant_id=p_tenant_id;
  delete from public.product_units_v481 where tenant_id=p_tenant_id;
  delete from public.product_charge_rules_v610 where tenant_id=p_tenant_id;
  delete from public.sales_charge_catalog_v610 where tenant_id=p_tenant_id;
  delete from public.product_invoice_attributes_v45 where tenant_id=p_tenant_id;
  delete from public.customers where tenant_id=p_tenant_id;
  delete from public.suppliers where tenant_id=p_tenant_id;
  delete from public.location_product_settings where tenant_id=p_tenant_id;
  delete from public.location_document_numbers where tenant_id=p_tenant_id;
  delete from public.location_document_counters where tenant_id=p_tenant_id;
  delete from public.gst_location_registrations_v520 where tenant_id=p_tenant_id;
  delete from public.printer_profiles where tenant_id=p_tenant_id;
  delete from public.business_task_comments_v500 where tenant_id=p_tenant_id;
  delete from public.business_task_history_v500 where tenant_id=p_tenant_id;
  delete from public.business_tasks where tenant_id=p_tenant_id;
  delete from public.business_audit_log where tenant_id=p_tenant_id;
  delete from public.transaction_import_documents_v490 where tenant_id=p_tenant_id;
  delete from public.transaction_import_runs_v490 where tenant_id=p_tenant_id;
  delete from public.document_output_events_v495 where tenant_id=p_tenant_id;
  update public.business_locations set parent_location_id = null where tenant_id=p_tenant_id;
  delete from public.business_locations where tenant_id=p_tenant_id;

  -- 20. Settings & sync
  delete from public.tenant_settings_v2 where tenant_id=p_tenant_id;
  delete from public.tenant_settings where tenant_id=p_tenant_id;
  delete from public.tenant_modules where tenant_id=p_tenant_id;
  delete from public.tenant_ui_designs where tenant_id=p_tenant_id;
  delete from public.tenant_subscriptions where tenant_id=p_tenant_id;
  delete from public.tenant_invoice_template_assignments_v45 where tenant_id=p_tenant_id;
  delete from public.tenant_invoice_templates where tenant_id=p_tenant_id;
  delete from public.tenant_code_counters where tenant_id=p_tenant_id;
  delete from public.thq_sync_events_v480 where tenant_id=p_tenant_id;
  delete from public.thq_sync_state_v480 where tenant_id=p_tenant_id;
  delete from public.notifications where tenant_id=p_tenant_id;
  delete from public.report_export_events where tenant_id=p_tenant_id;
  delete from public.support_tickets where tenant_id=p_tenant_id;

  -- 21. Finally delete the tenant row
  delete from public.tenants where id=p_tenant_id;

  -- Clean up division if empty
  if v_division_id is not null then
    delete from public.business_divisions
    where id=v_division_id
      and not exists(select 1 from public.business_division_members where division_id=v_division_id);
  end if;

  return jsonb_build_object('success',true,'tenant_id',p_tenant_id,'business_name',v_name);
end $$;

revoke all on function public.platform_business_delete_v471(uuid) from public, anon, authenticated;
grant execute on function public.platform_business_delete_v471(uuid) to service_role;
grant execute on function public.platform_business_prepare_delete_v41(uuid, text) to authenticated, service_role;
