-- Migration: 20261012154500_business_delete_integrity_and_auto_reset_v704.sql
-- Description: Enable graceful business deletion in Admin Panel by bypassing immutability triggers
-- during platform_business_delete_v471, breaking circular foreign keys, and providing
-- verify_device_binding_v704 for activated client and POS systems to auto-reset.

-- 1. Trigger functions with platform business delete bypass

create or replace function private.gst_snapshot_immutable_v520()
returns trigger
language plpgsql
set search_path = public, private, pg_temp
as $$
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  raise exception 'GST evidence is immutable. Use a linked return, credit/debit note or amendment instead of editing/deleting the original GST evidence';
end;
$$;

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
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

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

create or replace function private.v600_block_story_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  raise exception 'THQ v6.0 transaction story is append-only; % is not permitted', tg_op
    using errcode='55000';
end;
$$;

create or replace function private.gst_append_only_guard_v600()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  raise exception 'GST portal import evidence is append-only';
end;
$$;

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

create or replace function public.business_location_active_system_guard_v601()
returns trigger
language plpgsql
as $$
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;
  if old.active
     and not new.active
     and exists(
       select 1
       from public.business_devices d
       where d.tenant_id=new.tenant_id
         and d.location_id=new.id
         and d.status='active'
     ) then
    raise exception
      'Deactivate or move active Client/POS systems before deactivating this store';
  end if;
  return new;
end;
$$;

