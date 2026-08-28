-- THQ ERP V4.7.2 — post-upgrade verification after migration 118.
select public.thq_backend_contract_v47() as backend_contract;

select migration_no, schema_version, release_name, applied_at
from public.thq_schema_releases
where migration_no = 118;

select
  to_regprocedure('public.cashier_shift_open_v472(uuid,uuid,uuid,numeric,timestamp with time zone,text,text)') is not null as cashier_shift_open_v472,
  to_regprocedure('public.cashier_shift_close_v472(uuid,uuid,numeric,timestamp with time zone,text,text)') is not null as cashier_shift_close_v472,
  to_regprocedure('public.cashier_shift_edit_v472(uuid,uuid,timestamp with time zone,timestamp with time zone,numeric,numeric,text)') is not null as cashier_shift_edit_v472,
  to_regprocedure('public.cashier_shift_current_v472(uuid,uuid)') is not null as cashier_shift_current_v472,
  to_regprocedure('public.cashier_shift_history_v472(uuid,uuid,date,date,integer)') is not null as cashier_shift_history_v472,
  to_regprocedure('public.cashier_shift_edits_v472(uuid,uuid)') is not null as cashier_shift_edits_v472,
  to_regprocedure('public.pos_terminal_day_v472(uuid,uuid,date)') is not null as pos_terminal_day_v472;

select
  to_regclass('public.cashier_shift_edits') is not null as cashier_shift_edits_table,
  exists(select 1 from public.modules where key='cashier_shifts' and is_active) as cashier_shift_module_active,
  exists(select 1 from public.modules where key='terminal_day' and is_active) as terminal_daily_module_active;
