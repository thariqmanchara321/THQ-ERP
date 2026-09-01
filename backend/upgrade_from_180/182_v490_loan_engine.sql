-- THQ ERP v4.9.0 — Loan lifecycle, schedule, collection and accounting engine.
begin;

create or replace function private.loan_v490_access(
  p_tenant_id uuid,
  p_location_id uuid,
  p_permission text default 'loans.view',
  p_location_level text default 'view'
) returns void
language plpgsql stable security definer
set search_path=public,private,pg_temp
as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not exists(select 1 from public.tenant_modules where tenant_id=p_tenant_id and module_key='loans' and enabled) then
    raise exception 'Loans module is disabled';
  end if;
  if p_location_id is not null then perform private.v4_location_access(p_tenant_id,p_location_id,p_location_level);end if;
  if private.erp_user_is_owner(p_tenant_id) then return;end if;
  if not private.erp_has_permission(p_tenant_id,p_permission) and not private.erp_has_permission(p_tenant_id,'loans.manage') then
    raise exception 'Loan permission required: %',p_permission;
  end if;
end $$;
revoke all on function private.loan_v490_access(uuid,uuid,text,text) from public;

create or replace function private.loan_v490_periods_per_year(p_frequency text)
returns numeric language sql immutable as $$
  select case lower(coalesce(p_frequency,'monthly'))
    when 'weekly' then 52::numeric
    when 'biweekly' then 26::numeric
    when 'monthly' then 12::numeric
    when 'quarterly' then 4::numeric
    when 'half_yearly' then 2::numeric
    when 'yearly' then 1::numeric
    else 12::numeric end
$$;
revoke all on function private.loan_v490_periods_per_year(text) from public;

create or replace function private.loan_v490_due_date(p_first date,p_frequency text,p_offset integer)
returns date language plpgsql immutable as $$ begin
  return case lower(coalesce(p_frequency,'monthly'))
    when 'weekly' then p_first+(greatest(p_offset,0)*7)
    when 'biweekly' then p_first+(greatest(p_offset,0)*14)
    when 'monthly' then (p_first+make_interval(months=>greatest(p_offset,0)))::date
    when 'quarterly' then (p_first+make_interval(months=>greatest(p_offset,0)*3))::date
    when 'half_yearly' then (p_first+make_interval(months=>greatest(p_offset,0)*6))::date
    when 'yearly' then (p_first+make_interval(years=>greatest(p_offset,0)))::date
    else (p_first+make_interval(months=>greatest(p_offset,0)))::date end;
end $$;
revoke all on function private.loan_v490_due_date(date,text,integer) from public;

create or replace function private.loan_v490_event(
  p_tenant_id uuid,p_loan_id uuid,p_type text,p_message text default null,p_metadata jsonb default '{}'::jsonb
) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
  insert into public.loan_events_v490(tenant_id,loan_id,event_type,message,metadata,created_by)
  values(p_tenant_id,p_loan_id,trim(p_type),nullif(trim(coalesce(p_message,'')),''),coalesce(p_metadata,'{}'::jsonb),auth.uid());
end $$;
revoke all on function private.loan_v490_event(uuid,uuid,text,text,jsonb) from public;

