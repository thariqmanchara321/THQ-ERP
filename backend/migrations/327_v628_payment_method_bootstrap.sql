begin;

create or replace function private.v628_seed_payment_methods(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare
  v_cash uuid;
  v_bank uuid;
  v_upi uuid;
  v_card uuid;
begin
  if exists (
    select 1
    from public.payment_methods_v522
    where tenant_id=p_tenant_id
  ) then
    return;
  end if;

  select id into v_cash
  from public.accounting_accounts
  where tenant_id=p_tenant_id and active and system_key='cash'
  limit 1;

  select id into v_bank
  from public.accounting_accounts
  where tenant_id=p_tenant_id and active and system_key='bank'
  limit 1;

  select id into v_upi
  from public.accounting_accounts
  where tenant_id=p_tenant_id and active and system_key='upi'
  limit 1;

  select id into v_card
  from public.accounting_accounts
  where tenant_id=p_tenant_id and active and system_key='card'
  limit 1;

  if v_cash is null or v_bank is null then
    raise exception 'Core cash/bank ledger accounts are not ready for tenant %',p_tenant_id;
  end if;

  insert into public.payment_methods_v522(
    tenant_id,code,display_name,ledger_account_id,active,allow_over_tender,sort_order
  )
  values
    (p_tenant_id,'cash','Cash',v_cash,true,true,10),
    (p_tenant_id,'upi','UPI',coalesce(v_upi,v_bank),true,false,20),
    (p_tenant_id,'card','Card',coalesce(v_card,v_bank),true,false,30),
    (p_tenant_id,'bank','Bank',v_bank,true,false,40),
    (p_tenant_id,'cheque','Cheque',v_bank,true,false,50),
    (p_tenant_id,'wallet','Wallet',v_bank,true,false,60),
    (p_tenant_id,'credit','Credit',null,true,false,70),
    (p_tenant_id,'other','Other',v_bank,true,false,80)
  on conflict(tenant_id,code) do nothing;
end
$function$;

revoke all on function private.v628_seed_payment_methods(uuid)
  from public,anon,authenticated;

create or replace function public.platform_create_business(
  p_name text,
  p_slug text,
  p_business_type text,
  p_module_keys text[]
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_tenant_id uuid;
  v_slug text;
begin
  if not private.is_platform_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;

  if nullif(trim(p_name),'') is null then
    raise exception 'Business name is required';
  end if;

  v_slug:=lower(trim(p_slug));
  if nullif(v_slug,'') is null then
    raise exception 'Business slug is required';
  end if;

  if v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception 'Slug may contain only lowercase letters, numbers and hyphens';
  end if;

  if exists(select 1 from public.tenants t where t.slug=v_slug) then
    raise exception 'A business with this slug already exists';
  end if;

  if exists(
    select 1
    from unnest(coalesce(p_module_keys,array[]::text[])) requested(module_key)
    left join public.modules m on m.key=requested.module_key
    where m.key is null
  ) then
    raise exception 'One or more selected modules do not exist';
  end if;

  insert into public.tenants(name,slug,business_type,status)
  values(trim(p_name),v_slug,nullif(trim(p_business_type),''),'active')
  returning id into v_tenant_id;

  insert into public.tenant_settings(tenant_id,currency_code,timezone,locale)
  values(v_tenant_id,'INR','Asia/Kolkata','en_IN');

  insert into public.tenant_modules(tenant_id,module_key,enabled)
  select v_tenant_id,m.key,true
  from public.modules m
  where m.key='dashboard'
     or m.key=any(coalesce(p_module_keys,array[]::text[]))
  on conflict(tenant_id,module_key)
  do update set enabled=true;

  perform private.seed_default_roles(v_tenant_id);
  perform private.v500_ensure_main_location(v_tenant_id);
  perform private.v628_seed_payment_methods(v_tenant_id);

  return v_tenant_id;
end
$function$;

do $block$
declare
  v_tenant_id uuid;
begin
  for v_tenant_id in
    select t.id
    from public.tenants t
    where t.status='active'
      and not exists(
        select 1
        from public.payment_methods_v522 pm
        where pm.tenant_id=t.id
      )
  loop
    perform private.v628_seed_payment_methods(v_tenant_id);
  end loop;
end
$block$;

insert into public.thq_schema_releases(
  migration_no,
  schema_version,
  release_name,
  notes
)
values(
  327,
  '6.2.8-payment-method-bootstrap',
  'Payment Method Bootstrap for New Businesses',
  'Ensures new businesses receive canonical Cash, UPI, Card, Bank, Cheque, Wallet, Credit and Other payment methods mapped to seeded ledger accounts, and backfills active tenants with no payment methods.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
