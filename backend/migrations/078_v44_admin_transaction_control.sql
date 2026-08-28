-- FLEXI ERP V4.4
-- Platform-admin transaction control centre with safe void rules.
begin;

create or replace function public.platform_transactions_list_v44(
  p_tenant_id uuid,p_from date default null,p_to date default null,p_query text default null,p_limit integer default 500
) returns table(
  entity_type text,entity_id uuid,reference text,entry_date date,party text,total numeric,paid numeric,balance numeric,status text,
  location_id uuid,location_name text,device_id uuid,device_name text,created_at timestamptz
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';lim integer:=greatest(1,least(coalesce(p_limit,500),2000));begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required';end if;
  return query
  select z.* from (
    select 'sale'::text,s.id,coalesce(dn.terminal_number,ln.local_number,s.sale_number)::text,s.sale_date,c.name::text,s.grand_total,
      coalesce(py.paid,0)::numeric,greatest(s.grand_total-coalesce(py.paid,0),0)::numeric,s.status::text,o.location_id,l.name::text,o.device_id,d.name::text,s.created_at
    from public.sales s join public.customers c on c.id=s.customer_id
    left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id) py on py.sale_id=s.id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    left join public.business_locations l on l.id=o.location_id left join public.business_devices d on d.id=o.device_id
    left join public.location_document_numbers ln on ln.tenant_id=p_tenant_id and ln.entity_type='sale' and ln.entity_id=s.id
    left join public.device_document_numbers dn on dn.tenant_id=p_tenant_id and dn.entity_type='sale' and dn.entity_id=s.id
    where s.tenant_id=p_tenant_id and (p_from is null or s.sale_date>=p_from) and (p_to is null or s.sale_date<=p_to)
      and (trim(coalesce(p_query,''))='' or lower(coalesce(s.sale_number,'')) like q or lower(coalesce(c.name,'')) like q or lower(coalesce(dn.terminal_number,ln.local_number,'')) like q)
    union all
    select 'purchase'::text,p.id,coalesce(dn.terminal_number,ln.local_number,p.purchase_number)::text,p.purchase_date,sup.name::text,p.grand_total,
      coalesce(py.paid,0)::numeric,greatest(p.grand_total-coalesce(py.paid,0),0)::numeric,p.status::text,o.location_id,l.name::text,o.device_id,d.name::text,p.created_at
    from public.purchases p join public.suppliers sup on sup.id=p.supplier_id
    left join(select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id=p.id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id
    left join public.business_locations l on l.id=o.location_id left join public.business_devices d on d.id=o.device_id
    left join public.location_document_numbers ln on ln.tenant_id=p_tenant_id and ln.entity_type='purchase' and ln.entity_id=p.id
    left join public.device_document_numbers dn on dn.tenant_id=p_tenant_id and dn.entity_type='purchase' and dn.entity_id=p.id
    where p.tenant_id=p_tenant_id and (p_from is null or p.purchase_date>=p_from) and (p_to is null or p.purchase_date<=p_to)
      and (trim(coalesce(p_query,''))='' or lower(coalesce(p.purchase_number,'')) like q or lower(coalesce(sup.name,'')) like q or lower(coalesce(p.supplier_invoice_number,'')) like q or lower(coalesce(dn.terminal_number,ln.local_number,'')) like q)
    union all
    select 'expense'::text,e.id,e.expense_number::text,e.expense_date,coalesce(e.payee,e.description)::text,e.total_amount,0::numeric,e.total_amount,e.status::text,o.location_id,l.name::text,o.device_id,d.name::text,e.created_at
    from public.expenses e
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='expense' and o.entity_id=e.id
    left join public.business_locations l on l.id=o.location_id left join public.business_devices d on d.id=o.device_id
    where e.tenant_id=p_tenant_id and (p_from is null or e.expense_date>=p_from) and (p_to is null or e.expense_date<=p_to)
      and (trim(coalesce(p_query,''))='' or lower(coalesce(e.expense_number,'')) like q or lower(coalesce(e.payee,'')) like q or lower(coalesce(e.description,'')) like q)
  ) z order by z.created_at desc limit lim;
end $$;
grant execute on function public.platform_transactions_list_v44(uuid,date,date,text,integer) to authenticated;

create or replace function public.platform_transaction_void_v44(
  p_tenant_id uuid,p_entity_type text,p_entity_id uuid,p_reason text
) returns void
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_type text:=lower(coalesce(p_entity_type,''));v_loc uuid;v_ref text;r record;begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('technical_admin') then raise exception 'Super/technical admin required';end if;
  if trim(coalesce(p_reason,''))='' then raise exception 'Reason is required';end if;

  if v_type='sale' then
    if exists(select 1 from public.sale_payments where sale_id=p_entity_id and amount<>0) then raise exception 'Paid sale cannot be directly voided. Use business return/refund workflow.';end if;
    if exists(select 1 from public.sales_returns where sale_id=p_entity_id) then raise exception 'Sale with returns cannot be voided';end if;
    select o.location_id,s.sale_number into v_loc,v_ref from public.sales s join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id where s.id=p_entity_id and s.tenant_id=p_tenant_id for update;
    if v_loc is null then raise exception 'Sale not found or has no branch origin';end if;
    for r in select si.variant_id,si.quantity,pr.item_type from public.sale_items si join public.product_variants pv on pv.id=si.variant_id join public.products pr on pr.id=pv.product_id where si.sale_id=p_entity_id loop
      if r.item_type='stock' then
        perform public.inventory_adjust_stock(p_tenant_id,r.variant_id,r.quantity,'Admin void sale • '||v_ref);
        perform private.v4_location_stock_apply(p_tenant_id,v_loc,r.variant_id,r.quantity,'sale_return','sale',p_entity_id,v_ref,'Platform Admin Void • '||trim(p_reason),null,false);
      end if;
    end loop;
    update public.sales set status='void' where id=p_entity_id and tenant_id=p_tenant_id;
    insert into public.transaction_corrections(tenant_id,entity_type,entity_id,correction_type,reason,created_by,metadata) values(p_tenant_id,'sale',p_entity_id,'void',trim(p_reason),auth.uid(),jsonb_build_object('platform_admin',true));

  elsif v_type='purchase' then
    if exists(select 1 from public.purchase_payments where purchase_id=p_entity_id and amount<>0) then raise exception 'Paid purchase cannot be directly voided. Use business return/refund workflow.';end if;
    if exists(select 1 from public.purchase_returns where purchase_id=p_entity_id) then raise exception 'Purchase with returns cannot be voided';end if;
    select o.location_id,p.purchase_number into v_loc,v_ref from public.purchases p join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id where p.id=p_entity_id and p.tenant_id=p_tenant_id for update;
    if v_loc is null then raise exception 'Purchase not found or has no branch origin';end if;
    for r in select pi.variant_id,pi.quantity,pr.item_type from public.purchase_items pi join public.product_variants pv on pv.id=pi.variant_id join public.products pr on pr.id=pv.product_id where pi.purchase_id=p_entity_id loop
      if r.item_type='stock' then
        if coalesce((select quantity from public.location_stock_balances where tenant_id=p_tenant_id and location_id=v_loc and variant_id=r.variant_id),0)<r.quantity then raise exception 'Cannot void purchase because branch stock has already been consumed';end if;
        perform public.inventory_adjust_stock(p_tenant_id,r.variant_id,-r.quantity,'Admin void purchase • '||v_ref);
        perform private.v4_location_stock_apply(p_tenant_id,v_loc,r.variant_id,-r.quantity,'purchase_return','purchase',p_entity_id,v_ref,'Platform Admin Void • '||trim(p_reason),null,false);
      end if;
    end loop;
    update public.purchases set status='void' where id=p_entity_id and tenant_id=p_tenant_id;
    insert into public.transaction_corrections(tenant_id,entity_type,entity_id,correction_type,reason,created_by,metadata) values(p_tenant_id,'purchase',p_entity_id,'void',trim(p_reason),auth.uid(),jsonb_build_object('platform_admin',true));

  elsif v_type='expense' then
    select expense_number into v_ref from public.expenses where id=p_entity_id and tenant_id=p_tenant_id and status='posted' for update;
    if v_ref is null then raise exception 'Posted expense not found';end if;
    update public.expenses set status='void',updated_at=now() where id=p_entity_id and tenant_id=p_tenant_id;
    begin perform private.v4_reverse_source_journal(p_tenant_id,'expense',p_entity_id,'expense_void','Platform Admin Void '||v_ref); exception when undefined_function then null; end;
  else
    raise exception 'Unsupported entity type';
  end if;
  perform private.platform_audit_write('transaction.void',v_type,p_entity_id::text,p_tenant_id,jsonb_build_object('reason',trim(p_reason),'reference',v_ref));
end $$;
grant execute on function public.platform_transaction_void_v44(uuid,text,uuid,text) to authenticated;

commit;
select 'Flexi ERP V4.4 platform transaction control ready' as status;
