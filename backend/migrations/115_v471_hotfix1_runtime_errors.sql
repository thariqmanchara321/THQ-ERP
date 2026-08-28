-- THQ ERP V4.7.1 Hotfix 1
-- Runtime fixes found during release acceptance testing.
-- 1) Fix POS held-invoice feed: RETURNS TABLE output column `id` conflicted with an unqualified business_devices.id reference.
-- 2) Fix Admin/system/customer-receipt audit calls: private.business_audit_write has JSONB and UUID compatibility overloads, so an untyped NULL was ambiguous at runtime.
-- Safe to apply once after migration 114.
begin;

create or replace function public.platform_system_deactivate_v46(p_tenant_id uuid,p_device_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v_code text;begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required';end if;
  select device_code into v_code from public.business_devices where id=p_device_id and tenant_id=p_tenant_id for update;
  if v_code is null then raise exception 'System not found';end if;
  update public.system_installations set status='inactive',deactivated_at=now(),deactivation_reason=nullif(trim(coalesce(p_reason,'')),'')
  where tenant_id=p_tenant_id and system_id=p_device_id and status='active';
  update public.business_devices set status='inactive',installation_id=null,device_secret_hash=null,last_seen_at=null,
    deactivated_at=now(),deactivated_by=auth.uid(),deactivation_reason=nullif(trim(coalesce(p_reason,'')),''),updated_at=now()
  where id=p_device_id and tenant_id=p_tenant_id and status='active';
  perform private.business_audit_write(p_tenant_id,'system.deactivate','business_device',p_device_id,v_code,null::jsonb,jsonb_build_object('reason',nullif(trim(coalesce(p_reason,'')),'')));
end$$;
grant execute on function public.platform_system_deactivate_v46(uuid,uuid,text) to authenticated;

create or replace function public.platform_system_update_v471(
  p_tenant_id uuid,p_system_id uuid,p_location_id uuid,p_name text,p_module_keys text[],
  p_invoice_prefix text,p_system_role text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare d public.business_devices%rowtype;v_modules text[];v_role text;v_old_location uuid;
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required';end if;
  select * into d from public.business_devices where id=p_system_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'System not found';end if;
  if not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active) then raise exception 'Target store/location is not active';end if;
  v_old_location:=d.location_id;
  v_role:=coalesce(nullif(trim(p_system_role),''),d.system_role,case when d.app_type='pos' then 'pos' else 'office' end);
  if d.app_type='pos' and v_role<>'pos' then raise exception 'POS systems must use POS role';end if;
  if d.app_type='client' and v_role not in('back_office','office','inventory') then raise exception 'Invalid Client system role';end if;

  if d.location_id<>p_location_id then
    if exists(select 1 from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_system_id and status='open') then
      raise exception 'Close the cashier shift before moving this system to another store';
    end if;
    if exists(select 1 from public.pos_held_sales where tenant_id=p_tenant_id and device_id=p_system_id) then
      raise exception 'Resume or remove held invoices before moving this POS to another store';
    end if;
  end if;

  if d.app_type='pos' then
    select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules
    from unnest(coalesce(p_module_keys,'{}'::text[]))x
    where x in('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs','cashier_shifts','notifications','tasks','support','terminal_day')
      and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);
    if nullif(upper(trim(p_invoice_prefix)),'') is not null and exists(
      select 1 from public.business_devices x where x.tenant_id=p_tenant_id and x.id<>p_system_id and x.status<>'revoked'
       and upper(coalesce(x.invoice_prefix,''))=upper(trim(p_invoice_prefix))
    ) then raise exception 'Terminal invoice prefix is already in use';end if;
  else
    v_modules:='{}'::text[];
  end if;

  update public.business_devices
  set location_id=p_location_id,name=coalesce(nullif(trim(p_name),''),name),allowed_modules=v_modules,
      invoice_prefix=case when d.app_type='pos' then nullif(upper(trim(p_invoice_prefix)),'') else invoice_prefix end,
      system_role=v_role,updated_at=now()
  where id=p_system_id;

  perform private.business_audit_write(p_tenant_id,'system.update','business_device',p_system_id,d.device_code,null::jsonb,jsonb_build_object('from_location_id',v_old_location,'to_location_id',p_location_id,'system_role',v_role,'modules',v_modules));
  return jsonb_build_object('success',true,'system_id',p_system_id,'location_id',p_location_id,'system_role',v_role,'allowed_modules',v_modules);
