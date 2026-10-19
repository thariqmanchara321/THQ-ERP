alter table public.gst_provider_jobs_v600
  add column if not exists processing_started_at timestamptz,
  add column if not exists completed_at timestamptz;

create index if not exists idx_gst_provider_jobs_v600_claim
  on public.gst_provider_jobs_v600(status,next_retry_at,created_at)
  where status in ('queued','failed');

create index if not exists idx_gst_provider_jobs_v600_snapshot
  on public.gst_provider_jobs_v600(tenant_id,snapshot_id,operation,created_at desc);

create or replace function private.gst_service_role_assert_v600()
returns void
language plpgsql
stable
security invoker
set search_path=public,private,pg_temp
as $function$
begin
  if coalesce(current_setting('request.jwt.claim.role',true),'') <> 'service_role' then
    raise exception 'Service role required';
  end if;
end
$function$;

create or replace function public.gst_provider_connection_mark_v600(
  p_tenant_id uuid,
  p_registration_id uuid,
  p_provider_key text,
  p_connection_status text,
  p_mode text,
  p_capabilities jsonb default '{}'::jsonb,
  p_provider_account_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare
  v_status text:=lower(trim(coalesce(p_connection_status,'')));
  v_mode text:=lower(trim(coalesce(p_mode,'')));
  v_provider text:=lower(trim(coalesce(p_provider_key,'')));
  v_config jsonb;
begin
  perform private.gst_service_role_assert_v600();
  if v_provider='' then raise exception 'Provider key required'; end if;
  if v_status not in ('verified','disconnected','error') then raise exception 'Invalid provider connection status'; end if;
  if v_mode not in ('sandbox','production') then raise exception 'Invalid provider mode'; end if;
  if jsonb_typeof(coalesce(p_capabilities,'{}'::jsonb)) <> 'object' then raise exception 'Provider capabilities must be an object'; end if;
  if not exists(select 1 from public.gst_registrations_v520 r where r.id=p_registration_id and r.tenant_id=p_tenant_id) then
    raise exception 'GST registration not found';
  end if;

  v_config:=jsonb_strip_nulls(jsonb_build_object(
    'connection_status',v_status,
    'mode',v_mode,
    'capabilities',coalesce(p_capabilities,'{}'::jsonb),
    'provider_account_reference',nullif(trim(coalesce(p_provider_account_reference,'')),''),
    'verified_at',case when v_status='verified' then now() else null end,
    'secrets_location','edge_function_environment',
    'contains_credentials',false,
    'contract_version',1
  ));

  update public.gst_registrations_v520
  set provider_key=v_provider,
      provider_config=v_config,
      updated_at=now()
  where id=p_registration_id and tenant_id=p_tenant_id;

  update public.gst_registration_versions_v520
  set provider_key=v_provider,
      provider_config=v_config
  where tenant_id=p_tenant_id and registration_id=p_registration_id and effective_to is null;

  return jsonb_build_object('registration_id',p_registration_id,'provider_key',v_provider,'provider',v_config);
end
$function$;

create or replace function public.gst_provider_connection_status_v600(
  p_tenant_id uuid,
  p_registration_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $function$
declare v jsonb;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') then raise exception 'GST compliance view permission required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'registration_id',r.id,'gstin',r.gstin,'legal_name',r.legal_name,
      'einvoice_enabled',r.einvoice_enabled,'ewaybill_enabled',r.ewaybill_enabled,'returns_enabled',r.returns_enabled,
      'provider_key',r.provider_key,'provider',coalesce(r.provider_config,'{}'::jsonb)
    ) order by r.gstin),'[]'::jsonb)
  into v
  from public.gst_registrations_v520 r
  where r.tenant_id=p_tenant_id and r.active and (p_registration_id is null or r.id=p_registration_id);
  return jsonb_build_object('registrations',v);
end
$function$;

