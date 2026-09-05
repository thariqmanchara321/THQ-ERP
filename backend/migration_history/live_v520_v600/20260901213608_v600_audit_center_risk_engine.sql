insert into public.tenant_modules(tenant_id,module_key,enabled,config)
select t.id,'audit_center',true,'{}'::jsonb
from public.tenants t
on conflict (tenant_id,module_key) do update set enabled=true,updated_at=now();

create table if not exists public.audit_risk_config_v600 (
  tenant_id uuid primary key,
  discount_review_pct numeric(9,4) not null default 10,
  discount_high_pct numeric(9,4) not null default 20,
  stock_adjustment_review_value numeric(18,4) not null default 10000,
  stock_adjustment_high_value numeric(18,4) not null default 50000,
  backdate_review_days integer not null default 1,
  backdate_high_days integer not null default 7,
  negative_margin_high boolean not null default true,
  payment_edit_high boolean not null default true,
  posted_purchase_edit_review boolean not null default true,
  manual_journal_review boolean not null default true,
  active boolean not null default true,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  constraint audit_risk_config_v600_discount_chk check (discount_review_pct>=0 and discount_high_pct>=discount_review_pct),
  constraint audit_risk_config_v600_stock_chk check (stock_adjustment_review_value>=0 and stock_adjustment_high_value>=stock_adjustment_review_value),
  constraint audit_risk_config_v600_backdate_chk check (backdate_review_days>=0 and backdate_high_days>=backdate_review_days)
);

insert into public.audit_risk_config_v600(tenant_id)
select id from public.tenants
on conflict (tenant_id) do nothing;

alter table public.audit_risk_config_v600 enable row level security;
revoke all on public.audit_risk_config_v600 from anon,authenticated;

create table if not exists public.audit_findings_v600 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  source_event_id uuid not null,
  correlation_id uuid not null,
  severity text not null,
  rule_code text not null,
  title text not null,
  description text not null,
  risk_score numeric(6,2) not null,
  entity_type text not null,
  entity_id uuid not null,
  entity_reference text,
  location_id uuid,
  device_id uuid,
  actor_user_id uuid,
  detected_at timestamptz not null default now(),
  evidence jsonb not null default '{}'::jsonb,
  status text not null default 'open',
  reviewer_id uuid,
  reviewed_at timestamptz,
  review_note text,
  resolution_note text,
  updated_at timestamptz not null default now(),
  constraint audit_findings_v600_severity_chk check (severity in ('high_risk','needs_review')),
  constraint audit_findings_v600_status_chk check (status in ('open','under_review','explained','resolved','escalated','dismissed')),
  constraint audit_findings_v600_score_chk check (risk_score between 0 and 100),
  constraint audit_findings_v600_event_rule_uq unique(tenant_id,source_event_id,rule_code)
);

create index if not exists audit_findings_v600_queue_idx on public.audit_findings_v600(tenant_id,status,severity,detected_at desc);
create index if not exists audit_findings_v600_corr_idx on public.audit_findings_v600(tenant_id,correlation_id,detected_at desc);
create index if not exists audit_findings_v600_entity_idx on public.audit_findings_v600(tenant_id,entity_type,entity_id,detected_at desc);
create index if not exists audit_findings_v600_location_idx on public.audit_findings_v600(tenant_id,location_id,detected_at desc) where location_id is not null;

alter table public.audit_findings_v600 enable row level security;
revoke all on public.audit_findings_v600 from anon,authenticated;

create or replace function private.v600_guard_finding_evidence()
returns trigger
language plpgsql
security invoker
set search_path=''
as $$
begin
  if old.tenant_id is distinct from new.tenant_id
    or old.source_event_id is distinct from new.source_event_id
    or old.correlation_id is distinct from new.correlation_id
    or old.severity is distinct from new.severity
    or old.rule_code is distinct from new.rule_code
    or old.title is distinct from new.title
    or old.description is distinct from new.description
    or old.risk_score is distinct from new.risk_score
    or old.entity_type is distinct from new.entity_type
    or old.entity_id is distinct from new.entity_id
    or old.entity_reference is distinct from new.entity_reference
    or old.location_id is distinct from new.location_id
    or old.device_id is distinct from new.device_id
    or old.actor_user_id is distinct from new.actor_user_id
    or old.detected_at is distinct from new.detected_at
    or old.evidence is distinct from new.evidence then
      raise exception 'Audit finding evidence is immutable; only review lifecycle fields may change' using errcode='55000';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function private.v600_guard_finding_evidence() from public,anon,authenticated;