end $$;
grant execute on function public.platform_system_update_v471(uuid,uuid,uuid,text,text[],text,text) to authenticated;

create or replace function public.platform_system_delete_v471(p_tenant_id uuid,p_system_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare d public.business_devices%rowtype;v_has_history boolean:=false;
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required';end if;
  select * into d from public.business_devices where id=p_system_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'System not found';end if;

  select exists(select 1 from public.document_origins where tenant_id=p_tenant_id and device_id=p_system_id)
      or exists(select 1 from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_system_id)
      or exists(select 1 from public.system_installations where tenant_id=p_tenant_id and system_id=p_system_id)
  into v_has_history;

  delete from public.pos_held_sales where tenant_id=p_tenant_id and device_id=p_system_id;
  update public.system_installations set status='revoked',deactivated_at=coalesce(deactivated_at,now()),
    deactivation_reason=coalesce(nullif(trim(coalesce(p_reason,'')),''),'System removed from Admin')
  where tenant_id=p_tenant_id and system_id=p_system_id and status<>'revoked';

  if v_has_history then
    update public.business_devices set status='revoked',installation_id=null,device_secret_hash=null,activation_hash=null,
      activation_expires_at=null,last_seen_at=null,deactivated_at=coalesce(deactivated_at,now()),deactivation_reason=coalesce(nullif(trim(coalesce(p_reason,'')),''),'System removed from Admin'),updated_at=now()
    where id=p_system_id;
    perform private.business_audit_write(p_tenant_id,'system.archive','business_device',p_system_id,d.device_code,null::jsonb,jsonb_build_object('reason',p_reason));
    return jsonb_build_object('success',true,'action','archived','system_id',p_system_id,'message','System has transaction/installation history and was safely archived.');
  end if;

  delete from public.business_devices where id=p_system_id and tenant_id=p_tenant_id;
  perform private.business_audit_write(p_tenant_id,'system.delete','business_device',p_system_id,d.device_code,null::jsonb,jsonb_build_object('reason',p_reason));
  return jsonb_build_object('success',true,'action','deleted','system_id',p_system_id,'message','Unused system permanently deleted.');
end $$;
grant execute on function public.platform_system_delete_v471(uuid,uuid,text) to authenticated;

create or replace function public.platform_location_delete_v471(p_tenant_id uuid,p_location_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare l public.business_locations%rowtype;v_has_history boolean:=false;
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then raise exception 'Platform admin required';end if;
  select * into l from public.business_locations where id=p_location_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'Store/location not found';end if;
  if coalesce(l.hierarchy_role,'')='main_store' or upper(coalesce(l.location_code,''))='MAIN' then
    raise exception 'MAIN STORE cannot be deleted. Rename/edit it instead.';
  end if;
  if exists(select 1 from public.business_devices where tenant_id=p_tenant_id and location_id=p_location_id and status<>'revoked') then
    raise exception 'Move or delete the systems assigned to this store before deleting it';
  end if;
  if exists(select 1 from public.business_locations where tenant_id=p_tenant_id and parent_location_id=p_location_id and active) then
    raise exception 'Move/archive child locations before deleting this store';
  end if;
  select exists(select 1 from public.document_origins where tenant_id=p_tenant_id and location_id=p_location_id)
      or exists(select 1 from public.journal_entries where tenant_id=p_tenant_id and location_id=p_location_id)
      or exists(select 1 from public.location_stock_balances where tenant_id=p_tenant_id and location_id=p_location_id)
  into v_has_history;

  if v_has_history then
    update public.business_locations set active=false,updated_at=now() where id=p_location_id;
    perform private.business_audit_write(p_tenant_id,'location.archive','business_location',p_location_id,l.location_code,null::jsonb,jsonb_build_object('reason',p_reason));
    return jsonb_build_object('success',true,'action','archived','location_id',p_location_id,'message','Store has business history and was safely archived.');
  end if;

  delete from public.business_locations where id=p_location_id and tenant_id=p_tenant_id;
  perform private.business_audit_write(p_tenant_id,'location.delete','business_location',p_location_id,l.location_code,null::jsonb,jsonb_build_object('reason',p_reason));
  return jsonb_build_object('success',true,'action','deleted','location_id',p_location_id,'message','Unused store permanently deleted.');
end $$;
grant execute on function public.platform_location_delete_v471(uuid,uuid,text) to authenticated;

create or replace function public.tenant_system_create_v471(
  p_tenant_id uuid,p_location_id uuid,p_name text,p_app_type text,p_platform_hint text default null,
  p_module_keys text[] default '{}'::text[],p_invoice_prefix text default null,p_system_role text default null
) returns jsonb language plpgsql security definer set search_path=public,private,extensions,pg_temp
as $$
declare v_id uuid:=gen_random_uuid();v_code text;v_device_code text;v_exp timestamptz:=now()+interval '24 hours';v_modules text[];v_role text;
begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'locations.manage') and not private.erp_has_permission(p_tenant_id,'locations.manage_all') then raise exception 'Permission denied';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_user_location_allowed(p_tenant_id,p_location_id,'manage') then raise exception 'Location manage access denied';end if;
  if p_app_type not in('client','pos') then raise exception 'Invalid app type';end if;
  if not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active) then raise exception 'Target store/location is not active';end if;
  v_role:=coalesce(nullif(trim(p_system_role),''),case when p_app_type='pos' then 'pos' else 'office' end);
  if p_app_type='pos' and v_role<>'pos' then raise exception 'POS systems must use POS role';end if;
  if p_app_type='client' and v_role not in('back_office','office','inventory') then raise exception 'Invalid Client system role';end if;
  if p_app_type='pos' then
    select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules from unnest(coalesce(p_module_keys,'{}'::text[]))x
    where x in('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs','cashier_shifts','notifications','tasks','support','terminal_day')
      and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);
  else v_modules:='{}'::text[];end if;
  if nullif(upper(trim(p_invoice_prefix)),'') is not null and exists(select 1 from public.business_devices d where d.tenant_id=p_tenant_id and d.status<>'revoked' and upper(coalesce(d.invoice_prefix,''))=upper(trim(p_invoice_prefix))) then raise exception 'Terminal invoice prefix is already in use';end if;
  v_code:=upper(substr(encode(gen_random_bytes(8),'hex'),1,12));v_device_code:=upper(p_app_type)||'-'||upper(substr(replace(v_id::text,'-',''),1,6));
  insert into public.business_devices(id,tenant_id,location_id,device_code,name,app_type,platform_hint,status,activation_hash,activation_expires_at,allowed_modules,invoice_prefix,system_role)
  values(v_id,p_tenant_id,p_location_id,v_device_code,coalesce(nullif(trim(p_name),''),'System'),p_app_type,nullif(trim(p_platform_hint),''),'pending',encode(digest(v_code,'sha256'),'hex'),v_exp,v_modules,case when p_app_type='pos' then nullif(upper(trim(p_invoice_prefix)),'') else null end,v_role);
  perform private.business_audit_write(p_tenant_id,'system.create','business_device',v_id,v_device_code,null::jsonb,jsonb_build_object('location_id',p_location_id,'app_type',p_app_type,'system_role',v_role,'modules',v_modules));
  return jsonb_build_object('device_id',v_id,'device_code',v_device_code,'activation_code',v_code,'expires_at',v_exp,'allowed_modules',v_modules,'system_role',v_role);
