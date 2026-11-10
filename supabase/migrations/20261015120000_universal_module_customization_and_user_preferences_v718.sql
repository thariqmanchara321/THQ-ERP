-- THQ ERP V7.1.8 — Universal Module Customization, Multi-Scope Navigation & User Preferences
-- 1. Canonical application scopes: business_desktop (client), pos_desktop (pos), mobile_erp (client_mobile), pos_mobile (mobile_pos), admin (admin).
-- 2. Extend public.app_menu_nodes_v45 constraint and support for all application scopes.
-- 3. Seed default global menus for client_mobile, mobile_pos, and admin.
-- 4. Authoritative app_menu_tree_v5 and backward-compatible app_menu_tree_v45 with tenant module entitlement filtering.
-- 5. Create public.user_ui_preferences table with RLS and secure get/save RPCs for user personalization.
-- 6. Upgrade Admin menu management RPCs for all application scopes.

begin;

-- ============================================================================
-- 1. CANONICAL APPLICATION SCOPE RESOLVER
-- ============================================================================

create or replace function private.canonical_app_scope(p_scope text)
returns text
language sql immutable
as $$
  select case trim(lower(coalesce(p_scope, '')))
    when 'client' then 'client'
    when 'business_desktop' then 'client'
    when 'pos' then 'pos'
    when 'pos_desktop' then 'pos'
    when 'client_mobile' then 'client_mobile'
    when 'mobile_erp' then 'client_mobile'
    when 'mobile_pos' then 'mobile_pos'
    when 'pos_mobile' then 'mobile_pos'
    when 'admin' then 'admin'
    else null
  end;
$$;

-- ============================================================================
-- 2. EXTEND APP_MENU_NODES_V45 CHECK CONSTRAINTS & ENSURE MODULES
-- ============================================================================

