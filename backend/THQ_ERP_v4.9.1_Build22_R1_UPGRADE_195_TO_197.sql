-- THQ ERP v4.9.1 Build 22 R1 continuation: migration 195 -> 197
-- Corrected Build 22 R1: declares v_shift in loan_payment_create_v491.
-- Generated from authoritative backend/migrations files.
-- Generated: 2026-08-29


-- ============================================================================
-- MIGRATION 195: 195_v491_bidirectional_loans.sql
-- ============================================================================
-- THQ ERP v4.9.1 — bidirectional Loans (Given/Receivable and Taken/Payable) + module accounting switch.
begin;

alter table public.loan_accounts_v490 add column if not exists direction text not null default 'given';
alter table public.loan_accounts_v490 add column if not exists counterparty_type text not null default 'customer';
alter table public.loan_accounts_v490 add column if not exists supplier_id uuid references public.suppliers(id) on delete restrict;
alter table public.loan_accounts_v490 add column if not exists counterparty_name text;
alter table public.loan_accounts_v490 add column if not exists counterparty_reference text;
alter table public.loan_accounts_v490 add column if not exists accounting_enabled boolean not null default true;
alter table public.loan_accounts_v490 alter column client_id drop not null;
do $$ begin
  if not exists(select 1 from pg_constraint where conname='loan_accounts_v490_direction_chk') then
    alter table public.loan_accounts_v490 add constraint loan_accounts_v490_direction_chk check(direction in('given','taken'));
  end if;
  if not exists(select 1 from pg_constraint where conname='loan_accounts_v490_counterparty_chk') then
    alter table public.loan_accounts_v490 add constraint loan_accounts_v490_counterparty_chk check(counterparty_type in('customer','supplier','other'));
  end if;
end $$;
update public.loan_accounts_v490 set direction='given',counterparty_type='customer',counterparty_name=coalesce(counterparty_name,(select c.name from public.customers c where c.id=client_id)) where direction is null or direction='given';

insert into public.accounting_accounts(tenant_id,code,name,account_type,system_key,is_system,description)
select t.id,x.code,x.name,x.typ,x.key,true,x.descr from public.tenants t cross join (values
 ('2210','Loan Payable','liability','loan_payable','Principal borrowed by the business'),
 ('5210','Loan Interest Expense','expense','loan_interest_expense','Interest paid/accrued on loans taken'),
 ('5220','Loan Penalty Expense','expense','loan_penalty_expense','Penalty/late charges on loans taken')
) x(code,name,typ,key,descr)
on conflict(tenant_id,code) do update set name=excluded.name,account_type=excluded.account_type,system_key=excluded.system_key,is_system=true,description=excluded.description;
insert into public.accounting_account_mappings(tenant_id,mapping_key,account_id)
select a.tenant_id,a.system_key,a.id from public.accounting_accounts a where a.system_key in('loan_payable','loan_interest_expense','loan_penalty_expense')
on conflict(tenant_id,mapping_key) do update set account_id=excluded.account_id,updated_at=now();