end $$;
grant execute on function public.tenant_system_create_v471(uuid,uuid,text,text,text,text[],text,text) to authenticated;

create or replace function public.tenant_system_update_v471(
  p_tenant_id uuid,p_system_id uuid,p_location_id uuid,p_name text,p_module_keys text[],p_invoice_prefix text,p_system_role text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare d public.business_devices%rowtype;v_modules text[];v_role text;v_old_location uuid;
begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'locations.manage') and not private.erp_has_permission(p_tenant_id,'locations.manage_all') then raise exception 'Permission denied';end if;
  select * into d from public.business_devices where id=p_system_id and tenant_id=p_tenant_id for update;if not found then raise exception 'System not found';end if;
  if not private.erp_user_is_owner(p_tenant_id) and (not private.erp_user_location_allowed(p_tenant_id,d.location_id,'manage') or not private.erp_user_location_allowed(p_tenant_id,p_location_id,'manage')) then raise exception 'Location manage access denied';end if;
  if not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active) then raise exception 'Target store/location is not active';end if;
  v_old_location:=d.location_id;v_role:=coalesce(nullif(trim(p_system_role),''),d.system_role,case when d.app_type='pos' then 'pos' else 'office' end);
  if d.app_type='pos' and v_role<>'pos' then raise exception 'POS systems must use POS role';end if;
  if d.app_type='client' and v_role not in('back_office','office','inventory') then raise exception 'Invalid Client system role';end if;
  if d.location_id<>p_location_id then
    if exists(select 1 from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_system_id and status='open') then raise exception 'Close the cashier shift before moving this system to another store';end if;
    if exists(select 1 from public.pos_held_sales where tenant_id=p_tenant_id and device_id=p_system_id) then raise exception 'Resume or remove held invoices before moving this POS to another store';end if;
  end if;
  if d.app_type='pos' then
    select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules from unnest(coalesce(p_module_keys,'{}'::text[]))x
    where x in('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs','cashier_shifts','notifications','tasks','support','terminal_day')
      and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);
    if nullif(upper(trim(p_invoice_prefix)),'') is not null and exists(select 1 from public.business_devices x where x.tenant_id=p_tenant_id and x.id<>p_system_id and x.status<>'revoked' and upper(coalesce(x.invoice_prefix,''))=upper(trim(p_invoice_prefix))) then raise exception 'Terminal invoice prefix is already in use';end if;
  else v_modules:='{}'::text[];end if;
  update public.business_devices set location_id=p_location_id,name=coalesce(nullif(trim(p_name),''),name),allowed_modules=v_modules,invoice_prefix=case when d.app_type='pos' then nullif(upper(trim(p_invoice_prefix)),'') else invoice_prefix end,system_role=v_role,updated_at=now() where id=p_system_id;
  perform private.business_audit_write(p_tenant_id,'system.update','business_device',p_system_id,d.device_code,null::jsonb,jsonb_build_object('from_location_id',v_old_location,'to_location_id',p_location_id,'system_role',v_role,'modules',v_modules));
  return jsonb_build_object('success',true,'system_id',p_system_id,'location_id',p_location_id,'system_role',v_role,'allowed_modules',v_modules);
