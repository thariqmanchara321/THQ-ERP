create or replace function private.v600_capture_business_row()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_new jsonb := case when tg_op='DELETE' then null else to_jsonb(new) end;
  v_old jsonb := case when tg_op='INSERT' then null else to_jsonb(old) end;
  v_row jsonb := coalesce(v_new,v_old,'{}'::jsonb);
  v_tenant uuid;
  v_entity_type text;
  v_entity_id uuid;
  v_reference text;
  v_root_type text;
  v_root_id uuid;
  v_action text;
  v_actor uuid;
  v_location uuid;
  v_device uuid;
  v_reason text;
  v_approval uuid;
  v_event_time timestamptz;
  v_source_module text;
  v_related jsonb := '[]'::jsonb;
  v_parent jsonb;
  v_changed text[];
begin
  v_changed := private.v600_changed_fields(v_old,v_new);
  if tg_op='UPDATE' and coalesce(array_length(v_changed,1),0)=0 then
    return new;
  end if;

  begin v_tenant := nullif(v_row->>'tenant_id','')::uuid; exception when others then v_tenant := null; end;
  begin v_entity_id := nullif(v_row->>'id','')::uuid; exception when others then v_entity_id := null; end;
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
    v_entity_type := 'sales_return';
    v_root_type := 'sale'; v_root_id := nullif(v_row->>'sale_id','')::uuid;
    v_reference := v_row->>'return_number'; v_source_module := 'returns';
    v_related := jsonb_build_array(jsonb_build_object('type','sale','id',v_root_id),jsonb_build_object('type','sales_return','id',v_entity_id));
    if tg_op='INSERT' then v_action := 'sales_return_created';
    elsif tg_op='DELETE' then v_action := 'sales_return_deleted'; else v_action := 'sales_return_modified'; end if;

  elsif tg_table_name='sales_return_items' then
    select to_jsonb(sr) into v_parent
    from public.sales_returns sr where sr.id=nullif(v_row->>'sales_return_id','')::uuid;
    v_tenant := nullif(v_parent->>'tenant_id','')::uuid;
    v_entity_type := 'sales_return_item';
    v_root_type := 'sale'; v_root_id := nullif(v_parent->>'sale_id','')::uuid;
    v_reference := v_parent->>'return_number'; v_source_module := 'returns';
    v_related := jsonb_build_array(jsonb_build_object('type','sale','id',v_root_id),jsonb_build_object('type','sales_return','id',nullif(v_row->>'sales_return_id','')::uuid));
    if tg_op='INSERT' then v_action := 'sales_return_item_added';
    elsif tg_op='DELETE' then v_action := 'sales_return_item_removed'; else v_action := 'sales_return_item_modified'; end if;

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

  elsif tg_table_name='purchase_invoices_v484' then
    v_entity_type := 'purchase_invoice'; v_root_type := 'purchase_invoice'; v_root_id := v_entity_id;
    v_reference := coalesce(v_row->>'supplier_invoice_number',v_row->>'invoice_number'); v_source_module := 'purchase_details';
    if tg_op='INSERT' then v_action := 'purchase_invoice_created';
    elsif tg_op='DELETE' then v_action := 'purchase_invoice_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'purchase_invoice_status_changed';
    else v_action := 'purchase_invoice_modified'; end if;

  elsif tg_table_name='purchase_invoice_items_v484' then
    select to_jsonb(pi) into v_parent from public.purchase_invoices_v484 pi where pi.id=nullif(v_row->>'purchase_invoice_id','')::uuid;
    v_tenant := nullif(v_parent->>'tenant_id','')::uuid;
    v_location := nullif(v_parent->>'location_id','')::uuid;
    v_entity_type := 'purchase_invoice_item'; v_root_type := 'purchase_invoice'; v_root_id := nullif(v_row->>'purchase_invoice_id','')::uuid;
    v_reference := coalesce(v_parent->>'supplier_invoice_number',v_parent->>'invoice_number'); v_source_module := 'purchase_details';
    v_related := jsonb_build_array(jsonb_build_object('type','purchase_invoice','id',v_root_id));
    if tg_op='INSERT' then v_action := 'purchase_invoice_item_added';
    elsif tg_op='DELETE' then v_action := 'purchase_invoice_item_removed'; else v_action := 'purchase_invoice_item_modified'; end if;

  elsif tg_table_name='purchase_payments' then
    v_entity_type := 'purchase_payment';
    v_root_type := 'purchase'; v_root_id := nullif(v_row->>'purchase_id','')::uuid;
    select p.purchase_number into v_reference from public.purchases p where p.tenant_id=v_tenant and p.id=v_root_id;
    v_source_module := 'payments';
    v_related := jsonb_build_array(jsonb_build_object('type','purchase','id',v_root_id));
    if tg_op='INSERT' then v_action := 'supplier_payment_recorded';
    elsif tg_op='DELETE' then v_action := 'supplier_payment_deleted'; else v_action := 'supplier_payment_modified'; end if;

  elsif tg_table_name='supplier_payments_v484' then
    v_entity_type := 'supplier_payment'; v_root_type := 'supplier_payment'; v_root_id := v_entity_id;
    v_reference := v_row->>'payment_number'; v_source_module := 'payments';
    if tg_op='INSERT' then v_action := 'supplier_payment_recorded';
    elsif tg_op='DELETE' then v_action := 'supplier_payment_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'supplier_payment_status_changed';
    else v_action := 'supplier_payment_modified'; end if;

  elsif tg_table_name='location_stock_movements' then
    v_entity_type := 'stock_movement'; v_source_module := 'inventory';
    v_reference := v_row->>'reference_number';
    if nullif(v_row->>'reference_id','') is not null then
      v_root_id := nullif(v_row->>'reference_id','')::uuid;
      v_root_type := coalesce(nullif(v_row->>'reference_type',''),'stock_movement');
    else
      v_root_id := v_entity_id; v_root_type := 'stock_movement';
    end if;
    v_related := case when v_root_id<>v_entity_id then jsonb_build_array(jsonb_build_object('type',v_root_type,'id',v_root_id)) else '[]'::jsonb end;
    if tg_op='INSERT' then v_action := 'stock_movement_recorded';
    elsif tg_op='DELETE' then v_action := 'stock_movement_deleted'; else v_action := 'stock_movement_modified'; end if;

  elsif tg_table_name='stock_adjustment_requests_v500' then
    v_entity_type := 'stock_adjustment'; v_root_type := 'stock_adjustment'; v_root_id := v_entity_id;
    v_reference := v_row->>'request_key'; v_source_module := 'inventory';
    if tg_op='INSERT' then v_action := 'stock_adjustment_requested';
    elsif tg_op='DELETE' then v_action := 'stock_adjustment_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'stock_adjustment_status_changed';
    else v_action := 'stock_adjustment_modified'; end if;

  elsif tg_table_name='journal_entries' then
    v_entity_type := 'journal_entry'; v_reference := v_row->>'entry_number'; v_source_module := 'accounting';
    if nullif(v_row->>'source_id','') is not null then
      v_root_id := nullif(v_row->>'source_id','')::uuid; v_root_type := coalesce(nullif(v_row->>'source_type',''),'journal_entry');
      v_related := jsonb_build_array(jsonb_build_object('type',v_root_type,'id',v_root_id));
    else
      v_root_id := v_entity_id; v_root_type := 'journal_entry';
    end if;
    if tg_op='INSERT' then v_action := 'journal_created';
    elsif tg_op='DELETE' then v_action := 'journal_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'journal_status_changed';
    else v_action := 'journal_modified'; end if;

  elsif tg_table_name='journal_lines' then
    select to_jsonb(j) into v_parent from public.journal_entries j where j.id=nullif(v_row->>'journal_entry_id','')::uuid;
    v_tenant := nullif(v_parent->>'tenant_id','')::uuid;
    v_location := nullif(v_parent->>'location_id','')::uuid;
    v_entity_type := 'journal_line';
    if nullif(v_parent->>'source_id','') is not null then
      v_root_id := nullif(v_parent->>'source_id','')::uuid; v_root_type := coalesce(nullif(v_parent->>'source_type',''),'journal_entry');
    else
      v_root_id := nullif(v_row->>'journal_entry_id','')::uuid; v_root_type := 'journal_entry';
    end if;
    v_reference := v_parent->>'entry_number'; v_source_module := 'accounting';
    v_related := jsonb_build_array(jsonb_build_object('type','journal_entry','id',nullif(v_row->>'journal_entry_id','')::uuid));
    if tg_op='INSERT' then v_action := 'journal_line_added';
    elsif tg_op='DELETE' then v_action := 'journal_line_removed'; else v_action := 'journal_line_modified'; end if;

  elsif tg_table_name='approval_requests' then
    v_entity_type := 'approval_request'; v_source_module := 'approvals';
    v_approval := v_entity_id;
    if nullif(v_row->>'entity_id','') is not null then
      v_root_id := nullif(v_row->>'entity_id','')::uuid; v_root_type := coalesce(nullif(v_row->>'entity_type',''),'approval_request');
      v_related := jsonb_build_array(jsonb_build_object('type',v_root_type,'id',v_root_id));
    else
      v_root_id := v_entity_id; v_root_type := 'approval_request';
    end if;
    v_reference := coalesce(v_row->>'action_key',v_row->>'module_key');
    if tg_op='INSERT' then v_action := 'approval_requested';
    elsif tg_op='DELETE' then v_action := 'approval_request_deleted';
    elsif (v_old->>'status') is distinct from (v_new->>'status') then v_action := 'approval_decided';
    else v_action := 'approval_modified'; end if;

  elsif tg_table_name='document_origins' then
    v_entity_type := 'document_origin';
    v_entity_id := nullif(v_row->>'entity_id','')::uuid;
    v_root_id := v_entity_id; v_root_type := coalesce(nullif(v_row->>'entity_type',''),'document');
    v_reference := v_row->>'entity_type'; v_source_module := 'platform';
    v_actor := coalesce(nullif(v_row->>'created_by','')::uuid,auth.uid());
    if tg_op='INSERT' then v_action := 'origin_linked';
    elsif tg_op='DELETE' then v_action := 'origin_unlinked'; else v_action := 'origin_modified'; end if;
  else
    return coalesce(new,old);
  end if;

  if v_tenant is null or v_entity_id is null or v_root_id is null then
    return coalesce(new,old);
  end if;

  if v_location is null or v_device is null then
    select coalesce(v_location,o.location_id),coalesce(v_device,o.device_id)
      into v_location,v_device
    from public.document_origins o
    where o.tenant_id=v_tenant and o.entity_type=v_root_type and o.entity_id=v_root_id
    limit 1;
  end if;

  perform private.v600_story_write(
    p_tenant_id=>v_tenant,
    p_entity_type=>v_entity_type,
    p_entity_id=>v_entity_id,
    p_entity_reference=>v_reference,
    p_action=>v_action,
    p_event_time=>v_event_time,
    p_actor_user_id=>v_actor,
    p_location_id=>v_location,
    p_device_id=>v_device,
    p_before=>v_old,
    p_after=>v_new,
    p_reason=>v_reason,
    p_approval_request_id=>v_approval,
    p_source_module=>v_source_module,
    p_source_function=>'trigger:'||tg_table_name,
    p_root_entity_type=>v_root_type,
    p_root_entity_id=>v_root_id,
    p_request_id=>nullif(v_row->>'request_id',''),
    p_related_entities=>v_related,
    p_metadata=>jsonb_build_object('table',tg_table_name,'operation',tg_op,'capture_version','6.0.0-build1')
  );

  return coalesce(new,old);