create or replace function private.loan_v491_accounting_enabled(p_tenant_id uuid)
returns boolean language sql stable security definer set search_path=public,private,pg_temp as $$
  select coalesce((select coalesce((settings#>>'{loans,reflect_in_accounting}')::boolean,true) from public.tenant_settings_v2 where tenant_id=p_tenant_id),true)
$$;
revoke all on function private.loan_v491_accounting_enabled(uuid) from public;

create or replace function public.loan_settings_v491_get(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;
 return jsonb_build_object('reflect_in_accounting',private.loan_v491_accounting_enabled(p_tenant_id),'note','This setting applies to new Draft/Approved loans. Active loans keep their accounting mode to preserve reconciliation.');
end $$;
grant execute on function public.loan_settings_v491_get(uuid) to authenticated;

create or replace function public.loan_settings_v491_set(p_tenant_id uuid,p_reflect boolean)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$ begin
 if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'loans.manage') then raise exception 'Permission denied'; end if;
 insert into public.tenant_settings_v2(tenant_id,settings,updated_by) values(p_tenant_id,jsonb_build_object('loans',jsonb_build_object('reflect_in_accounting',coalesce(p_reflect,true))),auth.uid())
 on conflict(tenant_id) do update set settings=jsonb_set(coalesce(public.tenant_settings_v2.settings,'{}'::jsonb),'{loans,reflect_in_accounting}',to_jsonb(coalesce(p_reflect,true)),true),updated_by=auth.uid(),updated_at=now();
 update public.loan_accounts_v490 set accounting_enabled=coalesce(p_reflect,true),updated_at=now(),updated_by=auth.uid() where tenant_id=p_tenant_id and status in('draft','submitted','approved');
 return jsonb_build_object('success',true,'reflect_in_accounting',coalesce(p_reflect,true));
end $$;
grant execute on function public.loan_settings_v491_set(uuid,boolean) to authenticated;

create or replace function public.loan_create_v491(p_tenant_id uuid,p_location_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid:=gen_random_uuid();v_no text;v_client uuid;v_supplier uuid;v_dir text;v_party text;v_name text;v_principal numeric;v_rate numeric;v_rate_type text;v_freq text;v_terms int;v_first date;v_mat date;v_amort text;begin
 perform private.loan_v490_access(p_tenant_id,p_location_id,'loans.create','operate');
 v_dir:=lower(coalesce(nullif(p_payload->>'direction',''),'given')); if v_dir not in('given','taken') then raise exception 'Loan direction must be given or taken';end if;
 v_party:=lower(coalesce(nullif(p_payload->>'counterparty_type',''),case when v_dir='given' then 'customer' else 'supplier' end)); if v_party not in('customer','supplier','other') then raise exception 'Invalid loan counterparty type'; end if;
 v_client:=nullif(p_payload->>'client_id','')::uuid; v_supplier:=nullif(p_payload->>'supplier_id','')::uuid;
 if v_party='customer' then select name into v_name from public.customers where id=v_client and tenant_id=p_tenant_id and coalesce(status,'active')='active' and not coalesce(is_walk_in,false); if v_name is null then raise exception 'Active non-walk-in customer/client is required';end if;
 elsif v_party='supplier' then select name into v_name from public.suppliers where id=v_supplier and tenant_id=p_tenant_id and coalesce(status,'active')='active'; if v_name is null then raise exception 'Active supplier/lender is required';end if;
 else v_name:=nullif(trim(coalesce(p_payload->>'counterparty_name','')),''); if v_name is null then raise exception 'Lender/borrower name is required';end if; end if;
 v_principal:=coalesce(nullif(p_payload->>'principal_amount','')::numeric,0); if v_principal<=0 then raise exception 'Principal amount must be positive';end if;
 v_rate:=coalesce(nullif(p_payload->>'interest_rate','')::numeric,0); if v_rate<0 or v_rate>1000 then raise exception 'Invalid interest rate';end if;
 v_rate_type:=lower(coalesce(nullif(p_payload->>'rate_type',''),'fixed')); if v_rate_type not in('fixed','variable') then raise exception 'Invalid interest type';end if;
 v_freq:=lower(coalesce(nullif(p_payload->>'repayment_frequency',''),'monthly')); if v_freq not in('weekly','biweekly','monthly','quarterly','half_yearly','yearly') then raise exception 'Invalid repayment frequency';end if;
 v_terms:=coalesce(nullif(p_payload->>'repayment_term_count','')::int,0); if v_terms<=0 or v_terms>1200 then raise exception 'Invalid repayment terms';end if;
 v_first:=nullif(p_payload->>'first_payment_date','')::date; if v_first is null then raise exception 'First payment date is required';end if;
 v_mat:=coalesce(nullif(p_payload->>'maturity_date','')::date,private.loan_v490_due_date(v_first,v_freq,v_terms-1)); if v_mat<v_first then raise exception 'Maturity date cannot be before first payment date';end if; if v_terms>1 and v_mat<private.loan_v490_due_date(v_first,v_freq,v_terms-2) then raise exception 'Maturity date is too early for the selected repayment terms';end if;
 v_amort:=lower(coalesce(nullif(p_payload->>'amortization_method',''),'reducing_balance')); if v_amort not in('reducing_balance','flat') then raise exception 'Invalid amortization method';end if;
 if v_rate_type='variable' and nullif(trim(coalesce(p_payload->>'rate_index','')),'') is null then raise exception 'Variable-rate loans require a rate index';end if;
 v_no:=case when v_dir='given' then 'LG-' else 'LT-' end||lpad(nextval('public.loan_number_seq_v490')::text,8,'0');
 insert into public.loan_accounts_v490(id,tenant_id,location_id,loan_number,client_id,supplier_id,direction,counterparty_type,counterparty_name,counterparty_reference,external_client_reference,purpose,principal_amount,interest_rate,rate_type,rate_index,rate_margin,rate_reset_frequency,next_rate_review_date,amortization_method,repayment_frequency,repayment_term_count,repayment_terms,first_payment_date,maturity_date,payment_warning_days,maturity_warning_days,grace_days,penalty_rate,collateral_summary,notes,status,accounting_enabled,created_by,updated_by)
 values(v_id,p_tenant_id,p_location_id,v_no,v_client,v_supplier,v_dir,v_party,v_name,nullif(trim(coalesce(p_payload->>'counterparty_reference','')),''),nullif(trim(coalesce(p_payload->>'external_client_reference','')),''),nullif(trim(coalesce(p_payload->>'purpose','')),''),v_principal,v_rate,v_rate_type,nullif(trim(coalesce(p_payload->>'rate_index','')),''),coalesce(nullif(p_payload->>'rate_margin','')::numeric,0),nullif(lower(trim(coalesce(p_payload->>'rate_reset_frequency',''))),''),nullif(p_payload->>'next_rate_review_date','')::date,v_amort,v_freq,v_terms,nullif(trim(coalesce(p_payload->>'repayment_terms','')),''),v_first,v_mat,coalesce(nullif(p_payload->>'payment_warning_days','')::int,5),coalesce(nullif(p_payload->>'maturity_warning_days','')::int,30),coalesce(nullif(p_payload->>'grace_days','')::int,0),coalesce(nullif(p_payload->>'penalty_rate','')::numeric,0),nullif(trim(coalesce(p_payload->>'collateral_summary','')),''),nullif(trim(coalesce(p_payload->>'notes','')),''),'draft',private.loan_v491_accounting_enabled(p_tenant_id),auth.uid(),auth.uid());
 perform private.loan_v490_event(p_tenant_id,v_id,'created',case when v_dir='given' then 'Loan given created' else 'Loan taken created' end,jsonb_build_object('direction',v_dir,'counterparty_type',v_party,'counterparty_name',v_name,'principal_amount',v_principal,'accounting_enabled',private.loan_v491_accounting_enabled(p_tenant_id)));
 return jsonb_build_object('success',true,'loan_id',v_id,'loan_number',v_no,'direction',v_dir,'status','draft');
end $$;
grant execute on function public.loan_create_v491(uuid,uuid,jsonb) to authenticated;

create or replace function public.loan_update_v491(p_tenant_id uuid,p_loan_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
 v public.loan_accounts_v490%rowtype;v_client uuid;v_supplier uuid;v_party text;v_name text;v_dir text;
 v_principal numeric;v_rate numeric;v_penalty numeric;v_rate_type text;v_freq text;v_terms int;v_first date;v_mat date;v_amort text;
begin
 select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;
 if not found then raise exception 'Loan not found';end if;
 perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.create','operate');
 if v.status not in('draft','rejected') then raise exception 'Only Draft/Rejected loans can be edited';end if;

 v_dir:=lower(coalesce(nullif(p_payload->>'direction',''),v.direction));
 if v_dir not in('given','taken') then raise exception 'Loan direction must be given or taken';end if;
 v_party:=lower(coalesce(nullif(p_payload->>'counterparty_type',''),v.counterparty_type));
 if v_party not in('customer','supplier','other') then raise exception 'Invalid loan counterparty type';end if;
 v_client:=nullif(coalesce(nullif(p_payload->>'client_id',''),v.client_id::text),'')::uuid;
 v_supplier:=nullif(coalesce(nullif(p_payload->>'supplier_id',''),v.supplier_id::text),'')::uuid;
 if v_party='customer' then
   select name into v_name from public.customers where id=v_client and tenant_id=p_tenant_id and coalesce(status,'active')='active' and not coalesce(is_walk_in,false);
   if v_name is null then raise exception 'Active non-walk-in customer/client is required';end if;
 elsif v_party='supplier' then
   select name into v_name from public.suppliers where id=v_supplier and tenant_id=p_tenant_id and coalesce(status,'active')='active';
   if v_name is null then raise exception 'Active supplier/lender is required';end if;
 else
   v_name:=coalesce(nullif(trim(coalesce(p_payload->>'counterparty_name','')),''),v.counterparty_name);
   if v_name is null then raise exception 'Lender/borrower name is required';end if;
 end if;

 v_principal:=coalesce(nullif(p_payload->>'principal_amount','')::numeric,v.principal_amount);
 v_rate:=coalesce(nullif(p_payload->>'interest_rate','')::numeric,v.interest_rate);
 v_penalty:=coalesce(nullif(p_payload->>'penalty_rate','')::numeric,v.penalty_rate);
 if v_principal<=0 then raise exception 'Principal amount must be positive';end if;
 if v_rate<0 or v_rate>1000 then raise exception 'Invalid interest rate';end if;
 if v_penalty<0 or v_penalty>1000 then raise exception 'Invalid penalty rate';end if;
 v_rate_type:=lower(coalesce(nullif(p_payload->>'rate_type',''),v.rate_type));
 if v_rate_type not in('fixed','variable') then raise exception 'Invalid interest type';end if;
 v_freq:=lower(coalesce(nullif(p_payload->>'repayment_frequency',''),v.repayment_frequency));
 if v_freq not in('weekly','biweekly','monthly','quarterly','half_yearly','yearly') then raise exception 'Invalid repayment frequency';end if;
 v_terms:=coalesce(nullif(p_payload->>'repayment_term_count','')::int,v.repayment_term_count);
 if v_terms<=0 or v_terms>1200 then raise exception 'Invalid repayment terms';end if;
 v_first:=coalesce(nullif(p_payload->>'first_payment_date','')::date,v.first_payment_date);
 v_mat:=coalesce(nullif(p_payload->>'maturity_date','')::date,private.loan_v490_due_date(v_first,v_freq,v_terms-1));
 if v_mat<v_first then raise exception 'Maturity date cannot be before first payment date';end if;
 if v_terms>1 and v_mat<private.loan_v490_due_date(v_first,v_freq,v_terms-2) then raise exception 'Maturity date is too early for the selected repayment terms';end if;
 v_amort:=lower(coalesce(nullif(p_payload->>'amortization_method',''),v.amortization_method));
 if v_amort not in('reducing_balance','flat') then raise exception 'Invalid amortization method';end if;
 if v_rate_type='variable' and nullif(trim(coalesce(p_payload->>'rate_index',v.rate_index,'')),'') is null then raise exception 'Variable-rate loans require a rate index';end if;

 update public.loan_accounts_v490 set
   direction=v_dir,counterparty_type=v_party,
   client_id=case when v_party='customer' then v_client else null end,
   supplier_id=case when v_party='supplier' then v_supplier else null end,
   counterparty_name=v_name,
   counterparty_reference=coalesce(nullif(trim(p_payload->>'counterparty_reference'),''),counterparty_reference),
   external_client_reference=coalesce(nullif(trim(p_payload->>'external_client_reference'),''),external_client_reference),
   purpose=coalesce(nullif(trim(p_payload->>'purpose'),''),purpose),principal_amount=v_principal,interest_rate=v_rate,
   rate_type=v_rate_type,rate_index=coalesce(nullif(trim(p_payload->>'rate_index'),''),rate_index),
   rate_margin=coalesce(nullif(p_payload->>'rate_margin','')::numeric,rate_margin),
   rate_reset_frequency=coalesce(nullif(lower(p_payload->>'rate_reset_frequency'),''),rate_reset_frequency),
   next_rate_review_date=coalesce(nullif(p_payload->>'next_rate_review_date','')::date,next_rate_review_date),
   amortization_method=v_amort,repayment_frequency=v_freq,repayment_term_count=v_terms,
   repayment_terms=coalesce(nullif(trim(p_payload->>'repayment_terms'),''),repayment_terms),first_payment_date=v_first,maturity_date=v_mat,
   payment_warning_days=coalesce(nullif(p_payload->>'payment_warning_days','')::int,payment_warning_days),
   maturity_warning_days=coalesce(nullif(p_payload->>'maturity_warning_days','')::int,maturity_warning_days),
   grace_days=coalesce(nullif(p_payload->>'grace_days','')::int,grace_days),penalty_rate=v_penalty,
   collateral_summary=coalesce(nullif(trim(p_payload->>'collateral_summary'),''),collateral_summary),
   notes=coalesce(nullif(trim(p_payload->>'notes'),''),notes),status='draft',rejection_reason=null,rejected_by=null,rejected_at=null,
   accounting_enabled=private.loan_v491_accounting_enabled(p_tenant_id),updated_by=auth.uid(),updated_at=now()
 where id=p_loan_id;
 perform private.loan_v490_event(p_tenant_id,p_loan_id,'updated','Loan details updated',jsonb_build_object('direction',v_dir,'counterparty_type',v_party,'counterparty_name',v_name));
 perform private.thq_sync_bump_v480(p_tenant_id,'finance','loan',p_loan_id::text,'update');
 return jsonb_build_object('success',true,'loan_id',p_loan_id,'direction',v_dir,'status','draft');
end $$;
grant execute on function public.loan_update_v491(uuid,uuid,jsonb) to authenticated;

create or replace function private.loan_v491_party_json(v public.loan_accounts_v490)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$ declare j jsonb; begin
 if v.counterparty_type='customer' then select jsonb_build_object('id',c.id,'type','customer','name',c.name,'public_id',c.tracking_code,'phone',c.phone,'email',c.email,'tax_number',c.tax_number) into j from public.customers c where c.id=v.client_id;
 elsif v.counterparty_type='supplier' then select jsonb_build_object('id',s.id,'type','supplier','name',s.name,'public_id',s.tracking_code,'phone',s.phone,'email',s.email,'tax_number',s.tax_number) into j from public.suppliers s where s.id=v.supplier_id;
 else j:=jsonb_build_object('id',null,'type','other','name',v.counterparty_name,'public_id',coalesce(v.counterparty_reference,''),'phone','','email','','tax_number',''); end if; return coalesce(j,'{}'::jsonb); end $$;
revoke all on function private.loan_v491_party_json(public.loan_accounts_v490) from public;

create or replace function public.loan_list_v491(p_tenant_id uuid,p_location_id uuid default null,p_status text default null,p_direction text default null,p_query text default '',p_limit int default 500)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$ declare result jsonb; begin
 perform private.loan_v490_access(p_tenant_id,p_location_id,'loans.view','view');
 select coalesce(jsonb_agg(x order by (x->>'warning_rank')::int,(x->>'updated_at') desc),'[]'::jsonb) into result from (
  select to_jsonb(l)||private.loan_v491_party_json(l)||jsonb_build_object('loan_id',l.id,'client_name',coalesce(l.counterparty_name,c.name,s.name),'client_public_id',coalesce(c.tracking_code,s.tracking_code,l.counterparty_reference,''),'total_outstanding',round(l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding,2),'next_due_date',nd.due_date,'next_due_amount',coalesce(nd.amount,0),'warning_level',case when coalesce(ov.cnt,0)>0 then 'danger' when l.status='defaulted' then 'danger' when nd.due_date<=current_date+l.payment_warning_days then 'warning' else 'normal' end,'warning_message',case when coalesce(ov.cnt,0)>0 then ov.cnt||' overdue installment(s)' when nd.due_date<=current_date+l.payment_warning_days then 'Payment due '||to_char(nd.due_date,'DD Mon YYYY') else null end,'warning_rank',case when coalesce(ov.cnt,0)>0 then 0 when l.status in('active','defaulted') then 1 else 2 end) x
  from public.loan_accounts_v490 l left join public.customers c on c.id=l.client_id left join public.suppliers s on s.id=l.supplier_id
  left join lateral(select sc.due_date,round((sc.principal_due+sc.interest_due+sc.penalty_due)-(sc.principal_paid+sc.interest_paid+sc.penalty_paid),2) amount from public.loan_schedule_v490 sc where sc.loan_id=l.id and sc.status<>'waived' and (sc.principal_due+sc.interest_due+sc.penalty_due)-(sc.principal_paid+sc.interest_paid+sc.penalty_paid)>0.005 order by sc.due_date limit 1) nd on true
  left join lateral(select count(*) cnt from public.loan_schedule_v490 sc where sc.loan_id=l.id and sc.status='overdue') ov on true
  where l.tenant_id=p_tenant_id and (p_location_id is null or l.location_id=p_location_id) and (p_status is null or p_status='' or l.status=lower(p_status)) and (p_direction is null or p_direction='' or l.direction=lower(p_direction)) and (trim(coalesce(p_query,''))='' or lower(concat_ws(' ',l.loan_number,l.counterparty_name,c.name,s.name,c.tracking_code,s.tracking_code,l.purpose,l.counterparty_reference)) like '%'||lower(trim(p_query))||'%') and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view') limit least(greatest(coalesce(p_limit,500),1),2000)
 ) q;
 return result;
end $$;
grant execute on function public.loan_list_v491(uuid,uuid,text,text,text,integer) to authenticated;

create or replace function public.loan_detail_v491(p_tenant_id uuid,p_loan_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$ declare v public.loan_accounts_v490%rowtype;begin
 select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id; if not found then raise exception 'Loan not found';end if; perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.view','view'); if v.status in('active','defaulted','closed') then perform private.loan_v490_refresh(p_tenant_id,p_loan_id); select * into v from public.loan_accounts_v490 where id=p_loan_id;end if;
 return jsonb_build_object('loan',to_jsonb(v)||jsonb_build_object('total_outstanding',round(v.principal_outstanding+v.interest_outstanding+v.penalty_outstanding,2),'client_name',v.counterparty_name,'client_public_id',coalesce(v.counterparty_reference,''),'location_name',(select name from public.business_locations where id=v.location_id)),'counterparty',private.loan_v491_party_json(v),'schedule',coalesce((select jsonb_agg(to_jsonb(s) order by s.installment_no) from public.loan_schedule_v490 s where s.loan_id=v.id),'[]'::jsonb),'payments',coalesce((select jsonb_agg(to_jsonb(p) order by p.payment_date desc,p.created_at desc) from public.loan_payments_v490 p where p.loan_id=v.id),'[]'::jsonb),'rate_history',coalesce((select jsonb_agg(to_jsonb(r) order by r.effective_date desc) from public.loan_rate_history_v490 r where r.loan_id=v.id),'[]'::jsonb),'collateral',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.loan_collateral_v490 x where x.loan_id=v.id),'[]'::jsonb),'guarantors',coalesce((select jsonb_agg(to_jsonb(g) order by g.created_at) from public.loan_guarantors_v490 g where g.loan_id=v.id),'[]'::jsonb),'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.event_date desc) from public.loan_events_v490 e where e.loan_id=v.id),'[]'::jsonb),'settings',jsonb_build_object('reflect_in_accounting',v.accounting_enabled));
end $$;
grant execute on function public.loan_detail_v491(uuid,uuid) to authenticated;

-- Shared activation transaction. For Taken loans, receiving the principal increases cash/bank and Loan Payable.
create or replace function public.loan_activate_v491(p_tenant_id uuid,p_loan_id uuid,p_disbursement_date date default current_date,p_payment_method text default 'bank',p_reference_number text default null,p_device_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;v_ppy numeric;v_pr numeric;v_inst numeric;v_flat numeric;v_bal numeric;v_int numeric;v_prin numeric;v_due date;i int;v_lines jsonb;v_shift uuid;begin
 select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;if not found then raise exception 'Loan not found';end if;perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.disburse','manage');if p_device_id is not null and not exists(select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.location_id=v.location_id and d.status='active') then raise exception 'Invalid POS/device for this loan location';end if;if v.status='active' then return jsonb_build_object('success',true,'loan_id',v.id,'status','active','idempotent',true);end if;if v.status<>'approved' then raise exception 'Only Approved loans can be activated';end if;if coalesce(p_disbursement_date,current_date)>v.first_payment_date then raise exception 'First payment date cannot be before funding date';end if;
 delete from public.loan_schedule_v490 where tenant_id=p_tenant_id and loan_id=p_loan_id;v_ppy:=private.loan_v490_periods_per_year(v.repayment_frequency);v_pr:=case when v_ppy=0 then 0 else v.interest_rate/100.0/v_ppy end;v_bal:=v.principal_amount;
 if v.amortization_method='flat' then v_flat:=round(v.principal_amount*v.interest_rate/100.0*(v.repayment_term_count/v_ppy),2);v_inst:=round((v.principal_amount+v_flat)/v.repayment_term_count,2);elsif abs(v_pr)<0.000000001 then v_inst:=round(v.principal_amount/v.repayment_term_count,2);else v_inst:=round(v.principal_amount*v_pr/(1-power(1+v_pr,-v.repayment_term_count)),2);end if;
 for i in 1..v.repayment_term_count loop v_due:=private.loan_v490_due_date(v.first_payment_date,v.repayment_frequency,i-1);if i=v.repayment_term_count or v_due>v.maturity_date then v_due:=v.maturity_date;end if;if v.amortization_method='flat' then v_int:=case when i=v.repayment_term_count then round(v_flat-coalesce((select sum(interest_due) from public.loan_schedule_v490 where loan_id=p_loan_id),0),2) else round(v_flat/v.repayment_term_count,2) end;v_prin:=case when i=v.repayment_term_count then round(v_bal,2) else least(round(v.principal_amount/v.repayment_term_count,2),v_bal) end;else v_int:=round(v_bal*v_pr,2);v_prin:=case when i=v.repayment_term_count then round(v_bal,2) else least(greatest(round(v_inst-v_int,2),0),v_bal) end;end if;insert into public.loan_schedule_v490(tenant_id,loan_id,installment_no,due_date,opening_principal,principal_due,interest_due,status) values(p_tenant_id,p_loan_id,i,v_due,round(v_bal,2),v_prin,v_int,case when v_due<=current_date then 'due' else 'pending' end);v_bal:=greatest(v_bal-v_prin,0);end loop;
 update public.loan_accounts_v490 set status='active',disbursement_date=coalesce(p_disbursement_date,current_date),disbursed_by=auth.uid(),disbursed_at=now(),principal_outstanding=principal_amount,updated_by=auth.uid(),updated_at=now() where id=p_loan_id;
 if v.accounting_enabled then perform private.v491_ensure_financial_mappings(p_tenant_id); if v.direction='given' then v_lines:=jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'loan_receivable'),'debit',v.principal_amount,'credit',0,'party_type',v.counterparty_type,'party_id',coalesce(v.client_id,v.supplier_id),'description','Loan given principal'),jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,p_payment_method),'debit',0,'credit',v.principal_amount,'description','Loan given funding')); else v_lines:=jsonb_build_array(jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,p_payment_method),'debit',v.principal_amount,'credit',0,'description','Loan taken funds received'),jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'loan_payable'),'debit',0,'credit',v.principal_amount,'party_type',v.counterparty_type,'party_id',coalesce(v.client_id,v.supplier_id),'description','Loan taken principal payable'));end if;perform private.v4_journal_create(p_tenant_id,v.location_id,coalesce(p_disbursement_date,current_date),'Loan activation '||v.loan_number,'loan_activation_v491',v.id,v.loan_number,v_lines); if p_device_id is not null and lower(coalesce(p_payment_method,''))='cash' then select id into v_shift from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_device_id and status='open' order by opened_at desc limit 1; if v_shift is not null then insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by) values(p_tenant_id,v_shift,case when v.direction='given' then 'cash_out' else 'cash_in' end,case when v.direction='given' then -abs(v.principal_amount) else abs(v.principal_amount) end,'loan_activation_v491',v.id,v.loan_number,case when v.direction='given' then 'Loan given' else 'Loan taken funds received' end,auth.uid()); end if; end if;end if;
 insert into public.loan_rate_history_v490(tenant_id,loan_id,effective_date,previous_rate,new_rate,rate_index,rate_margin,reason,changed_by) values(p_tenant_id,p_loan_id,coalesce(p_disbursement_date,current_date),null,v.interest_rate,v.rate_index,v.rate_margin,'Initial effective rate',auth.uid());perform private.loan_v490_refresh(p_tenant_id,p_loan_id);perform private.loan_v490_event(p_tenant_id,p_loan_id,'activated',case when v.direction='given' then 'Loan funds given' else 'Loan funds received' end,jsonb_build_object('direction',v.direction,'amount',v.principal_amount,'payment_method',p_payment_method,'accounting_enabled',v.accounting_enabled));return jsonb_build_object('success',true,'loan_id',v.id,'status','active','direction',v.direction);