end $$;
grant execute on function public.tenant_system_update_v471(uuid,uuid,uuid,text,text[],text,text) to authenticated;

create or replace function public.tenant_system_revoke_v471(p_tenant_id uuid,p_system_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare d public.business_devices%rowtype;begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'locations.manage') and not private.erp_has_permission(p_tenant_id,'locations.manage_all') then raise exception 'Permission denied';end if;
  select * into d from public.business_devices where id=p_system_id and tenant_id=p_tenant_id for update;if not found then raise exception 'System not found';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_user_location_allowed(p_tenant_id,d.location_id,'manage') then raise exception 'Location manage access denied';end if;
  if exists(select 1 from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_system_id and status='open') then raise exception 'Close the cashier shift before revoking this POS';end if;
  update public.system_installations set status='revoked',deactivated_at=coalesce(deactivated_at,now()),deactivation_reason=coalesce(nullif(trim(coalesce(p_reason,'')),''),'Revoked by business manager') where tenant_id=p_tenant_id and system_id=p_system_id and status<>'revoked';
  update public.business_devices set status='revoked',activation_hash=null,activation_expires_at=null,device_secret_hash=null,installation_id=null,updated_at=now() where id=p_system_id;
  perform private.business_audit_write(p_tenant_id,'system.revoke','business_device',p_system_id,d.device_code,null::jsonb,jsonb_build_object('reason',coalesce(p_reason,'Business manager revoke')));
  return jsonb_build_object('success',true,'system_id',p_system_id,'status','revoked');
