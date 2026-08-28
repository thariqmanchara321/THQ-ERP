-- THQ V4.5
-- Net-of-return top products/customers/GST analytics.
begin;

create or replace function public.analytics_top_products_v4(p_tenant_id uuid,p_from date,p_to date,p_location_id uuid default null,p_limit integer default 10)
returns table(variant_id uuid,product_name text,sku text,quantity numeric,revenue numeric,gross_profit numeric)
language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 return query
 with sold as (
   select si.variant_id,max(pr.name) product_name,max(pv.sku) sku,sum(si.quantity) qty,sum(si.line_total) revenue,sum(coalesce(si.gross_profit,0)) profit
   from public.sale_items si join public.sales s on s.id=si.sale_id join public.product_variants pv on pv.id=si.variant_id join public.products pr on pr.id=pv.product_id left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
   where s.tenant_id=p_tenant_id and s.sale_date between p_from and p_to and coalesce(s.status,'') not in('void','cancelled') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view') group by si.variant_id
 ),ret as (
   select ri.variant_id,sum(ri.quantity) qty,sum(ri.line_total) revenue,sum(coalesce(si.cost_total,0)*(ri.quantity/nullif(si.quantity,0))) return_cost
   from public.sales_return_items ri join public.sales_returns r on r.id=ri.sales_return_id join public.sale_items si on si.id=ri.sale_item_id
   where r.tenant_id=p_tenant_id and r.return_date between p_from and p_to and r.refund_status<>'waived' and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view') group by ri.variant_id
 )
 select s.variant_id,s.product_name,s.sku,greatest(s.qty-coalesce(r.qty,0),0),greatest(s.revenue-coalesce(r.revenue,0),0),s.profit-(coalesce(r.revenue,0)-coalesce(r.return_cost,0))
 from sold s left join ret r on r.variant_id=s.variant_id order by greatest(s.qty-coalesce(r.qty,0),0) desc limit greatest(1,least(coalesce(p_limit,10),100));
end $$;
grant execute on function public.analytics_top_products_v4(uuid,date,date,uuid,integer) to authenticated;

create or replace function public.analytics_top_customers_v4(p_tenant_id uuid,p_from date,p_to date,p_location_id uuid default null,p_limit integer default 10)
returns table(customer_id uuid,customer_name text,sale_count bigint,revenue numeric,balance_due numeric)
language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 return query
 select c.id,c.name,count(s.id),sum(greatest(s.grand_total-coalesce(rt.returned,0),0)),sum(greatest(s.grand_total-coalesce(py.paid,0)-coalesce(rt.returned,0),0))
 from public.sales s join public.customers c on c.id=s.customer_id
 left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
 left join(select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id
 left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
 where s.tenant_id=p_tenant_id and s.sale_date between p_from and p_to and coalesce(s.status,'') not in('void','cancelled') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
 group by c.id,c.name order by sum(greatest(s.grand_total-coalesce(rt.returned,0),0)) desc limit greatest(1,least(coalesce(p_limit,10),100));
end $$;
grant execute on function public.analytics_top_customers_v4(uuid,date,date,uuid,integer) to authenticated;

create or replace function public.gst_summary_v4(p_tenant_id uuid,p_from date,p_to date,p_location_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$ declare v_out numeric;v_in numeric;v_sales numeric;v_purchases numeric;v_sr_tax numeric;v_pr_tax numeric;v_sr_sub numeric;v_pr_sub numeric;begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 select coalesce(sum(s.tax_total),0),coalesce(sum(s.taxable_total),0) into v_out,v_sales from public.sales s left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id where s.tenant_id=p_tenant_id and s.sale_date between p_from and p_to and coalesce(s.status,'') not in('void','cancelled') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
 select coalesce(sum(p.tax_total),0),coalesce(sum(p.taxable_total),0) into v_in,v_purchases from public.purchases p left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id where p.tenant_id=p_tenant_id and p.purchase_date between p_from and p_to and coalesce(p.status,'') not in('void','cancelled') and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view');
 select coalesce(sum(tax_total),0),coalesce(sum(subtotal),0) into v_sr_tax,v_sr_sub from public.sales_returns where tenant_id=p_tenant_id and return_date between p_from and p_to and refund_status<>'waived' and private.erp_document_scope_allowed(p_tenant_id,location_id,p_location_id,'view');
 select coalesce(sum(tax_total),0),coalesce(sum(subtotal),0) into v_pr_tax,v_pr_sub from public.purchase_returns where tenant_id=p_tenant_id and return_date between p_from and p_to and credit_status<>'waived' and private.erp_document_scope_allowed(p_tenant_id,location_id,p_location_id,'view');
 return jsonb_build_object('taxable_sales',greatest(v_sales-v_sr_sub,0),'output_gst',greatest(v_out-v_sr_tax,0),'taxable_purchases',greatest(v_purchases-v_pr_sub,0),'input_gst',greatest(v_in-v_pr_tax,0),'sales_return_tax',v_sr_tax,'purchase_return_tax',v_pr_tax,'net_gst_payable',(v_out-v_sr_tax)-(v_in-v_pr_tax));
end $$;
grant execute on function public.gst_summary_v4(uuid,date,date,uuid) to authenticated;

commit;
select 'THQ V4.5 return-aware analytics ready' as status;
