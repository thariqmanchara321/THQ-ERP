-- THQ ERP v4.9.0 Build 21 — Loan collection hardening and readable runtime errors.
begin;

-- Repair financial mappings before accepting loan collections. This is additive
-- and safe for tenants created before the v4.7 accounting provisioning trigger.
do $$
declare r record;
begin
  for r in select id from public.tenants loop
    perform private.v47_ensure_accounting_for_tenant(r.id);
  end loop;
end $$;

insert into public.accounting_accounts(tenant_id,code,name,account_type,system_key,is_system,description)
select t.id,x.code,x.name,x.account_type,x.system_key,true,x.description
from public.tenants t
cross join (values
  ('1110','Loan Receivable','asset','loan_receivable','Outstanding principal advanced to customers/clients'),
  ('4020','Loan Interest Income','income','loan_interest_income','Interest earned on customer/client loans'),
  ('4030','Loan Penalty Income','income','loan_penalty_income','Late-payment and overdue loan charges')
) as x(code,name,account_type,system_key,description)
on conflict(tenant_id,code) do nothing;

insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id)
select a.tenant_id,a.system_key,a.id
from public.accounting_accounts a
where a.system_key in('loan_receivable','loan_interest_income','loan_penalty_income')
on conflict(tenant_id,mapping_key) do update set account_id=excluded.account_id,updated_at=now();

