do $$
declare
  v_sql text;
begin
  v_sql:=pg_get_functiondef('public.restaurant_order_create_v32(uuid,uuid,uuid,text,uuid,uuid,integer,text,text,jsonb)'::regprocedure);
  if position('thq_sync_bump_v480(p_tenant_id,''restaurant''' in v_sql)=0 then
    raise exception 'Expected Restaurant sync call not found in restaurant_order_create_v32';
  end if;
  execute replace(v_sql,'thq_sync_bump_v480(p_tenant_id,''restaurant''','thq_sync_bump_v480(p_tenant_id,''transactions''');

  v_sql:=pg_get_functiondef('public.restaurant_order_bill_v489(uuid,uuid,uuid,uuid,date,numeric,text,text,numeric)'::regprocedure);
  if position('thq_sync_bump_v480(p_tenant_id,''restaurant''' in v_sql)=0 then
    raise exception 'Expected Restaurant sync call not found in restaurant_order_bill_v489';
  end if;
  execute replace(v_sql,'thq_sync_bump_v480(p_tenant_id,''restaurant''','thq_sync_bump_v480(p_tenant_id,''transactions''');

  v_sql:=pg_get_functiondef('public.gst_restaurant_order_bill_v520(uuid,uuid,uuid,uuid,date,numeric,text,text,numeric,text,text)'::regprocedure);
  if position('thq_sync_bump_v480(p_tenant_id,''restaurant''' in v_sql)=0 then
    raise exception 'Expected Restaurant sync call not found in gst_restaurant_order_bill_v520';
  end if;
  execute replace(v_sql,'thq_sync_bump_v480(p_tenant_id,''restaurant''','thq_sync_bump_v480(p_tenant_id,''transactions''');
end $$;