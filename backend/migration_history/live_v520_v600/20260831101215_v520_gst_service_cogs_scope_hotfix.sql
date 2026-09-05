create or replace function private.gst_snapshot_document_journal_lines_v520(p_tenant_id uuid,p_snapshot_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path='public','private','pg_temp'
as $$
declare
  s public.gst_document_snapshots_v520%rowtype;
  v_lines jsonb:='[]'::jsonb;
  v_tax_lines jsonb;
  v_delta numeric;
  v_total numeric;
  v_paid numeric:=0;
  v_balance numeric;
  v_cost numeric:=0;
  v_base_stock numeric:=0;
  v_base_expense numeric:=0;
  v_party uuid;
  v_origin_time timestamptz;
  v_method record;
  v_payment_acc text;
  v_original_total numeric;
  v_previous_returns numeric;
  v_outstanding numeric;
  v_reduce numeric;
  v_credit numeric;
begin
  select * into s from public.gst_document_snapshots_v520 where id=p_snapshot_id and tenant_id=p_tenant_id;
  if not found then raise exception 'Authoritative GST snapshot not found'; end if;
  if abs(coalesce(s.additional_charges,0))>0.0001 then raise exception 'GST journal composer does not accept unclassified additional charges'; end if;
  v_total:=round(s.grand_total,2);
  v_delta:=round(coalesce(s.calculation_rounding,0)+coalesce(s.round_off,0),2);
  v_tax_lines:=private.gst_snapshot_tax_journal_lines_v520(p_tenant_id,p_snapshot_id);

  if s.source_type='sale' then
    select x.customer_id into v_party from public.sales x where x.id=s.source_id and x.tenant_id=p_tenant_id and x.status='posted';
    if v_party is null then raise exception 'Posted Sale source not found'; end if;
    select created_at into v_origin_time from public.document_origins where tenant_id=p_tenant_id and entity_type='sale' and entity_id=s.source_id order by created_at limit 1;
    for v_method in
      select lower(coalesce(payment_method,'cash')) method,round(sum(amount),2) amount
      from public.sale_payments
      where tenant_id=p_tenant_id and sale_id=s.source_id and (v_origin_time is null or created_at<=v_origin_time)
      group by lower(coalesce(payment_method,'cash'))
    loop
      v_paid:=v_paid+v_method.amount;
      v_payment_acc:='payment.'||case when v_method.method='cash' then 'cash' when v_method.method='upi' then 'upi' when v_method.method in('card','credit_card','debit_card') then 'card' else 'bank' end;
      v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,v_payment_acc,v_method.amount,'debit','Sale receipt','customer',v_party));
    end loop;
    v_paid:=least(round(v_paid,2),v_total);
    v_balance:=round(v_total-v_paid,2);
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'accounts_receivable',v_balance,'debit','Customer receivable','customer',v_party));
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'sales_revenue',round(s.taxable_total,2),'credit','Sales revenue','customer',v_party));
    v_lines:=v_lines||v_tax_lines;
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_rounding_line_v520(p_tenant_id,v_delta,'sale','GST sale calculation/document round off'));

    -- COGS and Inventory Asset belong only to physical stock lines.
    select round(coalesce(sum(coalesce(si.cost_total,0)) filter(where p.item_type='stock'),0),2)
      into v_cost
    from public.sale_items si
    join public.product_variants pv on pv.id=si.variant_id and pv.tenant_id=si.tenant_id
    join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id
    where si.tenant_id=p_tenant_id and si.sale_id=s.source_id;
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'cogs',v_cost,'debit','Cost of goods sold'));
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'inventory_asset',v_cost,'credit','Inventory issued'));

  elsif s.source_type='purchase' then
    select x.supplier_id into v_party from public.purchases x where x.id=s.source_id and x.tenant_id=p_tenant_id and x.status='posted';
    if v_party is null then raise exception 'Posted Purchase source not found'; end if;
    select created_at into v_origin_time from public.document_origins where tenant_id=p_tenant_id and entity_type='purchase' and entity_id=s.source_id order by created_at limit 1;
    select round(coalesce(sum(ls.taxable_value) filter(where p.item_type='stock'),0),2),
           round(coalesce(sum(ls.taxable_value) filter(where p.item_type<>'stock'),0),2)
      into v_base_stock,v_base_expense
    from public.gst_document_line_snapshots_v520 ls
    join public.purchase_items pi on pi.id=ls.source_line_id and pi.purchase_id=s.source_id
    join public.product_variants pv on pv.id=pi.variant_id
    join public.products p on p.id=pv.product_id
    where ls.snapshot_id=s.id;
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'inventory_asset',v_base_stock,'debit','Purchased stock at GST taxable value','supplier',v_party));
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'purchase_expense',v_base_expense,'debit','Purchased service/non-stock at GST taxable value','supplier',v_party));
    v_lines:=v_lines||v_tax_lines;
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_rounding_line_v520(p_tenant_id,v_delta,'purchase','GST purchase calculation/document round off'));
    for v_method in
      select lower(coalesce(payment_method,'cash')) method,round(sum(amount),2) amount
      from public.purchase_payments
      where tenant_id=p_tenant_id and purchase_id=s.source_id and (v_origin_time is null or created_at<=v_origin_time)
      group by lower(coalesce(payment_method,'cash'))
    loop
      v_paid:=v_paid+v_method.amount;
      v_payment_acc:='payment.'||case when v_method.method='cash' then 'cash' when v_method.method='upi' then 'upi' when v_method.method in('card','credit_card','debit_card') then 'card' else 'bank' end;
      v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,v_payment_acc,v_method.amount,'credit','Supplier payment','supplier',v_party));
    end loop;
    v_paid:=least(round(v_paid,2),v_total);
    v_balance:=round(v_total-v_paid,2);
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'accounts_payable',v_balance,'credit','Supplier payable','supplier',v_party));

  elsif s.source_type='purchase_invoice_v484' then
    select x.supplier_id into v_party from public.purchase_invoices_v484 x where x.id=s.source_id and x.tenant_id=p_tenant_id and x.status in('draft','posted','part_paid','paid');
    if v_party is null then raise exception 'Purchase Invoice source not found'; end if;
    select round(coalesce(sum(ls.taxable_value) filter(where p.item_type='stock'),0),2),
           round(coalesce(sum(ls.taxable_value) filter(where p.item_type<>'stock'),0),2)
      into v_base_stock,v_base_expense
    from public.gst_document_line_snapshots_v520 ls
    join public.purchase_invoice_items_v484 ii on ii.id=ls.source_line_id and ii.purchase_invoice_id=s.source_id
    join public.product_variants pv on pv.id=ii.variant_id
    join public.products p on p.id=pv.product_id
    where ls.snapshot_id=s.id;
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'inventory_asset',v_base_stock,'debit','Purchase invoice stock value','supplier',v_party));
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'purchase_expense',v_base_expense,'debit','Purchase invoice service/non-stock value','supplier',v_party));
    v_lines:=v_lines||v_tax_lines;
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_rounding_line_v520(p_tenant_id,v_delta,'purchase','GST purchase invoice calculation/document round off'));
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'accounts_payable',v_total,'credit','Supplier payable','supplier',v_party));

  elsif s.source_type='sales_return' then
    select sa.customer_id,sa.grand_total into v_party,v_original_total
    from public.sales_returns sr join public.sales sa on sa.id=sr.sale_id and sa.tenant_id=sr.tenant_id
    where sr.id=s.source_id and sr.tenant_id=p_tenant_id;
    if v_party is null then raise exception 'Sales Return source not found'; end if;
    select round(coalesce(sum(amount),0),2) into v_paid
    from public.sale_payments p join public.sales_returns sr on sr.sale_id=p.sale_id where sr.id=s.source_id;
    select round(coalesce(sum(r2.grand_total),0),2) into v_previous_returns
    from public.sales_returns r1 join public.sales_returns r2 on r2.sale_id=r1.sale_id and r2.id<>r1.id and r2.created_at<=r1.created_at and r2.refund_status<>'waived'
    where r1.id=s.source_id;
    v_outstanding:=greatest(round(v_original_total-v_paid-v_previous_returns,2),0);
    v_reduce:=least(v_total,v_outstanding);
    v_credit:=greatest(round(v_total-v_reduce,2),0);
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'sales_revenue',round(s.taxable_total,2),'debit','Sales return revenue reversal','customer',v_party));
    v_lines:=v_lines||v_tax_lines;
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_rounding_line_v520(p_tenant_id,v_delta,'sales_return','GST sales return calculation/document round off'));
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'accounts_receivable',v_reduce,'credit','Reduce customer receivable','customer',v_party));
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'customer_credits',v_credit,'credit','Customer return credit / refund due','customer',v_party));

    -- Reverse COGS/inventory only for returned physical stock lines.
    select round(coalesce(sum(coalesce(si.cost_total,0)*(ri.quantity/nullif(si.quantity,0))) filter(where p.item_type='stock'),0),2)
      into v_cost
    from public.sales_return_items ri
    join public.sale_items si on si.id=ri.sale_item_id
    join public.product_variants pv on pv.id=si.variant_id and pv.tenant_id=si.tenant_id
    join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id
    where ri.sales_return_id=s.source_id;
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'inventory_asset',v_cost,'debit','Returned inventory restored'));
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'cogs',v_cost,'credit','COGS reversed for returned goods'));

  elsif s.source_type='purchase_return' then
    select pu.supplier_id,pu.grand_total into v_party,v_original_total
    from public.purchase_returns pr join public.purchases pu on pu.id=pr.purchase_id and pu.tenant_id=pr.tenant_id
    where pr.id=s.source_id and pr.tenant_id=p_tenant_id;
    if v_party is null then raise exception 'Purchase Return source not found'; end if;
    select round(coalesce(sum(amount),0),2) into v_paid
    from public.purchase_payments p join public.purchase_returns pr on pr.purchase_id=p.purchase_id where pr.id=s.source_id;
    select round(coalesce(sum(r2.grand_total),0),2) into v_previous_returns
    from public.purchase_returns r1 join public.purchase_returns r2 on r2.purchase_id=r1.purchase_id and r2.id<>r1.id and r2.created_at<=r1.created_at and r2.credit_status<>'waived'
    where r1.id=s.source_id;
    v_outstanding:=greatest(round(v_original_total-v_paid-v_previous_returns,2),0);
    v_reduce:=least(v_total,v_outstanding);
    v_credit:=greatest(round(v_total-v_reduce,2),0);
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'accounts_payable',v_reduce,'debit','Reduce supplier payable','supplier',v_party));
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'supplier_credits',v_credit,'debit','Supplier return credit / refund due','supplier',v_party));
    select round(coalesce(sum(ls.taxable_value) filter(where p.item_type='stock'),0),2),
           round(coalesce(sum(ls.taxable_value) filter(where p.item_type<>'stock'),0),2)
      into v_base_stock,v_base_expense
    from public.gst_document_line_snapshots_v520 ls
    join public.purchase_return_items ri on ri.id=ls.source_line_id and ri.purchase_return_id=s.source_id
    join public.product_variants pv on pv.id=ri.variant_id
    join public.products p on p.id=pv.product_id
    where ls.snapshot_id=s.id;
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'inventory_asset',v_base_stock,'credit','Purchase return stock value reversal','supplier',v_party));
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_gl_line_v520(p_tenant_id,'purchase_expense',v_base_expense,'credit','Purchase return service/non-stock reversal','supplier',v_party));
    v_lines:=v_lines||v_tax_lines;
    v_lines:=private.gst_append_nonnull_line_v520(v_lines,private.gst_rounding_line_v520(p_tenant_id,v_delta,'purchase_return','GST purchase return calculation/document round off'));
  else
    raise exception 'GST document journal composer does not support source type %',s.source_type;
  end if;
  return v_lines;
end
$$;