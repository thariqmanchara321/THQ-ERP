-- THQ ERP V4.7 — accounting provisioning + strict posting.
begin;

create or replace function private.v47_ensure_accounting_for_tenant(p_tenant_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if not exists(select 1 from public.tenants where id=p_tenant_id) then
    raise exception 'Tenant not found';
  end if;

  insert into public.accounting_accounts(tenant_id,code,name,account_type,system_key,is_system,description)
  select p_tenant_id,x.code,x.name,x.type,x.key,true,x.description from (values
   ('1000','Cash in Hand','asset','cash','Cash received at counters'),
   ('1010','Bank Account','asset','bank','Primary bank account'),
   ('1020','UPI Clearing','asset','upi','UPI collections/settlements'),
   ('1030','Card Clearing','asset','card','Card collections/settlements'),
   ('1100','Accounts Receivable','asset','accounts_receivable','Customer credit outstanding'),
   ('1200','Inventory Asset','asset','inventory_asset','Stock value'),
   ('1300','Input GST Receivable','asset','input_gst','Input GST credit'),
   ('2000','Accounts Payable','liability','accounts_payable','Supplier outstanding'),
   ('2100','Output GST Payable','liability','output_gst','GST collected on sales'),
   ('3000','Owner Equity','equity','owner_equity','Owner/capital equity'),
   ('4000','Sales Revenue','income','sales_revenue','Product/service sales'),
   ('4010','Other Revenue','income','other_revenue','Other operating revenue'),
   ('5000','Cost of Goods Sold','cogs','cogs','Inventory cost of sold goods'),
   ('6000','Operating Expenses','expense','operating_expense','General operating expenses'),
   ('6010','Purchase / Direct Expense','expense','purchase_expense','Direct purchase expense for non-stock items'),
   ('6900','Rounding / Variance','expense','rounding','Small rounding and cash variances')
  ) x(code,name,type,key,description)
  on conflict(tenant_id,code) do nothing;

  insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id)
  select a.tenant_id,'payment.'||a.system_key,a.id
  from public.accounting_accounts a
  where a.tenant_id=p_tenant_id and a.system_key in('cash','bank','upi','card')
  on conflict(tenant_id,mapping_key) do nothing;

  insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id)
  select a.tenant_id,a.system_key,a.id
  from public.accounting_accounts a
  where a.tenant_id=p_tenant_id and a.system_key in(
    'accounts_receivable','accounts_payable','inventory_asset','input_gst','output_gst',
    'sales_revenue','cogs','operating_expense','purchase_expense','rounding'
  )
  on conflict(tenant_id,mapping_key) do nothing;
end $$;
revoke all on function private.v47_ensure_accounting_for_tenant(uuid) from public;

create or replace function private.v47_tenant_accounting_after_insert()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  perform private.v47_ensure_accounting_for_tenant(new.id);
  return new;
end $$;
revoke all on function private.v47_tenant_accounting_after_insert() from public;
drop trigger if exists trg_v47_tenant_accounting_after_insert on public.tenants;
create trigger trg_v47_tenant_accounting_after_insert
after insert on public.tenants for each row execute function private.v47_tenant_accounting_after_insert();

-- Backfill/repair mappings for every current business before strict posting is enabled.
do $$ declare r record; begin
  for r in select id from public.tenants loop
    perform private.v47_ensure_accounting_for_tenant(r.id);
  end loop;
end $$;

-- Critical change: accounting errors are no longer swallowed. A required journal failure
-- now aborts the surrounding sale/purchase/expense transaction.
create or replace function private.v4_origin_after_insert()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_shift uuid;v_cash numeric;v_ref text;v_method text;begin
  perform private.v4_accounting_post_document(new.tenant_id,new.entity_type,new.entity_id);

  if new.device_id is not null then
    select id into v_shift from public.cashier_shifts
    where tenant_id=new.tenant_id and device_id=new.device_id and status='open'
    order by opened_at desc limit 1;
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
    select payment_method,total_amount,expense_number into v_method,v_cash,v_ref
    from public.expenses where id=new.entity_id and tenant_id=new.tenant_id;
    if lower(coalesce(v_method,''))='cash' and coalesce(v_cash,0)>0 and not exists(select 1 from public.cash_drawer_movements where shift_id=v_shift and reference_type='expense' and reference_id=new.entity_id) then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(new.tenant_id,v_shift,'expense',-abs(v_cash),'expense',new.entity_id,v_ref,'Cash expense',new.created_by);
    end if;
  end if;
  return new;
end $$;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(102,'4.7.0','Foundation Lock & Production Stabilization','Strict automatic accounting posting and new-tenant accounting provisioning.')
on conflict(migration_no) do update set notes=excluded.notes;

commit;
select 'THQ ERP V4.7 migration 102 accounting integrity ready' as status;
