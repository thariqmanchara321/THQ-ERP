
begin;

-- THQ ERP v6.1.4 Build 7 — Final Stabilization
-- Security/performance hardening only. No GST/accounting/transaction writer logic changes.

-- Pin search_path on the five functions reported by the database advisor.
alter function public.reports_catalog_v500()
  set search_path = public, private, extensions, pg_temp;

alter function private.gst_v520_account_family(text)
  set search_path = public, private, extensions, pg_temp;

alter function private.gst_append_nonnull_line_v520(jsonb, jsonb)
  set search_path = public, private, extensions, pg_temp;

alter function private.loan_v490_periods_per_year(text)
  set search_path = public, private, extensions, pg_temp;

alter function private.loan_v490_due_date(date, text, integer)
  set search_path = public, private, extensions, pg_temp;

-- citext is relocatable. Keep extensions out of the API-facing public schema.
do $$
begin
  if exists (
    select 1
    from pg_extension e
    join pg_namespace n on n.oid = e.extnamespace
    where e.extname = 'citext'
      and n.nspname = 'public'
  ) then
    alter extension citext set schema extensions;
  end if;
end
$$;

-- SECURITY DEFINER functions are application RPCs for signed-in users.
-- Anonymous activation/login are handled by Edge Functions using service_role.
-- Revoke inherited/public execution, then explicitly preserve authenticated
-- application and service-role execution.
do $$
declare
  r record;
  v_signature text;
begin
  for r in
    select
      n.nspname as schema_name,
      p.proname as function_name,
      pg_get_function_identity_arguments(p.oid) as identity_args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and p.prokind = 'f'
  loop
    v_signature := format(
      '%I.%I(%s)',
      r.schema_name,
      r.function_name,
      r.identity_args
    );

    execute 'revoke execute on function ' || v_signature || ' from anon, public';
    execute 'grant execute on function ' || v_signature || ' to authenticated, service_role';
  end loop;
end
$$;

-- Prevent the same anonymous/PUBLIC grant pattern on future public functions
-- created by the migration owner. Signed-in app users and service_role remain
-- explicit API principals.
alter default privileges in schema public
  revoke execute on functions from public, anon;

alter default privileges in schema public
  grant execute on functions to authenticated, service_role;

-- Targeted FK/join indexes identified from live usage. Avoid mass-indexing
-- advisor INFO findings that already have useful tenant-first composites.
create index if not exists idx_journal_lines_journal_entry_v614
  on public.journal_lines (journal_entry_id);

create index if not exists idx_sales_returns_tenant_sale_v614
  on public.sales_returns (tenant_id, sale_id, created_at desc);

create index if not exists idx_sales_return_items_return_v614
  on public.sales_return_items (sales_return_id);

create index if not exists idx_sales_return_items_sale_item_v614
  on public.sales_return_items (sale_item_id);

create index if not exists idx_stock_transfer_items_transfer_v614
  on public.stock_transfer_items (transfer_id);

create index if not exists idx_stock_transfer_items_variant_v614
  on public.stock_transfer_items (variant_id);

insert into public.platform_app_releases(
  id,app_key,platform,version,build_number,status,minimum_supported,mandatory,
  release_notes,download_url,released_at
)
values
(
  gen_random_uuid(),'client','windows','6.1.4',7,'stable',false,false,
  'THQ ERP v6.1.4 Build 7 — Final Stabilization. Runtime UI stabilization, database security hardening, targeted index improvements, and release-state reconciliation. GST/accounting transaction authority is unchanged.',
  null,now()
),
(
  gen_random_uuid(),'pos','windows','6.1.4',7,'stable',false,false,
  'THQ ERP v6.1.4 Build 7 — Final Stabilization. Fixes responsive POS layout overflow, strengthens database RPC security, adds targeted indexes, and reconciles release state. GST/accounting transaction authority is unchanged.',
  null,now()
),
(
  gen_random_uuid(),'admin','web','6.1.4',7,'stable',false,false,
  'THQ ERP v6.1.4 Build 7 — Final Stabilization. Fixes Material/ListTile runtime warnings, strengthens privileged Edge Function gateway authentication and database RPC security, and improves diagnostics.',
  null,now()
)
on conflict(app_key,platform,version) do update
set build_number=excluded.build_number,
    status=excluded.status,
    minimum_supported=excluded.minimum_supported,
    mandatory=excluded.mandatory,
    release_notes=excluded.release_notes,
    released_at=excluded.released_at;

insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  297,
  '6.1.4-build7',
  'v6.1.4 Build 7 Final Stabilization',
  'Final stabilization: remove anonymous/PUBLIC execution from public SECURITY DEFINER RPCs while preserving authenticated/service-role access; pin mutable function search paths; relocate citext to extensions; add targeted relationship indexes; synchronize desktop/admin release metadata. No GST, accounting, inventory, settlement, sale, purchase, return, or mobile sync writer logic changes.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
;
