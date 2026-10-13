-- THQ ERP Migration v707
-- Fix document_origins story capture, optional supplier invoice in purchases, and batch variant price updates

-- 1. Update private.v600_story_write to safely return null if required fields are missing
CREATE OR REPLACE FUNCTION private.v600_story_write(
  p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_entity_reference text, p_action text,
  p_event_time timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_actor_user_id uuid DEFAULT NULL::uuid, p_location_id uuid DEFAULT NULL::uuid,
  p_device_id uuid DEFAULT NULL::uuid, p_before jsonb DEFAULT NULL::jsonb,
  p_after jsonb DEFAULT NULL::jsonb, p_reason text DEFAULT NULL::text,
  p_approval_request_id uuid DEFAULT NULL::uuid, p_source_module text DEFAULT NULL::text,
  p_source_function text DEFAULT NULL::text, p_source_app text DEFAULT NULL::text,
  p_root_entity_type text DEFAULT NULL::text, p_root_entity_id uuid DEFAULT NULL::uuid,
  p_request_id text DEFAULT NULL::text, p_related_entities jsonb DEFAULT '[]'::jsonb,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  v_id uuid := gen_random_uuid();
  v_actor uuid := coalesce(p_actor_user_id,auth.uid());
  v_actor_name text;
  v_roles text[] := '{}'::text[];
  v_device_name text;
  v_device_code text;
  v_source_app text := p_source_app;
  v_location uuid := p_location_id;
  v_device uuid := p_device_id;
  v_root_type text := coalesce(nullif(trim(p_root_entity_type),''),p_entity_type);
  v_root_id uuid := coalesce(p_root_entity_id,p_entity_id);
  v_corr uuid;
  v_prev_hash text;
  v_hash text;
  v_changed text[];
  v_approved_by uuid;
  v_approved_at timestamptz;
  v_approval_note text;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
  v_event_time timestamptz := coalesce(p_event_time,now());
  v_payload jsonb;
begin
  if p_tenant_id is null or p_entity_id is null or nullif(trim(p_entity_type),'') is null or nullif(trim(p_action),'') is null then
    return null;
  end if;

  if not exists (select 1 from public.tenants t where t.id=p_tenant_id) then
    return null;
  end if;

  if v_actor is not null then
    select u.username::text into v_actor_name
    from public.user_login_names u
    where u.user_id=v_actor;

    select coalesce(array_agg(distinct r.key order by r.key),'{}'::text[])
      into v_roles
    from public.tenant_memberships m
    join public.user_roles ur on ur.membership_id=m.id and ur.tenant_id=m.tenant_id
    join public.roles r on r.id=ur.role_id and r.tenant_id=m.tenant_id
    where m.tenant_id=p_tenant_id and m.user_id=v_actor and m.status='active';
  end if;

  if v_device is not null then
    select d.name,d.device_code,coalesce(v_source_app,d.app_type),coalesce(v_location,d.location_id)
      into v_device_name,v_device_code,v_source_app,v_location
    from public.business_devices d
    where d.tenant_id=p_tenant_id and d.id=v_device;
  end if;

  if p_approval_request_id is not null then
    select a.decided_by,a.decided_at,a.decision_note,coalesce(v_reason,a.reason)
      into v_approved_by,v_approved_at,v_approval_note,v_reason
    from public.approval_requests a
    where a.tenant_id=p_tenant_id and a.id=p_approval_request_id;
  end if;

  v_corr := extensions.uuid_generate_v5(
    extensions.uuid_ns_url(),
    'thq:v600:'||p_tenant_id::text||':'||lower(v_root_type)||':'||v_root_id::text
  );

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_corr::text,0));

  select e.event_hash into v_prev_hash
  from public.transaction_story_events_v600 e
  where e.tenant_id=p_tenant_id and e.correlation_id=v_corr
  order by e.event_sequence desc
  limit 1;

  v_changed := private.v600_changed_fields(p_before,p_after);

  v_payload := jsonb_build_object(
    'id',v_id,'tenant_id',p_tenant_id,'correlation_id',v_corr,
    'root_entity_type',v_root_type,'root_entity_id',v_root_id,
    'entity_type',p_entity_type,'entity_id',p_entity_id,'entity_reference',p_entity_reference,
    'action',p_action,'event_time',v_event_time,'actor_user_id',v_actor,'actor_name',v_actor_name,
    'actor_role_keys',v_roles,'location_id',v_location,'device_id',v_device,
    'device_name',v_device_name,'device_code',v_device_code,'source_app',v_source_app,
    'request_id',p_request_id,'before_data',p_before,'after_data',p_after,'changed_fields',v_changed,
    'reason',v_reason,'approval_request_id',p_approval_request_id,'approved_by',v_approved_by,
    'approved_at',v_approved_at,'approval_note',v_approval_note,'source_module',p_source_module,
    'source_function',p_source_function,'related_entities',coalesce(p_related_entities,'[]'::jsonb),
    'metadata',coalesce(p_metadata,'{}'::jsonb),'previous_event_hash',v_prev_hash
  );

  v_hash := encode(extensions.digest(coalesce(v_prev_hash,'')||v_payload::text,'sha256'),'hex');

  insert into public.transaction_story_events_v600(
    id,tenant_id,correlation_id,root_entity_type,root_entity_id,
    entity_type,entity_id,entity_reference,action,event_time,
    actor_user_id,actor_name,actor_role_keys,location_id,device_id,device_name,device_code,source_app,
    request_id,before_data,after_data,changed_fields,reason,approval_request_id,approved_by,approved_at,approval_note,
    source_module,source_function,related_entities,metadata,previous_event_hash,event_hash
  ) values (
    v_id,p_tenant_id,v_corr,v_root_type,v_root_id,
    p_entity_type,p_entity_id,p_entity_reference,p_action,v_event_time,
    v_actor,v_actor_name,v_roles,v_location,v_device,v_device_name,v_device_code,v_source_app,
    p_request_id,p_before,p_after,v_changed,v_reason,p_approval_request_id,v_approved_by,v_approved_at,v_approval_note,
    p_source_module,p_source_function,coalesce(p_related_entities,'[]'::jsonb),coalesce(p_metadata,'{}'::jsonb),v_prev_hash,v_hash
  );

  return v_id;
