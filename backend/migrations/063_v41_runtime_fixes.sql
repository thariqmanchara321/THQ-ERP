-- FLEXI ERP V4.1
-- Runtime fixes found during V4 field testing: accounting register text types,
-- scoped purchase/sales list ambiguity, and legacy MAIN product bootstrap.
begin;

-- Bootstrap only legacy product variants that have no location assignment yet.
-- Existing child-store-only assignments are preserved exactly as configured.
do $$
declare r record; v_main uuid;
begin
  for r in select id from public.tenants loop
    select l.id into v_main
    from public.business_locations l
    where l.tenant_id=r.id and l.active
    order by case when upper(coalesce(l.location_code,''))='MAIN' then 0 when l.parent_location_id is null then 1 else 2 end,
             l.created_at
    limit 1;
    if v_main is null then continue; end if;

    -- Only bootstrap genuinely unassigned/legacy variants. A product already assigned
    -- to a child store must NOT suddenly become available in MAIN.
    insert into public.location_product_settings(tenant_id,location_id,variant_id,active,selling_price,reorder_level)
    select pv.tenant_id,v_main,pv.id,true,pv.selling_price,pv.reorder_level
    from public.product_variants pv
    where pv.tenant_id=r.id
      and not exists(
        select 1 from public.location_product_settings existing
        where existing.tenant_id=pv.tenant_id and existing.variant_id=pv.id
      )
    on conflict(tenant_id,location_id,variant_id) do nothing;

    -- Seed a MAIN balance only when the product has no branch balance anywhere.
    -- This preserves products intentionally created/stocked in a child store.
    insert into public.location_stock_balances(tenant_id,location_id,variant_id,quantity,average_cost)
    select pv.tenant_id,v_main,pv.id,coalesce(sb.qty,0),coalesce(pv.cost_price,0)
    from public.product_variants pv
    join public.location_product_settings ps
      on ps.tenant_id=pv.tenant_id and ps.variant_id=pv.id and ps.location_id=v_main
    left join (
      select b.tenant_id,b.variant_id,sum(b.quantity) qty
      from public.stock_balances b
      where b.tenant_id=r.id
      group by b.tenant_id,b.variant_id
    ) sb on sb.tenant_id=pv.tenant_id and sb.variant_id=pv.id
    where pv.tenant_id=r.id
      and not exists(
        select 1 from public.location_stock_balances existing
        where existing.tenant_id=pv.tenant_id and existing.variant_id=pv.id
      )
    on conflict(tenant_id,location_id,variant_id) do nothing;
  end loop;
end $$;

-- Sales list: fully qualify payment aggregation columns so PL/pgSQL OUT variables
-- can never shadow sale_id.
create or replace function public.sales_list_v32(p_tenant_id uuid,p_location_id uuid default null)
returns table(
  sale_id uuid,sale_number text,invoice_number text,customer_id uuid,customer_name text,sale_date date,due_date date,
  subtotal numeric,discount_total numeric,tax_total numeric,additional_charges numeric,grand_total numeric,
  paid_amount numeric,balance_due numeric,payment_status text,cost_total numeric,gross_profit numeric,status text,created_at timestamptz,
  location_id uuid,location_name text,device_id uuid,device_name text
)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if p_location_id is not null and not private.erp_user_location_allowed(p_tenant_id,p_location_id,'view')
     and not private.erp_has_permission(p_tenant_id,'locations.view_all')
     and not private.erp_has_permission(p_tenant_id,'locations.manage_all')
     and not private.erp_user_is_owner(p_tenant_id) then
    raise exception 'Location access denied';
  end if;
  return query
  select s.id,s.sale_number::text,coalesce(dn.terminal_number,ln.local_number,s.sale_number)::text,
    s.customer_id,c.name::text,s.sale_date,s.due_date,
    s.subtotal,s.discount_total,s.tax_total,s.additional_charges,s.grand_total,
    coalesce(py.paid,0)::numeric,greatest(s.grand_total-coalesce(py.paid,0),0)::numeric,
    (case when greatest(s.grand_total-coalesce(py.paid,0),0)<=0.0001 then 'paid' when coalesce(py.paid,0)>0 then 'partial' else 'unpaid' end)::text,
    coalesce(s.cost_total,0)::numeric,coalesce(s.gross_profit,0)::numeric,s.status::text,s.created_at,
    o.location_id,l.name::text,o.device_id,d.name::text
  from public.sales s
  join public.customers c on c.id=s.customer_id
  left join (
    select sp.sale_id as entity_sale_id,sum(sp.amount) as paid
    from public.sale_payments sp group by sp.sale_id
  ) py on py.entity_sale_id=s.id
  left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
  left join public.business_locations l on l.id=o.location_id
  left join public.business_devices d on d.id=o.device_id
  left join public.location_document_numbers ln on ln.tenant_id=p_tenant_id and ln.entity_type='sale' and ln.entity_id=s.id
  left join public.device_document_numbers dn on dn.tenant_id=p_tenant_id and dn.entity_type='sale' and dn.entity_id=s.id
  where s.tenant_id=p_tenant_id
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'sales.view') or private.erp_has_permission(p_tenant_id,'sales.manage'))
    and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
  order by s.sale_date desc,s.created_at desc;
