-- FLEXI ERP V4 automatic journals, accounting registers and search.
begin;

create or replace function private.v4_accounting_post_document(p_tenant_id uuid,p_entity_type text,p_entity_id uuid)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_loc uuid;v_total numeric;v_tax numeric;v_net numeric;v_cost numeric:=0;v_paid numeric:=0;v_method text:='cash';v_date date;v_ref text;v_party uuid;v_lines jsonb:='[]'::jsonb;v_pay_account uuid;begin
  select location_id into v_loc from public.document_origins where tenant_id=p_tenant_id and entity_type=p_entity_type and entity_id=p_entity_id;
  if p_entity_type='sale' then
    select grand_total,tax_total,greatest(grand_total-tax_total,0),cost_total,sale_date,sale_number,customer_id into v_total,v_tax,v_net,v_cost,v_date,v_ref,v_party from public.sales where id=p_entity_id and tenant_id=p_tenant_id;if not found then return null;end if;
    select coalesce(sum(amount),0),(array_agg(payment_method order by paid_at,id))[1] into v_paid,v_method from public.sale_payments where sale_id=p_entity_id;
    v_paid:=least(coalesce(v_paid,0),v_total);v_pay_account:=private.v4_payment_account(p_tenant_id,v_method);
    if v_paid>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_pay_account,'debit',v_paid,'credit',0,'party_type','customer','party_id',v_party,'description','Sale receipt'));end if;
    if v_total-v_paid>0.005 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_receivable'),'debit',v_total-v_paid,'credit',0,'party_type','customer','party_id',v_party,'description','Customer receivable'));end if;
    if v_net>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'sales_revenue'),'debit',0,'credit',v_net,'party_type','customer','party_id',v_party,'description','Sales revenue'));end if;
    if v_tax>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'output_gst'),'debit',0,'credit',v_tax,'description','Output GST'));end if;
    if coalesce(v_cost,0)>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'cogs'),'debit',v_cost,'credit',0,'description','Cost of goods sold'),jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'inventory_asset'),'debit',0,'credit',v_cost,'description','Inventory issued'));end if;
    return private.v4_journal_create(p_tenant_id,v_loc,v_date,'Sale '||v_ref,'sale',p_entity_id,v_ref,v_lines);
  elsif p_entity_type='purchase' then
    select grand_total,tax_total,greatest(grand_total-tax_total,0),purchase_date,purchase_number,supplier_id into v_total,v_tax,v_net,v_date,v_ref,v_party from public.purchases where id=p_entity_id and tenant_id=p_tenant_id;if not found then return null;end if;
    select coalesce(sum(amount),0),(array_agg(payment_method order by paid_at,id))[1] into v_paid,v_method from public.purchase_payments where purchase_id=p_entity_id;
    v_paid:=least(coalesce(v_paid,0),v_total);v_pay_account:=private.v4_payment_account(p_tenant_id,v_method);
    if v_net>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'inventory_asset'),'debit',v_net,'credit',0,'party_type','supplier','party_id',v_party,'description','Purchase / inventory'));end if;
    if v_tax>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'input_gst'),'debit',v_tax,'credit',0,'description','Input GST'));end if;
    if v_paid>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_pay_account,'debit',0,'credit',v_paid,'party_type','supplier','party_id',v_party,'description','Supplier payment'));end if;
    if v_total-v_paid>0.005 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_payable'),'debit',0,'credit',v_total-v_paid,'party_type','supplier','party_id',v_party,'description','Supplier payable'));end if;
    return private.v4_journal_create(p_tenant_id,v_loc,v_date,'Purchase '||v_ref,'purchase',p_entity_id,v_ref,v_lines);
  elsif p_entity_type='expense' then
    select total_amount,tax_amount,greatest(total_amount-tax_amount,0),expense_date,expense_number into v_total,v_tax,v_net,v_date,v_ref from public.expenses where id=p_entity_id and tenant_id=p_tenant_id;if not found then return null;end if;
    select payment_method into v_method from public.expenses where id=p_entity_id;v_pay_account:=private.v4_payment_account(p_tenant_id,v_method);
    v_lines:=jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'operating_expense'),'debit',v_net,'credit',0,'description','Operating expense'));
    if v_tax>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'input_gst'),'debit',v_tax,'credit',0,'description','Input GST'));end if;
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_pay_account,'debit',0,'credit',v_total,'description','Expense payment'));
    return private.v4_journal_create(p_tenant_id,v_loc,v_date,'Expense '||v_ref,'expense',p_entity_id,v_ref,v_lines);
  end if;return null;
end $$;
revoke all on function private.v4_accounting_post_document(uuid,text,uuid) from public;

