-- THQ ERP v4.9.1 / migration 197 post-upgrade verification
-- Run after applying the v4.9.1 migrations.

select public.thq_v491_verify() as v491_verification;

select migration_no,schema_version,release_name,applied_at
from public.thq_schema_releases
where migration_no between 194 and 197
order by migration_no;

-- These mappings must exist for every tenant.
select t.id as tenant_id,t.name as tenant_name,required.mapping_key
from public.tenants t
cross join (values
 ('customer_credits'),('supplier_credits'),
 ('loan_receivable'),('loan_interest_income'),('loan_penalty_income'),
 ('loan_payable'),('loan_interest_expense'),('loan_penalty_expense')
) required(mapping_key)
left join public.accounting_account_mappings m
  on m.tenant_id=t.id and m.mapping_key=required.mapping_key
where m.account_id is null
order by t.name,required.mapping_key;

-- Must return no rows: posted journals with debit/credit mismatch.
select j.tenant_id,j.id,j.journal_number,j.source_type,j.source_id,
       round(coalesce(sum(l.debit),0),2) total_debit,
       round(coalesce(sum(l.credit),0),2) total_credit
from public.journal_entries j
join public.journal_lines l on l.journal_entry_id=j.id
where j.status='posted'
group by j.tenant_id,j.id,j.journal_number,j.source_type,j.source_id
having abs(round(coalesce(sum(l.debit),0)-coalesce(sum(l.credit),0),2)) > 0.01
order by j.created_at desc;

-- Must return no rows: duplicate posted journals for one source transaction.
select tenant_id,source_type,source_id,count(*) posted_journals
from public.journal_entries
where status='posted' and source_type is not null and source_id is not null
group by tenant_id,source_type,source_id
having count(*)>1
order by count(*) desc;

-- Full operational/accounting reconciliation per tenant.
select t.id as tenant_id,t.name as tenant_name,public.finance_reconciliation_v491(t.id) as reconciliation
from public.tenants t
order by t.name;