create or replace function public.gst_einvoice_preview_v600(
  p_tenant_id uuid,
  p_snapshot_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $function$
declare
  s public.gst_document_snapshots_v520%rowtype;
  seller jsonb;
  buyer jsonb;
  items jsonb;
  errors text[]:='{}';
  warnings text[]:='{}';
  doc_type text;
  payload jsonb;
  reg public.gst_registrations_v520%rowtype;
begin
  if not (private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') or private.gst_v520_has_access(p_tenant_id,'gst_compliance.einvoice')) then
    raise exception 'GST e-invoice permission required';
  end if;
  select * into s from public.gst_document_snapshots_v520 where id=p_snapshot_id and tenant_id=p_tenant_id;
  if not found then raise exception 'GST snapshot not found'; end if;
  if not private.erp_document_scope_allowed(p_tenant_id,s.location_id,s.location_id,'view') then raise exception 'Location access denied'; end if;

  seller:=coalesce(s.legal_context->'seller','{}'::jsonb);
  buyer:=coalesce(s.legal_context->'buyer','{}'::jsonb);
  select * into reg from public.gst_registrations_v520 where id=s.thq_registration_id and tenant_id=p_tenant_id;

  if s.tax_mode<>'gst_registered' then errors:=array_append(errors,'E-Invoice requires a GST-registered authoritative snapshot'); end if;
  if s.direction<>'outward' then errors:=array_append(errors,'E-Invoice is supported only for outward documents'); end if;
  if s.document_class not in('tax_invoice','credit_note','debit_note') then errors:=array_append(errors,'Document class is not eligible for IRN generation'); end if;
  if upper(coalesce(s.supply_type,'')) not in('B2B','SEZWP','SEZWOP','EXPWP','EXPWOP','DEXP') then errors:=array_append(errors,'Supply type is not eligible for e-invoice'); end if;
  if reg.id is null then errors:=array_append(errors,'THQ GST registration is missing');
  elsif not reg.einvoice_enabled then errors:=array_append(errors,'E-Invoice is not enabled for this GST registration'); end if;
  if length(coalesce(s.document_number,'')) not between 1 and 16 then errors:=array_append(errors,'Invoice document number must be 1-16 characters for IRP'); end if;

  if nullif(seller->>'gstin','') is null then errors:=array_append(errors,'Seller GSTIN is missing from immutable legal context'); end if;
  if nullif(seller->>'legal_name','') is null then errors:=array_append(errors,'Seller legal name is missing from immutable legal context'); end if;
  if nullif(seller->>'address_line1','') is null then errors:=array_append(errors,'Seller address is missing from immutable legal context'); end if;
  if nullif(seller->>'city','') is null then errors:=array_append(errors,'Seller location/city is missing from immutable legal context'); end if;
  if nullif(seller->>'postal_code','') is null then errors:=array_append(errors,'Seller PIN is missing from immutable legal context'); end if;
  if nullif(seller->>'state_code','') is null then errors:=array_append(errors,'Seller state code is missing from immutable legal context'); end if;

  if upper(coalesce(s.supply_type,'')) in('B2B','SEZWP','SEZWOP') and nullif(buyer->>'gstin','') is null then errors:=array_append(errors,'Registered buyer GSTIN is missing from immutable legal context'); end if;
  if nullif(buyer->>'legal_name','') is null then errors:=array_append(errors,'Buyer legal name is missing from immutable legal context'); end if;
  if nullif(buyer->>'address_line1','') is null then errors:=array_append(errors,'Buyer address is missing from immutable legal context'); end if;
  if nullif(buyer->>'city','') is null then errors:=array_append(errors,'Buyer location/city is missing from immutable legal context'); end if;
  if nullif(buyer->>'state_code','') is null and upper(coalesce(s.supply_type,'')) not in('EXPWP','EXPWOP') then errors:=array_append(errors,'Buyer state code is missing from immutable legal context'); end if;
  if nullif(s.place_of_supply_code,'') is null then errors:=array_append(errors,'Place of Supply is missing'); end if;

  if exists(select 1 from public.gst_document_line_snapshots_v520 l where l.snapshot_id=s.id and (nullif(trim(coalesce(l.hsn_sac,'')),'') is null or l.quantity<=0)) then
    errors:=array_append(errors,'Every e-invoice line requires HSN/SAC and positive quantity');
  end if;
  if exists(select 1 from public.gst_document_line_snapshots_v520 l where l.snapshot_id=s.id and nullif(trim(coalesce(l.unit_code,'')),'') is null) then
    errors:=array_append(errors,'Every e-invoice line requires an immutable unit/UQC code');
  end if;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'SlNo',l.line_no::text,
      'PrdDesc',coalesce(nullif(l.product_name,''),nullif(l.variant_name,''),nullif(l.sku,''),'Item'),
      'IsServc',case when l.supply_kind='service' then 'Y' else 'N' end,
      'HsnCd',l.hsn_sac,
      'Qty',round(l.quantity,3),
      'FreeQty',0,
      'Unit',l.unit_code,
      'UnitPrice',round(l.unit_price,2),
      'TotAmt',round(l.quantity*l.unit_price,2),
      'Discount',round(l.discount_amount,2),
      'AssAmt',round(l.taxable_value,2),
      'GstRt',round(l.applied_gst_rate,3),
      'IgstAmt',round(l.igst,2),
      'CgstAmt',round(l.cgst,2),
      'SgstAmt',round(l.sgst+l.utgst,2),
      'CesRt',round(l.applied_cess_rate,3),
      'CesAmt',round(greatest(l.cess-(l.quantity*l.applied_cess_per_unit),0),2),
      'CesNonAdvlAmt',round(l.quantity*l.applied_cess_per_unit,2),
      'OthChrg',0,
      'TotItemVal',round(l.line_total,2)
    )) order by l.line_no),'[]'::jsonb)
  into items
  from public.gst_document_line_snapshots_v520 l
  where l.snapshot_id=s.id and l.tenant_id=p_tenant_id;

  doc_type:=case s.document_class when 'tax_invoice' then 'INV' when 'credit_note' then 'CRN' when 'debit_note' then 'DBN' end;
  payload:=jsonb_build_object(
    'Version','1.1',
    'TranDtls',jsonb_build_object('TaxSch','GST','SupTyp',upper(s.supply_type),'RegRev',case when s.rcm_tax_payable_total>0 then 'Y' else 'N' end,'IgstOnIntra',case when s.interstate=false and s.igst_total>0 then 'Y' else 'N' end),
    'DocDtls',jsonb_build_object('Typ',doc_type,'No',s.document_number,'Dt',to_char(s.document_date,'DD/MM/YYYY')),
    'SellerDtls',jsonb_strip_nulls(jsonb_build_object('Gstin',seller->>'gstin','LglNm',seller->>'legal_name','TrdNm',seller->>'trade_name','Addr1',seller->>'address_line1','Addr2',seller->>'address_line2','Loc',seller->>'city','Pin',nullif(seller->>'postal_code','')::integer,'Stcd',seller->>'state_code','Ph',seller->>'phone','Em',seller->>'email')),
    'BuyerDtls',jsonb_strip_nulls(jsonb_build_object('Gstin',coalesce(nullif(buyer->>'gstin',''),'URP'),'LglNm',buyer->>'legal_name','TrdNm',buyer->>'trade_name','Pos',s.place_of_supply_code,'Addr1',buyer->>'address_line1','Addr2',buyer->>'address_line2','Loc',buyer->>'city','Pin',case when nullif(buyer->>'postal_code','') is null then null else (buyer->>'postal_code')::integer end,'Stcd',coalesce(nullif(buyer->>'state_code',''),case when upper(s.supply_type) in('EXPWP','EXPWOP') then '96' end),'Ph',buyer->>'phone','Em',buyer->>'email')),
    'ItemList',items,
    'ValDtls',jsonb_build_object('AssVal',round(s.taxable_total,2),'CgstVal',round(s.cgst_total,2),'SgstVal',round(s.sgst_total+s.utgst_total,2),'IgstVal',round(s.igst_total,2),'CesVal',round(s.cess_total,2),'Discount',round(s.discount_total,2),'OthChrg',round(s.additional_charges,2),'RndOffAmt',round(s.round_off,2),'TotInvVal',round(s.grand_total,2))
  );

  return jsonb_build_object(
    'ready',cardinality(errors)=0,
    'snapshot_id',s.id,'snapshot_hash',s.snapshot_hash,'document_identity_hash',s.document_identity_hash,
    'registration_id',s.thq_registration_id,'provider_key',reg.provider_key,
    'errors',to_jsonb(errors),'warnings',to_jsonb(warnings),'payload',payload
  );
