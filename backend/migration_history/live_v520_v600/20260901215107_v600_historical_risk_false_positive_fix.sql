create or replace function private.v600_evaluate_story_event()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  c public.audit_risk_config_v600%rowtype;
  v_discount_pct numeric := 0;
  v_subtotal numeric;
  v_discount numeric;
  v_gp numeric;
  v_value numeric;
  v_days integer;
  v_entry_date date;
  v_sale_date date;
  v_paid boolean := false;
  v_historical boolean := coalesce((new.metadata->>'historical_reconstruction')::boolean,false);
  v_financial_fields text[] := array['customer_id','sale_date','due_date','quantity','unit_price','unit_cost','discount_amount','discount_total','tax_rate','taxable_total','tax_total','additional_charges','grand_total','cost_total','gross_profit','round_off','status'];
begin
  select * into c from public.audit_risk_config_v600 where tenant_id=new.tenant_id;
  if not found then
    insert into public.audit_risk_config_v600(tenant_id) values(new.tenant_id) on conflict do nothing;
    select * into c from public.audit_risk_config_v600 where tenant_id=new.tenant_id;
  end if;
  if not coalesce(c.active,true) then return new; end if;

  if new.action in ('sale_deleted','sales_return_deleted','purchase_deleted','purchase_invoice_deleted','payment_deleted','supplier_payment_deleted','journal_deleted','stock_movement_deleted','approval_request_deleted') then
    perform private.v600_add_finding(new,'high_risk','DELETION_OR_REMOVAL','Deleted or removed business record','A business-significant record was deleted or removed. Review the full transaction story and linked accounting/stock effects.',95,jsonb_build_object('operation',new.action));
  end if;

  if new.entity_type='sale' and new.after_data is not null then
    begin v_subtotal := nullif(new.after_data->>'subtotal','')::numeric; exception when others then v_subtotal := null; end;
    begin v_discount := nullif(new.after_data->>'discount_total','')::numeric; exception when others then v_discount := null; end;
    if coalesce(v_subtotal,0)<>0 then v_discount_pct := round(abs(coalesce(v_discount,0))*100/abs(v_subtotal),4); end if;
    if v_discount_pct >= c.discount_high_pct and v_discount_pct>0 then
      perform private.v600_add_finding(new,'high_risk','UNUSUAL_DISCOUNT_HIGH','Unusually high discount','Discount exceeds the tenant high-risk threshold.',88,jsonb_build_object('discount_pct',v_discount_pct,'threshold_pct',c.discount_high_pct,'subtotal',v_subtotal,'discount',v_discount));
    elsif v_discount_pct >= c.discount_review_pct and v_discount_pct>0 then
      perform private.v600_add_finding(new,'needs_review','UNUSUAL_DISCOUNT_REVIEW','Discount needs review','Discount exceeds the tenant review threshold.',62,jsonb_build_object('discount_pct',v_discount_pct,'threshold_pct',c.discount_review_pct,'subtotal',v_subtotal,'discount',v_discount));
    end if;
    begin v_gp := nullif(new.after_data->>'gross_profit','')::numeric; exception when others then v_gp := null; end;
    if c.negative_margin_high and coalesce(v_gp,0)<0 then
      perform private.v600_add_finding(new,'high_risk','NEGATIVE_MARGIN_SALE','Negative-margin sale','Recognized gross profit for the sale is negative.',92,jsonb_build_object('gross_profit',v_gp,'grand_total',new.after_data->>'grand_total','cost_total',new.after_data->>'cost_total'));
    end if;
    if not v_historical then
      begin v_sale_date := nullif(new.after_data->>'sale_date','')::date; exception when others then v_sale_date := null; end;
      if v_sale_date is not null then
        v_days := new.event_time::date-v_sale_date;
        if v_days >= c.backdate_high_days and v_days>0 then
          perform private.v600_add_finding(new,'high_risk','BACKDATED_SALE_HIGH','Significantly backdated sale','Sale date is substantially earlier than the recorded transaction time.',86,jsonb_build_object('backdated_days',v_days,'threshold_days',c.backdate_high_days,'sale_date',v_sale_date));
        elsif v_days >= c.backdate_review_days and v_days>0 then
          perform private.v600_add_finding(new,'needs_review','BACKDATED_SALE_REVIEW','Backdated sale','Sale date is earlier than the recorded transaction time beyond the review threshold.',58,jsonb_build_object('backdated_days',v_days,'threshold_days',c.backdate_review_days,'sale_date',v_sale_date));
        end if;
      end if;
    end if;
  end if;

  if new.entity_type='sale_item' and new.after_data is not null then
    begin v_gp := nullif(new.after_data->>'gross_profit','')::numeric; exception when others then v_gp := null; end;
    if c.negative_margin_high and coalesce(v_gp,0)<0 then
      perform private.v600_add_finding(new,'high_risk','NEGATIVE_MARGIN_ITEM','Negative-margin product line','A sale line has negative recognized gross profit.',90,jsonb_build_object('gross_profit',v_gp,'sku',new.after_data->>'sku','product_name',new.after_data->>'product_name'));
    end if;
  end if;

  if new.action in ('sale_modified','sale_item_modified') and c.payment_edit_high and new.root_entity_type='sale' then
    select exists(select 1 from public.sale_payments sp where sp.tenant_id=new.tenant_id and sp.sale_id=new.root_entity_id) into v_paid;
    if v_paid and new.changed_fields && v_financial_fields then
      perform private.v600_add_finding(new,'high_risk','EDIT_AFTER_PAYMENT','Invoice changed after payment','Financial or commercial fields changed after at least one payment had been recorded.',91,jsonb_build_object('changed_fields',new.changed_fields));
    end if;
  end if;

  if new.action in ('payment_modified','supplier_payment_modified') and c.payment_edit_high then
    perform private.v600_add_finding(new,'high_risk','PAYMENT_EDITED','Posted payment changed','A recorded payment was modified. Review method, amount, reference, actor and linked journal.',94,jsonb_build_object('before',new.before_data,'after',new.after_data));
  end if;

  if new.entity_type in ('purchase','purchase_invoice') and new.action like '%modified' and c.posted_purchase_edit_review then
    if coalesce(new.before_data->>'posted_at',new.after_data->>'posted_at','')<>'' or coalesce(new.before_data->>'status',new.after_data->>'status','') in ('posted','approved','received') then
      perform private.v600_add_finding(new,'needs_review','POSTED_PURCHASE_EDIT','Posted purchase changed','A posted/approved purchase record was modified and should be reviewed.',72,jsonb_build_object('changed_fields',new.changed_fields,'status',coalesce(new.after_data->>'status',new.before_data->>'status')));
    end if;
  end if;

  if new.entity_type='stock_adjustment' then
    perform private.v600_add_finding(new,'needs_review','STOCK_ADJUSTMENT','Stock adjustment','A manual stock adjustment request was created or changed.',68,jsonb_build_object('quantity_delta',coalesce(new.after_data->>'quantity_delta',new.before_data->>'quantity_delta'),'status',coalesce(new.after_data->>'status',new.before_data->>'status')));
  end if;

  if new.entity_type='stock_movement' and lower(coalesce(new.after_data->>'movement_type',new.before_data->>'movement_type','')) like '%adjust%' then
    begin v_value := abs(coalesce(nullif(coalesce(new.after_data->>'quantity_delta',new.before_data->>'quantity_delta'),'')::numeric,0) * coalesce(nullif(coalesce(new.after_data->>'unit_cost',new.before_data->>'unit_cost'),'')::numeric,0)); exception when others then v_value := 0; end;
    if v_value>=c.stock_adjustment_high_value then
      perform private.v600_add_finding(new,'high_risk','STOCK_ADJUSTMENT_HIGH_VALUE','High-value stock adjustment','The estimated value of a stock adjustment exceeds the high-risk threshold.',89,jsonb_build_object('estimated_value',v_value,'threshold_value',c.stock_adjustment_high_value));
    elsif v_value>=c.stock_adjustment_review_value then
      perform private.v600_add_finding(new,'needs_review','STOCK_ADJUSTMENT_VALUE_REVIEW','Stock adjustment value needs review','The estimated value of a stock adjustment exceeds the review threshold.',66,jsonb_build_object('estimated_value',v_value,'threshold_value',c.stock_adjustment_review_value));
    end if;
  end if;

  if new.entity_type='journal_entry' and new.after_data is not null then
    if c.manual_journal_review and nullif(new.after_data->>'source_id','') is null then
      perform private.v600_add_finding(new,'needs_review','MANUAL_JOURNAL','Manual journal','A journal entry has no source transaction and should be reviewed as a manual journal.',64,jsonb_build_object('entry_number',new.after_data->>'entry_number','description',new.after_data->>'description'));
    end if;
    if not v_historical then
      begin v_entry_date := nullif(new.after_data->>'entry_date','')::date; exception when others then v_entry_date := null; end;
      if v_entry_date is not null then
        v_days := new.event_time::date-v_entry_date;
        if v_days>=c.backdate_high_days and v_days>0 then
          perform private.v600_add_finding(new,'high_risk','BACKDATED_JOURNAL_HIGH','Significantly backdated journal','Journal entry date is substantially earlier than the recorded event time.',87,jsonb_build_object('backdated_days',v_days,'entry_date',v_entry_date));
        elsif v_days>=c.backdate_review_days and v_days>0 then
          perform private.v600_add_finding(new,'needs_review','BACKDATED_JOURNAL_REVIEW','Backdated journal','Journal entry date is earlier than the recorded event time beyond the review threshold.',60,jsonb_build_object('backdated_days',v_days,'entry_date',v_entry_date));
        end if;
      end if;
    end if;
  end if;

  return new;