create or replace function public.loan_payment_create_v490(
  p_tenant_id uuid,p_loan_id uuid,p_amount numeric,p_payment_date date default current_date,p_payment_method text default 'cash',
  p_reference_number text default null,p_notes text default null,p_device_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v public.loan_accounts_v490%rowtype;
  v_payment uuid:=gen_random_uuid();
  v_no text;
  v_amount numeric:=round(coalesce(p_amount,0),2);
  v_remaining numeric:=round(coalesce(p_amount,0),2);
  v_method text:=lower(coalesce(nullif(trim(p_payment_method),''),'cash'));
  v_device_id uuid:=p_device_id;
  v_device_app text;
  v_device_location uuid;
  r record;
  v_pen numeric;v_int numeric;v_prin numeric;v_take numeric;
  v_total_pen numeric:=0;v_total_int numeric:=0;v_total_prin numeric:=0;
  v_lines jsonb:='[]'::jsonb;
  v_shift uuid;
begin
  if v_remaining<=0 then raise exception 'Payment amount must be positive';end if;
  if v_method not in('cash','upi','card','credit_card','debit_card','bank','bank_transfer') then
    raise exception 'Unsupported loan payment method %',v_method;
  end if;

  select * into v from public.loan_accounts_v490
  where tenant_id=p_tenant_id and id=p_loan_id for update;
  if not found then raise exception 'Loan not found';end if;

  perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.collect','operate');

  -- Client workstations can have a registered Client device. It must not be
  -- treated as a POS cash drawer. Only an active POS device is retained for
  -- cash-shift posting; Client/non-POS device IDs are intentionally ignored.
  if v_device_id is not null then
    select d.app_type,d.location_id into v_device_app,v_device_location
    from public.business_devices d
    where d.id=v_device_id and d.tenant_id=p_tenant_id and d.status='active';
    if not found then
      v_device_id:=null;
      v_device_app:=null;
      v_device_location:=null;
    elsif v_device_app='pos' and v_device_location<>v.location_id then
      raise exception 'POS device belongs to a different loan location';
    elsif v_device_app<>'pos' then
      v_device_id:=null;
    end if;
  end if;

  if v.status not in('active','defaulted') then
    raise exception 'Payments are allowed only for Active/Defaulted loans';
  end if;

  perform private.loan_v490_refresh(p_tenant_id,p_loan_id);
  select * into v from public.loan_accounts_v490
  where tenant_id=p_tenant_id and id=p_loan_id for update;

  if v_remaining>v.principal_outstanding+v.interest_outstanding+v.penalty_outstanding+0.005 then
    raise exception 'Payment % exceeds loan outstanding %',v_remaining,
      round(v.principal_outstanding+v.interest_outstanding+v.penalty_outstanding,2);
  end if;

  -- Re-check/repair accounting immediately before the journal is created.
  perform private.v47_ensure_accounting_for_tenant(p_tenant_id);
  if private.v4_account_id(p_tenant_id,'loan_receivable') is null then
    raise exception 'Loan receivable accounting mapping is not configured';
  end if;
  if private.v4_account_id(p_tenant_id,'loan_interest_income') is null then
    raise exception 'Loan interest income accounting mapping is not configured';
  end if;
  if private.v4_account_id(p_tenant_id,'loan_penalty_income') is null then
    raise exception 'Loan penalty income accounting mapping is not configured';
  end if;
  if private.v4_payment_account(p_tenant_id,v_method) is null then
    raise exception 'Payment account mapping is not configured for %',v_method;
  end if;

  v_no:='LPAY-'||lpad(nextval('public.loan_payment_number_seq_v490')::text,9,'0');
  insert into public.loan_payments_v490(
    id,tenant_id,loan_id,location_id,payment_number,payment_date,amount,payment_method,
    reference_number,notes,device_id,created_by
  ) values(
    v_payment,p_tenant_id,p_loan_id,v.location_id,v_no,coalesce(p_payment_date,current_date),v_amount,v_method,
    nullif(trim(coalesce(p_reference_number,'')),''),nullif(trim(coalesce(p_notes,'')),''),v_device_id,auth.uid()
  );

  -- Apply penalty -> interest -> principal, oldest installment first. Future
  -- scheduled installments are valid for early/pre-payments as well.
  for r in
    select * from public.loan_schedule_v490
    where tenant_id=p_tenant_id and loan_id=p_loan_id and status<>'waived'
      and (principal_due+interest_due+penalty_due)-(principal_paid+interest_paid+penalty_paid)>0.005
    order by due_date,installment_no
    for update
  loop
    exit when v_remaining<=0.005;
    v_pen:=greatest(r.penalty_due-r.penalty_paid,0);
    v_int:=greatest(r.interest_due-r.interest_paid,0);
    v_prin:=greatest(r.principal_due-r.principal_paid,0);

    v_take:=least(v_remaining,v_pen);v_pen:=v_take;v_remaining:=v_remaining-v_take;
    v_take:=least(v_remaining,v_int);v_int:=v_take;v_remaining:=v_remaining-v_take;
    v_take:=least(v_remaining,v_prin);v_prin:=v_take;v_remaining:=v_remaining-v_take;

    if v_pen+v_int+v_prin>0 then
      update public.loan_schedule_v490
      set penalty_paid=penalty_paid+v_pen,
          interest_paid=interest_paid+v_int,
          principal_paid=principal_paid+v_prin,
          updated_at=now()
      where id=r.id;
      insert into public.loan_payment_allocations_v490(
        tenant_id,payment_id,schedule_id,principal_amount,interest_amount,penalty_amount
      ) values(p_tenant_id,v_payment,r.id,v_prin,v_int,v_pen);
      v_total_pen:=v_total_pen+v_pen;
      v_total_int:=v_total_int+v_int;
      v_total_prin:=v_total_prin+v_prin;
    end if;
  end loop;

  if v_remaining>0.005 then
    raise exception 'Payment could not be fully allocated. Remaining %',round(v_remaining,2);
  end if;

  update public.loan_payments_v490
  set principal_amount=round(v_total_prin,2),
      interest_amount=round(v_total_int,2),
      penalty_amount=round(v_total_pen,2)
  where id=v_payment;

  v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
    'account_id',private.v4_payment_account(p_tenant_id,v_method),
    'debit',v_amount,'credit',0,'party_type','customer','party_id',v.client_id,
    'description','Loan repayment received'
  ));
  if v_total_prin>0 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'account_id',private.v4_account_id(p_tenant_id,'loan_receivable'),
      'debit',0,'credit',v_total_prin,'party_type','customer','party_id',v.client_id,
      'description','Loan principal repaid'
    ));
  end if;
  if v_total_int>0 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'account_id',private.v4_account_id(p_tenant_id,'loan_interest_income'),
      'debit',0,'credit',v_total_int,'party_type','customer','party_id',v.client_id,
      'description','Loan interest income'
    ));
  end if;
  if v_total_pen>0 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'account_id',private.v4_account_id(p_tenant_id,'loan_penalty_income'),
      'debit',0,'credit',v_total_pen,'party_type','customer','party_id',v.client_id,
      'description','Loan penalty income'
    ));
  end if;

  begin
    perform private.v4_journal_create(
      p_tenant_id,v.location_id,coalesce(p_payment_date,current_date),
      'Loan payment '||v_no,'loan_payment_v490',v_payment,v_no,v_lines
    );
  exception when others then
    raise exception 'Loan payment accounting post failed: %',SQLERRM;
  end;

  if v_device_id is not null and v_device_app='pos' and v_method='cash' then
    select id into v_shift from public.cashier_shifts
    where tenant_id=p_tenant_id and device_id=v_device_id and status='open'
    order by opened_at desc limit 1;
    if v_shift is not null then
      insert into public.cash_drawer_movements(
        tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by
      ) values(
        p_tenant_id,v_shift,'cash_in',abs(v_amount),'loan_payment_v490',v_payment,v_no,'Loan repayment',auth.uid()
      );
    end if;
  end if;

  perform private.loan_v490_refresh(p_tenant_id,p_loan_id);
  perform private.loan_v490_event(
    p_tenant_id,p_loan_id,'payment','Loan payment received',
    jsonb_build_object(
      'payment_id',v_payment,'payment_number',v_no,'amount',v_amount,
      'principal',round(v_total_prin,2),'interest',round(v_total_int,2),'penalty',round(v_total_pen,2),
      'payment_method',v_method
    )
  );
  perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan_payment',v_payment::text,'create');

  return jsonb_build_object(
    'success',true,'payment_id',v_payment,'payment_number',v_no,'amount',v_amount,
    'principal_amount',round(v_total_prin,2),'interest_amount',round(v_total_int,2),'penalty_amount',round(v_total_pen,2),
    'remaining_outstanding',greatest(round(v.principal_outstanding+v.interest_outstanding+v.penalty_outstanding-v_amount,2),0)
  );
end $$;
grant execute on function public.loan_payment_create_v490(uuid,uuid,numeric,date,text,text,text,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(191,'4.9.0','Loan Collection Hardening','Repairs accounting mappings, separates Client devices from POS cash drawer behavior and hardens loan payment posting.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 21 migration 191 loan collection hardening applied' as status;
