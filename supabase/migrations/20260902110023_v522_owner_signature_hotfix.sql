do $$
declare v_def text; v_oid oid;
begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='payment_method_save_v522'
    and p.oid::regprocedure::text='payment_method_save_v522(uuid,text,text,uuid,boolean,integer)';
  if v_oid is null then raise exception 'payment_method_save_v522 not found'; end if;
  v_def:=pg_get_functiondef(v_oid);
  v_def:=replace(v_def,'private.erp_user_is_owner(p_tenant_id)','private.erp_user_is_owner(p_tenant_id, auth.uid())');
  execute v_def;

  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='gst_sale_create_v522'
    and p.oid::regprocedure::text='gst_sale_create_v522(uuid,uuid,date,date,jsonb,jsonb,text,uuid,uuid,text,text,text)';
  if v_oid is null then raise exception 'gst_sale_create_v522 not found'; end if;
  v_def:=pg_get_functiondef(v_oid);
  v_def:=replace(v_def,'private.erp_user_is_owner(p_tenant_id)','private.erp_user_is_owner(p_tenant_id, auth.uid())');
  execute v_def;
end $$;;