end
$function$;

create or replace function public.gst_ewaybill_preview_v600(
  p_tenant_id uuid,
  p_snapshot_id uuid,
  p_transport jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $function$
declare
  s public.gst_document_snapshots_v520%rowtype;
  seller jsonb;
  buyer jsonb;
  reg public.gst_registrations_v520%rowtype;
  items jsonb;
  errors text[]:='{}';
  warnings text[]:='{}';
  mode text:=lower(trim(coalesce(p_transport->>'mode','road')));
  age_limit int:=180;
  age_rule jsonb;
  goods_count int;
  payload jsonb;
begin
  if not (private.gst_v520_has_access(p_tenant_id,'gst_compliance.view') or private.gst_v520_has_access(p_tenant_id,'gst_compliance.ewaybill')) then
    raise exception 'GST E-Way Bill permission required';
  end if;
  select * into s from public.gst_document_snapshots_v520 where id=p_snapshot_id and tenant_id=p_tenant_id;
  if not found then raise exception 'GST snapshot not found'; end if;
  if not private.erp_document_scope_allowed(p_tenant_id,s.location_id,s.location_id,'view') then raise exception 'Location access denied'; end if;
  seller:=coalesce(s.legal_context->'seller','{}'::jsonb);
  buyer:=coalesce(s.legal_context->'buyer','{}'::jsonb);
  select * into reg from public.gst_registrations_v520 where id=s.thq_registration_id and tenant_id=p_tenant_id;

  select rule_value into age_rule from public.gst_policy_rules_v520 where rule_key='ewaybill_document_age_limit' and effective_from<=current_date and (effective_to is null or effective_to>=current_date) order by effective_from desc limit 1;
  age_limit:=coalesce((age_rule->>'days')::int,180);
  select count(*) into goods_count from public.gst_document_line_snapshots_v520 l where l.snapshot_id=s.id and l.supply_kind='goods';

  if s.tax_mode<>'gst_registered' then errors:=array_append(errors,'E-Way Bill requires a GST-registered authoritative snapshot'); end if;
  if reg.id is null then errors:=array_append(errors,'THQ GST registration is missing');
  elsif not reg.ewaybill_enabled then errors:=array_append(errors,'E-Way Bill is not enabled for this GST registration'); end if;
  if goods_count=0 then errors:=array_append(errors,'Service-only document does not require this E-Way Bill goods-movement path'); end if;
  if current_date-s.document_date>age_limit then errors:=array_append(errors,format('Document is older than the configured %s-day E-Way Bill generation limit',age_limit)); end if;
  if mode not in('road','rail','air','ship') then errors:=array_append(errors,'Transport mode must be road, rail, air or ship'); end if;
  if coalesce((p_transport->>'distance_km')::numeric,0)<0 then errors:=array_append(errors,'Transport distance cannot be negative'); end if;
  if mode='road' and nullif(trim(coalesce(p_transport->>'vehicle_no','')),'') is null and nullif(trim(coalesce(p_transport->>'transporter_id','')),'') is null then errors:=array_append(errors,'Road movement requires vehicle number or transporter ID'); end if;
  if mode in('rail','air','ship') and nullif(trim(coalesce(p_transport->>'document_no','')),'') is null then errors:=array_append(errors,'Rail/Air/Ship movement requires transport document number'); end if;
  if nullif(seller->>'postal_code','') is null or nullif(seller->>'state_code','') is null then errors:=array_append(errors,'Dispatch PIN/state is missing from immutable legal context'); end if;
  if nullif(buyer->>'postal_code','') is null or (nullif(buyer->>'state_code','') is null and upper(s.supply_type) not in('EXPWP','EXPWOP')) then errors:=array_append(errors,'Delivery PIN/state is missing from immutable legal context'); end if;
  if s.grand_total<=50000 then warnings:=array_append(warnings,'Document value is at or below the general 50000 E-Way Bill threshold; statutory exceptions may still apply'); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'line_no',l.line_no,'description',coalesce(nullif(l.product_name,''),nullif(l.variant_name,''),nullif(l.sku,''),'Item'),
      'hsn_sac',l.hsn_sac,'quantity',l.quantity,'unit_code',l.unit_code,'taxable_value',l.taxable_value,
      'cgst',l.cgst,'sgst',l.sgst,'utgst',l.utgst,'igst',l.igst,'cess',l.cess,'gst_rate',l.applied_gst_rate
    ) order by l.line_no),'[]'::jsonb)
  into items from public.gst_document_line_snapshots_v520 l where l.snapshot_id=s.id and l.supply_kind='goods';

  payload:=jsonb_build_object(
    'schema','thq-ewaybill-v1','snapshot_id',s.id,'document_type',s.document_class,'document_number',s.document_number,'document_date',s.document_date,
    'supply_type',s.supply_type,'place_of_supply_code',s.place_of_supply_code,
    'from',seller,'to',buyer,'items',items,
    'values',jsonb_build_object('taxable',s.taxable_total,'cgst',s.cgst_total,'sgst',s.sgst_total,'utgst',s.utgst_total,'igst',s.igst_total,'cess',s.cess_total,'total',s.grand_total),
    'transport',jsonb_strip_nulls(jsonb_build_object(
      'mode',mode,'distance_km',nullif(p_transport->>'distance_km','')::numeric,
      'transporter_id',nullif(trim(coalesce(p_transport->>'transporter_id','')),''),'transporter_name',nullif(trim(coalesce(p_transport->>'transporter_name','')),''),
      'vehicle_no',nullif(trim(coalesce(p_transport->>'vehicle_no','')),''),'vehicle_type',coalesce(nullif(trim(coalesce(p_transport->>'vehicle_type','')),''),'regular'),
      'document_no',nullif(trim(coalesce(p_transport->>'document_no','')),''),'document_date',nullif(p_transport->>'document_date','')::date
    ))
  );

  return jsonb_build_object('ready',cardinality(errors)=0,'snapshot_id',s.id,'registration_id',s.thq_registration_id,'provider_key',reg.provider_key,'errors',to_jsonb(errors),'warnings',to_jsonb(warnings),'payload',payload);
