-- THQ ERP v5.0.0 — platform completion helpers.
begin;
create or replace function public.thq_v500_capabilities()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$ select jsonb_build_object(
 'finance_controls',true,'journal_center',true,'bank_reconciliation',true,'recurring_expenses',true,'crm',true,'loyalty',true,
 'purchase_quotations',true,'supplier_performance',true,'reorder_suggestions',true,'reports_center',true,'returns_report',true,
 'task_notification_sync',true,'notification_center',true,'dashboard_bi',true,'finance_reconciliation',true,
 'searchable_selectors',true,'invoice_designer',true,'print_pdf_excel',true,'change_business_supported',true
) $$;
grant execute on function public.thq_v500_capabilities() to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(208,'5.0.0','Platform Completion','Capability contract for v5 milestone workspaces and cross-module controls.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v5.0.0 migration 208 applied' as status;
