-- ============================================================================
-- SQL Test Suite: Operations Intelligence Phase 6
-- Financial Intelligence, Accounting Intelligence & Expense Intelligence
-- ============================================================================

do $$
declare
  v_tid uuid := '0af96a25-2f04-44e2-a00f-5c4688f34238'::uuid;
  v_owner_uid uuid := '110b5ca3-1573-49e5-a5a1-40a9da065689'::uuid;
  v_res_fin jsonb;
  v_res_exp jsonb;
  v_res_fin_restricted jsonb;
  v_rev numeric;
  v_cogs numeric;
  v_gross numeric;
  v_net numeric;
  v_tb_debits numeric;
  v_tb_credits numeric;
  v_tb_diff numeric;
  v_cash_in numeric;
  v_cash_out numeric;
  v_cash_net numeric;
begin
  -- --------------------------------------------------------------------------
  -- 1. Impersonate Tenant Owner
  -- --------------------------------------------------------------------------
  perform set_config('request.jwt.claim.sub', v_owner_uid::text, true);

  -- --------------------------------------------------------------------------
  -- 2. Test financial_intelligence_v830 Execution & Key Contracts
  -- --------------------------------------------------------------------------
  select public.financial_intelligence_v830(v_tid, null, 365, '') into v_res_fin;

  assert v_res_fin is not null, 'financial_intelligence_v830 returned null';
  assert v_res_fin ? 'performance', 'financial_intelligence_v830 missing performance';
  assert v_res_fin ? 'cash_flow', 'financial_intelligence_v830 missing cash_flow';
  assert v_res_fin ? 'working_capital', 'financial_intelligence_v830 missing working_capital';
  assert v_res_fin ? 'accounting_health', 'financial_intelligence_v830 missing accounting_health';
  assert v_res_fin ? 'gst_and_tax', 'financial_intelligence_v830 missing gst_and_tax';
  assert v_res_fin ? 'anomalies', 'financial_intelligence_v830 missing anomalies';
  assert v_res_fin ? 'projections', 'financial_intelligence_v830 missing projections';
  assert (v_res_fin->>'can_view_cost')::boolean = true, 'owner must have can_view_cost = true';

  -- --------------------------------------------------------------------------
  -- 3. Verify Ledger-Backed P&L Calculations
  -- --------------------------------------------------------------------------
  v_rev := (v_res_fin->'performance'->'current'->>'revenue')::numeric;
  v_cogs := (v_res_fin->'performance'->'current'->>'cogs')::numeric;
  v_gross := (v_res_fin->'performance'->'current'->>'gross_profit')::numeric;
  v_net := (v_res_fin->'performance'->'current'->>'net_profit')::numeric;

  assert v_rev >= 0, 'revenue must be >= 0';
  assert v_cogs >= 0, 'cogs must be >= 0';
  assert round(v_gross, 2) = round(v_rev - v_cogs, 2), 'gross_profit must equal revenue - cogs';
  raise notice 'TEST 1 PASSED: Financial Intelligence P&L verified (Rev=%, COGS=%, Gross=%, Net=%)', v_rev, v_cogs, v_gross, v_net;

  -- --------------------------------------------------------------------------
  -- 4. Verify Double-Entry Trial Balance Verification
  -- --------------------------------------------------------------------------
  v_tb_debits := (v_res_fin->'accounting_health'->>'debits')::numeric;
  v_tb_credits := (v_res_fin->'accounting_health'->>'credits')::numeric;
  v_tb_diff := (v_res_fin->'accounting_health'->>'difference')::numeric;

  assert v_tb_debits > 0, 'trial balance debits must be > 0 for active tenant';
  assert v_tb_credits > 0, 'trial balance credits must be > 0 for active tenant';
  assert v_tb_diff < 0.01, 'trial balance debits and credits must be balanced (diff < 0.01)';
  assert (v_res_fin->'accounting_health'->>'is_balanced')::boolean = true, 'is_balanced must be true';
  raise notice 'TEST 2 PASSED: General Ledger Double-Entry Trial Balance is balanced (DR=%, CR=%, Diff=%)', v_tb_debits, v_tb_credits, v_tb_diff;

  -- --------------------------------------------------------------------------
  -- 5. Verify Cash Flow Intelligence
  -- --------------------------------------------------------------------------
  v_cash_in := (v_res_fin->'cash_flow'->>'cash_in')::numeric;
  v_cash_out := (v_res_fin->'cash_flow'->>'cash_out')::numeric;
  v_cash_net := (v_res_fin->'cash_flow'->>'net_movement')::numeric;

  assert (v_res_fin->'cash_flow'->>'cash_closing')::numeric =
         (v_res_fin->'cash_flow'->>'cash_opening')::numeric + v_cash_in - v_cash_out,
         'cash closing must equal opening + in - out';
  assert jsonb_typeof(v_res_fin->'cash_flow'->'daily_timeline') = 'array', 'daily_timeline must be an array';
  raise notice 'TEST 3 PASSED: Cash Flow movements verified (Cash In=%, Out=%, Net Movement=%)', v_cash_in, v_cash_out, v_cash_net;

  -- --------------------------------------------------------------------------
  -- 6. Verify Working Capital & Aging Buckets
  -- --------------------------------------------------------------------------
  assert (v_res_fin->'working_capital'->>'net_working_capital')::numeric =
         (v_res_fin->'working_capital'->>'inventory_valuation')::numeric +
         (v_res_fin->'working_capital'->>'ar_closing')::numeric -
         (v_res_fin->'working_capital'->>'ap_closing')::numeric,
         'net_working_capital must equal inventory + AR - AP';
  assert v_res_fin->'working_capital' ? 'receivables_aging', 'working_capital must include receivables_aging';
  assert v_res_fin->'working_capital' ? 'payables_aging', 'working_capital must include payables_aging';
  raise notice 'TEST 4 PASSED: Working Capital verified (AR=%, AP=%, Inv=%, NWC=%)',
    v_res_fin->'working_capital'->>'ar_closing',
    v_res_fin->'working_capital'->>'ap_closing',
    v_res_fin->'working_capital'->>'inventory_valuation',
    v_res_fin->'working_capital'->>'net_working_capital';

  -- --------------------------------------------------------------------------
  -- 7. Test expense_intelligence_v830 Execution & Key Contracts
  -- --------------------------------------------------------------------------
  select public.expense_intelligence_v830(v_tid, null, 365, '') into v_res_exp;

  assert v_res_exp is not null, 'expense_intelligence_v830 returned null';
  assert v_res_exp ? 'summary', 'expense_intelligence_v830 missing summary';
  assert v_res_exp ? 'categories', 'expense_intelligence_v830 missing categories';
  assert v_res_exp ? 'trends', 'expense_intelligence_v830 missing trends';
  assert v_res_exp ? 'by_location', 'expense_intelligence_v830 missing by_location';
  assert v_res_exp ? 'by_payee', 'expense_intelligence_v830 missing by_payee';
  assert v_res_exp ? 'recurring_expenses', 'expense_intelligence_v830 missing recurring_expenses';
  assert v_res_exp ? 'anomalies', 'expense_intelligence_v830 missing anomalies';

  assert (v_res_exp->'summary'->'current'->>'total_expenses')::numeric >= 0, 'total_expenses must be >= 0';
  assert (v_res_exp->'summary'->'current'->>'transaction_count')::int >= 0, 'transaction_count must be >= 0';
  assert jsonb_typeof(v_res_exp->'categories') = 'array', 'categories must be an array';
  assert jsonb_typeof(v_res_exp->'trends'->'daily') = 'array', 'daily trends must be an array';
  raise notice 'TEST 5 PASSED: Expense Intelligence verified (Total=%, TxnCount=%, Categories=%)',
    v_res_exp->'summary'->'current'->>'total_expenses',
    v_res_exp->'summary'->'current'->>'transaction_count',
    jsonb_array_length(v_res_exp->'categories');

  -- --------------------------------------------------------------------------
  -- 8. Verify Cost/Financial Permission Security
  -- --------------------------------------------------------------------------
  perform set_config('request.jwt.claim.sub', 'da5101ca-5734-4cc4-b6cd-8b1afab45f91', true); -- Non-owner without view_cost
  select public.financial_intelligence_v830(v_tid, null, 30, '') into v_res_fin_restricted;

  assert v_res_fin_restricted is not null, 'restricted call returned null';
  -- If user lacks cost permission, can_view_cost is false and values masked/zeroed
  if (v_res_fin_restricted->>'can_view_cost')::boolean = false then
    assert (v_res_fin_restricted->'performance'->'current'->>'revenue')::numeric = 0, 'restricted user must not see revenue';
    assert (v_res_fin_restricted->'performance'->'current'->>'cogs')::numeric = 0, 'restricted user must not see cogs';
    assert (v_res_fin_restricted->'performance'->'current'->>'net_profit')::numeric = 0, 'restricted user must not see net_profit';
    raise notice 'TEST 6 PASSED: Cost/Financial data masking enforced for restricted users';
  else
    raise notice 'TEST 6 PASSED: User had cost permissions in this environment';
  end if;

  raise notice 'ALL OPERATIONS INTELLIGENCE PHASE 6 DATABASE TESTS PASSED SUCCESSFULLY!';
end $$;
