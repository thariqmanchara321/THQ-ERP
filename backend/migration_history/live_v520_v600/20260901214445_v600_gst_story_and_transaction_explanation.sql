create or replace function private.v600_capture_gst_evidence()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_source_type text;
  v_source_id uuid;
  v_source_number text;
  v_root_type text;
  v_root_id uuid;
  v_location uuid;
  v_actor uuid;
  v_event_time timestamptz;
  v_after jsonb;
  v_action text;
begin
  if tg_op<>'INSERT' then return new; end if;
  v_source_type:=new.source_type;
  v_source_id:=new.source_id;
  v_source_number:=new.source_number;
  v_root_type:=v_source_type;
  v_root_id:=v_source_id;

  if v_source_type='sales_return' then
    select sr.sale_id into v_root_id from public.sales_returns sr where sr.tenant_id=new.tenant_id and sr.id=v_source_id;
    if v_root_id is not null then v_root_type:='sale'; else v_root_id:=v_source_id; end if;
  end if;

  if tg_table_name='gst_document_snapshots_v520' then
    v_location:=new.location_id;
    v_actor:=new.created_by;
    v_event_time:=new.created_at;
    v_action:='gst_authoritative_snapshot_created';
    v_after:=jsonb_build_object(
      'snapshot_id',new.id,'source_type',new.source_type,'source_id',new.source_id,'source_number',new.source_number,
      'document_number',new.document_number,'document_date',new.document_date,'direction',new.direction,
      'document_kind',new.document_kind,'document_class',new.document_class,'tax_mode',new.tax_mode,
      'taxable_total',new.taxable_total,'cgst_total',new.cgst_total,'sgst_total',new.sgst_total,'utgst_total',new.utgst_total,
      'igst_total',new.igst_total,'cess_total',new.cess_total,'tax_collected_total',new.tax_collected_total,
      'rcm_tax_payable_total',new.rcm_tax_payable_total,'government_tax_total',new.government_tax_total,
      'grand_total',new.grand_total,'engine_version',new.engine_version,'snapshot_hash',new.snapshot_hash,
      'document_identity_hash',new.document_identity_hash,'evidence_class','authoritative_v520'
    );
  else
    v_location:=new.location_id;
    v_actor:=auth.uid();
    v_event_time:=new.marked_at;
    v_action:='gst_legacy_evidence_marked';
    v_after:=jsonb_build_object(
      'marker_id',new.id,'source_type',new.source_type,'source_id',new.source_id,'source_number',new.source_number,
      'document_date',new.document_date,'legacy_taxable_total',new.legacy_taxable_total,'legacy_tax_total',new.legacy_tax_total,
      'legacy_grand_total',new.legacy_grand_total,'verification_status',new.verification_status,'note',new.note,
      'source_hash',new.source_hash,'evidence_class','legacy_unverified'
    );
  end if;

  perform private.v600_story_write(
    p_tenant_id=>new.tenant_id,
    p_entity_type=>case when tg_table_name='gst_document_snapshots_v520' then 'gst_snapshot' else 'gst_legacy_marker' end,
    p_entity_id=>new.id,
    p_entity_reference=>v_source_number,
    p_action=>v_action,
    p_event_time=>v_event_time,
    p_actor_user_id=>v_actor,
    p_location_id=>v_location,
    p_before=>null,
    p_after=>v_after,
    p_source_module=>'gst_compliance',
    p_source_function=>'trigger:'||tg_table_name,
    p_root_entity_type=>v_root_type,
    p_root_entity_id=>v_root_id,
    p_related_entities=>jsonb_build_array(jsonb_build_object('type',v_source_type,'id',v_source_id)),
    p_metadata=>jsonb_build_object('capture_version','6.0.0-build1','gst_rule','v5.2 authoritative transactions never fall back to legacy after failure')
  );
  return new;
end;
$$;
revoke all on function private.v600_capture_gst_evidence() from public,anon,authenticated;

