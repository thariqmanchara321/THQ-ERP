-- This migration intentionally DOES NOT replace the working sales engine.
-- It only fails early if the two RPCs required by the new Sale Details screen are absent.
do $$
begin
  if to_regprocedure('public.sales_get_detail(uuid,uuid)') is null then
    raise exception 'Missing RPC public.sales_get_detail(uuid,uuid). Keep/use the Sales foundation migration from the previous build.';
  end if;
  -- sales_add_payment can have a multi-parameter signature; check by name.
  if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='sales_add_payment') then
    raise exception 'Missing RPC public.sales_add_payment. Keep/use the Sales foundation migration from the previous build.';
  end if;
end $$;
