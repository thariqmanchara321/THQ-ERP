create or replace function public.audit_historical_bootstrap_v600(
  p_tenant_id uuid,
  p_from date default null,
  p_limit integer default 5000
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  r record;
  v_from date:=coalesce(p_from,date '2000-01-01');
  v_limit integer:=greatest(1,least(coalesce(p_limit,5000),20000));
  c_sales integer:=0; c_sale_payments integer:=0; c_returns integer:=0;
  c_purchases integer:=0; c_purchase_payments integer:=0; c_purchase_invoices integer:=0; c_supplier_payments integer:=0;
  c_journals integer:=0; c_adjustments integer:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) or not private.has_permission(p_tenant_id,'audit_center.configure') then
    raise exception 'Permission denied' using errcode='42501';
  end if;

  for r in
    select s.id,s.sale_number,s.created_at,s.created_by,to_jsonb(s) row_data,o.location_id,o.device_id
    from public.sales s
    left join lateral (
      select d.location_id,d.device_id from public.document_origins d
      where d.tenant_id=s.tenant_id and d.entity_type='sale' and d.entity_id=s.id order by d.created_at asc limit 1
    ) o on true
    where s.tenant_id=p_tenant_id and s.sale_date>=v_from
      and not exists(select 1 from public.transaction_story_events_v600 e where e.tenant_id=s.tenant_id and e.entity_type='sale' and e.entity_id=s.id)
    order by s.created_at limit v_limit
  loop
    perform private.v600_story_write(p_tenant_id,'sale',r.id,r.sale_number,'historical_sale_baseline',r.created_at,r.created_by,r.location_id,r.device_id,null,r.row_data,null,null,'sales','audit_historical_bootstrap_v600',null,'sale',r.id,null,'[]'::jsonb,jsonb_build_object('historical_reconstruction',true,'tracking_quality','baseline_only','no_inferred_edit_history',true));
    c_sales:=c_sales+1;
  end loop;

  for r in
    select sp.id,sp.sale_id,sp.paid_at,sp.created_by,to_jsonb(sp) row_data,s.sale_number,o.location_id,o.device_id
    from public.sale_payments sp join public.sales s on s.tenant_id=sp.tenant_id and s.id=sp.sale_id
    left join lateral (select d.location_id,d.device_id from public.document_origins d where d.tenant_id=s.tenant_id and d.entity_type='sale' and d.entity_id=s.id order by d.created_at asc limit 1) o on true
    where sp.tenant_id=p_tenant_id and s.sale_date>=v_from
      and not exists(select 1 from public.transaction_story_events_v600 e where e.tenant_id=sp.tenant_id and e.entity_type='sale_payment' and e.entity_id=sp.id)
    order by sp.paid_at limit v_limit
  loop
    perform private.v600_story_write(p_tenant_id,'sale_payment',r.id,r.sale_number,'historical_payment_baseline',r.paid_at,r.created_by,r.location_id,r.device_id,null,r.row_data,null,null,'payments','audit_historical_bootstrap_v600',null,'sale',r.sale_id,null,jsonb_build_array(jsonb_build_object('type','sale','id',r.sale_id)),jsonb_build_object('historical_reconstruction',true,'tracking_quality','baseline_only','no_inferred_edit_history',true));
    c_sale_payments:=c_sale_payments+1;
  end loop;

  for r in
    select sr.id,sr.sale_id,sr.return_number,sr.created_at,sr.created_by,sr.location_id,sr.device_id,to_jsonb(sr) row_data
    from public.sales_returns sr join public.sales s on s.tenant_id=sr.tenant_id and s.id=sr.sale_id
    where sr.tenant_id=p_tenant_id and sr.return_date>=v_from
      and not exists(select 1 from public.transaction_story_events_v600 e where e.tenant_id=sr.tenant_id and e.entity_type='sales_return' and e.entity_id=sr.id)
    order by sr.created_at limit v_limit
  loop
    perform private.v600_story_write(p_tenant_id,'sales_return',r.id,r.return_number,'historical_sales_return_baseline',r.created_at,r.created_by,r.location_id,r.device_id,null,r.row_data,r.row_data->>'reason',null,'returns','audit_historical_bootstrap_v600',null,'sale',r.sale_id,null,jsonb_build_array(jsonb_build_object('type','sale','id',r.sale_id)),jsonb_build_object('historical_reconstruction',true,'tracking_quality','baseline_only','no_inferred_edit_history',true));
    c_returns:=c_returns+1;
  end loop;

  for r in
    select p.id,p.purchase_number,p.created_at,p.created_by,to_jsonb(p) row_data,o.location_id,o.device_id
    from public.purchases p
    left join lateral (select d.location_id,d.device_id from public.document_origins d where d.tenant_id=p.tenant_id and d.entity_type='purchase' and d.entity_id=p.id order by d.created_at asc limit 1) o on true
    where p.tenant_id=p_tenant_id and p.purchase_date>=v_from
      and not exists(select 1 from public.transaction_story_events_v600 e where e.tenant_id=p.tenant_id and e.entity_type='purchase' and e.entity_id=p.id)
    order by p.created_at limit v_limit
  loop
    perform private.v600_story_write(p_tenant_id,'purchase',r.id,r.purchase_number,'historical_purchase_baseline',r.created_at,r.created_by,r.location_id,r.device_id,null,r.row_data,null,null,'purchases','audit_historical_bootstrap_v600',null,'purchase',r.id,null,'[]'::jsonb,jsonb_build_object('historical_reconstruction',true,'tracking_quality','baseline_only','no_inferred_edit_history',true));
    c_purchases:=c_purchases+1;
  end loop;

  for r in
    select pp.id,pp.purchase_id,pp.paid_at,pp.created_by,to_jsonb(pp) row_data,p.purchase_number,o.location_id,o.device_id
    from public.purchase_payments pp join public.purchases p on p.tenant_id=pp.tenant_id and p.id=pp.purchase_id
    left join lateral (select d.location_id,d.device_id from public.document_origins d where d.tenant_id=p.tenant_id and d.entity_type='purchase' and d.entity_id=p.id order by d.created_at asc limit 1) o on true
    where pp.tenant_id=p_tenant_id and p.purchase_date>=v_from
      and not exists(select 1 from public.transaction_story_events_v600 e where e.tenant_id=pp.tenant_id and e.entity_type='purchase_payment' and e.entity_id=pp.id)
    order by pp.paid_at limit v_limit
  loop
    perform private.v600_story_write(p_tenant_id,'purchase_payment',r.id,r.purchase_number,'historical_purchase_payment_baseline',r.paid_at,r.created_by,r.location_id,r.device_id,null,r.row_data,null,null,'payments','audit_historical_bootstrap_v600',null,'purchase',r.purchase_id,null,jsonb_build_array(jsonb_build_object('type','purchase','id',r.purchase_id)),jsonb_build_object('historical_reconstruction',true,'tracking_quality','baseline_only','no_inferred_edit_history',true));
    c_purchase_payments:=c_purchase_payments+1;
  end loop;

  for r in
    select pi.id,coalesce(pi.supplier_invoice_number,pi.invoice_number) reference,pi.created_at,pi.created_by,pi.location_id,to_jsonb(pi) row_data
    from public.purchase_invoices_v484 pi
    where pi.tenant_id=p_tenant_id and pi.invoice_date>=v_from
      and not exists(select 1 from public.transaction_story_events_v600 e where e.tenant_id=pi.tenant_id and e.entity_type='purchase_invoice' and e.entity_id=pi.id)
    order by pi.created_at limit v_limit
  loop
    perform private.v600_story_write(p_tenant_id,'purchase_invoice',r.id,r.reference,'historical_purchase_invoice_baseline',r.created_at,r.created_by,r.location_id,null,null,r.row_data,null,null,'purchase_details','audit_historical_bootstrap_v600',null,'purchase_invoice',r.id,null,'[]'::jsonb,jsonb_build_object('historical_reconstruction',true,'tracking_quality','baseline_only','no_inferred_edit_history',true));
    c_purchase_invoices:=c_purchase_invoices+1;
  end loop;

  for r in
    select sp.id,sp.payment_number,sp.payment_date,sp.created_at,sp.created_by,sp.location_id,to_jsonb(sp) row_data
    from public.supplier_payments_v484 sp
    where sp.tenant_id=p_tenant_id and sp.payment_date>=v_from
      and not exists(select 1 from public.transaction_story_events_v600 e where e.tenant_id=sp.tenant_id and e.entity_type='supplier_payment' and e.entity_id=sp.id)
    order by sp.created_at limit v_limit
  loop
    perform private.v600_story_write(p_tenant_id,'supplier_payment',r.id,r.payment_number,'historical_supplier_payment_baseline',r.created_at,r.created_by,r.location_id,null,null,r.row_data,null,null,'payments','audit_historical_bootstrap_v600',null,'supplier_payment',r.id,null,'[]'::jsonb,jsonb_build_object('historical_reconstruction',true,'tracking_quality','baseline_only','no_inferred_edit_history',true));
    c_supplier_payments:=c_supplier_payments+1;
  end loop;

  for r in
    select j.id,j.entry_number,j.created_at,j.created_by,j.location_id,j.source_type,j.source_id,to_jsonb(j) row_data
    from public.journal_entries j
    where j.tenant_id=p_tenant_id and j.entry_date>=v_from
      and not exists(select 1 from public.transaction_story_events_v600 e where e.tenant_id=j.tenant_id and e.entity_type='journal_entry' and e.entity_id=j.id)
    order by j.created_at limit v_limit
  loop
    perform private.v600_story_write(p_tenant_id,'journal_entry',r.id,r.entry_number,'historical_journal_baseline',r.created_at,r.created_by,r.location_id,null,null,r.row_data,null,null,'accounting','audit_historical_bootstrap_v600',null,coalesce(nullif(r.source_type,''),'journal_entry'),coalesce(r.source_id,r.id),null,
      case when r.source_id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('type',r.source_type,'id',r.source_id)) end,
      jsonb_build_object('historical_reconstruction',true,'tracking_quality','baseline_only','no_inferred_edit_history',true));
    c_journals:=c_journals+1;
  end loop;

  for r in
    select a.id,a.requested_at,a.requested_by,a.location_id,a.device_id,a.approval_request_id,to_jsonb(a) row_data
    from public.stock_adjustment_requests_v500 a
    where a.tenant_id=p_tenant_id and a.requested_at::date>=v_from
      and not exists(select 1 from public.transaction_story_events_v600 e where e.tenant_id=a.tenant_id and e.entity_type='stock_adjustment' and e.entity_id=a.id)
    order by a.requested_at limit v_limit
  loop
    perform private.v600_story_write(p_tenant_id,'stock_adjustment',r.id,r.row_data->>'request_key','historical_stock_adjustment_baseline',r.requested_at,r.requested_by,r.location_id,r.device_id,null,r.row_data,r.row_data->>'note',r.approval_request_id,'inventory','audit_historical_bootstrap_v600',null,'stock_adjustment',r.id,null,'[]'::jsonb,jsonb_build_object('historical_reconstruction',true,'tracking_quality','baseline_only','no_inferred_edit_history',true));
    c_adjustments:=c_adjustments+1;
  end loop;

  perform private.business_audit_write(p_tenant_id,'audit_historical_bootstrap','audit_center',p_tenant_id,'v6.0 historical baseline',null,jsonb_build_object('from',v_from,'sales',c_sales,'sale_payments',c_sale_payments,'sales_returns',c_returns,'purchases',c_purchases,'purchase_payments',c_purchase_payments,'purchase_invoices',c_purchase_invoices,'supplier_payments',c_supplier_payments,'journals',c_journals,'stock_adjustments',c_adjustments));

  return jsonb_build_object('from',v_from,'limit_per_type',v_limit,'created',jsonb_build_object('sales',c_sales,'sale_payments',c_sale_payments,'sales_returns',c_returns,'purchases',c_purchases,'purchase_payments',c_purchase_payments,'purchase_invoices',c_purchase_invoices,'supplier_payments',c_supplier_payments,'journals',c_journals,'stock_adjustments',c_adjustments),'rule','Baseline events only reflect records that actually exist. They do not infer historical edits, reasons, approvals or device activity not already recorded.');