end $$;
grant execute on function public.loan_activate_v491(uuid,uuid,date,text,text,uuid) to authenticated;

create or replace function public.loan_payment_create_v491(p_tenant_id uuid,p_loan_id uuid,p_amount numeric,p_payment_date date default current_date,p_payment_method text default 'cash',p_reference_number text default null,p_notes text default null,p_device_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_accounts_v490%rowtype;pid uuid:=gen_random_uuid();pno text;rem numeric:=round(coalesce(p_amount,0),2);amt numeric:=rem;r record;pen numeric;intr numeric;prin numeric;take numeric;tp numeric:=0;ti numeric:=0;tpr numeric:=0;lines jsonb:='[]'::jsonb;v_shift uuid;begin
 if rem<=0 then raise exception 'Payment amount must be positive';end if;select * into v from public.loan_accounts_v490 where tenant_id=p_tenant_id and id=p_loan_id for update;if not found then raise exception 'Loan not found';end if;perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.collect','operate');if p_device_id is not null and not exists(select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.location_id=v.location_id and d.status='active') then raise exception 'Invalid POS/device for this loan location';end if;if v.status not in('active','defaulted') then raise exception 'Payments are allowed only for Active/Defaulted loans';end if;perform private.loan_v490_refresh(p_tenant_id,p_loan_id);select * into v from public.loan_accounts_v490 where id=p_loan_id for update;if rem>v.principal_outstanding+v.interest_outstanding+v.penalty_outstanding+0.005 then raise exception 'Payment exceeds outstanding amount';end if;
 pno:=case when v.direction='given' then 'LRCV-' else 'LPAY-' end||lpad(nextval('public.loan_payment_number_seq_v490')::text,9,'0');insert into public.loan_payments_v490(id,tenant_id,loan_id,location_id,payment_number,payment_date,amount,payment_method,reference_number,notes,device_id,created_by) values(pid,p_tenant_id,p_loan_id,v.location_id,pno,coalesce(p_payment_date,current_date),amt,lower(p_payment_method),nullif(trim(coalesce(p_reference_number,'')),''),nullif(trim(coalesce(p_notes,'')),''),p_device_id,auth.uid());
 for r in select * from public.loan_schedule_v490 where loan_id=p_loan_id and status<>'waived' and (principal_due+interest_due+penalty_due)-(principal_paid+interest_paid+penalty_paid)>0.005 order by due_date,installment_no for update loop exit when rem<=0.005;pen:=least(rem,greatest(r.penalty_due-r.penalty_paid,0));rem:=rem-pen;intr:=least(rem,greatest(r.interest_due-r.interest_paid,0));rem:=rem-intr;prin:=least(rem,greatest(r.principal_due-r.principal_paid,0));rem:=rem-prin;update public.loan_schedule_v490 set penalty_paid=penalty_paid+pen,interest_paid=interest_paid+intr,principal_paid=principal_paid+prin,updated_at=now() where id=r.id;insert into public.loan_payment_allocations_v490(tenant_id,payment_id,schedule_id,principal_amount,interest_amount,penalty_amount) values(p_tenant_id,pid,r.id,prin,intr,pen);tp:=tp+pen;ti:=ti+intr;tpr:=tpr+prin;end loop;if rem>0.005 then raise exception 'Payment could not be fully allocated';end if;update public.loan_payments_v490 set principal_amount=tpr,interest_amount=ti,penalty_amount=tp where id=pid;
 if v.accounting_enabled then if v.direction='given' then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,p_payment_method),'debit',amt,'credit',0,'description','Loan collection received'));if tpr>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'loan_receivable'),'debit',0,'credit',tpr,'description','Loan principal collected'));end if;if ti>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'loan_interest_income'),'debit',0,'credit',ti,'description','Loan interest income'));end if;if tp>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'loan_penalty_income'),'debit',0,'credit',tp,'description','Loan penalty income'));end if;else if tpr>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'loan_payable'),'debit',tpr,'credit',0,'description','Loan principal repaid'));end if;if ti>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'loan_interest_expense'),'debit',ti,'credit',0,'description','Loan interest expense'));end if;if tp>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'loan_penalty_expense'),'debit',tp,'credit',0,'description','Loan penalty expense'));end if;lines:=lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_payment_account(p_tenant_id,p_payment_method),'debit',0,'credit',amt,'description','Loan repayment paid'));end if;perform private.v4_journal_create(p_tenant_id,v.location_id,coalesce(p_payment_date,current_date),'Loan payment '||pno,'loan_payment_v491',pid,pno,lines);if p_device_id is not null and lower(coalesce(p_payment_method,''))='cash' then select id into v_shift from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_device_id and status='open' order by opened_at desc limit 1;if v_shift is not null then insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by) values(p_tenant_id,v_shift,case when v.direction='given' then 'cash_in' else 'cash_out' end,case when v.direction='given' then abs(amt) else -abs(amt) end,'loan_payment_v491',pid,pno,case when v.direction='given' then 'Loan collection' else 'Loan repayment' end,auth.uid());end if;end if;end if;
 perform private.loan_v490_refresh(p_tenant_id,p_loan_id);perform private.loan_v490_event(p_tenant_id,p_loan_id,'payment',case when v.direction='given' then 'Loan collection received' else 'Loan repayment paid' end,jsonb_build_object('amount',amt,'principal',tpr,'interest',ti,'penalty',tp,'direction',v.direction,'accounting_enabled',v.accounting_enabled));return jsonb_build_object('success',true,'payment_id',pid,'payment_number',pno,'direction',v.direction,'amount',amt,'principal_amount',tpr,'interest_amount',ti,'penalty_amount',tp);
