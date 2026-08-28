-- THQ V4.5
-- Admin party selectors and audited payment-method/reference corrections.
begin;

create or replace function public.platform_parties_list_v45(p_tenant_id uuid,p_party_type text,p_query text default null)
returns table(id uuid,name text,phone text,reference text)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required';end if;
  if p_party_type='customer' then
    return query select c.id,c.name::text,coalesce(c.phone,'')::text,coalesce(c.tracking_code,'')::text from public.customers c
      where c.tenant_id=p_tenant_id and (trim(coalesce(p_query,''))='' or lower(c.name) like q or lower(coalesce(c.phone,'')) like q or lower(coalesce(c.tracking_code,'')) like q)
      order by c.name limit 250;
  elsif p_party_type='supplier' then
    return query select s.id,s.name::text,coalesce(s.phone,'')::text,coalesce(s.tracking_code,'')::text from public.suppliers s
      where s.tenant_id=p_tenant_id and (trim(coalesce(p_query,''))='' or lower(s.name) like q or lower(coalesce(s.phone,'')) like q or lower(coalesce(s.tracking_code,'')) like q)
      order by s.name limit 250;
  else raise exception 'Invalid party type';end if;
end $$;
grant execute on function public.platform_parties_list_v45(uuid,text,text) to authenticated;

create or replace function public.platform_payment_correct_v45(
  p_tenant_id uuid,p_entity_type text,p_payment_id uuid,p_payment_method text,p_reference_number text,p_reason text
) returns void
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_old_method text;v_amount numeric;v_paid_at timestamptz;v_entity uuid;v_loc uuid;v_ref text;v_party uuid;v_lines jsonb;v_shift uuid;begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('technical_admin') then raise exception 'Super/technical admin required';end if;
  if trim(coalesce(p_reason,''))='' then raise exception 'Correction reason is required';end if;
  if lower(coalesce(p_payment_method,'')) not in('cash','bank','upi','card','credit_card','debit_card') then raise exception 'Unsupported payment method';end if;

  if p_entity_type='sale' then
    select sp.payment_method,sp.amount,sp.paid_at,sp.sale_id,s.sale_number,s.customer_id,o.location_id
      into v_old_method,v_amount,v_paid_at,v_entity,v_ref,v_party,v_loc
    from public.sale_payments sp join public.sales s on s.id=sp.sale_id
    left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id
    where sp.id=p_payment_id and s.tenant_id=p_tenant_id;
    if v_entity is null then raise exception 'Sale payment not found';end if;
    perform private.v4_reverse_source_journal(p_tenant_id,'sale_payment',p_payment_id,'sale_payment_edit_reverse','Admin payment correction');
    update public.journal_entries set status='reversed' where tenant_id=p_tenant_id and source_type='sale_payment' and source_id=p_payment_id and status='posted';
    update public.sale_payments set payment_method=lower(p_payment_method),reference_number=nullif(trim(coalesce(p_reference_number,'')),'') where id=p_payment_id;
    v_lines:=jsonb_build_array(
      jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,p_payment_method),'debit',v_amount,'credit',0,'party_type','customer','party_id',v_party,'description','Customer receipt • corrected'),
      jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_receivable'),'debit',0,'credit',v_amount,'party_type','customer','party_id',v_party,'description','Receivable settlement • corrected')
    );
    perform private.v4_journal_create(p_tenant_id,v_loc,coalesce(v_paid_at::date,current_date),'Customer receipt • '||v_ref,'sale_payment',p_payment_id,v_ref,v_lines);
    if lower(coalesce(v_old_method,''))='cash' and lower(p_payment_method)<>'cash' then
      update public.cash_drawer_movements set amount=0,note=coalesce(note,'')||' • Corrected from cash to '||lower(p_payment_method)
       where tenant_id=p_tenant_id and reference_type='sale_payment' and reference_id=p_payment_id;
    elsif lower(coalesce(v_old_method,''))<>'cash' and lower(p_payment_method)='cash' then
      select cs.id into v_shift from public.cashier_shifts cs join public.document_origins o on o.device_id=cs.device_id
      where o.entity_type='sale' and o.entity_id=v_entity and cs.tenant_id=p_tenant_id and cs.opened_at<=coalesce(v_paid_at,now()) and (cs.closed_at is null or cs.closed_at>=coalesce(v_paid_at,now())) order by cs.opened_at desc limit 1;
      if v_shift is not null and not exists(select 1 from public.cash_drawer_movements where reference_type='sale_payment' and reference_id=p_payment_id and amount<>0) then
        insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
        values(p_tenant_id,v_shift,'sale',v_amount,'sale_payment',p_payment_id,v_ref,'Admin corrected payment to cash',auth.uid());
      end if;
    end if;
  elsif p_entity_type='purchase' then
    select pp.payment_method,pp.amount,pp.paid_at,pp.purchase_id,p.purchase_number,p.supplier_id,o.location_id
      into v_old_method,v_amount,v_paid_at,v_entity,v_ref,v_party,v_loc
    from public.purchase_payments pp join public.purchases p on p.id=pp.purchase_id
    left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id
    where pp.id=p_payment_id and p.tenant_id=p_tenant_id;
    if v_entity is null then raise exception 'Purchase payment not found';end if;
    perform private.v4_reverse_source_journal(p_tenant_id,'purchase_payment',p_payment_id,'purchase_payment_edit_reverse','Admin payment correction');
    update public.journal_entries set status='reversed' where tenant_id=p_tenant_id and source_type='purchase_payment' and source_id=p_payment_id and status='posted';
    update public.purchase_payments set payment_method=lower(p_payment_method),reference_number=nullif(trim(coalesce(p_reference_number,'')),'') where id=p_payment_id;
    v_lines:=jsonb_build_array(
      jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_payable'),'debit',v_amount,'credit',0,'party_type','supplier','party_id',v_party,'description','Payable settlement • corrected'),
      jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,p_payment_method),'debit',0,'credit',v_amount,'party_type','supplier','party_id',v_party,'description','Supplier payment • corrected')
    );
    perform private.v4_journal_create(p_tenant_id,v_loc,coalesce(v_paid_at::date,current_date),'Supplier payment • '||v_ref,'purchase_payment',p_payment_id,v_ref,v_lines);
  else raise exception 'Payment correction supports sale or purchase';end if;

  insert into public.transaction_corrections(tenant_id,entity_type,entity_id,correction_type,reason,created_by,metadata)
  values(p_tenant_id,p_entity_type,v_entity,'edit',trim(p_reason),auth.uid(),jsonb_build_object('payment_id',p_payment_id,'old_method',v_old_method,'new_method',lower(p_payment_method),'reference_number',p_reference_number));
  perform private.platform_audit_write('transaction.payment.correct',p_entity_type,v_entity::text,p_tenant_id,jsonb_build_object('payment_id',p_payment_id,'old_method',v_old_method,'new_method',lower(p_payment_method),'reason',trim(p_reason)));
end $$;
grant execute on function public.platform_payment_correct_v45(uuid,text,uuid,text,text,text) to authenticated;

commit;
select 'THQ V4.5 admin payment correction ready' as status;
