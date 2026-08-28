-- FLEXI ERP V4 complete tenant backup manifest.
-- Excludes authentication passwords, refresh tokens, activation hashes and device secrets by design.
begin;

create or replace function public.business_backup_export_v4(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_run uuid:=gen_random_uuid();v jsonb;
begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'backup.export') then
    raise exception 'Backup/export permission required';
  end if;

  insert into public.business_export_runs(id,tenant_id,requested_by,status)
  values(v_run,p_tenant_id,auth.uid(),'running');

  v:=jsonb_build_object(
    'format','flexi-erp-v4-complete',
    'exported_at',now(),
    'security_note','Auth passwords/tokens, activation hashes and device secrets are intentionally excluded.',
    'tenant',(select to_jsonb(t) from public.tenants t where t.id=p_tenant_id),
    'tenant_settings',coalesce((select to_jsonb(x) from public.tenant_settings x where x.tenant_id=p_tenant_id),'{}'::jsonb),
    'tenant_settings_v2',coalesce((select to_jsonb(x) from public.tenant_settings_v2 x where x.tenant_id=p_tenant_id),'{}'::jsonb),
    'subscription',coalesce((select to_jsonb(x) from public.tenant_subscriptions x where x.tenant_id=p_tenant_id order by x.created_at desc limit 1),'{}'::jsonb),
    'tenant_modules',coalesce((select jsonb_agg(to_jsonb(x)) from public.tenant_modules x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'locations',coalesce((select jsonb_agg(to_jsonb(x)) from public.business_locations x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'devices',coalesce((select jsonb_agg(to_jsonb(x)-'activation_hash'-'device_secret_hash') from public.business_devices x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'location_user_access',coalesce((select jsonb_agg(to_jsonb(x)) from public.business_user_location_access x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'document_origins',coalesce((select jsonb_agg(to_jsonb(x)) from public.document_origins x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'location_document_numbers',coalesce((select jsonb_agg(to_jsonb(x)) from public.location_document_numbers x where x.tenant_id=p_tenant_id),'[]'::jsonb),

    'products',coalesce((select jsonb_agg(to_jsonb(x)) from public.products x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'variants',coalesce((select jsonb_agg(to_jsonb(x)) from public.product_variants x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'stock_balances',coalesce((select jsonb_agg(to_jsonb(x)) from public.stock_balances x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'stock_movements',coalesce((select jsonb_agg(to_jsonb(x)) from public.stock_movements x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'location_products',coalesce((select jsonb_agg(to_jsonb(x)) from public.location_product_settings x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'location_stock',coalesce((select jsonb_agg(to_jsonb(x)) from public.location_stock_balances x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'location_stock_movements',coalesce((select jsonb_agg(to_jsonb(x)) from public.location_stock_movements x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'stock_transfers',coalesce((select jsonb_agg(to_jsonb(x)) from public.stock_transfers x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'stock_transfer_items',coalesce((select jsonb_agg(to_jsonb(i)) from public.stock_transfer_items i join public.stock_transfers t on t.id=i.transfer_id where t.tenant_id=p_tenant_id),'[]'::jsonb),
    'stock_counts',coalesce((select jsonb_agg(to_jsonb(x)) from public.stock_counts x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'stock_count_items',coalesce((select jsonb_agg(to_jsonb(i)) from public.stock_count_items i join public.stock_counts c on c.id=i.count_id where c.tenant_id=p_tenant_id),'[]'::jsonb),

    'customers',coalesce((select jsonb_agg(to_jsonb(x)) from public.customers x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'suppliers',coalesce((select jsonb_agg(to_jsonb(x)) from public.suppliers x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'sales',coalesce((select jsonb_agg(to_jsonb(x)) from public.sales x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'sale_items',coalesce((select jsonb_agg(to_jsonb(i)) from public.sale_items i join public.sales s on s.id=i.sale_id where s.tenant_id=p_tenant_id),'[]'::jsonb),
    'sale_payments',coalesce((select jsonb_agg(to_jsonb(i)) from public.sale_payments i join public.sales s on s.id=i.sale_id where s.tenant_id=p_tenant_id),'[]'::jsonb),
    'sales_returns',coalesce((select jsonb_agg(to_jsonb(x)) from public.sales_returns x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'sales_return_items',coalesce((select jsonb_agg(to_jsonb(i)) from public.sales_return_items i join public.sales_returns r on r.id=i.sales_return_id where r.tenant_id=p_tenant_id),'[]'::jsonb),
    'purchases',coalesce((select jsonb_agg(to_jsonb(x)) from public.purchases x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'purchase_items',coalesce((select jsonb_agg(to_jsonb(i)) from public.purchase_items i join public.purchases p on p.id=i.purchase_id where p.tenant_id=p_tenant_id),'[]'::jsonb),
    'purchase_payments',coalesce((select jsonb_agg(to_jsonb(i)) from public.purchase_payments i join public.purchases p on p.id=i.purchase_id where p.tenant_id=p_tenant_id),'[]'::jsonb),
    'purchase_returns',coalesce((select jsonb_agg(to_jsonb(x)) from public.purchase_returns x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'purchase_return_items',coalesce((select jsonb_agg(to_jsonb(i)) from public.purchase_return_items i join public.purchase_returns r on r.id=i.purchase_return_id where r.tenant_id=p_tenant_id),'[]'::jsonb),
    'transaction_corrections',coalesce((select jsonb_agg(to_jsonb(x)) from public.transaction_corrections x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'expenses',coalesce((select jsonb_agg(to_jsonb(x)) from public.expenses x where x.tenant_id=p_tenant_id),'[]'::jsonb),

    'cashier_shifts',coalesce((select jsonb_agg(to_jsonb(x)) from public.cashier_shifts x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'cash_drawer_movements',coalesce((select jsonb_agg(to_jsonb(x)) from public.cash_drawer_movements x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'accounts',coalesce((select jsonb_agg(to_jsonb(x)) from public.accounting_accounts x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'account_mappings',coalesce((select jsonb_agg(to_jsonb(x)) from public.accounting_account_mappings x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'journals',coalesce((select jsonb_agg(to_jsonb(x)) from public.journal_entries x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'journal_lines',coalesce((select jsonb_agg(to_jsonb(l)) from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id where j.tenant_id=p_tenant_id),'[]'::jsonb),

    'tenant_invoice_templates',coalesce((select jsonb_agg(to_jsonb(x)) from public.tenant_invoice_templates x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'printer_profiles',coalesce((select jsonb_agg(to_jsonb(x)) from public.printer_profiles x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'invoice_print_events',coalesce((select jsonb_agg(to_jsonb(x)) from public.invoice_print_events x where x.tenant_id=p_tenant_id),'[]'::jsonb),

    'notifications',coalesce((select jsonb_agg(to_jsonb(x)) from public.notifications x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'tasks',coalesce((select jsonb_agg(to_jsonb(x)) from public.business_tasks x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'attachments',coalesce((select jsonb_agg(to_jsonb(x)) from public.entity_attachments x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'approval_rules',coalesce((select jsonb_agg(to_jsonb(x)) from public.approval_rules x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'approval_requests',coalesce((select jsonb_agg(to_jsonb(x)) from public.approval_requests x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'custom_fields',coalesce((select jsonb_agg(to_jsonb(x)) from public.custom_field_definitions x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'custom_field_values',coalesce((select jsonb_agg(to_jsonb(x)) from public.custom_field_values x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'audit',coalesce((select jsonb_agg(to_jsonb(x)) from public.business_audit_log x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'support_tickets',coalesce((select jsonb_agg(to_jsonb(x)) from public.support_tickets x where x.tenant_id=p_tenant_id),'[]'::jsonb),

    'production_recipes',coalesce((select jsonb_agg(to_jsonb(x)) from public.production_recipes x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'production_runs',coalesce((select jsonb_agg(to_jsonb(x)) from public.production_runs x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'production_boms',coalesce((select jsonb_agg(to_jsonb(x)) from public.production_boms x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'production_material_reservations',coalesce((select jsonb_agg(to_jsonb(x)) from public.production_material_reservations x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'service_vehicles',coalesce((select jsonb_agg(to_jsonb(x)) from public.service_vehicles x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'service_jobs',coalesce((select jsonb_agg(to_jsonb(x)) from public.service_jobs x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'restaurant_tables',coalesce((select jsonb_agg(to_jsonb(x)) from public.restaurant_tables x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'restaurant_orders',coalesce((select jsonb_agg(to_jsonb(x)) from public.restaurant_orders x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'restaurant_kots',coalesce((select jsonb_agg(to_jsonb(x)) from public.restaurant_kots x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'workshop_vehicles',coalesce((select jsonb_agg(to_jsonb(x)) from public.workshop_vehicles x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'workshop_job_cards',coalesce((select jsonb_agg(to_jsonb(x)) from public.workshop_job_cards x where x.tenant_id=p_tenant_id),'[]'::jsonb)
  );

  update public.business_export_runs
  set status='completed',completed_at=now(),record_counts=jsonb_build_object(
    'products',jsonb_array_length(v->'products'),
    'customers',jsonb_array_length(v->'customers'),
    'suppliers',jsonb_array_length(v->'suppliers'),
    'sales',jsonb_array_length(v->'sales'),
    'purchases',jsonb_array_length(v->'purchases'),
    'expenses',jsonb_array_length(v->'expenses'),
    'journals',jsonb_array_length(v->'journals'),
    'stock_movements',jsonb_array_length(v->'location_stock_movements')
  ) where id=v_run;

  return jsonb_build_object('run_id',v_run,'backup',v);
exception when others then
  update public.business_export_runs set status='failed',notes=sqlerrm where id=v_run;
  raise;
end $$;
grant execute on function public.business_backup_export_v4(uuid) to authenticated;

commit;
select 'Flexi ERP V4 complete business backup/export ready' as status;