end $$;
grant execute on function public.loan_payment_create_v491(uuid,uuid,numeric,date,text,text,text,uuid) to authenticated;

create or replace function public.loan_dashboard_v491(p_tenant_id uuid,p_location_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r jsonb;begin
 perform private.loan_v490_access(p_tenant_id,p_location_id,'loans.view','view');
 with scoped as (
   select l.*
   from public.loan_accounts_v490 l
   where l.tenant_id=p_tenant_id
     and (p_location_id is null or l.location_id=p_location_id)
     and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view')
 ), next_due as (
   select s.loan_id,min(s.due_date) due_date
   from public.loan_schedule_v490 s
   join scoped l on l.id=s.loan_id
   where s.status<>'waived'
     and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005
   group by s.loan_id
 ), pay_today as (
   select l.direction,coalesce(sum(p.amount),0) amount
   from public.loan_payments_v490 p join scoped l on l.id=p.loan_id
   where p.status<>'reversed' and p.payment_date=current_date
   group by l.direction
 )
 select jsonb_build_object(
   'total_loans',count(*),
   'active',count(*) filter(where status='active'),
   'defaulted',count(*) filter(where status='defaulted'),
   'given_active_principal',coalesce(sum(principal_outstanding) filter(where direction='given' and status in('active','defaulted')),0),
   'taken_active_principal',coalesce(sum(principal_outstanding) filter(where direction='taken' and status in('active','defaulted')),0),
   'receivable',coalesce(sum(principal_outstanding+interest_outstanding+penalty_outstanding) filter(where direction='given' and status in('active','defaulted')),0),
   'payable',coalesce(sum(principal_outstanding+interest_outstanding+penalty_outstanding) filter(where direction='taken' and status in('active','defaulted')),0),
   'total_outstanding',coalesce(sum(principal_outstanding+interest_outstanding+penalty_outstanding) filter(where status in('active','defaulted')),0),
   'overdue_loans',count(*) filter(where status in('active','defaulted') and exists(select 1 from next_due n where n.loan_id=scoped.id and n.due_date+grace_days<current_date)),
   'maturing_next_30_days',count(*) filter(where status in('active','defaulted') and maturity_date between current_date and current_date+30),
   'collected_today',coalesce((select amount from pay_today where direction='given'),0),
   'repaid_today',coalesce((select amount from pay_today where direction='taken'),0),
   'accounting_enabled',private.loan_v491_accounting_enabled(p_tenant_id)
 ) into r from scoped;
 return coalesce(r,'{}'::jsonb);
end $$;
grant execute on function public.loan_dashboard_v491(uuid,uuid) to authenticated;

create or replace function public.loan_payment_reverse_v491(p_tenant_id uuid,p_payment_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v public.loan_payments_v490%rowtype;a record;l public.loan_accounts_v490%rowtype;v_shift uuid;begin
 if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Reversal reason is required';end if;
 select * into v from public.loan_payments_v490 where tenant_id=p_tenant_id and id=p_payment_id for update;if not found then raise exception 'Loan payment not found';end if;
 select * into l from public.loan_accounts_v490 where id=v.loan_id and tenant_id=p_tenant_id;if not found then raise exception 'Loan not found';end if;
 perform private.loan_v490_access(p_tenant_id,v.location_id,'loans.manage','manage');
 if v.status='reversed' then return jsonb_build_object('success',true,'payment_id',v.id,'status','reversed','idempotent',true);end if;
 for a in select * from public.loan_payment_allocations_v490 where tenant_id=p_tenant_id and payment_id=p_payment_id loop
  update public.loan_schedule_v490 set principal_paid=greatest(principal_paid-a.principal_amount,0),interest_paid=greatest(interest_paid-a.interest_amount,0),penalty_paid=greatest(penalty_paid-a.penalty_amount,0),paid_at=null,updated_at=now() where id=a.schedule_id;
 end loop;
 if l.accounting_enabled then
  perform private.v4_reverse_source_journal(p_tenant_id,'loan_payment_v491',v.id,'loan_payment_reversal_v491','Reverse loan payment '||v.payment_number||' • '||trim(p_reason));
  if v.device_id is not null and lower(coalesce(v.payment_method,''))='cash' then
    select id into v_shift from public.cashier_shifts where tenant_id=p_tenant_id and device_id=v.device_id and status='open' order by opened_at desc limit 1;
    if v_shift is not null then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(p_tenant_id,v_shift,case when l.direction='given' then 'cash_out' else 'cash_in' end,case when l.direction='given' then -abs(v.amount) else abs(v.amount) end,'loan_payment_reversal_v491',v.id,v.payment_number,'Loan payment reversal: '||trim(p_reason),auth.uid());
    end if;
  end if;
 end if;
 update public.loan_payments_v490 set status='reversed',reversed_by=auth.uid(),reversed_at=now(),reversal_reason=trim(p_reason) where id=p_payment_id;
 perform private.loan_v490_refresh(p_tenant_id,v.loan_id);
 perform private.loan_v490_event(p_tenant_id,v.loan_id,'payment_reversed','Loan payment reversed: '||trim(p_reason),jsonb_build_object('payment_id',v.id,'payment_number',v.payment_number,'amount',v.amount,'direction',l.direction));
 return jsonb_build_object('success',true,'payment_id',v.id,'status','reversed');
end $$;
grant execute on function public.loan_payment_reverse_v491(uuid,uuid,text) to authenticated;

create or replace function public.loan_warnings_v491(p_tenant_id uuid,p_location_id uuid default null,p_limit int default 250)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r jsonb;begin
 perform private.loan_v490_access(p_tenant_id,p_location_id,'loans.view','view');
 select coalesce(jsonb_agg(x order by case x->>'severity' when 'danger' then 0 when 'warning' then 1 else 2 end,(x->>'event_date')::date),'[]'::jsonb) into r from (
  select jsonb_build_object('loan_id',l.id,'loan_number',l.loan_number,'client_name',coalesce(l.counterparty_name,c.name,s.name,'Party'),'direction',l.direction,'warning_type',case when sc.due_date is not null and current_date>sc.due_date+l.grace_days then 'overdue_payment' when l.maturity_date<=current_date+l.maturity_warning_days then 'maturity' when sc.due_date<=current_date+l.payment_warning_days then 'payment_due' when l.rate_type='variable' and l.next_rate_review_date<=current_date+l.payment_warning_days then 'rate_review' else 'status' end,'severity',case when sc.due_date is not null and current_date>sc.due_date+l.grace_days then 'danger' when l.status='defaulted' then 'danger' else 'warning' end,'event_date',coalesce(sc.due_date,l.maturity_date),'amount',coalesce(sc.balance,0),'message',case when l.direction='given' then 'Receivable loan requires attention' else 'Payable loan requires attention' end) x
  from public.loan_accounts_v490 l left join public.customers c on c.id=l.client_id left join public.suppliers s on s.id=l.supplier_id
  left join lateral(select z.due_date,round((z.principal_due+z.interest_due+z.penalty_due)-(z.principal_paid+z.interest_paid+z.penalty_paid),2) balance from public.loan_schedule_v490 z where z.loan_id=l.id and z.status<>'waived' and (z.principal_due+z.interest_due+z.penalty_due)-(z.principal_paid+z.interest_paid+z.penalty_paid)>0.005 order by z.due_date limit 1) sc on true
  where l.tenant_id=p_tenant_id and l.status in('active','defaulted') and (p_location_id is null or l.location_id=p_location_id) and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view') and (l.status='defaulted' or (sc.due_date is not null and sc.due_date<=current_date+l.payment_warning_days) or l.maturity_date<=current_date+l.maturity_warning_days or (l.rate_type='variable' and l.next_rate_review_date is not null and l.next_rate_review_date<=current_date+l.payment_warning_days)) limit least(greatest(coalesce(p_limit,250),1),1000)
 )q;
 return r;
end $$;
grant execute on function public.loan_warnings_v491(uuid,uuid,integer) to authenticated;


-- Pending Payments now classifies loans by direction: Given -> receivable, Taken -> payable.
create or replace function public.payments_party_summary_v491(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_query text default '',
  p_limit integer default 500
) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  v_receivables jsonb;
  v_payables jsonb;
  v_q text:='%'||lower(trim(coalesce(p_query,'')))||'%';
  v_limit int:=greatest(1,least(coalesce(p_limit,500),2000));
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_has_permission(p_tenant_id,'payments.view')
     and not private.erp_has_permission(p_tenant_id,'sales.manage')
     and not private.erp_has_permission(p_tenant_id,'purchases.manage')
     and not private.erp_user_is_owner(p_tenant_id) then
    raise exception 'Permission denied';
  end if;

  with sale_paid as (
    select sale_id,sum(amount)::numeric paid from public.sale_payments group by sale_id
  ), sale_returned as (
    select sale_id,sum(grand_total)::numeric returned
    from public.sales_returns where refund_status<>'waived' group by sale_id
  ), sale_docs as (
    select s.customer_id party_id,'sale'::text source_type,s.id source_id,
      coalesce(dn.terminal_number,ln.local_number,s.sale_number) reference,
      s.sale_date doc_date,s.due_date,
      s.grand_total::numeric total,coalesce(sp.paid,0)::numeric paid,
      greatest(s.grand_total-coalesce(sp.paid,0)-coalesce(sr.returned,0),0)::numeric balance,
      o.location_id,l.name location_name
    from public.sales s
    left join sale_paid sp on sp.sale_id=s.id
    left join sale_returned sr on sr.sale_id=s.id
    left join public.document_origins o on o.tenant_id=s.tenant_id and o.entity_type='sale' and o.entity_id=s.id
    left join public.business_locations l on l.id=o.location_id
    left join public.location_document_numbers ln on ln.entity_type='sale' and ln.entity_id=s.id
    left join public.device_document_numbers dn on dn.entity_type='sale' and dn.entity_id=s.id
    where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('cancelled','void')
      and greatest(s.grand_total-coalesce(sp.paid,0)-coalesce(sr.returned,0),0)>0.005
      and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
  ), loan_docs as (
    select l.client_id party_id,'loan'::text source_type,l.id source_id,l.loan_number reference,
      coalesce(l.disbursement_date,l.created_at::date) doc_date,
      coalesce((select min(s.due_date) from public.loan_schedule_v490 s
        where s.tenant_id=l.tenant_id and s.loan_id=l.id and s.status<>'waived'
          and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005),l.maturity_date) due_date,
      (l.principal_amount+l.interest_outstanding+l.penalty_outstanding)::numeric total,
      l.total_paid::numeric paid,
      (l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding)::numeric balance,
      l.location_id,bl.name location_name
    from public.loan_accounts_v490 l
    join public.business_locations bl on bl.id=l.location_id
    where l.tenant_id=p_tenant_id and coalesce(l.direction,'given')='given' and l.counterparty_type='customer' and l.status in('active','defaulted')
      and (l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding)>0.005
      and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view')
  ), customer_docs as (
    select * from sale_docs union all select * from loan_docs
  ), customer_rows as (
    select c.id party_id,'customer'::text party_type,c.name party_name,
      coalesce(c.tracking_code,'') tracking_code,coalesce(c.phone,'') phone,coalesce(c.email,'') email,
      round(sum(d.balance),2) balance,
      round(sum(case when d.source_type='sale' then d.balance else 0 end),2) sales_outstanding,
      round(sum(case when d.source_type='loan' then d.balance else 0 end),2) loan_outstanding,
      round(sum(case when d.due_date is not null and d.due_date<current_date then d.balance else 0 end),2) overdue,
      count(*)::int document_count,min(d.due_date) filter(where d.due_date>=current_date) next_due_date,
      max(d.doc_date) last_activity_date
    from customer_docs d join public.customers c on c.id=d.party_id and c.tenant_id=p_tenant_id
    where trim(coalesce(p_query,''))='' or lower(c.name) like v_q or lower(coalesce(c.tracking_code,'')) like v_q
      or lower(coalesce(c.phone,'')) like v_q or lower(coalesce(c.email,'')) like v_q
    group by c.id,c.name,c.tracking_code,c.phone,c.email
    order by sum(d.balance) desc,c.name
    limit v_limit
  )
  select coalesce(jsonb_agg(to_jsonb(r) order by r.balance desc,r.party_name),'[]'::jsonb)
  into v_receivables from customer_rows r;

  with purchase_paid as (
    select purchase_id,sum(amount)::numeric paid from public.purchase_payments group by purchase_id
  ), purchase_returned as (
    select purchase_id,sum(grand_total)::numeric returned
    from public.purchase_returns where credit_status<>'waived' group by purchase_id
  ), legacy_docs as (
    select p.supplier_id party_id,'purchase'::text source_type,p.id source_id,
      coalesce(dn.terminal_number,ln.local_number,p.purchase_number) reference,
      p.purchase_date doc_date,p.due_date,p.grand_total::numeric total,coalesce(pp.paid,0)::numeric paid,
      greatest(p.grand_total-coalesce(pp.paid,0)-coalesce(pr.returned,0),0)::numeric balance,
      o.location_id,l.name location_name
    from public.purchases p
    left join purchase_paid pp on pp.purchase_id=p.id
    left join purchase_returned pr on pr.purchase_id=p.id
    left join public.document_origins o on o.tenant_id=p.tenant_id and o.entity_type='purchase' and o.entity_id=p.id
    left join public.business_locations l on l.id=o.location_id
    left join public.location_document_numbers ln on ln.entity_type='purchase' and ln.entity_id=p.id
    left join public.device_document_numbers dn on dn.entity_type='purchase' and dn.entity_id=p.id
    where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('cancelled','void')
      and greatest(p.grand_total-coalesce(pp.paid,0)-coalesce(pr.returned,0),0)>0.005
      and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
  ), v2_docs as (
    select i.supplier_id party_id,'purchase_invoice'::text source_type,i.id source_id,
      i.invoice_number reference,i.invoice_date doc_date,i.due_date,i.grand_total::numeric total,
      i.paid_total::numeric paid,i.balance_due::numeric balance,i.location_id,l.name location_name
    from public.purchase_invoices_v484 i join public.business_locations l on l.id=i.location_id
    where i.tenant_id=p_tenant_id and i.status in('posted','part_paid') and i.balance_due>0.005
      and private.erp_document_scope_allowed(p_tenant_id,i.location_id,p_location_id,'view')
  ), taken_loan_docs as (
    select l.supplier_id party_id,'loan_taken'::text source_type,l.id source_id,l.loan_number reference,
      coalesce(l.disbursement_date,l.created_at::date) doc_date,
      coalesce((select min(sc.due_date) from public.loan_schedule_v490 sc where sc.loan_id=l.id and sc.status<>'waived' and (sc.principal_due+sc.interest_due+sc.penalty_due)-(sc.principal_paid+sc.interest_paid+sc.penalty_paid)>0.005),l.maturity_date) due_date,
      (l.principal_amount+l.interest_outstanding+l.penalty_outstanding)::numeric total,l.total_paid::numeric paid,
      (l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding)::numeric balance,l.location_id,bl.name location_name
    from public.loan_accounts_v490 l join public.business_locations bl on bl.id=l.location_id
    where l.tenant_id=p_tenant_id and l.direction='taken' and l.counterparty_type='supplier' and l.supplier_id is not null and l.status in('active','defaulted')
      and (l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding)>0.005
      and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view')
  ), supplier_docs as (
    select * from legacy_docs union all select * from v2_docs union all select * from taken_loan_docs
  ), supplier_credits as (
    select p.supplier_id,
      round(sum(greatest(p.amount-coalesce(a.allocated,0),0)),2)::numeric credit_balance
    from public.supplier_payments_v484 p
    left join (
      select supplier_payment_id,sum(amount)::numeric allocated
      from public.supplier_payment_allocations_v484 group by supplier_payment_id
    ) a on a.supplier_payment_id=p.id
    where p.tenant_id=p_tenant_id and p.status='posted'
      and private.erp_document_scope_allowed(p_tenant_id,p.location_id,p_location_id,'view')
    group by p.supplier_id
  ), supplier_rows as (
    select s.id party_id,'supplier'::text party_type,s.name party_name,
      coalesce(s.tracking_code,'') tracking_code,coalesce(s.phone,'') phone,coalesce(s.email,'') email,
      round(greatest(sum(d.balance)-coalesce(sc.credit_balance,0),0),2) balance,
      round(sum(case when d.source_type='purchase' then d.balance else 0 end),2) purchase_outstanding,
      round(sum(case when d.source_type='purchase_invoice' then d.balance else 0 end),2) invoice_outstanding,
      round(sum(case when d.source_type='loan_taken' then d.balance else 0 end),2) loan_outstanding,
      round(coalesce(sc.credit_balance,0),2) credit_balance,
      round(sum(case when d.due_date is not null and d.due_date<current_date then d.balance else 0 end),2) overdue,
      count(*)::int document_count,min(d.due_date) filter(where d.due_date>=current_date) next_due_date,
      max(d.doc_date) last_activity_date
    from supplier_docs d join public.suppliers s on s.id=d.party_id and s.tenant_id=p_tenant_id
    left join supplier_credits sc on sc.supplier_id=s.id
    where trim(coalesce(p_query,''))='' or lower(s.name) like v_q or lower(coalesce(s.tracking_code,'')) like v_q
      or lower(coalesce(s.phone,'')) like v_q or lower(coalesce(s.email,'')) like v_q
    group by s.id,s.name,s.tracking_code,s.phone,s.email,sc.credit_balance
    having greatest(sum(d.balance)-coalesce(sc.credit_balance,0),0)>0.005 or coalesce(sc.credit_balance,0)>0.005
    order by greatest(sum(d.balance)-coalesce(sc.credit_balance,0),0) desc,s.name
    limit v_limit
  )
  select coalesce(jsonb_agg(to_jsonb(r) order by r.balance desc,r.party_name),'[]'::jsonb)
  into v_payables from supplier_rows r;

  return jsonb_build_object(
    'receivables',v_receivables,
    'payables',v_payables,
    'totals',jsonb_build_object(
      'receivable',coalesce((select sum((x->>'balance')::numeric) from jsonb_array_elements(v_receivables) x),0),
      'payable',coalesce((select sum((x->>'balance')::numeric) from jsonb_array_elements(v_payables) x),0),
      'customer_count',jsonb_array_length(v_receivables),
      'supplier_count',jsonb_array_length(v_payables)
    )
  );
end $$;
grant execute on function public.payments_party_summary_v491(uuid,uuid,text,integer) to authenticated;

create or replace function public.payments_party_detail_v491(
  p_tenant_id uuid,
  p_party_type text,
  p_party_id uuid,
  p_location_id uuid default null
) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  v_party jsonb;
  v_documents jsonb:='[]'::jsonb;
  v_payments jsonb:='[]'::jsonb;
  v_credit numeric:=0;
  v_kind text:=lower(trim(coalesce(p_party_type,'')));
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_has_permission(p_tenant_id,'payments.view')
     and not private.erp_has_permission(p_tenant_id,'sales.manage')
     and not private.erp_has_permission(p_tenant_id,'purchases.manage')
     and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Permission denied';end if;

  if v_kind='customer' then
    select jsonb_build_object(
      'party_id',c.id,'party_type','customer','party_name',c.name,'tracking_code',coalesce(c.tracking_code,''),
      'phone',coalesce(c.phone,''),'email',coalesce(c.email,''),'tax_number',coalesce(c.tax_number,'')
    ) into v_party from public.customers c where c.tenant_id=p_tenant_id and c.id=p_party_id;
    if v_party is null then raise exception 'Customer not found';end if;

    with sale_paid as (
      select sale_id,sum(amount)::numeric paid from public.sale_payments group by sale_id
    ), sale_returned as (
      select sale_id,sum(grand_total)::numeric returned from public.sales_returns where refund_status<>'waived' group by sale_id
    ), docs as (
      select 'sale'::text source_type,s.id source_id,
        coalesce(dn.terminal_number,ln.local_number,s.sale_number) reference,s.sale_date doc_date,s.due_date,
        s.grand_total::numeric total,coalesce(sp.paid,0)::numeric paid,
        greatest(s.grand_total-coalesce(sp.paid,0)-coalesce(sr.returned,0),0)::numeric balance,
        coalesce(s.status,'') status,o.location_id,l.name location_name,
        jsonb_build_object('returned',coalesce(sr.returned,0),'sale_number',s.sale_number) extra
      from public.sales s
      left join sale_paid sp on sp.sale_id=s.id left join sale_returned sr on sr.sale_id=s.id
      left join public.document_origins o on o.tenant_id=s.tenant_id and o.entity_type='sale' and o.entity_id=s.id
      left join public.business_locations l on l.id=o.location_id
      left join public.location_document_numbers ln on ln.entity_type='sale' and ln.entity_id=s.id
      left join public.device_document_numbers dn on dn.entity_type='sale' and dn.entity_id=s.id
      where s.tenant_id=p_tenant_id and s.customer_id=p_party_id and coalesce(s.status,'') not in('cancelled','void')
        and greatest(s.grand_total-coalesce(sp.paid,0)-coalesce(sr.returned,0),0)>0.005
        and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
      union all
      select 'loan'::text,l.id,l.loan_number,coalesce(l.disbursement_date,l.created_at::date),
        coalesce((select min(sc.due_date) from public.loan_schedule_v490 sc where sc.tenant_id=l.tenant_id and sc.loan_id=l.id and sc.status<>'waived'
          and (sc.principal_due+sc.interest_due+sc.penalty_due)-(sc.principal_paid+sc.interest_paid+sc.penalty_paid)>0.005),l.maturity_date),
        (l.principal_amount+l.interest_outstanding+l.penalty_outstanding)::numeric,l.total_paid::numeric,
        (l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding)::numeric,l.status,l.location_id,bl.name,
        jsonb_build_object(
          'principal_outstanding',l.principal_outstanding,'interest_outstanding',l.interest_outstanding,
          'penalty_outstanding',l.penalty_outstanding,'interest_rate',l.interest_rate,'rate_type',l.rate_type,
          'maturity_date',l.maturity_date,'repayment_frequency',l.repayment_frequency,'repayment_term_count',l.repayment_term_count
        )
      from public.loan_accounts_v490 l join public.business_locations bl on bl.id=l.location_id
      where l.tenant_id=p_tenant_id and coalesce(l.direction,'given')='given' and l.client_id=p_party_id and l.status in('active','defaulted')
        and (l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding)>0.005
        and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view')
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'source_type',source_type,'source_id',source_id,'reference',reference,'date',doc_date,'due_date',due_date,
      'total',total,'paid',paid,'balance',balance,'status',status,'location_id',location_id,'location_name',location_name,
      'overdue',due_date is not null and due_date<current_date,'extra',extra
    ) order by coalesce(due_date,doc_date),doc_date),'[]'::jsonb) into v_documents from docs;

    with payments as (
      select coalesce(sp.paid_at,sp.created_at) ts,'sale_payment'::text payment_type,sp.id,
        coalesce(dn.terminal_number,ln.local_number,s.sale_number) reference,sp.amount::numeric amount,sp.payment_method,
        null::text payment_number,o.location_id,l.name location_name
      from public.sale_payments sp join public.sales s on s.id=sp.sale_id
      left join public.document_origins o on o.tenant_id=s.tenant_id and o.entity_type='sale' and o.entity_id=s.id
      left join public.business_locations l on l.id=o.location_id
      left join public.location_document_numbers ln on ln.entity_type='sale' and ln.entity_id=s.id
      left join public.device_document_numbers dn on dn.entity_type='sale' and dn.entity_id=s.id
      where s.tenant_id=p_tenant_id and s.customer_id=p_party_id
        and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
      union all
      select lp.created_at,'loan_payment',lp.id,la.loan_number,lp.amount,lp.payment_method,lp.payment_number,lp.location_id,bl.name
      from public.loan_payments_v490 lp join public.loan_accounts_v490 la on la.id=lp.loan_id
      join public.business_locations bl on bl.id=lp.location_id
      where lp.tenant_id=p_tenant_id and coalesce(la.direction,'given')='given' and la.client_id=p_party_id and lp.status='posted'
        and private.erp_document_scope_allowed(p_tenant_id,lp.location_id,p_location_id,'view')
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'payment_type',payment_type,'payment_id',id,'reference',reference,'payment_number',payment_number,
      'date',ts::date,'amount',amount,'payment_method',payment_method,'location_id',location_id,'location_name',location_name
    ) order by ts desc),'[]'::jsonb) into v_payments from (select * from payments order by ts desc limit 100) p;

  elsif v_kind='supplier' then
    select jsonb_build_object(
      'party_id',s.id,'party_type','supplier','party_name',s.name,'tracking_code',coalesce(s.tracking_code,''),
      'phone',coalesce(s.phone,''),'email',coalesce(s.email,''),'tax_number',coalesce(s.tax_number,'')
    ) into v_party from public.suppliers s where s.tenant_id=p_tenant_id and s.id=p_party_id;
    if v_party is null then raise exception 'Supplier not found';end if;

    with purchase_paid as (
      select purchase_id,sum(amount)::numeric paid from public.purchase_payments group by purchase_id
    ), purchase_returned as (
      select purchase_id,sum(grand_total)::numeric returned from public.purchase_returns where credit_status<>'waived' group by purchase_id
    ), docs as (
      select 'purchase'::text source_type,p.id source_id,
        coalesce(dn.terminal_number,ln.local_number,p.purchase_number) reference,p.purchase_date doc_date,p.due_date,
        p.grand_total::numeric total,coalesce(pp.paid,0)::numeric paid,
        greatest(p.grand_total-coalesce(pp.paid,0)-coalesce(pr.returned,0),0)::numeric balance,
        coalesce(p.status,'') status,o.location_id,l.name location_name,
        jsonb_build_object('returned',coalesce(pr.returned,0),'purchase_number',p.purchase_number) extra
      from public.purchases p
      left join purchase_paid pp on pp.purchase_id=p.id left join purchase_returned pr on pr.purchase_id=p.id
      left join public.document_origins o on o.tenant_id=p.tenant_id and o.entity_type='purchase' and o.entity_id=p.id
      left join public.business_locations l on l.id=o.location_id
      left join public.location_document_numbers ln on ln.entity_type='purchase' and ln.entity_id=p.id
      left join public.device_document_numbers dn on dn.entity_type='purchase' and dn.entity_id=p.id
      where p.tenant_id=p_tenant_id and p.supplier_id=p_party_id and coalesce(p.status,'') not in('cancelled','void')
        and greatest(p.grand_total-coalesce(pp.paid,0)-coalesce(pr.returned,0),0)>0.005
        and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
      union all
      select 'purchase_invoice'::text,i.id,i.invoice_number,i.invoice_date,i.due_date,i.grand_total,i.paid_total,i.balance_due,
        i.status,i.location_id,bl.name,
        jsonb_build_object('supplier_invoice_number',coalesce(i.supplier_invoice_number,''),'purchase_order_id',i.purchase_order_id)
      from public.purchase_invoices_v484 i join public.business_locations bl on bl.id=i.location_id
      where i.tenant_id=p_tenant_id and i.supplier_id=p_party_id and i.status in('posted','part_paid') and i.balance_due>0.005
        and private.erp_document_scope_allowed(p_tenant_id,i.location_id,p_location_id,'view')
      union all
      select 'loan_taken'::text,l.id,l.loan_number,coalesce(l.disbursement_date,l.created_at::date),
        coalesce((select min(sc.due_date) from public.loan_schedule_v490 sc where sc.loan_id=l.id and sc.status<>'waived' and (sc.principal_due+sc.interest_due+sc.penalty_due)-(sc.principal_paid+sc.interest_paid+sc.penalty_paid)>0.005),l.maturity_date),
        l.principal_amount+l.interest_outstanding+l.penalty_outstanding,l.total_paid,
        l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding,l.status,l.location_id,bl.name,
        jsonb_build_object('direction','taken','principal_outstanding',l.principal_outstanding,'interest_outstanding',l.interest_outstanding,'penalty_outstanding',l.penalty_outstanding,'interest_rate',l.interest_rate,'maturity_date',l.maturity_date)
      from public.loan_accounts_v490 l join public.business_locations bl on bl.id=l.location_id
      where l.tenant_id=p_tenant_id and l.direction='taken' and l.counterparty_type='supplier' and l.supplier_id=p_party_id and l.status in('active','defaulted')
        and (l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding)>0.005
        and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view')
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'source_type',source_type,'source_id',source_id,'reference',reference,'date',doc_date,'due_date',due_date,
      'total',total,'paid',paid,'balance',balance,'status',status,'location_id',location_id,'location_name',location_name,
      'overdue',due_date is not null and due_date<current_date,'extra',extra
    ) order by coalesce(due_date,doc_date),doc_date),'[]'::jsonb) into v_documents from docs;

    select coalesce(sum(greatest(p.amount-coalesce(a.allocated,0),0)),0) into v_credit
    from public.supplier_payments_v484 p
    left join (
      select supplier_payment_id,sum(amount)::numeric allocated from public.supplier_payment_allocations_v484 group by supplier_payment_id
    ) a on a.supplier_payment_id=p.id
    where p.tenant_id=p_tenant_id and p.supplier_id=p_party_id and p.status='posted'
      and private.erp_document_scope_allowed(p_tenant_id,p.location_id,p_location_id,'view');

    with payments as (
      select coalesce(pp.paid_at,pp.created_at) ts,'purchase_payment'::text payment_type,pp.id,
        coalesce(dn.terminal_number,ln.local_number,p.purchase_number) reference,pp.amount::numeric amount,pp.payment_method,
        null::text payment_number,o.location_id,l.name location_name
      from public.purchase_payments pp join public.purchases p on p.id=pp.purchase_id
      left join public.document_origins o on o.tenant_id=p.tenant_id and o.entity_type='purchase' and o.entity_id=p.id
      left join public.business_locations l on l.id=o.location_id
      left join public.location_document_numbers ln on ln.entity_type='purchase' and ln.entity_id=p.id
      left join public.device_document_numbers dn on dn.entity_type='purchase' and dn.entity_id=p.id
      where p.tenant_id=p_tenant_id and p.supplier_id=p_party_id
        and private.erp_document_scope_allowed(p_tenant_id,o.location_id,p_location_id,'view')
      union all
      select sp.created_at,'supplier_payment',sp.id,sp.reference_number,sp.amount,sp.payment_method,sp.payment_number,sp.location_id,bl.name
      from public.supplier_payments_v484 sp join public.business_locations bl on bl.id=sp.location_id
      where sp.tenant_id=p_tenant_id and sp.supplier_id=p_party_id and sp.status='posted'
        and private.erp_document_scope_allowed(p_tenant_id,sp.location_id,p_location_id,'view')
      union all
      select lp.created_at,'loan_repayment',lp.id,la.loan_number,lp.amount,lp.payment_method,lp.payment_number,lp.location_id,bl.name
      from public.loan_payments_v490 lp join public.loan_accounts_v490 la on la.id=lp.loan_id join public.business_locations bl on bl.id=lp.location_id
      where lp.tenant_id=p_tenant_id and la.direction='taken' and la.counterparty_type='supplier' and la.supplier_id=p_party_id and lp.status='posted'
        and private.erp_document_scope_allowed(p_tenant_id,lp.location_id,p_location_id,'view')
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'payment_type',payment_type,'payment_id',id,'reference',coalesce(reference,''),'payment_number',payment_number,
      'date',ts::date,'amount',amount,'payment_method',payment_method,'location_id',location_id,'location_name',location_name
    ) order by ts desc),'[]'::jsonb) into v_payments from (select * from payments order by ts desc limit 100) p;
  else
    raise exception 'Party type must be customer or supplier';
  end if;

  return jsonb_build_object(
    'party',v_party,
    'documents',v_documents,
    'recent_payments',v_payments,
    'gross_outstanding',coalesce((select sum((x->>'balance')::numeric) from jsonb_array_elements(v_documents) x),0),
    'credit_balance',round(coalesce(v_credit,0),2),
    'net_outstanding',greatest(coalesce((select sum((x->>'balance')::numeric) from jsonb_array_elements(v_documents) x),0)-coalesce(v_credit,0),0),
    'overdue',coalesce((select sum((x->>'balance')::numeric) from jsonb_array_elements(v_documents) x where coalesce((x->>'overdue')::boolean,false)),0)
  );