create or replace function private.audit_capture_v704()
returns trigger
language plpgsql
as $$
declare r jsonb;b jsonb;a jsonb;cfg jsonb;t uuid;eid uuid;root_id uuid;root_type text;lid uuid;reference text;related jsonb:='[]';
begin
 if current_setting('flexi.platform_business_delete', true) = 'true' then
   if tg_op='DELETE' then return old; else return new; end if;
 end if;
 b:=case when tg_op<>'INSERT' then to_jsonb(old) end;
 a:=case when tg_op<>'DELETE' then to_jsonb(new) end;
 if tg_op='UPDATE' and b is not distinct from a then return new;end if;
 r:=coalesce(a,b);t:=(r->>'tenant_id')::uuid;eid:=(r->>'id')::uuid;
 select value into cfg from jsonb_array_elements(private.audit_catalog_v704()) where value->>'key'=tg_table_name;
 if cfg is null then raise exception 'Audit capture table is not registered';end if;
 root_id:=eid;root_type:=cfg->>'entity';
 if cfg->'parent'<>'null'::jsonb and nullif(r->>(cfg#>>'{parent,0}'),'') is not null then
  root_id:=(r->>(cfg#>>'{parent,0}'))::uuid;
  select value->>'entity' into root_type from jsonb_array_elements(private.audit_catalog_v704()) where value->>'key'=cfg#>>'{parent,1}';
  related:=jsonb_build_array(jsonb_build_object('type',root_type,'id',root_id));
 end if;
 select l into lid from unnest(private.audit_record_locations_v704(t,tg_table_name,r)) l where l is not null limit 1;
 reference:=coalesce(r->>'sale_number',r->>'purchase_number',r->>'payment_number',r->>'receipt_number',r->>'loan_number',r->>'load_number',r->>'order_number',r->>'trip_number',r->>'voucher_number',r->>'job_number',r->>'run_number',r->>'staff_code',r->>'return_number',r->>'name',cfg->>'label');
 perform private.v600_story_write(
  p_tenant_id=>t,p_entity_type=>cfg->>'entity',p_entity_id=>eid,
  p_entity_reference=>reference,p_action=>lower(tg_op)||'_saved_record',
  p_event_time=>statement_timestamp(),p_actor_user_id=>auth.uid(),
  p_location_id=>lid,p_before=>private.audit_clean_v704(b,true),
  p_after=>private.audit_clean_v704(a,true),
  p_reason=>coalesce(r->>'reason',r->>'void_reason',r->>'cancel_reason'),
  p_source_module=>cfg->>'group',p_source_function=>'audit_capture_v704',
  p_root_entity_type=>root_type,p_root_entity_id=>root_id,
  p_related_entities=>related,p_metadata=>jsonb_build_object('capture_version','v704','dataset',tg_table_name)
 );
 if tg_op='DELETE' then return old;end if;return new;
end;
$$;

create or replace function private.thq_sync_bump_v480(p_tenant_id uuid, p_domain text, p_entity_type text DEFAULT NULL::text, p_entity_id text DEFAULT NULL::text, p_action text DEFAULT 'change'::text)
returns void language plpgsql security definer set search_path to 'public', 'private', 'pg_temp'
as $$
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then return; end if;
  if p_tenant_id is null then return; end if;
  insert into public.thq_sync_state_v480(tenant_id) values(p_tenant_id)
  on conflict(tenant_id) do nothing;

  update public.thq_sync_state_v480 set
    configuration_version=configuration_version+case when p_domain='configuration' then 1 else 0 end,
    catalogue_version=catalogue_version+case when p_domain='catalogue' then 1 else 0 end,
    parties_version=parties_version+case when p_domain='parties' then 1 else 0 end,
    transactions_version=transactions_version+case when p_domain='transactions' then 1 else 0 end,
    inventory_version=inventory_version+case when p_domain='inventory' then 1 else 0 end,
    finance_version=finance_version+case when p_domain='finance' then 1 else 0 end,
    updated_at=now()
  where tenant_id=p_tenant_id;

  insert into public.thq_sync_events_v480(tenant_id,domain,entity_type,entity_id,action)
  values(p_tenant_id,p_domain,nullif(trim(coalesce(p_entity_type,'')),''),nullif(trim(coalesce(p_entity_id,'')),''),coalesce(nullif(trim(p_action),''),'change'));

  delete from public.thq_sync_events_v480 e
  where e.tenant_id=p_tenant_id and e.id < (
    select coalesce(max(x.id)-2000,0) from public.thq_sync_events_v480 x where x.tenant_id=p_tenant_id
  );
end;
$$;

create or replace function private.thq_sync_row_trigger_v480()
returns trigger language plpgsql security definer set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_tenant uuid;
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    if TG_OP='DELETE' then return old; end if;
    return new;
  end if;
  if TG_OP='DELETE' then
    v_tenant:=old.tenant_id;
    perform private.thq_sync_bump_v480(v_tenant,TG_ARGV[0],TG_TABLE_NAME,null,lower(TG_OP));
    return old;
  end if;
  v_tenant:=new.tenant_id;
  perform private.thq_sync_bump_v480(v_tenant,TG_ARGV[0],TG_TABLE_NAME,null,lower(TG_OP));
  return new;
end;
$$;

-- 2. Device verification RPC for client and POS systems
create or replace function public.verify_device_binding_v704(
  p_device_id uuid,
  p_tenant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_tenant_name text;
  v_business_code text;
  v_tenant_status text;
  v_device_status text;
  v_device_name text;
begin
  if p_tenant_id is null then
    return jsonb_build_object('valid', false, 'reason', 'missing_tenant');
  end if;

  select name, business_code, status into v_tenant_name, v_business_code, v_tenant_status
  from public.tenants
  where id = p_tenant_id;

  if v_tenant_name is null or v_tenant_status <> 'active' then
    return jsonb_build_object('valid', false, 'reason', 'business_deleted_or_inactive');
  end if;

  if p_device_id is not null then
    select status, name into v_device_status, v_device_name
    from public.business_devices
    where id = p_device_id and tenant_id = p_tenant_id;

    if v_device_status is null or v_device_status <> 'active' then
      return jsonb_build_object('valid', false, 'reason', 'device_revoked_or_deleted');
    end if;
  end if;

  return jsonb_build_object(
    'valid', true,
    'business_name', v_tenant_name,
    'business_code', v_business_code
  );
end;
$$;

revoke all on function public.verify_device_binding_v704(uuid, uuid) from public;
grant execute on function public.verify_device_binding_v704(uuid, uuid) to anon, authenticated, service_role;

-- 3. Production leaf-to-root platform_business_delete_v471 implementation
create or replace function public.platform_business_delete_v471(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_name text;
  v_division_id uuid;
begin
  if coalesce(auth.role(),'')<>'service_role' and current_user<>'postgres' then
    raise exception 'Service role required';
  end if;
  select name into v_name from public.tenants where id=p_tenant_id for update;
  if v_name is null then raise exception 'Business not found';end if;

  select division_id into v_division_id from public.business_division_members where tenant_id=p_tenant_id;

  -- Transaction-scoped bypass for immutability guards
  perform set_config('flexi.platform_business_delete', 'true', true);

  -- 1. Break circular / cross references on staff, load costs, and payments
  update public.staff_earnings_v630 set load_cost_id = null where tenant_id=p_tenant_id;
  update public.material_load_costs_v630 set staff_earning_id = null where tenant_id=p_tenant_id;
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

  -- 4. Customer and supplier receipt / payment allocations
  delete from public.customer_receipt_allocations where tenant_id=p_tenant_id;
  delete from public.customer_receipts where tenant_id=p_tenant_id;
  delete from public.supplier_payment_allocations_v484 where supplier_payment_id in (select id from public.supplier_payments_v484 where tenant_id=p_tenant_id);
  delete from public.supplier_payments_v484 where tenant_id=p_tenant_id;
  delete from public.supplier_ledger_entries_v484 where tenant_id=p_tenant_id;

  -- 5. Sales & purchases
  delete from public.sales_return_items where sales_return_id in (select id from public.sales_returns where tenant_id=p_tenant_id);
  delete from public.sales_returns where tenant_id=p_tenant_id;
  delete from public.purchase_return_items where purchase_return_id in (select id from public.purchase_returns where tenant_id=p_tenant_id);
  delete from public.purchase_returns where tenant_id=p_tenant_id;

  delete from public.sale_payments where tenant_id=p_tenant_id;
  delete from public.sale_payment_allocations_v522 where tenant_id=p_tenant_id;
  delete from public.sale_items where tenant_id=p_tenant_id;
  delete from public.sale_commercial_summary_v610 where tenant_id=p_tenant_id;
  delete from public.sales where tenant_id=p_tenant_id;

  delete from public.purchase_invoice_items_v484 where purchase_invoice_id in (select id from public.purchase_invoices_v484 where tenant_id=p_tenant_id);
  delete from public.purchase_invoices_v484 where tenant_id=p_tenant_id;
  delete from public.purchase_items where tenant_id=p_tenant_id;
  delete from public.purchase_payments where tenant_id=p_tenant_id;
  delete from public.purchases where tenant_id=p_tenant_id;
  delete from public.purchase_quotation_items_v500 where quotation_id in (select id from public.purchase_quotations_v500 where tenant_id=p_tenant_id);
  delete from public.purchase_quotations_v500 where tenant_id=p_tenant_id;
  delete from public.purchase_order_items_v480 where purchase_order_id in (select id from public.purchase_orders_v480 where tenant_id=p_tenant_id);
  delete from public.purchase_orders_v480 where tenant_id=p_tenant_id;
  delete from public.purchase_request_items_v484 where request_id in (select id from public.purchase_requests_v484 where tenant_id=p_tenant_id);
  delete from public.purchase_requests_v484 where tenant_id=p_tenant_id;
  delete from public.goods_receipt_items_v484 where goods_receipt_id in (select id from public.goods_receipts_v484 where tenant_id=p_tenant_id);
  delete from public.goods_receipts_v484 where tenant_id=p_tenant_id;

  -- 6. GST snapshots and evidence
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

  -- 7. Audit and story
  delete from public.transaction_story_events_v600 where tenant_id=p_tenant_id;
  delete from public.audit_findings_v600 where tenant_id=p_tenant_id;
  delete from public.transaction_corrections where tenant_id=p_tenant_id;
  delete from public.transaction_requests_v47 where tenant_id=p_tenant_id;

  -- 8. Workshop and vehicles
  delete from public.workshop_job_items where job_id in (select id from public.workshop_job_cards where tenant_id=p_tenant_id);
  delete from public.workshop_job_cards where tenant_id=p_tenant_id;
  delete from public.workshop_vehicles where tenant_id=p_tenant_id;
  delete from public.service_jobs where tenant_id=p_tenant_id;
  delete from public.service_vehicles where tenant_id=p_tenant_id;
  delete from public.product_warranties_v483 where tenant_id=p_tenant_id;

  -- 9. Logistics
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

  -- 10. Loans
  delete from public.loan_payment_allocations_v490 where tenant_id=p_tenant_id;
  delete from public.loan_payments_v490 where tenant_id=p_tenant_id;
  delete from public.loan_schedule_v490 where tenant_id=p_tenant_id;
  delete from public.loan_rate_history_v490 where tenant_id=p_tenant_id;
  delete from public.loan_guarantors_v490 where tenant_id=p_tenant_id;
  delete from public.loan_collateral_v490 where tenant_id=p_tenant_id;
  delete from public.loan_events_v490 where tenant_id=p_tenant_id;
  delete from public.loan_accounts_v490 where tenant_id=p_tenant_id;

  -- 11. Finance and accounts
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

  -- 12. Stock & inventory
  delete from public.stock_transfer_allocations_v485 where tenant_id=p_tenant_id;
  delete from public.stock_transfer_history_v485 where tenant_id=p_tenant_id;
  delete from public.stock_transfer_items where transfer_id in (select id from public.stock_transfers where tenant_id=p_tenant_id);
  delete from public.stock_transfers where tenant_id=p_tenant_id;
  delete from public.stock_adjustment_requests_v500 where tenant_id=p_tenant_id;
  delete from public.stock_count_items where count_id in (select id from public.stock_counts where tenant_id=p_tenant_id);
  delete from public.stock_counts where tenant_id=p_tenant_id;
  delete from public.stock_movements where tenant_id=p_tenant_id;
  delete from public.inventory_trace_events_v483 where tenant_id=p_tenant_id;
  delete from public.inventory_serials_v483 where tenant_id=p_tenant_id;
  delete from public.inventory_batches_v483 where tenant_id=p_tenant_id;
  delete from public.inventory_batch_balances_v483 where tenant_id=p_tenant_id;
  delete from public.location_stock_movements where tenant_id=p_tenant_id;
  delete from public.location_stock_balances where tenant_id=p_tenant_id;
  delete from public.stock_balances where tenant_id=p_tenant_id;
  delete from public.product_identifiers_v482 where tenant_id=p_tenant_id;
  delete from public.product_identifier_sequences_v482 where tenant_id=p_tenant_id;
  delete from public.product_tracking_policies_v483 where tenant_id=p_tenant_id;
  delete from private.tracking_conversions_v633 where tenant_id=p_tenant_id;

  -- 13. Production & restaurant
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

  -- 14. POS & Cashiers
  delete from public.cashier_shifts where tenant_id=p_tenant_id;
  delete from public.pos_offline_sync_v486 where tenant_id=p_tenant_id;
  delete from public.pos_held_sales where tenant_id=p_tenant_id;
  delete from public.pos_device_preferences where tenant_id=p_tenant_id;
  delete from public.mobile_pos_receipt_events_v488 where tenant_id=p_tenant_id;
  delete from public.mobile_pos_kot_requests_v488 where tenant_id=p_tenant_id;
  delete from public.mobile_pos_terminal_settings_v488 where tenant_id=p_tenant_id;

  -- 15. Systems & devices
  delete from public.system_installations where tenant_id=p_tenant_id or system_id in (select id from public.business_devices where tenant_id=p_tenant_id);
  delete from public.device_app_status where tenant_id=p_tenant_id;
  delete from public.business_devices where tenant_id=p_tenant_id;

  -- 16. Users & Memberships
  delete from public.user_login_names where tenant_id=p_tenant_id;
  delete from public.user_roles where tenant_id=p_tenant_id;
  delete from public.user_preferences_v4 where tenant_id=p_tenant_id;
  delete from public.user_saved_views where tenant_id=p_tenant_id;
  delete from public.business_user_location_access where tenant_id=p_tenant_id;
  delete from public.business_user_app_access where tenant_id=p_tenant_id;
  delete from public.business_division_members where tenant_id=p_tenant_id;
  delete from public.tenant_memberships where tenant_id=p_tenant_id;

  -- 17. Catalogue, CRM & locations
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

  -- 18. Settings
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

  -- 19. Finally delete the tenant row
  delete from public.tenants where id=p_tenant_id;

  -- Clean up division if empty
  if v_division_id is not null then
    delete from public.business_divisions
    where id=v_division_id
      and not exists(select 1 from public.business_division_members where division_id=v_division_id);
  end if;

  if found then 
    return jsonb_build_object('success',true,'tenant_id',p_tenant_id,'business_name',v_name);
  end if;
  raise exception 'Business delete did not complete';
end $$;

revoke all on function public.platform_business_delete_v471(uuid) from public, anon, authenticated;
grant execute on function public.platform_business_delete_v471(uuid) to service_role;
