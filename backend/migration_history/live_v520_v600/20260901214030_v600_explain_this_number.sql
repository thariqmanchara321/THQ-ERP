create or replace function private.v600_period_metric_values(
  p_tenant_id uuid,p_from date,p_to date,p_location_id uuid default null
)
returns table(
  sales_revenue numeric,
  total_income numeric,
  cogs numeric,
  expenses numeric,
  gross_profit numeric,
  net_profit numeric
)
language sql
stable
security definer
set search_path=''
as $$
  select
    coalesce(sum(case when a.system_key='sales_revenue' then jl.credit-jl.debit else 0 end),0)::numeric as sales_revenue,
    coalesce(sum(case when a.account_type='income' then jl.credit-jl.debit else 0 end),0)::numeric as total_income,
    coalesce(sum(case when a.account_type='cogs' then jl.debit-jl.credit else 0 end),0)::numeric as cogs,
    coalesce(sum(case when a.account_type='expense' then jl.debit-jl.credit else 0 end),0)::numeric as expenses,
    (coalesce(sum(case when a.system_key='sales_revenue' then jl.credit-jl.debit else 0 end),0)
      -coalesce(sum(case when a.account_type='cogs' then jl.debit-jl.credit else 0 end),0))::numeric as gross_profit,
    (coalesce(sum(case when a.account_type='income' then jl.credit-jl.debit else 0 end),0)
      -coalesce(sum(case when a.account_type='cogs' then jl.debit-jl.credit else 0 end),0)
      -coalesce(sum(case when a.account_type='expense' then jl.debit-jl.credit else 0 end),0))::numeric as net_profit
  from public.journal_entries j
  join public.journal_lines jl on jl.journal_entry_id=j.id
  join public.accounting_accounts a on a.id=jl.account_id and a.tenant_id=j.tenant_id
  where j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date between p_from and p_to
    and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view');
$$;
revoke all on function private.v600_period_metric_values(uuid,date,date,uuid) from public,anon,authenticated;

create or replace function private.v600_balance_metric_values(
  p_tenant_id uuid,p_as_of date,p_location_id uuid default null
)
returns table(
  inventory_value numeric,
  receivables numeric,
  payables numeric,
  cash numeric,
  bank numeric,
  upi numeric,
  card numeric,
  gst_payable numeric
)
language sql
stable
security definer
set search_path=''
as $$
with balances as (
  select a.system_key,a.account_type,
    case when a.account_type in ('asset','expense','cogs')
      then coalesce(sum(jl.debit-jl.credit),0)
      else coalesce(sum(jl.credit-jl.debit),0)
    end::numeric amount
  from public.accounting_accounts a
  left join public.journal_lines jl on jl.account_id=a.id
  left join public.journal_entries j on j.id=jl.journal_entry_id
    and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date<=p_as_of
    and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
  where a.tenant_id=p_tenant_id and a.active
  group by a.id,a.system_key,a.account_type
)
select
  coalesce(sum(amount) filter(where system_key='inventory_asset'),0)::numeric,
  coalesce(sum(amount) filter(where system_key='accounts_receivable'),0)::numeric,
  coalesce(sum(amount) filter(where system_key='accounts_payable'),0)::numeric,
  coalesce(sum(amount) filter(where system_key='cash'),0)::numeric,
  coalesce(sum(amount) filter(where system_key='bank'),0)::numeric,
  coalesce(sum(amount) filter(where system_key='upi'),0)::numeric,
  coalesce(sum(amount) filter(where system_key='card'),0)::numeric,
  (
    coalesce(sum(amount) filter(where system_key in ('output_gst','output_cgst','output_sgst','output_utgst','output_igst','output_cess','rcm_gst_payable','rcm_cgst_payable','rcm_sgst_payable','rcm_utgst_payable','rcm_igst_payable','rcm_cess_payable')),0)
    -coalesce(sum(amount) filter(where system_key in ('input_gst','input_cgst','input_sgst','input_utgst','input_igst','input_cess','rcm_input_gst','rcm_input_cgst','rcm_input_sgst','rcm_input_utgst','rcm_input_igst','rcm_input_cess')),0)
  )::numeric
from balances;
$$;
revoke all on function private.v600_balance_metric_values(uuid,date,uuid) from public,anon,authenticated;

