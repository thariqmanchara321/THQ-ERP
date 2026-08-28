-- FLEXI ERP PLATFORM V2 CORE
-- Additive platform metadata, templates, subscriptions, settings and audit foundation.
-- Requires migration 001 helpers and the existing multi-tenant foundation.

create schema if not exists private;

alter table public.modules add column if not exists is_active boolean not null default true;
alter table public.modules add column if not exists is_beta boolean not null default false;
alter table public.modules add column if not exists requires_configuration boolean not null default false;
alter table public.modules add column if not exists minimum_plan_key text;

create table if not exists public.module_dependencies (
  module_key text not null references public.modules(key) on delete cascade,
  depends_on_module_key text not null references public.modules(key) on delete restrict,
  primary key (module_key, depends_on_module_key),
  check (module_key <> depends_on_module_key)
);

create table if not exists public.module_business_types (
  module_key text not null references public.modules(key) on delete cascade,
  business_type text not null,
  primary key (module_key, business_type)
);

create table if not exists public.business_templates (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  business_type text not null,
  description text,
  is_active boolean not null default true,
  is_system boolean not null default false,
  sort_order integer not null default 100,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.business_template_modules (
  template_id uuid not null references public.business_templates(id) on delete cascade,
  module_key text not null references public.modules(key) on delete cascade,
  primary key (template_id, module_key)
);

create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  description text,
  monthly_price numeric(18,2) not null default 0 check (monthly_price >= 0),
  yearly_price numeric(18,2) not null default 0 check (yearly_price >= 0),
  currency_code text not null default 'INR',
  is_active boolean not null default true,
  sort_order integer not null default 100,
  limits jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.subscription_plan_modules (
  plan_id uuid not null references public.subscription_plans(id) on delete cascade,
  module_key text not null references public.modules(key) on delete cascade,
  primary key (plan_id, module_key)
);

create table if not exists public.tenant_subscriptions (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  plan_id uuid not null references public.subscription_plans(id),
  status text not null default 'trial' check (status in ('trial','active','past_due','suspended','cancelled')),
  billing_cycle text not null default 'monthly' check (billing_cycle in ('monthly','yearly','custom')),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  trial_ends_at timestamptz,
  limit_overrides jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tenant_settings_v2 (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  settings jsonb not null default '{}'::jsonb,
  updated_by uuid,
  updated_at timestamptz not null default now()
);

create table if not exists public.platform_settings (
  key text primary key,
  value jsonb not null,
  description text,
  updated_by uuid,
  updated_at timestamptz not null default now()
);

create table if not exists private.platform_admin_role_assignments (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role_key text not null check (role_key in ('super_admin','support_admin','billing_admin','sales_admin','technical_admin','auditor')),
  active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists private.platform_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid,
  tenant_id uuid references public.tenants(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_platform_audit_created on private.platform_audit_log(created_at desc);
create index if not exists idx_platform_audit_tenant on private.platform_audit_log(tenant_id, created_at desc);

alter table public.module_dependencies enable row level security;
alter table public.module_business_types enable row level security;
alter table public.business_templates enable row level security;
alter table public.business_template_modules enable row level security;
alter table public.subscription_plans enable row level security;
alter table public.subscription_plan_modules enable row level security;
alter table public.tenant_subscriptions enable row level security;
alter table public.tenant_settings_v2 enable row level security;
alter table public.platform_settings enable row level security;

-- Direct writes are intentionally blocked. Platform changes go through protected RPCs.
revoke insert, update, delete on public.module_dependencies from authenticated;
revoke insert, update, delete on public.module_business_types from authenticated;
revoke insert, update, delete on public.business_templates from authenticated;
revoke insert, update, delete on public.business_template_modules from authenticated;
revoke insert, update, delete on public.subscription_plans from authenticated;
revoke insert, update, delete on public.subscription_plan_modules from authenticated;
revoke insert, update, delete on public.tenant_subscriptions from authenticated;
revoke insert, update, delete on public.tenant_settings_v2 from authenticated;
revoke insert, update, delete on public.platform_settings from authenticated;

create or replace function private.platform_v2_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select coalesce(public.current_user_is_platform_admin(), false)
      or exists (
        select 1 from private.platform_admin_role_assignments a
        where a.user_id = auth.uid() and a.active
      );
$$;

create or replace function private.platform_v2_has_role(p_role_key text)
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select coalesce(public.current_user_is_platform_admin(), false)
      or exists (
        select 1 from private.platform_admin_role_assignments a
        where a.user_id = auth.uid()
          and a.active
          and (a.role_key = 'super_admin' or a.role_key = p_role_key)
      );
$$;

create or replace function private.platform_audit_write(
  p_action text,
  p_entity_type text,
  p_entity_id text default null,
  p_tenant_id uuid default null,
  p_details jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  insert into private.platform_audit_log(actor_user_id, tenant_id, action, entity_type, entity_id, details)
  values(auth.uid(), p_tenant_id, p_action, p_entity_type, p_entity_id, coalesce(p_details, '{}'::jsonb));
end $$;

create or replace function private.erp_module_available(p_tenant_id uuid, p_module_key text)
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select private.erp_module_enabled(p_tenant_id, p_module_key)
     and coalesce((select m.is_active from public.modules m where m.key=p_module_key), false)
     and (
       not exists (select 1 from public.tenant_subscriptions ts where ts.tenant_id=p_tenant_id)
       or exists (
         select 1
         from public.tenant_subscriptions ts
         join public.subscription_plan_modules spm on spm.plan_id=ts.plan_id
         where ts.tenant_id=p_tenant_id
           and ts.status in ('trial','active','past_due')
           and spm.module_key=p_module_key
       )
     );
$$;

revoke all on function private.platform_v2_is_admin() from public;
revoke all on function private.platform_v2_has_role(text) from public;
revoke all on function private.platform_audit_write(text,text,text,uuid,jsonb) from public;
revoke all on function private.erp_module_available(uuid,text) from public;