create or replace function private.loan_v490_refresh(p_tenant_id uuid,p_loan_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v public.loan_accounts_v490%rowtype;
  v_principal numeric:=0;v_interest numeric:=0;v_penalty numeric:=0;v_paid numeric:=0;
begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;
  if not found then raise exception 'Loan not found';end if;

  if v.status in('active','defaulted','closed') then
    update public.loan_schedule_v490 s
    set penalty_due=case
          when current_date>s.due_date+v.grace_days and s.status not in('paid','waived') and v.penalty_rate>0
            then round((s.principal_due+s.interest_due)*v.penalty_rate/100.0/365.0*
                 greatest(current_date-(s.due_date+v.grace_days),0),2)
          else greatest(s.penalty_due,0) end,
        updated_at=now()
    where s.tenant_id=p_tenant_id and s.loan_id=p_loan_id;

    update public.loan_schedule_v490 s
    set status=case
          when s.status='waived' then 'waived'
          when (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)<=0.005 then 'paid'
          when (s.principal_paid+s.interest_paid+s.penalty_paid)>0.005 then
            case when current_date>s.due_date+v.grace_days then 'overdue' else 'partial' end
          when current_date>s.due_date+v.grace_days then 'overdue'
          when current_date>=s.due_date then 'due'
          else 'pending' end,
        paid_at=case
          when (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)<=0.005
            then coalesce(s.paid_at,now()) else null end,
        updated_at=now()
    where s.tenant_id=p_tenant_id and s.loan_id=p_loan_id;
  end if;

  select
    coalesce(sum(greatest(principal_due-principal_paid,0)),0),
    coalesce(sum(greatest(interest_due-interest_paid,0)),0),
    coalesce(sum(greatest(penalty_due-penalty_paid,0)),0)
  into v_principal,v_interest,v_penalty
  from public.loan_schedule_v490 where tenant_id=p_tenant_id and loan_id=p_loan_id and status<>'waived';

  select coalesce(sum(amount),0) into v_paid
  from public.loan_payments_v490 where tenant_id=p_tenant_id and loan_id=p_loan_id and status='posted';

  update public.loan_accounts_v490
  set principal_outstanding=round(v_principal,2),interest_outstanding=round(v_interest,2),penalty_outstanding=round(v_penalty,2),
      total_paid=round(v_paid,2),
      status=case
        when status in('active','defaulted') and v_principal+v_interest+v_penalty<=0.005 then 'closed'
        else status end,
      closed_at=case when status in('active','defaulted') and v_principal+v_interest+v_penalty<=0.005 then coalesce(closed_at,now()) else closed_at end,
      updated_at=now()
  where tenant_id=p_tenant_id and id=p_loan_id;
end $$;
revoke all on function private.loan_v490_refresh(uuid,uuid) from public;

create or replace function public.loan_create_v490(p_tenant_id uuid,p_location_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v_id uuid:=gen_random_uuid();v_no text;v_client uuid;v_principal numeric;v_rate numeric;v_rate_type text;
  v_freq text;v_terms integer;v_first date;v_maturity date;v_amort text;v_penalty numeric;
begin
  perform private.loan_v490_access(p_tenant_id,p_location_id,'loans.create','operate');
  v_client:=nullif(p_payload->>'client_id','')::uuid;
  if v_client is null or not exists(select 1 from public.customers where id=v_client and tenant_id=p_tenant_id and coalesce(status,'active')='active' and not coalesce(is_walk_in,false)) then raise exception 'An active non-walk-in client/customer is required';end if;
  v_principal:=coalesce(nullif(p_payload->>'principal_amount','')::numeric,0);if v_principal<=0 then raise exception 'Principal amount must be positive';end if;
  v_rate:=coalesce(nullif(p_payload->>'interest_rate','')::numeric,0);if v_rate<0 or v_rate>1000 then raise exception 'Invalid interest rate';end if;
  v_rate_type:=lower(coalesce(nullif(p_payload->>'rate_type',''),'fixed'));if v_rate_type not in('fixed','variable') then raise exception 'Rate type must be fixed or variable';end if;
  v_freq:=lower(coalesce(nullif(p_payload->>'repayment_frequency',''),'monthly'));
  if v_freq not in('weekly','biweekly','monthly','quarterly','half_yearly','yearly') then raise exception 'Invalid repayment frequency';end if;
  v_terms:=coalesce(nullif(p_payload->>'repayment_term_count','')::integer,0);if v_terms<=0 or v_terms>1200 then raise exception 'Invalid repayment term count';end if;
  v_first:=nullif(p_payload->>'first_payment_date','')::date;if v_first is null then raise exception 'First payment date is required';end if;
  v_maturity:=coalesce(nullif(p_payload->>'maturity_date','')::date,private.loan_v490_due_date(v_first,v_freq,v_terms-1));
  if v_maturity<v_first then raise exception 'Maturity date cannot be before first payment date';end if;
  if v_terms>1 and v_maturity<private.loan_v490_due_date(v_first,v_freq,v_terms-2) then raise exception 'Maturity date is too early for the selected repayment terms';end if;
  v_amort:=lower(coalesce(nullif(p_payload->>'amortization_method',''),'reducing_balance'));
  if v_amort not in('reducing_balance','flat') then raise exception 'Invalid amortization method';end if;
  v_penalty:=coalesce(nullif(p_payload->>'penalty_rate','')::numeric,0);if v_penalty<0 or v_penalty>1000 then raise exception 'Invalid penalty rate';end if;
  if v_rate_type='variable' and nullif(trim(coalesce(p_payload->>'rate_index','')),'') is null then raise exception 'Variable-rate loans require a rate index';end if;

  v_no:='LOAN-'||lpad(nextval('public.loan_number_seq_v490')::text,8,'0');
  insert into public.loan_accounts_v490(
    id,tenant_id,location_id,loan_number,client_id,external_client_reference,purpose,principal_amount,interest_rate,rate_type,
    rate_index,rate_margin,rate_reset_frequency,next_rate_review_date,amortization_method,repayment_frequency,repayment_term_count,
    repayment_terms,first_payment_date,maturity_date,payment_warning_days,maturity_warning_days,grace_days,penalty_rate,
    collateral_summary,notes,status,created_by,updated_by
  ) values(
    v_id,p_tenant_id,p_location_id,v_no,v_client,nullif(trim(coalesce(p_payload->>'external_client_reference','')),''),
    nullif(trim(coalesce(p_payload->>'purpose','')),''),v_principal,v_rate,v_rate_type,
    nullif(trim(coalesce(p_payload->>'rate_index','')),''),coalesce(nullif(p_payload->>'rate_margin','')::numeric,0),
    nullif(lower(trim(coalesce(p_payload->>'rate_reset_frequency',''))),''),nullif(p_payload->>'next_rate_review_date','')::date,
    v_amort,v_freq,v_terms,nullif(trim(coalesce(p_payload->>'repayment_terms','')),''),v_first,v_maturity,
    coalesce(nullif(p_payload->>'payment_warning_days','')::integer,5),coalesce(nullif(p_payload->>'maturity_warning_days','')::integer,30),
    coalesce(nullif(p_payload->>'grace_days','')::integer,0),v_penalty,
    nullif(trim(coalesce(p_payload->>'collateral_summary','')),''),nullif(trim(coalesce(p_payload->>'notes','')),''),'draft',auth.uid(),auth.uid()
  );
  perform private.loan_v490_event(p_tenant_id,v_id,'created','Loan created',jsonb_build_object('principal_amount',v_principal,'rate_type',v_rate_type,'interest_rate',v_rate));
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan',v_id::text,'create');
  return jsonb_build_object('success',true,'loan_id',v_id,'loan_number',v_no,'status','draft');
end $$;
grant execute on function public.loan_create_v490(uuid,uuid,jsonb) to authenticated;

create or replace function public.loan_update_v490(p_tenant_id uuid,p_loan_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;v_client uuid;v_first date;v_mat date;begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.create','operate');
  if v.status not in('draft','rejected') then raise exception 'Only Draft/Rejected loans can be edited';end if;
  v_client:=coalesce(nullif(p_payload->>'client_id','')::uuid,v.client_id);
  if not exists(select 1 from public.customers where id=v_client and tenant_id=p_tenant_id and coalesce(status,'active')='active' and not coalesce(is_walk_in,false)) then raise exception 'Client/customer must be active and not walk-in';end if;
  v_first:=coalesce(nullif(p_payload->>'first_payment_date','')::date,v.first_payment_date);
  v_mat:=coalesce(nullif(p_payload->>'maturity_date','')::date,v.maturity_date);if v_mat<v_first then raise exception 'Maturity date cannot be before first payment date';end if;
  update public.loan_accounts_v490 set
    client_id=v_client,
    external_client_reference=coalesce(nullif(trim(p_payload->>'external_client_reference'),''),external_client_reference),
    purpose=coalesce(nullif(trim(p_payload->>'purpose'),''),purpose),
    principal_amount=coalesce(nullif(p_payload->>'principal_amount','')::numeric,principal_amount),
    interest_rate=coalesce(nullif(p_payload->>'interest_rate','')::numeric,interest_rate),
    rate_type=coalesce(nullif(lower(p_payload->>'rate_type'),''),rate_type),
    rate_index=coalesce(nullif(trim(p_payload->>'rate_index'),''),rate_index),
    rate_margin=coalesce(nullif(p_payload->>'rate_margin','')::numeric,rate_margin),
    rate_reset_frequency=coalesce(nullif(lower(p_payload->>'rate_reset_frequency'),''),rate_reset_frequency),
    next_rate_review_date=coalesce(nullif(p_payload->>'next_rate_review_date','')::date,next_rate_review_date),
    amortization_method=coalesce(nullif(lower(p_payload->>'amortization_method'),''),amortization_method),
    repayment_frequency=coalesce(nullif(lower(p_payload->>'repayment_frequency'),''),repayment_frequency),
    repayment_term_count=coalesce(nullif(p_payload->>'repayment_term_count','')::integer,repayment_term_count),
    repayment_terms=coalesce(nullif(trim(p_payload->>'repayment_terms'),''),repayment_terms),
    first_payment_date=v_first,maturity_date=v_mat,
    payment_warning_days=coalesce(nullif(p_payload->>'payment_warning_days','')::integer,payment_warning_days),
    maturity_warning_days=coalesce(nullif(p_payload->>'maturity_warning_days','')::integer,maturity_warning_days),
    grace_days=coalesce(nullif(p_payload->>'grace_days','')::integer,grace_days),
    penalty_rate=coalesce(nullif(p_payload->>'penalty_rate','')::numeric,penalty_rate),
    collateral_summary=coalesce(nullif(trim(p_payload->>'collateral_summary'),''),collateral_summary),
    notes=coalesce(nullif(trim(p_payload->>'notes'),''),notes),
    status='draft',rejection_reason=null,rejected_by=null,rejected_at=null,updated_by=auth.uid(),updated_at=now()
  where tenant_id=p_tenant_id and id=p_loan_id;
  if exists(
    select 1 from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id
      and rate_type='variable' and nullif(trim(coalesce(rate_index,'')),'') is null
  ) then raise exception 'Variable-rate loans require a rate index';end if;
  if exists(
    select 1 from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id
      and repayment_term_count>1
      and maturity_date<private.loan_v490_due_date(first_payment_date,repayment_frequency,repayment_term_count-2)
  ) then raise exception 'Maturity date is too early for the selected repayment terms';end if;
  perform private.loan_v490_event(p_tenant_id,p_loan_id,'updated','Loan details updated');
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan',p_loan_id::text,'update');
  return jsonb_build_object('success',true,'loan_id',p_loan_id,'status','draft');
end $$;
grant execute on function public.loan_update_v490(uuid,uuid,jsonb) to authenticated;

create or replace function public.loan_submit_v490(p_tenant_id uuid,p_loan_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.create','operate');
  if v.status<>'draft' then raise exception 'Only Draft loans can be submitted';end if;
  update public.loan_accounts_v490 set status='submitted',updated_by=auth.uid(),updated_at=now() where id=p_loan_id;
  perform private.loan_v490_event(p_tenant_id,p_loan_id,'submitted','Loan submitted for approval');
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan',p_loan_id::text,'submit');
  return jsonb_build_object('success',true,'loan_id',p_loan_id,'status','submitted');
end $$;
grant execute on function public.loan_submit_v490(uuid,uuid) to authenticated;

create or replace function public.loan_decide_v490(p_tenant_id uuid,p_loan_id uuid,p_approve boolean,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.approve','manage');
  if v.status<>'submitted' then raise exception 'Only Submitted loans can be approved/rejected';end if;
  if coalesce(p_approve,false) then
    update public.loan_accounts_v490 set status='approved',approved_by=auth.uid(),approved_at=now(),rejection_reason=null,rejected_by=null,rejected_at=null,updated_by=auth.uid(),updated_at=now() where id=p_loan_id;
    perform private.loan_v490_event(p_tenant_id,p_loan_id,'approved',coalesce(nullif(trim(p_note),''),'Loan approved'));
  else
    if nullif(trim(coalesce(p_note,'')),'') is null then raise exception 'Rejection reason is required';end if;
    update public.loan_accounts_v490 set status='rejected',rejected_by=auth.uid(),rejected_at=now(),rejection_reason=trim(p_note),updated_by=auth.uid(),updated_at=now() where id=p_loan_id;
    perform private.loan_v490_event(p_tenant_id,p_loan_id,'rejected',trim(p_note));
  end if;
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan',p_loan_id::text,case when p_approve then 'approve' else 'reject' end);
  return jsonb_build_object('success',true,'loan_id',p_loan_id,'status',case when p_approve then 'approved' else 'rejected' end);
end $$;
grant execute on function public.loan_decide_v490(uuid,uuid,boolean,text) to authenticated;

create or replace function public.loan_disburse_v490(
  p_tenant_id uuid,p_loan_id uuid,p_disbursement_date date default current_date,p_payment_method text default 'bank',
  p_reference_number text default null,p_device_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v public.loan_accounts_v490%rowtype;v_ppy numeric;v_period_rate numeric;v_installment numeric;v_flat_interest numeric;
  v_balance numeric;v_interest numeric;v_principal numeric;v_due date;v_i integer;v_lines jsonb;v_shift uuid;
begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.disburse','manage');
  if p_device_id is not null and not exists(
    select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.location_id=v.location_id and d.status='active'
  ) then raise exception 'Invalid POS/device for this loan location';end if;
  if v.status='active' then return jsonb_build_object('success',true,'loan_id',v.id,'loan_number',v.loan_number,'status','active','idempotent',true);end if;
  if v.status<>'approved' then raise exception 'Only Approved loans can be disbursed';end if;
  if coalesce(p_disbursement_date,current_date)>v.first_payment_date then raise exception 'First payment date cannot be before disbursement date';end if;
  delete from public.loan_schedule_v490 where tenant_id=p_tenant_id and loan_id=p_loan_id;
  v_ppy:=private.loan_v490_periods_per_year(v.repayment_frequency);
  v_period_rate:=case when v_ppy=0 then 0 else v.interest_rate/100.0/v_ppy end;
  v_balance:=v.principal_amount;
  if v.amortization_method='flat' then
    v_flat_interest:=round(v.principal_amount*v.interest_rate/100.0*(v.repayment_term_count/v_ppy),2);
    v_installment:=round((v.principal_amount+v_flat_interest)/v.repayment_term_count,2);
  elsif abs(v_period_rate)<0.000000001 then
    v_installment:=round(v.principal_amount/v.repayment_term_count,2);
  else
    v_installment:=round(v.principal_amount*v_period_rate/(1-power(1+v_period_rate,-v.repayment_term_count)),2);
  end if;

  for v_i in 1..v.repayment_term_count loop
    v_due:=private.loan_v490_due_date(v.first_payment_date,v.repayment_frequency,v_i-1);
    if v_i=v.repayment_term_count or v_due>v.maturity_date then v_due:=v.maturity_date;end if;
    if v.amortization_method='flat' then
      v_interest:=case when v_i=v.repayment_term_count then round(v_flat_interest-coalesce((select sum(interest_due) from public.loan_schedule_v490 where loan_id=p_loan_id),0),2) else round(v_flat_interest/v.repayment_term_count,2) end;
      v_principal:=case when v_i=v.repayment_term_count then round(v_balance,2) else least(round(v.principal_amount/v.repayment_term_count,2),v_balance) end;
    else
      v_interest:=round(v_balance*v_period_rate,2);
      v_principal:=case when v_i=v.repayment_term_count then round(v_balance,2) else least(greatest(round(v_installment-v_interest,2),0),v_balance) end;
    end if;
    insert into public.loan_schedule_v490(tenant_id,loan_id,installment_no,due_date,opening_principal,principal_due,interest_due,status)
    values(p_tenant_id,p_loan_id,v_i,v_due,round(v_balance,2),v_principal,v_interest,case when v_due<=current_date then 'due' else 'pending' end);
    v_balance:=greatest(v_balance-v_principal,0);
  end loop;

  update public.loan_accounts_v490 set status='active',disbursement_date=coalesce(p_disbursement_date,current_date),disbursed_by=auth.uid(),disbursed_at=now(),
    principal_outstanding=principal_amount,updated_by=auth.uid(),updated_at=now() where id=p_loan_id;

  v_lines:=jsonb_build_array(
    jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'loan_receivable'),'debit',v.principal_amount,'credit',0,'party_type','customer','party_id',v.client_id,'description','Loan principal advanced'),
    jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,p_payment_method),'debit',0,'credit',v.principal_amount,'party_type','customer','party_id',v.client_id,'description','Loan disbursement')
  );
  perform private.v4_journal_create(p_tenant_id,v.location_id,coalesce(p_disbursement_date,current_date),'Loan disbursement '||v.loan_number,'loan_disbursement_v490',v.id,v.loan_number,v_lines);

  if p_device_id is not null and lower(coalesce(p_payment_method,''))='cash' then
    select id into v_shift from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_device_id and status='open' order by opened_at desc limit 1;
    if v_shift is not null then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(p_tenant_id,v_shift,'cash_out',-abs(v.principal_amount),'loan_disbursement_v490',v.id,v.loan_number,'Loan disbursement',auth.uid());
    end if;
  end if;

  insert into public.loan_rate_history_v490(tenant_id,loan_id,effective_date,previous_rate,new_rate,rate_index,rate_margin,reason,changed_by)
  values(p_tenant_id,p_loan_id,coalesce(p_disbursement_date,current_date),null,v.interest_rate,v.rate_index,v.rate_margin,'Initial effective rate',auth.uid());
  perform private.loan_v490_refresh(p_tenant_id,p_loan_id);
  perform private.loan_v490_event(p_tenant_id,p_loan_id,'disbursed','Loan disbursed',jsonb_build_object('amount',v.principal_amount,'payment_method',p_payment_method,'reference_number',p_reference_number));
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan',p_loan_id::text,'disburse');
  return jsonb_build_object('success',true,'loan_id',v.id,'loan_number',v.loan_number,'status','active','principal_amount',v.principal_amount);
end $$;
grant execute on function public.loan_disburse_v490(uuid,uuid,date,text,text,uuid) to authenticated;

create or replace function public.loan_payment_create_v490(
  p_tenant_id uuid,p_loan_id uuid,p_amount numeric,p_payment_date date default current_date,p_payment_method text default 'cash',
  p_reference_number text default null,p_notes text default null,p_device_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v public.loan_accounts_v490%rowtype;v_payment uuid:=gen_random_uuid();v_no text;v_amount numeric:=round(coalesce(p_amount,0),2);v_remaining numeric:=round(coalesce(p_amount,0),2);
  r record;v_pen numeric;v_int numeric;v_prin numeric;v_take numeric;v_total_pen numeric:=0;v_total_int numeric:=0;v_total_prin numeric:=0;
  v_lines jsonb:='[]'::jsonb;v_shift uuid;
begin
  if v_remaining<=0 then raise exception 'Payment amount must be positive';end if;
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.collect','operate');
  if p_device_id is not null and not exists(
    select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.location_id=v.location_id and d.status='active'
  ) then raise exception 'Invalid POS/device for this loan location';end if;
  if v.status not in('active','defaulted') then raise exception 'Payments are allowed only for Active/Defaulted loans';end if;
  perform private.loan_v490_refresh(p_tenant_id,p_loan_id);
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;
  if v_remaining>v.principal_outstanding+v.interest_outstanding+v.penalty_outstanding+0.005 then raise exception 'Payment exceeds loan outstanding';end if;

  v_no:='LPAY-'||lpad(nextval('public.loan_payment_number_seq_v490')::text,9,'0');
  insert into public.loan_payments_v490(id,tenant_id,loan_id,location_id,payment_number,payment_date,amount,payment_method,reference_number,notes,device_id,created_by)
  values(v_payment,p_tenant_id,p_loan_id,v.location_id,v_no,coalesce(p_payment_date,current_date),v_remaining,lower(coalesce(nullif(trim(p_payment_method),''),'cash')),
    nullif(trim(coalesce(p_reference_number,'')),''),nullif(trim(coalesce(p_notes,'')),''),p_device_id,auth.uid());

  for r in select * from public.loan_schedule_v490 where tenant_id=p_tenant_id and loan_id=p_loan_id and status<>'waived'
           and (principal_due+interest_due+penalty_due)-(principal_paid+interest_paid+penalty_paid)>0.005 order by due_date,installment_no for update loop
    exit when v_remaining<=0.005;
    v_pen:=greatest(r.penalty_due-r.penalty_paid,0);v_int:=greatest(r.interest_due-r.interest_paid,0);v_prin:=greatest(r.principal_due-r.principal_paid,0);
    v_take:=least(v_remaining,v_pen);v_pen:=v_take;v_remaining:=v_remaining-v_take;
    v_take:=least(v_remaining,v_int);v_int:=v_take;v_remaining:=v_remaining-v_take;
    v_take:=least(v_remaining,v_prin);v_prin:=v_take;v_remaining:=v_remaining-v_take;
    if v_pen+v_int+v_prin>0 then
      update public.loan_schedule_v490 set penalty_paid=penalty_paid+v_pen,interest_paid=interest_paid+v_int,principal_paid=principal_paid+v_prin,updated_at=now() where id=r.id;
      insert into public.loan_payment_allocations_v490(tenant_id,payment_id,schedule_id,principal_amount,interest_amount,penalty_amount)
      values(p_tenant_id,v_payment,r.id,v_prin,v_int,v_pen);
      v_total_pen:=v_total_pen+v_pen;v_total_int:=v_total_int+v_int;v_total_prin:=v_total_prin+v_prin;
    end if;
  end loop;
  if v_remaining>0.005 then raise exception 'Payment could not be fully allocated';end if;
  update public.loan_payments_v490 set principal_amount=round(v_total_prin,2),interest_amount=round(v_total_int,2),penalty_amount=round(v_total_pen,2) where id=v_payment;

  v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,p_payment_method),'debit',v_amount,'credit',0,'party_type','customer','party_id',v.client_id,'description','Loan repayment received'));
  if v_total_prin>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'loan_receivable'),'debit',0,'credit',v_total_prin,'party_type','customer','party_id',v.client_id,'description','Loan principal repaid'));end if;
  if v_total_int>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'loan_interest_income'),'debit',0,'credit',v_total_int,'party_type','customer','party_id',v.client_id,'description','Loan interest income'));end if;
  if v_total_pen>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'loan_penalty_income'),'debit',0,'credit',v_total_pen,'party_type','customer','party_id',v.client_id,'description','Loan penalty income'));end if;
  perform private.v4_journal_create(p_tenant_id,v.location_id,coalesce(p_payment_date,current_date),'Loan payment '||v_no,'loan_payment_v490',v_payment,v_no,v_lines);

  if p_device_id is not null and lower(coalesce(p_payment_method,''))='cash' then
    select id into v_shift from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_device_id and status='open' order by opened_at desc limit 1;
    if v_shift is not null then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(p_tenant_id,v_shift,'cash_in',abs(v_amount),'loan_payment_v490',v_payment,v_no,'Loan repayment',auth.uid());
    end if;
  end if;

  perform private.loan_v490_refresh(p_tenant_id,p_loan_id);
  perform private.loan_v490_event(p_tenant_id,p_loan_id,'payment','Loan payment received',jsonb_build_object('payment_id',v_payment,'payment_number',v_no,'amount',v_amount,'principal',v_total_prin,'interest',v_total_int,'penalty',v_total_pen));
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan_payment',v_payment::text,'create');
  return jsonb_build_object('success',true,'payment_id',v_payment,'payment_number',v_no,'amount',v_amount,'principal_amount',round(v_total_prin,2),'interest_amount',round(v_total_int,2),'penalty_amount',round(v_total_pen,2));
