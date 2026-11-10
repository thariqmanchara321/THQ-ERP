-- Migration: 361_v714_fix_business_and_store_deletion_integrity.sql
-- Description:
-- 1. Alters invoice_print_events.device_id foreign key constraint to ON DELETE SET NULL
--    so deletion of business_devices is never blocked by invoice print logs.
-- 2. Corrects platform_business_prepare_delete_v41 division member promotion logic to use
--    the actual business_division_members composite key (division_id, tenant_id) and created_at,
--    fixing the "column 'id' does not exist" error when deleting a main business.
-- 3. Hardens platform_business_delete_v471 to clean up invoice_print_events, printer_profiles,
--    device counters, and expense history before deleting business_devices and tenants.
-- 4. Hardens platform_location_delete_v471 so stores with operational/financial records are
--    safely archived, while unused stores cleanly purge location setup artifacts before deletion.

-- 1. Fix foreign key constraint on invoice_print_events.device_id
alter table public.invoice_print_events
  drop constraint if exists invoice_print_events_device_id_fkey,
  add constraint invoice_print_events_device_id_fkey
    foreign key (device_id) references public.business_devices(id) on delete set null;

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
  v_next_tenant_id uuid;
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
    select tenant_id into v_next_tenant_id
    from public.business_division_members
    where division_id = v_member.division_id and tenant_id <> p_tenant_id
    order by created_at asc, tenant_id asc
    limit 1;

    if v_next_tenant_id is not null then
      update public.business_division_members
      set member_type = 'main'
      where division_id = v_member.division_id and tenant_id = v_next_tenant_id;

      update public.business_divisions
      set main_tenant_id = v_next_tenant_id, updated_at = now()
      where id = v_member.division_id;
    end if;
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

-- 3. Production leaf-to-root platform_business_delete_v471 implementation
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

  -- 1. Break circular / cross references on staff, load costs, inventory, accounts, and devices
  update public.staff_earnings_v630 set load_cost_id = null where tenant_id=p_tenant_id;
  update public.material_load_costs_v630 set staff_earning_id = null where tenant_id=p_tenant_id;
  update public.inventory_batches_v483 set first_purchase_id = null where tenant_id=p_tenant_id;
  update public.accounting_accounts set parent_id = null where tenant_id=p_tenant_id;
  update public.business_locations set parent_location_id = null where tenant_id=p_tenant_id;
  update public.sale_payments set payment_allocation_id = null where tenant_id=p_tenant_id;
  update public.invoice_print_events set device_id = null where tenant_id=p_tenant_id;

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
  delete from public.expense_change_history_v600 where tenant_id=p_tenant_id;
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

  -- 16. POS, Cashiers & Print Logs
  delete from public.cashier_shifts where tenant_id=p_tenant_id;
  delete from public.pos_offline_sync_v486 where tenant_id=p_tenant_id;
  delete from public.pos_held_sales where tenant_id=p_tenant_id;
  delete from public.pos_device_preferences where tenant_id=p_tenant_id;
  delete from public.invoice_print_events where tenant_id=p_tenant_id;
  delete from public.printer_profiles where tenant_id=p_tenant_id;
  delete from public.device_document_counters where tenant_id=p_tenant_id;
  delete from public.device_document_numbers where tenant_id=p_tenant_id;

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

  -- Clean up division if empty, or ensure main_tenant_id points to active main member
  if v_division_id is not null then
    if not exists(select 1 from public.business_division_members where division_id=v_division_id) then
      delete from public.business_divisions where id=v_division_id;
    else
      update public.business_divisions
      set main_tenant_id = (
        select tenant_id from public.business_division_members
        where division_id=v_division_id and member_type='main'
        limit 1
      )
      where id=v_division_id and main_tenant_id=p_tenant_id;
    end if;
  end if;

  return jsonb_build_object('success',true,'tenant_id',p_tenant_id,'business_name',v_name);
end $$;