-- 2A. Ensure standard core and operational modules exist in public.modules so FKs succeed
insert into public.modules (key, name, description, category, sort_order, is_active, is_core)
values
  ('dashboard', 'Dashboard', 'Business overview', 'Core', 10, true, true),
  ('inventory', 'Inventory', 'Products, variants, stock ledger and locations', 'Core', 20, true, false),
  ('sales', 'Sales', 'Sales invoices and customer payments', 'Core', 30, true, false),
  ('pos', 'Point of Sale', 'Fast counter checkout', 'Sales', 35, true, false),
  ('purchases', 'Purchases', 'Supplier purchases and payments', 'Core', 40, true, false),
  ('customers', 'Customers', 'Customer master and statements', 'CRM', 50, true, false),
  ('suppliers', 'Suppliers', 'Supplier master and statements', 'CRM', 60, true, false),
  ('expenses', 'Expenses', 'Business expense capture', 'Finance', 70, true, false),
  ('accounting', 'Accounting', 'Operational accounting summaries and ledger', 'Finance', 80, true, false),
  ('reports', 'Reports', 'Business reporting', 'Analytics', 90, true, false),
  ('inventory_reports', 'Inventory Reports', 'Stock valuation, movements and item reconciliation', 'Reports', 91, true, false),
  ('stock_transfers', 'Stock Transfers', 'Branch/warehouse stock transfer and receiving', 'Inventory', 25, true, false),
  ('cashier_shifts', 'Cashier Shifts', 'Opening/closing cash and drawer reconciliation', 'POS', 36, true, false),
  ('terminal_day', 'Terminal Daily', 'Terminal daily register', 'POS', 37, true, false),
  ('returns', 'Returns', 'Sales and purchase returns', 'Operations', 38, true, false),
  ('gst_compliance', 'GST & Compliance', 'GST tax engine and compliance', 'Compliance', 45, true, false),
  ('audit_center', 'Audit Center', 'Audit intelligence and verification', 'Compliance', 46, true, false),
  ('loans', 'Loans & Credit', 'Loans and credit tracking', 'Finance', 86, true, false),
  ('payments', 'Payments', 'Receivables and payables center', 'Finance', 95, true, false),
  ('approvals', 'Approvals', 'Configurable approval workflows', 'Administration', 97, true, false),
  ('notifications', 'Notifications', 'Business alerts and notifications', 'Core', 95, true, false),
  ('support', 'Support', 'Support tickets and diagnostics', 'Administration', 99, true, false),
  ('settings', 'Business Settings', 'Tenant business configuration', 'Core', 900, true, false),
  ('restaurant', 'Restaurant', 'Restaurant and tables extension', 'Restaurant', 200, true, false),
  ('restaurant_orders', 'Restaurant Orders', 'Dine-in, takeaway and delivery order workflows', 'Restaurant', 210, true, false),
  ('transport_service', 'Transport Service', 'Transport and vehicles', 'Service', 520, true, false),
  ('vehicle_logistics', 'Vehicle Logistics', 'Vehicle fleet and stock movement', 'Inventory', 515, true, false),
  ('logistics_operations', 'Logistics Operations', 'Pickup and delivery operations', 'Operations', 514, true, false),
  ('aggregate_yard', 'Material Yard', 'Bulk material and quarry yard', 'Operations', 18, true, false),
  ('staff', 'Staff', 'Staff, attendance, advances and payroll', 'Operations', 65, true, false),
  ('attendance', 'Attendance', 'Staff attendance tracking', 'Operations', 66, true, false),
  ('locations', 'Locations / Branches', 'Child stores, branches and reporting locations', 'Platform', 130, true, false),
  ('production', 'Production', 'Recipes/BOM and finished goods', 'Manufacturing', 500, true, false),
  ('logs', 'Logs & Issues', 'Application errors and audit activity', 'Platform', 910, true, false),
  ('invoice_templates', 'Invoice Templates', 'Business invoice template assignment', 'Platform', 920, true, false),
  ('users', 'Team & Access', 'Business users and store scope', 'Administration', 905, true, false),
  ('tasks', 'Tasks', 'Internal tasks and follow-ups', 'CRM', 96, true, false),
  ('barcode', 'Barcode', 'Barcode scanning and labels', 'Operations', 100, true, false),
  ('warranty', 'Warranty', 'Warranty tracking', 'Operations', 110, true, false),
  ('vehicle_compatibility', 'Vehicle Compatibility', 'Vehicle-to-part compatibility', 'Automotive', 120, true, false),
  ('workshop', 'Workshop / Garage', 'Vehicles and job cards', 'Workshop', 300, true, false),
  ('healthcare', 'Clinic / Hospital', 'Patient and clinical workflows', 'Healthcare', 400, true, false),
  ('pharmacy', 'Pharmacy', 'Medicine and batch inventory', 'Healthcare', 410, true, false),
  ('lab', 'Diagnostic Lab', 'Lab tests and results', 'Healthcare', 420, true, false),
  ('backup', 'Backup & Export', 'Portable tenant backup', 'Administration', 98, true, false),
  ('division_overview', 'Division Overview', 'Merged business summary', 'Management', 12, true, false),
  ('operations_intelligence', 'Operations Intelligence', 'Operational intelligence', 'Operations', 14, true, false),
  ('pricing', 'Pricing', 'Price lists and customer pricing', 'Commerce', 18, true, false),
  ('sales_details', 'Sales Details', 'Sales history and invoice detail', 'Operations', 31, true, false),
  ('purchase_details', 'Purchase Details', 'Purchase requests and orders', 'Operations', 41, true, false),
  ('bulk_import', 'Bulk Import', 'Bulk data import', 'Operations', 105, true, false)
on conflict (key) do nothing;

-- 2B. Extend app_key check constraint for all 5 canonical application scopes
alter table public.app_menu_nodes_v45
  drop constraint if exists app_menu_nodes_v45_app_key_check;

alter table public.app_menu_nodes_v45
  add constraint app_menu_nodes_v45_app_key_check
  check (app_key = any (array[
    'client'::text,
    'pos'::text,
    'admin'::text,
    'client_mobile'::text,
    'mobile_pos'::text,
    'business_desktop'::text,
    'pos_desktop'::text,
    'mobile_erp'::text,
    'pos_mobile'::text
  ]));

-- 2C. Update module_key check constraint
alter table public.app_menu_nodes_v45
  drop constraint if exists app_menu_nodes_v45_check;

