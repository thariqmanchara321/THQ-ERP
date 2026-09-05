-- THQ ERP v5.2 GST & Compliance
-- Migration 227: GST component account hierarchy and bootstrap.

begin;

create or replace function private.gst_v520_ensure_account(
  p_tenant_id uuid,
  p_code text,
  p_name text,
  p_account_type text,
  p_system_key text,
  p_parent_system_key text,
  p_description text
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid; v_parent uuid; v_existing_key text;
begin
  if not exists(select 1 from public.tenants where id=p_tenant_id) then raise exception 'Tenant not found';end if;
  if nullif(trim(coalesce(p_system_key,'')),'') is null then raise exception 'GST accounting system key required';end if;
  select id into v_id from public.accounting_accounts where tenant_id=p_tenant_id and system_key=p_system_key;
  if v_id is not null then return v_id;end if;
  if p_parent_system_key is not null then
    select id into v_parent from public.accounting_accounts where tenant_id=p_tenant_id and system_key=p_parent_system_key and active;
    if v_parent is null then raise exception 'GST accounting parent mapping % missing',p_parent_system_key;end if;
  end if;
  select system_key into v_existing_key from public.accounting_accounts where tenant_id=p_tenant_id and code=p_code;
  if found then raise exception 'Accounting code % is already used by system key %. Resolve the chart conflict before GST component setup',p_code,coalesce(v_existing_key,'<custom account>');end if;
  insert into public.accounting_accounts(tenant_id,code,name,account_type,parent_id,system_key,description,is_system,active)
  values(p_tenant_id,p_code,p_name,p_account_type,v_parent,p_system_key,p_description,true,true)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function private.gst_v520_ensure_account(uuid,text,text,text,text,text,text) from public,anon,authenticated;

create or replace function private.gst_v520_ensure_accounts(p_tenant_id uuid) returns void
language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v uuid;
begin
  if not exists(select 1 from public.accounting_accounts where tenant_id=p_tenant_id and system_key='input_gst' and active) then raise exception 'Legacy Input GST control account missing';end if;
  if not exists(select 1 from public.accounting_accounts where tenant_id=p_tenant_id and system_key='output_gst' and active) then raise exception 'Legacy Output GST control account missing';end if;

  v:=private.gst_v520_ensure_account(p_tenant_id,'1300-CGST','Input CGST Receivable','asset','input_cgst','input_gst','Book input CGST separately for v5.2 authoritative GST transactions');
  v:=private.gst_v520_ensure_account(p_tenant_id,'1300-SGST','Input SGST Receivable','asset','input_sgst','input_gst','Book input SGST separately for v5.2 authoritative GST transactions');
  v:=private.gst_v520_ensure_account(p_tenant_id,'1300-UTGST','Input UTGST Receivable','asset','input_utgst','input_gst','Book input UTGST separately for v5.2 authoritative GST transactions');
  v:=private.gst_v520_ensure_account(p_tenant_id,'1300-IGST','Input IGST Receivable','asset','input_igst','input_gst','Book input IGST separately for v5.2 authoritative GST transactions');
  v:=private.gst_v520_ensure_account(p_tenant_id,'1300-CESS','Input GST Compensation Cess Receivable','asset','input_cess','input_gst','Book input compensation cess separately for v5.2 authoritative GST transactions');

  v:=private.gst_v520_ensure_account(p_tenant_id,'1300-RCM','RCM Input GST Receivable','asset','rcm_input_gst','input_gst','Control account for reverse-charge input credit recognized only after RCM tax payment and ITC eligibility');
  v:=private.gst_v520_ensure_account(p_tenant_id,'1300-RCM-CGST','RCM Input CGST Receivable','asset','rcm_input_cgst','rcm_input_gst','RCM CGST input credit after payment/eligibility');
  v:=private.gst_v520_ensure_account(p_tenant_id,'1300-RCM-SGST','RCM Input SGST Receivable','asset','rcm_input_sgst','rcm_input_gst','RCM SGST input credit after payment/eligibility');
  v:=private.gst_v520_ensure_account(p_tenant_id,'1300-RCM-UTGST','RCM Input UTGST Receivable','asset','rcm_input_utgst','rcm_input_gst','RCM UTGST input credit after payment/eligibility');
  v:=private.gst_v520_ensure_account(p_tenant_id,'1300-RCM-IGST','RCM Input IGST Receivable','asset','rcm_input_igst','rcm_input_gst','RCM IGST input credit after payment/eligibility');
  v:=private.gst_v520_ensure_account(p_tenant_id,'1300-RCM-CESS','RCM Input Cess Receivable','asset','rcm_input_cess','rcm_input_gst','RCM compensation cess input credit after payment/eligibility');

  v:=private.gst_v520_ensure_account(p_tenant_id,'2100-CGST','Output CGST Payable','liability','output_cgst','output_gst','Output CGST collected on v5.2 authoritative GST transactions');
  v:=private.gst_v520_ensure_account(p_tenant_id,'2100-SGST','Output SGST Payable','liability','output_sgst','output_gst','Output SGST collected on v5.2 authoritative GST transactions');
  v:=private.gst_v520_ensure_account(p_tenant_id,'2100-UTGST','Output UTGST Payable','liability','output_utgst','output_gst','Output UTGST collected on v5.2 authoritative GST transactions');
  v:=private.gst_v520_ensure_account(p_tenant_id,'2100-IGST','Output IGST Payable','liability','output_igst','output_gst','Output IGST collected on v5.2 authoritative GST transactions');
  v:=private.gst_v520_ensure_account(p_tenant_id,'2100-CESS','Output GST Compensation Cess Payable','liability','output_cess','output_gst','Output compensation cess collected on v5.2 authoritative GST transactions');

  v:=private.gst_v520_ensure_account(p_tenant_id,'2160-RCM','RCM GST Payable','liability','rcm_gst_payable',null,'Recipient GST liability under reverse charge; separate from supplier payable and output GST');
  v:=private.gst_v520_ensure_account(p_tenant_id,'2160-RCM-CGST','RCM CGST Payable','liability','rcm_cgst_payable','rcm_gst_payable','Recipient CGST liability under reverse charge');
  v:=private.gst_v520_ensure_account(p_tenant_id,'2160-RCM-SGST','RCM SGST Payable','liability','rcm_sgst_payable','rcm_gst_payable','Recipient SGST liability under reverse charge');
  v:=private.gst_v520_ensure_account(p_tenant_id,'2160-RCM-UTGST','RCM UTGST Payable','liability','rcm_utgst_payable','rcm_gst_payable','Recipient UTGST liability under reverse charge');
  v:=private.gst_v520_ensure_account(p_tenant_id,'2160-RCM-IGST','RCM IGST Payable','liability','rcm_igst_payable','rcm_gst_payable','Recipient IGST liability under reverse charge');
  v:=private.gst_v520_ensure_account(p_tenant_id,'2160-RCM-CESS','RCM Cess Payable','liability','rcm_cess_payable','rcm_gst_payable','Recipient compensation cess liability under reverse charge');

  insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id)
  select a.tenant_id,a.system_key,a.id from public.accounting_accounts a
  where a.tenant_id=p_tenant_id and a.system_key in(
    'input_cgst','input_sgst','input_utgst','input_igst','input_cess',
    'rcm_input_gst','rcm_input_cgst','rcm_input_sgst','rcm_input_utgst','rcm_input_igst','rcm_input_cess',
    'output_cgst','output_sgst','output_utgst','output_igst','output_cess',
    'rcm_gst_payable','rcm_cgst_payable','rcm_sgst_payable','rcm_utgst_payable','rcm_igst_payable','rcm_cess_payable'
  )
  on conflict(tenant_id,mapping_key) do update set account_id=excluded.account_id,updated_at=now();