end;
$$;

revoke all on function private.v600_capture_business_row() from public,anon,authenticated;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'sales','sale_items','sale_payments','sales_returns','sales_return_items',
    'purchases','purchase_items','purchase_invoices_v484','purchase_invoice_items_v484',
    'purchase_payments','supplier_payments_v484','location_stock_movements',
    'stock_adjustment_requests_v500','journal_entries','journal_lines','approval_requests','document_origins'
  ] loop
    execute format('drop trigger if exists %I on public.%I','trg_v600_transaction_story',v_table);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function private.v600_capture_business_row()','trg_v600_transaction_story',v_table);
  end loop;
end $$;

create or replace function private.v600_can_view_entity(p_tenant_id uuid,p_entity_type text)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_type text := lower(coalesce(p_entity_type,''));
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then return false; end if;
  if private.has_permission(p_tenant_id,'audit_center.view') then return true; end if;
  if v_type in ('sale','sale_item','sale_payment','sales_return','sales_return_item') then
    return private.has_permission(p_tenant_id,'sales.view') or private.has_permission(p_tenant_id,'sales.manage');
  elsif v_type in ('purchase','purchase_item','purchase_payment') then
    return private.has_permission(p_tenant_id,'purchases.view') or private.has_permission(p_tenant_id,'purchases.manage');
  elsif v_type in ('purchase_invoice','purchase_invoice_item','supplier_payment') then
    return private.has_permission(p_tenant_id,'purchasing.view') or private.has_permission(p_tenant_id,'purchasing.manage')
      or private.has_permission(p_tenant_id,'purchases.view') or private.has_permission(p_tenant_id,'purchases.manage');
  elsif v_type in ('journal_entry','journal_line') then
    return private.has_permission(p_tenant_id,'accounting.view') or private.has_permission(p_tenant_id,'accounting.manage');
  elsif v_type in ('stock_movement','stock_adjustment') then
    return private.has_permission(p_tenant_id,'inventory.view') or private.has_permission(p_tenant_id,'inventory.manage');
  elsif v_type='approval_request' then
    return private.has_permission(p_tenant_id,'approvals.view') or private.has_permission(p_tenant_id,'approvals.manage');
  end if;
  return false;