alter table public.app_menu_nodes_v45
  add constraint app_menu_nodes_v45_check
  check (
    (node_type = 'group' and module_key is null)
    or
    (node_type = 'module')
  );

-- ============================================================================
-- 3. SEED DEFAULT GLOBAL MENUS (CLIENT_MOBILE, MOBILE_POS, ADMIN)
-- ============================================================================

-- 3A. Mobile ERP (client_mobile) Groups
insert into public.app_menu_nodes_v45(tenant_id, app_key, node_key, node_type, label, icon_key, sort_order)
values
  (null, 'client_mobile', 'overview', 'group', 'Overview', 'dashboard', 10),
  (null, 'client_mobile', 'sales_ops', 'group', 'Sales & Orders', 'sales', 20),
  (null, 'client_mobile', 'procurement_stock', 'group', 'Procurement & Stock', 'inventory', 30),
  (null, 'client_mobile', 'materials_fleet', 'group', 'Material Yard & Fleet', 'aggregate_yard', 40),
  (null, 'client_mobile', 'finance_ledger', 'group', 'Finance & Accounts', 'finance', 50),
  (null, 'client_mobile', 'people_crm', 'group', 'People & CRM', 'customers', 60),
  (null, 'client_mobile', 'oversight', 'group', 'Oversight & Settings', 'settings', 70)
on conflict do nothing;

-- 3B. Mobile ERP (client_mobile) Module Nodes
insert into public.app_menu_nodes_v45(tenant_id, app_key, node_key, node_type, module_key, parent_id, label, icon_key, sort_order)
select null, 'client_mobile', x.node_key, 'module', x.module_key, p.id, x.label, x.icon_key, x.sort_order
from (values
  ('dashboard', 'dashboard', 'Dashboard', 'dashboard', 10, 'overview'),
  ('sales', 'sales', 'Sales Register', 'sales', 10, 'sales_ops'),
  ('returns', 'returns', 'Sales Returns', 'returns', 20, 'sales_ops'),
  ('purchases', 'purchases', 'Purchase Register', 'purchases', 10, 'procurement_stock'),
  ('inventory', 'inventory', 'Stock Catalog', 'inventory', 20, 'procurement_stock'),
  ('stock_transfers', 'stock_transfers', 'Stock Transfers', 'stock_transfers', 30, 'procurement_stock'),
  ('inventory_reports', 'inventory_reports', 'Inventory Reports', 'inventory_reports', 40, 'procurement_stock'),
  ('aggregate_yard', 'aggregate_yard', 'Material Yard & Quarry', 'aggregate_yard', 10, 'materials_fleet'),
  ('transport_service', 'transport_service', 'Transport & Fleet', 'transport_service', 20, 'materials_fleet'),
  ('logistics_operations', 'logistics_operations', 'Logistics Operations', 'logistics_operations', 30, 'materials_fleet'),
  ('vehicle_logistics', 'vehicle_logistics', 'Vehicle Stock Movement', 'vehicle_logistics', 40, 'materials_fleet'),
  ('accounting', 'accounting', 'Accounting & Ledgers', 'accounting', 10, 'finance_ledger'),
  ('payments', 'payments', 'Party Settlements', 'payments', 20, 'finance_ledger'),
  ('expenses', 'expenses', 'Expenses', 'expenses', 30, 'finance_ledger'),
  ('gst_compliance', 'gst_compliance', 'GST Compliance', 'gst_compliance', 40, 'finance_ledger'),
  ('loans', 'loans', 'Loans & Financing', 'loans', 50, 'finance_ledger'),
  ('customers', 'customers', 'Customers Master', 'customers', 10, 'people_crm'),
  ('suppliers', 'suppliers', 'Suppliers Master', 'suppliers', 20, 'people_crm'),
  ('staff', 'staff', 'Staff Directory', 'staff', 30, 'people_crm'),
  ('attendance', 'attendance', 'Staff Attendance', 'attendance', 40, 'people_crm'),
  ('reports', 'reports', 'Reports Center', 'reports', 10, 'oversight'),
  ('audit_center', 'audit_center', 'Audit Intelligence', 'audit_center', 20, 'oversight'),
  ('approvals', 'approvals', 'Approvals', 'approvals', 30, 'oversight'),
  ('notifications', 'notifications', 'Notifications', 'notifications', 40, 'oversight'),
  ('support', 'support', 'Support & Help', 'support', 50, 'oversight'),
  ('settings', 'settings', 'Business Settings', 'settings', 60, 'oversight')
) as x(node_key, module_key, label, icon_key, sort_order, parent_key)
join public.app_menu_nodes_v45 p on p.tenant_id is null and p.app_key = 'client_mobile' and p.node_key = x.parent_key
on conflict do nothing;

