-- THQ ERP v6.1 Restaurant KOT kind prerequisite
-- Ensures fresh/replayed databases have the KOT kind discriminator before delta/void KOT migrations.

alter table public.restaurant_kots
  add column if not exists kind text not null default 'items';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.restaurant_kots'::regclass
      and conname = 'restaurant_kots_kind_check'
  ) then
    alter table public.restaurant_kots
      add constraint restaurant_kots_kind_check
      check (kind in ('items', 'void', 'reprint'));
  end if;
end
$$;