end;
$function$;

-- 2. Update private.v600_capture_business_row to properly assign v_entity_id for document_origins
CREATE OR REPLACE FUNCTION private.v600_capture_business_row()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_old jsonb := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end;
  v_new jsonb := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end;
  v_row jsonb := coalesce(v_new, v_old);
  v_tenant uuid;
  v_entity_id uuid;
  v_entity_type text;
  v_action text;
  v_root_type text;
  v_root_id uuid;
  v_reference text;
  v_location uuid;
  v_device uuid;
  v_actor uuid;
  v_approval uuid;
  v_reason text;
  v_event_time timestamptz;
  v_source_module text;
  v_related jsonb := '[]'::jsonb;
  v_parent jsonb;
  v_changed text[];
begin
  if current_setting('flexi.platform_business_delete', true) = 'true' then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;

  v_changed := private.v600_changed_fields(v_old,v_new);
  if tg_op='UPDATE' and coalesce(array_length(v_changed,1),0)=0 then
    return new;
  end if;

  begin v_tenant := nullif(v_row->>'tenant_id','')::uuid; exception when others then v_tenant := null; end;
  begin v_entity_id := coalesce(nullif(v_row->>'id','')::uuid, nullif(v_row->>'entity_id','')::uuid); exception when others then v_entity_id := null; end;
  begin v_location := nullif(v_row->>'location_id','')::uuid; exception when others then v_location := null; end;
  begin v_device := nullif(v_row->>'device_id','')::uuid; exception when others then v_device := null; end;
  begin v_approval := nullif(v_row->>'approval_request_id','')::uuid; exception when others then v_approval := null; end;

  v_action := case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'modified' else 'deleted' end;
  v_actor := coalesce(
    nullif(v_row->>'updated_by','')::uuid,
    nullif(v_row->>'decided_by','')::uuid,
    nullif(v_row->>'created_by','')::uuid,
    nullif(v_row->>'requested_by','')::uuid,
    auth.uid()
  );
  v_reason := nullif(trim(coalesce(v_row->>'reason',v_row->>'void_reason',v_row->>'decision_note',v_row->>'note',v_row->>'notes','')),'');
  v_event_time := coalesce(
    nullif(v_row->>'updated_at','')::timestamptz,
    nullif(v_row->>'decided_at','')::timestamptz,
    nullif(v_row->>'paid_at','')::timestamptz,
    nullif(v_row->>'occurred_at','')::timestamptz,
    nullif(v_row->>'posted_at','')::timestamptz,
    nullif(v_row->>'requested_at','')::timestamptz,
    nullif(v_row->>'created_at','')::timestamptz,
    now()
  );

  if tg_table_name='sales' then
    v_entity_type := 'sale'; v_root_type := 'sale'; v_root_id := v_entity_id;
    v_reference := v_row->>'sale_number'; v_source_module := 'sales';
    if tg_op='INSERT' then v_action := 'sale_created';
    elsif tg_op='DELETE' then v_action := 'sale_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'sale_status_changed';
    else v_action := 'sale_modified'; end if;

  elsif tg_table_name='sale_items' then
    v_entity_type := 'sale_item';
    v_root_type := 'sale'; v_root_id := nullif(v_row->>'sale_id','')::uuid;
    v_reference := coalesce(v_row->>'sku',v_row->>'product_name'); v_source_module := 'sales';
    v_related := jsonb_build_array(jsonb_build_object('type','sale','id',v_root_id));
    if tg_op='INSERT' then v_action := 'sale_item_added';
    elsif tg_op='DELETE' then v_action := 'sale_item_removed'; else v_action := 'sale_item_modified'; end if;

  elsif tg_table_name='sale_payments' then
    v_entity_type := 'sale_payment';
    v_root_type := 'sale'; v_root_id := nullif(v_row->>'sale_id','')::uuid;
    select s.sale_number into v_reference from public.sales s where s.tenant_id=v_tenant and s.id=v_root_id;
    v_source_module := 'payments';
    v_related := jsonb_build_array(jsonb_build_object('type','sale','id',v_root_id));
    if tg_op='INSERT' then v_action := 'payment_recorded';
    elsif tg_op='DELETE' then v_action := 'payment_deleted'; else v_action := 'payment_modified'; end if;

  elsif tg_table_name='sales_returns' then
    v_entity_type := 'sale_return'; v_root_type := 'sale'; v_root_id := nullif(v_row->>'sale_id','')::uuid;
    v_reference := v_row->>'return_number'; v_source_module := 'returns';
    v_related := jsonb_build_array(jsonb_build_object('type','sale','id',v_root_id));
    if tg_op='INSERT' then v_action := 'return_created';
    elsif tg_op='DELETE' then v_action := 'return_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'return_status_changed';
    else v_action := 'return_modified'; end if;

  elsif tg_table_name='sales_return_items' then
    select to_jsonb(r) into v_parent
    from public.sales_returns r where r.id=nullif(v_row->>'return_id','')::uuid;
    v_tenant := nullif(v_parent->>'tenant_id','')::uuid;
    v_entity_type := 'sale_return_item';
    v_root_type := 'sale'; v_root_id := nullif(v_parent->>'sale_id','')::uuid;
    v_reference := v_parent->>'return_number'; v_source_module := 'returns';
    v_related := jsonb_build_array(
      jsonb_build_object('type','sale_return','id',nullif(v_row->>'return_id','')::uuid),
      jsonb_build_object('type','sale','id',v_root_id)
    );
    if tg_op='INSERT' then v_action := 'return_item_added';
    elsif tg_op='DELETE' then v_action := 'return_item_removed'; else v_action := 'return_item_modified'; end if;

  elsif tg_table_name='customer_invoices_v484' then
    v_entity_type := 'customer_invoice'; v_root_type := 'customer_invoice'; v_root_id := v_entity_id;
    v_reference := coalesce(v_row->>'invoice_number',v_row->>'proforma_number'); v_source_module := 'invoices';
    if tg_op='INSERT' then v_action := 'invoice_created';
    elsif tg_op='DELETE' then v_action := 'invoice_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'invoice_status_changed';
    else v_action := 'invoice_modified'; end if;

  elsif tg_table_name='customer_invoice_items_v484' then
    select to_jsonb(ci) into v_parent
    from public.customer_invoices_v484 ci where ci.id=nullif(v_row->>'customer_invoice_id','')::uuid;
    v_tenant := nullif(v_parent->>'tenant_id','')::uuid;
    v_entity_type := 'customer_invoice_item';
    v_root_type := 'customer_invoice'; v_root_id := nullif(v_row->>'customer_invoice_id','')::uuid;
    v_reference := coalesce(v_row->>'sku',v_row->>'product_name'); v_source_module := 'invoices';
    v_related := jsonb_build_array(jsonb_build_object('type','customer_invoice','id',v_root_id));
    if tg_op='INSERT' then v_action := 'invoice_item_added';
    elsif tg_op='DELETE' then v_action := 'invoice_item_removed'; else v_action := 'invoice_item_modified'; end if;

  elsif tg_table_name='customer_payments_v484' then
    v_entity_type := 'customer_payment'; v_root_type := 'customer_payment'; v_root_id := v_entity_id;
    v_reference := v_row->>'payment_number'; v_source_module := 'payments';
    if tg_op='INSERT' then v_action := 'payment_created';
    elsif tg_op='DELETE' then v_action := 'payment_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'payment_status_changed';
    else v_action := 'payment_modified'; end if;

  elsif tg_table_name='purchases' then
    v_entity_type := 'purchase'; v_root_type := 'purchase'; v_root_id := v_entity_id;
    v_reference := v_row->>'purchase_number'; v_source_module := 'purchases';
    if tg_op='INSERT' then v_action := 'purchase_created';
    elsif tg_op='DELETE' then v_action := 'purchase_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'purchase_status_changed';
    else v_action := 'purchase_modified'; end if;

  elsif tg_table_name='purchase_items' then
    v_entity_type := 'purchase_item';
    v_root_type := 'purchase'; v_root_id := nullif(v_row->>'purchase_id','')::uuid;
    v_reference := coalesce(v_row->>'sku',v_row->>'product_name'); v_source_module := 'purchases';
    v_related := jsonb_build_array(jsonb_build_object('type','purchase','id',v_root_id));
    if tg_op='INSERT' then v_action := 'purchase_item_added';
    elsif tg_op='DELETE' then v_action := 'purchase_item_removed'; else v_action := 'purchase_item_modified'; end if;

  elsif tg_table_name='purchase_payments' then
    v_entity_type := 'purchase_payment';
    v_root_type := 'purchase'; v_root_id := nullif(v_row->>'purchase_id','')::uuid;
    select p.purchase_number into v_reference from public.purchases p where p.tenant_id=v_tenant and p.id=v_root_id;
    v_source_module := 'payments';
    v_related := jsonb_build_array(jsonb_build_object('type','purchase','id',v_root_id));
    if tg_op='INSERT' then v_action := 'payment_recorded';
    elsif tg_op='DELETE' then v_action := 'payment_deleted'; else v_action := 'payment_modified'; end if;

  elsif tg_table_name='purchase_invoices_v484' then
    v_entity_type := 'purchase_invoice'; v_root_type := 'purchase_invoice'; v_root_id := v_entity_id;
    v_reference := coalesce(v_row->>'invoice_number',v_row->>'supplier_invoice_number'); v_source_module := 'invoices';
    if tg_op='INSERT' then v_action := 'invoice_created';
    elsif tg_op='DELETE' then v_action := 'invoice_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'invoice_status_changed';
    else v_action := 'invoice_modified'; end if;

  elsif tg_table_name='purchase_invoice_items_v484' then
    select to_jsonb(pi) into v_parent
    from public.purchase_invoices_v484 pi where pi.id=nullif(v_row->>'purchase_invoice_id','')::uuid;
    v_tenant := nullif(v_parent->>'tenant_id','')::uuid;
    v_entity_type := 'purchase_invoice_item';
    v_root_type := 'purchase_invoice'; v_root_id := nullif(v_row->>'purchase_invoice_id','')::uuid;
    v_reference := coalesce(v_row->>'sku',v_row->>'product_name'); v_source_module := 'invoices';
    v_related := jsonb_build_array(jsonb_build_object('type','purchase_invoice','id',v_root_id));
    if tg_op='INSERT' then v_action := 'invoice_item_added';
    elsif tg_op='DELETE' then v_action := 'invoice_item_removed'; else v_action := 'invoice_item_modified'; end if;

  elsif tg_table_name='supplier_payments_v484' then
    v_entity_type := 'supplier_payment'; v_root_type := 'supplier_payment'; v_root_id := v_entity_id;
    v_reference := v_row->>'payment_number'; v_source_module := 'payments';
    if tg_op='INSERT' then v_action := 'payment_created';
    elsif tg_op='DELETE' then v_action := 'payment_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'payment_status_changed';
    else v_action := 'payment_modified'; end if;

  elsif tg_table_name='document_origins' then
    v_entity_id := coalesce(nullif(v_row->>'id','')::uuid, nullif(v_row->>'entity_id','')::uuid);
    v_entity_type := 'document_origin';
    v_root_type := coalesce(nullif(v_row->>'entity_type',''), 'document_origin');
    v_root_id := v_entity_id;
    v_reference := v_row->>'entity_reference';
    v_source_module := 'origins';
    v_related := jsonb_build_array(jsonb_build_object('type',v_root_type,'id',v_root_id));
    if tg_op='INSERT' then v_action := 'origin_attached';
    elsif tg_op='DELETE' then v_action := 'origin_detached'; else v_action := 'origin_modified'; end if;

  elsif tg_table_name='approval_requests' then
    v_entity_type := 'approval_request';
    v_root_type := v_row->>'entity_type'; v_root_id := nullif(v_row->>'entity_id','')::uuid;
    v_reference := coalesce(v_row->>'request_number',v_row->>'action'); v_source_module := 'approvals';
    v_related := jsonb_build_array(jsonb_build_object('type',v_root_type,'id',v_root_id));
    if tg_op='INSERT' then v_action := 'approval_requested';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then
      v_action := case v_new->>'status' when 'approved' then 'approval_granted' when 'rejected' then 'approval_rejected' else 'approval_status_changed' end;
    else v_action := 'approval_modified'; end if;

  elsif tg_table_name='journal_entries' then
    v_entity_type := 'journal_entry';
    v_root_type := coalesce(nullif(v_row->>'source_type',''),'journal');
    v_root_id := coalesce(nullif(v_row->>'source_id','')::uuid,v_entity_id);
    v_reference := v_row->>'entry_number'; v_source_module := 'accounting';
    if v_root_type<>'journal' then
      v_related := jsonb_build_array(jsonb_build_object('type',v_root_type,'id',v_root_id));
    end if;
    if tg_op='INSERT' then v_action := 'journal_created';
    elsif tg_op='DELETE' then v_action := 'journal_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'journal_status_changed';
    else v_action := 'journal_modified'; end if;

  elsif tg_table_name='journal_lines' then
    select to_jsonb(j) into v_parent
    from public.journal_entries j where j.id=nullif(v_row->>'journal_entry_id','')::uuid;
    v_tenant := nullif(v_parent->>'tenant_id','')::uuid;
    v_entity_type := 'journal_line';
    v_root_type := coalesce(nullif(v_parent->>'source_type',''),'journal');
    v_root_id := coalesce(nullif(v_parent->>'source_id','')::uuid,nullif(v_row->>'journal_entry_id','')::uuid);
    v_reference := v_parent->>'entry_number'; v_source_module := 'accounting';
    v_related := jsonb_build_array(
      jsonb_build_object('type','journal_entry','id',nullif(v_row->>'journal_entry_id','')::uuid),
      jsonb_build_object('type',v_root_type,'id',v_root_id)
    );
    if tg_op='INSERT' then v_action := 'journal_line_added';
    elsif tg_op='DELETE' then v_action := 'journal_line_removed'; else v_action := 'journal_line_modified'; end if;

  elsif tg_table_name='location_stock_movements' then
    v_entity_type := 'stock_movement';
    v_root_type := coalesce(nullif(v_row->>'source_type',''),'stock_movement');
    v_root_id := coalesce(nullif(v_row->>'source_id','')::uuid,v_entity_id);
    v_reference := coalesce(v_row->>'reference_number',v_row->>'source_type'); v_source_module := 'inventory';
    if v_root_type<>'stock_movement' then
      v_related := jsonb_build_array(jsonb_build_object('type',v_root_type,'id',v_root_id));
    end if;
    if tg_op='INSERT' then v_action := 'movement_recorded';
    elsif tg_op='DELETE' then v_action := 'movement_deleted'; else v_action := 'movement_modified'; end if;

  elsif tg_table_name='stock_adjustment_requests_v500' then
    v_entity_type := 'stock_adjustment'; v_root_type := 'stock_adjustment'; v_root_id := v_entity_id;
    v_reference := v_row->>'request_number'; v_source_module := 'inventory';
    if tg_op='INSERT' then v_action := 'adjustment_requested';
    elsif tg_op='DELETE' then v_action := 'adjustment_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'adjustment_status_changed';
    else v_action := 'adjustment_modified'; end if;

  else
    return coalesce(new,old);
  end if;

  if v_tenant is null or v_entity_id is null or v_entity_type is null or v_action is null then
    return coalesce(new, old);
  end if;

  perform private.v600_story_write(
    p_tenant_id => v_tenant,
    p_entity_type => v_entity_type,
    p_entity_id => v_entity_id,
    p_entity_reference => v_reference,
    p_action => v_action,
    p_event_time => v_event_time,
    p_actor_user_id => v_actor,
    p_location_id => v_location,
    p_device_id => v_device,
    p_approval_request_id => v_approval,
    p_before => v_old,
    p_after => v_new,
    p_reason => v_reason,
    p_source_module => v_source_module,
    p_source_function => 'v600_capture_business_row',
    p_root_entity_type => v_root_type,
    p_root_entity_id => v_root_id,
    p_related_entities => v_related,
    p_metadata => jsonb_build_object('table',tg_table_name,'op',tg_op)
  );

  return coalesce(new,old);