-- 3C. Mobile POS (mobile_pos) Groups
insert into public.app_menu_nodes_v45(tenant_id, app_key, node_key, node_type, label, icon_key, sort_order)
values
  (null, 'mobile_pos', 'checkout', 'group', 'Checkout', 'pos', 10),
  (null, 'mobile_pos', 'shift_ops', 'group', 'Shifts & Offline', 'terminal', 20),
  (null, 'mobile_pos', 'masters', 'group', 'Catalog & Orders', 'inventory', 30),
  (null, 'mobile_pos', 'management', 'group', 'Management', 'settings', 40)
on conflict do nothing;

-- 3D. Mobile POS (mobile_pos) Module Nodes
insert into public.app_menu_nodes_v45(tenant_id, app_key, node_key, node_type, module_key, parent_id, label, icon_key, sort_order)
select null, 'mobile_pos', x.node_key, 'module', x.module_key, p.id, x.label, x.icon_key, x.sort_order
from (values
  ('sales', 'pos', 'Sell / Checkout', 'pos', 10, 'checkout'),
  ('returns', 'returns', 'Counter Returns', 'returns', 20, 'checkout'),
  ('restaurant', 'restaurant', 'Restaurant / KOT', 'restaurant', 30, 'checkout'),
  ('cashier_shifts', 'cashier_shifts', 'Cashier Shift', 'shift', 10, 'shift_ops'),
  ('offline_sync', 'sales', 'Offline Sync Queue', 'sync', 20, 'shift_ops'),
  ('inventory', 'inventory', 'Products & Stock', 'inventory', 10, 'masters'),
  ('customers', 'customers', 'Customers', 'customers', 20, 'masters'),
  ('suppliers', 'suppliers', 'Suppliers', 'suppliers', 30, 'masters'),
  ('purchases', 'purchases', 'Purchases', 'purchases', 40, 'masters'),
  ('expenses', 'expenses', 'Quick Expenses', 'expenses', 50, 'masters'),
  ('reports', 'reports', 'Daily POS Reports', 'reports', 10, 'management'),
  ('notifications', 'notifications', 'Notifications', 'notifications', 20, 'management'),
  ('support', 'support', 'Diagnostics & Support', 'support', 30, 'management'),
  ('settings', 'settings', 'Terminal Settings', 'settings', 40, 'management')
) as x(node_key, module_key, label, icon_key, sort_order, parent_key)
join public.app_menu_nodes_v45 p on p.tenant_id is null and p.app_key = 'mobile_pos' and p.node_key = x.parent_key
on conflict do nothing;

-- 3E. Admin Panel (admin) Groups & Nodes
insert into public.app_menu_nodes_v45(tenant_id, app_key, node_key, node_type, label, icon_key, sort_order)
values
  (null, 'admin', 'governance', 'group', 'Platform Governance', 'settings', 10),
  (null, 'admin', 'catalogue', 'group', 'Module & Layout Control', 'extension', 20),
  (null, 'admin', 'monetization', 'group', 'Commercial & Audit', 'finance', 30)
on conflict do nothing;