end $$;
grant execute on function public.sales_list_v32(uuid,uuid) to authenticated;

-- Purchases list: same shadowing fix for purchase_id.
create or replace function public.purchases_list_v32(p_tenant_id uuid,p_location_id uuid default null)
returns table(
  purchase_id uuid,purchase_number text,invoice_number text,supplier_id uuid,supplier_name text,supplier_invoice_number text,purchase_date date,due_date date,
  subtotal numeric,discount_total numeric,tax_total numeric,additional_charges numeric,grand_total numeric,paid_amount numeric,balance_due numeric,payment_status text,status text,created_at timestamptz,
  location_id uuid,location_name text,device_id uuid,device_name text
)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  select p.id,p.purchase_number::text,coalesce(dn.terminal_number,ln.local_number,p.purchase_number)::text,
    p.supplier_id,s.name::text,p.supplier_invoice_number::text,p.purchase_date,p.due_date,
    p.subtotal,p.discount_total,p.tax_total,p.additional_charges,p.grand_total,
    coalesce(py.paid,0)::numeric,greatest(p.grand_total-coalesce(py.paid,0),0)::numeric,
    (case when greatest(p.grand_total-coalesce(py.paid,0),0)<=0.0001 then 'paid' when coalesce(py.paid,0)>0 then 'partial' else 'unpaid' end)::text,
    p.status::text,p.created_at,o.location_id,l.name::text,o.device_id,d.name::text
  from public.purchases p
  join public.suppliers s on s.id=p.supplier_id
  left join (
    select pp.purchase_id as entity_purchase_id,sum(pp.amount) as paid
    from public.purchase_payments pp group by pp.purchase_id
  ) py on py.entity_purchase_id=p.id
  left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id
  left join public.business_locations l on l.id=o.location_id
  left join public.business_devices d on d.id=o.device_id
  left join public.location_document_numbers ln on ln.tenant_id=p_tenant_id and ln.entity_type='purchase' and ln.entity_id=p.id
  left join public.device_document_numbers dn on dn.tenant_id=p_tenant_id and dn.entity_type='purchase' and dn.entity_id=p.id
  where p.tenant_id=p_tenant_id
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'purchases.view') or private.erp_has_permission(p_tenant_id,'purchases.manage'))
    and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
  order by p.purchase_date desc,p.created_at desc;
end $$;
grant execute on function public.purchases_list_v32(uuid,uuid) to authenticated;

