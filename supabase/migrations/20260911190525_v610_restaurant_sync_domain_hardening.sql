-- THQ ERP v6.1 Restaurant sync-domain hardening
-- Normalizes Restaurant configuration RPCs to the valid THQ sync domain: configuration.

do $migration$
declare
  v_def text;
begin
  select pg_get_functiondef(
    'public.restaurant_table_layout_batch_set_v610(uuid,uuid,uuid,jsonb)'::regprocedure
  ) into v_def;
  execute replace(v_def, '''master''', '''configuration''');

  select pg_get_functiondef(
    'public.restaurant_table_reservation_set_v610(uuid,uuid,uuid,text,text,timestamptz,text)'::regprocedure
  ) into v_def;
  execute replace(v_def, '''settings''', '''configuration''');

  select pg_get_functiondef(
    'public.restaurant_table_reservation_clear_v610(uuid,uuid,uuid,text)'::regprocedure
  ) into v_def;
  execute replace(v_def, '''settings''', '''configuration''');

  select pg_get_functiondef(
    'public.restaurant_table_status_set_v610(uuid,uuid,uuid,text,text)'::regprocedure
  ) into v_def;
  execute replace(v_def, '''settings''', '''configuration''');
end
$migration$;

do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'restaurant_table_layout_batch_set_v610',
        'restaurant_table_reservation_set_v610',
        'restaurant_table_reservation_clear_v610',
        'restaurant_table_status_set_v610'
      )
      and (
        pg_get_functiondef(p.oid) like '%''master''%'
        or pg_get_functiondef(p.oid) like '%''settings''%'
      )
  ) then
    raise exception 'Restaurant sync-domain hardening did not fully normalize the affected RPCs';
  end if;
end
$$;