end $$;
revoke all on function private.gst_v520_ensure_accounts(uuid) from public,anon,authenticated;

create or replace function private.v47_ensure_accounting_for_tenant(p_tenant_id uuid) returns void
language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if not exists(select 1 from public.tenants where id=p_tenant_id) then raise exception 'Tenant not found';end if;
  insert into public.accounting_accounts(tenant_id,code,name,account_type,system_key,is_system,description)
  select p_tenant_id,x.code,x.name,x.type,x.key,true,x.description from (values
   ('1000','Cash in Hand','asset','cash','Cash received at counters'),('1010','Bank Account','asset','bank','Primary bank account'),('1020','UPI Clearing','asset','upi','UPI collections/settlements'),('1030','Card Clearing','asset','card','Card collections/settlements'),('1100','Accounts Receivable','asset','accounts_receivable','Customer credit outstanding'),('1200','Inventory Asset','asset','inventory_asset','Stock value'),('1300','Input GST Receivable','asset','input_gst','Legacy/control Input GST account; v5.2 authoritative GST uses component children'),('2000','Accounts Payable','liability','accounts_payable','Supplier outstanding'),('2100','Output GST Payable','liability','output_gst','Legacy/control Output GST account; v5.2 authoritative GST uses component children'),('3000','Owner Equity','equity','owner_equity','Owner/capital equity'),('4000','Sales Revenue','income','sales_revenue','Product/service sales'),('4010','Other Revenue','income','other_revenue','Other operating revenue'),('5000','Cost of Goods Sold','cogs','cogs','Inventory cost of sold goods'),('6000','Operating Expenses','expense','operating_expense','General operating expenses'),('6010','Purchase / Direct Expense','expense','purchase_expense','Direct purchase expense for non-stock items'),('6900','Rounding / Variance','expense','rounding','Small rounding and cash variances')) x(code,name,type,key,description)
  on conflict(tenant_id,code) do nothing;
  insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id)
  select a.tenant_id,'payment.'||a.system_key,a.id from public.accounting_accounts a where a.tenant_id=p_tenant_id and a.system_key in('cash','bank','upi','card') on conflict(tenant_id,mapping_key) do nothing;
  insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id)
  select a.tenant_id,a.system_key,a.id from public.accounting_accounts a where a.tenant_id=p_tenant_id and a.system_key in('accounts_receivable','accounts_payable','inventory_asset','input_gst','output_gst','sales_revenue','cogs','operating_expense','purchase_expense','rounding') on conflict(tenant_id,mapping_key) do nothing;
  perform private.gst_v520_ensure_accounts(p_tenant_id);