insert into public.app_menu_nodes_v45(tenant_id, app_key, node_key, node_type, module_key, parent_id, label, icon_key, sort_order)
select null, 'admin', x.node_key, 'module', x.module_key, p.id, x.label, x.icon_key, x.sort_order
from (values
  ('overview', 'dashboard', 'Overview', 'dashboard', 10, 'governance'),
  ('businesses', 'settings', 'Businesses', 'store', 20, 'governance'),
  ('modules', 'settings', 'Modules Catalogue', 'extension', 10, 'catalogue'),
  ('menu', 'settings', 'Menu Builder', 'account_tree', 20, 'catalogue'),
  ('design', 'settings', 'Design Studio', 'palette', 30, 'catalogue'),
  ('subscriptions', 'accounting', 'Subscriptions', 'payments', 10, 'monetization'),
  ('transactions', 'reports', 'Transaction Control', 'manage_search', 20, 'monetization'),
  ('settings', 'settings', 'Platform Settings', 'tune', 30, 'monetization'),
  ('support', 'support', 'Support & Tickets', 'support', 40, 'monetization')
) as x(node_key, module_key, label, icon_key, sort_order, parent_key)
join public.app_menu_nodes_v45 p on p.tenant_id is null and p.app_key = 'admin' and p.node_key = x.parent_key
on conflict do nothing;

-- ============================================================================
-- 4. AUTHORITATIVE APP MENU RESOLVER (V5 & UPGRADED V45)
-- ============================================================================

create or replace function public.app_menu_tree_v5(p_tenant_id uuid, p_app_key text)
returns table(
  id uuid,
  node_key text,
  node_type text,
  module_key text,
  parent_id uuid,
  label text,
  icon_key text,
  sort_order integer,
  enabled boolean,
  collapsed_by_default boolean,
  metadata jsonb
)
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_canonical text;
  v_use_tenant boolean;
begin
  v_canonical := private.canonical_app_scope(p_app_key);
  if v_canonical is null then
    raise exception 'Invalid app scope or key: %', p_app_key;
  end if;

  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied for tenant %', p_tenant_id;
  end if;

  select exists(
    select 1 from public.app_menu_nodes_v45 n
    where n.tenant_id = p_tenant_id and n.app_key = v_canonical
  ) into v_use_tenant;

  return query
  select
    n.id,
    n.node_key,
    n.node_type,
    n.module_key,
    n.parent_id,
    n.label,
    n.icon_key,
    n.sort_order,
    n.enabled,
    n.collapsed_by_default,
    n.metadata
  from public.app_menu_nodes_v45 n
  where n.app_key = v_canonical
    and n.enabled
    and ((v_use_tenant and n.tenant_id = p_tenant_id) or (not v_use_tenant and n.tenant_id is null))
    -- Filter out module nodes if that module is disabled for this tenant
    and (
      n.node_type = 'group'
      or n.module_key is null
      or exists (
        select 1 from public.tenant_modules tm
        where tm.tenant_id = p_tenant_id
          and (
            tm.module_key = n.module_key
            or (n.module_key = 'inventory_reports' and tm.module_key in ('reports', 'inventory'))
          )
          and tm.enabled = true
      )
    )
  order by n.sort_order, n.label;
end $$;

grant execute on function public.app_menu_tree_v5(uuid, text) to authenticated;

-- Upgrade legacy app_menu_tree_v45 to delegate safely to canonical scopes without breaking legacy callers
create or replace function public.app_menu_tree_v45(p_tenant_id uuid, p_app_key text)
returns table(
  id uuid,
  node_key text,
  node_type text,
  module_key text,
  parent_id uuid,
  label text,
  icon_key text,
  sort_order integer,
  enabled boolean,
  collapsed_by_default boolean,
  metadata jsonb
)
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
begin
  return query select * from public.app_menu_tree_v5(p_tenant_id, p_app_key);
end $$;

grant execute on function public.app_menu_tree_v45(uuid, text) to authenticated;

-- ============================================================================
-- 5. USER UI PREFERENCES (PERSONALIZATION)
-- ============================================================================

create table if not exists public.user_ui_preferences (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  app_scope text not null,
  favorites text[] not null default array[]::text[],
  hidden_nodes text[] not null default array[]::text[],
  sort_order jsonb not null default '{}'::jsonb,
  quick_actions text[] not null default array[]::text[],
  table_density text not null default 'compact',
  default_landing_module text,
  dashboard_widgets jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ux_user_ui_preferences unique(tenant_id, user_id, app_scope)
);

