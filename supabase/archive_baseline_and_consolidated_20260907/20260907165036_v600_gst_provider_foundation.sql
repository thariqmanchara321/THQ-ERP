alter table public.gst_document_snapshots_v520
  add column legal_context jsonb not null default '{}'::jsonb;

alter table public.gst_document_line_snapshots_v520
  add column unit_code text;

create or replace function private.gst_snapshot_legal_context_before_insert_v600()
returns trigger
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_reg public.gst_registrations_v520%rowtype;
  v_party public.gst_party_registrations_v520%rowtype;
  v_party_id uuid;
  v_customer public.customers%rowtype;
  v_supplier public.suppliers%rowtype;
  v_location public.business_locations%rowtype;
  v_seller jsonb := '{}'::jsonb;
  v_buyer jsonb := '{}'::jsonb;
begin
  if new.tax_mode <> 'gst_registered' then
    new.legal_context := jsonb_build_object('tax_mode',new.tax_mode,'captured_at',now());
    return new;
  end if;

  select * into v_reg
  from public.gst_registrations_v520 r
  where r.id=new.thq_registration_id and r.tenant_id=new.tenant_id;

  select * into v_location
  from public.business_locations l
  where l.id=new.location_id and l.tenant_id=new.tenant_id;

  if nullif(new.quote_payload->>'party_profile_id','') is not null then
    select * into v_party
    from public.gst_party_registrations_v520 g
    where g.id=(new.quote_payload->>'party_profile_id')::uuid
      and g.tenant_id=new.tenant_id;
  end if;

  if new.source_type='sale' then
    select s.customer_id into v_party_id from public.sales s
    where s.id=new.source_id and s.tenant_id=new.tenant_id;
  elsif new.source_type='sales_return' then
    select s.customer_id into v_party_id
    from public.sales_returns sr
    join public.sales s on s.id=sr.sale_id and s.tenant_id=sr.tenant_id
    where sr.id=new.source_id and sr.tenant_id=new.tenant_id;
  elsif new.source_type='purchase' then
    select p.supplier_id into v_party_id from public.purchases p
    where p.id=new.source_id and p.tenant_id=new.tenant_id;
  elsif new.source_type='purchase_return' then
    select p.supplier_id into v_party_id
    from public.purchase_returns pr
    join public.purchases p on p.id=pr.purchase_id and p.tenant_id=pr.tenant_id
    where pr.id=new.source_id and pr.tenant_id=new.tenant_id;
  elsif new.source_type='purchase_invoice_v484' then
    select pi.supplier_id into v_party_id from public.purchase_invoices_v484 pi
    where pi.id=new.source_id and pi.tenant_id=new.tenant_id;
  end if;

  if new.direction='outward' and v_party_id is not null then
    select * into v_customer from public.customers c
    where c.id=v_party_id and c.tenant_id=new.tenant_id;
  elsif new.direction='inward' and v_party_id is not null then
    select * into v_supplier from public.suppliers s
    where s.id=v_party_id and s.tenant_id=new.tenant_id;
  end if;

  if new.direction='outward' then
    v_seller:=jsonb_strip_nulls(jsonb_build_object(
      'gstin',v_reg.gstin,'legal_name',v_reg.legal_name,'trade_name',v_reg.trade_name,
      'address_line1',coalesce(v_reg.address_line1,v_location.address_line1),
      'address_line2',coalesce(v_reg.address_line2,v_location.address_line2),
      'city',coalesce(v_reg.city,v_location.city),'postal_code',coalesce(v_reg.postal_code,v_location.postal_code),
      'state_code',v_reg.state_code,'country',coalesce(v_reg.country,v_location.country),
      'phone',v_location.phone,'email',v_location.email));
    v_buyer:=jsonb_strip_nulls(jsonb_build_object(
      'gstin',coalesce(v_party.gstin,new.recipient_gstin),'legal_name',coalesce(v_party.legal_name,v_customer.name),
      'trade_name',v_party.trade_name,'address_line1',coalesce(v_party.address_line1,v_customer.address_line1),
      'address_line2',coalesce(v_party.address_line2,v_customer.address_line2),'city',coalesce(v_party.city,v_customer.city),
      'postal_code',coalesce(v_party.postal_code,v_customer.postal_code),
      'state_code',coalesce(v_party.state_code,new.recipient_state_code,public.gst_state_code_resolve_v520(v_customer.state)),
      'country',coalesce(v_party.country,v_customer.country),'phone',v_customer.phone,'email',v_customer.email));
  else
    v_seller:=jsonb_strip_nulls(jsonb_build_object(
      'gstin',coalesce(v_party.gstin,new.supplier_gstin),'legal_name',coalesce(v_party.legal_name,v_supplier.name),
      'trade_name',v_party.trade_name,'address_line1',coalesce(v_party.address_line1,v_supplier.address_line1),
      'address_line2',coalesce(v_party.address_line2,v_supplier.address_line2),'city',coalesce(v_party.city,v_supplier.city),
      'postal_code',coalesce(v_party.postal_code,v_supplier.postal_code),
      'state_code',coalesce(v_party.state_code,new.supplier_state_code,public.gst_state_code_resolve_v520(v_supplier.state)),
      'country',coalesce(v_party.country,v_supplier.country),'phone',v_supplier.phone,'email',v_supplier.email));
    v_buyer:=jsonb_strip_nulls(jsonb_build_object(
      'gstin',v_reg.gstin,'legal_name',v_reg.legal_name,'trade_name',v_reg.trade_name,
      'address_line1',coalesce(v_reg.address_line1,v_location.address_line1),
      'address_line2',coalesce(v_reg.address_line2,v_location.address_line2),
      'city',coalesce(v_reg.city,v_location.city),'postal_code',coalesce(v_reg.postal_code,v_location.postal_code),
      'state_code',v_reg.state_code,'country',coalesce(v_reg.country,v_location.country),
      'phone',v_location.phone,'email',v_location.email));
  end if;

  new.legal_context:=jsonb_build_object(
    'version',1,'captured_at',now(),'seller',v_seller,'buyer',v_buyer,
    'place_of_supply_code',new.place_of_supply_code,'source','snapshot_insert_v600');
  return new;
