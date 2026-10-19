-- THQ ERP — Selective Operational Reset for TENZO TRADERS - Main (tenzo-traders-main)
-- Tenant ID: 4854b09a-96e8-43a4-b0f7-8ad179384fad
-- Store ID: edb2454f-149c-421f-8cc1-930158d0e8ba
-- Backup archive: D:\ERP\flexi_erp\backup_tenzo_traders_main_20261013.json (272 records)

begin;

do $$
declare
  v_tenant_id uuid := '4854b09a-96e8-43a4-b0f7-8ad179384fad';
  v_location_id uuid := 'edb2454f-149c-421f-8cc1-930158d0e8ba';
begin
  -- Set transaction-level platform business delete bypass for authoritative guards
  perform set_config('flexi.platform_business_delete', 'true', true);

  -- 1. Material Yard loads & snapshots
  delete from public.material_load_sale_snapshots_v630 where tenant_id = v_tenant_id;
  delete from public.material_load_delivery_v630 where tenant_id = v_tenant_id;
  delete from public.material_load_requests_v630 where tenant_id = v_tenant_id;
  delete from public.material_load_costs_v630 where tenant_id = v_tenant_id;
  delete from public.material_load_cost_payments_v630 where tenant_id = v_tenant_id;
  delete from public.aggregate_load_events_v617 where load_id in (select id from public.aggregate_loads_v617 where tenant_id = v_tenant_id);
  delete from public.aggregate_freight_settlements_v620 where tenant_id = v_tenant_id;
  delete from public.transport_trip_hub_v611 where material_load_id in (select id from public.aggregate_loads_v617 where tenant_id = v_tenant_id);
  delete from public.aggregate_loads_v617 where tenant_id = v_tenant_id;

  -- 2. GST document snapshots
  delete from public.gst_document_line_snapshots_v520 where tenant_id = v_tenant_id;
  delete from public.gst_document_snapshots_v520 where tenant_id = v_tenant_id;

  -- 3. Sales & related payments, allocations, items
  delete from public.customer_receipt_allocations where tenant_id = v_tenant_id;
  delete from public.sale_commercial_summary_v610 where tenant_id = v_tenant_id;
  delete from public.sale_payments where sale_id in (select id from public.sales where tenant_id = v_tenant_id);
  delete from public.sale_payment_allocations_v522 where tenant_id = v_tenant_id;
  delete from public.sale_items where sale_id in (select id from public.sales where tenant_id = v_tenant_id);
  delete from public.sales_returns where tenant_id = v_tenant_id;
  delete from public.pos_held_sales where tenant_id = v_tenant_id;
  delete from public.sales where tenant_id = v_tenant_id;

  -- 4. Purchases & related payments, items
  delete from public.supplier_payment_allocations_v484 where supplier_payment_id in (select id from public.supplier_payments_v484 where tenant_id = v_tenant_id);
  delete from public.supplier_payments_v484 where tenant_id = v_tenant_id;
  delete from public.supplier_ledger_entries_v484 where tenant_id = v_tenant_id;
  delete from public.party_settlement_allocations_v626 where tenant_id = v_tenant_id;
  delete from public.party_settlements_v626 where tenant_id = v_tenant_id;
  delete from public.purchase_payments where purchase_id in (select id from public.purchases where tenant_id = v_tenant_id);
  delete from public.purchase_items where purchase_id in (select id from public.purchases where tenant_id = v_tenant_id);
  delete from public.purchase_returns where tenant_id = v_tenant_id;
  delete from public.purchase_orders_v480 where tenant_id = v_tenant_id;
  delete from public.purchase_requests_v484 where tenant_id = v_tenant_id;
  delete from public.purchases where tenant_id = v_tenant_id;

  -- 5. Expenses
  delete from public.expense_change_history_v600 where tenant_id = v_tenant_id;
  delete from public.expenses where tenant_id = v_tenant_id;

  -- 6. Journals & ledger lines
  delete from public.journal_lines where journal_entry_id in (select id from public.journal_entries where tenant_id = v_tenant_id);
  delete from public.journal_entries where tenant_id = v_tenant_id;

  -- 7. Stock movements & transfers
  delete from public.stock_transfer_allocations_v485 where tenant_id = v_tenant_id;
  delete from public.stock_transfers where tenant_id = v_tenant_id;
  delete from public.stock_counts where tenant_id = v_tenant_id;
  delete from public.stock_movements where tenant_id = v_tenant_id;
  delete from public.location_stock_movements where tenant_id = v_tenant_id;

  -- 8. Stock balances reconciliation (reset to 0)
  update public.stock_balances set quantity = 0, updated_at = now() where tenant_id = v_tenant_id;
  update public.location_stock_balances set quantity = 0, updated_at = now() where tenant_id = v_tenant_id;

  -- 9. Document counters & sequence numbers
  delete from public.location_document_numbers where tenant_id = v_tenant_id and location_id = v_location_id;
  update public.location_document_counters set last_number = 0 where location_id = v_location_id;

  -- 10. Transaction story events
  delete from public.transaction_story_events_v600 where tenant_id = v_tenant_id;

  raise notice 'Selective operational reset completed successfully.';
end $$;

commit;