end
$function$;

create or replace function private.gst_provider_connection_assert_v600(
  p_tenant_id uuid,
  p_registration_id uuid,
  p_capability text
)
returns public.gst_registrations_v520
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $function$
declare r public.gst_registrations_v520%rowtype; cap boolean;
begin
  select * into r from public.gst_registrations_v520 where id=p_registration_id and tenant_id=p_tenant_id and active;
  if not found then raise exception 'GST registration not found'; end if;
  if nullif(trim(coalesce(r.provider_key,'')),'') is null then raise exception 'GST provider is not configured'; end if;
  if coalesce(r.provider_config->>'connection_status','')<>'verified' then raise exception 'GST provider connection is not verified'; end if;
  cap:=coalesce((r.provider_config->'capabilities'->>p_capability)::boolean,false);
  if not cap then raise exception 'GST provider capability % is not verified',p_capability; end if;
  return r;
end
$function$;

create or replace function private.gst_provider_enqueue_v600(
  p_tenant_id uuid,
  p_registration_id uuid,
  p_snapshot_id uuid,
  p_related_job_id uuid,
  p_operation text,
  p_request_id uuid,
  p_provider_key text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare v_hash text; existing public.gst_provider_jobs_v600%rowtype; v_id uuid;
begin
  if p_request_id is null then raise exception 'Stable request ID is required'; end if;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('tenant_id',p_tenant_id,'operation',p_operation,'snapshot_id',p_snapshot_id,'related_job_id',p_related_job_id,'payload',coalesce(p_payload,'{}'::jsonb))::text,'UTF8'),'sha256'),'hex');
  select * into existing from public.gst_provider_jobs_v600 where tenant_id=p_tenant_id and operation=p_operation and request_id=p_request_id;
  if found then
    if existing.request_hash<>v_hash then raise exception 'GST provider request ID was already used with a different payload'; end if;
    return jsonb_build_object('job_id',existing.id,'status',existing.status,'idempotent_replay',true,'request_hash',existing.request_hash);
  end if;
  insert into public.gst_provider_jobs_v600(tenant_id,registration_id,snapshot_id,related_job_id,operation,request_id,provider_key,status,request_payload,request_hash,created_by)
  values(p_tenant_id,p_registration_id,p_snapshot_id,p_related_job_id,p_operation,p_request_id,p_provider_key,'queued',coalesce(p_payload,'{}'::jsonb),v_hash,auth.uid()) returning id into v_id;
  return jsonb_build_object('job_id',v_id,'status','queued','idempotent_replay',false,'request_hash',v_hash);
