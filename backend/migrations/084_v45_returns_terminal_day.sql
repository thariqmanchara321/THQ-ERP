-- THQ V4.5
-- POS return workspace support and return-aware Terminal Daily / Day Close.
begin;

create or replace function public.transaction_return_status_v45(p_tenant_id uuid,p_entity_type text,p_entity_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare original_qty numeric:=0;returned_qty numeric:=0;returned_total numeric:=0;v_status text:='not_returned';begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if p_entity_type='sale' then
    select coalesce(sum(quantity),0) into original_qty from public.sale_items where sale_id=p_entity_id;
    select coalesce(sum(i.quantity),0),coalesce(sum(r.grand_total),0) into returned_qty,returned_total from public.sales_returns r join public.sales_return_items i on i.sales_return_id=r.id where r.tenant_id=p_tenant_id and r.sale_id=p_entity_id and r.refund_status<>'waived';
  elsif p_entity_type='purchase' then
    select coalesce(sum(quantity),0) into original_qty from public.purchase_items where purchase_id=p_entity_id;
    select coalesce(sum(i.quantity),0),coalesce(sum(r.grand_total),0) into returned_qty,returned_total from public.purchase_returns r join public.purchase_return_items i on i.purchase_return_id=r.id where r.tenant_id=p_tenant_id and r.purchase_id=p_entity_id and r.credit_status<>'waived';
  else raise exception 'Invalid entity type';end if;
  if returned_qty>0 and returned_qty+0.0001>=original_qty then v_status:='fully_returned';
  elsif returned_qty>0 then v_status:='partially_returned';end if;
  return jsonb_build_object('status',v_status,'original_quantity',original_qty,'returned_quantity',returned_qty,'returned_total',returned_total);
end $$;
grant execute on function public.transaction_return_status_v45(uuid,text,uuid) to authenticated;

create or replace function public.pos_terminal_day_v45(p_tenant_id uuid,p_device_id uuid,p_day date default current_date)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_base jsonb;v_returns numeric:=0;v_return_count bigint:=0;v_purchase_returns numeric:=0;v_purchase_return_count bigint:=0;v_expenses numeric:=0;v_expense_count bigint:=0;v_held bigint:=0;v_return_rows jsonb:='[]'::jsonb;begin
  select public.pos_terminal_day_v41(p_tenant_id,p_device_id,p_day) into v_base;
  select coalesce(sum(r.grand_total),0),count(*) into v_returns,v_return_count
  from public.sales_returns r where r.tenant_id=p_tenant_id and r.device_id=p_device_id and r.return_date=p_day and r.refund_status<>'waived';
  select coalesce(sum(r.grand_total),0),count(*) into v_purchase_returns,v_purchase_return_count
  from public.purchase_returns r where r.tenant_id=p_tenant_id and r.device_id=p_device_id and r.return_date=p_day and r.credit_status<>'waived';
  select coalesce(sum(e.total_amount),0),count(*) into v_expenses,v_expense_count
  from public.expenses e join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='expense' and o.entity_id=e.id and o.device_id=p_device_id
  where e.tenant_id=p_tenant_id and e.expense_date=p_day and e.status='posted';
  select count(*) into v_held from public.pos_held_sales h where h.tenant_id=p_tenant_id and h.device_id=p_device_id;
  select coalesce(jsonb_agg(x order by x.created_at desc),'[]'::jsonb) into v_return_rows from (
    select r.id,r.return_number,'sale_return'::text return_type,r.return_date,r.grand_total,r.reason,r.created_at,s.sale_number reference,c.name party
    from public.sales_returns r join public.sales s on s.id=r.sale_id join public.customers c on c.id=s.customer_id
    where r.tenant_id=p_tenant_id and r.device_id=p_device_id and r.return_date=p_day
    union all
    select r.id,r.return_number,'purchase_return',r.return_date,r.grand_total,r.reason,r.created_at,p.purchase_number,sp.name
    from public.purchase_returns r join public.purchases p on p.id=r.purchase_id join public.suppliers sp on sp.id=p.supplier_id
    where r.tenant_id=p_tenant_id and r.device_id=p_device_id and r.return_date=p_day
  ) x;
  return coalesce(v_base,'{}'::jsonb)||jsonb_build_object(
    'sales_returns',v_returns,'sales_return_count',v_return_count,
    'purchase_returns',v_purchase_returns,'purchase_return_count',v_purchase_return_count,
    'net_sales',greatest(coalesce((v_base->>'gross_sales')::numeric,0)-v_returns,0),
    'expenses',v_expenses,'expense_count',v_expense_count,'held_count',v_held,'returns',v_return_rows
  );
end $$;
grant execute on function public.pos_terminal_day_v45(uuid,uuid,date) to authenticated;

create or replace function public.returns_register_v45(p_tenant_id uuid,p_from date,p_to date,p_location_id uuid default null,p_type text default 'all',p_query text default null)
returns table(return_type text,return_id uuid,return_number text,return_date date,reference text,party text,grand_total numeric,status text,location_id uuid,location_name text,device_id uuid,device_name text,reason text,created_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select * from (
    select 'sale_return'::text,r.id,r.return_number,r.return_date,s.sale_number,c.name,r.grand_total,r.refund_status,r.location_id,l.name,r.device_id,d.name,r.reason,r.created_at
    from public.sales_returns r join public.sales s on s.id=r.sale_id join public.customers c on c.id=s.customer_id join public.business_locations l on l.id=r.location_id left join public.business_devices d on d.id=r.device_id
    where r.tenant_id=p_tenant_id and r.return_date between p_from and p_to and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view') and p_type in('all','sale') and (trim(coalesce(p_query,''))='' or lower(r.return_number) like q or lower(s.sale_number) like q or lower(c.name) like q)
    union all
    select 'purchase_return',r.id,r.return_number,r.return_date,p.purchase_number,sp.name,r.grand_total,r.credit_status,r.location_id,l.name,r.device_id,d.name,r.reason,r.created_at
    from public.purchase_returns r join public.purchases p on p.id=r.purchase_id join public.suppliers sp on sp.id=p.supplier_id join public.business_locations l on l.id=r.location_id left join public.business_devices d on d.id=r.device_id
    where r.tenant_id=p_tenant_id and r.return_date between p_from and p_to and private.erp_document_scope_allowed(p_tenant_id,r.location_id,p_location_id,'view') and p_type in('all','purchase') and (trim(coalesce(p_query,''))='' or lower(r.return_number) like q or lower(p.purchase_number) like q or lower(sp.name) like q)
  ) z order by z.created_at desc;
end $$;
grant execute on function public.returns_register_v45(uuid,date,date,uuid,text,text) to authenticated;

commit;
select 'THQ V4.5 return-aware terminal daily ready' as status;
