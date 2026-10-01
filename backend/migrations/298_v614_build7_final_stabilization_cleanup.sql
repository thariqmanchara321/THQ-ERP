begin;

-- Cleanup is intentionally idempotent. The live stabilization process briefly
-- produced a second set of equivalent index names; keep the v614 names only.
drop index if exists public.idx_journal_lines_journal_entry_final;
drop index if exists public.idx_sales_return_items_sale_item_final;
drop index if exists public.idx_sales_return_items_return_final;
drop index if exists public.idx_stock_transfer_items_transfer_final;
drop index if exists public.idx_stock_transfer_items_variant_final;

insert into public.thq_schema_releases(
  migration_no, schema_version, release_name, notes
)
values(
  298,
  '6.1.4-build7-final',
  'v6.1.4 Build 7 Final Stabilization Cleanup',
  'Removes redundant duplicate indexes created during final stabilization verification. No data, GST, accounting, transaction, stock or authorization semantics changed.'
)
on conflict(migration_no) do update
set schema_version = excluded.schema_version,
    release_name = excluded.release_name,
    notes = excluded.notes;

commit;