end $$;
grant execute on function public.tenant_system_revoke_v471(uuid,uuid,text) to authenticated;

create or replace function public.customer_receive_payment_v471(
  p_tenant_id uuid,p_customer_id uuid,p_amount numeric,p_payment_method text,p_reference_number text,p_notes text,
  p_sale_id uuid default null,p_location_id uuid default null,p_device_id uuid default null,p_request_id text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_existing jsonb;v_receipt uuid:=gen_random_uuid();v_receipt_no text;v_remaining numeric:=round(coalesce(p_amount,0),2);v_total_outstanding numeric:=0;
  v_location uuid:=p_location_id;v_sale record;v_alloc numeric;v_result jsonb;v_payment_id uuid;v_started timestamptz:=clock_timestamp();v_lines jsonb;v_response jsonb;
  v_is_platform boolean:=private.platform_v2_is_admin();v_device_type text;v_device_location uuid;
begin
  if nullif(trim(coalesce(p_request_id,'')),'') is null then raise exception 'Request ID is required';end if;
  v_existing:=private.v47_request_existing(p_tenant_id,p_request_id,'customer.receipt');if v_existing is not null then return v_existing;end if;
  if not v_is_platform then
    if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
    if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'payments.receive') and not private.erp_has_permission(p_tenant_id,'sales.manage') then raise exception 'Receive payment permission required';end if;
  end if;
  if v_remaining<=0 then raise exception 'Payment amount must be greater than zero';end if;
  -- Serialize receipts per customer so two terminals cannot both collect the same remaining balance.
  perform 1 from public.customers where id=p_customer_id and tenant_id=p_tenant_id and status='active' and not coalesce(is_walk_in,false) for update;
  if not found then raise exception 'Select an active non-walk-in customer';end if;
  if lower(coalesce(p_payment_method,'')) not in('cash','upi','card','bank','cheque','other') then raise exception 'Invalid payment method';end if;

  if p_device_id is not null then
    select app_type,location_id into v_device_type,v_device_location
    from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active';
    if v_device_type is null then raise exception 'Active collecting system not found';end if;
    if v_device_type='pos' then
      if p_location_id is not null and p_location_id<>v_device_location then raise exception 'Collecting POS/location mismatch';end if;
      v_location:=v_device_location;
    else
      v_location:=coalesce(p_location_id,v_device_location);
    end if;
    if not v_is_platform then perform private.erp_validate_transaction_origin(p_tenant_id,v_location,p_device_id,'sales');end if;
    if v_device_type='pos' and lower(p_payment_method)='cash'
       and exists(select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and 'cashier_shifts'=any(coalesce(d.allowed_modules,'{}'::text[])))
       and not exists(select 1 from public.cashier_shifts s where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open') then
      raise exception 'Open cashier shift before receiving cash on this POS';
    end if;
  elsif v_location is not null and not v_is_platform and not private.erp_document_scope_allowed(p_tenant_id,v_location,v_location,'operate') then
    raise exception 'Location access denied';
  end if;

  select coalesce(sum(greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)),0) into v_total_outstanding
  from public.sales s left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
  left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id
  left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
  where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') not in('void','cancelled')
    and (p_sale_id is null or s.id=p_sale_id)
    and (v_is_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'operate'));
  if v_total_outstanding<=0.005 then raise exception 'Customer has no outstanding balance in the permitted scope';end if;
  if v_remaining>v_total_outstanding+0.005 then raise exception 'Payment % exceeds outstanding balance %',v_remaining,v_total_outstanding;end if;

  if v_location is null then
    select o.location_id into v_location from public.sales s join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and (p_sale_id is null or s.id=p_sale_id)
    order by coalesce(s.due_date,s.sale_date),s.created_at limit 1;
  end if;
  if v_location is null and v_is_platform then
    select id into v_location from public.business_locations where tenant_id=p_tenant_id and active order by case when hierarchy_role='main_store' then 0 else 1 end,created_at limit 1;
  end if;
  if v_location is null then raise exception 'Could not determine collection location';end if;
  v_receipt_no:='RCT-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.customer_receipt_number_seq')::text,6,'0');
  insert into public.customer_receipts(id,tenant_id,customer_id,receipt_number,receipt_date,amount,payment_method,reference_number,notes,location_id,device_id,created_by)
  values(v_receipt,p_tenant_id,p_customer_id,v_receipt_no,current_date,v_remaining,lower(p_payment_method),nullif(trim(coalesce(p_reference_number,'')),''),nullif(trim(coalesce(p_notes,'')),''),v_location,p_device_id,auth.uid());

  perform set_config('thq.customer_receipt_id',v_receipt::text,true);
  for v_sale in
    select s.id,s.sale_number,greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)::numeric balance,o.location_id
    from public.sales s left join(select sale_id,sum(amount) paid from public.sale_payments group by sale_id)py on py.sale_id=s.id
    left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id)rt on rt.sale_id=s.id
    left join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id
    where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') not in('void','cancelled')
      and greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)>0.005 and (p_sale_id is null or s.id=p_sale_id)
      and (v_is_platform or private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'operate'))
    order by case when p_sale_id is not null then 0 else 1 end,coalesce(s.due_date,s.sale_date),s.created_at
    for update of s
  loop
    exit when v_remaining<=0.005;
    v_alloc:=least(v_remaining,v_sale.balance);
    v_payment_id:=null;
    if v_is_platform then
      v_payment_id:=private.v471_platform_insert_sale_payment(v_sale.id,v_alloc,lower(p_payment_method),p_reference_number,coalesce(p_notes,'')||case when trim(coalesce(p_notes,''))='' then '' else ' • ' end||'Receipt '||v_receipt_no);
    else
      v_result:=public.sales_add_payment_v32(p_tenant_id,v_sale.id,v_alloc,lower(p_payment_method),p_reference_number,coalesce(p_notes,'')||case when trim(coalesce(p_notes,''))='' then '' else ' • ' end||'Receipt '||v_receipt_no);
      begin v_payment_id:=nullif(coalesce(v_result->>'payment_id',v_result->>'id'),'')::uuid;exception when others then v_payment_id:=null;end;
      if v_payment_id is null then
        select sp.id into v_payment_id from public.sale_payments sp where sp.sale_id=v_sale.id and abs(sp.amount-v_alloc)<0.005 and lower(sp.payment_method)=lower(p_payment_method)
          and sp.paid_at>=v_started-interval '2 seconds' order by sp.paid_at desc,sp.id desc limit 1;
      end if;
    end if;
    insert into public.customer_receipt_allocations(tenant_id,receipt_id,sale_id,payment_id,amount)
    values(p_tenant_id,v_receipt,v_sale.id,v_payment_id,v_alloc);
    v_remaining:=v_remaining-v_alloc;
  end loop;
  perform set_config('thq.customer_receipt_id','',true);
  if v_remaining>0.005 then raise exception 'Could not allocate full receipt. Remaining %',v_remaining;end if;

  v_lines:=jsonb_build_array(
    jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,p_payment_method),'debit',p_amount,'credit',0,'party_type','customer','party_id',p_customer_id,'description','Customer account receipt'),
    jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_receivable'),'debit',0,'credit',p_amount,'party_type','customer','party_id',p_customer_id,'description','Receivable settlement')
  );
  perform private.v4_journal_create(p_tenant_id,v_location,current_date,'Customer account receipt • '||v_receipt_no,'customer_receipt',v_receipt,v_receipt_no,v_lines);

  if lower(p_payment_method)='cash' and p_device_id is not null then
    insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
    select p_tenant_id,s.id,'receipt',p_amount,'customer_receipt',v_receipt,v_receipt_no,'Customer balance receipt',auth.uid()
    from public.cashier_shifts s where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open'
      and not exists(select 1 from public.cash_drawer_movements m where m.reference_type='customer_receipt' and m.reference_id=v_receipt)
    order by s.opened_at desc limit 1;
  end if;

  perform private.business_audit_write(p_tenant_id,'customer.payment.receive','customer',p_customer_id,v_receipt_no,null::jsonb,jsonb_build_object('receipt_id',v_receipt,'amount',p_amount,'payment_method',lower(p_payment_method),'sale_id',p_sale_id,'location_id',v_location,'device_id',p_device_id));
  v_response:=jsonb_build_object('success',true,'receipt_id',v_receipt,'receipt_number',v_receipt_no,'amount',p_amount,'outstanding_before',v_total_outstanding,'outstanding_after',greatest(v_total_outstanding-p_amount,0));
  return private.v47_request_complete(p_tenant_id,p_request_id,'customer.receipt',v_response);