exception when others then
  begin
    perform private.platform_audit_write('audit_risk_evaluation_error','transaction_story_event',new.id::text,new.tenant_id,jsonb_build_object('sqlstate',sqlstate,'message',sqlerrm));
  exception when others then null;
  end;
  return new;
end;
$$;

with affected as (
  select f.id,f.tenant_id,f.entity_reference,f.status
  from public.audit_findings_v600 f
  join public.transaction_story_events_v600 e on e.tenant_id=f.tenant_id and e.id=f.source_event_id
  where coalesce((e.metadata->>'historical_reconstruction')::boolean,false)
    and f.rule_code in ('BACKDATED_SALE_HIGH','BACKDATED_SALE_REVIEW','BACKDATED_JOURNAL_HIGH','BACKDATED_JOURNAL_REVIEW')
    and f.status not in ('resolved','dismissed')
), updated as (
  update public.audit_findings_v600 f
  set status='dismissed',
      reviewer_id=null,
      reviewed_at=now(),
      resolution_note='Automatically dismissed by THQ v6.0 baseline-risk correction: historical reconstruction timing is not evidence that a user backdated the original transaction.'
  from affected a
  where f.id=a.id
  returning f.id,f.tenant_id,f.entity_reference
)
select count(*) from updated;

insert into public.business_audit_log(
  tenant_id,action,entity_type,entity_id,entity_reference,user_id,reason,before_data,after_data,metadata
)
select t.id,'audit_baseline_risk_correction','audit_center',t.id,'v6.0 baseline timing correction',null,
  'Historical reconstruction timestamps are not user backdating evidence.',null::jsonb,
  jsonb_build_object('rule_codes',jsonb_build_array('BACKDATED_SALE_HIGH','BACKDATED_SALE_REVIEW','BACKDATED_JOURNAL_HIGH','BACKDATED_JOURNAL_REVIEW')),
  jsonb_build_object('system_correction',true,'release','6.0.0-build1')
from public.tenants t
where exists(
  select 1 from public.audit_findings_v600 f
  join public.transaction_story_events_v600 e on e.tenant_id=f.tenant_id and e.id=f.source_event_id
  where f.tenant_id=t.id
    and coalesce((e.metadata->>'historical_reconstruction')::boolean,false)
    and f.rule_code in ('BACKDATED_SALE_HIGH','BACKDATED_SALE_REVIEW','BACKDATED_JOURNAL_HIGH','BACKDATED_JOURNAL_REVIEW')
    and f.status='dismissed'
    and f.resolution_note like 'Automatically dismissed by THQ v6.0 baseline-risk correction:%'
);

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values (266,'6.0.0-build1','Historical Risk False-Positive Correction','Prevents reconstructed historical baseline timestamps from triggering backdated sale/journal risk rules. Existing baseline-derived backdate findings are preserved as immutable evidence but system-dismissed with an explicit correction note instead of being deleted. Static factual checks such as negative margin, unusual discount and manual journal remain eligible on historical baselines.')
on conflict (migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;