end $$;
grant execute on function public.loan_payment_create_v490(uuid,uuid,numeric,date,text,text,text,uuid) to authenticated;

create or replace function public.loan_payment_reverse_v490(p_tenant_id uuid,p_payment_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_payments_v490%rowtype;a record;v_shift uuid;begin
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Reversal reason is required';end if;
  select * into v from public.loan_payments_v490 where tenant_id=p_tenant_id and id=p_payment_id for update;if not found then raise exception 'Loan payment not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.manage','manage');
  if v.status='reversed' then return jsonb_build_object('success',true,'payment_id',v.id,'status','reversed','idempotent',true);end if;
  for a in select * from public.loan_payment_allocations_v490 where tenant_id=p_tenant_id and payment_id=p_payment_id loop
    update public.loan_schedule_v490 set principal_paid=greatest(principal_paid-a.principal_amount,0),interest_paid=greatest(interest_paid-a.interest_amount,0),penalty_paid=greatest(penalty_paid-a.penalty_amount,0),paid_at=null,updated_at=now() where id=a.schedule_id;
  end loop;
  update public.loan_payments_v490 set status='reversed',reversed_by=auth.uid(),reversed_at=now(),reversal_reason=trim(p_reason) where id=p_payment_id;
  update public.journal_entries set status='reversed' where tenant_id=p_tenant_id and source_type='loan_payment_v490' and source_id=p_payment_id and status='posted';
  if v.device_id is not null and lower(v.payment_method)='cash' then
    select id into v_shift from public.cashier_shifts where tenant_id=p_tenant_id and device_id=v.device_id and status='open' order by opened_at desc limit 1;
    if v_shift is not null then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(p_tenant_id,v_shift,'cash_out',-abs(v.amount),'loan_payment_reversal_v490',v.id,v.payment_number,'Loan payment reversal: '||trim(p_reason),auth.uid());
    end if;
  end if;
  perform private.loan_v490_refresh(p_tenant_id,v.loan_id);
  perform private.loan_v490_event(p_tenant_id,v.loan_id,'payment_reversed','Loan payment reversed: '||trim(p_reason),jsonb_build_object('payment_id',v.id,'payment_number',v.payment_number,'amount',v.amount));
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan_payment',v.id::text,'reverse');
  return jsonb_build_object('success',true,'payment_id',v.id,'status','reversed');
