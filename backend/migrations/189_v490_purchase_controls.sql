-- THQ ERP v4.9.0 Build 20 — Purchasing operational controls and reversals.
begin;

create or replace function public.goods_receipt_cancel_v490(
  p_tenant_id uuid,p_goods_receipt_id uuid,p_reason text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare g public.goods_receipts_v484%rowtype;begin
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Cancellation reason is required';end if;
  select * into g from public.goods_receipts_v484 where tenant_id=p_tenant_id and id=p_goods_receipt_id for update;
  if not found then raise exception 'GRN not found';end if;
  perform private.purchasing_v484_access(p_tenant_id,g.location_id,true);
  if g.status='cancelled' then return jsonb_build_object('success',true,'goods_receipt_id',g.id,'status','cancelled','idempotent',true);end if;
  if g.status<>'draft' then raise exception 'Only Draft GRNs can be cancelled. Posted receipts require a controlled purchase return/reversal so stock traceability is preserved';end if;
  update public.goods_receipts_v484 set status='cancelled',cancelled_by=auth.uid(),cancelled_at=now(),notes=concat_ws(E'\n',notes,'Cancelled: '||trim(p_reason)),updated_at=now() where id=g.id;
  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','goods_receipt',g.id::text,'cancel');
  return jsonb_build_object('success',true,'goods_receipt_id',g.id,'grn_number',g.grn_number,'status','cancelled');
end $$;
grant execute on function public.goods_receipt_cancel_v490(uuid,uuid,text) to authenticated;

create or replace function public.purchase_invoice_void_v490(
  p_tenant_id uuid,p_purchase_invoice_id uuid,p_reason text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare i public.purchase_invoices_v484%rowtype;li record;v_po_status text;v_new_po_status text;v_has_received boolean;v_complete_received boolean;begin
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Void reason is required';end if;
  select * into i from public.purchase_invoices_v484 where tenant_id=p_tenant_id and id=p_purchase_invoice_id for update;
  if not found then raise exception 'Purchase Invoice not found';end if;
  perform private.purchasing_v484_access(p_tenant_id,i.location_id,true);
  if i.status='void' then return jsonb_build_object('success',true,'purchase_invoice_id',i.id,'status','void','idempotent',true);end if;
  if i.status not in('draft','posted') then raise exception 'Only Draft or unpaid Posted invoices can be voided';end if;
  if coalesce(i.paid_total,0)>0.005 or exists(
    select 1 from public.supplier_payment_allocations_v484 a
    join public.supplier_payments_v484 p on p.id=a.supplier_payment_id
    where a.purchase_invoice_id=i.id and p.status='posted'
  ) then raise exception 'Invoice has supplier payments. Void/reverse those payments first';end if;

  if i.status='posted' then
    update public.journal_entries set status='reversed'
    where tenant_id=p_tenant_id and source_type='purchase_invoice_v484' and source_id=i.id and status='posted';
    insert into public.supplier_ledger_entries_v484(
      tenant_id,supplier_id,location_id,entry_date,entry_type,source_id,reference_number,description,debit,credit,created_by
    ) values(
      p_tenant_id,i.supplier_id,i.location_id,current_date,'void',i.id,i.invoice_number,
      'Void purchase invoice: '||trim(p_reason),0,i.grand_total,auth.uid()
    ) on conflict(tenant_id,entry_type,source_id) do nothing;
    for li in select purchase_order_item_id,sum(quantity) qty from public.purchase_invoice_items_v484 where purchase_invoice_id=i.id group by purchase_order_item_id loop
      update public.purchase_order_items_v480
      set invoiced_quantity=greatest(invoiced_quantity-li.qty,0)
      where id=li.purchase_order_item_id;
    end loop;
  end if;

  update public.purchase_invoices_v484
  set status='void',balance_due=0,updated_at=now(),notes=concat_ws(E'\n',notes,'Voided: '||trim(p_reason))
  where id=i.id;

  if i.purchase_order_id is not null then
    select status into v_po_status from public.purchase_orders_v480 where id=i.purchase_order_id for update;
    select exists(select 1 from public.purchase_order_items_v480 where purchase_order_id=i.purchase_order_id and received_quantity>0.000001),
           not exists(select 1 from public.purchase_order_items_v480 where purchase_order_id=i.purchase_order_id and received_quantity+0.000001<quantity)
    into v_has_received,v_complete_received;
    v_new_po_status:=case when v_complete_received then 'received' when v_has_received then 'partially_received' else case when v_po_status='draft' then 'draft' else 'ordered' end end;
    if v_po_status='closed' or v_po_status='received' then
      update public.purchase_orders_v480 set status=v_new_po_status,closed_at=null,updated_at=now() where id=i.purchase_order_id;
      insert into public.purchase_order_status_history_v480(purchase_order_id,from_status,to_status,reason,changed_by)
      values(i.purchase_order_id,v_po_status,v_new_po_status,'Reopened because invoice '||i.invoice_number||' was voided',auth.uid());
    end if;
  end if;

  perform private.thq_sync_bump_v480(p_tenant_id,'accounting','purchase_invoice',i.id::text,'void');
  return jsonb_build_object('success',true,'purchase_invoice_id',i.id,'invoice_number',i.invoice_number,'status','void','purchase_order_status',v_new_po_status);
end $$;
grant execute on function public.purchase_invoice_void_v490(uuid,uuid,text) to authenticated;

create or replace function public.supplier_payment_create_v490(
  p_tenant_id uuid,p_location_id uuid,p_supplier_id uuid,p_payment_date date,p_amount numeric,p_payment_method text,
  p_allocations jsonb default '[]'::jsonb,p_reference_number text default null,p_notes text default null,p_device_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v jsonb;v_payment uuid;v_no text;v_shift uuid;begin
  if p_device_id is not null and not exists(
    select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.location_id=p_location_id and d.status='active'
  ) then raise exception 'Invalid device for supplier payment location';end if;
  v:=public.supplier_payment_create_v484(p_tenant_id,p_location_id,p_supplier_id,p_payment_date,p_amount,p_payment_method,p_allocations,p_reference_number,p_notes);
  v_payment:=nullif(v->>'supplier_payment_id','')::uuid;v_no:=v->>'payment_number';
  if v_payment is not null and p_device_id is not null and lower(trim(coalesce(p_payment_method,'')))='cash' then
    select id into v_shift from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_device_id and status='open' order by opened_at desc limit 1;
    if v_shift is not null and not exists(select 1 from public.cash_drawer_movements where reference_type='supplier_payment_v490' and reference_id=v_payment) then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(p_tenant_id,v_shift,'cash_out',-abs(p_amount),'supplier_payment_v490',v_payment,v_no,'Supplier cash payment',auth.uid());
    end if;
  end if;
  return v||jsonb_build_object('payment_engine','v4.9.0');
end $$;
grant execute on function public.supplier_payment_create_v490(uuid,uuid,uuid,date,numeric,text,jsonb,text,text,uuid) to authenticated;

create or replace function public.supplier_payment_void_v490(
  p_tenant_id uuid,p_supplier_payment_id uuid,p_reason text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.supplier_payments_v484%rowtype;a record;v_device uuid;v_shift uuid;begin
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Void reason is required';end if;
  select * into p from public.supplier_payments_v484 where tenant_id=p_tenant_id and id=p_supplier_payment_id for update;
  if not found then raise exception 'Supplier payment not found';end if;
  perform private.purchasing_v484_access(p_tenant_id,p.location_id,true);
  if p.status='void' then return jsonb_build_object('success',true,'supplier_payment_id',p.id,'status','void','idempotent',true);end if;

  update public.supplier_payments_v484 set status='void',voided_by=auth.uid(),voided_at=now(),void_reason=trim(p_reason) where id=p.id;
  for a in select purchase_invoice_id from public.supplier_payment_allocations_v484 where supplier_payment_id=p.id loop
    perform private.v484_refresh_invoice_payment_status(a.purchase_invoice_id);
  end loop;
  update public.journal_entries set status='reversed'
  where tenant_id=p_tenant_id and source_type='supplier_payment_v484' and source_id=p.id and status='posted';
  insert into public.supplier_ledger_entries_v484(
    tenant_id,supplier_id,location_id,entry_date,entry_type,source_id,reference_number,description,debit,credit,created_by
  ) values(
    p_tenant_id,p.supplier_id,p.location_id,current_date,'void',p.id,p.payment_number,
    'Void supplier payment: '||trim(p_reason),p.amount,0,auth.uid()
  ) on conflict(tenant_id,entry_type,source_id) do nothing;

  select d.id into v_device
  from public.business_devices d join public.cashier_shifts s on s.device_id=d.id and s.tenant_id=p_tenant_id and s.status='open'
  where d.tenant_id=p_tenant_id and d.location_id=p.location_id and d.status='active'
    and exists(select 1 from public.cash_drawer_movements m where m.shift_id=s.id and m.reference_type='supplier_payment_v490' and m.reference_id=p.id)
  order by s.opened_at desc limit 1;
  if v_device is not null and lower(p.payment_method)='cash' then
    select id into v_shift from public.cashier_shifts where tenant_id=p_tenant_id and device_id=v_device and status='open' order by opened_at desc limit 1;
    if v_shift is not null and not exists(select 1 from public.cash_drawer_movements where reference_type='supplier_payment_void_v490' and reference_id=p.id) then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(p_tenant_id,v_shift,'cash_in',abs(p.amount),'supplier_payment_void_v490',p.id,p.payment_number,'Supplier payment void: '||trim(p_reason),auth.uid());
    end if;
  end if;
  perform private.thq_sync_bump_v480(p_tenant_id,'accounting','supplier_payment',p.id::text,'void');
  return jsonb_build_object('success',true,'supplier_payment_id',p.id,'payment_number',p.payment_number,'status','void');
end $$;
grant execute on function public.supplier_payment_void_v490(uuid,uuid,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(189,'4.9.0','Purchase Controls','Draft GRN cancellation, controlled Purchase Invoice void/reopen, supplier payment cash-drawer integration and payment reversal.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 20 migration 189 purchase controls applied' as status;
