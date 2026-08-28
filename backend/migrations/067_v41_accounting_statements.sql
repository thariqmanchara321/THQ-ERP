-- FLEXI ERP V4.1
-- Practical financial statements built from the posted double-entry journal.
begin;

create or replace function public.accounting_statement_v41(
  p_tenant_id uuid,
  p_statement text,
  p_from date,
  p_to date,
  p_location_id uuid default null
) returns jsonb
language plpgsql stable security definer
set search_path=public,private,pg_temp
as $$
declare
  v_key text:=lower(trim(coalesce(p_statement,'')));
  v_rows jsonb:='[]'::jsonb;
  v_summary jsonb:='{}'::jsonb;
  v_revenue numeric:=0; v_cogs numeric:=0; v_expenses numeric:=0; v_net numeric:=0;
  v_assets numeric:=0; v_liabilities numeric:=0; v_equity numeric:=0; v_current_earnings numeric:=0;
  v_dr numeric:=0; v_cr numeric:=0; v_in numeric:=0; v_out numeric:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'accounting.view')
     and not private.erp_has_permission(p_tenant_id,'accounting.manage') then
    raise exception 'Accounting permission required';
  end if;
  if p_to is null then raise exception 'End date is required';end if;
  if p_from is null then p_from:=date '2000-01-01';end if;
  if p_from>p_to then raise exception 'Invalid date range';end if;

  if v_key='trial_balance' then
    with balances as (
      select a.id,a.code::text code,a.name::text name,a.account_type::text account_type,
        coalesce(sum(jl.debit) filter(where j.id is not null),0)::numeric debit,
        coalesce(sum(jl.credit) filter(where j.id is not null),0)::numeric credit
      from public.accounting_accounts a
      left join public.journal_lines jl on jl.account_id=a.id
      left join public.journal_entries j on j.id=jl.journal_entry_id
        and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date<=p_to
        and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
      where a.tenant_id=p_tenant_id and a.active
      group by a.id,a.code,a.name,a.account_type
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'account_id',id,'code',code,'name',name,'account_type',account_type,
      'debit',debit,'credit',credit,
      'balance',case when account_type in('asset','expense','cogs') then debit-credit else credit-debit end
    ) order by code),'[]'::jsonb),coalesce(sum(debit),0),coalesce(sum(credit),0)
    into v_rows,v_dr,v_cr from balances where abs(debit)>0.0001 or abs(credit)>0.0001;
    v_summary:=jsonb_build_object('total_debit',v_dr,'total_credit',v_cr,'difference',v_dr-v_cr);

  elsif v_key='profit_loss' then
    with balances as (
      select a.id,a.code::text code,a.name::text name,a.account_type::text account_type,
        case when a.account_type='income' then coalesce(sum(jl.credit-jl.debit) filter(where j.id is not null),0)
             else coalesce(sum(jl.debit-jl.credit) filter(where j.id is not null),0) end::numeric amount
      from public.accounting_accounts a
      left join public.journal_lines jl on jl.account_id=a.id
      left join public.journal_entries j on j.id=jl.journal_entry_id
        and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date between p_from and p_to
        and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
      where a.tenant_id=p_tenant_id and a.active and a.account_type in('income','cogs','expense')
      group by a.id,a.code,a.name,a.account_type
    )
    select coalesce(jsonb_agg(jsonb_build_object('account_id',id,'code',code,'name',name,'account_type',account_type,'amount',amount) order by account_type,code),'[]'::jsonb),
      coalesce(sum(amount) filter(where account_type='income'),0),
      coalesce(sum(amount) filter(where account_type='cogs'),0),
      coalesce(sum(amount) filter(where account_type='expense'),0)
    into v_rows,v_revenue,v_cogs,v_expenses from balances where abs(amount)>0.0001;
    v_net:=v_revenue-v_cogs-v_expenses;
    v_summary:=jsonb_build_object('revenue',v_revenue,'cogs',v_cogs,'expenses',v_expenses,'net_profit',v_net,'from',p_from,'to',p_to);

  elsif v_key='balance_sheet' then
    with balances as (
      select a.id,a.code::text code,a.name::text name,a.account_type::text account_type,
        case when a.account_type='asset' then coalesce(sum(jl.debit-jl.credit) filter(where j.id is not null),0)
             else coalesce(sum(jl.credit-jl.debit) filter(where j.id is not null),0) end::numeric amount
      from public.accounting_accounts a
      left join public.journal_lines jl on jl.account_id=a.id
      left join public.journal_entries j on j.id=jl.journal_entry_id
        and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date<=p_to
        and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
      where a.tenant_id=p_tenant_id and a.active and a.account_type in('asset','liability','equity')
      group by a.id,a.code,a.name,a.account_type
    ), earnings as (
      select coalesce(sum(case when a.account_type='income' then jl.credit-jl.debit when a.account_type in('expense','cogs') then -(jl.debit-jl.credit) else 0 end),0)::numeric amount
      from public.journal_lines jl
      join public.accounting_accounts a on a.id=jl.account_id and a.tenant_id=p_tenant_id
      join public.journal_entries j on j.id=jl.journal_entry_id and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date<=p_to
      where a.account_type in('income','expense','cogs') and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
    )
    select coalesce(jsonb_agg(jsonb_build_object('account_id',id,'code',code,'name',name,'account_type',account_type,'amount',amount) order by account_type,code),'[]'::jsonb),
      coalesce(sum(amount) filter(where account_type='asset'),0),
      coalesce(sum(amount) filter(where account_type='liability'),0),
      coalesce(sum(amount) filter(where account_type='equity'),0)
    into v_rows,v_assets,v_liabilities,v_equity from balances where abs(amount)>0.0001;
    select amount into v_current_earnings from earnings;
    v_summary:=jsonb_build_object(
      'assets',v_assets,'liabilities',v_liabilities,'equity',v_equity,
      'current_earnings',v_current_earnings,
      'liabilities_and_equity',v_liabilities+v_equity+v_current_earnings,
      'difference',v_assets-(v_liabilities+v_equity+v_current_earnings),'as_of',p_to
    );

  elsif v_key='cash_flow' then
    with cash_accounts as (
      select distinct a.id,a.code::text code,a.name::text name,a.system_key::text system_key
      from public.accounting_accounts a
      left join public.accounting_account_mappings m on m.tenant_id=a.tenant_id and m.account_id=a.id
      where a.tenant_id=p_tenant_id and a.active
        and (a.system_key in('cash','bank','upi','card') or m.mapping_key in('payment.cash','payment.bank','payment.upi','payment.card'))
    ), moves as (
      select a.id,a.code,a.name,a.system_key,
        coalesce(sum(jl.debit) filter(where j.id is not null),0)::numeric inflow,
        coalesce(sum(jl.credit) filter(where j.id is not null),0)::numeric outflow
      from cash_accounts a
      left join public.journal_lines jl on jl.account_id=a.id
      left join public.journal_entries j on j.id=jl.journal_entry_id
        and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date between p_from and p_to
        and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
      group by a.id,a.code,a.name,a.system_key
    )
    select coalesce(jsonb_agg(jsonb_build_object('account_id',id,'code',code,'name',name,'system_key',system_key,'inflow',inflow,'outflow',outflow,'net_change',inflow-outflow) order by code),'[]'::jsonb),
      coalesce(sum(inflow),0),coalesce(sum(outflow),0)
    into v_rows,v_in,v_out from moves where abs(inflow)>0.0001 or abs(outflow)>0.0001;
    v_summary:=jsonb_build_object('inflow',v_in,'outflow',v_out,'net_change',v_in-v_out,'from',p_from,'to',p_to,'note','Cash/Bank/UPI/Card account movement');
  else
    raise exception 'Unknown accounting statement %',p_statement;
  end if;

  return jsonb_build_object('statement',v_key,'rows',v_rows,'summary',v_summary,'location_id',p_location_id);
end $$;

revoke all on function public.accounting_statement_v41(uuid,text,date,date,uuid) from public,anon;
grant execute on function public.accounting_statement_v41(uuid,text,date,date,uuid) to authenticated;

commit;
select 'Flexi ERP V4.1 accounting statements ready' as status;
