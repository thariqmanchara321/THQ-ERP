-- THQ V4.5
-- Audited Super Admin transaction correction centre.
begin;

alter table public.transaction_corrections drop constraint if exists transaction_corrections_correction_type_check;
alter table public.transaction_corrections add constraint transaction_corrections_correction_type_check
check(correction_type in('void','cancel','return','credit_note','debit_note','reverse_recreate','edit'));

create or replace function public.platform_transaction_detail_v45(p_tenant_id uuid,p_entity_type text,p_entity_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare v jsonb;begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required';end if;
  if p_entity_type='sale' then
    select jsonb_build_object('entity',to_jsonb(s),'party',to_jsonb(c),'origin',to_jsonb(o),'items',coalesce((select jsonb_agg(to_jsonb(i)) from public.sale_items i where i.sale_id=s.id),'[]'::jsonb),'payments',coalesce((select jsonb_agg(to_jsonb(p)) from public.sale_payments p where p.sale_id=s.id),'[]'::jsonb)) into v
    from public.sales s join public.customers c on c.id=s.customer_id left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id where s.id=p_entity_id and s.tenant_id=p_tenant_id;
  elsif p_entity_type='purchase' then
    select jsonb_build_object('entity',to_jsonb(p),'party',to_jsonb(sp),'origin',to_jsonb(o),'items',coalesce((select jsonb_agg(to_jsonb(i)) from public.purchase_items i where i.purchase_id=p.id),'[]'::jsonb),'payments',coalesce((select jsonb_agg(to_jsonb(py)) from public.purchase_payments py where py.purchase_id=p.id),'[]'::jsonb)) into v
    from public.purchases p join public.suppliers sp on sp.id=p.supplier_id left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id where p.id=p_entity_id and p.tenant_id=p_tenant_id;
  elsif p_entity_type='expense' then
    select jsonb_build_object('entity',to_jsonb(e),'origin',to_jsonb(o),'items','[]'::jsonb,'payments','[]'::jsonb) into v from public.expenses e left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='expense' and o.entity_id=e.id where e.id=p_entity_id and e.tenant_id=p_tenant_id;
  else raise exception 'Unsupported entity type';end if;
  if v is null then raise exception 'Transaction not found';end if;return v;
end $$;
grant execute on function public.platform_transaction_detail_v45(uuid,text,uuid) to authenticated;

create or replace function public.platform_transaction_correct_v45(p_tenant_id uuid,p_entity_type text,p_entity_id uuid,p_patch jsonb,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_type text:=lower(p_entity_type);v_before jsonb;v_after jsonb;v_loc uuid;v_paid numeric:=0;x jsonb;r record;old_qty numeric;new_qty numeric;delta numeric;new_price numeric;new_disc numeric;new_tax numeric;new_sub numeric;new_taxable numeric;new_tax_amount numeric;new_line numeric;unit_cost numeric;begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('technical_admin') then raise exception 'Super/technical admin required';end if;
  if trim(coalesce(p_reason,''))='' then raise exception 'Correction reason is required';end if;
  v_before:=public.platform_transaction_detail_v45(p_tenant_id,v_type,p_entity_id);
  select location_id into v_loc from public.document_origins where tenant_id=p_tenant_id and entity_type=v_type and entity_id=p_entity_id;

  if v_type='sale' then
    if (p_patch ? 'customer_id') and not exists(select 1 from public.customers where id=(p_patch->>'customer_id')::uuid and tenant_id=p_tenant_id) then raise exception 'Customer not found';end if;
    update public.sales set
      customer_id=case when p_patch?'customer_id' then (p_patch->>'customer_id')::uuid else customer_id end,
      due_date=case when p_patch?'due_date' then nullif(p_patch->>'due_date','')::date else due_date end,
      notes=case when p_patch?'notes' then p_patch->>'notes' else notes end
    where id=p_entity_id and tenant_id=p_tenant_id;
    if p_patch?'items' then
      if exists(select 1 from public.sales_returns where sale_id=p_entity_id) then raise exception 'Item/value edits are blocked after a return. Use a correcting return/new invoice.';end if;
      select coalesce(sum(amount),0) into v_paid from public.sale_payments where sale_id=p_entity_id;
      perform private.v4_reverse_source_journal(p_tenant_id,'sale',p_entity_id,'sale_edit_reverse','Admin correction sale');
      update public.journal_entries set status='reversed' where tenant_id=p_tenant_id and source_type='sale' and source_id=p_entity_id and status='posted';
      for x in select value from jsonb_array_elements(p_patch->'items') loop
        select quantity into old_qty from public.sale_items where id=(x->>'item_id')::uuid and sale_id=p_entity_id for update;
        if old_qty is null then raise exception 'Sale item not found';end if;
        new_qty:=coalesce(nullif(x->>'quantity','')::numeric,old_qty);if new_qty<=0 then raise exception 'Quantity must be positive. Use Return/Void to remove an item.';end if;
        select coalesce(cost_total/nullif(quantity,0),0),unit_price,discount_amount,tax_rate into unit_cost,new_price,new_disc,new_tax from public.sale_items where id=(x->>'item_id')::uuid;
        new_price:=coalesce(nullif(x->>'unit_price','')::numeric,new_price);new_disc:=coalesce(nullif(x->>'discount_amount','')::numeric,new_disc);new_tax:=coalesce(nullif(x->>'tax_rate','')::numeric,new_tax);
        delta:=old_qty-new_qty;
        if abs(delta)>0.0001 and exists(select 1 from public.product_variants pv join public.products p on p.id=pv.product_id where pv.id=(select variant_id from public.sale_items where id=(x->>'item_id')::uuid) and p.item_type='stock') then
          if delta<0 and coalesce((select quantity-reserved_quantity-damaged_quantity-quarantine_quantity from public.location_stock_balances where tenant_id=p_tenant_id and location_id=v_loc and variant_id=(select variant_id from public.sale_items where id=(x->>'item_id')::uuid)),0)<abs(delta) then raise exception 'Insufficient branch stock for correction';end if;
          perform public.inventory_adjust_stock(p_tenant_id,(select variant_id from public.sale_items where id=(x->>'item_id')::uuid),delta,'Admin sale correction');
          perform private.v4_location_stock_apply(p_tenant_id,v_loc,(select variant_id from public.sale_items where id=(x->>'item_id')::uuid),delta,'adjustment','sale',p_entity_id,null,'Platform Admin correction • '||trim(p_reason),null,false);
        end if;
        new_sub:=round(new_qty*new_price,2);new_taxable:=greatest(new_sub-new_disc,0);new_tax_amount:=round(new_taxable*new_tax/100.0,2);new_line:=new_taxable+new_tax_amount;
        update public.sale_items set quantity=new_qty,unit_price=new_price,discount_amount=new_disc,tax_rate=new_tax,subtotal=new_sub,taxable_amount=new_taxable,tax_amount=new_tax_amount,line_total=new_line,cost_total=round(unit_cost*new_qty,2),gross_profit=new_taxable-round(unit_cost*new_qty,2) where id=(x->>'item_id')::uuid and sale_id=p_entity_id;
      end loop;
      update public.sales s set subtotal=q.subtotal,discount_total=q.discount_total,taxable_total=q.taxable_total,tax_total=q.tax_total,grand_total=q.line_total+s.additional_charges,cost_total=q.cost_total,gross_profit=q.gross_profit
      from (select sale_id,sum(subtotal) subtotal,sum(discount_amount) discount_total,sum(taxable_amount) taxable_total,sum(tax_amount) tax_total,sum(line_total) line_total,sum(cost_total) cost_total,sum(gross_profit) gross_profit from public.sale_items where sale_id=p_entity_id group by sale_id) q where s.id=q.sale_id;
      if v_paid>(select grand_total from public.sales where id=p_entity_id)+0.005 then raise exception 'Corrected total would be below payments already received';end if;
      perform private.v4_accounting_post_document(p_tenant_id,'sale',p_entity_id);
    end if;
  elsif v_type='purchase' then
    if (p_patch?'supplier_id') and not exists(select 1 from public.suppliers where id=(p_patch->>'supplier_id')::uuid and tenant_id=p_tenant_id) then raise exception 'Supplier not found';end if;
    update public.purchases set
      supplier_id=case when p_patch?'supplier_id' then (p_patch->>'supplier_id')::uuid else supplier_id end,
      supplier_invoice_number=case when p_patch?'supplier_invoice_number' then p_patch->>'supplier_invoice_number' else supplier_invoice_number end,
      due_date=case when p_patch?'due_date' then nullif(p_patch->>'due_date','')::date else due_date end,
      notes=case when p_patch?'notes' then p_patch->>'notes' else notes end
    where id=p_entity_id and tenant_id=p_tenant_id;
    if p_patch?'items' then
      if exists(select 1 from public.purchase_returns where purchase_id=p_entity_id) then raise exception 'Item/value edits are blocked after a return. Use Purchase Return/new bill.';end if;
      select coalesce(sum(amount),0) into v_paid from public.purchase_payments where purchase_id=p_entity_id;
      perform private.v4_reverse_source_journal(p_tenant_id,'purchase',p_entity_id,'purchase_edit_reverse','Admin correction purchase');
      update public.journal_entries set status='reversed' where tenant_id=p_tenant_id and source_type='purchase' and source_id=p_entity_id and status='posted';
      for x in select value from jsonb_array_elements(p_patch->'items') loop
        select quantity,unit_cost,discount_amount,tax_rate into old_qty,new_price,new_disc,new_tax from public.purchase_items where id=(x->>'item_id')::uuid and purchase_id=p_entity_id for update;
        if old_qty is null then raise exception 'Purchase item not found';end if;
        new_qty:=coalesce(nullif(x->>'quantity','')::numeric,old_qty);if new_qty<=0 then raise exception 'Quantity must be positive. Use Purchase Return/Void to remove an item.';end if;
        new_price:=coalesce(nullif(x->>'unit_cost','')::numeric,new_price);new_disc:=coalesce(nullif(x->>'discount_amount','')::numeric,new_disc);new_tax:=coalesce(nullif(x->>'tax_rate','')::numeric,new_tax);
        delta:=new_qty-old_qty;
        if abs(delta)>0.0001 and exists(select 1 from public.product_variants pv join public.products p on p.id=pv.product_id where pv.id=(select variant_id from public.purchase_items where id=(x->>'item_id')::uuid) and p.item_type='stock') then
          if delta<0 and coalesce((select quantity-reserved_quantity-damaged_quantity-quarantine_quantity from public.location_stock_balances where tenant_id=p_tenant_id and location_id=v_loc and variant_id=(select variant_id from public.purchase_items where id=(x->>'item_id')::uuid)),0)<abs(delta) then raise exception 'Cannot reduce purchase because stock has already been consumed';end if;
          perform public.inventory_adjust_stock(p_tenant_id,(select variant_id from public.purchase_items where id=(x->>'item_id')::uuid),delta,'Admin purchase correction');
          perform private.v4_location_stock_apply(p_tenant_id,v_loc,(select variant_id from public.purchase_items where id=(x->>'item_id')::uuid),delta,'adjustment','purchase',p_entity_id,null,'Platform Admin correction • '||trim(p_reason),null,false);
        end if;
        new_sub:=round(new_qty*new_price,2);new_taxable:=greatest(new_sub-new_disc,0);new_tax_amount:=round(new_taxable*new_tax/100.0,2);new_line:=new_taxable+new_tax_amount;
        update public.purchase_items set quantity=new_qty,unit_cost=new_price,discount_amount=new_disc,tax_rate=new_tax,subtotal=new_sub,taxable_amount=new_taxable,tax_amount=new_tax_amount,line_total=new_line where id=(x->>'item_id')::uuid and purchase_id=p_entity_id;
      end loop;
      update public.purchases p set subtotal=q.subtotal,discount_total=q.discount_total,taxable_total=q.taxable_total,tax_total=q.tax_total,grand_total=q.line_total+p.additional_charges
      from (select purchase_id,sum(subtotal) subtotal,sum(discount_amount) discount_total,sum(taxable_amount) taxable_total,sum(tax_amount) tax_total,sum(line_total) line_total from public.purchase_items where purchase_id=p_entity_id group by purchase_id) q where p.id=q.purchase_id;
      if v_paid>(select grand_total from public.purchases where id=p_entity_id)+0.005 then raise exception 'Corrected total would be below payments already made';end if;
      perform private.v4_accounting_post_document(p_tenant_id,'purchase',p_entity_id);
    end if;
  elsif v_type='expense' then
    perform private.v4_reverse_source_journal(p_tenant_id,'expense',p_entity_id,'expense_edit_reverse','Admin correction expense');
    update public.journal_entries set status='reversed' where tenant_id=p_tenant_id and source_type='expense' and source_id=p_entity_id and status='posted';
    update public.expenses set
      expense_date=case when p_patch?'expense_date' then (p_patch->>'expense_date')::date else expense_date end,
      payee=case when p_patch?'payee' then p_patch->>'payee' else payee end,
      description=case when p_patch?'description' then p_patch->>'description' else description end,
      total_amount=case when p_patch?'total_amount' then (p_patch->>'total_amount')::numeric else total_amount end,
      tax_amount=case when p_patch?'tax_amount' then (p_patch->>'tax_amount')::numeric else tax_amount end,
      payment_method=case when p_patch?'payment_method' then p_patch->>'payment_method' else payment_method end,
      updated_at=now()
    where id=p_entity_id and tenant_id=p_tenant_id;
    perform private.v4_accounting_post_document(p_tenant_id,'expense',p_entity_id);
  else raise exception 'Unsupported entity type';end if;

  v_after:=public.platform_transaction_detail_v45(p_tenant_id,v_type,p_entity_id);
  insert into public.transaction_corrections(tenant_id,entity_type,entity_id,correction_type,reason,created_by,metadata)
  values(p_tenant_id,v_type,p_entity_id,'edit',trim(p_reason),auth.uid(),jsonb_build_object('before',v_before,'patch',p_patch,'after',v_after,'platform_admin',true));
  perform private.platform_audit_write('transaction.correct',v_type,p_entity_id::text,p_tenant_id,jsonb_build_object('reason',trim(p_reason),'patch',p_patch));
  return v_after;
end $$;
grant execute on function public.platform_transaction_correct_v45(uuid,text,uuid,jsonb,text) to authenticated;

commit;
select 'THQ V4.5 admin transaction editor ready' as status;
