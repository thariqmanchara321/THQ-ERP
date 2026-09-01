-- THQ ERP v4.9.1 release contract.
begin;

-- v4.9.1 is additive/backward-compatible with the v4.9.0 desktop Client/POS.
-- New v4.9.1 applications require migration 197 through their local release contract,
-- while already-installed v4.9.0 clients are not needlessly blocked by the backend.
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
  select jsonb_build_object(
    'product','THQ ERP',
    'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
    'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
    'minimum_app_version','4.9.0',
    'release','Financial Integrity & Bidirectional Loans',
    'api_version','v1',
    'backward_compatible',true
  )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v491_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  miss text[]:='{}';
  p text;
  req text[]:=array[
    'sales_return_create_v483',
    'loan_create_v491','loan_update_v491','loan_activate_v491','loan_payment_create_v491','loan_payment_reverse_v491',
    'loan_list_v491','loan_detail_v491','loan_dashboard_v491','loan_warnings_v491',
    'loan_settings_v491_get','loan_settings_v491_set',
    'payments_party_summary_v491','payments_party_detail_v491',
    'finance_reconciliation_v491'
  ];
begin
  foreach p in array req loop
    if not exists(
      select 1 from pg_proc x join pg_namespace n on n.oid=x.pronamespace
      where n.nspname='public' and x.proname=p
    ) then
      miss:=array_append(miss,p);
    end if;
  end loop;

  if not exists(select 1 from public.accounting_account_mappings where mapping_key='customer_credits') then miss:=array_append(miss,'mapping.customer_credits');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='supplier_credits') then miss:=array_append(miss,'mapping.supplier_credits');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_receivable') then miss:=array_append(miss,'mapping.loan_receivable');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_payable') then miss:=array_append(miss,'mapping.loan_payable');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_interest_income') then miss:=array_append(miss,'mapping.loan_interest_income');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_interest_expense') then miss:=array_append(miss,'mapping.loan_interest_expense');end if;

  return jsonb_build_object(
    'ready',cardinality(miss)=0,
    'missing',to_jsonb(miss),
    'schema_version','4.9.1',
    'migration_no',197,
    'minimum_compatible_app','4.9.0',
    'sales_return_accounting_repaired',true,
    'bidirectional_loans',true,
    'loan_accounting_switch',true,
    'party_payment_center',true,
    'finance_reconciliation',true,
    'client_compact_ui',true
  );
end $$;
grant execute on function public.thq_v491_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(197,'4.9.1','Financial Integrity & Bidirectional Loans','Sales-return accounting repair, loans given/taken, module accounting switch, finance reconciliation, party payment integration and compact Client workspace UI.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.9.1 migration 197 release applied' as status;