end;
$$;
revoke all on function private.v600_can_view_entity(uuid,text) from public,anon,authenticated;

create or replace function public.transaction_history_v600(
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_limit integer default 250
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_sensitive boolean;
  v_corr uuid;
  v_result jsonb;
begin
  if not private.v600_can_view_entity(p_tenant_id,p_entity_type) then
    raise exception 'Permission denied for transaction history' using errcode='42501';
  end if;
  if p_entity_id is null then raise exception 'Entity id is required'; end if;
  v_sensitive := private.has_permission(p_tenant_id,'audit_history.view_sensitive');
  v_corr := extensions.uuid_generate_v5(extensions.uuid_ns_url(),'thq:v600:'||p_tenant_id::text||':'||lower(p_entity_type)||':'||p_entity_id::text);

  select jsonb_build_object(
    'tenant_id',p_tenant_id,
    'requested_entity',jsonb_build_object('type',p_entity_type,'id',p_entity_id),
    'correlation_id',v_corr,
    'sensitive_values_visible',v_sensitive,
    'events',coalesce(jsonb_agg(jsonb_build_object(
      'sequence',e.event_sequence,
      'id',e.id,
      'action',e.action,
      'event_time',e.event_time,
      'entity_type',e.entity_type,
      'entity_id',e.entity_id,
      'entity_reference',e.entity_reference,
      'actor',jsonb_build_object('user_id',e.actor_user_id,'name',e.actor_name,'roles',e.actor_role_keys),
      'location_id',e.location_id,
      'device',jsonb_build_object('id',e.device_id,'name',e.device_name,'code',e.device_code,'app',e.source_app),
      'what_changed',e.changed_fields,
      'before',case when v_sensitive then e.before_data else null end,
      'after',case when v_sensitive then e.after_data else null end,
      'reason',e.reason,
      'approval',jsonb_build_object('request_id',e.approval_request_id,'approved_by',e.approved_by,'approved_at',e.approved_at,'note',e.approval_note),
      'source_module',e.source_module,
      'related_entities',e.related_entities,
      'integrity',jsonb_build_object('previous_hash',e.previous_event_hash,'event_hash',e.event_hash)
    ) order by e.event_sequence),'[]'::jsonb)
  ) into v_result
  from (
    select * from public.transaction_story_events_v600
    where tenant_id=p_tenant_id and correlation_id=v_corr
    order by event_sequence desc
    limit greatest(1,least(coalesce(p_limit,250),1000))
  ) e;

  return coalesce(v_result,jsonb_build_object('events','[]'::jsonb));
end;
$$;

revoke all on function public.transaction_history_v600(uuid,text,uuid,integer) from public,anon;
grant execute on function public.transaction_history_v600(uuid,text,uuid,integer) to authenticated;

create or replace function public.transaction_story_verify_v600(
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_corr uuid;
  v_prev text := null;
  v_expected text;
  v_payload jsonb;
  r record;
  v_checked integer := 0;
begin
  if not private.has_permission(p_tenant_id,'audit_center.view') then
    raise exception 'Permission denied' using errcode='42501';
  end if;
  v_corr := extensions.uuid_generate_v5(extensions.uuid_ns_url(),'thq:v600:'||p_tenant_id::text||':'||lower(p_entity_type)||':'||p_entity_id::text);
  for r in select * from public.transaction_story_events_v600 where tenant_id=p_tenant_id and correlation_id=v_corr order by event_sequence loop
    if r.previous_event_hash is distinct from v_prev then
      return jsonb_build_object('valid',false,'checked',v_checked,'failed_sequence',r.event_sequence,'reason','previous_hash_mismatch');
    end if;
    v_payload := jsonb_build_object(
      'id',r.id,'tenant_id',r.tenant_id,'correlation_id',r.correlation_id,
      'root_entity_type',r.root_entity_type,'root_entity_id',r.root_entity_id,
      'entity_type',r.entity_type,'entity_id',r.entity_id,'entity_reference',r.entity_reference,
      'action',r.action,'event_time',r.event_time,'actor_user_id',r.actor_user_id,'actor_name',r.actor_name,
      'actor_role_keys',r.actor_role_keys,'location_id',r.location_id,'device_id',r.device_id,
      'device_name',r.device_name,'device_code',r.device_code,'source_app',r.source_app,
      'request_id',r.request_id,'before_data',r.before_data,'after_data',r.after_data,'changed_fields',r.changed_fields,
      'reason',r.reason,'approval_request_id',r.approval_request_id,'approved_by',r.approved_by,
      'approved_at',r.approved_at,'approval_note',r.approval_note,'source_module',r.source_module,
      'source_function',r.source_function,'related_entities',r.related_entities,
      'metadata',r.metadata,'previous_event_hash',r.previous_event_hash
    );
    v_expected := encode(extensions.digest(coalesce(v_prev,'')||v_payload::text,'sha256'),'hex');
    if v_expected is distinct from r.event_hash then
      return jsonb_build_object('valid',false,'checked',v_checked,'failed_sequence',r.event_sequence,'reason','event_hash_mismatch');
    end if;
    v_prev := r.event_hash;
    v_checked := v_checked+1;
  end loop;
  return jsonb_build_object('valid',true,'checked',v_checked,'correlation_id',v_corr);
end;
$$;
revoke all on function public.transaction_story_verify_v600(uuid,text,uuid) from public,anon;
grant execute on function public.transaction_story_verify_v600(uuid,text,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values (256,'6.0.0-build1','THQ Transaction Story Capture + History','Captures business-significant inserts/updates/deletes for sales, payments, returns, purchases, inventory, journals, approvals and document origins into the append-only v6.0 transaction story. Adds permission-aware History/Why and hash-chain verification APIs. Existing v5.2 GST/accounting writers are not replaced or rerouted.')
on conflict (migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;