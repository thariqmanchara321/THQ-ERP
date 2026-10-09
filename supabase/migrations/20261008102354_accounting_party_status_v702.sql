-- Trade-party history status for shared ledger filtering. Reporting only.
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
    'payment_status',case when (r->>'outstanding')::numeric<=0.005 then 'Paid' when (r->>'paid_as_of')::numeric>0.005 then 'Partial' else 'Unpaid' end,
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
     'payment_status',case when (r->>'paid_as_of')::numeric>=(r->>'grand_total')::numeric-0.005 then 'Paid' when (r->>'paid_as_of')::numeric>0.005 then 'Partial' else 'Unpaid' end,
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
   'entry_number',g.entry_number,'source_type',coalesce(g.source_type,'unknown'),'type',initcap(replace(coalesce(g.source_type,'unknown'),'_',' ')),
   'source_id',g.source_id,'description',g.description,'party',coalesce(nullif(g.party,''),g.src->>'party',''),'status',g.status,'amount',g.debit,
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


notify pgrst,'reload schema';
