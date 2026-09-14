-- THQ ERP v6.1 Restaurant table-event type alignment
-- Keeps upgraded databases compatible with v6.1 transfer/merge/split/move/state/bill/clear events.

alter table public.restaurant_table_events
  drop constraint if exists restaurant_table_events_event_type_check;

alter table public.restaurant_table_events
  add constraint restaurant_table_events_event_type_check
  check (
    event_type in (
      'transfer',
      'merge',
      'split',
      'move_items',
      'state',
      'bill_request',
      'clear'
    )
  );