drop trigger if exists trg_v600_finding_evidence_guard on public.audit_findings_v600;
create trigger trg_v600_finding_evidence_guard
before update on public.audit_findings_v600
for each row execute function private.v600_guard_finding_evidence();

create or replace function private.v600_add_finding(
  p_event public.transaction_story_events_v600,
  p_severity text,
  p_rule_code text,
  p_title text,
  p_description text,
  p_score numeric,
  p_evidence jsonb
)
returns void
language plpgsql
security definer
set search_path=''
as $$
begin
  insert into public.audit_findings_v600(
    tenant_id,source_event_id,correlation_id,severity,rule_code,title,description,risk_score,
    entity_type,entity_id,entity_reference,location_id,device_id,actor_user_id,detected_at,evidence
  ) values (
    p_event.tenant_id,p_event.id,p_event.correlation_id,p_severity,p_rule_code,p_title,p_description,p_score,
    p_event.entity_type,p_event.entity_id,p_event.entity_reference,p_event.location_id,p_event.device_id,p_event.actor_user_id,
    p_event.event_time,coalesce(p_evidence,'{}'::jsonb) || jsonb_build_object('event_id',p_event.id,'action',p_event.action,'changed_fields',p_event.changed_fields)
  )
  on conflict (tenant_id,source_event_id,rule_code) do nothing;
end;
$$;
revoke all on function private.v600_add_finding(public.transaction_story_events_v600,text,text,text,text,numeric,jsonb) from public,anon,authenticated;

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

  return new;
exception when others then
  begin
    perform private.platform_audit_write('audit_risk_evaluation_error','transaction_story_event',new.id::text,new.tenant_id,jsonb_build_object('sqlstate',sqlstate,'message',sqlerrm));
  exception when others then null;
  end;
  return new;
end;
$$;
revoke all on function private.v600_evaluate_story_event() from public,anon,authenticated;

drop trigger if exists trg_v600_audit_risk_eval on public.transaction_story_events_v600;
create trigger trg_v600_audit_risk_eval
after insert on public.transaction_story_events_v600
for each row execute function private.v600_evaluate_story_event();

create or replace function private.v600_seed_role_permissions()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.key='auditor' then
    insert into public.role_permissions(role_id,permission_key)
    select new.id,x.k from (values('audit_center.view'::text),('audit_center.review'),('audit_center.export'),('audit_history.view_sensitive'),('profitability.view'),('explain.view')) x(k)
    on conflict do nothing;
  elsif new.key='owner' then
    insert into public.role_permissions(role_id,permission_key)
    select new.id,x.k from (values('audit_center.view'::text),('audit_center.review'),('audit_center.resolve'),('audit_center.export'),('audit_center.configure'),('audit_history.view_sensitive'),('profitability.view'),('explain.view')) x(k)
    on conflict do nothing;
  elsif new.key in ('manager','accountant') then
    insert into public.role_permissions(role_id,permission_key)
    select new.id,x.k from (values('audit_center.view'::text),('audit_center.review'),('audit_center.resolve'),('audit_center.export'),('profitability.view'),('explain.view')) x(k)
    on conflict do nothing;
  end if;
  return new;
end;
$$;
revoke all on function private.v600_seed_role_permissions() from public,anon,authenticated;

drop trigger if exists trg_v600_seed_role_permissions on public.roles;
create trigger trg_v600_seed_role_permissions
after insert or update of key on public.roles
for each row execute function private.v600_seed_role_permissions();

create or replace function private.v600_seed_tenant_audit()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare v_role uuid;
begin
  insert into public.tenant_modules(tenant_id,module_key,enabled,config) values(new.id,'audit_center',true,'{}'::jsonb) on conflict (tenant_id,module_key) do update set enabled=true,updated_at=now();
  insert into public.audit_risk_config_v600(tenant_id) values(new.id) on conflict do nothing;
  select id into v_role from public.roles where tenant_id=new.id and key='auditor';
  if v_role is null then
    insert into public.roles(id,tenant_id,key,name,is_system) values(gen_random_uuid(),new.id,'auditor','Auditor',true) returning id into v_role;
  end if;
  return new;
