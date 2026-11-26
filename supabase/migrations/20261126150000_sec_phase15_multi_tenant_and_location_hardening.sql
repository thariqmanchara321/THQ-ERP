-- ============================================================================
-- Migration: Phase 15 Security, Permissions & Multi-Tenant Isolation Hardening
-- Release: #718 (v8.3.12)
-- Description: Authoritative database-level scoping, location isolation,
--              permission guards, device status/expiry validation,
--              offline sync authorization, and revocation of anon access.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Helper: private.erp_can_view_all_locations
-- ----------------------------------------------------------------------------
create or replace function private.erp_can_view_all_locations(p_tenant_id uuid)
returns boolean language sql stable security definer set search_path=public,private,pg_temp as $$
  select exists (
    select 1 where private.erp_user_is_owner(p_tenant_id)
  ) or exists (
    select 1 where private.erp_has_permission(p_tenant_id, 'locations.view_all')
  ) or exists (
    select 1 where private.erp_has_permission(p_tenant_id, 'locations.manage_all')
  );
$$;

revoke all on function private.erp_can_view_all_locations(uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2. Helper: private.erp_assert_location_access
-- ----------------------------------------------------------------------------
create or replace function private.erp_assert_location_access(
  p_tenant_id uuid,
  p_location_id uuid,
  p_required text default 'view'
)
returns void language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  if p_location_id is not null then
    if not private.erp_document_scope_allowed(p_tenant_id, p_location_id, p_location_id, p_required) then
      raise exception 'Location access denied' using errcode = '42501';
    end if;
  else
    if not private.erp_can_view_all_locations(p_tenant_id) then
      raise exception 'Location access denied: cross-location view not authorized' using errcode = '42501';
    end if;
  end if;
end;
$$;

revoke all on function private.erp_assert_location_access(uuid, uuid, text) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3. Hardened POS Device Location & Active Status Validation
-- ----------------------------------------------------------------------------
create or replace function private.v486_pos_device_location(
  p_tenant_id uuid,
  p_device_id uuid,
  p_location_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_location uuid;
  v_type text;
  v_status text;
  v_deactivated_at timestamptz;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied' using errcode = '42501';
  end if;

  select d.location_id, d.app_type, d.status, d.deactivated_at
    into v_location, v_type, v_status, v_deactivated_at
  from public.business_devices d
  where d.id = p_device_id and d.tenant_id = p_tenant_id;

  if v_location is null then
    raise exception 'POS terminal not found';
  end if;
  if v_status <> 'active' or v_deactivated_at is not null then
    raise exception 'POS terminal is not active';
  end if;
  if v_type <> 'pos' then
    raise exception 'Offline POS sync requires a POS terminal';
  end if;
  if p_location_id is not null and p_location_id <> v_location then
    raise exception 'POS terminal location mismatch';
  end if;
  if not private.erp_document_scope_allowed(p_tenant_id, v_location, p_location_id, 'view') then
    raise exception 'Location access denied' using errcode = '42501';
  end if;

  return v_location;
end;
$$;

revoke all on function private.v486_pos_device_location(uuid, uuid, uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 4. Hardened Mobile POS and Client Mobile Location Resolution
-- ----------------------------------------------------------------------------
create or replace function private.v488_mobile_pos_location(
  p_tenant_id uuid,
  p_device_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
begin
  return private.v486_pos_device_location(p_tenant_id, p_device_id, null);
end;
$$;

revoke all on function private.v488_mobile_pos_location(uuid, uuid) from public, anon, authenticated;

create or replace function private.v487_client_mobile_location(
  p_tenant_id uuid,
  p_device_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_location uuid;
  v_type text;
  v_status text;
  v_deactivated_at timestamptz;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied' using errcode = '42501';
  end if;

  select d.location_id, d.app_type, d.status, d.deactivated_at
    into v_location, v_type, v_status, v_deactivated_at
  from public.business_devices d
  where d.id = p_device_id and d.tenant_id = p_tenant_id;

  if v_location is null then
    raise exception 'Client Mobile system not found';
  end if;
  if v_status <> 'active' or v_deactivated_at is not null then
    raise exception 'Client Mobile system is not active';
  end if;
  if v_type <> 'client' then
    raise exception 'Client Mobile requires a Client system activation';
  end if;
  if not private.erp_document_scope_allowed(p_tenant_id, v_location, v_location, 'view') then
    raise exception 'Location access denied' using errcode = '42501';
  end if;

  return v_location;
end;
$$;

revoke all on function private.v487_client_mobile_location(uuid, uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 5. Revoke Insecure Baseline anon Grants on Supplier Payment RPCs
-- ----------------------------------------------------------------------------
revoke all on function public.supplier_payment_create_v484(uuid, uuid, uuid, date, numeric, text, jsonb, text, text) from public, anon;
revoke all on function public.supplier_payment_create_v490(uuid, uuid, uuid, date, numeric, text, jsonb, text, text, uuid) from public, anon;
revoke all on function public.supplier_payment_list_v484(uuid, uuid, uuid, text, integer) from public, anon;
revoke all on function public.supplier_payment_void_v490(uuid, uuid, text) from public, anon;

grant execute on function public.supplier_payment_create_v484(uuid, uuid, uuid, date, numeric, text, jsonb, text, text) to authenticated, service_role;
grant execute on function public.supplier_payment_create_v490(uuid, uuid, uuid, date, numeric, text, jsonb, text, text, uuid) to authenticated, service_role;
grant execute on function public.supplier_payment_list_v484(uuid, uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function public.supplier_payment_void_v490(uuid, uuid, text) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 6. Hardened Supplier Payables Intelligence (Permission & Location Enforcement)
-- ----------------------------------------------------------------------------
create or replace function public.supplier_payables_intelligence_v480(
  p_tenant_id uuid,
  p_location_id uuid default null::uuid,
  p_query text default ''::text,
  p_limit integer default 1000
) returns table(
  supplier_id uuid,
  supplier_name text,
  phone text,
  total_outstanding numeric,
  current_amount numeric,
  days_1_30 numeric,
  days_31_60 numeric,
  days_61_90 numeric,
  days_90_plus numeric,
  open_invoice_count bigint,
  oldest_due_date date,
  last_purchase_date date,
  status text
)
language plpgsql stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  q text := '%' || lower(trim(coalesce(p_query, ''))) || '%';
  v_has_tenant_access boolean;
  v_has_support_access boolean;
begin
  v_has_tenant_access := private.erp_user_has_tenant_access(p_tenant_id);
  v_has_support_access := private.platform_user_has_support_access(p_tenant_id, 'supplier_support');
  if not v_has_tenant_access and not v_has_support_access then
    raise exception 'Access denied' using errcode = '42501';
  end if;

  if v_has_tenant_access and not v_has_support_access then
    if not (private.erp_user_is_owner(p_tenant_id)
            or private.erp_has_permission(p_tenant_id, 'purchases.view')
            or private.erp_has_permission(p_tenant_id, 'purchases.manage')
            or private.erp_has_permission(p_tenant_id, 'suppliers.view')
            or private.erp_has_permission(p_tenant_id, 'suppliers.manage')
            or private.erp_has_permission(p_tenant_id, 'reports.view')) then
      raise exception 'Supplier payables permission required' using errcode = '42501';
    end if;
  end if;

  if p_location_id is not null then
    if not (v_has_support_access or private.erp_document_scope_allowed(p_tenant_id, p_location_id, p_location_id, 'view')) then
      raise exception 'Location access denied' using errcode = '42501';
    end if;
  else
    if not (v_has_support_access or private.erp_can_view_all_locations(p_tenant_id)) then
      raise exception 'Location access denied: cross-location view not authorized' using errcode = '42501';
    end if;
  end if;

  return query
  with legacy_open as (
    select p.supplier_id, p.purchase_date, coalesce(p.due_date, p.purchase_date) due_date,
      greatest(p.grand_total - coalesce(rt.returned, 0) - coalesce(py.paid, 0), 0)::numeric balance
    from public.purchases p
    left join (select purchase_id, sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id = p.id
    left join (select purchase_id, sum(grand_total) returned from public.purchase_returns where credit_status <> 'waived' group by purchase_id) rt on rt.purchase_id = p.id
    left join public.document_origins o on o.tenant_id = p_tenant_id and o.entity_type = 'purchase' and o.entity_id = p.id
    where p.tenant_id = p_tenant_id and coalesce(p.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id, o.location_id, p_location_id, 'view')
      and greatest(p.grand_total - coalesce(rt.returned, 0) - coalesce(py.paid, 0), 0) > 0.005
  ), v2_open as (
    select i.supplier_id, i.invoice_date as purchase_date, coalesce(i.due_date, i.invoice_date) due_date,
      greatest(i.balance_due, 0)::numeric balance
    from public.purchase_invoices_v484 i
    where i.tenant_id = p_tenant_id and i.status in ('posted', 'part_paid') and i.balance_due > 0.005
      and (p_location_id is null or i.location_id = p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id, i.location_id, p_location_id, 'view')
  ), open_docs as (
    select * from legacy_open
    union all
    select * from v2_open
  ), agg as (
    select op.supplier_id, sum(op.balance)::numeric outstanding, count(*)::bigint cnt, min(op.due_date) oldest, max(op.purchase_date) last_purchase,
      coalesce(sum(op.balance) filter (where op.due_date >= current_date), 0)::numeric current_amt,
      coalesce(sum(op.balance) filter (where op.due_date < current_date and op.due_date >= current_date - 30), 0)::numeric a1,
      coalesce(sum(op.balance) filter (where op.due_date < current_date - 30 and op.due_date >= current_date - 60), 0)::numeric a2,
      coalesce(sum(op.balance) filter (where op.due_date < current_date - 60 and op.due_date >= current_date - 90), 0)::numeric a3,
      coalesce(sum(op.balance) filter (where op.due_date < current_date - 90), 0)::numeric a4
    from open_docs op group by op.supplier_id
  )
  select s.id, s.name, coalesce(s.phone, ''), coalesce(a.outstanding, 0)::numeric, coalesce(a.current_amt, 0)::numeric, coalesce(a.a1, 0)::numeric,
    coalesce(a.a2, 0)::numeric, coalesce(a.a3, 0)::numeric, coalesce(a.a4, 0)::numeric, coalesce(a.cnt, 0), a.oldest, a.last_purchase,
    (case when coalesce(a.outstanding, 0) <= 0.005 then 'clear' when coalesce(a.a4, 0) > 0 then 'critical_overdue'
      when coalesce(a.a1, 0) + coalesce(a.a2, 0) + coalesce(a.a3, 0) > 0 then 'overdue' else 'current' end)::text
  from public.suppliers s left join agg a on a.supplier_id = s.id
  where s.tenant_id = p_tenant_id and coalesce(s.status, 'active') = 'active'
    and (trim(coalesce(p_query, '')) = '' or lower(s.name) like q or lower(coalesce(s.phone, '')) like q)
  order by coalesce(a.a4, 0) desc, coalesce(a.outstanding, 0) desc, s.name
  limit greatest(1, least(coalesce(p_limit, 1000), 5000));
end;
$$;

revoke all on function public.supplier_payables_intelligence_v480(uuid, uuid, text, integer) from public, anon;
grant execute on function public.supplier_payables_intelligence_v480(uuid, uuid, text, integer) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 7. Hardened Customer Credit Intelligence (Permission & Location Enforcement)
-- ----------------------------------------------------------------------------
create or replace function public.customer_credit_intelligence_v480(
  p_tenant_id uuid,
  p_location_id uuid default null::uuid,
  p_query text default ''::text,
  p_limit integer default 1000
) returns table(
  customer_id uuid,
  public_id text,
  customer_name text,
  phone text,
  credit_limit numeric,
  total_outstanding numeric,
  available_credit numeric,
  utilization_pct numeric,
  current_amount numeric,
  days_1_30 numeric,
  days_31_60 numeric,
  days_61_90 numeric,
  days_90_plus numeric,
  open_invoice_count bigint,
  oldest_due_date date,
  status text
)
language plpgsql stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  q text := '%' || lower(trim(coalesce(p_query, ''))) || '%';
  v_has_tenant_access boolean;
  v_has_support_access boolean;
begin
  v_has_tenant_access := private.erp_user_has_tenant_access(p_tenant_id);
  v_has_support_access := private.platform_user_has_support_access(p_tenant_id, 'customer_support');
  if not v_has_tenant_access and not v_has_support_access then
    raise exception 'Access denied' using errcode = '42501';
  end if;

  if v_has_tenant_access and not v_has_support_access then
    if not (private.erp_user_is_owner(p_tenant_id)
            or private.erp_has_permission(p_tenant_id, 'customers.view')
            or private.erp_has_permission(p_tenant_id, 'customers.manage')
            or private.erp_has_permission(p_tenant_id, 'sales.view')
            or private.erp_has_permission(p_tenant_id, 'accounting.view')
            or private.erp_has_permission(p_tenant_id, 'reports.view')) then
      raise exception 'Customer credit permission required' using errcode = '42501';
    end if;
  end if;

  if p_location_id is not null then
    if not (v_has_support_access or private.erp_document_scope_allowed(p_tenant_id, p_location_id, p_location_id, 'view')) then
      raise exception 'Location access denied' using errcode = '42501';
    end if;
  else
    if not (v_has_support_access or private.erp_can_view_all_locations(p_tenant_id)) then
      raise exception 'Location access denied: cross-location view not authorized' using errcode = '42501';
    end if;
  end if;

  return query
  with open_sales as (
    select s.id, s.customer_id, coalesce(s.due_date, s.sale_date) due_date,
      greatest(s.grand_total - coalesce(rt.returned, 0) - coalesce(py.paid, 0), 0)::numeric balance
    from public.sales s
    left join (select sale_id, sum(amount) paid from public.sale_payments group by sale_id) py on py.sale_id = s.id
    left join (select sale_id, sum(grand_total) returned from public.sales_returns where refund_status <> 'waived' group by sale_id) rt on rt.sale_id = s.id
    left join public.document_origins o on o.tenant_id = p_tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
    where s.tenant_id = p_tenant_id and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id, o.location_id, p_location_id, 'view')
      and greatest(s.grand_total - coalesce(rt.returned, 0) - coalesce(py.paid, 0), 0) > 0.005
  ), agg as (
    select os.customer_id, sum(os.balance)::numeric outstanding, count(*)::bigint cnt, min(os.due_date) oldest,
      sum(os.balance) filter (where os.due_date >= current_date)::numeric current_amt,
      sum(os.balance) filter (where os.due_date < current_date and os.due_date >= current_date - 30)::numeric a1,
      sum(os.balance) filter (where os.due_date < current_date - 30 and os.due_date >= current_date - 60)::numeric a2,
      sum(os.balance) filter (where os.due_date < current_date - 60 and os.due_date >= current_date - 90)::numeric a3,
      sum(os.balance) filter (where os.due_date < current_date - 90)::numeric a4
    from open_sales os group by os.customer_id
  )
  select c.id, coalesce(c.tracking_code, ''), c.name, coalesce(c.phone, ''), coalesce(c.credit_limit, 0)::numeric, coalesce(a.outstanding, 0)::numeric,
    greatest(coalesce(c.credit_limit, 0) - coalesce(a.outstanding, 0), 0)::numeric,
    case when coalesce(c.credit_limit, 0) > 0 then round(coalesce(a.outstanding, 0) * 100 / coalesce(c.credit_limit, 1), 1) else null end::numeric,
    coalesce(a.current_amt, 0)::numeric, coalesce(a.a1, 0)::numeric, coalesce(a.a2, 0)::numeric, coalesce(a.a3, 0)::numeric, coalesce(a.a4, 0)::numeric,
    coalesce(a.cnt, 0), a.oldest,
    (case when coalesce(a.outstanding, 0) <= 0.005 then 'clear' when coalesce(a.a4, 0) > 0 then 'critical_overdue'
      when coalesce(a.a1, 0) + coalesce(a.a2, 0) + coalesce(a.a3, 0) > 0 then 'overdue' else 'current' end)::text
  from public.customers c left join agg a on a.customer_id = c.id
  where c.tenant_id = p_tenant_id and coalesce(c.status, 'active') = 'active'
    and (trim(coalesce(p_query, '')) = '' or lower(c.name) like q or lower(coalesce(c.phone, '')) like q)
  order by coalesce(a.a4, 0) desc, coalesce(a.outstanding, 0) desc, c.name
  limit greatest(1, least(coalesce(p_limit, 1000), 5000));
end;
$$;

revoke all on function public.customer_credit_intelligence_v480(uuid, uuid, text, integer) from public, anon;
grant execute on function public.customer_credit_intelligence_v480(uuid, uuid, text, integer) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 8. Hardened Daily Detailed Accounts (v7.2.5 Enrichment Baseline with Scoping)
-- ----------------------------------------------------------------------------
create or replace function public.daily_detailed_accounts_v720(
  p_tenant_id uuid,
  p_from date,
  p_to date,
  p_location_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_zone text;
  v_cash_opening numeric := 0;
  v_cash_received numeric := 0;
  v_cash_paid numeric := 0;
  v_cash_closing numeric := 0;

  v_bank_opening numeric := 0;
  v_bank_received numeric := 0;
  v_bank_paid numeric := 0;
  v_bank_closing numeric := 0;

  v_sales_count bigint := 0;
  v_sales_total numeric := 0;
  v_sales_tax numeric := 0;
  v_sales_cash numeric := 0;
  v_sales_bank numeric := 0;
  v_sales_credit numeric := 0;

  v_purchases_count bigint := 0;
  v_purchases_total numeric := 0;
  v_purchases_tax numeric := 0;
  v_purchases_cash numeric := 0;
  v_purchases_bank numeric := 0;
  v_purchases_credit numeric := 0;

  v_customer_receipts numeric := 0;
  v_supplier_payments numeric := 0;
  v_expenses_total numeric := 0;
  v_transfers_total numeric := 0;

  v_sales_returns_count bigint := 0;
  v_sales_returns_total numeric := 0;
  v_purchase_returns_count bigint := 0;
  v_purchase_returns_total numeric := 0;

  v_ar_opening numeric := 0;
  v_ar_closing numeric := 0;
  v_ap_opening numeric := 0;
  v_ap_closing numeric := 0;

  v_day_journals jsonb := '[]'::jsonb;
  v_exceptions jsonb := '[]'::jsonb;
  v_closing_statement text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Tenant access denied' using errcode = '42501';
  end if;

  if not (private.erp_user_is_owner(p_tenant_id)
          or private.erp_has_permission(p_tenant_id, 'accounting.view')
          or private.erp_has_permission(p_tenant_id, 'reports.view')) then
    raise exception 'Accounting permission required' using errcode = '42501';
  end if;

  perform private.erp_assert_location_access(p_tenant_id, p_location_id, 'view');

  select coalesce(timezone, 'Asia/Kolkata') into v_zone
  from public.tenant_settings
  where tenant_id = p_tenant_id;

  -- 1. Cash Balances
  select coalesce(sum(jl.debit - jl.credit), 0) into v_cash_opening
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date < p_from
    and (a.system_key in ('cash_drawer', 'cash_in_hand') or private.accounting_money_method_v702(p_tenant_id, a.id) = 'cash')
    and (p_location_id is null or j.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, j.location_id, p_location_id, 'view');

  select
    coalesce(sum(case when jl.debit > jl.credit then jl.debit - jl.credit else 0 end), 0),
    coalesce(sum(case when jl.credit > jl.debit then jl.credit - jl.debit else 0 end), 0)
    into v_cash_received, v_cash_paid
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date between p_from and p_to
    and (a.system_key in ('cash_drawer', 'cash_in_hand') or private.accounting_money_method_v702(p_tenant_id, a.id) = 'cash')
    and (p_location_id is null or j.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, j.location_id, p_location_id, 'view');

  v_cash_closing := v_cash_opening + v_cash_received - v_cash_paid;

  -- 2. Bank Balances
  select coalesce(sum(jl.debit - jl.credit), 0) into v_bank_opening
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date < p_from
    and (a.account_type = 'bank' or private.accounting_money_method_v702(p_tenant_id, a.id) in ('bank', 'bank_account', 'upi', 'card', 'pos_card'))
    and (p_location_id is null or j.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, j.location_id, p_location_id, 'view');

  select
    coalesce(sum(case when jl.debit > jl.credit then jl.debit - jl.credit else 0 end), 0),
    coalesce(sum(case when jl.credit > jl.debit then jl.credit - jl.debit else 0 end), 0)
    into v_bank_received, v_bank_paid
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date between p_from and p_to
    and (a.account_type = 'bank' or private.accounting_money_method_v702(p_tenant_id, a.id) in ('bank', 'bank_account', 'upi', 'card', 'pos_card'))
    and (p_location_id is null or j.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, j.location_id, p_location_id, 'view');

  v_bank_closing := v_bank_opening + v_bank_received - v_bank_paid;

  -- 3. Sales Totals
  select
    count(distinct s.id),
    coalesce(sum(s.grand_total), 0),
    coalesce(sum(s.tax_total), 0)
    into v_sales_count, v_sales_total, v_sales_tax
  from public.sales s
  left join public.document_origins os on os.tenant_id = s.tenant_id and os.entity_type = 'sale' and os.entity_id = s.id
  where s.tenant_id = p_tenant_id
    and s.sale_date between p_from and p_to
    and coalesce(s.status, '') not in ('void', 'cancelled')
    and (p_location_id is null or os.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, os.location_id, p_location_id, 'view');

  select coalesce(sum(sp.amount), 0) into v_sales_cash
  from public.sale_payments sp
  join public.sales s on s.id = sp.sale_id and s.tenant_id = sp.tenant_id
  left join public.document_origins os on os.tenant_id = s.tenant_id and os.entity_type = 'sale' and os.entity_id = s.id
  where s.tenant_id = p_tenant_id
    and s.sale_date between p_from and p_to
    and coalesce(s.status, '') not in ('void', 'cancelled')
    and lower(trim(coalesce(sp.payment_method, ''))) in ('cash')
    and (p_location_id is null or os.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, os.location_id, p_location_id, 'view');

  select coalesce(sum(sp.amount), 0) into v_sales_bank
  from public.sale_payments sp
  join public.sales s on s.id = sp.sale_id and s.tenant_id = sp.tenant_id
  left join public.document_origins os on os.tenant_id = s.tenant_id and os.entity_type = 'sale' and os.entity_id = s.id
  where s.tenant_id = p_tenant_id
    and s.sale_date between p_from and p_to
    and coalesce(s.status, '') not in ('void', 'cancelled')
    and lower(trim(coalesce(sp.payment_method, ''))) not in ('cash', 'credit')
    and (p_location_id is null or os.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, os.location_id, p_location_id, 'view');

  v_sales_credit := greatest(0, v_sales_total - v_sales_cash - v_sales_bank);

  -- 4. Purchases Totals
  select
    count(distinct p.id),
    coalesce(sum(p.grand_total), 0),
    coalesce(sum(p.tax_total), 0)
    into v_purchases_count, v_purchases_total, v_purchases_tax
  from public.purchases p
  left join public.document_origins op on op.tenant_id = p.tenant_id and op.entity_type = 'purchase' and op.entity_id = p.id
  where p.tenant_id = p_tenant_id
    and p.purchase_date between p_from and p_to
    and coalesce(p.status, '') not in ('void', 'cancelled')
    and (p_location_id is null or op.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, op.location_id, p_location_id, 'view');

  select coalesce(sum(pp.amount), 0) into v_purchases_cash
  from public.purchase_payments pp
  join public.purchases p on p.id = pp.purchase_id and p.tenant_id = pp.tenant_id
  left join public.document_origins op on op.tenant_id = p.tenant_id and op.entity_type = 'purchase' and op.entity_id = p.id
  where p.tenant_id = p_tenant_id
    and p.purchase_date between p_from and p_to
    and coalesce(p.status, '') not in ('void', 'cancelled')
    and lower(trim(coalesce(pp.payment_method, ''))) in ('cash')
    and (p_location_id is null or op.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, op.location_id, p_location_id, 'view');

  select coalesce(sum(pp.amount), 0) into v_purchases_bank
  from public.purchase_payments pp
  join public.purchases p on p.id = pp.purchase_id and p.tenant_id = pp.tenant_id
  left join public.document_origins op on op.tenant_id = p.tenant_id and op.entity_type = 'purchase' and op.entity_id = p.id
  where p.tenant_id = p_tenant_id
    and p.purchase_date between p_from and p_to
    and coalesce(p.status, '') not in ('void', 'cancelled')
    and lower(trim(coalesce(pp.payment_method, ''))) not in ('cash', 'credit')
    and (p_location_id is null or op.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, op.location_id, p_location_id, 'view');

  v_purchases_credit := greatest(0, v_purchases_total - v_purchases_cash - v_purchases_bank);

  -- 5. Customer Receipts, Supplier Payments, Expenses, Transfers
  select coalesce(sum(sp.amount), 0) into v_customer_receipts
  from public.sale_payments sp
  join public.sales s on s.id = sp.sale_id and s.tenant_id = sp.tenant_id
  left join public.document_origins os on os.tenant_id = s.tenant_id and os.entity_type = 'sale' and os.entity_id = s.id
  where s.tenant_id = p_tenant_id
    and sp.payment_date between p_from and p_to
    and coalesce(s.status, '') not in ('void', 'cancelled')
    and (p_location_id is null or os.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, os.location_id, p_location_id, 'view');

  select coalesce(sum(pp.amount), 0) into v_supplier_payments
  from public.purchase_payments pp
  join public.purchases p on p.id = pp.purchase_id and p.tenant_id = pp.tenant_id
  left join public.document_origins op on op.tenant_id = p.tenant_id and op.entity_type = 'purchase' and op.entity_id = p.id
  where p.tenant_id = p_tenant_id
    and pp.payment_date between p_from and p_to
    and coalesce(p.status, '') not in ('void', 'cancelled')
    and (p_location_id is null or op.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, op.location_id, p_location_id, 'view');

  select coalesce(sum(e.total_amount), 0) into v_expenses_total
  from public.expenses e
  left join public.document_origins oe on oe.tenant_id = e.tenant_id and oe.entity_type = 'expense' and oe.entity_id = e.id
  where e.tenant_id = p_tenant_id
    and e.expense_date between p_from and p_to
    and e.status = 'posted'
    and (p_location_id is null or oe.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, oe.location_id, p_location_id, 'view');

  select coalesce(sum(jl.debit), 0) into v_transfers_total
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  where j.tenant_id = p_tenant_id
    and j.status = 'posted'
    and j.entry_date between p_from and p_to
    and j.entry_type in ('contra', 'transfer')
    and (p_location_id is null or j.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, j.location_id, p_location_id, 'view');

  -- 6. Returns
  select count(*), coalesce(sum(sr.grand_total), 0)
    into v_sales_returns_count, v_sales_returns_total
  from public.sales_returns sr
  where sr.tenant_id = p_tenant_id
    and sr.return_date between p_from and p_to
    and sr.refund_status <> 'waived'
    and (p_location_id is null or sr.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, sr.location_id, p_location_id, 'view');

  select count(*), coalesce(sum(pr.grand_total), 0)
    into v_purchase_returns_count, v_purchase_returns_total
  from public.purchase_returns pr
  where pr.tenant_id = p_tenant_id
    and pr.return_date between p_from and p_to
    and pr.credit_status <> 'waived'
    and (p_location_id is null or pr.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, pr.location_id, p_location_id, 'view');

  -- 7. Receivables and Payables Movement
  select coalesce(sum(jl.debit - jl.credit), 0) into v_ar_opening
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id and j.status = 'posted' and j.entry_date < p_from
    and a.system_key = 'accounts_receivable'
    and (p_location_id is null or j.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, j.location_id, p_location_id, 'view');

  select coalesce(sum(jl.debit - jl.credit), 0) into v_ar_closing
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id and j.status = 'posted' and j.entry_date <= p_to
    and a.system_key = 'accounts_receivable'
    and (p_location_id is null or j.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, j.location_id, p_location_id, 'view');

  select coalesce(sum(jl.credit - jl.debit), 0) into v_ap_opening
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id and j.status = 'posted' and j.entry_date < p_from
    and a.system_key = 'accounts_payable'
    and (p_location_id is null or j.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, j.location_id, p_location_id, 'view');

  select coalesce(sum(jl.credit - jl.debit), 0) into v_ap_closing
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  join public.accounting_accounts a on a.id = jl.account_id and a.tenant_id = j.tenant_id
  where j.tenant_id = p_tenant_id and j.status = 'posted' and j.entry_date <= p_to
    and a.system_key = 'accounts_payable'
    and (p_location_id is null or j.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, j.location_id, p_location_id, 'view');

  -- 8. Day Journals
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', j.id,
      'entry_number', j.entry_number,
      'entry_date', j.entry_date,
      'created_at', j.created_at,
      'entry_type', j.entry_type,
      'description', j.description,
      'reference_type', j.reference_type,
      'reference_id', j.reference_id,
      'status', j.status,
      'total_debit', coalesce(l.total_debit, 0),
      'total_credit', coalesce(l.total_credit, 0),
      'line_count', coalesce(l.line_count, 0),
      'party_name', case
        when j.reference_type in ('sale', 'sales_invoice') then (select c.name from public.sales s join public.customers c on c.id = s.customer_id where s.id = j.reference_id)
        when j.reference_type in ('purchase', 'purchase_invoice') then (select sup.name from public.purchases p join public.suppliers sup on sup.id = p.supplier_id where p.id = j.reference_id)
        else null
      end,
      'financial_effect', case
        when j.entry_type in ('sale', 'sales_invoice') then 'Revenue Recognition / AR'
        when j.entry_type in ('purchase', 'purchase_invoice') then 'Inventory / AP Liability'
        when j.entry_type = 'expense' then 'Operating Expense'
        when j.entry_type in ('payment_in', 'receipt') then 'Cash/Bank Inflow'
        when j.entry_type in ('payment_out', 'payment') then 'Cash/Bank Outflow'
        when j.entry_type = 'contra' then 'Cash/Bank Transfer'
        else initcap(coalesce(j.entry_type, 'journal'))
      end,
      'is_reversal', coalesce(j.description ilike '%reversal%' or j.description ilike '%void%', false),
      'is_balanced', abs(coalesce(l.total_debit, 0) - coalesce(l.total_credit, 0)) < 0.01,
      'lines', coalesce(l.lines, '[]'::jsonb)
    ) order by j.entry_date desc, j.created_at desc
  ), '[]'::jsonb) into v_day_journals
  from public.journal_entries j
  left join lateral (
    select
      sum(jl.debit) as total_debit,
      sum(jl.credit) as total_credit,
      count(*) as line_count,
      jsonb_agg(
        jsonb_build_object(
          'id', jl.id,
          'account_id', jl.account_id,
          'account_code', a.account_code,
          'account_name', a.name,
          'account_type', a.account_type,
          'debit', jl.debit,
          'credit', jl.credit,
          'description', jl.description
        ) order by jl.line_order, jl.created_at
      ) as lines
    from public.journal_lines jl
    join public.accounting_accounts a on a.id = jl.account_id
    where jl.journal_entry_id = j.id
  ) l on true
  where j.tenant_id = p_tenant_id
    and j.entry_date between p_from and p_to
    and (p_location_id is null or j.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, j.location_id, p_location_id, 'view')
  limit 200;

  -- 9. Closing Statement
  v_closing_statement := format(
    'Daily Accounts Report for %s to %s. Total Sales: %s across %s transactions. Total Purchases: %s across %s orders. Cash Net: %s (Closing %s). Bank Net: %s (Closing %s). System reconciliation status: %s.',
    p_from, p_to,
    round(v_sales_total, 2), v_sales_count,
    round(v_purchases_total, 2), v_purchases_count,
    round(v_cash_received - v_cash_paid, 2), round(v_cash_closing, 2),
    round(v_bank_received - v_bank_paid, 2), round(v_bank_closing, 2),
    case when jsonb_array_length(v_exceptions) = 0 then 'BALANCED' else 'FLAGGED' end
  );

  return jsonb_build_object(
    'period', jsonb_build_object(
      'from', p_from,
      'to', p_to,
      'generated_at', now(),
      'timezone', v_zone,
      'location_id', p_location_id
    ),
    'cash', jsonb_build_object(
      'opening', v_cash_opening,
      'received', v_cash_received,
      'paid', v_cash_paid,
      'closing', v_cash_closing,
      'net_movement', v_cash_received - v_cash_paid
    ),
    'bank', jsonb_build_object(
      'opening', v_bank_opening,
      'received', v_bank_received,
      'paid', v_bank_paid,
      'closing', v_bank_closing,
      'net_movement', v_bank_received - v_bank_paid
    ),
    'sales', jsonb_build_object(
      'count', v_sales_count,
      'total', v_sales_total,
      'tax', v_sales_tax,
      'cash', v_sales_cash,
      'bank', v_sales_bank,
      'credit', v_sales_credit
    ),
    'purchases', jsonb_build_object(
      'count', v_purchases_count,
      'total', v_purchases_total,
      'tax', v_purchases_tax,
      'cash', v_purchases_cash,
      'bank', v_purchases_bank,
      'credit', v_purchases_credit
    ),
    'receipts', jsonb_build_object(
      'customer_receipts', v_customer_receipts
    ),
    'payments', jsonb_build_object(
      'supplier_payments', v_supplier_payments,
      'operating_expenses', v_expenses_total,
      'transfers', v_transfers_total
    ),
    'returns', jsonb_build_object(
      'sales_count', v_sales_returns_count,
      'sales_total', v_sales_returns_total,
      'purchase_count', v_purchase_returns_count,
      'purchase_total', v_purchase_returns_total
    ),
    'receivables', jsonb_build_object(
      'opening', v_ar_opening,
      'closing', v_ar_closing,
      'net_movement', v_ar_closing - v_ar_opening
    ),
    'payables', jsonb_build_object(
      'opening', v_ap_opening,
      'closing', v_ap_closing,
      'net_movement', v_ap_closing - v_ap_opening
    ),
    'day_journals', v_day_journals,
    'exceptions', v_exceptions,
    'reconciliation_status', case when jsonb_array_length(v_exceptions) = 0 then 'Passed' else 'Mismatch' end,
    'integrity_checks', jsonb_build_object(
      'double_entry_balanced', not exists (
        select 1 from public.journal_entries j
        left join lateral (
          select sum(jl.debit) as debits, sum(jl.credit) as credits
          from public.journal_lines jl where jl.journal_entry_id = j.id
        ) l on true
        where j.tenant_id = p_tenant_id and j.entry_date between p_from and p_to
          and abs(coalesce(l.debits, 0) - coalesce(l.credits, 0)) >= 0.01
      ),
      'non_negative_cash', v_cash_closing >= 0,
      'cash_ledger_reconciled', true,
      'reconciliation_status', case when jsonb_array_length(v_exceptions) = 0 then 'Passed' else 'Exceptions Flagged' end,
      'exceptions_count', jsonb_array_length(v_exceptions)
    ),
    'closing_statement', v_closing_statement
  );
end;
$$;

revoke all on function public.daily_detailed_accounts_v720(uuid, date, date, uuid) from public, anon;
grant execute on function public.daily_detailed_accounts_v720(uuid, date, date, uuid) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 9. Hardened Operations Intelligence Summary (v8.3.0)
-- ----------------------------------------------------------------------------
create or replace function public.operations_intelligence_summary_v830(
  p_tenant_id uuid,
  p_location_id uuid default null::uuid,
  p_days integer default 30
)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_from date := current_date - (v_days - 1);
  v_sales numeric := 0;
  v_returns numeric := 0;
  v_cost numeric := 0;
  v_order_count bigint := 0;
  v_expenses numeric := 0;
  v_inventory_val numeric := 0;
  v_low_stock bigint := 0;
  v_out_of_stock bigint := 0;
  v_dead_stock bigint := 0;
  v_overstock bigint := 0;
  v_total_variants bigint := 0;
  v_receivable numeric := 0;
  v_overdue_recv numeric := 0;
  v_payable numeric := 0;
  v_overdue_pay numeric := 0;
  v_aov numeric := 0;
  v_unresolved_insights bigint := 0;
  v_critical_insights bigint := 0;
  v_pending_actions bigint := 0;
  v_pipeline jsonb := '{}'::jsonb;
  v_hourly jsonb := '[]'::jsonb;
  v_top_products jsonb := '[]'::jsonb;
  v_can_view_cost boolean := false;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied' using errcode = '42501';
  end if;

  perform private.erp_assert_location_access(p_tenant_id, p_location_id, 'view');

  v_can_view_cost := private.erp_user_is_owner(p_tenant_id) 
    or private.erp_has_permission(p_tenant_id, 'inventory.view_cost')
    or private.erp_has_permission(p_tenant_id, 'inventory.manage');

  -- Sales & Revenue metrics (join document_origins for location mapping)
  select coalesce(sum(s.grand_total), 0), coalesce(sum(s.cost_total), 0), count(*)
    into v_sales, v_cost, v_order_count
  from public.sales s
  left join public.document_origins o on o.tenant_id = s.tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
  where s.tenant_id = p_tenant_id
    and s.sale_date between v_from and current_date
    and coalesce(s.status, '') not in ('void', 'cancelled')
    and (p_location_id is null or o.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, o.location_id, p_location_id, 'view');

  -- Sales returns
  select coalesce(sum(r.grand_total), 0)
    into v_returns
  from public.sales_returns r
  where r.tenant_id = p_tenant_id
    and r.return_date between v_from and current_date
    and r.refund_status <> 'waived'
    and (p_location_id is null or r.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, r.location_id, p_location_id, 'view');

  if v_order_count > 0 then
    v_aov := round((v_sales - v_returns) / v_order_count, 2);
  end if;

  -- Expenses
  select coalesce(sum(e.total_amount), 0)
    into v_expenses
  from public.expenses e
  left join public.document_origins o on o.tenant_id = e.tenant_id and o.entity_type = 'expense' and o.entity_id = e.id
  where e.tenant_id = p_tenant_id
    and e.expense_date between v_from and current_date
    and e.status = 'posted'
    and (p_location_id is null or o.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, o.location_id, p_location_id, 'view');

  -- Inventory health from v830 RPC
  select 
    count(*) filter (where status = 'low_stock'),
    count(*) filter (where status = 'out_of_stock'),
    count(*) filter (where status = 'dead_stock'),
    count(*) filter (where status = 'overstock'),
    count(*),
    coalesce(sum(stock_value), 0)
  into v_low_stock, v_out_of_stock, v_dead_stock, v_overstock, v_total_variants, v_inventory_val
  from public.inventory_intelligence_v830(p_tenant_id, p_location_id, v_days, '', 5000);

  -- Customer credit receivables
  select 
    coalesce(sum(total_outstanding), 0),
    coalesce(sum(days_1_30 + days_31_60 + days_61_90 + days_90_plus), 0)
  into v_receivable, v_overdue_recv
  from public.customer_credit_intelligence_v480(p_tenant_id, p_location_id, '', 5000);

  -- Supplier payables
  select 
    coalesce(sum(total_outstanding), 0),
    coalesce(sum(days_1_30 + days_31_60 + days_61_90 + days_90_plus), 0)
  into v_payable, v_overdue_pay
  from public.supplier_payables_intelligence_v480(p_tenant_id, p_location_id, '', 5000);

  -- Operations pipeline
  v_pipeline := coalesce(public.operations_pipeline_v489(p_tenant_id, p_location_id), '{}'::jsonb);

  -- Active insights counts
  select count(*), count(*) filter (where severity = 'critical')
    into v_unresolved_insights, v_critical_insights
  from public.erp_intelligence_insights
  where tenant_id = p_tenant_id
    and status in ('new_insight', 'acknowledged', 'in_progress')
    and (p_location_id is null or location_id is null or location_id = p_location_id);

  -- Pending actions count
  select count(*)
    into v_pending_actions
  from public.erp_intelligence_actions
  where tenant_id = p_tenant_id
    and status = 'pending_approval'
    and (p_location_id is null or location_id is null or location_id = p_location_id);

  -- Top 10 selling products (join document_origins for location mapping)
  select coalesce(jsonb_agg(to_jsonb(tp)), '[]'::jsonb)
  into v_top_products
  from (
    select pr.name as product_name, pv.sku, sum(si.quantity) as quantity_sold, round(sum(si.line_total), 2) as revenue
    from public.sale_items si
    join public.sales s on s.id = si.sale_id
    join public.product_variants pv on pv.id = si.variant_id
    join public.products pr on pr.id = pv.product_id
    left join public.document_origins o on o.tenant_id = s.tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
    where s.tenant_id = p_tenant_id
      and s.sale_date between v_from and current_date
      and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id, o.location_id, p_location_id, 'view')
    group by pr.name, pv.sku
    order by revenue desc
    limit 10
  ) tp;

  -- Hourly sales distribution for today
  select coalesce(jsonb_agg(to_jsonb(hd)), '[]'::jsonb)
  into v_hourly
  from (
    select extract(hour from s.created_at)::int as hour, count(*) as count, round(sum(s.grand_total), 2) as total
    from public.sales s
    left join public.document_origins o on o.tenant_id = s.tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
    where s.tenant_id = p_tenant_id
      and s.sale_date = current_date
      and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id, o.location_id, p_location_id, 'view')
    group by extract(hour from s.created_at)
    order by hour
  ) hd;

  return jsonb_build_object(
    'gross_sales', round(v_sales, 2),
    'sales_returns', round(v_returns, 2),
    'net_sales', round(v_sales - v_returns, 2),
    'order_count', v_order_count,
    'average_order_value', v_aov,
    'cogs', case when v_can_view_cost then round(v_cost, 2) else null end,
    'gross_margin', case when v_can_view_cost and v_sales > 0 then round((v_sales - v_cost) / v_sales * 100, 2) else null end,
    'operating_expenses', round(v_expenses, 2),
    'net_profit', case when v_can_view_cost then round(v_sales - v_returns - v_cost - v_expenses, 2) else null end,
    'stock_value', case when v_can_view_cost then round(v_inventory_val, 2) else null end,
    'total_variants', v_total_variants,
    'low_stock_count', v_low_stock,
    'out_of_stock_count', v_out_of_stock,
    'dead_stock_count', v_dead_stock,
    'overstock_count', v_overstock,
    'total_receivable', round(v_receivable, 2),
    'overdue_receivable', round(v_overdue_recv, 2),
    'total_payable', round(v_payable, 2),
    'overdue_payable', round(v_overdue_pay, 2),
    'unresolved_insights', v_unresolved_insights,
    'critical_insights', v_critical_insights,
    'pending_actions', v_pending_actions,
    'pipeline', v_pipeline,
    'hourly_distribution', v_hourly,
    'top_products', v_top_products,
    'cost_visible', v_can_view_cost
  );
end;
$$;

revoke all on function public.operations_intelligence_summary_v830(uuid, uuid, integer) from public, anon;
grant execute on function public.operations_intelligence_summary_v830(uuid, uuid, integer) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 10. Hardened Inventory Intelligence (v8.3.0)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.inventory_intelligence_v830(
  p_tenant_id uuid,
  p_location_id uuid DEFAULT NULL::uuid,
  p_days integer DEFAULT 30,
  p_query text DEFAULT ''::text,
  p_limit integer DEFAULT 1000
)
RETURNS TABLE (
  location_id uuid,
  location_code text,
  location_name text,
  variant_id uuid,
  product_id uuid,
  product_name text,
  sku text,
  barcode text,
  quantity numeric,
  available numeric,
  reorder_level numeric,
  max_stock numeric,
  average_cost numeric,
  stock_value numeric,
  net_sold_qty numeric,
  avg_daily_sales numeric,
  days_cover numeric,
  suggested_reorder numeric,
  last_sale_date date,
  last_purchase_date date,
  status text,
  abc_class text,
  movement_class text,
  incoming_po_qty numeric,
  in_transit_qty numeric,
  reserved_qty numeric,
  net_effective_stock numeric,
  sales_value numeric,
  cumulative_sales_pct numeric,
  turnover_ratio numeric,
  excess_qty numeric,
  excess_value numeric
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_from date := current_date - (v_days - 1);
  q text := '%' || lower(trim(coalesce(p_query, ''))) || '%';
  v_can_view_cost boolean := false;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied' using errcode = '42501';
  end if;

  perform private.erp_assert_location_access(p_tenant_id, p_location_id, 'view');

  v_can_view_cost := private.erp_user_is_owner(p_tenant_id) 
    or private.erp_has_permission(p_tenant_id, 'inventory.view_cost')
    or private.erp_has_permission(p_tenant_id, 'inventory.manage');

  return query
  with active_locs as (
    select l.id as location_id, l.location_code, l.name as location_name
    from public.business_locations l
    where l.tenant_id = p_tenant_id
      and l.active = true
      and (p_location_id is null or l.id = p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id, l.id, p_location_id, 'view')
  ),
  sold as (
    select o.location_id, si.variant_id,
      sum(greatest(si.quantity - coalesce((
        select sum(ri.quantity)
        from public.sales_return_items ri
        join public.sales_returns r on r.id = ri.sales_return_id
        where ri.sale_item_id = si.id and r.refund_status <> 'waived' and r.return_date <= current_date
      ), 0), 0))::numeric as qty
    from public.sale_items si
    join public.sales s on s.id = si.sale_id
    join public.document_origins o on o.tenant_id = p_tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
    where s.tenant_id = p_tenant_id
      and s.sale_date between v_from and current_date
      and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id, o.location_id, p_location_id, 'view')
    group by o.location_id, si.variant_id
  ),
  last_sold as (
    select o.location_id, si.variant_id, max(s.sale_date) as last_date
    from public.sale_items si
    join public.sales s on s.id = si.sale_id
    join public.document_origins o on o.tenant_id = p_tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
    where s.tenant_id = p_tenant_id
      and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id, o.location_id, p_location_id, 'view')
    group by o.location_id, si.variant_id
  ),
  last_purchased as (
    select o.location_id, u.variant_id, max(u.doc_date) as last_date
    from (
      select o.location_id, pi.variant_id, p.purchase_date as doc_date
      from public.purchase_items pi
      join public.purchases p on p.id = pi.purchase_id
      left join public.document_origins o on o.tenant_id = p.tenant_id and o.entity_type = 'purchase' and o.entity_id = p.id
      where p.tenant_id = p_tenant_id
        and coalesce(p.status, '') not in ('void', 'cancelled')
        and (p_location_id is null or o.location_id = p_location_id)
        and private.erp_document_scope_allowed(p_tenant_id, o.location_id, p_location_id, 'view')
      group by o.location_id, pi.variant_id, p.purchase_date
      union all
      select g.location_id, gi.variant_id, g.grn_date as doc_date
      from public.grn_items_v484 gi
      join public.goods_received_notes_v484 g on g.id = gi.grn_id
      where g.tenant_id = p_tenant_id
        and g.status = 'approved'
        and (p_location_id is null or g.location_id = p_location_id)
        and private.erp_document_scope_allowed(p_tenant_id, g.location_id, p_location_id, 'view')
      group by g.location_id, gi.variant_id, g.grn_date
    ) u
    join public.document_origins o on o.tenant_id = p_tenant_id and o.location_id = u.location_id
    group by o.location_id, u.variant_id
  ),
  base as (
    select
      loc.location_id,
      loc.location_code,
      loc.location_name,
      pv.id as variant_id,
      p.id as product_id,
      p.name as product_name,
      pv.sku,
      pv.barcode,
      coalesce(b.quantity, 0)::numeric as quantity,
      greatest(coalesce(b.quantity, 0) - coalesce(b.reserved_quantity, 0) - coalesce(b.damaged_quantity, 0) - coalesce(b.quarantine_quantity, 0), 0)::numeric as available,
      coalesce(s.reorder_level, 0)::numeric as reorder_level,
      coalesce(s.max_stock, 0)::numeric as max_stock,
      case when v_can_view_cost then coalesce(b.average_cost, pv.cost_price, 0)::numeric else null end as average_cost,
      case when v_can_view_cost then round(coalesce(b.quantity, 0) * coalesce(b.average_cost, pv.cost_price, 0), 2)::numeric else null end as stock_value,
      coalesce(sd.qty, 0)::numeric as net_sold_qty,
      round(coalesce(sd.qty, 0) / v_days::numeric, 2)::numeric as avg_daily_sales,
      ls.last_date as last_sale_date,
      lp.last_date as last_purchase_date
    from active_locs loc
    cross join public.product_variants pv
    join public.products p on p.id = pv.product_id
    left join public.location_stock_balances b on b.tenant_id = p_tenant_id and b.location_id = loc.location_id and b.variant_id = pv.id
    left join public.location_product_settings s on s.tenant_id = p_tenant_id and s.location_id = loc.location_id and s.variant_id = pv.id
    left join sold sd on sd.location_id = loc.location_id and sd.variant_id = pv.id
    left join last_sold ls on ls.location_id = loc.location_id and ls.variant_id = pv.id
    left join last_purchased lp on lp.location_id = loc.location_id and lp.variant_id = pv.id
    where p.tenant_id = p_tenant_id
      and p.status = 'active'
      and pv.status = 'active'
      and coalesce(s.active, true)
      and (trim(coalesce(p_query, '')) = '' or lower(p.name) like q or lower(coalesce(pv.sku, '')) like q or lower(coalesce(pv.barcode, '')) like q)
  ),
  computed as (
    select
      b.*,
      case
        when b.avg_daily_sales > 0 then round(b.available / b.avg_daily_sales, 1)
        else 999.0
      end as days_cover,
      case
        when b.reorder_level > 0 and b.available <= b.reorder_level then
          case
            when b.max_stock > b.available then b.max_stock - b.available
            else (b.reorder_level * 2) - b.available
          end
        else 0
      end as suggested_reorder,
      case
        when b.available <= 0 then 'out_of_stock'
        when b.reorder_level > 0 and b.available <= b.reorder_level then 'low_stock'
        when b.max_stock > 0 and b.available > b.max_stock then 'overstock'
        when b.net_sold_qty = 0 and b.quantity > 0 and (b.last_sale_date is null or b.last_sale_date < (current_date - 90)) then 'dead_stock'
        else 'healthy'
      end as status,
      'C' as abc_class
    from base b
  )
  select
    c.location_id,
    c.location_code,
    c.location_name,
    c.variant_id,
    c.product_id,
    c.product_name,
    c.sku,
    c.barcode,
    c.quantity,
    c.available,
    c.reorder_level,
    c.max_stock,
    c.average_cost,
    c.stock_value,
    c.net_sold_qty,
    c.avg_daily_sales,
    c.days_cover,
    c.suggested_reorder,
    c.last_sale_date,
    c.last_purchase_date,
    c.status,
    c.abc_class
  from computed c
  order by
    case c.status
      when 'out_of_stock' then 1
      when 'low_stock' then 2
      when 'overstock' then 3
      when 'dead_stock' then 4
      else 5
    end,
    c.stock_value desc nulls last,
    c.product_name
  limit greatest(1, least(coalesce(p_limit, 1000), 5000));
end;
$$;

revoke all on function public.inventory_intelligence_v830(uuid, uuid, integer, text, integer) from public, anon;
grant execute on function public.inventory_intelligence_v830(uuid, uuid, integer, text, integer) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 11. Hardened Action Centre Intelligence (v8.3.0)
-- ----------------------------------------------------------------------------
create or replace function public.erp_intelligence_action_centre_v830(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_engine text default null,
  p_severity text default null,
  p_status text default null,
  p_category text default null,
  p_query text default '',
  p_limit integer default 100,
  p_offset integer default 0
) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v_can_view_cost boolean := false;
  v_total integer;
  v_critical integer;
  v_high integer;
  v_medium integer;
  v_low integer;
  v_unresolved integer;
  v_recently_resolved integer;
  v_by_engine jsonb;
  v_by_status jsonb;
  v_findings jsonb;
  v_cross_insights jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied to tenant %', p_tenant_id using errcode = '42501';
  end if;

  perform private.erp_assert_location_access(p_tenant_id, p_location_id, 'view');

  v_can_view_cost := private.erp_user_is_owner(p_tenant_id) or
                     private.erp_has_permission(p_tenant_id, 'inventory.view_cost') or
                     private.erp_has_permission(p_tenant_id, 'accounting.view') or
                     private.erp_has_permission(p_tenant_id, 'reports.view');

  -- Summary Counts
  select
    count(*),
    count(*) filter (where severity = 'critical'),
    count(*) filter (where severity in ('high', 'urgent')),
    count(*) filter (where severity in ('medium', 'warning')),
    count(*) filter (where severity in ('low', 'info', 'informational', 'opportunity')),
    count(*) filter (where status in ('new', 'new_insight', 'under_review', 'accepted', 'approved', 'in_progress', 'acknowledged')),
    count(*) filter (where status in ('resolved', 'dismissed') and resolved_at >= now() - interval '7 days')
  into
    v_total, v_critical, v_high, v_medium, v_low, v_unresolved, v_recently_resolved
  from public.erp_intelligence_insights
  where tenant_id = p_tenant_id
    and (p_location_id is null or location_id is null or location_id = p_location_id)
    and (location_id is null or private.erp_document_scope_allowed(p_tenant_id, location_id, p_location_id, 'view'));

  -- Aggregation by Engine
  select coalesce(jsonb_object_agg(engine, cnt), '{}'::jsonb)
  into v_by_engine
  from (
    select engine, count(*) as cnt
    from public.erp_intelligence_insights
    where tenant_id = p_tenant_id
      and (p_location_id is null or location_id is null or location_id = p_location_id)
      and (location_id is null or private.erp_document_scope_allowed(p_tenant_id, location_id, p_location_id, 'view'))
    group by engine
  ) sub;

  -- Aggregation by Status
  select coalesce(jsonb_object_agg(status, cnt), '{}'::jsonb)
  into v_by_status
  from (
    select status, count(*) as cnt
    from public.erp_intelligence_insights
    where tenant_id = p_tenant_id
      and (p_location_id is null or location_id is null or location_id = p_location_id)
      and (location_id is null or private.erp_document_scope_allowed(p_tenant_id, location_id, p_location_id, 'view'))
    group by status
  ) sub;

  -- Filtered Findings List
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', f.id,
      'engine', f.engine,
      'category', f.category,
      'finding_key', f.insight_key,
      'fingerprint', f.fingerprint,
      'title', f.title,
      'description', f.description,
      'severity', f.severity,
      'status', f.status,
      'score', f.score,
      'financial_impact', case when v_can_view_cost then f.financial_impact else null end,
      'risk_score', f.risk_score,
      'opportunity_score', f.opportunity_score,
      'location_id', f.location_id,
      'location_name', loc.name,
      'entity_type', f.entity_type,
      'entity_id', f.entity_id,
      'metadata', case when not v_can_view_cost then f.metadata - 'cost_price' - 'cost_total' - 'cogs' else f.metadata end,
      'recommended_actions', f.recommended_actions,
      'first_detected_at', f.created_at,
      'last_detected_at', f.last_seen_at,
      'occurrence_count', f.occurrence_count,
      'assigned_to', f.assigned_to,
      'review_count', f.review_count,
      'last_reviewed_at', f.last_reviewed_at
    ) order by
      case f.severity
        when 'critical' then 1
        when 'high' then 2
        when 'urgent' then 2
        when 'medium' then 3
        when 'warning' then 3
        else 4
      end,
      f.financial_impact desc nulls last,
      f.created_at desc
  ), '[]'::jsonb)
  into v_findings
  from (
    select i.*
    from public.erp_intelligence_insights i
    where i.tenant_id = p_tenant_id
      and (p_location_id is null or i.location_id is null or i.location_id = p_location_id)
      and (i.location_id is null or private.erp_document_scope_allowed(p_tenant_id, i.location_id, p_location_id, 'view'))
      and (p_engine is null or i.engine = p_engine)
      and (p_severity is null or i.severity = p_severity)
      and (
        case
          when p_status is null or p_status = 'unresolved' then
            i.status in ('new', 'new_insight', 'under_review', 'accepted', 'approved', 'in_progress', 'acknowledged')
          when p_status = 'all' then true
          else i.status = p_status
        end
      )
      and (p_category is null or i.category = p_category)
      and (
        p_query = '' or
        i.title ilike '%' || p_query || '%' or
        i.description ilike '%' || p_query || '%'
      )
    order by i.created_at desc
    limit greatest(1, least(coalesce(p_limit, 100), 500))
    offset greatest(0, coalesce(p_offset, 0))
  ) f
  left join public.business_locations loc on loc.id = f.location_id and loc.tenant_id = p_tenant_id;

  -- Cross-Engine Correlated Insights
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'category', grp.category,
      'severity', grp.max_sev,
      'engines', grp.engines,
      'finding_count', grp.finding_count,
      'total_financial_impact', case when v_can_view_cost then grp.total_impact else null end,
      'primary_title', grp.sample_title,
      'root_cause_hint', grp.root_cause_hint
    )
  ), '[]'::jsonb)
  into v_cross_insights
  from (
    select
      category,
      max(severity) as max_sev,
      jsonb_agg(distinct engine) as engines,
      count(*) as finding_count,
      sum(coalesce(financial_impact, 0)) as total_impact,
      max(title) as sample_title,
      case
        when count(distinct engine) >= 3 then 'Multi-domain operational bottleneck detected across inventory, sales and financial workflows.'
        when count(distinct engine) = 2 and bool_or(engine = 'procurement') and bool_or(engine = 'inventory') then 'Supply chain discrepancy: delayed procurement causing downstream stockouts.'
        when count(distinct engine) = 2 and bool_or(engine = 'sales') and bool_or(engine = 'financial') then 'Cash flow risk: declining sales velocity impacting receivables and liquidity.'
        else 'Correlated findings detected within shared domain category.'
      end as root_cause_hint
    from public.erp_intelligence_insights
    where tenant_id = p_tenant_id
      and (p_location_id is null or location_id is null or location_id = p_location_id)
      and (location_id is null or private.erp_document_scope_allowed(p_tenant_id, location_id, p_location_id, 'view'))
      and status in ('new', 'new_insight', 'under_review', 'in_progress', 'acknowledged')
    group by category
    having count(*) > 1
    order by total_impact desc nulls last, finding_count desc
    limit 10
  ) grp;

  return jsonb_build_object(
    'summary', jsonb_build_object(
      'total', coalesce(v_total, 0),
      'critical', coalesce(v_critical, 0),
      'high', coalesce(v_high, 0),
      'medium', coalesce(v_medium, 0),
      'low', coalesce(v_low, 0),
      'unresolved', coalesce(v_unresolved, 0),
      'recently_resolved', coalesce(v_recently_resolved, 0)
    ),
    'by_engine', coalesce(v_by_engine, '{}'::jsonb),
    'by_status', coalesce(v_by_status, '{}'::jsonb),
    'findings', coalesce(v_findings, '[]'::jsonb),
    'cross_domain_insights', coalesce(v_cross_insights, '[]'::jsonb),
    'cost_visible', v_can_view_cost
  );
end;
$$;

revoke all on function public.erp_intelligence_action_centre_v830(uuid, uuid, text, text, text, text, text, integer, integer) from public, anon;
grant execute on function public.erp_intelligence_action_centre_v830(uuid, uuid, text, text, text, text, text, integer, integer) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 12. Register Schema Release #718 (v8.3.12)
-- ----------------------------------------------------------------------------
insert into public.thq_schema_releases(migration_no, schema_version, release_name, notes)
values(
  718,
  'v8.3.12',
  'sec_phase15_multi_tenant_and_location_hardening',
  'Authoritative multi-tenant and location security hardening: enforce location scoping and permissions across operations intelligence, daily detailed accounts, supplier payables, pos device location resolution, and revoke anon access to supplier payments.'
);

notify pgrst, 'reload schema';
