begin;

-- THQ ERP v6.1.4 Build 7 — Final Stabilization
-- Pre-auth activation/login use Edge Functions. Normal application RPCs require
-- an authenticated session, so anonymous clients do not need direct EXECUTE on
-- public SECURITY DEFINER functions.
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as fn
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
  loop
    execute format('revoke execute on function %s from anon', r.fn);
  end loop;
end $$;

alter function public.reports_catalog_v500()
  set search_path = public, private, extensions, pg_temp;

alter function private.gst_v520_account_family(text)
  set search_path = private, public, extensions, pg_temp;

alter function private.gst_append_nonnull_line_v520(jsonb, jsonb)
  set search_path = private, public, extensions, pg_temp;

alter function private.loan_v490_periods_per_year(text)
  set search_path = private, public, extensions, pg_temp;

alter function private.loan_v490_due_date(date, text, integer)
  set search_path = private, public, extensions, pg_temp;

alter extension citext set schema extensions;

-- Only targeted high-value FK indexes. Do not bulk-create advisor suggestions.
create index if not exists idx_journal_lines_journal_entry_v614
  on public.journal_lines(journal_entry_id);

create index if not exists idx_sales_return_items_return_v614
  on public.sales_return_items(sales_return_id);

create index if not exists idx_sales_return_items_sale_item_v614
  on public.sales_return_items(sale_item_id);

create index if not exists idx_sales_return_items_variant_v614
  on public.sales_return_items(variant_id);

create index if not exists idx_sales_returns_sale_v614
  on public.sales_returns(sale_id);

create index if not exists idx_stock_transfer_items_transfer_v614
  on public.stock_transfer_items(transfer_id);

create index if not exists idx_stock_transfer_items_variant_v614
  on public.stock_transfer_items(variant_id);

create index if not exists idx_business_devices_location_v614
  on public.business_devices(location_id);

insert into public.platform_app_releases(
  id, app_key, platform, version, build_number, status,
  minimum_supported, mandatory, release_notes, download_url, released_at
)
values
(
  gen_random_uuid(), 'client', 'windows', '6.1.4', 7, 'stable',
  false, false,
  'THQ ERP v6.1.4 Build 7 — Final Stabilization. Final runtime/security hardening checkpoint. No change to authoritative GST, accounting, stock or transaction writer semantics.',
  null, now()
),
(
  gen_random_uuid(), 'pos', 'windows', '6.1.4', 7, 'stable',
  false, false,
  'THQ ERP v6.1.4 Build 7 — Final Stabilization. Fixes final POS responsive overflows and completes runtime/security hardening without changing authoritative GST or transaction writer semantics.',
  null, now()
),
(
  gen_random_uuid(), 'admin', 'web', '6.1.4', 7, 'stable',
  false, false,
  'THQ ERP v6.1.4 Build 7 — Final Stabilization. Fixes Admin ListTile Material/background warning and completes runtime/security hardening.',
  null, now()
)
on conflict(app_key, platform, version) do update
set build_number = excluded.build_number,
    status = excluded.status,
    minimum_supported = excluded.minimum_supported,
    mandatory = excluded.mandatory,
    release_notes = excluded.release_notes;

insert into public.thq_schema_releases(
  migration_no, schema_version, release_name, notes
)
values(
  297,
  '6.1.4-build7',
  'v6.1.4 Build 7 Final Stabilization',
  'Final security/runtime stabilization: revoke anon EXECUTE from public SECURITY DEFINER RPCs, pin mutable function search paths, relocate citext, add targeted FK indexes, and synchronize desktop/Admin release metadata. Authoritative GST/accounting/transaction writer semantics remain unchanged.'
)
on conflict(migration_no) do update
set schema_version = excluded.schema_version,
    release_name = excluded.release_name,
    notes = excluded.notes;

commit;