end $$;
grant execute on function public.customer_receive_payment_v471(uuid,uuid,numeric,text,text,text,uuid,uuid,uuid,text) to authenticated;

create or replace function public.pos_held_sales_feed_v471(p_tenant_id uuid,p_device_id uuid)
returns table(id uuid,hold_code text,label text,customer_id uuid,customer_name text,item_count integer,total numeric,held_by text,created_at timestamptz,state jsonb)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$declare v_location uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select d.location_id into v_location from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.status='active';
  if v_location is null then raise exception 'Active terminal not found';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_user_location_allowed(p_tenant_id,v_location,'view') then raise exception 'Terminal access denied';end if;
  return query select h.id,h.hold_code,h.label,h.customer_id,c.name::text,
    coalesce(jsonb_array_length(coalesce(h.state->'items','[]'::jsonb)),0),coalesce((h.state->>'total')::numeric,0),
    coalesce(ul.username::text,''),h.created_at,h.state
  from public.pos_held_sales h left join public.customers c on c.id=h.customer_id left join public.user_login_names ul on ul.user_id=h.held_by
  where h.tenant_id=p_tenant_id and h.device_id=p_device_id order by h.created_at desc;
end $$;
grant execute on function public.pos_held_sales_feed_v471(uuid,uuid) to authenticated;

