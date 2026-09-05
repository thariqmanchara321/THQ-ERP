do $$
declare v_def text;v_old text:='''offline_sync'',''v5.2-foundation'',''gst_engine'',''gst_v520''';v_new text:='''offline_sync'',''v4.8.6'',''gst_engine'',''legacy_unverified''';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='pos_offline_sale_sync_v486'
    and pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_device_id uuid, p_location_id uuid, p_request_id text, p_payload jsonb';
  if v_def is null then raise exception 'pos_offline_sale_sync_v486 definition not found';end if;
  if position(v_old in v_def)=0 then raise exception 'Expected v486 response metadata fragment not found; refusing broad rewrite';end if;
  v_def:=replace(v_def,v_old,v_new);
  execute v_def;
end$$;