-- Accounting register: citext columns are explicitly cast to text to exactly match
-- the RETURNS TABLE contract on installations that use citext names/usernames.
create or replace function public.accounting_register_v4(
  p_tenant_id uuid,p_register text,p_from date,p_to date,p_location_id uuid default null,p_query text default null
)
returns table(entry_date date,reference text,party text,description text,debit numeric,credit numeric,location_code text,user_name text,source_type text,source_id uuid)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  select j.entry_date,
    j.source_reference::text,
    coalesce(case when jl.party_type='customer' then c.name::text when jl.party_type='supplier' then s.name::text else '' end,'')::text,
    coalesce(jl.description::text,j.description::text,'')::text,
    jl.debit,jl.credit,
    coalesce(bl.location_code::text,'')::text,
    coalesce(ul.username::text,'')::text,
    j.source_type::text,j.source_id
  from public.journal_entries j
  join public.journal_lines jl on jl.journal_entry_id=j.id
  join public.accounting_accounts a on a.id=jl.account_id
  left join public.customers c on jl.party_type='customer' and c.id=jl.party_id
  left join public.suppliers s on jl.party_type='supplier' and s.id=jl.party_id
  left join public.business_locations bl on bl.id=j.location_id
  left join public.user_login_names ul on ul.user_id=j.created_by
  where j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date between p_from and p_to
    and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view')
    and (p_register='all'
      or (p_register='sales' and j.source_type in('sale','sale_payment','sales_return'))
      or (p_register='purchases' and j.source_type in('purchase','purchase_payment','purchase_return'))
      or (p_register='cash' and a.system_key='cash')
      or (p_register='bank' and a.system_key in('bank','upi','card'))
      or (p_register='gst' and a.system_key in('input_gst','output_gst'))
      or (p_register='receivables' and a.system_key='accounts_receivable')
      or (p_register='payables' and a.system_key='accounts_payable')
      or (p_register='journal' and j.source_type='manual'))
    and (
      trim(coalesce(p_query,''))=''
      or lower(coalesce(j.source_reference::text,'')) like q
      or lower(coalesce(j.description::text,'')) like q
      or lower(coalesce(c.name::text,'')) like q
      or lower(coalesce(s.name::text,'')) like q
      or lower(coalesce(a.name::text,'')) like q
      or exists(
        select 1 from public.sales sx
        join public.sale_items six on six.sale_id=sx.id
        join public.product_variants pvx on pvx.id=six.variant_id
        join public.products prx on prx.id=pvx.product_id
        where sx.tenant_id=p_tenant_id
          and sx.id=case
            when j.source_type='sale' then j.source_id
            when j.source_type='sale_payment' then (select spx.sale_id from public.sale_payments spx where spx.id=j.source_id)
            when j.source_type='sales_return' then (select srx.sale_id from public.sales_returns srx where srx.id=j.source_id)
            else null end
          and (lower(prx.name::text) like q or lower(coalesce(pvx.sku::text,'')) like q or lower(coalesce(pvx.part_number::text,'')) like q)
      )
      or exists(
        select 1 from public.purchases pxh
        join public.purchase_items pix on pix.purchase_id=pxh.id
        join public.product_variants pvx on pvx.id=pix.variant_id
        join public.products prx on prx.id=pvx.product_id
        where pxh.tenant_id=p_tenant_id
          and pxh.id=case
            when j.source_type='purchase' then j.source_id
            when j.source_type='purchase_payment' then (select ppx.purchase_id from public.purchase_payments ppx where ppx.id=j.source_id)
            when j.source_type='purchase_return' then (select prx2.purchase_id from public.purchase_returns prx2 where prx2.id=j.source_id)
            else null end
          and (lower(prx.name::text) like q or lower(coalesce(pvx.sku::text,'')) like q or lower(coalesce(pvx.part_number::text,'')) like q)
      )
    )
  order by j.entry_date desc,j.created_at desc;
end $$;
grant execute on function public.accounting_register_v4(uuid,text,date,date,uuid,text) to authenticated;

commit;
select 'Flexi ERP V4.1 runtime fixes ready' as status;