create or replace function public.explain_metric_contract_v600(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) or not private.has_permission(p_tenant_id,'explain.view') then
    raise exception 'Permission denied' using errcode='42501';
  end if;
  return jsonb_build_object(
    'version','6.0.0-build1',
    'metrics',jsonb_build_array(
      jsonb_build_object('key','sales','label','Sales','kind','period','equation','Posted Sales Revenue credits - debits'),
      jsonb_build_object('key','cogs','label','COGS','kind','period','equation','Posted COGS debits - credits'),
      jsonb_build_object('key','gross_profit','label','Gross Profit','kind','period','equation','Sales - COGS'),
      jsonb_build_object('key','net_profit','label','Net Profit','kind','period','equation','Income - COGS - Expenses'),
      jsonb_build_object('key','inventory_value','label','Inventory Value','kind','balance','equation','Inventory Asset debits - credits as of date'),
      jsonb_build_object('key','receivables','label','Receivables','kind','balance','equation','Accounts Receivable debits - credits as of date'),
      jsonb_build_object('key','payables','label','Payables','kind','balance','equation','Accounts Payable credits - debits as of date'),
      jsonb_build_object('key','cash','label','Cash','kind','balance','equation','Cash in Hand debits - credits as of date'),
      jsonb_build_object('key','bank','label','Bank','kind','balance','equation','Bank Account debits - credits as of date'),
      jsonb_build_object('key','gst_payable','label','Net GST Payable','kind','balance','equation','Output/RCM GST liabilities - eligible Input/RCM Input GST assets as of date')
    ),
    'rule','ERP calculates first and explains second. Returned equations/components are derived from posted journals; natural-language text must not alter numeric values.'
  );
end;
$$;
revoke all on function public.explain_metric_contract_v600(uuid) from public,anon;
grant execute on function public.explain_metric_contract_v600(uuid) to authenticated;

