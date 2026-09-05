do $$
declare r record; v_def text; v_new text;
begin
  for r in
    select p.oid,p.proname
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f'
      and p.proname in ('purchase_invoice_post_v484','purchase_invoice_void_v490','supplier_payment_create_v484','supplier_payment_void_v490')
  loop
    v_def:=pg_get_functiondef(r.oid);
    v_new:=replace(v_def,'thq_sync_bump_v480(p_tenant_id,''accounting''','thq_sync_bump_v480(p_tenant_id,''finance''');
    if v_new=v_def then
      raise exception 'Expected accounting sync-domain call not found in %',r.proname;
    end if;
    execute v_new;
  end loop;
end $$;