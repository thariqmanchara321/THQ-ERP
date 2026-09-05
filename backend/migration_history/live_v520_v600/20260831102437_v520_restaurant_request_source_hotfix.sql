do $$
declare v_sql text;
begin
  v_sql:=pg_get_functiondef('public.gst_restaurant_order_bill_v520(uuid,uuid,uuid,uuid,date,numeric,text,text,numeric,text,text)'::regprocedure);
  if position('''gst.restaurant.order.bill.v520'',''sale'',v_sale_id' in v_sql)=0 then
    raise exception 'Expected Restaurant wrapper completion source not found';
  end if;
  execute replace(v_sql,
    '''gst.restaurant.order.bill.v520'',''sale'',v_sale_id,v_snapshot,v_sale_journal,v_response',
    '''gst.restaurant.order.bill.v520'',''restaurant_order'',o.id,v_snapshot,v_sale_journal,v_response');
end $$;