end
$function$;

create or replace function public.gst_einvoice_queue_v600(p_tenant_id uuid,p_snapshot_id uuid,p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare p jsonb; r public.gst_registrations_v520%rowtype; existing uuid;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.einvoice') then raise exception 'GST e-invoice permission required'; end if;
  p:=public.gst_einvoice_preview_v600(p_tenant_id,p_snapshot_id);
  if coalesce((p->>'ready')::boolean,false) is not true then raise exception 'E-Invoice preview is not submission-ready: %',p->'errors'; end if;
  r:=private.gst_provider_connection_assert_v600(p_tenant_id,(p->>'registration_id')::uuid,'einvoice');
  select j.id into existing from public.gst_provider_jobs_v600 j where j.tenant_id=p_tenant_id and j.snapshot_id=p_snapshot_id and j.operation='einvoice_generate' and j.status in('queued','processing','succeeded','cancelled') order by j.created_at desc limit 1;
  if existing is not null and not exists(select 1 from public.gst_provider_jobs_v600 j where j.id=existing and j.request_id=p_request_id) then raise exception 'An IRN lifecycle already exists for this GST snapshot'; end if;
  return private.gst_provider_enqueue_v600(p_tenant_id,r.id,p_snapshot_id,null,'einvoice_generate',p_request_id,r.provider_key,p->'payload');
end
$function$;

create or replace function public.gst_ewaybill_queue_v600(p_tenant_id uuid,p_snapshot_id uuid,p_request_id uuid,p_transport jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare p jsonb; r public.gst_registrations_v520%rowtype;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.ewaybill') then raise exception 'GST E-Way Bill permission required'; end if;
  p:=public.gst_ewaybill_preview_v600(p_tenant_id,p_snapshot_id,p_transport);
  if coalesce((p->>'ready')::boolean,false) is not true then raise exception 'E-Way Bill preview is not submission-ready: %',p->'errors'; end if;
  r:=private.gst_provider_connection_assert_v600(p_tenant_id,(p->>'registration_id')::uuid,'ewaybill');
  if exists(select 1 from public.gst_provider_jobs_v600 j where j.tenant_id=p_tenant_id and j.snapshot_id=p_snapshot_id and j.operation='ewaybill_generate' and j.status in('queued','processing','succeeded')) then
    if not exists(select 1 from public.gst_provider_jobs_v600 j where j.tenant_id=p_tenant_id and j.snapshot_id=p_snapshot_id and j.operation='ewaybill_generate' and j.request_id=p_request_id) then raise exception 'An active E-Way Bill lifecycle already exists for this GST snapshot'; end if;
  end if;
  return private.gst_provider_enqueue_v600(p_tenant_id,r.id,p_snapshot_id,null,'ewaybill_generate',p_request_id,r.provider_key,p->'payload');
end
$function$;

create or replace function public.gst_ewaybill_cancel_queue_v600(p_tenant_id uuid,p_snapshot_id uuid,p_request_id uuid,p_reason_code text,p_remarks text)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare j public.gst_provider_jobs_v600%rowtype; r public.gst_registrations_v520%rowtype; payload jsonb;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.ewaybill') then raise exception 'GST E-Way Bill permission required'; end if;
  select * into j from public.gst_provider_jobs_v600 where tenant_id=p_tenant_id and snapshot_id=p_snapshot_id and operation='ewaybill_generate' and status='succeeded' order by created_at desc limit 1;
  if not found or j.ewaybill_no is null then raise exception 'Successful E-Way Bill not found'; end if;
  if j.ewaybill_date is null or now()>j.ewaybill_date+interval '24 hours' then raise exception 'E-Way Bill cancellation window has expired'; end if;
  if trim(coalesce(p_reason_code,'')) not in('1','2','3','4') then raise exception 'E-Way Bill cancellation reason code must be 1-4'; end if;
  if nullif(trim(coalesce(p_remarks,'')),'') is null then raise exception 'Cancellation remarks are required'; end if;
  r:=private.gst_provider_connection_assert_v600(p_tenant_id,j.registration_id,'ewaybill');
  payload:=jsonb_build_object('ewaybill_no',j.ewaybill_no,'reason_code',trim(p_reason_code),'remarks',trim(p_remarks));
  return private.gst_provider_enqueue_v600(p_tenant_id,r.id,p_snapshot_id,j.id,'ewaybill_cancel',p_request_id,r.provider_key,payload);
end
$function$;

create or replace function public.gst_irn_cancel_queue_v600(p_tenant_id uuid,p_snapshot_id uuid,p_request_id uuid,p_reason_code text,p_remarks text)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare j public.gst_provider_jobs_v600%rowtype; r public.gst_registrations_v520%rowtype; payload jsonb;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.cancel_irn') then raise exception 'GST IRN cancellation permission required'; end if;
  select * into j from public.gst_provider_jobs_v600 where tenant_id=p_tenant_id and snapshot_id=p_snapshot_id and operation='einvoice_generate' and status='succeeded' order by created_at desc limit 1;
  if not found or j.irn is null then raise exception 'Successful IRN not found'; end if;
  if j.ack_at is null or now()>j.ack_at+interval '24 hours' then raise exception 'IRN cancellation window has expired'; end if;
  if exists(select 1 from public.gst_provider_jobs_v600 e where e.tenant_id=p_tenant_id and e.snapshot_id=p_snapshot_id and e.operation='ewaybill_generate' and e.status='succeeded') then raise exception 'Cancel the active E-Way Bill before cancelling the IRN'; end if;
  if trim(coalesce(p_reason_code,'')) not in('1','2','3','4') then raise exception 'IRN cancellation reason code must be 1-4'; end if;
  if nullif(trim(coalesce(p_remarks,'')),'') is null then raise exception 'Cancellation remarks are required'; end if;
  r:=private.gst_provider_connection_assert_v600(p_tenant_id,j.registration_id,'einvoice');
  payload:=jsonb_build_object('irn',j.irn,'reason_code',trim(p_reason_code),'remarks',trim(p_remarks));
  return private.gst_provider_enqueue_v600(p_tenant_id,r.id,p_snapshot_id,j.id,'einvoice_cancel',p_request_id,r.provider_key,payload);
end
$function$;

create or replace function public.gst_provider_job_retry_v600(p_tenant_id uuid,p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare j public.gst_provider_jobs_v600%rowtype;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.submit') then raise exception 'GST submission permission required'; end if;
  select * into j from public.gst_provider_jobs_v600 where id=p_job_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'GST provider job not found'; end if;
  if j.status<>'failed' then raise exception 'Only failed GST provider jobs can be retried'; end if;
  if j.attempt_count>=8 then raise exception 'GST provider retry limit reached'; end if;
  update public.gst_provider_jobs_v600 set status='queued',error_code=null,error_message=null,next_retry_at=null,processing_started_at=null,completed_at=null where id=j.id;
  return jsonb_build_object('job_id',j.id,'status','queued','request_hash',j.request_hash);
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
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'job_id',j.id,'snapshot_id',j.snapshot_id,'operation',j.operation,'status',j.status,'request_id',j.request_id,
      'provider_key',j.provider_key,'provider_reference',j.provider_reference,'irn',j.irn,'ack_no',j.ack_no,'ack_at',j.ack_at,
      'ewaybill_no',j.ewaybill_no,'ewaybill_date',j.ewaybill_date,'ewaybill_valid_until',j.ewaybill_valid_until,
      'error_code',j.error_code,'error_message',j.error_message,'attempt_count',j.attempt_count,'next_retry_at',j.next_retry_at,
      'created_at',j.created_at,'updated_at',j.updated_at,'completed_at',j.completed_at
    )) order by j.created_at desc),'[]'::jsonb)
  into jobs from public.gst_provider_jobs_v600 j
  where j.tenant_id=p_tenant_id and (p_snapshot_id is null or j.snapshot_id=p_snapshot_id);
  return jsonb_build_object('jobs',jobs);