create index if not exists idx_user_ui_preferences_lookup
  on public.user_ui_preferences(tenant_id, user_id, app_scope);

alter table public.user_ui_preferences enable row level security;

drop policy if exists user_ui_preferences_select on public.user_ui_preferences;
create policy user_ui_preferences_select on public.user_ui_preferences
  for select
  using (
    user_id = auth.uid() and private.erp_user_has_tenant_access(tenant_id)
  );

drop policy if exists user_ui_preferences_insert on public.user_ui_preferences;
create policy user_ui_preferences_insert on public.user_ui_preferences
  for insert
  with check (
    user_id = auth.uid() and private.erp_user_has_tenant_access(tenant_id)
  );

drop policy if exists user_ui_preferences_update on public.user_ui_preferences;
create policy user_ui_preferences_update on public.user_ui_preferences
  for update
  using (
    user_id = auth.uid() and private.erp_user_has_tenant_access(tenant_id)
  )
  with check (
    user_id = auth.uid() and private.erp_user_has_tenant_access(tenant_id)
  );

drop policy if exists user_ui_preferences_delete on public.user_ui_preferences;
create policy user_ui_preferences_delete on public.user_ui_preferences
  for delete
  using (
    user_id = auth.uid() and private.erp_user_has_tenant_access(tenant_id)
  );