end $$;
revoke all on function private.v47_ensure_accounting_for_tenant(uuid) from public,anon,authenticated;

create or replace function private.gst_v520_account_family(p_system_key text) returns text
language sql immutable as $$
 select case
  when p_system_key in('input_gst','input_cgst','input_sgst','input_utgst','input_igst','input_cess') then 'input_booked'
  when p_system_key in('rcm_input_gst','rcm_input_cgst','rcm_input_sgst','rcm_input_utgst','rcm_input_igst','rcm_input_cess') then 'rcm_input'
  when p_system_key in('output_gst','output_cgst','output_sgst','output_utgst','output_igst','output_cess') then 'output'
  when p_system_key in('rcm_gst_payable','rcm_cgst_payable','rcm_sgst_payable','rcm_utgst_payable','rcm_igst_payable','rcm_cess_payable') then 'rcm_payable'
  else null end
$$;
revoke all on function private.gst_v520_account_family(text) from public,anon,authenticated;

create or replace function private.gst_v520_account_ids(p_tenant_id uuid,p_family text) returns table(account_id uuid)
language sql stable security definer set search_path=public,private,pg_temp as $$
 select a.id from public.accounting_accounts a
 where a.tenant_id=p_tenant_id and a.active and (
   (p_family='input_booked' and private.gst_v520_account_family(a.system_key)='input_booked') or
   (p_family='rcm_input' and private.gst_v520_account_family(a.system_key)='rcm_input') or
   (p_family='output' and private.gst_v520_account_family(a.system_key)='output') or
   (p_family='rcm_payable' and private.gst_v520_account_family(a.system_key)='rcm_payable') or
   (p_family='gst_all' and private.gst_v520_account_family(a.system_key) is not null)
 )
$$;
revoke all on function private.gst_v520_account_ids(uuid,text) from public,anon,authenticated;

do $$declare t record;begin for t in select id from public.tenants loop perform private.v47_ensure_accounting_for_tenant(t.id);end loop;end$$;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(227,'5.2.0-foundation','GST Component Account Hierarchy','Keeps v5.1 generic Input/Output GST as historical controls; adds component CGST/SGST/UTGST/IGST/Cess accounts plus separate RCM payable and deferred RCM input account families, with future-tenant bootstrap and deterministic mappings.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;