end;
$function$;

-- 3. Make supplier invoice optional in gst_purchase_create_v520
CREATE OR REPLACE FUNCTION public.gst_purchase_create_v520(
  p_tenant_id uuid, p_supplier_id uuid, p_supplier_invoice_number text,
  p_purchase_date date, p_due_date date, p_items jsonb,
  p_additional_charges numeric DEFAULT 0, p_round_off numeric DEFAULT 0,
  p_initial_payment numeric DEFAULT 0, p_payment_method text DEFAULT 'cash'::text,
  p_payment_reference text DEFAULT NULL::text, p_notes text DEFAULT NULL::text,
  p_location_id uuid DEFAULT NULL::uuid, p_device_id uuid DEFAULT NULL::uuid,
  p_request_id text DEFAULT NULL::text, p_supply_type text DEFAULT NULL::text,
  p_place_of_supply_code text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_req_payload jsonb;
  v_req_state jsonb;
  v_old_req jsonb;
  v_supply text;
  v_normalized jsonb;
  v_quote jsonb;
  v_bridge jsonb;
  v_basis jsonb;
  v_recon jsonb;
  v_source jsonb;
  v_purchase_id uuid;
  v_purchase_number text;
  v_snapshot uuid;
  v_journal uuid;
  v_document_number text;
  v_response jsonb;
  v_totals jsonb;
  v_supplier_invoice text := nullif(trim(coalesce(p_supplier_invoice_number,'')),'');
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not(private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'purchases.manage')) then raise exception 'Purchases permission required';end if;
  if not(private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate') or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')) then raise exception 'GST calculation permission required';end if;
  if p_location_id is null then raise exception 'Business location is required';end if;

  -- Supplier invoice number is not mandatory: auto-generate fallback if omitted
  if v_supplier_invoice is null then
    v_supplier_invoice := coalesce(
      nullif(trim(p_request_id),''),
      'PUR-' || to_char(coalesce(p_purchase_date, current_date), 'YYYYMMDD') || '-' || substr(gen_random_uuid()::text, 1, 6)
    );
  end if;

  if coalesce(p_additional_charges,0)<>0 then raise exception 'Additional charges are not enabled for authoritative GST Purchases until charge-level GST classification is configured';end if;
  if p_purchase_date is null then raise exception 'Purchase date is required';end if;
  if p_due_date is not null and p_due_date<p_purchase_date then raise exception 'Due date cannot be before purchase date';end if;
  if coalesce(p_initial_payment,0)<0 then raise exception 'Initial payment cannot be negative';end if;

  v_req_payload:=jsonb_build_object(
    'supplier_id',p_supplier_id,'supplier_invoice_number',v_supplier_invoice,
    'purchase_date',p_purchase_date,'due_date',p_due_date,'items',coalesce(p_items,'[]'::jsonb),
    'additional_charges',coalesce(p_additional_charges,0),'round_off',coalesce(p_round_off,0),
    'initial_payment',coalesce(p_initial_payment,0),'payment_method',lower(trim(coalesce(p_payment_method,''))),
    'payment_reference',nullif(trim(coalesce(p_payment_reference,'')),''),'notes',nullif(trim(coalesce(p_notes,'')),''),
    'location_id',p_location_id,'device_id',p_device_id,'supply_type',nullif(upper(trim(coalesce(p_supply_type,''))),''),
    'place_of_supply_code',nullif(trim(coalesce(p_place_of_supply_code,'')),'')
  );

  v_req_state:=private.gst_request_begin_v520(p_tenant_id,p_request_id,'gst.purchase.create.v520',v_req_payload);
  if coalesce((v_req_state->>'existing')::boolean,false) then return v_req_state->'response';end if;

  v_old_req:=private.v47_request_existing(p_tenant_id,p_request_id,'purchase.create');
  if v_old_req is not null then raise exception 'Request ID is already used by the legacy Purchase path';end if;

  v_normalized:=private.v481_normalize_items(p_tenant_id,p_items,'purchase');
  v_basis:=private.gst_purchase_inventory_basis_capture_v520(p_tenant_id,v_normalized);
  v_supply:=private.gst_purchase_supply_type_resolve_v520(p_tenant_id,p_supplier_id,p_purchase_date,p_supply_type);

  v_quote:=public.gst_purchase_quote_v520(p_tenant_id,p_location_id,p_supplier_id,p_purchase_date,v_supply,p_place_of_supply_code,v_normalized,0,p_round_off);
  if coalesce((v_quote->>'ready_for_compliance')::boolean,false) is not true then
    raise exception 'GST Purchase is not compliance-ready: %',coalesce(v_quote->'errors','[]'::jsonb)::text;
  end if;

  v_totals:=v_quote->'totals';
  if coalesce(p_initial_payment,0)>coalesce((v_totals->>'grand_total')::numeric,0)+0.005 then
    raise exception 'Payment cannot exceed GST Purchase total';
  end if;

  v_bridge:=private.gst_purchase_bridge_v520(p_items,v_normalized,(v_totals->>'grand_total')::numeric);

  perform private.gst_authoritative_context_enter_v520(p_tenant_id,'purchase');

  v_source:=public.purchases_create_v483(
    p_tenant_id,p_supplier_id,v_supplier_invoice,p_purchase_date,p_due_date,
    v_bridge->'items',(v_bridge->>'additional_charges')::numeric,p_initial_payment,
    p_payment_method,p_notes,p_location_id,p_device_id,p_request_id
  );

  v_purchase_id:=nullif(v_source->>'purchase_id','')::uuid;
  if v_purchase_id is null then raise exception 'GST Purchase source could not be resolved';end if;
  perform private.gst_authoritative_context_bind_v520(v_purchase_id);

  select p.purchase_number into v_purchase_number
  from public.purchases p
  where p.tenant_id=p_tenant_id and p.id=v_purchase_id and p.status='posted' and lower(trim(coalesce(p.supplier_invoice_number,'')))=lower(v_supplier_invoice)
  for update;

  if v_purchase_number is null then
    raise exception 'GST Purchase source is not posted or supplier invoice identity changed';
  end if;

  if exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='purchase' and j.source_id=v_purchase_id and j.status='posted') then
    raise exception 'Legacy Purchase journal was created inside authoritative GST context';
  end if;
  if exists(select 1 from public.gst_legacy_document_markers_v520 m where m.tenant_id=p_tenant_id and m.source_type='purchase' and m.source_id=v_purchase_id) then
    raise exception 'Legacy GST evidence was created inside authoritative GST context';
  end if;
  if exists(select 1 from public.journal_entries j join public.purchase_payments pp on pp.id=j.source_id and pp.purchase_id=v_purchase_id where j.tenant_id=p_tenant_id and j.source_type='purchase_payment' and j.status='posted') then
    raise exception 'Standalone initial Purchase payment journal was created inside authoritative GST context';
  end if;

  v_recon:=private.gst_purchase_reconcile_source_v520(p_tenant_id,v_purchase_id,p_location_id,v_quote,v_basis,p_payment_reference);
  v_snapshot:=private.gst_snapshot_create_v520(p_tenant_id,'purchase',v_purchase_id,v_purchase_number,p_location_id,p_purchase_date,v_quote,v_recon->'line_ids');
  v_journal:=private.gst_authoritative_journal_post_v520(p_tenant_id,v_snapshot);

  select s.document_number into v_document_number
  from public.gst_document_snapshots_v520 s
  where s.id=v_snapshot and s.tenant_id=p_tenant_id;

  if v_document_number is null or lower(trim(v_document_number))<>lower(v_supplier_invoice) then
    raise exception 'GST Purchase legal supplier invoice number was not captured';
  end if;

  v_response:=coalesce(v_source,'{}'::jsonb)||jsonb_build_object(
    'success',true,'gst_engine',v_quote->>'engine','gst_status','POSTED','gst_supply_type',v_supply,
    'place_of_supply_code',v_quote->>'place_of_supply_code','purchase_id',v_purchase_id,
    'purchase_number',v_purchase_number,'supplier_invoice_number',v_document_number,
    'grand_total',(v_totals->>'grand_total')::numeric,'taxable_total',(v_totals->>'taxable_value')::numeric,
    'tax_total',(v_totals->>'tax_collected_total')::numeric,'cgst',(v_totals->>'cgst')::numeric,
    'sgst',(v_totals->>'sgst')::numeric,'utgst',(v_totals->>'utgst')::numeric,'igst',(v_totals->>'igst')::numeric,
    'cess',(v_totals->>'cess')::numeric,'thq_rcm_tax_payable_total',coalesce((v_totals->>'thq_rcm_tax_payable_total')::numeric,0),
    'gst_snapshot_id',v_snapshot,'journal_id',v_journal,'inventory_costs',v_recon->'inventory_costs','gst_ready_for_compliance',true
  );

  v_response:=private.gst_request_complete_v520(p_tenant_id,p_request_id,'gst.purchase.create.v520','purchase',v_purchase_id,v_snapshot,v_journal,v_response);
  update public.transaction_requests_v47 set response=v_response where tenant_id=p_tenant_id and request_id=trim(p_request_id) and operation='purchase.create';
  perform private.gst_authoritative_context_exit_v520();
  return v_response;
