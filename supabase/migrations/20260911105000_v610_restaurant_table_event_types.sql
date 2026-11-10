-- THQ ERP v6.1 Restaurant table-event vocabulary alignment
-- Older databases only allowed transfer/merge/split. v6.1 also records move/state/bill/clear events.

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conrelid='public.restaurant_table_events'::regclass
      and conname='restaurant_table_events_event_type_check'
  ) then
    alter table public.restaurant_table_events
      drop constraint restaurant_table_events_event_type_check;
  end if;

  alter table public.restaurant_table_events
    add constraint restaurant_table_events_event_type_check
    check (event_type in ('transfer','merge','split','move_items','state','bill_request','clear'));
end
$$;;