end $$;
grant execute on function public.loan_payment_reverse_v490(uuid,uuid,text) to authenticated;

create or replace function public.loan_rate_change_v490(
  p_tenant_id uuid,p_loan_id uuid,p_new_rate numeric,p_effective_date date default current_date,p_rate_index text default null,p_rate_margin numeric default null,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;r record;v_ppy numeric;v_interest numeric;begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.rate_manage','manage');
  if v.rate_type<>'variable' then raise exception 'Only variable-rate loans can change rate';end if;
  if v.status not in('approved','active','defaulted') then raise exception 'Rate cannot be changed in the current loan status';end if;
  if coalesce(p_new_rate,-1)<0 or p_new_rate>1000 then raise exception 'Invalid new interest rate';end if;
  insert into public.loan_rate_history_v490(tenant_id,loan_id,effective_date,previous_rate,new_rate,rate_index,rate_margin,reason,changed_by)
  values(p_tenant_id,p_loan_id,coalesce(p_effective_date,current_date),v.interest_rate,p_new_rate,coalesce(nullif(trim(p_rate_index),''),v.rate_index),coalesce(p_rate_margin,v.rate_margin),nullif(trim(coalesce(p_reason,'')),''),auth.uid());
  update public.loan_accounts_v490 set interest_rate=p_new_rate,rate_index=coalesce(nullif(trim(p_rate_index),''),rate_index),rate_margin=coalesce(p_rate_margin,rate_margin),updated_by=auth.uid(),updated_at=now() where id=p_loan_id;
  if v.status in('active','defaulted') then
    v_ppy:=private.loan_v490_periods_per_year(v.repayment_frequency);
    for r in select * from public.loan_schedule_v490 where tenant_id=p_tenant_id and loan_id=p_loan_id and due_date>=coalesce(p_effective_date,current_date)
             and principal_paid+interest_paid+penalty_paid<=0.005 and status<>'waived' order by installment_no for update loop
      v_interest:=round(r.opening_principal*p_new_rate/100.0/v_ppy,2);
      update public.loan_schedule_v490 set interest_due=v_interest,updated_at=now() where id=r.id;
    end loop;
    perform private.loan_v490_refresh(p_tenant_id,p_loan_id);
  end if;
  perform private.loan_v490_event(p_tenant_id,p_loan_id,'rate_changed','Interest rate changed',jsonb_build_object('previous_rate',v.interest_rate,'new_rate',p_new_rate,'effective_date',coalesce(p_effective_date,current_date)));
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan',p_loan_id::text,'rate_change');
  return jsonb_build_object('success',true,'loan_id',p_loan_id,'interest_rate',p_new_rate,'rate_type','variable');
end $$;
grant execute on function public.loan_rate_change_v490(uuid,uuid,numeric,date,text,numeric,text) to authenticated;

create or replace function public.loan_status_v490(p_tenant_id uuid,p_loan_id uuid,p_status text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;v_status text:=lower(trim(coalesce(p_status,'')));begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.manage','manage');
  if v_status='cancelled' and v.status in('draft','submitted','approved','rejected') then
    update public.loan_accounts_v490 set status='cancelled',updated_by=auth.uid(),updated_at=now() where id=p_loan_id;
  elsif v_status='defaulted' and v.status='active' then
    update public.loan_accounts_v490 set status='defaulted',updated_by=auth.uid(),updated_at=now() where id=p_loan_id;
  elsif v_status='active' and v.status='defaulted' then
    update public.loan_accounts_v490 set status='active',updated_by=auth.uid(),updated_at=now() where id=p_loan_id;
  else raise exception 'Invalid loan status transition % -> %',v.status,v_status;end if;
  perform private.loan_v490_event(p_tenant_id,p_loan_id,'status_changed',coalesce(nullif(trim(p_reason),''),'Loan status changed to '||v_status),jsonb_build_object('from',v.status,'to',v_status));
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan',p_loan_id::text,'status');
  return jsonb_build_object('success',true,'loan_id',p_loan_id,'status',v_status);
end $$;
grant execute on function public.loan_status_v490(uuid,uuid,text,text) to authenticated;

create or replace function public.loan_collateral_save_v490(
  p_tenant_id uuid,p_loan_id uuid,p_collateral_id uuid,p_type text,p_description text,p_reference_number text,p_estimated_value numeric,p_status text default 'active',p_notes text default null
) returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;v_id uuid:=coalesce(p_collateral_id,gen_random_uuid());begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.manage','manage');
  if nullif(trim(coalesce(p_type,'')),'') is null or nullif(trim(coalesce(p_description,'')),'') is null then raise exception 'Collateral type and description are required';end if;
  insert into public.loan_collateral_v490(id,tenant_id,loan_id,collateral_type,description,reference_number,estimated_value,status,notes,created_by)
  values(v_id,p_tenant_id,p_loan_id,trim(p_type),trim(p_description),nullif(trim(coalesce(p_reference_number,'')),''),greatest(coalesce(p_estimated_value,0),0),coalesce(nullif(lower(trim(p_status)),''),'active'),nullif(trim(coalesce(p_notes,'')),''),auth.uid())
  on conflict(id) do update set collateral_type=excluded.collateral_type,description=excluded.description,reference_number=excluded.reference_number,estimated_value=excluded.estimated_value,status=excluded.status,notes=excluded.notes,updated_at=now();
  perform private.loan_v490_event(p_tenant_id,p_loan_id,'collateral_updated','Loan collateral updated');return v_id;
end $$;
grant execute on function public.loan_collateral_save_v490(uuid,uuid,uuid,text,text,text,numeric,text,text) to authenticated;

create or replace function public.loan_guarantor_save_v490(
  p_tenant_id uuid,p_loan_id uuid,p_guarantor_id uuid,p_customer_id uuid,p_name text,p_phone text,p_email text,p_guarantee_amount numeric,p_notes text default null
) returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;v_id uuid:=coalesce(p_guarantor_id,gen_random_uuid());begin
  select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id;if not found then raise exception 'Loan not found';end if;
  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.manage','manage');
  if p_customer_id is not null and not exists(select 1 from public.customers where id=p_customer_id and tenant_id=p_tenant_id) then raise exception 'Guarantor customer not found';end if;
  if nullif(trim(coalesce(p_name,'')),'') is null then raise exception 'Guarantor name is required';end if;
  insert into public.loan_guarantors_v490(id,tenant_id,loan_id,customer_id,name,phone,email,guarantee_amount,notes,created_by)
  values(v_id,p_tenant_id,p_loan_id,p_customer_id,trim(p_name),nullif(trim(coalesce(p_phone,'')),''),nullif(trim(coalesce(p_email,'')),''),p_guarantee_amount,nullif(trim(coalesce(p_notes,'')),''),auth.uid())
  on conflict(id) do update set customer_id=excluded.customer_id,name=excluded.name,phone=excluded.phone,email=excluded.email,guarantee_amount=excluded.guarantee_amount,notes=excluded.notes,updated_at=now();
  perform private.loan_v490_event(p_tenant_id,p_loan_id,'guarantor_updated','Loan guarantor updated');return v_id;
end $$;
grant execute on function public.loan_guarantor_save_v490(uuid,uuid,uuid,uuid,text,text,text,numeric,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(182,'4.9.0','Loans & Credit','Loan lifecycle engine: create/edit/submit/approval/disbursement, amortization schedules, fixed/variable rates, collections, payment reversal, penalties, collateral, guarantors, journal posting and POS cash-drawer integration.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 migration 182 loan engine applied' as status;