create or replace function private.v4_origin_after_insert()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_shift uuid;v_cash numeric;v_ref text;v_method text;begin
  begin perform private.v4_accounting_post_document(new.tenant_id,new.entity_type,new.entity_id);exception when others then null;end;
  if new.device_id is not null then
    select id into v_shift from public.cashier_shifts where tenant_id=new.tenant_id and device_id=new.device_id and status='open' order by opened_at desc limit 1;
  end if;

  if v_shift is not null and new.entity_type='sale' then
    select coalesce(sum(amount),0),max(s.sale_number) into v_cash,v_ref
    from public.sale_payments p join public.sales s on s.id=p.sale_id
    where p.sale_id=new.entity_id and lower(coalesce(p.payment_method,''))='cash';
    if v_cash>0 and not exists(select 1 from public.cash_drawer_movements where shift_id=v_shift and reference_type='sale' and reference_id=new.entity_id) then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(new.tenant_id,v_shift,'sale',v_cash,'sale',new.entity_id,v_ref,'Cash sale',new.created_by);
    end if;
  elsif v_shift is not null and new.entity_type='expense' then
    select payment_method,total_amount,expense_number into v_method,v_cash,v_ref from public.expenses where id=new.entity_id and tenant_id=new.tenant_id;
    if lower(coalesce(v_method,''))='cash' and coalesce(v_cash,0)>0 and not exists(select 1 from public.cash_drawer_movements where shift_id=v_shift and reference_type='expense' and reference_id=new.entity_id) then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(new.tenant_id,v_shift,'expense',-abs(v_cash),'expense',new.entity_id,v_ref,'Cash expense',new.created_by);
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_v4_origin_after_insert on public.document_origins;
create trigger trg_v4_origin_after_insert after insert on public.document_origins for each row execute function private.v4_origin_after_insert();

create or replace function private.v4_sale_payment_after_insert()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_tenant uuid;v_loc uuid;v_ref text;v_customer uuid;v_lines jsonb;begin
  select s.tenant_id,s.sale_number,s.customer_id,o.location_id into v_tenant,v_ref,v_customer,v_loc from public.sales s left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id where s.id=new.sale_id;
  if v_tenant is null or v_loc is null then return new;end if;
  if exists(select 1 from public.journal_entries where tenant_id=v_tenant and source_type='sale_payment' and source_id=new.id) then return new;end if;
  v_lines:=jsonb_build_array(jsonb_build_object('account_id',private.v4_payment_account(v_tenant,new.payment_method),'debit',new.amount,'credit',0,'party_type','customer','party_id',v_customer,'description','Customer receipt'),jsonb_build_object('account_id',private.v4_account_id(v_tenant,'accounts_receivable'),'debit',0,'credit',new.amount,'party_type','customer','party_id',v_customer,'description','Receivable settlement'));
  perform private.v4_journal_create(v_tenant,v_loc,coalesce(new.paid_at::date,current_date),'Customer receipt • '||v_ref,'sale_payment',new.id,v_ref,v_lines);
  if lower(coalesce(new.payment_method,''))='cash' then
    insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
    select v_tenant,sh.id,'sale',new.amount,'sale_payment',new.id,v_ref,'Customer cash receipt',auth.uid()
    from public.document_origins o join public.cashier_shifts sh on sh.tenant_id=v_tenant and sh.device_id=o.device_id and sh.status='open'
    where o.entity_type='sale' and o.entity_id=new.sale_id
      and not exists(select 1 from public.cash_drawer_movements m where m.reference_type='sale_payment' and m.reference_id=new.id)
    limit 1;
  end if;
  return new;
end $$;
drop trigger if exists trg_v4_sale_payment_after_insert on public.sale_payments;create trigger trg_v4_sale_payment_after_insert after insert on public.sale_payments for each row execute function private.v4_sale_payment_after_insert();

create or replace function private.v4_purchase_payment_after_insert()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_tenant uuid;v_loc uuid;v_ref text;v_supplier uuid;v_lines jsonb;begin
  select p.tenant_id,p.purchase_number,p.supplier_id,o.location_id into v_tenant,v_ref,v_supplier,v_loc from public.purchases p left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id where p.id=new.purchase_id;
  if v_tenant is null or v_loc is null then return new;end if;if exists(select 1 from public.journal_entries where tenant_id=v_tenant and source_type='purchase_payment' and source_id=new.id) then return new;end if;
  v_lines:=jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(v_tenant,'accounts_payable'),'debit',new.amount,'credit',0,'party_type','supplier','party_id',v_supplier,'description','Payable settlement'),jsonb_build_object('account_id',private.v4_payment_account(v_tenant,new.payment_method),'debit',0,'credit',new.amount,'party_type','supplier','party_id',v_supplier,'description','Supplier payment'));
  perform private.v4_journal_create(v_tenant,v_loc,coalesce(new.paid_at::date,current_date),'Supplier payment • '||v_ref,'purchase_payment',new.id,v_ref,v_lines);return new;
