-- THQ ERP V4.6
-- Core integrity, activation lifecycle, audit compatibility and operational helpers.
begin;

-- ---------------------------------------------------------------------------
-- 1. Audit compatibility: V4.5 accidentally passed location_id (uuid) in the
--    p_before position. Keep the canonical JSONB signature and provide a safe
--    overload so old V4.5 migrations/callers continue to work.
-- ---------------------------------------------------------------------------
create or replace function private.business_audit_write(
  p_tenant_id uuid,p_action text,p_entity_type text,p_entity_id uuid,
  p_reference text,p_before jsonb,p_after jsonb
)
returns void language plpgsql security definer
set search_path=public,private,pg_temp
as $$
declare v_location uuid; v_device uuid;
begin
  select o.location_id,o.device_id into v_location,v_device
  from public.document_origins o
  where o.tenant_id=p_tenant_id and o.entity_type=p_entity_type and o.entity_id=p_entity_id
  limit 1;

  if v_location is null and p_after ? 'location_id' then
    begin v_location := nullif(p_after->>'location_id','')::uuid; exception when others then null; end;
  end if;
  if v_device is null and p_after ? 'device_id' then
    begin v_device := nullif(p_after->>'device_id','')::uuid; exception when others then null; end;
  end if;

  insert into public.business_audit_log(
    tenant_id,user_id,action,entity_type,entity_id,entity_reference,
    before_data,after_data,location_id,device_id,metadata
  ) values(
    p_tenant_id,auth.uid(),p_action,p_entity_type,p_entity_id,p_reference,
    p_before,p_after,v_location,v_device,
    jsonb_build_object('source','erp','recorded_at',now(),'version','4.6')
  );
end $$;
revoke all on function private.business_audit_write(uuid,text,text,uuid,text,jsonb,jsonb) from public;

create or replace function private.business_audit_write(
  p_tenant_id uuid,p_action text,p_entity_type text,p_entity_id uuid,
  p_reference text,p_location_id uuid,p_after jsonb
)
returns void language plpgsql security definer
set search_path=public,private,pg_temp
as $$
begin
  perform private.business_audit_write(
    p_tenant_id,p_action,p_entity_type,p_entity_id,p_reference,
    jsonb_build_object('location_id',p_location_id),
    coalesce(p_after,'{}'::jsonb) || jsonb_build_object('location_id',p_location_id)
  );
end $$;
revoke all on function private.business_audit_write(uuid,text,text,uuid,text,uuid,jsonb) from public;

-- ---------------------------------------------------------------------------
-- 2. Activation lifecycle.
-- pending   = configured but not activated
-- active    = activated and bound to an installation
-- inactive  = deliberately deactivated; can be activated again
-- revoked   = permanently retired
-- ---------------------------------------------------------------------------
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid='public.business_devices'::regclass
      and contype='c'
      and pg_get_constraintdef(oid) ilike '%status%'
      and pg_get_constraintdef(oid) ilike '%pending%'
  loop
    execute format('alter table public.business_devices drop constraint %I',c.conname);
  end loop;
end $$;

alter table public.business_devices
  add column if not exists activation_issued_at timestamptz,
  add column if not exists activation_issued_by uuid references auth.users(id) on delete set null,
  add column if not exists deactivated_at timestamptz,
  add column if not exists deactivated_by uuid references auth.users(id) on delete set null,
  add column if not exists deactivation_reason text,
  add column if not exists activation_count integer not null default 0;

do $$ begin
  if not exists(select 1 from pg_constraint where conname='business_devices_status_v46_check') then
    alter table public.business_devices add constraint business_devices_status_v46_check
      check(status in ('pending','active','inactive','revoked'));
  end if;
end $$;

create index if not exists idx_business_devices_activation_v46
  on public.business_devices(tenant_id,status,location_id,app_type,created_at desc);

