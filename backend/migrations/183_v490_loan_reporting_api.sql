-- THQ ERP v4.9.0 — Loan reporting, warnings and shared API read model.
begin;

create or replace function public.loan_list_v490(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_status text default null,
  p_query text default '',
  p_limit integer default 500
) returns table(
  loan_id uuid,
  loan_number text,
  client_id uuid,
  client_public_id text,
  client_name text,
  location_id uuid,
  location_name text,
  purpose text,
  principal_amount numeric,
  interest_rate numeric,
  rate_type text,
  rate_index text,
  rate_margin numeric,
  amortization_method text,
  repayment_frequency text,
  repayment_term_count integer,
  repayment_terms text,
  first_payment_date date,
  maturity_date date,
  disbursement_date date,
  status text,
  principal_outstanding numeric,
  interest_outstanding numeric,
  penalty_outstanding numeric,
  total_outstanding numeric,
  total_paid numeric,
  next_due_date date,
  next_due_amount numeric,
  overdue_installments bigint,
  overdue_amount numeric,
  days_to_maturity integer,
  warning_level text,
  warning_message text,
  created_at timestamptz,
  updated_at timestamptz
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
  perform private.loan_v490_access(p_tenant_id,p_location_id,'loans.view','view');
  return query
  select
    l.id,l.loan_number,l.client_id,c.tracking_code,c.name,l.location_id,bl.name,l.purpose,
    l.principal_amount,l.interest_rate,l.rate_type,l.rate_index,l.rate_margin,l.amortization_method,
    l.repayment_frequency,l.repayment_term_count,l.repayment_terms,l.first_payment_date,l.maturity_date,l.disbursement_date,l.status,
    l.principal_outstanding,l.interest_outstanding,l.penalty_outstanding,
    round(l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding,2),l.total_paid,
    nd.due_date,coalesce(nd.due_amount,0),coalesce(ov.cnt,0),coalesce(ov.amount,0),
    (l.maturity_date-current_date)::integer,
    case
      when coalesce(ov.cnt,0)>0 then 'danger'
      when l.status in('active','defaulted') and l.maturity_date between current_date and current_date+l.maturity_warning_days then 'warning'
      when l.status in('active','defaulted') and nd.due_date is not null and nd.due_date<=current_date+l.payment_warning_days then 'warning'
      when l.rate_type='variable' and l.next_rate_review_date is not null and l.next_rate_review_date<=current_date+l.payment_warning_days then 'info'
      when l.status='defaulted' then 'danger'
      else 'normal' end,
    case
      when coalesce(ov.cnt,0)>0 then coalesce(ov.cnt,0)::text||' overdue installment(s)'
      when l.status in('active','defaulted') and l.maturity_date between current_date and current_date+l.maturity_warning_days then 'Matures in '||(l.maturity_date-current_date)::text||' day(s)'
      when l.status in('active','defaulted') and nd.due_date is not null and nd.due_date<=current_date+l.payment_warning_days then 'Payment due '||to_char(nd.due_date,'DD Mon YYYY')
      when l.rate_type='variable' and l.next_rate_review_date is not null and l.next_rate_review_date<=current_date+l.payment_warning_days then 'Variable rate review due '||to_char(l.next_rate_review_date,'DD Mon YYYY')
      when l.status='defaulted' then 'Loan marked defaulted'
      else null end,
    l.created_at,l.updated_at
  from public.loan_accounts_v490 l
  join public.customers c on c.id=l.client_id and c.tenant_id=l.tenant_id
  join public.business_locations bl on bl.id=l.location_id
  left join lateral(
    select s.due_date,
      round(greatest(s.principal_due-s.principal_paid,0)+greatest(s.interest_due-s.interest_paid,0)+greatest(s.penalty_due-s.penalty_paid,0),2) due_amount
    from public.loan_schedule_v490 s
    where s.tenant_id=l.tenant_id and s.loan_id=l.id and s.status<>'waived'
      and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005
    order by s.due_date,s.installment_no limit 1
  ) nd on true
  left join lateral(
    select count(*)::bigint cnt,
      round(coalesce(sum(greatest(s.principal_due-s.principal_paid,0)+greatest(s.interest_due-s.interest_paid,0)+greatest(s.penalty_due-s.penalty_paid,0)),0),2) amount
    from public.loan_schedule_v490 s
    where s.tenant_id=l.tenant_id and s.loan_id=l.id and s.status<>'waived'
      and current_date>s.due_date+l.grace_days
      and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005
  ) ov on true
  where l.tenant_id=p_tenant_id
    and (p_location_id is null or l.location_id=p_location_id)
    and (p_status is null or trim(p_status)='' or l.status=lower(trim(p_status)))
    and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view')
    and (trim(coalesce(p_query,''))='' or lower(concat_ws(' ',l.loan_number,c.name,c.tracking_code,l.external_client_reference,l.purpose,l.status)) like v_q)
  order by case when coalesce(ov.cnt,0)>0 then 0 when l.status in('active','defaulted') then 1 else 2 end,l.updated_at desc
  limit least(greatest(coalesce(p_limit,500),1),2000);
end $$;
grant execute on function public.loan_list_v490(uuid,uuid,text,text,integer) to authenticated;

create or replace function public.loan_detail_v490(p_tenant_id uuid,p_loan_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;v_result jsonb;begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id;
  if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.view','view');
  if v.status in('active','defaulted','closed') then perform private.loan_v490_refresh(p_tenant_id,p_loan_id);end if;
  select jsonb_build_object(
    'loan',to_jsonb(l)||jsonb_build_object(
      'total_outstanding',round(l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding,2),
      'client_name',c.name,'client_public_id',c.tracking_code,'client_phone',c.phone,'client_email',c.email,
      'location_name',bl.name,'location_code',bl.location_code
    ),
    'customer',jsonb_build_object('id',c.id,'public_id',c.tracking_code,'name',c.name,'phone',c.phone,'email',c.email,'tax_number',c.tax_number,'credit_limit',c.credit_limit,'status',c.status),
    'schedule',coalesce((select jsonb_agg(to_jsonb(s) order by s.installment_no) from public.loan_schedule_v490 s where s.tenant_id=p_tenant_id and s.loan_id=l.id),'[]'::jsonb),
    'payments',coalesce((select jsonb_agg(to_jsonb(p) order by p.payment_date desc,p.created_at desc) from public.loan_payments_v490 p where p.tenant_id=p_tenant_id and p.loan_id=l.id),'[]'::jsonb),
    'rate_history',coalesce((select jsonb_agg(to_jsonb(r) order by r.effective_date desc,r.changed_at desc) from public.loan_rate_history_v490 r where r.tenant_id=p_tenant_id and r.loan_id=l.id),'[]'::jsonb),
    'collateral',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.loan_collateral_v490 x where x.tenant_id=p_tenant_id and x.loan_id=l.id),'[]'::jsonb),
    'guarantors',coalesce((select jsonb_agg(to_jsonb(g) order by g.created_at) from public.loan_guarantors_v490 g where g.tenant_id=p_tenant_id and g.loan_id=l.id),'[]'::jsonb),
    'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.event_date desc) from public.loan_events_v490 e where e.tenant_id=p_tenant_id and e.loan_id=l.id),'[]'::jsonb)
  ) into v_result
  from public.loan_accounts_v490 l
  join public.customers c on c.id=l.client_id
  join public.business_locations bl on bl.id=l.location_id
  where l.tenant_id=p_tenant_id and l.id=p_loan_id;
  return v_result;