end;
$$;
revoke all on function public.audit_historical_bootstrap_v600(uuid,date,integer) from public,anon;
grant execute on function public.audit_historical_bootstrap_v600(uuid,date,integer) to authenticated;

create or replace function public.audit_findings_export_v600(
  p_tenant_id uuid,
  p_severity text default null,
  p_status text default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_location_id uuid default null,
  p_limit integer default 5000
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_sensitive boolean; v_rows jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) or not private.has_permission(p_tenant_id,'audit_center.export') then raise exception 'Permission denied' using errcode='42501'; end if;
  v_sensitive:=private.has_permission(p_tenant_id,'audit_history.view_sensitive');
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',f.id,'severity',f.severity,'risk_score',f.risk_score,'rule_code',f.rule_code,'title',f.title,'description',f.description,
    'status',f.status,'detected_at',f.detected_at,'entity_type',f.entity_type,'entity_id',f.entity_id,'entity_reference',f.entity_reference,
    'location_id',f.location_id,'device_id',f.device_id,'actor_user_id',f.actor_user_id,'reviewer_id',f.reviewer_id,'reviewed_at',f.reviewed_at,
    'review_note',f.review_note,'resolution_note',f.resolution_note,
    'evidence',case when v_sensitive then f.evidence else jsonb_build_object('redacted',true,'reason','audit_history.view_sensitive permission required') end
  ) order by f.detected_at desc),'[]'::jsonb) into v_rows
  from (
    select * from public.audit_findings_v600
    where tenant_id=p_tenant_id and (p_severity is null or severity=p_severity) and (p_status is null or status=p_status)
      and (p_from is null or detected_at>=p_from) and (p_to is null or detected_at<=p_to) and (p_location_id is null or location_id=p_location_id)
    order by detected_at desc limit greatest(1,least(coalesce(p_limit,5000),20000))
  ) f;
  return jsonb_build_object('format','thq-audit-export-v600','generated_at',now(),'tenant_id',p_tenant_id,'sensitive_evidence_included',v_sensitive,
    'filters',jsonb_build_object('severity',p_severity,'status',p_status,'from',p_from,'to',p_to,'location_id',p_location_id),'rows',v_rows);