-- Create a configured system without activating it.
create or replace function public.platform_system_create_v46(
  p_tenant_id uuid,p_location_id uuid,p_name text,p_app_type text,
  p_platform_hint text default null,p_module_keys text[] default '{}'::text[],
  p_invoice_prefix text default null
)
returns jsonb language plpgsql security definer
set search_path=public,private,extensions,pg_temp
as $$
declare v_id uuid:=gen_random_uuid(); v_code text; v_modules text[]; v_prefix text; v_no int;
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then
    raise exception 'Platform admin required';
  end if;
  if p_app_type not in ('client','pos') then raise exception 'Invalid app type'; end if;
  if not exists(select 1 from public.business_locations where id=p_location_id and tenant_id=p_tenant_id and active) then
    raise exception 'Invalid location';
  end if;

  if p_app_type='pos' then
    select coalesce(array_agg(distinct x),'{}'::text[]) into v_modules
    from unnest(coalesce(p_module_keys,'{}'::text[])) x
    where x in('sales','inventory','customers','suppliers','purchases','expenses','restaurant','logs','cashier_shifts','notifications','tasks','support','terminal_day')
      and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key=x and tm.enabled);
  else
    v_modules:='{}'::text[];
  end if;

  if nullif(upper(trim(p_invoice_prefix)),'') is not null then
    v_prefix:=upper(trim(p_invoice_prefix));
  else
    select coalesce(max(nullif(regexp_replace(coalesce(d.invoice_prefix,''),'[^0-9]','','g'),'')::int),0)+1
      into v_no
    from public.business_devices d
    where d.tenant_id=p_tenant_id and d.app_type=p_app_type and d.status<>'revoked';
    v_prefix:=upper(p_app_type)||lpad(v_no::text,2,'0');
  end if;

  if exists(select 1 from public.business_devices d where d.tenant_id=p_tenant_id and d.status<>'revoked' and upper(coalesce(d.invoice_prefix,''))=v_prefix) then
    raise exception 'Terminal invoice prefix is already in use';
  end if;

  insert into public.business_devices(
    id,tenant_id,location_id,device_code,name,app_type,platform_hint,status,
    activation_hash,activation_expires_at,allowed_modules,invoice_prefix,activation_count
  ) values(
    v_id,p_tenant_id,p_location_id,
    upper(p_app_type)||'-'||upper(substr(replace(v_id::text,'-',''),1,8)),
    coalesce(nullif(trim(p_name),''),'System'),p_app_type,nullif(trim(p_platform_hint),''),'pending',
    null,null,v_modules,v_prefix,0
  );

  perform private.business_audit_write(
    p_tenant_id,'system.create','business_device',v_id,
    v_prefix,null,jsonb_build_object('location_id',p_location_id,'app_type',p_app_type)
  );

  return jsonb_build_object('device_id',v_id,'status','pending','invoice_prefix',v_prefix,'allowed_modules',v_modules);
end $$;
grant execute on function public.platform_system_create_v46(uuid,uuid,text,text,text,text[],text) to authenticated;

-- Generate the one-time activation OTP for one selected configured system.
create or replace function public.platform_system_activate_v46(p_tenant_id uuid,p_device_id uuid)
returns jsonb language plpgsql security definer
set search_path=public,private,extensions,pg_temp
as $$
declare v_code text; v_exp timestamptz:=now()+interval '24 hours'; v_device public.business_devices%rowtype;
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then
    raise exception 'Platform admin required';
  end if;
  select * into v_device from public.business_devices where id=p_device_id and tenant_id=p_tenant_id for update;
  if v_device.id is null then raise exception 'System not found'; end if;
  if v_device.status not in ('pending','inactive') then raise exception 'Only pending or inactive systems can be activated'; end if;

  v_code:=upper(substr(encode(gen_random_bytes(8),'hex'),1,12));
  update public.business_devices
  set activation_hash=encode(digest(v_code,'sha256'),'hex'),
      activation_expires_at=v_exp,
      activation_issued_at=now(),
      activation_issued_by=auth.uid(),
      updated_at=now(),
      deactivated_at=null,
      deactivated_by=null,
      deactivation_reason=null
  where id=p_device_id;

  perform private.business_audit_write(
    p_tenant_id,'system.activation_issued','business_device',p_device_id,
    v_device.device_code,null,jsonb_build_object('location_id',v_device.location_id,'expires_at',v_exp)
  );

  return jsonb_build_object(
    'device_id',v_device.id,'device_code',v_device.device_code,'activation_code',v_code,
    'business_code',(select business_code from public.tenants where id=p_tenant_id),
    'expires_at',v_exp,'status','pending'
  );
end $$;
grant execute on function public.platform_system_activate_v46(uuid,uuid) to authenticated;