drop trigger if exists trg_v600_gst_story on public.gst_document_snapshots_v520;
create trigger trg_v600_gst_story
after insert on public.gst_document_snapshots_v520
for each row execute function private.v600_capture_gst_evidence();

drop trigger if exists trg_v600_gst_story on public.gst_legacy_document_markers_v520;
create trigger trg_v600_gst_story
after insert on public.gst_legacy_document_markers_v520
for each row execute function private.v600_capture_gst_evidence();

create or replace function public.transaction_explain_v600(
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_event_limit integer default 500
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_type text:=lower(trim(coalesce(p_entity_type,'')));
  v_root_type text;
  v_root_id uuid;
  v_corr uuid;
  v_sensitive boolean;
  v_audit boolean;
  v_accounting boolean;
  v_inventory boolean;
  v_current jsonb;
  v_origin jsonb;
  v_story jsonb:='[]'::jsonb;
  v_legacy_audit jsonb:='[]'::jsonb;
  v_payments jsonb:='[]'::jsonb;
  v_approvals jsonb:='[]'::jsonb;
  v_journals jsonb:='[]'::jsonb;
  v_stock jsonb:='[]'::jsonb;
  v_gst jsonb:='[]'::jsonb;
  v_story_count integer:=0;
  v_legacy_count integer:=0;
  v_quality text;
  v_notice text;
begin
  if p_entity_id is null then raise exception 'Entity id is required'; end if;
  if not private.v600_can_view_entity(p_tenant_id,v_type) then raise exception 'Permission denied' using errcode='42501'; end if;

  v_sensitive:=private.has_permission(p_tenant_id,'audit_history.view_sensitive');
  v_audit:=private.has_permission(p_tenant_id,'audit_center.view');
  v_accounting:=v_audit or private.has_permission(p_tenant_id,'accounting.view') or private.has_permission(p_tenant_id,'accounting.manage');
  v_inventory:=v_audit or private.has_permission(p_tenant_id,'inventory.view') or private.has_permission(p_tenant_id,'inventory.manage');
  v_root_type:=v_type; v_root_id:=p_entity_id;

  if v_type='sale' then
    select to_jsonb(s) into v_current from public.sales s where s.tenant_id=p_tenant_id and s.id=p_entity_id;
  elsif v_type='sale_item' then
    select to_jsonb(si),si.sale_id into v_current,v_root_id from public.sale_items si where si.tenant_id=p_tenant_id and si.id=p_entity_id;
    v_root_type:='sale';
  elsif v_type='sale_payment' then
    select to_jsonb(sp),sp.sale_id into v_current,v_root_id from public.sale_payments sp where sp.tenant_id=p_tenant_id and sp.id=p_entity_id;
    v_root_type:='sale';
  elsif v_type='sales_return' then
    select to_jsonb(sr),sr.sale_id into v_current,v_root_id from public.sales_returns sr where sr.tenant_id=p_tenant_id and sr.id=p_entity_id;
    v_root_type:='sale';
  elsif v_type='purchase' then
    select to_jsonb(p) into v_current from public.purchases p where p.tenant_id=p_tenant_id and p.id=p_entity_id;
  elsif v_type='purchase_item' then
    select to_jsonb(pi),pi.purchase_id into v_current,v_root_id from public.purchase_items pi where pi.tenant_id=p_tenant_id and pi.id=p_entity_id;
    v_root_type:='purchase';
  elsif v_type='purchase_payment' then
    select to_jsonb(pp),pp.purchase_id into v_current,v_root_id from public.purchase_payments pp where pp.tenant_id=p_tenant_id and pp.id=p_entity_id;
    v_root_type:='purchase';
  elsif v_type='purchase_invoice' then
    select to_jsonb(pi) into v_current from public.purchase_invoices_v484 pi where pi.tenant_id=p_tenant_id and pi.id=p_entity_id;
  elsif v_type='supplier_payment' then
    select to_jsonb(sp) into v_current from public.supplier_payments_v484 sp where sp.tenant_id=p_tenant_id and sp.id=p_entity_id;
  elsif v_type='journal_entry' then
    select to_jsonb(j) into v_current from public.journal_entries j where j.tenant_id=p_tenant_id and j.id=p_entity_id;
    if v_current is not null and nullif(v_current->>'source_id','') is not null then
      v_root_id:=(v_current->>'source_id')::uuid; v_root_type:=coalesce(nullif(v_current->>'source_type',''),'journal_entry');
    end if;
  elsif v_type='stock_adjustment' then
    select to_jsonb(a) into v_current from public.stock_adjustment_requests_v500 a where a.tenant_id=p_tenant_id and a.id=p_entity_id;
  else
    select jsonb_build_object('entity_type',v_type,'entity_id',p_entity_id) into v_current;
  end if;

  if v_current is null then raise exception 'Transaction not found'; end if;
  v_corr:=extensions.uuid_generate_v5(extensions.uuid_ns_url(),'thq:v600:'||p_tenant_id::text||':'||lower(v_root_type)||':'||v_root_id::text);

  select to_jsonb(o) into v_origin
  from public.document_origins o
  where o.tenant_id=p_tenant_id and o.entity_type=v_root_type and o.entity_id=v_root_id
  order by o.created_at asc limit 1;

  select count(*),coalesce(jsonb_agg(jsonb_build_object(
    'sequence',e.event_sequence,'id',e.id,'action',e.action,'event_time',e.event_time,
    'entity_type',e.entity_type,'entity_id',e.entity_id,'entity_reference',e.entity_reference,
    'actor',jsonb_build_object('user_id',e.actor_user_id,'name',e.actor_name,'roles',e.actor_role_keys),
    'location_id',e.location_id,'device',jsonb_build_object('id',e.device_id,'name',e.device_name,'code',e.device_code,'app',e.source_app),
    'changed_fields',e.changed_fields,'before',case when v_sensitive then e.before_data else null end,'after',case when v_sensitive then e.after_data else null end,
    'reason',e.reason,'approval',jsonb_build_object('request_id',e.approval_request_id,'approved_by',e.approved_by,'approved_at',e.approved_at,'note',e.approval_note),
    'source_module',e.source_module,'related_entities',e.related_entities,'event_hash',e.event_hash
  ) order by e.event_sequence),'[]'::jsonb)
  into v_story_count,v_story
  from (
    select * from public.transaction_story_events_v600
    where tenant_id=p_tenant_id and correlation_id=v_corr
    order by event_sequence
    limit greatest(1,least(coalesce(p_event_limit,500),2000))
  ) e;

  select count(*),coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,'action',a.action,'entity_type',a.entity_type,'entity_id',a.entity_id,'entity_reference',a.entity_reference,
    'user_id',a.user_id,'created_at',a.created_at,'location_id',a.location_id,'device_id',a.device_id,'reason',a.reason,
    'before',case when v_sensitive then a.before_data else null end,'after',case when v_sensitive then a.after_data else null end,'metadata',a.metadata
  ) order by a.created_at),'[]'::jsonb)
  into v_legacy_count,v_legacy_audit
  from public.business_audit_log a
  where a.tenant_id=p_tenant_id and (
    (a.entity_type=v_type and a.entity_id=p_entity_id) or
    (a.entity_type=v_root_type and a.entity_id=v_root_id)
  );

  if v_root_type='sale' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',sp.id,'amount',sp.amount,'method',sp.payment_method,'reference',sp.reference_number,'notes',sp.notes,
      'paid_at',sp.paid_at,'created_by',sp.created_by,'created_by_name',u.username::text
    ) order by sp.paid_at,sp.id),'[]'::jsonb) into v_payments
    from public.sale_payments sp left join public.user_login_names u on u.user_id=sp.created_by
    where sp.tenant_id=p_tenant_id and sp.sale_id=v_root_id;
  elsif v_root_type='purchase' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',pp.id,'amount',pp.amount,'method',pp.payment_method,'reference',pp.reference_number,'notes',pp.notes,
      'paid_at',pp.paid_at,'created_by',pp.created_by,'created_by_name',u.username::text
    ) order by pp.paid_at,pp.id),'[]'::jsonb) into v_payments
    from public.purchase_payments pp left join public.user_login_names u on u.user_id=pp.created_by
    where pp.tenant_id=p_tenant_id and pp.purchase_id=v_root_id;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',ar.id,'module',ar.module_key,'action',ar.action_key,'entity_type',ar.entity_type,'entity_id',ar.entity_id,
    'amount',ar.amount,'percentage',ar.percentage,'status',ar.status,'reason',ar.reason,
    'requested_by',ar.requested_by,'requested_at',ar.requested_at,'decided_by',ar.decided_by,'decided_at',ar.decided_at,'decision_note',ar.decision_note
  ) order by ar.requested_at),'[]'::jsonb) into v_approvals
  from public.approval_requests ar
  where ar.tenant_id=p_tenant_id and (
    (ar.entity_type=v_type and ar.entity_id=p_entity_id) or
    (ar.entity_type=v_root_type and ar.entity_id=v_root_id)
  );

  if v_accounting then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',j.id,'entry_number',j.entry_number,'entry_date',j.entry_date,'description',j.description,'status',j.status,
      'source_type',j.source_type,'source_id',j.source_id,'source_reference',j.source_reference,'reversal_of',j.reversal_of,
      'created_by',j.created_by,'created_at',j.created_at,'posted_at',j.posted_at,'location_id',j.location_id
    ) order by j.entry_date,j.created_at),'[]'::jsonb) into v_journals
    from public.journal_entries j
    where j.tenant_id=p_tenant_id and (
      (j.source_type=v_root_type and j.source_id=v_root_id) or
      (v_root_type='sale' and j.source_type='sales_return' and exists(select 1 from public.sales_returns sr where sr.tenant_id=p_tenant_id and sr.sale_id=v_root_id and sr.id=j.source_id))
    );
  end if;

  if v_inventory then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',m.id,'movement_type',m.movement_type,'variant_id',m.variant_id,'quantity_delta',m.quantity_delta,'unit_cost',m.unit_cost,
      'reference_type',m.reference_type,'reference_id',m.reference_id,'reference_number',m.reference_number,'note',m.note,
      'created_by',m.created_by,'device_id',m.device_id,'created_at',m.created_at,'balance_before',m.balance_before,'balance_after',m.balance_after,
      'movement_group',m.movement_group
    ) order by m.created_at,m.id),'[]'::jsonb) into v_stock
    from public.location_stock_movements m
    where m.tenant_id=p_tenant_id and (
      (m.reference_type=v_root_type and m.reference_id=v_root_id) or
      (v_root_type='sale' and m.reference_type='sales_return' and exists(select 1 from public.sales_returns sr where sr.tenant_id=p_tenant_id and sr.sale_id=v_root_id and sr.id=m.reference_id))
    );
  end if;

  select coalesce(jsonb_agg(x.evidence order by x.evidence_time,x.evidence_id),'[]'::jsonb) into v_gst
  from (
    select s.id evidence_id,s.created_at evidence_time,jsonb_build_object(
      'evidence_type','authoritative_snapshot','id',s.id,'source_type',s.source_type,'source_id',s.source_id,'source_number',s.source_number,
      'document_number',s.document_number,'document_date',s.document_date,'location_id',s.location_id,'tax_mode',s.tax_mode,
      'taxable_total',s.taxable_total,'cgst_total',s.cgst_total,'sgst_total',s.sgst_total,'utgst_total',s.utgst_total,'igst_total',s.igst_total,
      'cess_total',s.cess_total,'tax_collected_total',s.tax_collected_total,'rcm_tax_payable_total',s.rcm_tax_payable_total,
      'government_tax_total',s.government_tax_total,'grand_total',s.grand_total,'engine_version',s.engine_version,
      'snapshot_hash',s.snapshot_hash,'document_identity_hash',s.document_identity_hash,'created_at',s.created_at
    ) evidence
    from public.gst_document_snapshots_v520 s
    where s.tenant_id=p_tenant_id and (
      (s.source_type=v_root_type and s.source_id=v_root_id) or
      (v_root_type='sale' and s.source_type='sales_return' and exists(select 1 from public.sales_returns sr where sr.tenant_id=p_tenant_id and sr.sale_id=v_root_id and sr.id=s.source_id))
    )
    union all
    select l.id,l.marked_at,jsonb_build_object(
      'evidence_type','legacy_unverified','id',l.id,'source_type',l.source_type,'source_id',l.source_id,'source_number',l.source_number,
      'document_date',l.document_date,'location_id',l.location_id,'legacy_taxable_total',l.legacy_taxable_total,'legacy_tax_total',l.legacy_tax_total,
      'legacy_grand_total',l.legacy_grand_total,'verification_status',l.verification_status,'note',l.note,'source_hash',l.source_hash,'marked_at',l.marked_at
    )
    from public.gst_legacy_document_markers_v520 l
    where l.tenant_id=p_tenant_id and (
      (l.source_type=v_root_type and l.source_id=v_root_id) or
      (v_root_type='sale' and l.source_type='sales_return' and exists(select 1 from public.sales_returns sr where sr.tenant_id=p_tenant_id and sr.sale_id=v_root_id and sr.id=l.source_id))
    )
  ) x;

  if v_story_count>0 then
    v_quality:='enhanced_v600';
    v_notice:='v6.0 Transaction Story evidence is available. Older actions not captured before v6.0 are shown only when existing THQ records provide real evidence.';
  elsif v_legacy_count>0 then
    v_quality:='historical_partial';
    v_notice:='Historical transaction: enhanced v6.0 event tracking was not active. Existing audit/payment/stock/journal/GST records are shown; missing actor/edit/device/reason history is not inferred.';
  else
    v_quality:='historical_baseline_only';
    v_notice:='Historical transaction: enhanced tracking was not active when this record was created. THQ shows current state and related recorded evidence only; no missing history is fabricated.';
  end if;

  return jsonb_build_object(
    'requested_entity',jsonb_build_object('type',v_type,'id',p_entity_id),
    'transaction_root',jsonb_build_object('type',v_root_type,'id',v_root_id,'correlation_id',v_corr),
    'tracking_quality',v_quality,'historical_notice',v_notice,'sensitive_values_visible',v_sensitive,
    'current_record',v_current,'origin',v_origin,
    'transaction_story',v_story,'legacy_audit_evidence',v_legacy_audit,
    'payments',v_payments,'approvals',v_approvals,'journals',v_journals,'stock_movements',v_stock,'gst_evidence',v_gst,
    'accounting_visible',v_accounting,'inventory_visible',v_inventory,
    'gst_integrity_rule','Authoritative v5.2 GST snapshots remain authoritative. A failed v5.2 transaction must never be re-routed to a legacy writer; legacy markers are historical evidence only.'
  );
end;
$$;
revoke all on function public.transaction_explain_v600(uuid,text,uuid,integer) from public,anon;
grant execute on function public.transaction_explain_v600(uuid,text,uuid,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values (262,'6.0.0-build1','GST Story + Why Explanation Contract','Adds v6.0 Transaction Story capture for authoritative GST snapshots and legacy GST evidence without altering v5.2 writers. Adds the reusable Why/History explanation RPC combining v6 events with genuine historical audit, payment, approval, device/origin, permitted journal/stock and GST evidence. Historical gaps are explicitly labeled and never fabricated. The no-legacy-fallback rule for failed v5.2 transactions is preserved.')
on conflict (migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;