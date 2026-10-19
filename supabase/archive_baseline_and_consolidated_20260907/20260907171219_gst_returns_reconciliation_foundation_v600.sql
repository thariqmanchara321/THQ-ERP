create table if not exists public.gst_turnover_profiles_v600(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  financial_year_start date not null,
  aato_crore numeric(18,4) not null check(aato_crore>=0),
  source text not null default 'manual' check(source in('manual','portal','provider','audited')),
  verified boolean not null default false,
  notes text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,financial_year_start)
);

create table if not exists public.gst_return_periods_v600(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  registration_id uuid not null references public.gst_registrations_v520(id),
  period_start date not null,
  period_end date not null,
  frequency text not null default 'monthly' check(frequency in('monthly','quarterly')),
  status text not null default 'open' check(status in('open','review','locked','filed')),
  gstr1_filed_at timestamptz,
  gstr1a_filed_at timestamptz,
  gstr3b_filed_at timestamptz,
  lock_reason text,
  locked_by uuid,
  locked_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(period_end>=period_start),
  unique(tenant_id,registration_id,period_start,period_end)
);

create table if not exists public.gst_portal_import_batches_v600(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  registration_id uuid not null references public.gst_registrations_v520(id),
  period_start date not null,
  source text not null check(source in('gstr2b','ims')),
  request_id uuid not null,
  content_hash text not null,
  row_count integer not null check(row_count>=0),
  created_by uuid,
  created_at timestamptz not null default now(),
  unique(tenant_id,source,request_id)
);