create or replace function public.explain_metric_v600(
  p_tenant_id uuid,
  p_metric text,
  p_from date,
  p_to date,
  p_location_id uuid default null,
  p_driver_limit integer default 10
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_metric text := lower(trim(coalesce(p_metric,'')));
  v_kind text;
  v_label text;
  v_basis text;
  v_equation text;
  v_value numeric := 0;
  v_previous numeric := 0;
  v_change numeric := 0;
  v_driver_sum numeric := 0;
  v_days integer;
  v_prev_from date;
  v_prev_to date;
  curp record;
  prevp record;
  curb record;
  prevb record;
  v_components jsonb := '[]'::jsonb;
  v_drivers jsonb := '[]'::jsonb;
  v_product_drivers jsonb := '[]'::jsonb;
  v_reconciles boolean := true;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) or not private.has_permission(p_tenant_id,'explain.view') then
    raise exception 'Permission denied' using errcode='42501';
  end if;
  if p_from is null or p_to is null or p_to<p_from then raise exception 'Valid from/to dates are required'; end if;
  if v_metric not in ('sales','cogs','gross_profit','net_profit','inventory_value','receivables','payables','cash','bank','gst_payable') then
    raise exception 'Unsupported explain metric %',p_metric;
  end if;

  v_days := (p_to-p_from)+1;
  v_prev_to := p_from-1;
  v_prev_from := v_prev_to-(v_days-1);

  if v_metric in ('sales','cogs','gross_profit','net_profit') then
    v_kind := 'period';
    select * into curp from private.v600_period_metric_values(p_tenant_id,p_from,p_to,p_location_id);
    select * into prevp from private.v600_period_metric_values(p_tenant_id,v_prev_from,v_prev_to,p_location_id);

    if v_metric='sales' then
      v_label:='Sales'; v_basis:='Posted Sales Revenue journal lines'; v_equation:='Sales Revenue credits - debits';
      v_value:=curp.sales_revenue; v_previous:=prevp.sales_revenue;
    elsif v_metric='cogs' then
      v_label:='COGS'; v_basis:='Posted COGS journal lines'; v_equation:='COGS debits - credits';
      v_value:=curp.cogs; v_previous:=prevp.cogs;
    elsif v_metric='gross_profit' then
      v_label:='Gross Profit'; v_basis:='Posted Sales Revenue and COGS journal lines'; v_equation:='Sales - COGS';
      v_value:=curp.gross_profit; v_previous:=prevp.gross_profit;
      v_components:=jsonb_build_array(
        jsonb_build_object('key','sales','label','Sales','value',round(curp.sales_revenue,4),'operator','+'),
        jsonb_build_object('key','cogs','label','COGS','value',round(curp.cogs,4),'operator','-')
      );
    else
      v_label:='Net Profit'; v_basis:='All posted Income, COGS and Expense journal lines'; v_equation:='Income - COGS - Expenses';
      v_value:=curp.net_profit; v_previous:=prevp.net_profit;
      v_components:=jsonb_build_array(
        jsonb_build_object('key','income','label','Income','value',round(curp.total_income,4),'operator','+'),
        jsonb_build_object('key','cogs','label','COGS','value',round(curp.cogs,4),'operator','-'),
        jsonb_build_object('key','expenses','label','Expenses','value',round(curp.expenses,4),'operator','-')
      );
    end if;

    if v_metric in ('sales','cogs') then
      select coalesce(jsonb_agg(to_jsonb(q) order by abs(q.impact) desc),'[]'::jsonb),coalesce(sum(q.impact),0)
        into v_drivers,v_driver_sum
      from (
        with cur as (
          select coalesce(j.source_type,'manual') source_type,
            sum(case when v_metric='sales' then jl.credit-jl.debit else jl.debit-jl.credit end)::numeric amount
          from public.journal_entries j
          join public.journal_lines jl on jl.journal_entry_id=j.id
          join public.accounting_accounts a on a.id=jl.account_id and a.tenant_id=j.tenant_id
          where j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date between p_from and p_to
            and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
            and ((v_metric='sales' and a.system_key='sales_revenue') or (v_metric='cogs' and a.account_type='cogs'))
          group by coalesce(j.source_type,'manual')
        ), prev as (
          select coalesce(j.source_type,'manual') source_type,
            sum(case when v_metric='sales' then jl.credit-jl.debit else jl.debit-jl.credit end)::numeric amount
          from public.journal_entries j
          join public.journal_lines jl on jl.journal_entry_id=j.id
          join public.accounting_accounts a on a.id=jl.account_id and a.tenant_id=j.tenant_id
          where j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date between v_prev_from and v_prev_to
            and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
            and ((v_metric='sales' and a.system_key='sales_revenue') or (v_metric='cogs' and a.account_type='cogs'))
          group by coalesce(j.source_type,'manual')
        ), keys as (select source_type from cur union select source_type from prev)
        select k.source_type,round(coalesce(c.amount,0),4) current_value,round(coalesce(p.amount,0),4) previous_value,
          round(coalesce(c.amount,0)-coalesce(p.amount,0),4) impact
        from keys k left join cur c using(source_type) left join prev p using(source_type)
        order by abs(coalesce(c.amount,0)-coalesce(p.amount,0)) desc
        limit greatest(1,least(coalesce(p_driver_limit,10),50))
      ) q;

    elsif v_metric in ('gross_profit','net_profit') then
      select coalesce(jsonb_agg(to_jsonb(q) order by abs(q.impact) desc),'[]'::jsonb),coalesce(sum(q.impact),0)
        into v_drivers,v_driver_sum
      from (
        with cur as (
          select coalesce(j.source_type,'manual') source_type,
            sum(case
              when v_metric='gross_profit' and a.system_key='sales_revenue' then jl.credit-jl.debit
              when v_metric='gross_profit' and a.account_type='cogs' then -(jl.debit-jl.credit)
              when v_metric='net_profit' and a.account_type='income' then jl.credit-jl.debit
              when v_metric='net_profit' and a.account_type in ('cogs','expense') then -(jl.debit-jl.credit)
              else 0 end)::numeric amount
          from public.journal_entries j
          join public.journal_lines jl on jl.journal_entry_id=j.id
          join public.accounting_accounts a on a.id=jl.account_id and a.tenant_id=j.tenant_id
          where j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date between p_from and p_to
            and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
            and ((v_metric='gross_profit' and (a.system_key='sales_revenue' or a.account_type='cogs'))
              or (v_metric='net_profit' and a.account_type in ('income','cogs','expense')))
          group by coalesce(j.source_type,'manual')
        ), prev as (
          select coalesce(j.source_type,'manual') source_type,
            sum(case
              when v_metric='gross_profit' and a.system_key='sales_revenue' then jl.credit-jl.debit
              when v_metric='gross_profit' and a.account_type='cogs' then -(jl.debit-jl.credit)
              when v_metric='net_profit' and a.account_type='income' then jl.credit-jl.debit
              when v_metric='net_profit' and a.account_type in ('cogs','expense') then -(jl.debit-jl.credit)
              else 0 end)::numeric amount
          from public.journal_entries j
          join public.journal_lines jl on jl.journal_entry_id=j.id
          join public.accounting_accounts a on a.id=jl.account_id and a.tenant_id=j.tenant_id
          where j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date between v_prev_from and v_prev_to
            and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
            and ((v_metric='gross_profit' and (a.system_key='sales_revenue' or a.account_type='cogs'))
              or (v_metric='net_profit' and a.account_type in ('income','cogs','expense')))
          group by coalesce(j.source_type,'manual')
        ), keys as (select source_type from cur union select source_type from prev)
        select k.source_type,round(coalesce(c.amount,0),4) current_contribution,round(coalesce(p.amount,0),4) previous_contribution,
          round(coalesce(c.amount,0)-coalesce(p.amount,0),4) impact
        from keys k left join cur c using(source_type) left join prev p using(source_type)
        order by abs(coalesce(c.amount,0)-coalesce(p.amount,0)) desc
        limit greatest(1,least(coalesce(p_driver_limit,10),50))
      ) q;

      if v_metric='gross_profit' then
        select coalesce(jsonb_agg(to_jsonb(q) order by abs(q.profit_change) desc),'[]'::jsonb)
        into v_product_drivers
        from (
          with cur as (
            select * from private.v600_product_profit_rows(p_tenant_id,p_from,p_to,p_location_id,null)
          ), prev as (
            select * from private.v600_product_profit_rows(p_tenant_id,v_prev_from,v_prev_to,p_location_id,null)
          ), keys as (select variant_id from cur union select variant_id from prev)
          select k.variant_id,
            coalesce(c.product_name,p.product_name) product_name,
            coalesce(c.variant_name,p.variant_name) variant_name,
            coalesce(c.sku,p.sku) sku,
            round(coalesce(c.gross_profit,0),4) current_profit,
            round(coalesce(p.gross_profit,0),4) previous_profit,
            round(coalesce(c.gross_profit,0)-coalesce(p.gross_profit,0),4) profit_change
          from keys k left join cur c using(variant_id) left join prev p using(variant_id)
          order by abs(coalesce(c.gross_profit,0)-coalesce(p.gross_profit,0)) desc
          limit greatest(1,least(coalesce(p_driver_limit,10),50))
        ) q;
      end if;
    end if;

    v_change:=v_value-v_previous;
    if v_metric='gross_profit' and v_components='[]'::jsonb then null; end if;
    if v_metric='sales' then
      v_components:=jsonb_build_array(jsonb_build_object('key','sales_revenue','label','Sales Revenue','value',round(v_value,4),'operator','+'));
    elsif v_metric='cogs' then
      v_components:=jsonb_build_array(jsonb_build_object('key','cogs','label','COGS','value',round(v_value,4),'operator','+'));
    end if;

  else
    v_kind := 'balance';
    select * into curb from private.v600_balance_metric_values(p_tenant_id,p_to,p_location_id);
    select * into prevb from private.v600_balance_metric_values(p_tenant_id,p_from-1,p_location_id);
    if v_metric='inventory_value' then v_label:='Inventory Value'; v_basis:='Posted Inventory Asset balance'; v_equation:='Inventory Asset debits - credits'; v_value:=curb.inventory_value; v_previous:=prevb.inventory_value;
    elsif v_metric='receivables' then v_label:='Receivables'; v_basis:='Posted Accounts Receivable balance'; v_equation:='AR debits - credits'; v_value:=curb.receivables; v_previous:=prevb.receivables;
    elsif v_metric='payables' then v_label:='Payables'; v_basis:='Posted Accounts Payable balance'; v_equation:='AP credits - debits'; v_value:=curb.payables; v_previous:=prevb.payables;
    elsif v_metric='cash' then v_label:='Cash'; v_basis:='Posted Cash in Hand balance'; v_equation:='Cash debits - credits'; v_value:=curb.cash; v_previous:=prevb.cash;
    elsif v_metric='bank' then v_label:='Bank'; v_basis:='Posted Bank Account balance'; v_equation:='Bank debits - credits'; v_value:=curb.bank; v_previous:=prevb.bank;
    else v_label:='Net GST Payable'; v_basis:='Posted GST component control-account balances'; v_equation:='Output + RCM GST liabilities - Input + RCM Input GST assets'; v_value:=curb.gst_payable; v_previous:=prevb.gst_payable;
    end if;
    v_change:=v_value-v_previous;

    select coalesce(jsonb_agg(to_jsonb(q) order by q.code),'[]'::jsonb) into v_components
    from (
      select a.id account_id,a.code,a.name,a.system_key,a.account_type,
        round(case when a.account_type in ('asset','expense','cogs') then coalesce(sum(jl.debit-jl.credit),0) else coalesce(sum(jl.credit-jl.debit),0) end,4) amount
      from public.accounting_accounts a
      left join public.journal_lines jl on jl.account_id=a.id
      left join public.journal_entries j on j.id=jl.journal_entry_id and j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date<=p_to
        and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
      where a.tenant_id=p_tenant_id and a.active and (
        (v_metric='inventory_value' and a.system_key='inventory_asset') or
        (v_metric='receivables' and a.system_key='accounts_receivable') or
        (v_metric='payables' and a.system_key='accounts_payable') or
        (v_metric='cash' and a.system_key='cash') or
        (v_metric='bank' and a.system_key='bank') or
        (v_metric='gst_payable' and a.system_key in ('output_gst','output_cgst','output_sgst','output_utgst','output_igst','output_cess','rcm_gst_payable','rcm_cgst_payable','rcm_sgst_payable','rcm_utgst_payable','rcm_igst_payable','rcm_cess_payable','input_gst','input_cgst','input_sgst','input_utgst','input_igst','input_cess','rcm_input_gst','rcm_input_cgst','rcm_input_sgst','rcm_input_utgst','rcm_input_igst','rcm_input_cess'))
      )
      group by a.id,a.code,a.name,a.system_key,a.account_type
    ) q;

    select coalesce(jsonb_agg(to_jsonb(q) order by abs(q.impact) desc),'[]'::jsonb),coalesce(sum(q.impact),0)
    into v_drivers,v_driver_sum
    from (
      with cur as (
        select coalesce(j.source_type,'manual') source_type,
          sum(case
            when v_metric='inventory_value' and a.system_key='inventory_asset' then jl.debit-jl.credit
            when v_metric='receivables' and a.system_key='accounts_receivable' then jl.debit-jl.credit
            when v_metric='payables' and a.system_key='accounts_payable' then jl.credit-jl.debit
            when v_metric='cash' and a.system_key='cash' then jl.debit-jl.credit
            when v_metric='bank' and a.system_key='bank' then jl.debit-jl.credit
            when v_metric='gst_payable' and a.system_key in ('output_gst','output_cgst','output_sgst','output_utgst','output_igst','output_cess','rcm_gst_payable','rcm_cgst_payable','rcm_sgst_payable','rcm_utgst_payable','rcm_igst_payable','rcm_cess_payable') then jl.credit-jl.debit
            when v_metric='gst_payable' and a.system_key in ('input_gst','input_cgst','input_sgst','input_utgst','input_igst','input_cess','rcm_input_gst','rcm_input_cgst','rcm_input_sgst','rcm_input_utgst','rcm_input_igst','rcm_input_cess') then -(jl.debit-jl.credit)
            else 0 end)::numeric impact
        from public.journal_entries j join public.journal_lines jl on jl.journal_entry_id=j.id
        join public.accounting_accounts a on a.id=jl.account_id and a.tenant_id=j.tenant_id
        where j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date between p_from and p_to
          and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
        group by coalesce(j.source_type,'manual')
      )
      select source_type,round(impact,4) impact from cur where abs(impact)>0.00005
      order by abs(impact) desc
      limit greatest(1,least(coalesce(p_driver_limit,10),50))
    ) q;
  end if;

  if abs(v_driver_sum-v_change)>0.01 then v_reconciles:=false; end if;

  return jsonb_build_object(
    'metric',v_metric,'label',v_label,'kind',v_kind,'value',round(v_value,4),'basis',v_basis,'equation',v_equation,
    'period',jsonb_build_object('from',p_from,'to',p_to,'location_id',p_location_id),
    'components',v_components,
    'previous',jsonb_build_object('from',case when v_kind='period' then v_prev_from else null end,'to',case when v_kind='period' then v_prev_to else p_from-1 end,'value',round(v_previous,4)),
    'change',round(v_change,4),
    'drivers',v_drivers,
    'product_profit_drivers',v_product_drivers,
    'driver_reconciliation',jsonb_build_object('sum',round(v_driver_sum,4),'expected_change',round(v_change,4),'reconciles',v_reconciles,'note',case when v_reconciles then 'Displayed driver impacts reconcile to the metric change within rounding.' else 'Driver list is limited; hidden smaller drivers account for the remaining change.' end),
    'integrity_rule','Numbers are calculated from posted journal entries first. Explanation text is descriptive only and cannot change the calculation.'
  );
end;
$$;
revoke all on function public.explain_metric_v600(uuid,text,date,date,uuid,integer) from public,anon;
grant execute on function public.explain_metric_v600(uuid,text,date,date,uuid,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values (259,'6.0.0-build1','Explain This Number Engine','Adds deterministic, ledger-backed explanations for Sales, COGS, Gross Profit, Net Profit, Inventory Value, Receivables, Payables, Cash, Bank and Net GST Payable. Period metrics compare equal-length prior periods; balance metrics compare opening vs ending balances. Source-type driver impacts are quantified and reconciliation status is explicit; product GP drivers are included for gross profit without allowing text to invent numbers.')
on conflict (migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;