end $$;
grant execute on function public.loan_detail_v490(uuid,uuid) to authenticated;

create or replace function public.loan_dashboard_v490(p_tenant_id uuid,p_location_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_result jsonb;begin
  perform private.loan_v490_access(p_tenant_id,p_location_id,'loans.view','view');
  with scoped as(
    select l.* from public.loan_accounts_v490 l
    where l.tenant_id=p_tenant_id
      and (p_location_id is null or l.location_id=p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view')
  ), overdue as(
    select count(*)::bigint installments,
      count(distinct l.id)::bigint loans,
      round(coalesce(sum(greatest(s.principal_due-s.principal_paid,0)+greatest(s.interest_due-s.interest_paid,0)+greatest(s.penalty_due-s.penalty_paid,0)),0),2) amount
    from scoped l join public.loan_schedule_v490 s on s.loan_id=l.id and s.tenant_id=l.tenant_id
    where l.status in('active','defaulted') and s.status<>'waived'
      and current_date>s.due_date+l.grace_days
      and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005
  ), due7 as(
    select count(*)::bigint installments,
      round(coalesce(sum(greatest(s.principal_due-s.principal_paid,0)+greatest(s.interest_due-s.interest_paid,0)+greatest(s.penalty_due-s.penalty_paid,0)),0),2) amount
    from scoped l join public.loan_schedule_v490 s on s.loan_id=l.id and s.tenant_id=l.tenant_id
    where l.status in('active','defaulted') and s.status<>'waived' and s.due_date between current_date and current_date+7
      and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005
  ), collected as(
    select round(coalesce(sum(p.amount),0),2) amount
    from public.loan_payments_v490 p join scoped l on l.id=p.loan_id
    where p.status='posted' and p.payment_date=current_date
  )
  select jsonb_build_object(
    'total_loans',count(*),
    'draft',count(*) filter(where s.status='draft'),
    'submitted',count(*) filter(where s.status='submitted'),
    'approved',count(*) filter(where s.status='approved'),
    'active',count(*) filter(where s.status='active'),
    'defaulted',count(*) filter(where s.status='defaulted'),
    'closed',count(*) filter(where s.status='closed'),
    'active_principal',round(coalesce(sum(s.principal_outstanding) filter(where s.status in('active','defaulted')),0),2),
    'outstanding_interest',round(coalesce(sum(s.interest_outstanding) filter(where s.status in('active','defaulted')),0),2),
    'outstanding_penalty',round(coalesce(sum(s.penalty_outstanding) filter(where s.status in('active','defaulted')),0),2),
    'total_outstanding',round(coalesce(sum(s.principal_outstanding+s.interest_outstanding+s.penalty_outstanding) filter(where s.status in('active','defaulted')),0),2),
    'overdue_loans',(select loans from overdue),'overdue_installments',(select installments from overdue),'overdue_amount',(select amount from overdue),
    'due_next_7_days',(select installments from due7),'due_next_7_days_amount',(select amount from due7),
    'maturing_next_30_days',count(*) filter(where s.status in('active','defaulted') and s.maturity_date between current_date and current_date+30),
    'variable_rate_reviews',count(*) filter(where s.status in('approved','active','defaulted') and s.rate_type='variable' and s.next_rate_review_date between current_date and current_date+30),
    'collections_today',(select amount from collected)
  ) into v_result from scoped s;
  return coalesce(v_result,'{}'::jsonb);
end $$;
grant execute on function public.loan_dashboard_v490(uuid,uuid) to authenticated;

create or replace function public.loan_warnings_v490(
  p_tenant_id uuid,p_location_id uuid default null,p_limit integer default 250
) returns table(
  warning_type text,severity text,loan_id uuid,loan_number text,client_id uuid,client_name text,location_id uuid,
  event_date date,amount numeric,days_until integer,message text
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin
  perform private.loan_v490_access(p_tenant_id,p_location_id,'loans.view','view');
  return query
  with scoped as(
    select l.*,c.name client_name
    from public.loan_accounts_v490 l join public.customers c on c.id=l.client_id
    where l.tenant_id=p_tenant_id and l.status in('approved','active','defaulted')
      and (p_location_id is null or l.location_id=p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view')
  ), warnings as(
    select 'overdue_payment'::text,'danger'::text,l.id,l.loan_number,l.client_id,l.client_name,l.location_id,s.due_date,
      round(greatest(s.principal_due-s.principal_paid,0)+greatest(s.interest_due-s.interest_paid,0)+greatest(s.penalty_due-s.penalty_paid,0),2),
      (s.due_date-current_date)::integer,
      'Installment #'||s.installment_no::text||' overdue by '||(current_date-s.due_date)::text||' day(s)'::text
    from scoped l join public.loan_schedule_v490 s on s.loan_id=l.id and s.tenant_id=l.tenant_id
    where l.status in('active','defaulted') and s.status<>'waived' and current_date>s.due_date+l.grace_days
      and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005
    union all
    select 'payment_due'::text,'warning'::text,l.id,l.loan_number,l.client_id,l.client_name,l.location_id,s.due_date,
      round(greatest(s.principal_due-s.principal_paid,0)+greatest(s.interest_due-s.interest_paid,0)+greatest(s.penalty_due-s.penalty_paid,0),2),
      (s.due_date-current_date)::integer,
      'Installment #'||s.installment_no::text||' due in '||greatest(s.due_date-current_date,0)::text||' day(s)'::text
    from scoped l join public.loan_schedule_v490 s on s.loan_id=l.id and s.tenant_id=l.tenant_id
    where l.status in('active','defaulted') and s.status<>'waived'
      and s.due_date between current_date and current_date+l.payment_warning_days
      and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005
    union all
    select 'maturity'::text,'warning'::text,l.id,l.loan_number,l.client_id,l.client_name,l.location_id,l.maturity_date,
      round(l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding,2),(l.maturity_date-current_date)::integer,
      'Loan matures in '||greatest(l.maturity_date-current_date,0)::text||' day(s)'::text
    from scoped l where l.status in('active','defaulted') and l.maturity_date between current_date and current_date+l.maturity_warning_days
    union all
    select 'rate_review'::text,'info'::text,l.id,l.loan_number,l.client_id,l.client_name,l.location_id,l.next_rate_review_date,
      null::numeric,(l.next_rate_review_date-current_date)::integer,
      'Variable interest rate review due in '||greatest(l.next_rate_review_date-current_date,0)::text||' day(s)'::text
    from scoped l where l.rate_type='variable' and l.next_rate_review_date is not null
      and l.next_rate_review_date between current_date and current_date+greatest(l.payment_warning_days,7)
  )
  select w.* from warnings w
  order by case w.severity when 'danger' then 0 when 'warning' then 1 else 2 end,w.event_date,w.loan_number
  limit least(greatest(coalesce(p_limit,250),1),2000);
end $$;
grant execute on function public.loan_warnings_v490(uuid,uuid,integer) to authenticated;

create or replace function public.customer_loan_summary_v490(p_tenant_id uuid,p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_customer jsonb;v_summary jsonb;begin
  perform private.loan_v490_access(p_tenant_id,null,'loans.view','view');
  select jsonb_build_object('id',c.id,'public_id',c.tracking_code,'name',c.name,'phone',c.phone,'email',c.email)
  into v_customer from public.customers c where c.tenant_id=p_tenant_id and c.id=p_customer_id;
  if v_customer is null then raise exception 'Customer/client not found';end if;
  with scoped as(
    select l.* from public.loan_accounts_v490 l where l.tenant_id=p_tenant_id and l.client_id=p_customer_id
      and private.erp_document_scope_allowed(p_tenant_id,l.location_id,null,'view')
  ) select jsonb_build_object(
    'customer',v_customer,
    'loan_count',count(*),
    'active_count',count(*) filter(where status in('active','defaulted')),
    'principal_outstanding',round(coalesce(sum(principal_outstanding) filter(where status in('active','defaulted')),0),2),
    'interest_outstanding',round(coalesce(sum(interest_outstanding) filter(where status in('active','defaulted')),0),2),
    'penalty_outstanding',round(coalesce(sum(penalty_outstanding) filter(where status in('active','defaulted')),0),2),
    'total_outstanding',round(coalesce(sum(principal_outstanding+interest_outstanding+penalty_outstanding) filter(where status in('active','defaulted')),0),2),
    'loans',coalesce(jsonb_agg(jsonb_build_object(
      'loan_id',id,'loan_number',loan_number,'status',status,'principal_amount',principal_amount,'principal_outstanding',principal_outstanding,
      'interest_outstanding',interest_outstanding,'penalty_outstanding',penalty_outstanding,'rate_type',rate_type,'interest_rate',interest_rate,
      'repayment_frequency',repayment_frequency,'maturity_date',maturity_date,'location_id',location_id
    ) order by updated_at desc),'[]'::jsonb)
  ) into v_summary from scoped;
  return coalesce(v_summary,jsonb_build_object('customer',v_customer,'loan_count',0,'active_count',0,'principal_outstanding',0,'interest_outstanding',0,'penalty_outstanding',0,'total_outstanding',0,'loans','[]'::jsonb));
end $$;
grant execute on function public.customer_loan_summary_v490(uuid,uuid) to authenticated;

-- Feed loan risk into the existing THQ notification center without changing
-- the generic notification table or requiring a separate alert subsystem.
create or replace function private.loan_v490_refresh_notifications(p_tenant_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare r record;begin
  if p_user_id is null or p_user_id<>auth.uid() then return;end if;
  if not exists(select 1 from public.tenant_modules where tenant_id=p_tenant_id and module_key='loans' and enabled) then return;end if;
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'loans.view')
     and not private.erp_has_permission(p_tenant_id,'loans.manage') then return;end if;

  for r in select * from public.loan_warnings_v490(p_tenant_id,null,100) loop
    if not exists(
      select 1 from public.notifications n
      where n.tenant_id=p_tenant_id and n.user_id=p_user_id and n.category='loan'
        and n.entity_type='loan' and n.entity_id=r.loan_id and n.read_at is null
        and n.title=('Loan '||replace(r.warning_type,'_',' '))
        and n.created_at>now()-interval '12 hours'
    ) then
      insert into public.notifications(tenant_id,user_id,location_id,category,severity,title,message,entity_type,entity_id)
      values(
        p_tenant_id,p_user_id,r.location_id,'loan',
        case r.severity when 'danger' then 'critical' when 'warning' then 'warning' else 'info' end,
        'Loan '||replace(r.warning_type,'_',' '),
        r.loan_number||' • '||r.client_name||' • '||r.message,
        'loan',r.loan_id
      );
    end if;
  end loop;
end $$;
revoke all on function private.loan_v490_refresh_notifications(uuid,uuid) from public;

create or replace function public.notifications_list_v4(p_tenant_id uuid,p_limit integer default 50)
returns setof public.notifications language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  perform private.v4_refresh_notifications(p_tenant_id,auth.uid());
  perform private.loan_v490_refresh_notifications(p_tenant_id,auth.uid());
  return query select * from public.notifications
    where tenant_id=p_tenant_id and (user_id is null or user_id=auth.uid())
    order by created_at desc limit greatest(1,least(coalesce(p_limit,50),200));
end $$;
grant execute on function public.notifications_list_v4(uuid,integer) to authenticated;

-- Extend the existing cross-module attention summary with loan exposure/risk.
-- Users without loan visibility simply receive zeroed loan metrics.
create or replace function public.business_attention_summary_v480(p_tenant_id uuid,p_location_id uuid default null,p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v_low bigint:=0;v_out bigint:=0;v_dead bigint:=0;v_stock numeric:=0;v_recv numeric:=0;v_pay numeric:=0;v_overdue numeric:=0;
  v_pipeline jsonb;v_loans jsonb:='{}'::jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select count(*) filter(where status='low_stock'),count(*) filter(where status='out_of_stock'),count(*) filter(where status='dead_stock'),coalesce(sum(stock_value),0)
    into v_low,v_out,v_dead,v_stock from public.inventory_intelligence_v480(p_tenant_id,p_location_id,p_days,'',5000);
  select coalesce(sum(total_outstanding),0),coalesce(sum(days_1_30+days_31_60+days_61_90+days_90_plus),0)
    into v_recv,v_overdue from public.customer_credit_intelligence_v480(p_tenant_id,p_location_id,'',5000);
  select coalesce(sum(total_outstanding),0) into v_pay from public.supplier_payables_intelligence_v480(p_tenant_id,p_location_id,'',5000);
  v_pipeline:=public.operations_pipeline_v489(p_tenant_id,p_location_id);
  if exists(select 1 from public.tenant_modules where tenant_id=p_tenant_id and module_key='loans' and enabled)
     and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'loans.view') or private.erp_has_permission(p_tenant_id,'loans.manage')) then
    v_loans:=public.loan_dashboard_v490(p_tenant_id,p_location_id);
  end if;
  return jsonb_build_object(
    'low_stock',v_low,'out_of_stock',v_out,'dead_stock',v_dead,'inventory_value',round(v_stock,2),
    'receivables',round(v_recv,2),'overdue_receivables',round(v_overdue,2),'payables',round(v_pay,2),'days',greatest(1,least(coalesce(p_days,30),365)),
    'loan_total_outstanding',coalesce((v_loans->>'total_outstanding')::numeric,0),
    'loan_overdue_amount',coalesce((v_loans->>'overdue_amount')::numeric,0),
    'loan_overdue_count',coalesce((v_loans->>'overdue_loans')::bigint,0),
    'loan_due_next_7_days',coalesce((v_loans->>'due_next_7_days')::bigint,0),
    'loan_maturing_next_30_days',coalesce((v_loans->>'maturing_next_30_days')::bigint,0),
    'loan_variable_rate_reviews',coalesce((v_loans->>'variable_rate_reviews')::bigint,0)
  )||v_pipeline;
end $$;
grant execute on function public.business_attention_summary_v480(uuid,uuid,integer) to authenticated;


-- Keep Loans searchable from the existing THQ global search without exposing
-- loan values to users who do not have loan visibility.
create or replace function public.global_search_v4(p_tenant_id uuid,p_query text,p_limit integer default 60)
returns table(entity_type text,entity_id uuid,public_id text,title text,subtitle text,module_key text,location_id uuid)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';lim integer:=greatest(5,least(coalesce(p_limit,60),150));begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;if trim(coalesce(p_query,''))='' then return;end if;
  return query select * from (
    select 'product'::text,pv.id,coalesce(p.tracking_code,pv.sku),p.name,concat_ws(' • ','SKU '||pv.sku,nullif(pv.part_number,''),nullif(pv.barcode,'')),'inventory'::text,null::uuid from public.products p join public.product_variants pv on pv.product_id=p.id and pv.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and (lower(p.name) like q or lower(pv.sku) like q or lower(coalesce(pv.barcode,'')) like q or lower(coalesce(pv.part_number,'')) like q or lower(coalesce(p.tracking_code,'')) like q)
    union all select 'customer',c.id,c.tracking_code,c.name,concat_ws(' • ',c.phone,c.email,c.tax_number),'customers',null::uuid from public.customers c where c.tenant_id=p_tenant_id and (lower(c.name) like q or lower(coalesce(c.phone,'')) like q or lower(coalesce(c.email,'')) like q or lower(coalesce(c.tracking_code,'')) like q)
    union all select 'supplier',s.id,s.tracking_code,s.name,concat_ws(' • ',s.phone,s.email,s.tax_number),'suppliers',null::uuid from public.suppliers s where s.tenant_id=p_tenant_id and (lower(s.name) like q or lower(coalesce(s.phone,'')) like q or lower(coalesce(s.email,'')) like q or lower(coalesce(s.tracking_code,'')) like q)
    union all select 'sale',s.id,s.tracking_code,coalesce(dn.terminal_number,ln.local_number,s.sale_number),c.name||' • '||s.grand_total::text,'sales',o.location_id from public.sales s join public.customers c on c.id=s.customer_id left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id left join public.location_document_numbers ln on ln.entity_type='sale' and ln.entity_id=s.id left join public.device_document_numbers dn on dn.entity_type='sale' and dn.entity_id=s.id where s.tenant_id=p_tenant_id and private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view') and (lower(s.sale_number) like q or lower(coalesce(dn.terminal_number,'')) like q or lower(c.name) like q or lower(coalesce(s.tracking_code,'')) like q)
    union all select 'purchase',p.id,p.tracking_code,coalesce(dn.terminal_number,ln.local_number,p.purchase_number),s.name||' • '||p.grand_total::text,'purchases',o.location_id from public.purchases p join public.suppliers s on s.id=p.supplier_id left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id left join public.location_document_numbers ln on ln.entity_type='purchase' and ln.entity_id=p.id left join public.device_document_numbers dn on dn.entity_type='purchase' and dn.entity_id=p.id where p.tenant_id=p_tenant_id and private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view') and (lower(p.purchase_number) like q or lower(coalesce(dn.terminal_number,'')) like q or lower(s.name) like q or lower(coalesce(p.tracking_code,'')) like q)
    union all select 'loan',l.id,l.loan_number,l.loan_number,c.name||' • '||l.status||' • outstanding '||round(l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding,2)::text,'loans',l.location_id from public.loan_accounts_v490 l join public.customers c on c.id=l.client_id where l.tenant_id=p_tenant_id and exists(select 1 from public.tenant_modules tm where tm.tenant_id=p_tenant_id and tm.module_key='loans' and tm.enabled) and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'loans.view') or private.erp_has_permission(p_tenant_id,'loans.manage')) and private.erp_document_scope_allowed(p_tenant_id,l.location_id,null,'view') and (lower(l.loan_number) like q or lower(c.name) like q or lower(coalesce(c.tracking_code,'')) like q or lower(coalesce(l.external_client_reference,'')) like q or lower(coalesce(l.purpose,'')) like q)
    union all select 'account',a.id,a.code,a.name,a.account_type,'accounting',null::uuid from public.accounting_accounts a where a.tenant_id=p_tenant_id and active and (lower(a.code) like q or lower(a.name) like q)
    union all select 'stock_transfer',t.id,t.transfer_number,t.transfer_number,fl.location_code||' → '||tl.location_code||' • '||t.status,'stock_transfers',t.from_location_id from public.stock_transfers t join public.business_locations fl on fl.id=t.from_location_id join public.business_locations tl on tl.id=t.to_location_id where t.tenant_id=p_tenant_id and lower(t.transfer_number) like q
    union all select 'task',t.id,null,t.title,coalesce(t.status,'')||' • '||coalesce(t.description,''),'tasks',t.location_id from public.business_tasks t where t.tenant_id=p_tenant_id and (lower(t.title) like q or lower(coalesce(t.description,'')) like q)
    union all select 'workshop_job',j.id,j.job_number,j.job_number,coalesce(v.vehicle_number,'')||' • '||j.status,'workshop',j.location_id from public.workshop_job_cards j join public.workshop_vehicles v on v.id=j.vehicle_id where j.tenant_id=p_tenant_id and (lower(j.job_number) like q or lower(v.vehicle_number) like q)
  )z limit lim;
end $$;
grant execute on function public.global_search_v4(uuid,text,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(183,'4.9.0','Loans & Credit','Shared Client/POS loan list/detail/dashboard, proactive overdue/payment/maturity/rate warnings and customer loan summary API read models.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 migration 183 loan reporting API applied' as status;