create table if not exists public.gst_portal_itc_documents_v600(
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.gst_portal_import_batches_v600(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  registration_id uuid not null references public.gst_registrations_v520(id),
  period_start date not null,
  source text not null check(source in('gstr2b','ims')),
  portal_document_key text not null,
  supplier_gstin text,
  supplier_name text,
  document_type text not null check(document_type in('invoice','debit_note','credit_note','import_goods','import_service','isd','other')),
  document_number text,
  document_date date,
  place_of_supply_code text,
  taxable_value numeric(18,2) not null default 0,
  igst numeric(18,2) not null default 0,
  cgst numeric(18,2) not null default 0,
  sgst numeric(18,2) not null default 0,
  utgst numeric(18,2) not null default 0,
  cess numeric(18,2) not null default 0,
  document_total numeric(18,2) not null default 0,
  itc_available boolean not null default true,
  ims_action text not null default 'no_action' check(ims_action in('accepted','rejected','pending','no_action','not_applicable')),
  portal_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(batch_id,portal_document_key)
);

alter table public.gst_turnover_profiles_v600 enable row level security;
alter table public.gst_return_periods_v600 enable row level security;
alter table public.gst_portal_import_batches_v600 enable row level security;
alter table public.gst_portal_itc_documents_v600 enable row level security;

revoke all on public.gst_turnover_profiles_v600 from anon,authenticated;
revoke all on public.gst_return_periods_v600 from anon,authenticated;
revoke all on public.gst_portal_import_batches_v600 from anon,authenticated;
revoke all on public.gst_portal_itc_documents_v600 from anon,authenticated;

create index if not exists idx_gst_turnover_profiles_v600_tenant_fy on public.gst_turnover_profiles_v600(tenant_id,financial_year_start desc);
create index if not exists idx_gst_return_periods_v600_lookup on public.gst_return_periods_v600(tenant_id,registration_id,period_start,period_end,status);
create index if not exists idx_gst_portal_batches_v600_period on public.gst_portal_import_batches_v600(tenant_id,registration_id,period_start,source,created_at desc);
create index if not exists idx_gst_portal_docs_v600_match on public.gst_portal_itc_documents_v600(tenant_id,registration_id,period_start,upper(supplier_gstin),upper(document_number));

create or replace function private.gst_append_only_guard_v600()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
begin
  raise exception 'GST portal import evidence is append-only';
end
$function$;

drop trigger if exists trg_gst_portal_batch_append_only_v600 on public.gst_portal_import_batches_v600;
create trigger trg_gst_portal_batch_append_only_v600 before update or delete on public.gst_portal_import_batches_v600 for each row execute function private.gst_append_only_guard_v600();
drop trigger if exists trg_gst_portal_doc_append_only_v600 on public.gst_portal_itc_documents_v600;
create trigger trg_gst_portal_doc_append_only_v600 before update or delete on public.gst_portal_itc_documents_v600 for each row execute function private.gst_append_only_guard_v600();

create or replace function private.gst_period_lock_guard_v600()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare v_registration uuid;
begin
  if tg_table_name='gst_document_snapshots_v520' then
    v_registration:=new.thq_registration_id;
  else
    select m.registration_id into v_registration
    from public.gst_location_registrations_v520 m
    where m.tenant_id=new.tenant_id and m.location_id=new.location_id
      and new.document_date between m.effective_from and coalesce(m.effective_to,'infinity'::date)
    order by m.effective_from desc limit 1;
  end if;

  if exists(
    select 1 from public.gst_return_periods_v600 p
    where p.tenant_id=new.tenant_id
      and (v_registration is null or p.registration_id=v_registration)
      and new.document_date between p.period_start and p.period_end
      and (p.status in('locked','filed') or p.gstr3b_filed_at is not null)
  ) then
    raise exception 'GST return period is locked/filed for document date %',new.document_date;
  end if;
  return new;
end
$function$;

drop trigger if exists trg_gst_snapshot_period_lock_v600 on public.gst_document_snapshots_v520;
create trigger trg_gst_snapshot_period_lock_v600 before insert on public.gst_document_snapshots_v520 for each row execute function private.gst_period_lock_guard_v600();
drop trigger if exists trg_gst_legacy_period_lock_v600 on public.gst_legacy_document_markers_v520;
create trigger trg_gst_legacy_period_lock_v600 before insert on public.gst_legacy_document_markers_v520 for each row execute function private.gst_period_lock_guard_v600();

create or replace function public.gst_turnover_profile_save_v600(
  p_tenant_id uuid,
  p_financial_year_start date,
  p_aato_crore numeric,
  p_source text default 'manual',
  p_verified boolean default false,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare v_id uuid; v_fy date:=p_financial_year_start; v_source text:=lower(trim(coalesce(p_source,'manual')));
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.configure') then raise exception 'GST configuration permission required'; end if;
  if v_fy is null or extract(month from v_fy)<>4 or extract(day from v_fy)<>1 then raise exception 'Financial year start must be 1 April'; end if;
  if p_aato_crore is null or p_aato_crore<0 then raise exception 'AATO must be zero or positive'; end if;
  if v_source not in('manual','portal','provider','audited') then raise exception 'Invalid AATO source'; end if;
  insert into public.gst_turnover_profiles_v600(tenant_id,financial_year_start,aato_crore,source,verified,notes,created_by)
  values(p_tenant_id,v_fy,p_aato_crore,v_source,coalesce(p_verified,false),nullif(trim(coalesce(p_notes,'')),''),auth.uid())
  on conflict(tenant_id,financial_year_start) do update set aato_crore=excluded.aato_crore,source=excluded.source,verified=excluded.verified,notes=excluded.notes,updated_at=now()
  returning id into v_id;
  perform private.business_audit_write_v471(p_tenant_id,'gst.turnover_profile.save','gst_turnover_profile',v_id,v_fy::text,null,(select to_jsonb(x) from public.gst_turnover_profiles_v600 x where x.id=v_id));
  return (select to_jsonb(x) from public.gst_turnover_profiles_v600 x where x.id=v_id);
end
$function$;

create or replace function public.gst_turnover_profile_get_v600(p_tenant_id uuid,p_document_date date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $function$
declare v_fy date; v jsonb;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then raise exception 'GST compliance view permission required'; end if;
  v_fy:=case when extract(month from coalesce(p_document_date,current_date))>=4 then make_date(extract(year from coalesce(p_document_date,current_date))::int,4,1) else make_date((extract(year from coalesce(p_document_date,current_date))::int)-1,4,1) end;
  select to_jsonb(x) into v from public.gst_turnover_profiles_v600 x where x.tenant_id=p_tenant_id and x.financial_year_start=v_fy;
  return coalesce(v,jsonb_build_object('financial_year_start',v_fy,'configured',false));
end
$function$;

create or replace function public.gst_return_period_ensure_v600(
  p_tenant_id uuid,
  p_registration_id uuid,
  p_period_start date,
  p_frequency text default 'monthly'
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare v_frequency text:=lower(trim(coalesce(p_frequency,'monthly'))); v_start date; v_end date; v_id uuid;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.returns') then raise exception 'GST returns permission required'; end if;
  if not exists(select 1 from public.gst_registrations_v520 r where r.id=p_registration_id and r.tenant_id=p_tenant_id and r.active) then raise exception 'GST registration not found'; end if;
  if v_frequency not in('monthly','quarterly') then raise exception 'Return frequency must be monthly or quarterly'; end if;
  v_start:=date_trunc('month',p_period_start)::date;
  v_end:=case when v_frequency='monthly' then (v_start+interval '1 month-1 day')::date else (v_start+interval '3 months-1 day')::date end;
  insert into public.gst_return_periods_v600(tenant_id,registration_id,period_start,period_end,frequency,created_by)
  values(p_tenant_id,p_registration_id,v_start,v_end,v_frequency,auth.uid())
  on conflict(tenant_id,registration_id,period_start,period_end) do update set updated_at=public.gst_return_periods_v600.updated_at
  returning id into v_id;
  return (select to_jsonb(x) from public.gst_return_periods_v600 x where x.id=v_id);
end
$function$;

create or replace function public.gst_return_period_action_v600(
  p_tenant_id uuid,
  p_period_id uuid,
  p_action text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare p public.gst_return_periods_v600%rowtype; a text:=lower(trim(coalesce(p_action,''))); before_row jsonb;
begin
  select * into p from public.gst_return_periods_v600 where id=p_period_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'GST return period not found'; end if;
  before_row:=to_jsonb(p);
  if a in('lock','unlock') then
    if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.period_lock') then raise exception 'GST period-lock permission required'; end if;
  else
    if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.submit') then raise exception 'GST submission permission required'; end if;
  end if;

  if a='review' then
    if p.status in('locked','filed') then raise exception 'Locked/filed GST period cannot return to review'; end if;
    update public.gst_return_periods_v600 set status='review',updated_at=now() where id=p.id;
  elsif a='open' then
    if p.status in('locked','filed') then raise exception 'Locked/filed GST period cannot be reopened this way'; end if;
    update public.gst_return_periods_v600 set status='open',updated_at=now() where id=p.id;
  elsif a='lock' then
    if p.gstr3b_filed_at is not null then raise exception 'Filed GSTR-3B period is permanently locked'; end if;
    update public.gst_return_periods_v600 set status='locked',lock_reason=nullif(trim(coalesce(p_reason,'')),''),locked_by=auth.uid(),locked_at=now(),updated_at=now() where id=p.id;
  elsif a='unlock' then
    if p.gstr3b_filed_at is not null or p.status='filed' then raise exception 'Filed GST period cannot be unlocked'; end if;
    update public.gst_return_periods_v600 set status='open',lock_reason=null,locked_by=null,locked_at=null,updated_at=now() where id=p.id;
  elsif a='mark_gstr1_filed' then
    if p.gstr1_filed_at is not null then raise exception 'GSTR-1 is already marked filed'; end if;
    update public.gst_return_periods_v600 set gstr1_filed_at=now(),status='review',updated_at=now() where id=p.id;
  elsif a='mark_gstr1a_filed' then
    if p.gstr1_filed_at is null then raise exception 'GSTR-1 must be filed before GSTR-1A'; end if;
    if p.gstr1a_filed_at is not null then raise exception 'GSTR-1A can be marked filed only once per period'; end if;
    if p.gstr3b_filed_at is not null then raise exception 'GSTR-1A cannot be filed after GSTR-3B'; end if;
    update public.gst_return_periods_v600 set gstr1a_filed_at=now(),status='review',updated_at=now() where id=p.id;
  elsif a='mark_gstr3b_filed' then
    if p.gstr1_filed_at is null then raise exception 'GSTR-1 must be filed before final GSTR-3B period lock'; end if;
    if p.gstr3b_filed_at is not null then raise exception 'GSTR-3B is already marked filed'; end if;
    update public.gst_return_periods_v600 set gstr3b_filed_at=now(),status='filed',lock_reason=coalesce(nullif(trim(coalesce(p_reason,'')),''),'GSTR-3B filed'),locked_by=auth.uid(),locked_at=now(),updated_at=now() where id=p.id;
  else
    raise exception 'Unsupported GST return-period action';
  end if;
  perform private.business_audit_write_v471(p_tenant_id,'gst.return_period.'||a,'gst_return_period',p.id,p.period_start::text,before_row,(select to_jsonb(x) from public.gst_return_periods_v600 x where x.id=p.id));
  return (select to_jsonb(x) from public.gst_return_periods_v600 x where x.id=p.id);
end
$function$;

create or replace function public.gst_return_periods_list_v600(p_tenant_id uuid,p_registration_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $function$
declare v jsonb;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then raise exception 'GST compliance view permission required'; end if;
  select coalesce(jsonb_agg(to_jsonb(p) order by p.period_start desc),'[]'::jsonb) into v from public.gst_return_periods_v600 p where p.tenant_id=p_tenant_id and (p_registration_id is null or p.registration_id=p_registration_id);
  return v;
end
$function$;

create or replace function public.gst_portal_itc_import_v600(
  p_tenant_id uuid,
  p_registration_id uuid,
  p_period_start date,
  p_source text,
  p_request_id uuid,
  p_documents jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare
  src text:=lower(trim(coalesce(p_source,''))); per date:=date_trunc('month',p_period_start)::date; docs jsonb:=coalesce(p_documents,'[]'::jsonb);
  h text; b public.gst_portal_import_batches_v600%rowtype; x jsonb; k text; cnt int:=0; dtype text; action text;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.reconcile') then raise exception 'GST reconciliation permission required'; end if;
  if src not in('gstr2b','ims') then raise exception 'Portal import source must be gstr2b or ims'; end if;
  if p_request_id is null then raise exception 'Stable import request ID is required'; end if;
  if jsonb_typeof(docs)<>'array' then raise exception 'Portal import documents must be a JSON array'; end if;
  if jsonb_array_length(docs)>50000 then raise exception 'Portal import batch exceeds 50000 records'; end if;
  if not exists(select 1 from public.gst_registrations_v520 r where r.id=p_registration_id and r.tenant_id=p_tenant_id) then raise exception 'GST registration not found'; end if;
  h:=encode(extensions.digest(convert_to(jsonb_build_object('registration_id',p_registration_id,'period_start',per,'source',src,'documents',docs)::text,'UTF8'),'sha256'),'hex');
  select * into b from public.gst_portal_import_batches_v600 where tenant_id=p_tenant_id and source=src and request_id=p_request_id;
  if found then
    if b.content_hash<>h then raise exception 'Portal import request ID was already used with different content'; end if;
    return jsonb_build_object('batch_id',b.id,'row_count',b.row_count,'idempotent_replay',true,'content_hash',b.content_hash);
  end if;
  insert into public.gst_portal_import_batches_v600(tenant_id,registration_id,period_start,source,request_id,content_hash,row_count,created_by)
  values(p_tenant_id,p_registration_id,per,src,p_request_id,h,jsonb_array_length(docs),auth.uid()) returning * into b;

  for x in select value from jsonb_array_elements(docs) loop
    dtype:=lower(trim(coalesce(x->>'document_type','invoice')));
    if dtype not in('invoice','debit_note','credit_note','import_goods','import_service','isd','other') then raise exception 'Invalid portal document_type %',dtype; end if;
    action:=lower(trim(coalesce(x->>'ims_action',case when src='ims' then 'no_action' else 'not_applicable' end)));
    if action not in('accepted','rejected','pending','no_action','not_applicable') then raise exception 'Invalid IMS action %',action; end if;
    k:=nullif(trim(coalesce(x->>'portal_document_key','')),'');
    if k is null then
      k:=encode(extensions.digest(convert_to(jsonb_build_object('gstin',upper(trim(coalesce(x->>'supplier_gstin',''))),'document_type',dtype,'document_number',upper(trim(coalesce(x->>'document_number',''))),'document_date',x->>'document_date')::text,'UTF8'),'sha256'),'hex');
    end if;
    insert into public.gst_portal_itc_documents_v600(batch_id,tenant_id,registration_id,period_start,source,portal_document_key,supplier_gstin,supplier_name,document_type,document_number,document_date,place_of_supply_code,taxable_value,igst,cgst,sgst,utgst,cess,document_total,itc_available,ims_action,portal_payload)
    values(b.id,p_tenant_id,p_registration_id,per,src,k,nullif(upper(trim(coalesce(x->>'supplier_gstin',''))),''),nullif(trim(coalesce(x->>'supplier_name','')),''),dtype,nullif(trim(coalesce(x->>'document_number','')),''),nullif(x->>'document_date','')::date,nullif(trim(coalesce(x->>'place_of_supply_code','')),''),coalesce(nullif(x->>'taxable_value','')::numeric,0),coalesce(nullif(x->>'igst','')::numeric,0),coalesce(nullif(x->>'cgst','')::numeric,0),coalesce(nullif(x->>'sgst','')::numeric,0),coalesce(nullif(x->>'utgst','')::numeric,0),coalesce(nullif(x->>'cess','')::numeric,0),coalesce(nullif(x->>'document_total','')::numeric,0),coalesce(nullif(x->>'itc_available','')::boolean,true),action,x);
    cnt:=cnt+1;
  end loop;
  perform private.business_audit_write_v471(p_tenant_id,'gst.portal_import.'||src,'gst_portal_import_batch',b.id,per::text,null,jsonb_build_object('registration_id',p_registration_id,'source',src,'row_count',cnt,'content_hash',h));
  return jsonb_build_object('batch_id',b.id,'row_count',cnt,'idempotent_replay',false,'content_hash',h);
end
$function$;

create or replace function public.gst_gstr2b_reconciliation_v600(
  p_tenant_id uuid,
  p_registration_id uuid,
  p_period_start date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $function$
declare per date:=date_trunc('month',p_period_start)::date; b uuid; details jsonb; summary jsonb;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.reconcile') then raise exception 'GST reconciliation permission required'; end if;
  select x.id into b from public.gst_portal_import_batches_v600 x where x.tenant_id=p_tenant_id and x.registration_id=p_registration_id and x.period_start=per and x.source='gstr2b' order by x.created_at desc limit 1;
  if b is null then return jsonb_build_object('period_start',per,'registration_id',p_registration_id,'gstr2b_imported',false,'ready',false,'blockers',jsonb_build_array('gstr2b_not_imported')); end if;

  with books as(
    select s.id snapshot_id,s.source_type,s.document_number,s.document_date,s.supplier_gstin,s.taxable_total,s.igst_total,s.cgst_total,s.sgst_total,s.utgst_total,s.cess_total,s.grand_total,
      case when s.source_type in('purchase_return','credit_note') or s.document_class='credit_note' then -1 else 1 end effect
    from public.gst_document_snapshots_v520 s
    where s.tenant_id=p_tenant_id and s.thq_registration_id=p_registration_id and s.direction='inward' and date_trunc('month',s.document_date)::date=per
  ), portal as(
    select d.*,case when d.document_type='credit_note' then -1 else 1 end effect
    from public.gst_portal_itc_documents_v600 d where d.batch_id=b
  ), joined as(
    select bo.snapshot_id,bo.source_type,bo.document_number book_number,bo.document_date book_date,bo.supplier_gstin book_gstin,
      bo.taxable_total book_taxable,bo.igst_total book_igst,bo.cgst_total book_cgst,bo.sgst_total+bo.utgst_total book_sgst_utgst,bo.cess_total book_cess,bo.grand_total book_total,bo.effect book_effect,
      po.id portal_id,po.document_type,po.document_number portal_number,po.document_date portal_date,po.supplier_gstin portal_gstin,
      po.taxable_value portal_taxable,po.igst portal_igst,po.cgst portal_cgst,po.sgst+po.utgst portal_sgst_utgst,po.cess portal_cess,po.document_total portal_total,po.effect portal_effect,po.itc_available,po.ims_action,
      case when po.id is null then 'books_only'
           when abs(coalesce(bo.taxable_total,0)-coalesce(po.taxable_value,0))<=0.01 and abs(coalesce(bo.igst_total,0)-coalesce(po.igst,0))<=0.01 and abs(coalesce(bo.cgst_total,0)-coalesce(po.cgst,0))<=0.01 and abs(coalesce(bo.sgst_total+bo.utgst_total,0)-coalesce(po.sgst+po.utgst,0))<=0.01 and abs(coalesce(bo.cess_total,0)-coalesce(po.cess,0))<=0.01 then 'matched_exact'
           else 'matched_value_mismatch' end match_status
    from books bo left join portal po on upper(regexp_replace(coalesce(po.supplier_gstin,''),'\s','','g'))=upper(regexp_replace(coalesce(bo.supplier_gstin,''),'\s','','g')) and upper(trim(coalesce(po.document_number,'')))=upper(trim(coalesce(bo.document_number,''))) and po.document_date=bo.document_date
  ), portal_only as(
    select null::uuid snapshot_id,null::text source_type,null::text book_number,null::date book_date,null::text book_gstin,null::numeric book_taxable,null::numeric book_igst,null::numeric book_cgst,null::numeric book_sgst_utgst,null::numeric book_cess,null::numeric book_total,null::int book_effect,
      po.id portal_id,po.document_type,po.document_number portal_number,po.document_date portal_date,po.supplier_gstin portal_gstin,po.taxable_value portal_taxable,po.igst portal_igst,po.cgst portal_cgst,po.sgst+po.utgst portal_sgst_utgst,po.cess portal_cess,po.document_total portal_total,po.effect portal_effect,po.itc_available,po.ims_action,'portal_only'::text match_status
    from portal po where not exists(select 1 from books bo where upper(regexp_replace(coalesce(po.supplier_gstin,''),'\s','','g'))=upper(regexp_replace(coalesce(bo.supplier_gstin,''),'\s','','g')) and upper(trim(coalesce(po.document_number,'')))=upper(trim(coalesce(bo.document_number,''))) and po.document_date=bo.document_date)
  ), all_rows as(select * from joined union all select * from portal_only)
  select coalesce(jsonb_agg(to_jsonb(all_rows) order by coalesce(book_date,portal_date),coalesce(book_number,portal_number)),'[]'::jsonb),
    jsonb_build_object(
      'matched_exact',count(*) filter(where match_status='matched_exact'),
      'matched_value_mismatch',count(*) filter(where match_status='matched_value_mismatch'),
      'books_only',count(*) filter(where match_status='books_only'),
      'portal_only',count(*) filter(where match_status='portal_only'),
      'books_itc',round(coalesce(sum(book_effect*(coalesce(book_igst,0)+coalesce(book_cgst,0)+coalesce(book_sgst_utgst,0)+coalesce(book_cess,0))) filter(where snapshot_id is not null),0),2),
      'portal_itc',round(coalesce(sum(portal_effect*(coalesce(portal_igst,0)+coalesce(portal_cgst,0)+coalesce(portal_sgst_utgst,0)+coalesce(portal_cess,0))) filter(where portal_id is not null and itc_available),0),2),
      'matched_claimable_itc',round(coalesce(sum(portal_effect*(coalesce(portal_igst,0)+coalesce(portal_cgst,0)+coalesce(portal_sgst_utgst,0)+coalesce(portal_cess,0))) filter(where match_status='matched_exact' and itc_available),0),2)
    )
  into details,summary from all_rows;

  return jsonb_build_object('period_start',per,'registration_id',p_registration_id,'gstr2b_imported',true,'batch_id',b,'ready',coalesce((summary->>'matched_value_mismatch')::int,0)=0 and coalesce((summary->>'books_only')::int,0)=0 and coalesce((summary->>'portal_only')::int,0)=0,'summary',summary,'documents',details);
end
$function$;

revoke all on function public.gst_turnover_profile_save_v600(uuid,date,numeric,text,boolean,text) from public,anon;
grant execute on function public.gst_turnover_profile_save_v600(uuid,date,numeric,text,boolean,text) to authenticated;
revoke all on function public.gst_turnover_profile_get_v600(uuid,date) from public,anon;
grant execute on function public.gst_turnover_profile_get_v600(uuid,date) to authenticated;
revoke all on function public.gst_return_period_ensure_v600(uuid,uuid,date,text) from public,anon;
grant execute on function public.gst_return_period_ensure_v600(uuid,uuid,date,text) to authenticated;
revoke all on function public.gst_return_period_action_v600(uuid,uuid,text,text) from public,anon;
grant execute on function public.gst_return_period_action_v600(uuid,uuid,text,text) to authenticated;
revoke all on function public.gst_return_periods_list_v600(uuid,uuid) from public,anon;
grant execute on function public.gst_return_periods_list_v600(uuid,uuid) to authenticated;
revoke all on function public.gst_portal_itc_import_v600(uuid,uuid,date,text,uuid,jsonb) from public,anon;
grant execute on function public.gst_portal_itc_import_v600(uuid,uuid,date,text,uuid,jsonb) to authenticated;
revoke all on function public.gst_gstr2b_reconciliation_v600(uuid,uuid,date) from public,anon;
grant execute on function public.gst_gstr2b_reconciliation_v600(uuid,uuid,date) to authenticated;