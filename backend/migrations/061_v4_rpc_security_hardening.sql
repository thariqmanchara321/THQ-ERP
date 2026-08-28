-- FLEXI ERP V4 final RPC privilege hardening.
-- PostgreSQL functions are executable by PUBLIC by default unless explicitly revoked.
-- All public V4 RPCs are authenticated-only; every sensitive RPC also performs tenant/permission/location checks internally.
begin;

do $$
declare r record;v_sig text;
begin
  for r in
    select p.oid,n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and (right(p.proname,3)='_v4' or p.proname in ('document_origin_get'))
  loop
    v_sig:=format('%I.%I(%s)',r.nspname,r.proname,r.args);
    execute 'revoke all on function '||v_sig||' from public';
    begin execute 'revoke all on function '||v_sig||' from anon'; exception when undefined_object then null; end;
    execute 'grant execute on function '||v_sig||' to authenticated';
  end loop;
end $$;

commit;
select 'Flexi ERP V4 RPC security hardening applied' as status;