end
$function$;

create or replace function public.gst_provider_job_claim_v600()
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare j public.gst_provider_jobs_v600%rowtype;
begin
  perform private.gst_service_role_assert_v600();
  select * into j from public.gst_provider_jobs_v600
  where ((status='queued') or (status='failed' and next_retry_at is not null and next_retry_at<=now()))
    and attempt_count<8
  order by created_at
  for update skip locked limit 1;
  if not found then return null; end if;
  update public.gst_provider_jobs_v600
  set status='processing',attempt_count=attempt_count+1,processing_started_at=now(),error_code=null,error_message=null
  where id=j.id
  returning * into j;
  return to_jsonb(j);
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
declare j public.gst_provider_jobs_v600%rowtype; retry_at timestamptz;
begin
  perform private.gst_service_role_assert_v600();
  select * into j from public.gst_provider_jobs_v600 where id=p_job_id for update;
  if not found then raise exception 'GST provider job not found'; end if;
  if j.status<>'processing' then raise exception 'GST provider job is not processing'; end if;
  if p_success then
    update public.gst_provider_jobs_v600
    set status='succeeded',response_payload=coalesce(p_response,'{}'::jsonb),
        provider_reference=nullif(p_response->>'provider_reference',''),
        irn=coalesce(nullif(p_response->>'irn',''),irn),ack_no=coalesce(nullif(p_response->>'ack_no',''),ack_no),
        ack_at=coalesce(nullif(p_response->>'ack_at','')::timestamptz,ack_at),signed_invoice=coalesce(nullif(p_response->>'signed_invoice',''),signed_invoice),
        signed_qr_code=coalesce(nullif(p_response->>'signed_qr_code',''),signed_qr_code),
        ewaybill_no=coalesce(nullif(p_response->>'ewaybill_no',''),ewaybill_no),ewaybill_date=coalesce(nullif(p_response->>'ewaybill_date','')::timestamptz,ewaybill_date),
        ewaybill_valid_until=coalesce(nullif(p_response->>'ewaybill_valid_until','')::timestamptz,ewaybill_valid_until),
        error_code=null,error_message=null,next_retry_at=null,completed_at=now()
    where id=j.id returning * into j;
    if j.operation in('einvoice_cancel','ewaybill_cancel') and j.related_job_id is not null then
      update public.gst_provider_jobs_v600 set status='cancelled' where id=j.related_job_id and status='succeeded';
    end if;
  else
    retry_at:=case when p_retryable and j.attempt_count<8 then now()+make_interval(mins=>least(60,greatest(1,(power(2,least(j.attempt_count,6)))::int))) else null end;
    update public.gst_provider_jobs_v600
    set status='failed',response_payload=coalesce(p_response,'{}'::jsonb),error_code=nullif(trim(coalesce(p_error_code,'')),''),
        error_message=nullif(trim(coalesce(p_error_message,'')),''),next_retry_at=retry_at,completed_at=now()
    where id=j.id returning * into j;
  end if;
  return jsonb_build_object('job_id',j.id,'status',j.status,'attempt_count',j.attempt_count,'next_retry_at',j.next_retry_at,'operation',j.operation);
