-- THQ ERP v7.2.1
-- Accounting UI Compaction & Historical Balance Accuracy
-- 1. Corrects sales/purchases historical payment status to 'Partially Paid'
-- 2. Aligns Journal catalog to: Date | Journal No. | Source Reference | Type | Debit | Credit | Status
-- 3. Provides explicit journal debit/credit totals and status handling (Balanced / Unbalanced / Reversed / Draft)

begin;

create or replace function private.accounting_rows_v702(t uuid,k text,f date,z date,loc uuid,filters jsonb) returns setof jsonb
language plpgsql stable set search_path='' as $$
declare r jsonb;v jsonb;pid uuid:=nullif(filters->>'party_id','')::uuid;acc uuid:=nullif(filters->>'account_id','')::uuid;
 tz text:=coalesce((select timezone from public.tenant_settings where tenant_id=t),'UTC');
begin
 if k in('sales','purchases') then
  for r in select x from private.reports_rows_v631(t,case k when 'sales' then 'sales_register' else 'purchase_register' end,f,z,loc) x loop
   select coalesce(jsonb_agg(j.id),'[]') into v from public.journal_entries j where j.tenant_id=t and private.reports_scope_v631(t,j.location_id,loc,'view')
    and j.source_type=case k when 'sales' then 'sale' else 'purchase' end and j.source_id=(r->>'id')::uuid;
   return next jsonb_build_object('id',r->>'id','date',coalesce(r->>'sale_date',r->>'purchase_date'),'reference',coalesce(r->>'sale_number',r->>'purchase_number'),
    'party',coalesce(r->>'customer_name',r->>'supplier_name'),'party_id',coalesce(r->>'customer_id',r->>'supplier_id'),'total',r->'grand_total','paid',r->'paid_as_of','due',r->'outstanding',
    'payment_status',case when (r->>'outstanding')::numeric<=0.005 then 'Paid' when (r->>'paid_as_of')::numeric>0.005 then 'Partially Paid' else 'Unpaid' end,
    'overdue',coalesce((r->>'outstanding')::numeric>0.005 and nullif(r->>'due_date','')::date<z,false),'document_status',r->>'status',
    'source_type',case k when 'sales' then 'sale' else 'purchase' end,'source_id',r->>'id','document_type',case k when 'sales' then 'sale' else 'purchase' end,'document_id',r->>'id',
    'journal_ids',v,'accounting_status',case when jsonb_array_length(v)=0 then 'Posting missing' else 'Posted' end,'saved_items',r->'saved_items','returns',r->'returns_through_to',
    'payments',r->'payments_through_to','gst_snapshot',r->'gst_snapshot','invoice_evidence',r->'saved_load_invoice');
  end loop;
  if k='purchases' then
   for r in select to_jsonb(p)||jsonb_build_object('supplier_name',s.name,
    'paid_as_of',coalesce((select sum(a.amount) from public.supplier_payment_allocations_v484 a join public.supplier_payments_v484 sp on sp.id=a.supplier_payment_id and sp.tenant_id=t where a.purchase_invoice_id=p.id and sp.status='posted' and sp.payment_date<=z),0))
    from public.purchase_invoices_v484 p left join public.suppliers s on s.tenant_id=t and s.id=p.supplier_id
    where p.tenant_id=t and p.status in('posted','part_paid','paid') and p.invoice_date between f and z and private.reports_scope_v631(t,p.location_id,loc,'view') loop
    return next jsonb_build_object('id',r->>'id','date',r->>'invoice_date','reference',r->>'invoice_number','party',r->>'supplier_name','party_id',r->>'supplier_id',
     'total',r->'grand_total','paid',r->'paid_as_of','due',greatest((r->>'grand_total')::numeric-(r->>'paid_as_of')::numeric,0),
     'payment_status',case when (r->>'paid_as_of')::numeric>=(r->>'grand_total')::numeric-0.005 then 'Paid' when (r->>'paid_as_of')::numeric>0.005 then 'Partially Paid' else 'Unpaid' end,
     'document_status',r->>'status','source_type','purchase_invoice_v484','source_id',r->>'id','document_type','purchase_invoice_v484','document_id',r->>'id','supplier_invoice',r->>'supplier_invoice_number');
   end loop;
  end if;
 elsif k='journal' then
  return query with grouped as (
   select j.*,bl.name location_name,private.accounting_source_v702(t,j.source_type,j.source_id) src,
    coalesce(sum(l.debit),0) debit,coalesce(sum(l.credit),0) credit,count(l.id) line_count,
    coalesce(string_agg(distinct coalesce(c.name,s.name,m.name,cost.payee),', '),'') party,
    coalesce(jsonb_agg(jsonb_build_object('account_id',a.id,'account_name',a.name,'account_code',a.code,'account_type',a.account_type,'party_id',l.party_id,'party_type',l.party_type,
    'description',l.description,'debit',l.debit,'credit',l.credit,'payment_method',private.accounting_money_method_v702(t,a.id),'party',coalesce(c.name,s.name,m.name,cost.payee,'')) order by a.code,l.id) filter(where l.id is not null),'[]') lines
   from public.journal_entries j left join public.journal_lines l on l.journal_entry_id=j.id
   left join public.accounting_accounts a on a.id=l.account_id and a.tenant_id=t
   left join public.business_locations bl on bl.id=j.location_id and bl.tenant_id=t
   left join public.customers c on c.tenant_id=t and c.id=l.party_id and l.party_type='customer'
   left join public.suppliers s on s.tenant_id=t and s.id=l.party_id and l.party_type='supplier'
   left join public.staff_members_v630 m on m.tenant_id=t and m.id=l.party_id and l.party_type='staff'
   left join public.material_load_costs_v630 cost on cost.tenant_id=t and cost.id=l.party_id and l.party_type='load_cost'
   where j.tenant_id=t and j.entry_date between f and z and private.reports_scope_v631(t,j.location_id,loc,'view') group by j.id,bl.name)
  select jsonb_build_object('id',g.id,'journal_id',g.id,'date',g.entry_date,'created_at',g.created_at,'reference',coalesce(g.source_reference,g.entry_number),
   'entry_number',g.entry_number,'source_reference',coalesce(g.source_reference,''),'source_type',coalesce(g.source_type,'unknown'),'type',initcap(replace(coalesce(g.source_type,'unknown'),'_',' ')),
   'source_id',g.source_id,'description',g.description,'party',coalesce(nullif(g.party,''),g.src->>'party',''),
   'status',case when g.status='reversed' then 'Reversed' when g.status='draft' then 'Draft' when g.line_count>=2 and abs(g.debit-g.credit)<=0.005 then 'Balanced' else 'Unbalanced' end,
   'posting_status',g.status,'amount',g.debit,
   'debit',g.debit,'credit',g.credit,'difference',g.debit-g.credit,'balance_status',case when g.line_count>=2 and abs(g.debit-g.credit)<=0.005 then 'Balanced' else 'Unbalanced' end,
   'lines',g.lines,'location',g.location_name,'reversal_of',g.reversal_of,'reversals',(select coalesce(jsonb_agg(jsonb_build_object('journal_id',x.id,'reference',x.entry_number,'status',x.status)),'[]') from public.journal_entries x where x.tenant_id=t and x.reversal_of=g.id and private.reports_scope_v631(t,x.location_id,loc,'view')))||g.src
   from grouped g order by g.entry_date desc,g.created_at desc,g.id;
 elsif k in('general_ledger','cash','bank') then
  return query with raw as(select x from private.accounting_lines_v702(t,z,loc) x
   where (acc is null or x->>'account_id'=acc::text) and (k='general_ledger' or (k='cash' and x->>'money_method'='cash') or (k='bank' and x->>'money_method' in('bank','upi','card')))),
  grouped as(select x->>'journal_id' jid,case when k='cash' and acc is null then 'cash_total' else x->>'account_id' end aid,min(x::text)::jsonb sample,jsonb_agg(distinct x->>'account_id') cash_accounts,sum((x->>'debit')::numeric) debit,sum((x->>'credit')::numeric) credit from raw group by x->>'journal_id',case when k='cash' and acc is null then 'cash_total' else x->>'account_id' end),
  running as(select *,coalesce(sum(debit-credit) filter(where (sample->>'date')::date<f) over(partition by aid),0) opening,
   sum(debit-credit) over(partition by aid order by (sample->>'date')::date,sample->>'created_at',jid rows unbounded preceding) balance from grouped)
  select sample||jsonb_build_object('id',jid||':'||aid,'type',initcap(replace(sample->>'source_type','_',' ')),
   'account_id',case when aid='cash_total' then null else aid end,'cash_accounts',cash_accounts,'debit',debit,'credit',credit,'money_in',greatest(debit-credit,0),'money_out',greatest(credit-debit,0),'opening',opening,'balance',balance)
  from running where (sample->>'date')::date>=f order by (sample->>'date')::date,sample->>'created_at',jid,aid;
 elsif k in('customers','suppliers') then
  if pid is null then return;end if;
  return query with lines as(select x from private.accounting_lines_v702(t,z,loc) x),
  groups as(select x->>'journal_id' jid,min(x::text)::jsonb sample,
   count(distinct x->>'party_id') filter(where x->>'party_type'=case k when 'customers' then 'customer' else 'supplier' end) party_count,
   coalesce(sum(case when x->>'money_method'<>'' and x->>'party_id'=pid::text then case when k='customers' then (x->>'debit')::numeric-(x->>'credit')::numeric else (x->>'credit')::numeric-(x->>'debit')::numeric end else 0 end),0) tagged_money,
   coalesce(sum(case when x->>'party_id'=pid::text and ((k='customers' and x->>'system_key' in('accounts_receivable','customer_credits')) or (k='suppliers' and x->>'system_key' in('accounts_payable','supplier_credits'))) then
    case when k='customers' then (x->>'debit')::numeric-(x->>'credit')::numeric else (x->>'credit')::numeric-(x->>'debit')::numeric end else 0 end),0) delta,
   coalesce(sum(case when x->>'money_method'<>'' then case when k='customers' then (x->>'debit')::numeric-(x->>'credit')::numeric else (x->>'credit')::numeric-(x->>'debit')::numeric end else 0 end),0) money,
   bool_or((x->>'party_id'=pid::text and x->>'party_type'=case k when 'customers' then 'customer' else 'supplier' end and ((k='customers' and x->>'system_key' in('accounts_receivable','customer_credits')) or (k='suppliers' and x->>'system_key' in('accounts_payable','supplier_credits')))) or x->>case k when 'customers' then 'customer_id' else 'supplier_id' end=pid::text) belongs
   from lines group by x->>'journal_id'),
  balances as(select jid,sample,delta,belongs,case when party_count>1 then tagged_money else money end money,coalesce(sum(delta) filter(where (sample->>'date')::date<f) over(),0) opening,
   sum(delta) over(order by (sample->>'date')::date,sample->>'created_at',jid rows unbounded preceding) balance from groups where belongs)
  select sample||jsonb_build_object('id',jid,'party_id',pid,'type',initcap(replace(sample->>'source_type','_',' ')),
   'document_amount',case when (k='customers' and sample->>'source_type'='sale') or (k='suppliers' and sample->>'source_type' in('purchase','purchase_invoice_v484')) then coalesce((sample->>'document_total')::numeric,0) else 0 end,
   'money_amount',money,'adjustment',delta-case when (k='customers' and sample->>'source_type'='sale') or (k='suppliers' and sample->>'source_type' in('purchase','purchase_invoice_v484')) then coalesce((sample->>'document_total')::numeric,0) else 0 end+money,
   'opening',opening,'balance',balance,'balance_label',case when abs(balance)<=0.005 then 'Settled' when balance<0 then 'Advance / credit' else 'Outstanding' end,'payment_status',case when abs(balance)<=0.005 then 'Settled' when balance<0 then 'Advance / credit' else 'Outstanding' end)
  from balances where (sample->>'date')::date>=f order by (sample->>'date')::date,sample->>'created_at',jid;
 elsif k in('trial_balance','profit_loss','balance_sheet') then
  return query with raw as(select x from private.accounting_lines_v702(t,z,loc) x),
  accounts as(select x->>'account_id' aid,min(x::text)::jsonb sample,
   coalesce(sum((x->>'debit')::numeric-(x->>'credit')::numeric) filter(where (x->>'date')::date<f),0) opening,
   coalesce(sum((x->>'debit')::numeric) filter(where (x->>'date')::date>=f),0) debit,
   coalesce(sum((x->>'credit')::numeric) filter(where (x->>'date')::date>=f),0) credit,
   sum((x->>'debit')::numeric-(x->>'credit')::numeric) closing from raw group by x->>'account_id')
  select jsonb_build_object('id',aid,'account_id',aid,'account_name',sample->>'account_name','account_type',sample->>'account_type','account_group',sample->>'account_group',
   'group',case sample->>'account_type' when 'income' then 'Revenue' when 'cogs' then 'Cost of Goods Sold' when 'expense' then 'Operating Expenses' when 'asset' then 'Assets' when 'liability' then 'Liabilities' when 'equity' then 'Equity' else 'Other' end,
   'subgroup',case when sample->>'account_type'='asset' then case when sample->>'money_method'<>'' or sample->>'system_key' in('accounts_receivable','inventory_asset','supplier_credits') then 'Current Assets' else 'Other Assets' end when sample->>'account_type'='liability' then 'Liabilities' else sample->>'account_group' end,
   'opening',opening,'debit',debit,'credit',credit,'closing',closing,'closing_debit',greatest(closing,0),'closing_credit',greatest(-closing,0),
   'amount',case when k='profit_loss' then case when sample->>'account_type'='income' then credit-debit else debit-credit end else case when sample->>'account_type'='asset' then closing else -closing end end)
   from accounts where k='trial_balance' or (k='profit_loss' and sample->>'account_type' in('income','cogs','expense')) or (k='balance_sheet' and sample->>'account_type' in('asset','liability','equity'))
   order by case sample->>'account_type' when 'asset' then 1 when 'liability' then 2 when 'equity' then 3 when 'income' then 1 when 'cogs' then 2 when 'expense' then 3 else 4 end,sample->>'account_code',aid;
 elsif k='gst' then
  for r in select x from private.reports_rows_v631(t,'tax',f,z,loc) x loop
   v:=coalesce(r->'saved_snapshot','{}');
   if v->>'tax_mode'='non_gst' then continue;end if;
   if r->>'verification'='legacy_unverified' and coalesce((r->>'tax_collected_total')::numeric,0)=0 then continue;end if;
   return next jsonb_build_object('id',coalesce(v->>'id',r->>'source_number'),'date',r->>'document_date','reference',r->>'source_number',
    'party',coalesce(v#>>'{quote_payload,recipient,legal_name}',v#>>'{quote_payload,supplier,legal_name}',v->>'customer_name',v->>'supplier_name', (select c.name from public.customers c join public.sales sale on sale.customer_id=c.id and sale.tenant_id=t where c.tenant_id=t and sale.id=nullif(v->>'source_id','')::uuid), (select sup.name from public.suppliers sup join public.purchases pur on pur.supplier_id=sup.id and pur.tenant_id=t where sup.tenant_id=t and pur.id=nullif(v->>'source_id','')::uuid),''),
    'taxable',coalesce((r->>'taxable_total')::numeric,0)*coalesce((r->>'document_sign')::numeric,1),'cgst',(r->>'cgst_total')::numeric*coalesce((r->>'document_sign')::numeric,1),'sgst',(r->>'sgst_total')::numeric*coalesce((r->>'document_sign')::numeric,1),'igst',(r->>'igst_total')::numeric*coalesce((r->>'document_sign')::numeric,1),'utgst',(r->>'utgst_total')::numeric*coalesce((r->>'document_sign')::numeric,1),'cess',(r->>'cess_total')::numeric*coalesce((r->>'document_sign')::numeric,1),'gst_total',coalesce((r->>'tax_collected_total')::numeric,0)*coalesce((r->>'document_sign')::numeric,1),
    'direction',r->>'direction','document_sign',r->'document_sign','verification',r->>'verification','source_type',v->>'source_type','source_id',v->>'source_id',
    'interstate',v->'interstate','registration_status',case when nullif(v->>case when r->>'direction'='outward' then 'recipient_gstin' else 'supplier_gstin' end,'') is null then 'Unregistered' else 'Registered' end,
    'rates',(select coalesce(jsonb_agg(distinct x->'gst_rate'),'[]') from jsonb_array_elements(coalesce(v->'lines','[]')) x),
    'snapshot',v,'amount',coalesce((r->>'tax_collected_total')::numeric,0)*coalesce((r->>'document_sign')::numeric,1),'tax_mode',v->>'tax_mode')||private.accounting_source_v702(t,coalesce(v->>'source_type',case r->>'document_kind' when 'invoice' then 'sale' when 'bill' then 'purchase' else r->>'document_kind' end),coalesce(nullif(v->>'source_id',''),nullif(v->>'id',''))::uuid);
  end loop;
 elsif k='cash_flow' then
  return query with raw as(select x from private.accounting_lines_v702(t,z,loc) x where (x->>'date')::date>=f),
  grouped as(select x->>'journal_id' jid,min(x::text)::jsonb sample,
   coalesce(sum((x->>'debit')::numeric-(x->>'credit')::numeric) filter(where x->>'money_method' in('cash','bank')),0) movement,
   count(*) filter(where x->>'money_method'='cash') cash_lines,
   bool_or(x->>'account_type' in('income','expense','cogs') or x->>'system_key' in('accounts_receivable','accounts_payable','inventory_asset','staff_payable_v630','load_costs_payable_v630')) operating,
   bool_or(x->>'account_type'='equity' or x->>'system_key' ilike '%loan%') financing,
   bool_or(x->>'account_type'='asset' and x->>'money_method'='' and x->>'system_key' not in('accounts_receivable','inventory_asset','supplier_credits')) investing,
   bool_or(x->>'money_method' in('upi','card')) clearing
   from raw group by x->>'journal_id')
  select sample||jsonb_build_object('id',jid,'amount',movement,'money_in',greatest(movement,0),'money_out',greatest(-movement,0),
   'group',case when clearing then 'Unclassified clearing movement' when financing and operating then 'Unclassified mixed activity' when financing then 'Financing Activities' when investing and operating then 'Unclassified mixed activity' when investing then 'Investing Activities' when operating then 'Operating Activities' else 'Unclassified Activities' end)
   from grouped where abs(movement)>0.000001 order by (sample->>'date')::date,sample->>'created_at',jid;
 end if;
 return;
end $$;

create or replace function private.accounting_workspace_v702(t uuid,k text,f date,z date,loc uuid,q text,filters jsonb,sort_key text,sort_desc boolean,page_offset integer,page_limit integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare raw jsonb:='[]';matched jsonb:='[]';paged jsonb:='[]';summary jsonb:='[]';alerts jsonb:='[]';options jsonb;columns jsonb;
 r jsonb;v jsonb;entry record;key text;amt numeric:=0;opening numeric:=0;closing numeric:=0;net numeric:=0;
 revenue numeric:=0;cogs numeric:=0;expenses numeric:=0;assets numeric:=0;liabilities numeric:=0;equity numeric:=0;earnings numeric:=0;
 tax_mode text;account_id uuid:=nullif(filters->>'account_id','')::uuid;party_id uuid:=nullif(filters->>'party_id','')::uuid;
 catalog jsonb:='{"sales": [{"key": "date", "label": "Date", "type": "date"}, {"key": "reference", "label": "Invoice", "type": "text"}, {"key": "party", "label": "Customer", "type": "text"}, {"key": "total", "label": "Total", "type": "money"}, {"key": "paid", "label": "Paid", "type": "money"}, {"key": "due", "label": "Due", "type": "money"}, {"key": "payment_status", "label": "Status", "type": "text"}], "purchases": [{"key": "date", "label": "Date", "type": "date"}, {"key": "reference", "label": "Purchase", "type": "text"}, {"key": "party", "label": "Supplier", "type": "text"}, {"key": "total", "label": "Total", "type": "money"}, {"key": "paid", "label": "Paid", "type": "money"}, {"key": "due", "label": "Due", "type": "money"}, {"key": "payment_status", "label": "Status", "type": "text"}], "cash": [{"key": "date", "label": "Date", "type": "date"}, {"key": "reference", "label": "Reference", "type": "text"}, {"key": "type", "label": "Type", "type": "text"}, {"key": "party", "label": "Party / Description", "type": "text"}, {"key": "money_in", "label": "Cash In", "type": "money"}, {"key": "money_out", "label": "Cash Out", "type": "money"}, {"key": "balance", "label": "Balance", "type": "money"}], "bank": [{"key": "date", "label": "Date", "type": "date"}, {"key": "account_name", "label": "Account", "type": "text"}, {"key": "reference", "label": "Reference", "type": "text"}, {"key": "party", "label": "Party", "type": "text"}, {"key": "type", "label": "Type", "type": "text"}, {"key": "money_in", "label": "Money In", "type": "money"}, {"key": "money_out", "label": "Money Out", "type": "money"}, {"key": "balance", "label": "Balance", "type": "money"}], "customers": [{"key": "date", "label": "Date", "type": "date"}, {"key": "reference", "label": "Reference", "type": "text"}, {"key": "type", "label": "Type", "type": "text"}, {"key": "description", "label": "Details", "type": "text"}, {"key": "document_amount", "label": "Invoice", "type": "money"}, {"key": "money_amount", "label": "Received", "type": "money"}, {"key": "balance", "label": "Balance", "type": "money"}], "suppliers": [{"key": "date", "label": "Date", "type": "date"}, {"key": "reference", "label": "Reference", "type": "text"}, {"key": "type", "label": "Type", "type": "text"}, {"key": "description", "label": "Details", "type": "text"}, {"key": "document_amount", "label": "Purchase", "type": "money"}, {"key": "money_amount", "label": "Paid", "type": "money"}, {"key": "balance", "label": "Balance", "type": "money"}], "journal": [{"key": "date", "label": "Date", "type": "date"}, {"key": "entry_number", "label": "Journal No.", "type": "text"}, {"key": "source_reference", "label": "Source Reference", "type": "text"}, {"key": "type", "label": "Type", "type": "text"}, {"key": "debit", "label": "Debit", "type": "money"}, {"key": "credit", "label": "Credit", "type": "money"}, {"key": "status", "label": "Status", "type": "text"}], "general_ledger": [{"key": "date", "label": "Date", "type": "date"}, {"key": "reference", "label": "Reference", "type": "text"}, {"key": "description", "label": "Description", "type": "text"}, {"key": "debit", "label": "Debit", "type": "money"}, {"key": "credit", "label": "Credit", "type": "money"}, {"key": "balance", "label": "Running Balance", "type": "money"}], "gst": [{"key": "date", "label": "Date", "type": "date"}, {"key": "reference", "label": "Invoice", "type": "text"}, {"key": "party", "label": "Party", "type": "text"}, {"key": "taxable", "label": "Taxable Value", "type": "money"}, {"key": "cgst", "label": "CGST", "type": "money"}, {"key": "sgst", "label": "SGST", "type": "money"}, {"key": "igst", "label": "IGST", "type": "money"}, {"key": "gst_total", "label": "Total GST", "type": "money"}, {"key": "direction", "label": "Type", "type": "text"}], "profit_loss": [{"key": "group", "label": "Group", "type": "text"}, {"key": "account_name", "label": "Account", "type": "text"}, {"key": "amount", "label": "Amount", "type": "money"}], "balance_sheet": [{"key": "group", "label": "Group", "type": "text"}, {"key": "account_name", "label": "Account", "type": "text"}, {"key": "amount", "label": "Amount", "type": "money"}], "cash_flow": [{"key": "group", "label": "Activity", "type": "text"}, {"key": "reference", "label": "Reference", "type": "text"}, {"key": "description", "label": "Description", "type": "text"}, {"key": "money_in", "label": "Money In", "type": "money"}, {"key": "money_out", "label": "Money Out", "type": "money"}, {"key": "amount", "label": "Net Movement", "type": "money"}], "overview": [{"key": "label", "label": "Metric", "type": "text"}, {"key": "amount", "label": "Amount", "type": "money"}, {"key": "basis", "label": "Basis", "type": "text"}], "trial_balance": [{"key": "account_name", "label": "Account", "type": "text"}, {"key": "opening", "label": "Opening (signed DR)", "type": "money"}, {"key": "debit", "label": "Period Debit", "type": "money"}, {"key": "credit", "label": "Period Credit", "type": "money"}, {"key": "closing", "label": "Closing (signed DR)", "type": "money"}]}'::jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in is required' using errcode='42501';end if;
 begin perform private.v500_accounting_access(t,false); exception when raise_exception then raise exception 'Accounting access denied' using errcode='42501';end;
 if f is null or z is null or f>z then raise exception 'Choose a valid date range' using errcode='22023';end if;
 if page_offset is null or page_offset<0 or page_limit is null or page_limit<1 or page_limit>1000 then raise exception 'Invalid page size' using errcode='22023';end if;
 if jsonb_typeof(coalesce(filters,'{}'))<>'object' then raise exception 'Invalid filters' using errcode='22023';end if;
 if loc is not null and not private.reports_scope_v631(t,loc,loc,'view') then raise exception 'Store access denied' using errcode='42501';end if;
 if not catalog ? k then raise exception 'Unsupported accounting report' using errcode='22023';end if;
 for key in select jsonb_object_keys(coalesce(filters,'{}')) loop
  if key not in('account_id','party_id','payment_method','source_type','status','payment_status','balance_status','amount_min','amount_max','account_group','direction','registration_status','interstate','gst_rate','journal_id','document_id','overdue') then raise exception 'Unsupported filter: %',key using errcode='22023';end if;
 end loop;
 if account_id is not null and not exists(select 1 from public.accounting_accounts where tenant_id=t and id=account_id) then raise exception 'Account not found' using errcode='42501';end if;
 if party_id is not null and ((k='customers' and not exists(select 1 from public.customers where tenant_id=t and id=party_id)) or (k='suppliers' and not exists(select 1 from public.suppliers where tenant_id=t and id=party_id))) then raise exception 'Party not found' using errcode='42501';end if;
 columns:=catalog->k;
 if sort_key is not null and sort_key not in('source_type','amount','date','reference','party','entry_number','source_reference','debit','credit') and not exists(select 1 from jsonb_array_elements(columns) x where x->>'key'=sort_key) then raise exception 'Invalid sort column' using errcode='22023';end if;
 tax_mode:=private.gst_tax_mode_resolve_v520(t,z);
 -- Only metadata; the data rows below always enforce document location access.
 options:=jsonb_build_object('accounts',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'code',a.code,'type',a.account_type,'group',coalesce(p.name,a.account_type),'active',a.active,'method',private.accounting_money_method_v702(t,a.id)) order by a.code),'[]') from public.accounting_accounts a left join public.accounting_accounts p on p.id=a.parent_id and p.tenant_id=t where a.tenant_id=t),
 'customers',(select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name),'[]') from public.customers c where c.tenant_id=t),
 'suppliers',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name),'[]') from public.suppliers s where s.tenant_id=t),
 'parties',(select coalesce(jsonb_agg(p order by p->>'name'),'[]') from (select jsonb_build_object('id',id,'name',name||' · Customer') p from public.customers where tenant_id=t union all select jsonb_build_object('id',id,'name',name||' · Supplier') from public.suppliers where tenant_id=t union all select jsonb_build_object('id',id,'name',name||' · Staff') from public.staff_members_v630 where tenant_id=t) party_options),
 'sources',(select coalesce(jsonb_agg(x.source_type order by x.source_type),'[]') from (select distinct coalesce(j.source_type,'unknown') source_type from public.journal_entries j where j.tenant_id=t and private.reports_scope_v631(t,j.location_id,loc,'view')) x));
 if k='overview' then
  select coalesce(sum(case when x->>'account_type'='income' and (x->>'date')::date>=f then (x->>'credit')::numeric-(x->>'debit')::numeric else 0 end),0),
   coalesce(sum(case when x->>'account_type'='cogs' and (x->>'date')::date>=f then (x->>'debit')::numeric-(x->>'credit')::numeric else 0 end),0),
   coalesce(sum(case when x->>'account_type'='expense' and (x->>'date')::date>=f then (x->>'debit')::numeric-(x->>'credit')::numeric else 0 end),0)
   into revenue,cogs,expenses from private.accounting_lines_v702(t,z,loc) x;
  for entry in select * from (values ('sales','Sales','period'),('purchases','Purchases','period'),('receivables','Receivables','as_of'),('payables','Payables','as_of'),('cash','Cash','as_of'),('bank','Bank / UPI / Card','as_of'),('revenue','Revenue','period'),('expenses','Operating Expenses','period'),('net_profit','Profit / Loss','period'),('gst_payable','GST Payable / (Receivable)','as_of')) metrics(key,label,basis) loop
   amt:=0;
   if entry.key in('sales','purchases') then select coalesce(sum((x->>'total')::numeric),0) into amt from private.accounting_rows_v702(t,entry.key,f,z,loc,'{}') x;
   elsif entry.key='revenue' then amt:=revenue;
   elsif entry.key='expenses' then amt:=expenses;
   elsif entry.key='net_profit' then amt:=revenue-cogs-expenses;
   else select coalesce(sum(case when entry.key in('payables','gst_payable') then (x->>'credit')::numeric-(x->>'debit')::numeric else (x->>'debit')::numeric-(x->>'credit')::numeric end),0) into amt from private.accounting_lines_v702(t,z,loc) x
    where (entry.key='receivables' and x->>'system_key' in('accounts_receivable','customer_credits')) or (entry.key='payables' and x->>'system_key' in('accounts_payable','supplier_credits'))
     or (entry.key='cash' and x->>'money_method'='cash') or (entry.key='bank' and x->>'money_method' in('bank','upi','card'))
     or (entry.key='gst_payable' and private.gst_v520_account_family(x->>'system_key') is not null);
   end if;
   raw:=raw||jsonb_build_array(jsonb_build_object('id',entry.key,'label',entry.label,'amount',amt,'basis',case entry.basis when 'period' then 'During selected period' else 'As of '||z::text end,
    'target',case entry.key when 'sales' then 'sales' when 'purchases' then 'purchases' when 'cash' then 'cash' when 'bank' then 'bank' when 'receivables' then 'customers' when 'payables' then 'suppliers' when 'gst_payable' then 'gst' else 'profit_loss' end));
  end loop;
  select count(*) into amt from private.accounting_rows_v702(t,'journal',f,z,loc,'{}') x where x->>'balance_status'='Unbalanced';
  if amt>0 then alerts:=alerts||jsonb_build_array(jsonb_build_object('label',amt::text||' unbalanced journals','target','journal','filters',jsonb_build_object('balance_status','Unbalanced')));end if;
  for entry in select * from (values('sales','Overdue receivables'),('purchases','Overdue payables')) checks(key,label) loop
   select count(*) into amt from private.accounting_rows_v702(t,entry.key,date '1900-01-01',z,loc,'{}') x where x->>'overdue'='true';
   if amt>0 then alerts:=alerts||jsonb_build_array(jsonb_build_object('label',amt::text||' '||entry.label,'target',entry.key,'from','1900-01-01','filters',jsonb_build_object('overdue','true')));end if;
   select count(*) into amt from private.accounting_rows_v702(t,entry.key,f,z,loc,'{}') x where x->>'accounting_status'='Posting missing';
   if amt>0 then alerts:=alerts||jsonb_build_array(jsonb_build_object('label',amt::text||' '||entry.key||' documents need posting review','target',entry.key));end if;
  end loop;
  for r in select x from private.accounting_rows_v702(t,'cash',date '1900-01-01',z,loc,'{}') x where (x->>'balance')::numeric< -0.005 loop
   alerts:=alerts||jsonb_build_array(jsonb_build_object('label','Negative cash: '||(r->>'reference'),'target','general_ledger','filters',jsonb_build_object('account_id',r->>'account_id')));exit;
  end loop;
 else
  if not(k='general_ledger' and account_id is null) then select coalesce(jsonb_agg(x),'[]') into raw from private.accounting_rows_v702(t,k,f,z,loc,coalesce(filters,'{}')) x;end if;
 end if;
 if k in('cash','bank','general_ledger','customers','suppliers','cash_flow') then
  select coalesce(sum(case when k='suppliers' then (x->>'credit')::numeric-(x->>'debit')::numeric else (x->>'debit')::numeric-(x->>'credit')::numeric end) filter(where (x->>'date')::date<f),0),
   coalesce(sum(case when k='suppliers' then (x->>'credit')::numeric-(x->>'debit')::numeric else (x->>'debit')::numeric-(x->>'credit')::numeric end),0) into opening,closing
   from private.accounting_lines_v702(t,z,loc) x where
   (k='general_ledger' and account_id is not null and x->>'account_id'=account_id::text)
   or (k in('cash','bank','cash_flow') and (account_id is null or x->>'account_id'=account_id::text) and (k='cash_flow' and x->>'money_method' in('cash','bank') or k='cash' and x->>'money_method'='cash' or k='bank' and x->>'money_method' in('bank','upi','card')))
   or (k='customers' and party_id is not null and x->>'party_id'=party_id::text and x->>'system_key' in('accounts_receivable','customer_credits'))
   or (k='suppliers' and party_id is not null and x->>'party_id'=party_id::text and x->>'system_key' in('accounts_payable','supplier_credits'));
  summary:=jsonb_build_array(jsonb_build_object('label','Opening balance','value',opening),jsonb_build_object('label','Net movement','value',closing-opening),jsonb_build_object('label','Closing balance','value',closing));
 end if;
 if k='profit_loss' then
  select coalesce(sum((x->>'amount')::numeric) filter(where x->>'account_type'='income'),0),coalesce(sum((x->>'amount')::numeric) filter(where x->>'account_type'='cogs'),0),coalesce(sum((x->>'amount')::numeric) filter(where x->>'account_type'='expense'),0)
  into revenue,cogs,expenses from jsonb_array_elements(raw) x;
  summary:=jsonb_build_array(jsonb_build_object('label','Revenue','value',revenue),jsonb_build_object('label','Cost of Goods Sold','value',cogs),jsonb_build_object('label','Gross Profit','value',revenue-cogs),jsonb_build_object('label','Operating Expenses','value',expenses),jsonb_build_object('label','Net Profit','value',revenue-cogs-expenses));
 elsif k='balance_sheet' then
  select coalesce(sum((x->>'amount')::numeric) filter(where x->>'account_type'='asset'),0),coalesce(sum((x->>'amount')::numeric) filter(where x->>'account_type'='liability'),0),coalesce(sum((x->>'amount')::numeric) filter(where x->>'account_type'='equity'),0)
  into assets,liabilities,equity from jsonb_array_elements(raw) x;
  select coalesce(sum(case when x->>'account_type'='income' then (x->>'credit')::numeric-(x->>'debit')::numeric when x->>'account_type' in('expense','cogs') then (x->>'credit')::numeric-(x->>'debit')::numeric else 0 end),0) into earnings from private.accounting_lines_v702(t,z,loc) x;
  raw:=raw||jsonb_build_array(jsonb_build_object('id','current_earnings','group','Equity','account_name','Unclosed earnings','amount',earnings));
  summary:=jsonb_build_array(jsonb_build_object('label','Assets','value',assets),jsonb_build_object('label','Liabilities','value',liabilities),jsonb_build_object('label','Equity including earnings','value',equity+earnings),jsonb_build_object('label','Difference','value',assets-liabilities-equity-earnings));
 elsif k='trial_balance' then
  select coalesce(sum((x->>'debit')::numeric),0),coalesce(sum((x->>'credit')::numeric),0),coalesce(sum((x->>'closing')::numeric),0) into opening,closing,net from jsonb_array_elements(raw) x;
  summary:=jsonb_build_array(jsonb_build_object('label','Period Debit','value',opening),jsonb_build_object('label','Period Credit','value',closing),jsonb_build_object('label','Period difference','value',opening-closing),jsonb_build_object('label','Closing difference','value',net));
 end if;
 -- Compute balances and statement totals before presentation filters and pagination.
 select coalesce(jsonb_agg(value order by
  case when not sort_desc and jsonb_typeof(value->sort_key)='number' then (value->>sort_key)::numeric end asc nulls last,
  case when sort_desc and jsonb_typeof(value->sort_key)='number' then (value->>sort_key)::numeric end desc nulls last,
  case when not sort_desc then lower(value->>sort_key) end asc nulls last,
  case when sort_desc then lower(value->>sort_key) end desc nulls last,ordinality),'[]') into matched
  from jsonb_array_elements(raw) with ordinality records(value,ordinality)
  where private.accounting_search_v702(value,q)
  and not exists(select 1 from jsonb_each_text(coalesce(filters,'{}')) ff where ff.value<>'' and not coalesce(case
   when ff.key='account_id' and k='journal' then exists(select 1 from jsonb_array_elements(coalesce(records.value->'lines','[]')) x where x->>'account_id'=ff.value)
   when ff.key='party_id' and k='journal' then exists(select 1 from jsonb_array_elements(coalesce(records.value->'lines','[]')) x where x->>'party_id'=ff.value) or records.value->>'customer_id'=ff.value or records.value->>'supplier_id'=ff.value
   when ff.key='payment_method' and k='journal' then exists(select 1 from jsonb_array_elements(coalesce(records.value->'lines','[]')) x where x->>'payment_method'=ff.value) or records.value->>'payment_method'=ff.value
   when ff.key='status' and k='journal' then lower(coalesce(records.value->>'status',''))=lower(ff.value) or lower(coalesce(records.value->>'posting_status',''))=lower(ff.value) or (lower(ff.value)='posted' and records.value->>'status' in('Balanced','Unbalanced','posted'))
   when ff.key='balance_status' and k='journal' then lower(coalesce(records.value->>'balance_status',''))=lower(ff.value)
   when ff.key='payment_status' then
    case
     when lower(ff.value) in ('partial', 'partially paid') then records.value->>'payment_status' in('Partial','Partially Paid')
     else lower(coalesce(records.value->>'payment_status',''))=lower(ff.value)
    end
   when ff.key='amount_min' then coalesce(abs((records.value->>'amount')::numeric),(records.value->>'total')::numeric,greatest((records.value->>'money_in')::numeric,(records.value->>'money_out')::numeric,(records.value->>'debit')::numeric,(records.value->>'credit')::numeric,(records.value->>'document_amount')::numeric,abs((records.value->>'money_amount')::numeric),0))>=ff.value::numeric
   when ff.key='amount_max' then coalesce(abs((records.value->>'amount')::numeric),(records.value->>'total')::numeric,greatest((records.value->>'money_in')::numeric,(records.value->>'money_out')::numeric,(records.value->>'debit')::numeric,(records.value->>'credit')::numeric,(records.value->>'document_amount')::numeric,abs((records.value->>'money_amount')::numeric),0))<=ff.value::numeric
   when ff.key='gst_rate' then exists(select 1 from jsonb_array_elements(coalesce(records.value->'rates','[]')) x where x::numeric=ff.value::numeric)
   when ff.key='document_id' and k='journal' then records.value->>'document_id'=ff.value
   else coalesce(records.value->>ff.key,'')=ff.value end,false));
 select coalesce(jsonb_agg(value order by ordinality),'[]') into paged from jsonb_array_elements(matched) with ordinality where ordinality>page_offset and ordinality<=page_offset+page_limit;
 if k='gst' then
  select coalesce(sum((x->>'gst_total')::numeric) filter(where x->>'direction'='outward'),0),coalesce(sum((x->>'gst_total')::numeric) filter(where x->>'direction'='inward'),0) into opening,closing from jsonb_array_elements(matched) x;
  summary:=jsonb_build_array(jsonb_build_object('label','Output GST including returns','value',opening),jsonb_build_object('label','Input GST including returns','value',closing),jsonb_build_object('label','Output less input (before credits / RCM)','value',opening-closing));
 elsif k in('sales','purchases') then
  select coalesce(sum((x->>'total')::numeric),0),coalesce(sum((x->>'paid')::numeric),0),coalesce(sum((x->>'due')::numeric),0) into opening,closing,net from jsonb_array_elements(matched) x;
  summary:=jsonb_build_array(jsonb_build_object('label','Document Total','value',opening),jsonb_build_object('label','Paid through end date','value',closing),jsonb_build_object('label','Due through end date','value',net));
 elsif k='journal' then
  select coalesce(sum((x->>'debit')::numeric),0),coalesce(sum((x->>'credit')::numeric),0) into opening,closing from jsonb_array_elements(matched) x;
  summary:=jsonb_build_array(
    jsonb_build_object('label','Total Debit','value',opening),
    jsonb_build_object('label','Total Credit','value',closing),
    jsonb_build_object('label','Net Difference','value',opening-closing)
  );
 end if;
 return jsonb_build_object('version','accounting-v1','report',k,'columns',columns,'rows',paged,'summary',summary,'alerts',alerts,'options',options,
 'subgroup_totals',(select coalesce(jsonb_object_agg(sub_amounts.g,sub_amounts.amt),'{}') from (select (x->>'group')||':'||(x->>'subgroup') g,sum((x->>'amount')::numeric) amt from jsonb_array_elements(matched) x where x->>'subgroup' is not null group by (x->>'group')||':'||(x->>'subgroup')) sub_amounts),
 'group_totals',(select coalesce(jsonb_object_agg(group_amounts.g,group_amounts.amt),'{}') from (select x->>'group' g,sum((x->>'amount')::numeric) amt from jsonb_array_elements(matched) x where x->>'group' is not null group by x->>'group') group_amounts),
 'snapshot_token',md5(raw::text),
 'total_rows',jsonb_array_length(matched),'source_rows',jsonb_array_length(raw),'offset',page_offset,'limit',page_limit,'tax_mode',tax_mode,
 'context',jsonb_build_object('business',(select name from public.tenants where id=t),'currency',coalesce((select currency_code from public.tenant_settings where tenant_id=t),'INR'),
 'from',f,'to',z,'query',q,'filters',filters,'sort_key',sort_key,'sort_desc',sort_desc,'location',case when loc is null then 'All authorized stores' else (select name from public.business_locations where tenant_id=t and id=loc) end,'generated_at',statement_timestamp(),
 'balance_basis','Running balances are computed in accounting order before search, sorting and pagination.',
 'cash_flow_basis','Cash and bank accounts; UPI/card clearing is excluded from cash equivalents. Settlement and mixed entries require classification. Internal cash/bank transfers cancel.'));
end $$;

revoke all on function private.accounting_rows_v702(uuid,text,date,date,uuid,jsonb) from public,anon,authenticated;
revoke all on function private.accounting_workspace_v702(uuid,text,date,date,uuid,text,jsonb,text,boolean,integer,integer) from public,anon,authenticated;
grant execute on function public.accounting_workspace_v702(uuid,text,date,date,uuid,text,jsonb,text,boolean,integer,integer) to authenticated;

notify pgrst,'reload schema';

commit;