-- RPC to get user preferences for an application scope
create or replace function public.user_ui_preferences_get(p_tenant_id uuid, p_app_scope text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_canonical text;
  v_row public.user_ui_preferences%rowtype;
begin
  v_canonical := private.canonical_app_scope(p_app_scope);
  if v_canonical is null then
    raise exception 'Invalid app scope: %', p_app_scope;
  end if;

  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied for tenant %', p_tenant_id;
  end if;

  select * into v_row from public.user_ui_preferences
  where tenant_id = p_tenant_id and user_id = auth.uid() and app_scope = v_canonical;

  if not found then
    return jsonb_build_object(
      'app_scope', v_canonical,
      'favorites', array[]::text[],
      'hidden_nodes', array[]::text[],
      'sort_order', '{}'::jsonb,
      'quick_actions', array[]::text[],
      'table_density', 'compact',
      'default_landing_module', null,
      'dashboard_widgets', '[]'::jsonb,
      'is_default', true
    );
  end if;

  return jsonb_build_object(
    'app_scope', v_row.app_scope,
    'favorites', v_row.favorites,
    'hidden_nodes', v_row.hidden_nodes,
    'sort_order', v_row.sort_order,
    'quick_actions', v_row.quick_actions,
    'table_density', v_row.table_density,
    'default_landing_module', v_row.default_landing_module,
    'dashboard_widgets', v_row.dashboard_widgets,
    'is_default', false,
    'updated_at', v_row.updated_at
  );
end $$;

grant execute on function public.user_ui_preferences_get(uuid, text) to authenticated;

-- RPC to save user preferences for an application scope
create or replace function public.user_ui_preferences_save(
  p_tenant_id uuid,
  p_app_scope text,
  p_preferences jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_canonical text;
  v_favorites text[];
  v_hidden_nodes text[];
  v_sort_order jsonb;
  v_quick_actions text[];
  v_table_density text;
  v_landing text;
  v_widgets jsonb;
  v_row public.user_ui_preferences%rowtype;
begin
  v_canonical := private.canonical_app_scope(p_app_scope);
  if v_canonical is null then
    raise exception 'Invalid app scope: %', p_app_scope;
  end if;

  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied for tenant %', p_tenant_id;
  end if;

  select coalesce(array_agg(x::text), array[]::text[]) into v_favorites
  from jsonb_array_elements_text(coalesce(p_preferences->'favorites', '[]'::jsonb)) x;

  select coalesce(array_agg(x::text), array[]::text[]) into v_hidden_nodes
  from jsonb_array_elements_text(coalesce(p_preferences->'hidden_nodes', '[]'::jsonb)) x;

  select coalesce(array_agg(x::text), array[]::text[]) into v_quick_actions
  from jsonb_array_elements_text(coalesce(p_preferences->'quick_actions', '[]'::jsonb)) x;

  v_sort_order := coalesce(p_preferences->'sort_order', '{}'::jsonb);
  v_table_density := coalesce(nullif(p_preferences->>'table_density', ''), 'compact');
  v_landing := nullif(p_preferences->>'default_landing_module', '');
  v_widgets := coalesce(p_preferences->'dashboard_widgets', '[]'::jsonb);

  insert into public.user_ui_preferences(
    tenant_id, user_id, app_scope, favorites, hidden_nodes,
    sort_order, quick_actions, table_density, default_landing_module,
    dashboard_widgets, updated_at
  )
  values (
    p_tenant_id, auth.uid(), v_canonical, v_favorites, v_hidden_nodes,
    v_sort_order, v_quick_actions, v_table_density, v_landing,
    v_widgets, now()
  )
  on conflict (tenant_id, user_id, app_scope) do update set
    favorites = excluded.favorites,
    hidden_nodes = excluded.hidden_nodes,
    sort_order = excluded.sort_order,
    quick_actions = excluded.quick_actions,
    table_density = excluded.table_density,
    default_landing_module = excluded.default_landing_module,
    dashboard_widgets = excluded.dashboard_widgets,
    updated_at = now()
  returning * into v_row;

  return jsonb_build_object(
    'app_scope', v_row.app_scope,
    'favorites', v_row.favorites,
    'hidden_nodes', v_row.hidden_nodes,
    'sort_order', v_row.sort_order,
    'quick_actions', v_row.quick_actions,
    'table_density', v_row.table_density,
    'default_landing_module', v_row.default_landing_module,
    'dashboard_widgets', v_row.dashboard_widgets,
    'is_default', false,
    'updated_at', v_row.updated_at
  );
end $$;

grant execute on function public.user_ui_preferences_save(uuid, text, jsonb) to authenticated;

-- ============================================================================
-- 6. UPGRADE ADMIN MENU MANAGEMENT RPCS FOR ALL APPLICATION SCOPES
-- ============================================================================

create or replace function public.platform_menu_nodes_v45_list(p_tenant_id uuid, p_app_key text)
returns setof public.app_menu_nodes_v45
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_canonical text;
begin
  if not private.platform_v2_is_admin() then
    raise exception 'Platform admin required';
  end if;
  v_canonical := private.canonical_app_scope(p_app_key);
  if v_canonical is null then
    raise exception 'Invalid app key: %', p_app_key;
  end if;

  return query select * from public.app_menu_nodes_v45 n
  where n.app_key = v_canonical
    and ((p_tenant_id is null and n.tenant_id is null) or n.tenant_id = p_tenant_id)
  order by n.parent_id nulls first, n.sort_order, n.label;
end $$;

create or replace function public.platform_menu_copy_default_v45(p_tenant_id uuid, p_app_key text)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_canonical text;
  r record;
  v_map jsonb := '{}'::jsonb;
  v_parent uuid;
  v_new uuid;
begin
  if not private.platform_v2_is_admin() then
    raise exception 'Platform admin required';
  end if;
  v_canonical := private.canonical_app_scope(p_app_key);
  if v_canonical is null then
    raise exception 'Invalid app key: %', p_app_key;
  end if;

  delete from public.app_menu_nodes_v45 where tenant_id = p_tenant_id and app_key = v_canonical;

  for r in
    with recursive tree as (
      select n.*, 0 as depth from public.app_menu_nodes_v45 n
      where n.tenant_id is null and n.app_key = v_canonical and n.parent_id is null
      union all
      select c.*, t.depth + 1 from public.app_menu_nodes_v45 c
      join tree t on c.parent_id = t.id
      where c.tenant_id is null and c.app_key = v_canonical
    )
    select * from tree order by depth, sort_order, label
  loop
    v_parent := case when r.parent_id is null then null else nullif(v_map->>r.parent_id::text, '')::uuid end;
    insert into public.app_menu_nodes_v45(
      tenant_id, app_key, node_key, node_type, module_key, parent_id,
      label, icon_key, sort_order, enabled, collapsed_by_default, metadata, updated_by
    )
    values (
      p_tenant_id, v_canonical, r.node_key, r.node_type, r.module_key, v_parent,
      r.label, r.icon_key, r.sort_order, r.enabled, r.collapsed_by_default, r.metadata, auth.uid()
    )
    returning id into v_new;
    v_map := jsonb_set(v_map, array[r.id::text], to_jsonb(v_new::text), true);
  end loop;

  perform private.platform_audit_write('menu.copy_default', 'tenant', p_tenant_id::text, p_tenant_id, jsonb_build_object('app_key', v_canonical));
end $$;

create or replace function public.platform_menu_node_save_v45(
  p_id uuid,
  p_tenant_id uuid,
  p_app_key text,
  p_node_key text,
  p_node_type text,
  p_module_key text,
  p_parent_id uuid,
  p_label text,
  p_icon_key text,
  p_sort_order integer,
  p_enabled boolean,
  p_collapsed_by_default boolean,
  p_metadata jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_canonical text;
  v_id uuid := coalesce(p_id, gen_random_uuid());
begin
  if not private.platform_v2_has_role('technical_admin') and not private.platform_v2_has_role('super_admin') then
    raise exception 'Super or technical admin required';
  end if;

  v_canonical := private.canonical_app_scope(p_app_key);
  if v_canonical is null then
    raise exception 'Invalid app key: %', p_app_key;
  end if;

  if p_node_type not in ('group', 'module') then
    raise exception 'Invalid node type';
  end if;

  if trim(coalesce(p_label, '')) = '' or trim(coalesce(p_node_key, '')) = '' then
    raise exception 'Key and label required';
  end if;

  if p_node_type = 'module' and p_module_key is not null and not exists(select 1 from public.modules where key = p_module_key) then
    raise exception 'Module not found: %', p_module_key;
  end if;

  if p_parent_id is not null then
    if p_parent_id = v_id then
      raise exception 'A menu node cannot be its own parent';
    end if;
    if not exists(
      select 1 from public.app_menu_nodes_v45 x
      where x.id = p_parent_id and x.app_key = v_canonical and x.tenant_id is not distinct from p_tenant_id
    ) then
      raise exception 'Parent menu node not found';
    end if;
    if exists(
      with recursive ancestors as (
        select x.id, x.parent_id from public.app_menu_nodes_v45 x where x.id = p_parent_id
        union all
        select x.id, x.parent_id from public.app_menu_nodes_v45 x join ancestors a on x.id = a.parent_id
      ) select 1 from ancestors where id = v_id
    ) then
      raise exception 'Menu nesting would create a cycle';
    end if;
  end if;

  insert into public.app_menu_nodes_v45(
    id, tenant_id, app_key, node_key, node_type, module_key, parent_id,
    label, icon_key, sort_order, enabled, collapsed_by_default, metadata, updated_by
  )
  values (
    v_id, p_tenant_id, v_canonical, trim(p_node_key), p_node_type,
    case when p_node_type = 'module' then p_module_key else null end,
    p_parent_id, trim(p_label), nullif(trim(coalesce(p_icon_key, '')), ''),
    coalesce(p_sort_order, 100), coalesce(p_enabled, true),
    coalesce(p_collapsed_by_default, false), coalesce(p_metadata, '{}'::jsonb),
    auth.uid()
  )
  on conflict (id) do update set
    node_key = excluded.node_key,
    node_type = excluded.node_type,
    module_key = excluded.module_key,
    parent_id = excluded.parent_id,
    label = excluded.label,
    icon_key = excluded.icon_key,
    sort_order = excluded.sort_order,
    enabled = excluded.enabled,
    collapsed_by_default = excluded.collapsed_by_default,
    metadata = excluded.metadata,
    updated_by = auth.uid(),
    updated_at = now();

  perform private.platform_audit_write('menu.node.save', 'app_menu_node', v_id::text, p_tenant_id, jsonb_build_object('app_key', v_canonical, 'label', p_label, 'module_key', p_module_key));
  return v_id;
end $$;

commit;
