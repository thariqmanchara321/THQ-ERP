-- Flexi ERP V3: pending payments, top sellers/customers and bulk product import.
create or replace function public.payments_pending_list(p_tenant_id uuid,p_limit integer default 300)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_rec jsonb; v_pay jsonb; begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not private.erp_has_permission(p_tenant_id,'payments.view') and not private.erp_has_permission(p_tenant_id,'sales.manage') and not private.erp_has_permission(p_tenant_id,'purchases.manage') then raise exception 'Permission denied'; end if;
  select coalesce(jsonb_agg(x order by (x->>'date')::date desc),'[]'::jsonb) into v_rec from (
    select jsonb_build_object('id',s.id,'type','receivable','reference',s.sale_number,'party_id',s.customer_id,'party_name',c.name,'date',s.sale_date,'due_date',s.due_date,'total',s.grand_total,'paid',coalesce((select sum(sp.amount) from public.sale_payments sp where sp.sale_id=s.id),0),'balance',s.grand_total-coalesce((select sum(sp.amount) from public.sale_payments sp where sp.sale_id=s.id),0)) x
    from public.sales s join public.customers c on c.id=s.customer_id where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in ('cancelled','void') and s.grand_total-coalesce((select sum(sp.amount) from public.sale_payments sp where sp.sale_id=s.id),0) > 0.005 limit greatest(1,least(coalesce(p_limit,300),1000))
  ) q;
  select coalesce(jsonb_agg(x order by (x->>'date')::date desc),'[]'::jsonb) into v_pay from (
    select jsonb_build_object('id',p.id,'type','payable','reference',p.purchase_number,'party_id',p.supplier_id,'party_name',s.name,'date',p.purchase_date,'due_date',p.due_date,'total',p.grand_total,'paid',coalesce((select sum(pp.amount) from public.purchase_payments pp where pp.purchase_id=p.id),0),'balance',p.grand_total-coalesce((select sum(pp.amount) from public.purchase_payments pp where pp.purchase_id=p.id),0)) x
    from public.purchases p join public.suppliers s on s.id=p.supplier_id where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in ('cancelled','void') and p.grand_total-coalesce((select sum(pp.amount) from public.purchase_payments pp where pp.purchase_id=p.id),0) > 0.005 limit greatest(1,least(coalesce(p_limit,300),1000))
  ) q;
  return jsonb_build_object('receivables',coalesce(v_rec,'[]'::jsonb),'payables',coalesce(v_pay,'[]'::jsonb));
end $$;
grant execute on function public.payments_pending_list(uuid,integer) to authenticated;

create or replace function public.dashboard_v3_insights(p_tenant_id uuid,p_from_date date default (current_date-interval '29 days')::date,p_to_date date default current_date)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_top_products jsonb;v_top_customers jsonb;v_daily jsonb; begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('variant_id',variant_id,'product_name',product_name,'quantity',qty,'sales',sales) order by sales desc),'[]'::jsonb) into v_top_products from (
    select si.variant_id,max(coalesce(p.name,'Product')) product_name,sum(si.quantity)::numeric qty,sum(si.line_total)::numeric sales
    from public.sale_items si join public.sales s on s.id=si.sale_id left join public.product_variants pv on pv.id=si.variant_id left join public.products p on p.id=pv.product_id
    where s.tenant_id=p_tenant_id and s.sale_date between p_from_date and p_to_date and coalesce(s.status,'') not in ('cancelled','void') group by si.variant_id order by sales desc limit 10
  ) x;
  select coalesce(jsonb_agg(jsonb_build_object('customer_id',customer_id,'customer_name',customer_name,'sales',sales,'invoice_count',invoice_count) order by sales desc),'[]'::jsonb) into v_top_customers from (
    select s.customer_id,max(c.name) customer_name,sum(s.grand_total)::numeric sales,count(*)::int invoice_count from public.sales s join public.customers c on c.id=s.customer_id where s.tenant_id=p_tenant_id and s.sale_date between p_from_date and p_to_date and coalesce(s.status,'') not in ('cancelled','void') group by s.customer_id order by sales desc limit 10
  ) x;
  select coalesce(jsonb_agg(jsonb_build_object('date',d.day,'sales',coalesce(x.sales,0)) order by d.day),'[]'::jsonb) into v_daily from generate_series(p_from_date::timestamp,p_to_date::timestamp,interval '1 day') d(day) left join (select sale_date,sum(grand_total)::numeric sales from public.sales where tenant_id=p_tenant_id and sale_date between p_from_date and p_to_date and coalesce(status,'') not in ('cancelled','void') group by sale_date)x on x.sale_date=d.day::date;
  return jsonb_build_object('top_products',v_top_products,'top_customers',v_top_customers,'daily_sales',v_daily);
end $$;
grant execute on function public.dashboard_v3_insights(uuid,date,date) to authenticated;

-- Bulk import deliberately reuses inventory_create_product so all existing inventory rules stay centralized.
create or replace function public.inventory_bulk_create_products(p_tenant_id uuid,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare r jsonb; ok int:=0; failed int:=0; errs jsonb:='[]'::jsonb; idx int:=0; begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
  if not private.erp_has_permission(p_tenant_id,'bulk_import.use') and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Permission denied'; end if;
  if jsonb_typeof(p_rows)<>'array' then raise exception 'Rows must be an array'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    idx:=idx+1;
    begin
      perform public.inventory_create_product(
        p_tenant_id,
        coalesce(r->>'name',''),coalesce(r->>'sku',''),coalesce(nullif(r->>'item_type',''),'stock'),coalesce(r->>'description',''),coalesce(r->>'category',''),coalesce(r->>'brand',''),coalesce(r->>'barcode',''),coalesce(r->>'part_number',''),
        coalesce(nullif(r->>'cost_price','')::numeric,0),coalesce(nullif(r->>'selling_price','')::numeric,0),nullif(r->>'list_price','')::numeric,coalesce(nullif(r->>'tax_rate','')::numeric,0),coalesce(nullif(r->>'reorder_level','')::numeric,0),coalesce(nullif(r->>'opening_stock','')::numeric,0)
      ); ok:=ok+1;
    exception when others then failed:=failed+1; errs:=errs||jsonb_build_array(jsonb_build_object('row',idx,'sku',r->>'sku','error',sqlerrm)); end;
  end loop;
  perform private.business_audit_write(p_tenant_id,'bulk_import','product',null,null,null,jsonb_build_object('success',ok,'failed',failed));
  return jsonb_build_object('success_count',ok,'failed_count',failed,'errors',errs);
end $$;
grant execute on function public.inventory_bulk_create_products(uuid,jsonb) to authenticated;
