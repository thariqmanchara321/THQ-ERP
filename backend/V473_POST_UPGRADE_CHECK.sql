-- THQ ERP v4.7.3 — post-upgrade verification after migration 119.
select public.thq_backend_contract_v47() as backend_contract;

select migration_no,schema_version,release_name,applied_at
from public.thq_schema_releases
where migration_no=119;

select
  to_regprocedure('public.pos_terminal_day_v473(uuid,uuid,date)') is not null as terminal_day_v473,
  to_regprocedure('public.pos_terminal_invoices_v473(uuid,uuid,date,text,integer)') is not null as terminal_invoice_search_v473,
  to_regprocedure('public.pos_sales_today_v473(uuid,uuid,date)') is not null as pos_sales_today_v473,
  to_regprocedure('public.pos_purchases_today_v473(uuid,uuid,date)') is not null as pos_purchases_today_v473,
  to_regprocedure('public.pos_expenses_today_v473(uuid,uuid,date)') is not null as pos_expenses_today_v473,
  to_regprocedure('public.pos_return_documents_today_v473(uuid,uuid,date,text,text,integer)') is not null as pos_returns_today_v473;