end $$;
drop trigger if exists trg_v4_purchase_payment_after_insert on public.purchase_payments;create trigger trg_v4_purchase_payment_after_insert after insert on public.purchase_payments for each row execute function private.v4_purchase_payment_after_insert();

-- Backfill journals for historical V3 origins. Duplicate source guard makes this idempotent.
do $$ declare r record;begin for r in select tenant_id,entity_type,entity_id from public.document_origins where entity_type in('sale','purchase','expense') loop begin perform private.v4_accounting_post_document(r.tenant_id,r.entity_type,r.entity_id);exception when others then null;end;end loop;end $$;

create or replace function public.accounting_register_v4(p_tenant_id uuid,p_register text,p_from date,p_to date,p_location_id uuid default null,p_query text default null)
returns table(entry_date date,reference text,party text,description text,debit numeric,credit numeric,location_code text,user_name text,source_type text,source_id uuid)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  select j.entry_date,j.source_reference,coalesce(case when l.party_type='customer' then c.name when l.party_type='supplier' then s.name else '' end,''),coalesce(l.description,j.description),l.debit,l.credit,bl.location_code,coalesce(ul.username,''),j.source_type,j.source_id
  from public.journal_entries j join public.journal_lines l on l.journal_entry_id=j.id join public.accounting_accounts a on a.id=l.account_id
  left join public.customers c on l.party_type='customer' and c.id=l.party_id left join public.suppliers s on l.party_type='supplier' and s.id=l.party_id
  left join public.business_locations bl on bl.id=j.location_id left join public.user_login_names ul on ul.user_id=j.created_by
  where j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date between p_from and p_to
    and (p_location_id is null or j.location_id=p_location_id)
    and (p_location_id is null or private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view'))
    and (p_register='all' or (p_register='sales' and j.source_type in('sale','sale_payment','sales_return')) or (p_register='purchases' and j.source_type in('purchase','purchase_payment','purchase_return')) or (p_register='cash' and a.system_key='cash') or (p_register='bank' and a.system_key in('bank','upi','card')) or (p_register='gst' and a.system_key in('input_gst','output_gst')) or (p_register='journal' and j.source_type='manual'))
    and (
      trim(coalesce(p_query,''))=''
      or lower(coalesce(j.source_reference,'')) like q
      or lower(coalesce(j.description,'')) like q
      or lower(coalesce(c.name,'')) like q
      or lower(coalesce(s.name,'')) like q
      or lower(coalesce(a.name,'')) like q
      or exists(
        select 1 from public.sales sx
        join public.sale_items six on six.sale_id=sx.id
        join public.product_variants pvx on pvx.id=six.variant_id
        join public.products px on px.id=pvx.product_id
        where sx.tenant_id=p_tenant_id and sx.sale_number=j.source_reference
          and (lower(px.name) like q or lower(coalesce(pvx.sku,'')) like q or lower(coalesce(pvx.part_number,'')) like q)
      )
      or exists(
        select 1 from public.purchases pxh
        join public.purchase_items pix on pix.purchase_id=pxh.id
        join public.product_variants pvx on pvx.id=pix.variant_id
        join public.products prx on prx.id=pvx.product_id
        where pxh.tenant_id=p_tenant_id and pxh.purchase_number=j.source_reference
          and (lower(prx.name) like q or lower(coalesce(pvx.sku,'')) like q or lower(coalesce(pvx.part_number,'')) like q)
      )
    )
  order by j.entry_date desc,j.created_at desc;
end $$;
grant execute on function public.accounting_register_v4(uuid,text,date,date,uuid,text) to authenticated;

create or replace function public.accounting_manual_journal_v4(p_tenant_id uuid,p_location_id uuid,p_entry_date date,p_description text,p_lines jsonb)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'accounting.journal') and not private.erp_has_permission(p_tenant_id,'accounting.manage') then raise exception 'Manual journal permission required';end if;
  perform private.v4_location_access(p_tenant_id,p_location_id,'manage');return private.v4_journal_create(p_tenant_id,p_location_id,p_entry_date,trim(p_description),'manual',gen_random_uuid(),null,p_lines);
end $$;
grant execute on function public.accounting_manual_journal_v4(uuid,uuid,date,text,jsonb) to authenticated;

commit;
select 'Flexi ERP V4 automatic accounting and registers ready' as status;