end;
$function$;

-- 4. Pricing update RPC for purchase lines
CREATE OR REPLACE FUNCTION public.purchase_update_variant_pricing_v707(
  p_tenant_id uuid,
  p_updates jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_item jsonb;
  v_variant_id uuid;
  v_cost numeric;
  v_selling numeric;
  v_count int := 0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_updates, '[]'::jsonb))
  loop
    v_variant_id := nullif(v_item->>'variant_id', '')::uuid;
    v_cost := nullif(v_item->>'cost_price', '')::numeric;
    v_selling := nullif(v_item->>'selling_price', '')::numeric;

    if v_variant_id is not null then
      update public.product_variants
      set cost_price = coalesce(v_cost, cost_price),
          selling_price = coalesce(v_selling, selling_price),
          updated_at = now()
      where id = v_variant_id and tenant_id = p_tenant_id;

      update public.products
      set cost_price = coalesce(v_cost, cost_price),
          selling_price = coalesce(v_selling, selling_price),
          updated_at = now()
      where id = (select product_id from public.product_variants where id = v_variant_id and tenant_id = p_tenant_id)
        and tenant_id = p_tenant_id;

      v_count := v_count + 1;
    end if;
  end loop;

  return jsonb_build_object('success', true, 'updated_count', v_count);
end;
$function$;

REVOKE ALL ON FUNCTION public.purchase_update_variant_pricing_v707(uuid, jsonb) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.purchase_update_variant_pricing_v707(uuid, jsonb) TO authenticated, service_role;