end $$;
grant execute on function public.payments_party_detail_v491(uuid,text,uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(195,'4.9.1','Bidirectional Loans','Adds Loans Given and Loans Taken, lender/borrower counterparties, loan payable/interest expense accounting and a business-level loan accounting switch.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.9.1 migration 195 applied' as status;

-- ============================================================================
-- MIGRATION 196: 196_v491_finance_reconciliation.sql
-- ============================================================================
-- THQ ERP v4.9.1 — financial reconciliation diagnostics and accounting cross-check.
begin;

create or replace function public.finance_reconciliation_v491(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  unbalanced bigint:=0;
  duplicate_journals bigint:=0;
  missing text[]:='{}';
  sales_missing bigint:=0;
  purchases_missing bigint:=0;
  purchase_invoices_missing bigint:=0;
  expenses_missing bigint:=0;
  sret_missing bigint:=0;
  pret_missing bigint:=0;
  loan_missing bigint:=0;
  sale_overpayments bigint:=0;
  purchase_overpayments bigint:=0;
  purchase_invoice_overpayments bigint:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) and not private.platform_v2_is_admin() then
    raise exception 'Access denied';
  end if;

  select count(*) into unbalanced
  from (
    select j.id
    from public.journal_entries j
    join public.journal_lines l on l.journal_entry_id=j.id
    where j.tenant_id=p_tenant_id and j.status='posted'
    group by j.id
    having abs(sum(coalesce(l.debit,0))-sum(coalesce(l.credit,0)))>0.005
  ) q;

  -- More than one posted journal for the same source indicates a double-posting risk.
  select count(*) into duplicate_journals
  from (
    select source_type,source_id
    from public.journal_entries
    where tenant_id=p_tenant_id and status='posted' and source_id is not null
    group by source_type,source_id
    having count(*)>1
  ) q;

  select array_agg(k) into missing
  from unnest(array[
    'sales_revenue','output_gst','accounts_receivable','inventory_asset','cogs',
    'accounts_payable','input_gst','operating_expense','rounding',
    'customer_credits','supplier_credits','loan_receivable','loan_payable',
    'loan_interest_income','loan_interest_expense','loan_penalty_income','loan_penalty_expense'
  ]) k
  where private.v4_account_id(p_tenant_id,k) is null;

  select count(*) into sales_missing
  from public.sales s
  where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('void','cancelled')
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='sale' and j.source_id=s.id and j.status='posted');

  select count(*) into purchases_missing
  from public.purchases p
  where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled')
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='purchase' and j.source_id=p.id and j.status='posted');

  select count(*) into purchase_invoices_missing
  from public.purchase_invoices_v484 p
  where p.tenant_id=p_tenant_id and p.status in('posted','part_paid','paid')
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='purchase_invoice_v484' and j.source_id=p.id and j.status='posted');

  select count(*) into expenses_missing
  from public.expenses e
  where e.tenant_id=p_tenant_id and e.status='posted'
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='expense' and j.source_id=e.id and j.status='posted');

  select count(*) into sret_missing
  from public.sales_returns r
  where r.tenant_id=p_tenant_id and coalesce(r.grand_total,0)>0 and coalesce(r.refund_status,'')<>'waived'
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='sales_return' and j.source_id=r.id and j.status='posted');

  select count(*) into pret_missing
  from public.purchase_returns r
  where r.tenant_id=p_tenant_id and coalesce(r.grand_total,0)>0 and coalesce(r.credit_status,'')<>'waived'
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='purchase_return' and j.source_id=r.id and j.status='posted');

  select count(*) into loan_missing
  from public.loan_accounts_v490 l
  where l.tenant_id=p_tenant_id and l.accounting_enabled and l.status in('active','closed','defaulted')
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_id=l.id and j.source_type in('loan_activation_v491','loan_disbursement_v490') and j.status='posted');

  select count(*) into sale_overpayments
  from public.sales s
  where s.tenant_id=p_tenant_id
    and coalesce((select sum(sp.amount) from public.sale_payments sp where sp.sale_id=s.id),0)>coalesce(s.grand_total,0)+0.01;

  select count(*) into purchase_overpayments
  from public.purchases p
  where p.tenant_id=p_tenant_id
    and coalesce((select sum(pp.amount) from public.purchase_payments pp where pp.purchase_id=p.id),0)>coalesce(p.grand_total,0)+0.01;

  select count(*) into purchase_invoice_overpayments
  from public.purchase_invoices_v484 p
  where p.tenant_id=p_tenant_id and coalesce(p.paid_total,0)>coalesce(p.grand_total,0)+0.01;

  return jsonb_build_object(
    'ok',unbalanced=0 and duplicate_journals=0 and cardinality(coalesce(missing,'{}'))=0
      and sales_missing=0 and purchases_missing=0 and purchase_invoices_missing=0 and expenses_missing=0
      and sret_missing=0 and pret_missing=0 and loan_missing=0
      and sale_overpayments=0 and purchase_overpayments=0 and purchase_invoice_overpayments=0,
    'unbalanced_journals',unbalanced,
    'duplicate_posted_source_journals',duplicate_journals,
    'missing_mappings',to_jsonb(coalesce(missing,'{}')),
    'operational_without_journal',jsonb_build_object(
      'sales',sales_missing,
      'purchases',purchases_missing,
      'purchase_invoices',purchase_invoices_missing,
      'expenses',expenses_missing,
      'sales_returns',sret_missing,
      'purchase_returns',pret_missing,
      'accounted_loans',loan_missing
    ),
    'overpayments',jsonb_build_object(
      'sales',sale_overpayments,
      'purchases',purchase_overpayments,
      'purchase_invoices',purchase_invoice_overpayments
    ),
    'checked_at',now()
  );
