alter table public.gst_provider_jobs_v600
  add column if not exists return_period_id uuid references public.gst_return_periods_v600(id);
create index if not exists idx_gst_provider_jobs_v600_period on public.gst_provider_jobs_v600(tenant_id,return_period_id,operation,created_at desc);

create or replace function private.gst_provider_job_guard_v600()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
begin
  if new.tenant_id is distinct from old.tenant_id
     or new.registration_id is distinct from old.registration_id
     or new.snapshot_id is distinct from old.snapshot_id
     or new.return_period_id is distinct from old.return_period_id
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

create or replace function private.gst_portal_itc_import_core_v600(
  p_tenant_id uuid,
  p_registration_id uuid,
  p_period_start date,
  p_source text,
  p_request_id uuid,
  p_documents jsonb,
  p_actor uuid default null
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
  values(p_tenant_id,p_registration_id,per,src,p_request_id,h,jsonb_array_length(docs),p_actor) returning * into b;
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
  return jsonb_build_object('batch_id',b.id,'row_count',cnt,'idempotent_replay',false,'content_hash',h);
end
$function$;

create or replace function public.gst_portal_itc_import_v600(
  p_tenant_id uuid,p_registration_id uuid,p_period_start date,p_source text,p_request_id uuid,p_documents jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare v jsonb;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.reconcile') then raise exception 'GST reconciliation permission required'; end if;
  v:=private.gst_portal_itc_import_core_v600(p_tenant_id,p_registration_id,p_period_start,p_source,p_request_id,p_documents,auth.uid());
  perform private.business_audit_write_v471(p_tenant_id,'gst.portal_import.'||lower(trim(p_source)),'gst_portal_import_batch',(v->>'batch_id')::uuid,date_trunc('month',p_period_start)::date::text,null,v);
  return v;
end
$function$;

create or replace function public.gst_portal_itc_import_service_v600(
  p_tenant_id uuid,p_registration_id uuid,p_period_start date,p_source text,p_request_id uuid,p_documents jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
begin
  perform private.gst_service_role_assert_v600();
  return private.gst_portal_itc_import_core_v600(p_tenant_id,p_registration_id,p_period_start,p_source,p_request_id,p_documents,null);
end
$function$;

create or replace function private.gst_provider_enqueue_return_v600(
  p_tenant_id uuid,p_registration_id uuid,p_period_id uuid,p_operation text,p_request_id uuid,p_provider_key text,p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare v_hash text; existing public.gst_provider_jobs_v600%rowtype; v_id uuid;
begin
  if p_request_id is null then raise exception 'Stable request ID is required'; end if;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('tenant_id',p_tenant_id,'period_id',p_period_id,'operation',p_operation,'payload',coalesce(p_payload,'{}'::jsonb))::text,'UTF8'),'sha256'),'hex');
  select * into existing from public.gst_provider_jobs_v600 where tenant_id=p_tenant_id and operation=p_operation and request_id=p_request_id;
  if found then
    if existing.request_hash<>v_hash then raise exception 'GST provider request ID was already used with a different payload'; end if;
    return jsonb_build_object('job_id',existing.id,'status',existing.status,'idempotent_replay',true,'request_hash',existing.request_hash);
  end if;
  insert into public.gst_provider_jobs_v600(tenant_id,registration_id,return_period_id,operation,request_id,provider_key,status,request_payload,request_hash,created_by)
  values(p_tenant_id,p_registration_id,p_period_id,p_operation,p_request_id,p_provider_key,'queued',coalesce(p_payload,'{}'::jsonb),v_hash,auth.uid()) returning id into v_id;
  return jsonb_build_object('job_id',v_id,'status','queued','idempotent_replay',false,'request_hash',v_hash);
end
$function$;

create or replace function public.gst_gstr1_submit_queue_v600(p_tenant_id uuid,p_period_id uuid,p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare p public.gst_return_periods_v600%rowtype; preview jsonb; r public.gst_registrations_v520%rowtype;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.submit') then raise exception 'GST submission permission required'; end if;
  select * into p from public.gst_return_periods_v600 where id=p_period_id and tenant_id=p_tenant_id;
  if not found then raise exception 'GST return period not found'; end if;
  if p.gstr1_filed_at is not null then raise exception 'GSTR-1 is already marked filed'; end if;
  preview:=public.gst_gstr1_preview_v600(p_tenant_id,p.registration_id,p.period_start,p.period_end);
  if coalesce((preview->>'ready')::boolean,false) is not true then raise exception 'GSTR-1 preview is not submission-ready: %',preview->'blockers'; end if;
  r:=private.gst_provider_connection_assert_v600(p_tenant_id,p.registration_id,'returns');
  if exists(select 1 from public.gst_provider_jobs_v600 j where j.tenant_id=p_tenant_id and j.return_period_id=p.id and j.operation='gstr1_submit' and j.status in('queued','processing','succeeded')) then
    if not exists(select 1 from public.gst_provider_jobs_v600 j where j.tenant_id=p_tenant_id and j.return_period_id=p.id and j.operation='gstr1_submit' and j.request_id=p_request_id) then raise exception 'An active GSTR-1 submission already exists for this period'; end if;
  end if;
  return private.gst_provider_enqueue_return_v600(p_tenant_id,p.registration_id,p.id,'gstr1_submit',p_request_id,r.provider_key,preview);
end
$function$;

create or replace function public.gst_gstr3b_submit_queue_v600(p_tenant_id uuid,p_period_id uuid,p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare p public.gst_return_periods_v600%rowtype; preview jsonb; r public.gst_registrations_v520%rowtype;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.submit') then raise exception 'GST submission permission required'; end if;
  select * into p from public.gst_return_periods_v600 where id=p_period_id and tenant_id=p_tenant_id;
  if not found then raise exception 'GST return period not found'; end if;
  if p.gstr3b_filed_at is not null then raise exception 'GSTR-3B is already marked filed'; end if;
  preview:=public.gst_gstr3b_preview_v600(p_tenant_id,p.registration_id,p.period_start,p.period_end);
  if coalesce((preview->>'ready')::boolean,false) is not true then raise exception 'GSTR-3B preview is not submission-ready: %',preview->'blockers'; end if;
  r:=private.gst_provider_connection_assert_v600(p_tenant_id,p.registration_id,'returns');
  if exists(select 1 from public.gst_provider_jobs_v600 j where j.tenant_id=p_tenant_id and j.return_period_id=p.id and j.operation='gstr3b_submit' and j.status in('queued','processing','succeeded')) then
    if not exists(select 1 from public.gst_provider_jobs_v600 j where j.tenant_id=p_tenant_id and j.return_period_id=p.id and j.operation='gstr3b_submit' and j.request_id=p_request_id) then raise exception 'An active GSTR-3B submission already exists for this period'; end if;
  end if;
  return private.gst_provider_enqueue_return_v600(p_tenant_id,p.registration_id,p.id,'gstr3b_submit',p_request_id,r.provider_key,preview);
end
$function$;

create or replace function public.gst_gstr2b_fetch_queue_v600(p_tenant_id uuid,p_period_id uuid,p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare p public.gst_return_periods_v600%rowtype; r public.gst_registrations_v520%rowtype; payload jsonb;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.reconcile') then raise exception 'GST reconciliation permission required'; end if;
  select * into p from public.gst_return_periods_v600 where id=p_period_id and tenant_id=p_tenant_id;
  if not found then raise exception 'GST return period not found'; end if;
  if p.frequency<>'monthly' then raise exception 'GSTR-2B provider fetch is queued monthly'; end if;
  r:=private.gst_provider_connection_assert_v600(p_tenant_id,p.registration_id,'gstr2b');
  payload:=jsonb_build_object('form','GSTR-2B','period_id',p.id,'period_start',p.period_start,'gstin',r.gstin);
  return private.gst_provider_enqueue_return_v600(p_tenant_id,p.registration_id,p.id,'gstr2b_fetch',p_request_id,r.provider_key,payload);
end
$function$;

create or replace function public.gst_ims_fetch_queue_v600(p_tenant_id uuid,p_period_id uuid,p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare p public.gst_return_periods_v600%rowtype; r public.gst_registrations_v520%rowtype; payload jsonb;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.reconcile') then raise exception 'GST reconciliation permission required'; end if;
  select * into p from public.gst_return_periods_v600 where id=p_period_id and tenant_id=p_tenant_id;
  if not found then raise exception 'GST return period not found'; end if;
  r:=private.gst_provider_connection_assert_v600(p_tenant_id,p.registration_id,'ims');
  payload:=jsonb_build_object('form','IMS','period_id',p.id,'period_start',p.period_start,'gstin',r.gstin);
  return private.gst_provider_enqueue_return_v600(p_tenant_id,p.registration_id,p.id,'ims_fetch',p_request_id,r.provider_key,payload);
end
$function$;

create or replace function public.gst_einvoice_queue_v600(p_tenant_id uuid,p_snapshot_id uuid,p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare p jsonb; r public.gst_registrations_v520%rowtype; existing uuid; s public.gst_document_snapshots_v520%rowtype; aato jsonb; window_days int;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.einvoice') then raise exception 'GST e-invoice permission required'; end if;
  p:=public.gst_einvoice_preview_v600(p_tenant_id,p_snapshot_id);
  if coalesce((p->>'ready')::boolean,false) is not true then raise exception 'E-Invoice preview is not submission-ready: %',p->'errors'; end if;
  select * into s from public.gst_document_snapshots_v520 where id=p_snapshot_id and tenant_id=p_tenant_id;
  aato:=private.gst_aato_context_v600(p_tenant_id,s.document_date);
  if coalesce((aato->>'profile_available')::boolean,false) is not true then raise exception 'AATO profile is required before IRN submission can validate applicability/reporting window'; end if;
  window_days:=coalesce((aato->>'einvoice_reporting_window_days')::int,30);
  if coalesce((aato->>'einvoice_reporting_window_applies')::boolean,false) and current_date>s.document_date+window_days then raise exception 'IRN reporting window of % days has expired for this AATO profile',window_days; end if;
  r:=private.gst_provider_connection_assert_v600(p_tenant_id,(p->>'registration_id')::uuid,'einvoice');
  select j.id into existing from public.gst_provider_jobs_v600 j where j.tenant_id=p_tenant_id and j.snapshot_id=p_snapshot_id and j.operation='einvoice_generate' and j.status in('queued','processing','succeeded','cancelled') order by j.created_at desc limit 1;
  if existing is not null and not exists(select 1 from public.gst_provider_jobs_v600 j where j.id=existing and j.request_id=p_request_id) then raise exception 'An IRN lifecycle already exists for this GST snapshot'; end if;
  return private.gst_provider_enqueue_v600(p_tenant_id,r.id,p_snapshot_id,null,'einvoice_generate',p_request_id,r.provider_key,jsonb_build_object('aato',aato,'irp_payload',p->'payload'));
end
$function$;

create or replace function public.gst_provider_job_complete_v600(
  p_job_id uuid,
  p_success boolean,
  p_response jsonb default '{}'::jsonb,
  p_error_code text default null,
  p_error_message text default null,
  p_retryable boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare j public.gst_provider_jobs_v600%rowtype; retry_at timestamptz; p public.gst_return_periods_v600%rowtype; imported jsonb;
begin
  perform private.gst_service_role_assert_v600();
  select * into j from public.gst_provider_jobs_v600 where id=p_job_id for update;
  if not found then raise exception 'GST provider job not found'; end if;
  if j.status<>'processing' then raise exception 'GST provider job is not processing'; end if;
  if p_success then
    update public.gst_provider_jobs_v600
    set status='succeeded',response_payload=coalesce(p_response,'{}'::jsonb),provider_reference=nullif(p_response->>'provider_reference',''),
        irn=coalesce(nullif(p_response->>'irn',''),irn),ack_no=coalesce(nullif(p_response->>'ack_no',''),ack_no),ack_at=coalesce(nullif(p_response->>'ack_at','')::timestamptz,ack_at),
        signed_invoice=coalesce(nullif(p_response->>'signed_invoice',''),signed_invoice),signed_qr_code=coalesce(nullif(p_response->>'signed_qr_code',''),signed_qr_code),
        ewaybill_no=coalesce(nullif(p_response->>'ewaybill_no',''),ewaybill_no),ewaybill_date=coalesce(nullif(p_response->>'ewaybill_date','')::timestamptz,ewaybill_date),ewaybill_valid_until=coalesce(nullif(p_response->>'ewaybill_valid_until','')::timestamptz,ewaybill_valid_until),
        error_code=null,error_message=null,next_retry_at=null,completed_at=now()
    where id=j.id returning * into j;
    if j.operation in('einvoice_cancel','ewaybill_cancel') and j.related_job_id is not null then update public.gst_provider_jobs_v600 set status='cancelled' where id=j.related_job_id and status='succeeded'; end if;
    if j.return_period_id is not null then
      select * into p from public.gst_return_periods_v600 where id=j.return_period_id for update;
      if j.operation='gstr1_submit' then
        update public.gst_return_periods_v600 set gstr1_filed_at=coalesce(gstr1_filed_at,now()),status=case when status in('locked','filed') then status else 'review' end,updated_at=now() where id=p.id;
      elsif j.operation='gstr3b_submit' then
        update public.gst_return_periods_v600 set gstr3b_filed_at=coalesce(gstr3b_filed_at,now()),status='filed',lock_reason='GSTR-3B filed through GST provider',locked_at=coalesce(locked_at,now()),updated_at=now() where id=p.id;
      elsif j.operation='gstr2b_fetch' and jsonb_typeof(coalesce(p_response->'documents','[]'::jsonb))='array' then
        imported:=public.gst_portal_itc_import_service_v600(j.tenant_id,j.registration_id,p.period_start,'gstr2b',j.request_id,p_response->'documents');
      elsif j.operation='ims_fetch' and jsonb_typeof(coalesce(p_response->'documents','[]'::jsonb))='array' then
        imported:=public.gst_portal_itc_import_service_v600(j.tenant_id,j.registration_id,p.period_start,'ims',j.request_id,p_response->'documents');
      end if;
    end if;
  else
    retry_at:=case when p_retryable and j.attempt_count<8 then now()+make_interval(mins=>least(60,greatest(1,(power(2,least(j.attempt_count,6)))::int))) else null end;
    update public.gst_provider_jobs_v600 set status='failed',response_payload=coalesce(p_response,'{}'::jsonb),error_code=nullif(trim(coalesce(p_error_code,'')),''),error_message=nullif(trim(coalesce(p_error_message,'')),''),next_retry_at=retry_at,completed_at=now() where id=j.id returning * into j;
  end if;
  return jsonb_strip_nulls(jsonb_build_object('job_id',j.id,'status',j.status,'attempt_count',j.attempt_count,'next_retry_at',j.next_retry_at,'operation',j.operation,'return_period_id',j.return_period_id,'portal_import',imported));
end
$function$;

create or replace function public.gst_provider_status_v600(p_tenant_id uuid,p_snapshot_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $function$
declare jobs jsonb;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then raise exception 'GST compliance view permission required'; end if;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('job_id',j.id,'snapshot_id',j.snapshot_id,'return_period_id',j.return_period_id,'operation',j.operation,'status',j.status,'request_id',j.request_id,'provider_key',j.provider_key,'provider_reference',j.provider_reference,'irn',j.irn,'ack_no',j.ack_no,'ack_at',j.ack_at,'ewaybill_no',j.ewaybill_no,'ewaybill_date',j.ewaybill_date,'ewaybill_valid_until',j.ewaybill_valid_until,'error_code',j.error_code,'error_message',j.error_message,'attempt_count',j.attempt_count,'next_retry_at',j.next_retry_at,'created_at',j.created_at,'updated_at',j.updated_at,'completed_at',j.completed_at)) order by j.created_at desc),'[]'::jsonb)
  into jobs from public.gst_provider_jobs_v600 j where j.tenant_id=p_tenant_id and (p_snapshot_id is null or j.snapshot_id=p_snapshot_id);
  return jsonb_build_object('jobs',jobs);
end
$function$;

revoke all on function public.gst_portal_itc_import_service_v600(uuid,uuid,date,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.gst_portal_itc_import_service_v600(uuid,uuid,date,text,uuid,jsonb) to service_role;
revoke all on function public.gst_gstr1_submit_queue_v600(uuid,uuid,uuid) from public,anon;
grant execute on function public.gst_gstr1_submit_queue_v600(uuid,uuid,uuid) to authenticated;
revoke all on function public.gst_gstr3b_submit_queue_v600(uuid,uuid,uuid) from public,anon;
grant execute on function public.gst_gstr3b_submit_queue_v600(uuid,uuid,uuid) to authenticated;
revoke all on function public.gst_gstr2b_fetch_queue_v600(uuid,uuid,uuid) from public,anon;
grant execute on function public.gst_gstr2b_fetch_queue_v600(uuid,uuid,uuid) to authenticated;
revoke all on function public.gst_ims_fetch_queue_v600(uuid,uuid,uuid) from public,anon;
grant execute on function public.gst_ims_fetch_queue_v600(uuid,uuid,uuid) to authenticated;