end
$function$;

revoke all on function public.gst_provider_connection_mark_v600(uuid,uuid,text,text,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.gst_provider_connection_mark_v600(uuid,uuid,text,text,text,jsonb,text) to service_role;
revoke all on function public.gst_provider_job_claim_v600() from public,anon,authenticated;
grant execute on function public.gst_provider_job_claim_v600() to service_role;
revoke all on function public.gst_provider_job_complete_v600(uuid,boolean,jsonb,text,text,boolean) from public,anon,authenticated;
grant execute on function public.gst_provider_job_complete_v600(uuid,boolean,jsonb,text,text,boolean) to service_role;

revoke all on function public.gst_provider_connection_status_v600(uuid,uuid) from public,anon;
grant execute on function public.gst_provider_connection_status_v600(uuid,uuid) to authenticated;
revoke all on function public.gst_einvoice_preview_v600(uuid,uuid) from public,anon;
grant execute on function public.gst_einvoice_preview_v600(uuid,uuid) to authenticated;
revoke all on function public.gst_ewaybill_preview_v600(uuid,uuid,jsonb) from public,anon;
grant execute on function public.gst_ewaybill_preview_v600(uuid,uuid,jsonb) to authenticated;
revoke all on function public.gst_einvoice_queue_v600(uuid,uuid,uuid) from public,anon;
grant execute on function public.gst_einvoice_queue_v600(uuid,uuid,uuid) to authenticated;
revoke all on function public.gst_ewaybill_queue_v600(uuid,uuid,uuid,jsonb) from public,anon;
grant execute on function public.gst_ewaybill_queue_v600(uuid,uuid,uuid,jsonb) to authenticated;
revoke all on function public.gst_ewaybill_cancel_queue_v600(uuid,uuid,uuid,text,text) from public,anon;
grant execute on function public.gst_ewaybill_cancel_queue_v600(uuid,uuid,uuid,text,text) to authenticated;
revoke all on function public.gst_irn_cancel_queue_v600(uuid,uuid,uuid,text,text) from public,anon;
grant execute on function public.gst_irn_cancel_queue_v600(uuid,uuid,uuid,text,text) to authenticated;
revoke all on function public.gst_provider_job_retry_v600(uuid,uuid) from public,anon;
grant execute on function public.gst_provider_job_retry_v600(uuid,uuid) to authenticated;
revoke all on function public.gst_provider_status_v600(uuid,uuid) from public,anon;
grant execute on function public.gst_provider_status_v600(uuid,uuid) to authenticated;