end $$;
grant execute on function public.finance_reconciliation_v491(uuid) to authenticated;

create or replace function public.finance_operations_health_v490(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  return public.finance_reconciliation_v491(p_tenant_id);
end $$;
grant execute on function public.finance_operations_health_v490(uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(196,'4.9.1','Finance Reconciliation','Cross-checks double-entry balance, duplicate source journals, accounting mappings, Sales/Purchase/Purchase Invoice/Expense/Return/Loan journal coverage and overpayments.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.9.1 migration 196 applied' as status;

-- ============================================================================
-- MIGRATION 197: 197_v491_release.sql
-- ============================================================================
-- THQ ERP v4.9.1 release contract.
begin;

-- v4.9.1 is additive/backward-compatible with the v4.9.0 desktop Client/POS.
-- New v4.9.1 applications require migration 197 through their local release contract,
-- while already-installed v4.9.0 clients are not needlessly blocked by the backend.
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
  select jsonb_build_object(
    'product','THQ ERP',
    'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
    'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
    'minimum_app_version','4.9.0',
    'release','Financial Integrity & Bidirectional Loans',
    'api_version','v1',
    'backward_compatible',true
  )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v491_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  miss text[]:='{}';
  p text;
  req text[]:=array[
    'sales_return_create_v483',
    'loan_create_v491','loan_update_v491','loan_activate_v491','loan_payment_create_v491','loan_payment_reverse_v491',
    'loan_list_v491','loan_detail_v491','loan_dashboard_v491','loan_warnings_v491',
    'loan_settings_v491_get','loan_settings_v491_set',
    'payments_party_summary_v491','payments_party_detail_v491',
    'finance_reconciliation_v491'
  ];
begin
  foreach p in array req loop
    if not exists(
      select 1 from pg_proc x join pg_namespace n on n.oid=x.pronamespace
      where n.nspname='public' and x.proname=p
    ) then
      miss:=array_append(miss,p);
    end if;
  end loop;

  if not exists(select 1 from public.accounting_account_mappings where mapping_key='customer_credits') then miss:=array_append(miss,'mapping.customer_credits');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='supplier_credits') then miss:=array_append(miss,'mapping.supplier_credits');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_receivable') then miss:=array_append(miss,'mapping.loan_receivable');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_payable') then miss:=array_append(miss,'mapping.loan_payable');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_interest_income') then miss:=array_append(miss,'mapping.loan_interest_income');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_interest_expense') then miss:=array_append(miss,'mapping.loan_interest_expense');end if;

  return jsonb_build_object(
    'ready',cardinality(miss)=0,
    'missing',to_jsonb(miss),
    'schema_version','4.9.1',
    'migration_no',197,
    'minimum_compatible_app','4.9.0',
    'sales_return_accounting_repaired',true,
    'bidirectional_loans',true,
    'loan_accounting_switch',true,
    'party_payment_center',true,
    'finance_reconciliation',true,
    'client_compact_ui',true
  );
end $$;
grant execute on function public.thq_v491_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(197,'4.9.1','Financial Integrity & Bidirectional Loans','Sales-return accounting repair, loans given/taken, module accounting switch, finance reconciliation, party payment integration and compact Client workspace UI.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.9.1 migration 197 release applied' as status;