end;
$$;
revoke all on function private.v600_seed_tenant_audit() from public,anon,authenticated;

drop trigger if exists trg_v600_seed_tenant_audit on public.tenants;
create trigger trg_v600_seed_tenant_audit
after insert on public.tenants
for each row execute function private.v600_seed_tenant_audit();

create or replace function public.audit_risk_config_get_v600(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare c public.audit_risk_config_v600%rowtype;
begin
  if not private.has_permission(p_tenant_id,'audit_center.view') then raise exception 'Permission denied' using errcode='42501'; end if;
  select * into c from public.audit_risk_config_v600 where tenant_id=p_tenant_id;
  return to_jsonb(c)-'updated_by';
end;
$$;
revoke all on function public.audit_risk_config_get_v600(uuid) from public,anon;
grant execute on function public.audit_risk_config_get_v600(uuid) to authenticated;

create or replace function public.audit_risk_config_set_v600(p_tenant_id uuid,p_config jsonb)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare c public.audit_risk_config_v600%rowtype;
begin
  if not private.has_permission(p_tenant_id,'audit_center.configure') then raise exception 'Permission denied' using errcode='42501'; end if;
  insert into public.audit_risk_config_v600(
    tenant_id,discount_review_pct,discount_high_pct,stock_adjustment_review_value,stock_adjustment_high_value,
    backdate_review_days,backdate_high_days,negative_margin_high,payment_edit_high,posted_purchase_edit_review,manual_journal_review,active,updated_by,updated_at
  ) values (
    p_tenant_id,
    coalesce((p_config->>'discount_review_pct')::numeric,10),
    coalesce((p_config->>'discount_high_pct')::numeric,20),
    coalesce((p_config->>'stock_adjustment_review_value')::numeric,10000),
    coalesce((p_config->>'stock_adjustment_high_value')::numeric,50000),
    coalesce((p_config->>'backdate_review_days')::integer,1),
    coalesce((p_config->>'backdate_high_days')::integer,7),
    coalesce((p_config->>'negative_margin_high')::boolean,true),
    coalesce((p_config->>'payment_edit_high')::boolean,true),
    coalesce((p_config->>'posted_purchase_edit_review')::boolean,true),
    coalesce((p_config->>'manual_journal_review')::boolean,true),
    coalesce((p_config->>'active')::boolean,true),auth.uid(),now()
  )
  on conflict (tenant_id) do update set
    discount_review_pct=excluded.discount_review_pct,discount_high_pct=excluded.discount_high_pct,
    stock_adjustment_review_value=excluded.stock_adjustment_review_value,stock_adjustment_high_value=excluded.stock_adjustment_high_value,
    backdate_review_days=excluded.backdate_review_days,backdate_high_days=excluded.backdate_high_days,
    negative_margin_high=excluded.negative_margin_high,payment_edit_high=excluded.payment_edit_high,
    posted_purchase_edit_review=excluded.posted_purchase_edit_review,manual_journal_review=excluded.manual_journal_review,
    active=excluded.active,updated_by=auth.uid(),updated_at=now()
  returning * into c;
  perform private.business_audit_write(p_tenant_id,'audit_risk_config_updated','audit_risk_config',p_tenant_id,'v6.0 audit risk thresholds',null,to_jsonb(c));
  return to_jsonb(c)-'updated_by';
end;
$$;
revoke all on function public.audit_risk_config_set_v600(uuid,jsonb) from public,anon;
grant execute on function public.audit_risk_config_set_v600(uuid,jsonb) to authenticated;

create or replace function public.audit_center_summary_v600(
  p_tenant_id uuid,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_location_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_from timestamptz := coalesce(p_from,date_trunc('day',now()));
  v_to timestamptz := coalesce(p_to,now());
  v_high bigint; v_review bigint; v_open bigint; v_normal bigint; v_total_roots bigint;
begin
  if not private.has_permission(p_tenant_id,'audit_center.view') then raise exception 'Permission denied' using errcode='42501'; end if;
  select count(*) filter(where severity='high_risk'),count(*) filter(where severity='needs_review'),count(*) filter(where status in ('open','under_review','escalated'))
    into v_high,v_review,v_open
  from public.audit_findings_v600 f
  where f.tenant_id=p_tenant_id and f.detected_at>=v_from and f.detected_at<=v_to
    and (p_location_id is null or f.location_id=p_location_id);
  select count(distinct e.correlation_id) into v_total_roots
  from public.transaction_story_events_v600 e
  where e.tenant_id=p_tenant_id and e.event_time>=v_from and e.event_time<=v_to
    and (p_location_id is null or e.location_id=p_location_id);
  select count(*) into v_normal from (
    select distinct e.correlation_id
    from public.transaction_story_events_v600 e
    where e.tenant_id=p_tenant_id and e.event_time>=v_from and e.event_time<=v_to
      and (p_location_id is null or e.location_id=p_location_id)
      and not exists (select 1 from public.audit_findings_v600 f where f.tenant_id=e.tenant_id and f.correlation_id=e.correlation_id and f.detected_at>=v_from and f.detected_at<=v_to)
  ) q;
  return jsonb_build_object('from',v_from,'to',v_to,'location_id',p_location_id,'high_risk',coalesce(v_high,0),'needs_review',coalesce(v_review,0),'normal',coalesce(v_normal,0),'open_attention',coalesce(v_open,0),'transaction_roots',coalesce(v_total_roots,0));
end;
$$;
revoke all on function public.audit_center_summary_v600(uuid,timestamptz,timestamptz,uuid) from public,anon;
grant execute on function public.audit_center_summary_v600(uuid,timestamptz,timestamptz,uuid) to authenticated;

create or replace function public.audit_findings_list_v600(
  p_tenant_id uuid,
  p_severity text default null,
  p_status text default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_location_id uuid default null,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_result jsonb;
begin
  if not private.has_permission(p_tenant_id,'audit_center.view') then raise exception 'Permission denied' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.detected_at desc),'[]'::jsonb) into v_result
  from (
    select f.id,f.severity,f.risk_score,f.rule_code,f.title,f.description,f.status,f.detected_at,
      f.entity_type,f.entity_id,f.entity_reference,f.location_id,f.device_id,f.actor_user_id,f.reviewer_id,f.reviewed_at,f.review_note,f.resolution_note,
      e.actor_name,e.device_name,e.device_code,e.source_app,e.root_entity_type,e.root_entity_id
    from public.audit_findings_v600 f
    join public.transaction_story_events_v600 e on e.id=f.source_event_id and e.tenant_id=f.tenant_id
    where f.tenant_id=p_tenant_id
      and (p_severity is null or f.severity=p_severity)
      and (p_status is null or f.status=p_status)
      and (p_from is null or f.detected_at>=p_from)
      and (p_to is null or f.detected_at<=p_to)
      and (p_location_id is null or f.location_id=p_location_id)
    order by f.detected_at desc
    limit greatest(1,least(coalesce(p_limit,200),1000))
  ) q;
  return v_result;
end;
$$;
revoke all on function public.audit_findings_list_v600(uuid,text,text,timestamptz,timestamptz,uuid,integer) from public,anon;
grant execute on function public.audit_findings_list_v600(uuid,text,text,timestamptz,timestamptz,uuid,integer) to authenticated;

create or replace function public.audit_normal_transactions_v600(
  p_tenant_id uuid,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_location_id uuid default null,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_result jsonb;
begin
  if not private.has_permission(p_tenant_id,'audit_center.view') then raise exception 'Permission denied' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.last_event_at desc),'[]'::jsonb) into v_result
  from (
    select distinct on (e.correlation_id)
      e.correlation_id,e.root_entity_type,e.root_entity_id,e.entity_reference,e.event_time as last_event_at,e.action as last_action,
      e.actor_user_id,e.actor_name,e.location_id,e.device_id,e.device_name,e.device_code,e.source_app
    from public.transaction_story_events_v600 e
    where e.tenant_id=p_tenant_id
      and (p_from is null or e.event_time>=p_from)
      and (p_to is null or e.event_time<=p_to)
      and (p_location_id is null or e.location_id=p_location_id)
      and not exists (select 1 from public.audit_findings_v600 f where f.tenant_id=e.tenant_id and f.correlation_id=e.correlation_id and (p_from is null or f.detected_at>=p_from) and (p_to is null or f.detected_at<=p_to))
    order by e.correlation_id,e.event_sequence desc
    limit greatest(1,least(coalesce(p_limit,200),1000))
  ) q;
  return v_result;
