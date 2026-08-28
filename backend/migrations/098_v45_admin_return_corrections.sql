-- THQ V4.5
-- Extend Super Admin Transaction Control to sale/purchase return documents.
begin;

alter table public.transaction_corrections drop constraint if exists transaction_corrections_entity_type_check;
alter table public.transaction_corrections add constraint transaction_corrections_entity_type_check
check(entity_type in('sale','purchase','expense','payment','sales_return','purchase_return'));

create or replace function public.platform_transactions_list_v45(
  p_tenant_id uuid,p_from date default null,p_to date default null,p_query text default null,p_limit integer default 500
) returns table(
  entity_type text,entity_id uuid,reference text,entry_date date,party text,total numeric,paid numeric,balance numeric,status text,
  location_id uuid,location_name text,device_id uuid,device_name text,created_at timestamptz
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';lim integer:=greatest(1,least(coalesce(p_limit,500),2000));
begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required';end if;
  return query
  select z.* from (
    select b.entity_type,b.entity_id,b.reference,b.entry_date,b.party,b.total,b.paid,b.balance,b.status,b.location_id,b.location_name,b.device_id,b.device_name,b.created_at
    from public.platform_transactions_list_v44(p_tenant_id,p_from,p_to,p_query,2000) b

    union all

    select 'sales_return'::text,r.id,r.return_number::text,r.return_date,c.name::text,r.grand_total,
      0::numeric,r.grand_total::numeric,r.refund_status::text,r.location_id,l.name::text,r.device_id,d.name::text,r.created_at
    from public.sales_returns r
    join public.sales s on s.id=r.sale_id and s.tenant_id=p_tenant_id
    join public.customers c on c.id=s.customer_id
    join public.business_locations l on l.id=r.location_id
    left join public.business_devices d on d.id=r.device_id
    where r.tenant_id=p_tenant_id
      and (p_from is null or r.return_date>=p_from) and (p_to is null or r.return_date<=p_to)
      and (trim(coalesce(p_query,''))='' or lower(coalesce(r.return_number,'')) like q or lower(coalesce(s.sale_number,'')) like q or lower(coalesce(c.name,'')) like q)

    union all

    select 'purchase_return'::text,r.id,r.return_number::text,r.return_date,sp.name::text,r.grand_total,
      0::numeric,r.grand_total::numeric,r.credit_status::text,r.location_id,l.name::text,r.device_id,d.name::text,r.created_at
    from public.purchase_returns r
    join public.purchases p on p.id=r.purchase_id and p.tenant_id=p_tenant_id
    join public.suppliers sp on sp.id=p.supplier_id
    join public.business_locations l on l.id=r.location_id
    left join public.business_devices d on d.id=r.device_id
    where r.tenant_id=p_tenant_id
      and (p_from is null or r.return_date>=p_from) and (p_to is null or r.return_date<=p_to)
      and (trim(coalesce(p_query,''))='' or lower(coalesce(r.return_number,'')) like q or lower(coalesce(p.purchase_number,'')) like q or lower(coalesce(p.supplier_invoice_number,'')) like q or lower(coalesce(sp.name,'')) like q)
  ) z
  order by z.created_at desc
  limit lim;
end $$;
grant execute on function public.platform_transactions_list_v45(uuid,date,date,text,integer) to authenticated;

create or replace function public.platform_transaction_detail_v45(p_tenant_id uuid,p_entity_type text,p_entity_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v jsonb;v_type text:=lower(coalesce(p_entity_type,''));
begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required';end if;
  if v_type='sale' then
    select jsonb_build_object('entity',to_jsonb(s),'party',to_jsonb(c),'origin',to_jsonb(o),
      'items',coalesce((select jsonb_agg(to_jsonb(i)) from public.sale_items i where i.sale_id=s.id),'[]'::jsonb),
      'payments',coalesce((select jsonb_agg(to_jsonb(p)) from public.sale_payments p where p.sale_id=s.id),'[]'::jsonb)) into v
    from public.sales s join public.customers c on c.id=s.customer_id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.id=p_entity_id and s.tenant_id=p_tenant_id;
  elsif v_type='purchase' then
    select jsonb_build_object('entity',to_jsonb(p),'party',to_jsonb(sp),'origin',to_jsonb(o),
      'items',coalesce((select jsonb_agg(to_jsonb(i)) from public.purchase_items i where i.purchase_id=p.id),'[]'::jsonb),
      'payments',coalesce((select jsonb_agg(to_jsonb(py)) from public.purchase_payments py where py.purchase_id=p.id),'[]'::jsonb)) into v
    from public.purchases p join public.suppliers sp on sp.id=p.supplier_id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id
    where p.id=p_entity_id and p.tenant_id=p_tenant_id;
  elsif v_type='expense' then
    select jsonb_build_object('entity',to_jsonb(e),'origin',to_jsonb(o),'items','[]'::jsonb,'payments','[]'::jsonb) into v
    from public.expenses e
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='expense' and o.entity_id=e.id
    where e.id=p_entity_id and e.tenant_id=p_tenant_id;
  elsif v_type='sales_return' then
    select jsonb_build_object(
      'entity',to_jsonb(r),'party',to_jsonb(c),
      'origin',jsonb_build_object('location_id',r.location_id,'device_id',r.device_id,'source_type','sale','source_id',r.sale_id,'source_number',s.sale_number),
      'items',coalesce((select jsonb_agg(to_jsonb(ri)||jsonb_build_object('product_name',pr.name,'sku',pv.sku,'part_number',pv.part_number) order by ri.id)
        from public.sales_return_items ri join public.product_variants pv on pv.id=ri.variant_id join public.products pr on pr.id=pv.product_id where ri.sales_return_id=r.id),'[]'::jsonb),
      'payments','[]'::jsonb
    ) into v
    from public.sales_returns r join public.sales s on s.id=r.sale_id join public.customers c on c.id=s.customer_id
    where r.id=p_entity_id and r.tenant_id=p_tenant_id;
  elsif v_type='purchase_return' then
    select jsonb_build_object(
      'entity',to_jsonb(r),'party',to_jsonb(sp),
      'origin',jsonb_build_object('location_id',r.location_id,'device_id',r.device_id,'source_type','purchase','source_id',r.purchase_id,'source_number',p.purchase_number),
      'items',coalesce((select jsonb_agg(to_jsonb(ri)||jsonb_build_object('product_name',pr.name,'sku',pv.sku,'part_number',pv.part_number) order by ri.id)
        from public.purchase_return_items ri join public.product_variants pv on pv.id=ri.variant_id join public.products pr on pr.id=pv.product_id where ri.purchase_return_id=r.id),'[]'::jsonb),
      'payments','[]'::jsonb
    ) into v
    from public.purchase_returns r join public.purchases p on p.id=r.purchase_id join public.suppliers sp on sp.id=p.supplier_id
    where r.id=p_entity_id and r.tenant_id=p_tenant_id;
  else
    raise exception 'Unsupported entity type';
  end if;
  if v is null then raise exception 'Transaction not found';end if;
  return v;
end $$;
grant execute on function public.platform_transaction_detail_v45(uuid,text,uuid) to authenticated;

create or replace function public.platform_return_correct_v45(
  p_tenant_id uuid,p_entity_type text,p_entity_id uuid,p_patch jsonb,p_reason text
) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_type text:=lower(coalesce(p_entity_type,''));v_before jsonb;v_after jsonb;v_loc uuid;v_ref text;x jsonb;
  v_item_id uuid;v_variant uuid;v_old_qty numeric;v_new_qty numeric;v_delta numeric;v_stock_delta numeric;v_other numeric;
  v_original_qty numeric;v_unit numeric;v_discount_per_unit numeric;v_tax_rate numeric;v_sub numeric;v_disc numeric;v_line numeric;
  v_total_sub numeric;v_total_tax numeric;v_total numeric;
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('technical_admin') then raise exception 'Super/technical admin required';end if;
  if v_type not in('sales_return','purchase_return') then raise exception 'Unsupported return type';end if;
  if trim(coalesce(p_reason,''))='' then raise exception 'Correction reason is required';end if;
  v_before:=public.platform_transaction_detail_v45(p_tenant_id,v_type,p_entity_id);

  if v_type='sales_return' then
    select location_id,return_number into v_loc,v_ref from public.sales_returns where id=p_entity_id and tenant_id=p_tenant_id for update;
    if v_loc is null then raise exception 'Sales return not found';end if;
    if p_patch?'items' then
      perform private.v4_reverse_source_journal(p_tenant_id,'sales_return',p_entity_id,'sales_return_edit_reverse','Admin correction '||v_ref);
      update public.journal_entries set status='reversed' where tenant_id=p_tenant_id and source_type='sales_return' and source_id=p_entity_id and status='posted';
      for x in select value from jsonb_array_elements(coalesce(p_patch->'items','[]'::jsonb)) loop
        v_item_id:=(x->>'item_id')::uuid;
        select ri.variant_id,ri.quantity,si.quantity,si.unit_price,coalesce(si.discount_amount,0)/nullif(si.quantity,0),coalesce(si.tax_rate,0)
          into v_variant,v_old_qty,v_original_qty,v_unit,v_discount_per_unit,v_tax_rate
        from public.sales_return_items ri join public.sale_items si on si.id=ri.sale_item_id
        where ri.id=v_item_id and ri.sales_return_id=p_entity_id for update;
        if v_variant is null then raise exception 'Sales return item not found';end if;
        v_new_qty:=coalesce(nullif(x->>'quantity','')::numeric,v_old_qty);
        if v_new_qty<0 then raise exception 'Return quantity cannot be negative';end if;
        select coalesce(sum(other.quantity),0) into v_other
        from public.sales_return_items other join public.sales_returns sr on sr.id=other.sales_return_id
        where sr.sale_id=(select sale_id from public.sales_returns where id=p_entity_id) and other.sale_item_id=(select sale_item_id from public.sales_return_items where id=v_item_id) and other.id<>v_item_id;
        if v_other+v_new_qty>v_original_qty+0.0001 then raise exception 'Corrected return quantity exceeds originally sold quantity';end if;
        v_delta:=v_new_qty-v_old_qty;
        if v_delta<0 and coalesce((select quantity-reserved_quantity-damaged_quantity-quarantine_quantity from public.location_stock_balances where tenant_id=p_tenant_id and location_id=v_loc and variant_id=v_variant),0)<abs(v_delta) then
          raise exception 'Cannot reduce the sales return because the returned stock has already been consumed';
        end if;
        if abs(v_delta)>0.0001 then
          perform public.inventory_adjust_stock(p_tenant_id,v_variant,v_delta,'Admin sales return correction • '||v_ref);
          perform private.v4_location_stock_apply(p_tenant_id,v_loc,v_variant,v_delta,case when v_delta>0 then 'adjustment_in' else 'adjustment_out' end,'sales_return',p_entity_id,v_ref,'Platform Admin correction • '||trim(p_reason),null,false);
        end if;
        if v_new_qty=0 then
          delete from public.sales_return_items where id=v_item_id;
        else
          v_sub:=round(v_unit*v_new_qty,2);v_disc:=round(coalesce(v_discount_per_unit,0)*v_new_qty,2);
          v_line:=round(greatest(v_sub-v_disc,0)*(1+v_tax_rate/100.0),2);
          update public.sales_return_items set quantity=v_new_qty,unit_price=v_unit,discount_amount=v_disc,tax_rate=v_tax_rate,line_total=v_line where id=v_item_id;
        end if;
      end loop;
      select coalesce(sum((unit_price*quantity)-discount_amount),0),coalesce(sum(line_total-((unit_price*quantity)-discount_amount)),0),coalesce(sum(line_total),0)
        into v_total_sub,v_total_tax,v_total from public.sales_return_items where sales_return_id=p_entity_id;
      update public.sales_returns set subtotal=v_total_sub,tax_total=v_total_tax,grand_total=v_total where id=p_entity_id;
      if v_total>0 then perform private.v4_post_sales_return(p_entity_id);end if;
    end if;
    if p_patch?'reason' then update public.sales_returns set reason=coalesce(nullif(trim(p_patch->>'reason'),''),reason) where id=p_entity_id;end if;

  else
    select location_id,return_number into v_loc,v_ref from public.purchase_returns where id=p_entity_id and tenant_id=p_tenant_id for update;
    if v_loc is null then raise exception 'Purchase return not found';end if;
    if p_patch?'items' then
      perform private.v4_reverse_source_journal(p_tenant_id,'purchase_return',p_entity_id,'purchase_return_edit_reverse','Admin correction '||v_ref);
      update public.journal_entries set status='reversed' where tenant_id=p_tenant_id and source_type='purchase_return' and source_id=p_entity_id and status='posted';
      for x in select value from jsonb_array_elements(coalesce(p_patch->'items','[]'::jsonb)) loop
        v_item_id:=(x->>'item_id')::uuid;
        select ri.variant_id,ri.quantity,pi.quantity,pi.unit_cost,coalesce(pi.discount_amount,0)/nullif(pi.quantity,0),coalesce(pi.tax_rate,0)
          into v_variant,v_old_qty,v_original_qty,v_unit,v_discount_per_unit,v_tax_rate
        from public.purchase_return_items ri join public.purchase_items pi on pi.id=ri.purchase_item_id
        where ri.id=v_item_id and ri.purchase_return_id=p_entity_id for update;
        if v_variant is null then raise exception 'Purchase return item not found';end if;
        v_new_qty:=coalesce(nullif(x->>'quantity','')::numeric,v_old_qty);
        if v_new_qty<0 then raise exception 'Return quantity cannot be negative';end if;
        select coalesce(sum(other.quantity),0) into v_other
        from public.purchase_return_items other join public.purchase_returns pr on pr.id=other.purchase_return_id
        where pr.purchase_id=(select purchase_id from public.purchase_returns where id=p_entity_id) and other.purchase_item_id=(select purchase_item_id from public.purchase_return_items where id=v_item_id) and other.id<>v_item_id;
        if v_other+v_new_qty>v_original_qty+0.0001 then raise exception 'Corrected return quantity exceeds originally purchased quantity';end if;
        v_delta:=v_new_qty-v_old_qty;
        v_stock_delta:=-v_delta;
        if v_stock_delta<0 and coalesce((select quantity-reserved_quantity-damaged_quantity-quarantine_quantity from public.location_stock_balances where tenant_id=p_tenant_id and location_id=v_loc and variant_id=v_variant),0)<abs(v_stock_delta) then
          raise exception 'Cannot increase the purchase return because that stock is no longer available';
        end if;
        if abs(v_stock_delta)>0.0001 then
          perform public.inventory_adjust_stock(p_tenant_id,v_variant,v_stock_delta,'Admin purchase return correction • '||v_ref);
          perform private.v4_location_stock_apply(p_tenant_id,v_loc,v_variant,v_stock_delta,case when v_stock_delta>0 then 'adjustment_in' else 'adjustment_out' end,'purchase_return',p_entity_id,v_ref,'Platform Admin correction • '||trim(p_reason),null,false);
        end if;
        if v_new_qty=0 then
          delete from public.purchase_return_items where id=v_item_id;
        else
          v_sub:=round(v_unit*v_new_qty,2);v_disc:=round(coalesce(v_discount_per_unit,0)*v_new_qty,2);
          v_line:=round(greatest(v_sub-v_disc,0)*(1+v_tax_rate/100.0),2);
          update public.purchase_return_items set quantity=v_new_qty,unit_cost=v_unit,discount_amount=v_disc,tax_rate=v_tax_rate,line_total=v_line where id=v_item_id;
        end if;
      end loop;
      select coalesce(sum((unit_cost*quantity)-discount_amount),0),coalesce(sum(line_total-((unit_cost*quantity)-discount_amount)),0),coalesce(sum(line_total),0)
        into v_total_sub,v_total_tax,v_total from public.purchase_return_items where purchase_return_id=p_entity_id;
      update public.purchase_returns set subtotal=v_total_sub,tax_total=v_total_tax,grand_total=v_total where id=p_entity_id;
      if v_total>0 then perform private.v4_post_purchase_return(p_entity_id);end if;
    end if;
    if p_patch?'reason' then update public.purchase_returns set reason=coalesce(nullif(trim(p_patch->>'reason'),''),reason) where id=p_entity_id;end if;
  end if;

  v_after:=public.platform_transaction_detail_v45(p_tenant_id,v_type,p_entity_id);
  insert into public.transaction_corrections(tenant_id,entity_type,entity_id,correction_type,reason,created_by,metadata)
  values(p_tenant_id,v_type,p_entity_id,'edit',trim(p_reason),auth.uid(),jsonb_build_object('before',v_before,'patch',p_patch,'after',v_after,'platform_admin',true));
  perform private.platform_audit_write('transaction.correct',v_type,p_entity_id::text,p_tenant_id,jsonb_build_object('reason',trim(p_reason),'patch',p_patch));
  return v_after;
end $$;
grant execute on function public.platform_return_correct_v45(uuid,text,uuid,jsonb,text) to authenticated;

commit;
select 'THQ V4.5 admin return corrections ready' as status;