-- Keep the v4.7 contract compatible with the same 4.7.1 applications while reporting the hotfix migration.
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp
as $$
  select jsonb_build_object(
    'product','THQ ERP',
    'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
    'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
    'minimum_app_version','4.7.1',
    'release','Operational Stabilization Patch — Hotfix 1'
  )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(115,'4.7.1','Operational Stabilization Patch — Hotfix 1',
  'Runtime fixes for held-sale feed ambiguous id and business_audit_write overload ambiguity in system/customer receipt operations.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

-- Sanity checks: definitions must exist after replacement.
do $$begin
  if to_regprocedure('public.pos_held_sales_feed_v471(uuid,uuid)') is null then raise exception 'Held-sale feed missing after hotfix';end if;
  if to_regprocedure('public.platform_system_deactivate_v46(uuid,uuid,text)') is null then raise exception 'System deactivate RPC missing after hotfix';end if;
  if to_regprocedure('public.platform_system_update_v471(uuid,uuid,uuid,text,text[],text,text)') is null then raise exception 'System update RPC missing after hotfix';end if;
  if to_regprocedure('public.customer_receive_payment_v471(uuid,uuid,numeric,text,text,text,uuid,uuid,uuid,text)') is null then raise exception 'Customer payment RPC missing after hotfix';end if;
end$$;

commit;
select 'THQ ERP V4.7.1 Hotfix 1 migration 115 applied' as status;