end;
$$;
revoke all on function public.audit_normal_transactions_v600(uuid,timestamptz,timestamptz,uuid,integer) from public,anon;
grant execute on function public.audit_normal_transactions_v600(uuid,timestamptz,timestamptz,uuid,integer) to authenticated;

create or replace function public.audit_finding_detail_v600(p_tenant_id uuid,p_finding_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare f public.audit_findings_v600%rowtype; v_sensitive boolean; v_events jsonb;
begin
  if not private.has_permission(p_tenant_id,'audit_center.view') then raise exception 'Permission denied' using errcode='42501'; end if;
  select * into f from public.audit_findings_v600 where tenant_id=p_tenant_id and id=p_finding_id;
  if not found then raise exception 'Audit finding not found'; end if;
  v_sensitive := private.has_permission(p_tenant_id,'audit_history.view_sensitive');
  select coalesce(jsonb_agg(jsonb_build_object(
    'sequence',e.event_sequence,'id',e.id,'action',e.action,'event_time',e.event_time,'entity_type',e.entity_type,'entity_id',e.entity_id,'entity_reference',e.entity_reference,
    'actor',jsonb_build_object('user_id',e.actor_user_id,'name',e.actor_name,'roles',e.actor_role_keys),
    'device',jsonb_build_object('id',e.device_id,'name',e.device_name,'code',e.device_code,'app',e.source_app),'location_id',e.location_id,
    'changed_fields',e.changed_fields,'before',case when v_sensitive then e.before_data else null end,'after',case when v_sensitive then e.after_data else null end,
    'reason',e.reason,'approval',jsonb_build_object('request_id',e.approval_request_id,'approved_by',e.approved_by,'approved_at',e.approved_at,'note',e.approval_note),
    'related_entities',e.related_entities,'event_hash',e.event_hash
  ) order by e.event_sequence),'[]'::jsonb) into v_events
  from public.transaction_story_events_v600 e where e.tenant_id=p_tenant_id and e.correlation_id=f.correlation_id;
  return jsonb_build_object('finding',to_jsonb(f),'sensitive_values_visible',v_sensitive,'transaction_story',v_events);
end;
$$;
revoke all on function public.audit_finding_detail_v600(uuid,uuid) from public,anon;
grant execute on function public.audit_finding_detail_v600(uuid,uuid) to authenticated;

create or replace function public.audit_finding_review_v600(
  p_tenant_id uuid,p_finding_id uuid,p_status text,p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare f public.audit_findings_v600%rowtype; v_resolve boolean;
begin
  if p_status not in ('open','under_review','explained','resolved','escalated','dismissed') then raise exception 'Invalid audit finding status'; end if;
  v_resolve := p_status in ('resolved','escalated','dismissed');
  if v_resolve then
    if not private.has_permission(p_tenant_id,'audit_center.resolve') then raise exception 'Permission denied' using errcode='42501'; end if;
  elsif not private.has_permission(p_tenant_id,'audit_center.review') then
    raise exception 'Permission denied' using errcode='42501';
  end if;
  update public.audit_findings_v600 set
    status=p_status,reviewer_id=auth.uid(),reviewed_at=now(),
    review_note=case when v_resolve then review_note else coalesce(nullif(trim(p_note),''),review_note) end,
    resolution_note=case when v_resolve then coalesce(nullif(trim(p_note),''),resolution_note) else resolution_note end
  where tenant_id=p_tenant_id and id=p_finding_id
  returning * into f;
  if not found then raise exception 'Audit finding not found'; end if;
  return to_jsonb(f);
end;
$$;
revoke all on function public.audit_finding_review_v600(uuid,uuid,text,text) from public,anon;
grant execute on function public.audit_finding_review_v600(uuid,uuid,text,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values (257,'6.0.0-build1','Audit Center + Risk Engine','Adds THQ Audit Center backend with High Risk/Needs Review/Normal classification, configurable tenant thresholds, immutable finding evidence, reviewer lifecycle, normal-transaction feed and full evidence drill-down. Risk classification is secondary and cannot rewrite business/accounting records.')
on conflict (migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;