end;
$$;
revoke all on function public.audit_findings_export_v600(uuid,text,text,timestamptz,timestamptz,uuid,integer) from public,anon;
grant execute on function public.audit_findings_export_v600(uuid,text,text,timestamptz,timestamptz,uuid,integer) to authenticated;

create or replace function public.audit_finding_review_v600(
  p_tenant_id uuid,p_finding_id uuid,p_status text,p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare f public.audit_findings_v600%rowtype; v_before jsonb; v_resolve boolean;
begin
  if p_status not in ('open','under_review','explained','resolved','escalated','dismissed') then raise exception 'Invalid audit finding status'; end if;
  v_resolve:=p_status in ('resolved','escalated','dismissed');
  if v_resolve then
    if not private.has_permission(p_tenant_id,'audit_center.resolve') then raise exception 'Permission denied' using errcode='42501'; end if;
  elsif not private.has_permission(p_tenant_id,'audit_center.review') then raise exception 'Permission denied' using errcode='42501'; end if;
  select to_jsonb(x) into v_before from public.audit_findings_v600 x where x.tenant_id=p_tenant_id and x.id=p_finding_id;
  if v_before is null then raise exception 'Audit finding not found'; end if;
  update public.audit_findings_v600 set status=p_status,reviewer_id=auth.uid(),reviewed_at=now(),
    review_note=case when v_resolve then review_note else coalesce(nullif(trim(p_note),''),review_note) end,
    resolution_note=case when v_resolve then coalesce(nullif(trim(p_note),''),resolution_note) else resolution_note end
  where tenant_id=p_tenant_id and id=p_finding_id returning * into f;
  perform private.business_audit_write(p_tenant_id,'audit_finding_reviewed','audit_finding',p_finding_id,f.entity_reference,v_before,to_jsonb(f));
  return to_jsonb(f);
end;
$$;
revoke all on function public.audit_finding_review_v600(uuid,uuid,text,text) from public,anon;
grant execute on function public.audit_finding_review_v600(uuid,uuid,text,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values (263,'6.0.0-build1','Audit Historical Bootstrap + Export','Adds controlled permission-gated baseline reconstruction for existing sales, payments, returns, purchases, purchase invoices, supplier payments, journals and stock adjustments. Baselines never infer missing history. Adds audit export with sensitive-evidence redaction and makes every finding review/resolution itself auditable.')
on conflict (migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;