create or replace function public.platform_system_deactivate_v46(p_tenant_id uuid,p_device_id uuid,p_reason text default null)
returns void language plpgsql security definer
set search_path=public,private,pg_temp
as $$
declare v_code text;
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then
    raise exception 'Platform admin required';
  end if;
  select device_code into v_code from public.business_devices where id=p_device_id and tenant_id=p_tenant_id for update;
  if v_code is null then raise exception 'System not found'; end if;
  update public.business_devices
  set status='inactive',device_secret_hash=null,last_seen_at=null,
      deactivated_at=now(),deactivated_by=auth.uid(),deactivation_reason=nullif(trim(p_reason),''),
      updated_at=now()
  where id=p_device_id and tenant_id=p_tenant_id and status='active';
  perform private.business_audit_write(
    p_tenant_id,'system.deactivate','business_device',p_device_id,v_code,null,
    jsonb_build_object('reason',nullif(trim(p_reason),''))
  );
end $$;
grant execute on function public.platform_system_deactivate_v46(uuid,uuid,text) to authenticated;

create or replace function public.platform_systems_list_v46(p_tenant_id uuid)
returns table(
  id uuid,location_id uuid,location_name text,location_code text,device_code text,tracking_code text,
  name text,app_type text,platform_hint text,status text,allowed_modules text[],invoice_prefix text,
  installation_id text,activated_at timestamptz,activation_issued_at timestamptz,last_seen_at timestamptz,
  deactivated_at timestamptz,deactivation_reason text,created_at timestamptz
)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required'; end if;
  return query
  select d.id,d.location_id,l.name,l.location_code,d.device_code,d.tracking_code,d.name,d.app_type,d.platform_hint,
         d.status,d.allowed_modules,d.invoice_prefix,d.installation_id,d.activated_at,d.activation_issued_at,d.last_seen_at,
         d.deactivated_at,d.deactivation_reason,d.created_at
  from public.business_devices d
  join public.business_locations l on l.id=d.location_id
  where d.tenant_id=p_tenant_id
  order by l.sort_order,l.name,d.app_type,d.created_at;
end $$;
grant execute on function public.platform_systems_list_v46(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Keep V4.5 issue endpoint compatible, but route new UI to the two-step flow.
--    Existing callers still receive a one-time code.
-- ---------------------------------------------------------------------------
create or replace function public.platform_device_revoke(p_tenant_id uuid,p_device_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if not private.platform_v2_is_admin() then raise exception 'Platform admin required'; end if;
  update public.business_devices
  set status='revoked',device_secret_hash=null,activation_hash=null,activation_expires_at=null,updated_at=now()
  where id=p_device_id and tenant_id=p_tenant_id;
end $$;
grant execute on function public.platform_device_revoke(uuid,uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Data-quality helpers for immediate accounting/receivable visibility.
-- ---------------------------------------------------------------------------
create or replace function public.customer_outstanding_v46(p_tenant_id uuid,p_customer_id uuid)
returns jsonb language sql stable security definer set search_path=public,private,pg_temp
as $$
  select jsonb_build_object(
    'customer_id',p_customer_id,
    'outstanding',coalesce(sum(greatest(s.grand_total-coalesce((select sum(sp.amount) from public.sale_payments sp where sp.sale_id=s.id),0),0)),0)
  )
  from public.sales s
  where s.tenant_id=p_tenant_id and s.customer_id=p_customer_id and coalesce(s.status,'') not in('void','cancelled');
$$;
grant execute on function public.customer_outstanding_v46(uuid,uuid) to authenticated;

-- Ensure common operational indexes exist for registers/search.
create index if not exists idx_sales_tenant_date_customer_v46 on public.sales(tenant_id,sale_date desc,customer_id);
create index if not exists idx_purchases_tenant_date_supplier_v46 on public.purchases(tenant_id,purchase_date desc,supplier_id);
create index if not exists idx_expenses_tenant_date_v46 on public.expenses(tenant_id,expense_date desc);
create index if not exists idx_sale_payments_sale_v46 on public.sale_payments(sale_id,paid_at desc);
create index if not exists idx_purchase_payments_purchase_v46 on public.purchase_payments(purchase_id,paid_at desc);

commit;
select 'THQ V4.6 core fixes and activation lifecycle ready' as status;