end
$function$;

create trigger trg_gst_snapshot_legal_context_v600
before insert on public.gst_document_snapshots_v520
for each row execute function private.gst_snapshot_legal_context_before_insert_v600();

create or replace function private.gst_snapshot_line_unit_before_insert_v600()
returns trigger
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare v_source_type text;
begin
  new.unit_code:=nullif(trim(coalesce(new.line_payload->>'entered_unit_code',new.line_payload->>'unit_code','')),'');
  if new.unit_code is not null or new.source_line_id is null then return new; end if;
  select s.source_type into v_source_type from public.gst_document_snapshots_v520 s where s.id=new.snapshot_id;
  if v_source_type='sale' then
    select nullif(trim(coalesce(si.entered_unit_code,si.unit_code,'')),'') into new.unit_code
    from public.sale_items si where si.id=new.source_line_id;
  elsif v_source_type='sales_return' then
    select nullif(trim(coalesce(sri.entered_unit_code,'')),'') into new.unit_code
    from public.sales_return_items sri where sri.id=new.source_line_id;
  elsif v_source_type='purchase' then
    select nullif(trim(coalesce(pi.entered_unit_code,pi.unit_code,'')),'') into new.unit_code
    from public.purchase_items pi where pi.id=new.source_line_id;
  elsif v_source_type='purchase_return' then
    select nullif(trim(coalesce(pri.entered_unit_code,'')),'') into new.unit_code
    from public.purchase_return_items pri where pri.id=new.source_line_id;
  end if;
  return new;
end
$function$;

create trigger trg_gst_snapshot_line_unit_v600
before insert on public.gst_document_line_snapshots_v520
for each row execute function private.gst_snapshot_line_unit_before_insert_v600();

create table public.gst_provider_jobs_v600(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  registration_id uuid not null references public.gst_registrations_v520(id),
  snapshot_id uuid references public.gst_document_snapshots_v520(id),
  related_job_id uuid references public.gst_provider_jobs_v600(id),
  operation text not null check(operation in('einvoice_generate','einvoice_cancel','ewaybill_generate','ewaybill_cancel','gstr1_submit','gstr3b_submit','gstr2b_fetch','ims_fetch')),
  request_id uuid not null,
  provider_key text not null,
  status text not null default 'queued' check(status in('queued','processing','succeeded','failed','cancelled')),
  request_payload jsonb not null,
  request_hash text not null,
  response_payload jsonb not null default '{}'::jsonb,
  provider_reference text,
  irn text,
  ack_no text,
  ack_at timestamptz,
  signed_invoice text,
  signed_qr_code text,
  ewaybill_no text,
  ewaybill_date timestamptz,
  ewaybill_valid_until timestamptz,
  error_code text,
  error_message text,
  attempt_count integer not null default 0 check(attempt_count>=0),
  next_retry_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,operation,request_id)
);

create index gst_provider_jobs_v600_tenant_status_idx on public.gst_provider_jobs_v600(tenant_id,status,created_at desc);
create index gst_provider_jobs_v600_snapshot_idx on public.gst_provider_jobs_v600(tenant_id,snapshot_id,operation,created_at desc);
create unique index gst_provider_jobs_v600_active_snapshot_op_uidx
  on public.gst_provider_jobs_v600(tenant_id,snapshot_id,operation)
  where snapshot_id is not null and status in('queued','processing','succeeded');

alter table public.gst_provider_jobs_v600 enable row level security;

create or replace function private.gst_provider_job_guard_v600()
returns trigger
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
begin
  if new.tenant_id is distinct from old.tenant_id
     or new.registration_id is distinct from old.registration_id
     or new.snapshot_id is distinct from old.snapshot_id
     or new.related_job_id is distinct from old.related_job_id
     or new.operation is distinct from old.operation
     or new.request_id is distinct from old.request_id
     or new.provider_key is distinct from old.provider_key
     or new.request_payload is distinct from old.request_payload
     or new.request_hash is distinct from old.request_hash
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'GST provider job immutable request fields cannot be changed';
  end if;
  new.updated_at:=now();
  return new;
end
$function$;

create trigger trg_gst_provider_job_guard_v600
before update on public.gst_provider_jobs_v600
for each row execute function private.gst_provider_job_guard_v600();