-- 4. Production platform_location_delete_v471 implementation
create or replace function public.platform_location_delete_v471(
  p_tenant_id uuid,
  p_location_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  l public.business_locations%rowtype;
  v_has_history boolean := false;
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then
    raise exception 'Platform admin required';
  end if;

  select * into l from public.business_locations where id=p_location_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Store/location not found'; end if;

  if coalesce(l.hierarchy_role,'')='main_store' or upper(coalesce(l.location_code,''))='MAIN' then
    raise exception 'MAIN STORE cannot be deleted. Rename/edit it instead.';
  end if;

  if exists(select 1 from public.business_devices where tenant_id=p_tenant_id and location_id=p_location_id and status not in ('revoked', 'inactive')) then
    raise exception 'Move or delete the systems assigned to this store before deleting it';
  end if;

  if exists(select 1 from public.business_locations where tenant_id=p_tenant_id and parent_location_id=p_location_id and active) then
    raise exception 'Move/archive child locations before deleting this store';
  end if;

  select exists(select 1 from public.document_origins where tenant_id=p_tenant_id and location_id=p_location_id)
      or exists(select 1 from public.journal_entries where tenant_id=p_tenant_id and location_id=p_location_id)
      or exists(select 1 from public.location_stock_balances where tenant_id=p_tenant_id and location_id=p_location_id and coalesce(quantity,0) <> 0)
      or exists(select 1 from public.location_stock_movements where tenant_id=p_tenant_id and location_id=p_location_id)
      or exists(select 1 from public.sales where tenant_id=p_tenant_id and location_id=p_location_id)
      or exists(select 1 from public.purchases where tenant_id=p_tenant_id and location_id=p_location_id)
      or exists(select 1 from public.cashier_shifts where tenant_id=p_tenant_id and location_id=p_location_id)
      or exists(select 1 from public.goods_receipts_v484 where tenant_id=p_tenant_id and location_id=p_location_id)
      or exists(select 1 from public.purchase_invoices_v484 where tenant_id=p_tenant_id and location_id=p_location_id)
      or exists(select 1 from public.expenses where tenant_id=p_tenant_id and location_id=p_location_id)
      or exists(select 1 from public.stock_transfers where tenant_id=p_tenant_id and (source_location_id=p_location_id or destination_location_id=p_location_id))
  into v_has_history;

  if v_has_history then
    update public.business_locations set active=false,updated_at=now() where id=p_location_id;
    perform private.business_audit_write_v471(p_tenant_id,'location.archive','business_location',p_location_id,l.location_code,null::jsonb,jsonb_build_object('reason',p_reason));
    return jsonb_build_object('success',true,'action','archived','location_id',p_location_id,'message','Store has business history and was safely archived.');
  end if;

  -- Clean up location-scoped metadata and unused setup records before permanent deletion
  update public.business_locations set parent_location_id = null where parent_location_id = p_location_id and tenant_id = p_tenant_id;
  delete from public.invoice_print_events where location_id = p_location_id and tenant_id = p_tenant_id;
  delete from public.printer_profiles where location_id = p_location_id and tenant_id = p_tenant_id;
  delete from public.location_stock_balances where location_id = p_location_id and tenant_id = p_tenant_id;
  delete from public.location_document_numbers where location_id = p_location_id and tenant_id = p_tenant_id;
  delete from public.location_document_counters where location_id = p_location_id and tenant_id = p_tenant_id;
  delete from public.location_product_settings where location_id = p_location_id and tenant_id = p_tenant_id;
  delete from public.gst_location_registrations_v520 where location_id = p_location_id and tenant_id = p_tenant_id;
  delete from public.business_user_location_access where location_id = p_location_id and tenant_id = p_tenant_id;
  delete from public.restaurant_tables where location_id = p_location_id and tenant_id = p_tenant_id;
  delete from public.pos_held_sales where location_id = p_location_id and tenant_id = p_tenant_id;
  delete from public.pos_offline_sync_v486 where location_id = p_location_id and tenant_id = p_tenant_id;
  delete from public.device_app_status where device_id in (select id from public.business_devices where location_id = p_location_id and tenant_id = p_tenant_id);
  delete from public.system_installations where system_id in (select id from public.business_devices where location_id = p_location_id and tenant_id = p_tenant_id);
  delete from public.business_devices where location_id = p_location_id and tenant_id = p_tenant_id;

  delete from public.business_locations where id=p_location_id and tenant_id=p_tenant_id;
  perform private.business_audit_write_v471(p_tenant_id,'location.delete','business_location',p_location_id,l.location_code,null::jsonb,jsonb_build_object('reason',p_reason));
  return jsonb_build_object('success',true,'action','deleted','location_id',p_location_id,'message','Unused store permanently deleted.');
end $$;

-- 5. Permissions
revoke all on function public.platform_business_delete_v471(uuid) from public, anon, authenticated;
grant execute on function public.platform_business_delete_v471(uuid) to service_role;

revoke all on function public.platform_business_prepare_delete_v41(uuid, text) from public, anon;
grant execute on function public.platform_business_prepare_delete_v41(uuid, text) to authenticated, service_role;

revoke all on function public.platform_location_delete_v471(uuid, uuid, text) from public, anon;
grant execute on function public.platform_location_delete_v471(uuid, uuid, text) to authenticated, service_role;
