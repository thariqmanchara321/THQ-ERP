-- THQ ERP v4.9.0 — Loans & Credit release contract and deployment verification.
begin;

create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
   'product','THQ ERP',
   'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
   'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
   'minimum_app_version','4.9.0',
   'release','Loans & Credit',
   'api_version','v1'
 )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v490_release_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  v_missing text[]:='{}'::text[];
  v_proc text;
  v_required_procs text[]:=array[
    'purchases_list_v32','purchases_create_v489','purchase_request_list_v484','purchasing_dashboard_v484','purchase_invoice_create_v489',
    'loan_create_v490','loan_update_v490','loan_submit_v490','loan_decide_v490','loan_disburse_v490',
    'loan_payment_create_v490','loan_payment_reverse_v490','loan_rate_change_v490','loan_status_v490',
    'loan_collateral_save_v490','loan_guarantor_save_v490','loan_list_v490','loan_detail_v490',
    'loan_dashboard_v490','loan_warnings_v490','customer_loan_summary_v490','notifications_list_v4','business_attention_summary_v480','thq_api_contract_v480'
  ];
begin
  if to_regclass('public.loan_accounts_v490') is null then v_missing:=array_append(v_missing,'loan_accounts_v490');end if;
  if to_regclass('public.loan_schedule_v490') is null then v_missing:=array_append(v_missing,'loan_schedule_v490');end if;
  if to_regclass('public.loan_payments_v490') is null then v_missing:=array_append(v_missing,'loan_payments_v490');end if;
  if to_regclass('public.loan_payment_allocations_v490') is null then v_missing:=array_append(v_missing,'loan_payment_allocations_v490');end if;
  if to_regclass('public.loan_rate_history_v490') is null then v_missing:=array_append(v_missing,'loan_rate_history_v490');end if;
  if to_regclass('public.loan_collateral_v490') is null then v_missing:=array_append(v_missing,'loan_collateral_v490');end if;
  if to_regclass('public.loan_guarantors_v490') is null then v_missing:=array_append(v_missing,'loan_guarantors_v490');end if;
  if to_regclass('public.loan_events_v490') is null then v_missing:=array_append(v_missing,'loan_events_v490');end if;

  foreach v_proc in array v_required_procs loop
    if not exists(
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_proc
    ) then v_missing:=array_append(v_missing,v_proc);end if;
  end loop;

  if not exists(select 1 from public.modules where key='loans' and is_active) then v_missing:=array_append(v_missing,'module.loans');end if;
  if not exists(select 1 from public.permissions where key='loans.view') then v_missing:=array_append(v_missing,'permission.loans.view');end if;
  if not exists(select 1 from public.permissions where key='loans.collect') then v_missing:=array_append(v_missing,'permission.loans.collect');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_receivable') then v_missing:=array_append(v_missing,'mapping.loan_receivable');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_interest_income') then v_missing:=array_append(v_missing,'mapping.loan_interest_income');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_penalty_income') then v_missing:=array_append(v_missing,'mapping.loan_penalty_income');end if;
  if not exists(select 1 from public.app_menu_nodes_v45 where app_key='client' and module_key='loans') then v_missing:=array_append(v_missing,'navigation.client.loans');end if;
  if not exists(select 1 from public.app_menu_nodes_v45 where app_key='pos' and module_key='loans') then v_missing:=array_append(v_missing,'navigation.pos.loans');end if;

  return jsonb_build_object(
    'ready',cardinality(v_missing)=0,
    'missing',to_jsonb(v_missing),
    'schema_version','4.9.0',
    'migration_no',185,
    'api_version','v1',
    'purchasing_v2_resilience',true,
    'loans_client',true,
    'loans_pos',true,
    'fixed_variable_interest',true,
    'repayment_schedule',true,
    'maturity_warnings',true,
    'notification_attention_integration',true,
    'overdue_penalties',true,
    'loan_accounting',true,
    'cash_drawer_collection',true,
    'collateral_guarantors',true,
    'customer_linkage',true
  );
end $$;
grant execute on function public.thq_v490_release_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(185,'4.9.0','Loans & Credit','Client/POS loan management release with fixed/variable rates, schedules, warnings, collections, accounting integration, collateral/guarantors and Purchasing V2 resilience.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 migration 185 release contract applied' as status;
