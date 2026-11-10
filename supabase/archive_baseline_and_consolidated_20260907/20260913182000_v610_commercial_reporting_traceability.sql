-- THQ ERP v6.1 commercial pricing reporting + end-to-end sale traceability.

create or replace function public.sales_commercial_trace_v610(
  p_tenant_id uuid,
  p_sale_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  s public.sales%rowtype;
  v_commercial jsonb;
  v_restaurant jsonb;
  v_kots jsonb := '[]'::jsonb;
  v_gst jsonb;
  v_journal jsonb;
  v_payments jsonb := '[]'::jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'sales.view')
    or private.erp_has_permission(p_tenant_id,'sales.manage')
    or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')
  ) then
    raise exception 'Sales/GST view permission required';
  end if;

  select * into s
  from public.sales
  where id=p_sale_id and tenant_id=p_tenant_id;
  if not found then raise exception 'Sale not found'; end if;

  select jsonb_build_object(
    'id',c.id,
    'source_type',c.source_type,
    'source_id',c.source_id,
    'order_type',c.order_type,
    'discount_type',c.discount_type,
    'discount_value',c.discount_value,
    'document_discount_total',c.document_discount_total,
    'classified_charge_total',c.classified_charge_total,
    'charge_breakdown',c.charge_breakdown,
    'created_at',c.created_at
  )
  into v_commercial
  from public.sale_commercial_summary_v610 c
  where c.tenant_id=p_tenant_id and c.sale_id=p_sale_id
  order by c.created_at desc
  limit 1;

  select jsonb_build_object(
    'id',o.id,
    'order_number',o.order_number,
    'tracking_code',o.tracking_code,
    'order_type',o.order_type,
    'table_id',o.table_id,
    'guest_count',o.guest_count,
    'waiter_user_id',o.waiter_user_id,
    'status',o.status,
    'opened_at',o.opened_at,
    'kitchen_sent_at',o.kitchen_sent_at,
    'ready_at',o.ready_at,
    'served_at',o.served_at,
    'billed_at',o.billed_at
  )
  into v_restaurant
  from public.restaurant_orders o
  where o.tenant_id=p_tenant_id and o.sale_id=p_sale_id
  order by o.billed_at desc nulls last,o.updated_at desc
  limit 1;

  if v_restaurant is not null then
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id',k.id,
        'kot_number',k.kot_number,
        'tracking_code',k.tracking_code,
        'kind',k.kind,
        'status',k.status,
        'sent_at',k.sent_at,
        'started_at',k.started_at,
        'ready_at',k.ready_at,
        'served_at',k.served_at
      ) order by k.sent_at,k.id
    ),'[]'::jsonb)
    into v_kots
    from public.restaurant_kots k
    where k.tenant_id=p_tenant_id
      and k.order_id=(v_restaurant->>'id')::uuid;
  end if;

  select jsonb_build_object(
    'id',g.id,
    'source_number',g.source_number,
    'document_number',g.document_number,
    'document_date',g.document_date,
    'tax_mode',g.tax_mode,
    'supply_type',g.supply_type,
    'place_of_supply_code',g.place_of_supply_code,
    'interstate',g.interstate,
    'subtotal',g.subtotal,
    'discount_total',g.discount_total,
    'taxable_total',g.taxable_total,
    'cgst_total',g.cgst_total,
    'sgst_total',g.sgst_total,
    'utgst_total',g.utgst_total,
    'igst_total',g.igst_total,
    'cess_total',g.cess_total,
    'tax_collected_total',g.tax_collected_total,
    'round_off',g.round_off,
    'grand_total',g.grand_total,
    'engine_version',g.engine_version,
    'created_at',g.created_at
  )
  into v_gst
  from public.gst_document_snapshots_v520 g
  where g.tenant_id=p_tenant_id
    and g.source_type='sale'
    and g.source_id=p_sale_id
  order by g.created_at desc
  limit 1;

  select jsonb_build_object(
    'id',j.id,
    'entry_number',j.entry_number,
    'entry_date',j.entry_date,
    'status',j.status,
    'description',j.description,
    'source_reference',j.source_reference,
    'posted_at',j.posted_at,
    'line_count',(
      select count(*) from public.journal_lines l
      where l.journal_entry_id=j.id
    ),
    'debit_total',(
      select coalesce(sum(l.debit),0) from public.journal_lines l
      where l.journal_entry_id=j.id
    ),
    'credit_total',(
      select coalesce(sum(l.credit),0) from public.journal_lines l
      where l.journal_entry_id=j.id
    )
  )
  into v_journal
  from public.journal_entries j
  where j.tenant_id=p_tenant_id
    and j.source_type='sale'
    and j.source_id=p_sale_id
  order by j.created_at desc
  limit 1;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',p.id,
      'payment_method',p.payment_method,
      'amount',p.amount,
      'reference_number',p.reference_number,
      'paid_at',p.paid_at,
      'ledger_account_id',p.ledger_account_id
    ) order by p.paid_at,p.id
  ),'[]'::jsonb)
  into v_payments
  from public.sale_payments p
  where p.tenant_id=p_tenant_id and p.sale_id=p_sale_id;

  return jsonb_build_object(
    'sale',jsonb_build_object(
      'id',s.id,
      'sale_number',s.sale_number,
      'sale_date',s.sale_date,
      'status',s.status,
      'subtotal',s.subtotal,
      'discount_total',s.discount_total,
      'tax_total',s.tax_total,
      'round_off',s.round_off,
      'grand_total',s.grand_total
    ),
    'commercial_summary',v_commercial,
    'restaurant_order',v_restaurant,
    'kots',v_kots,
    'gst_snapshot',v_gst,
    'journal',v_journal,
    'payments',v_payments,
    'evidence',jsonb_build_object(
      'commercial_summary',v_commercial is not null,
      'restaurant_source',v_restaurant is not null,
      'gst_snapshot',v_gst is not null,
      'journal',v_journal is not null,
      'payments',jsonb_array_length(v_payments)>0,
      'authoritative_financial_chain_complete',
        v_gst is not null and v_journal is not null
    )
  );
end;
$$;

create or replace function public.reports_commercial_summary_v610(
  p_tenant_id uuid,
  p_from_date date,
  p_to_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_summary jsonb;
  v_order_types jsonb;
  v_discount_types jsonb;
  v_charges jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'sales.view')
    or private.erp_has_permission(p_tenant_id,'sales.manage')
    or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')
  ) then
    raise exception 'Sales/GST view permission required';
  end if;
  if p_from_date is null or p_to_date is null or p_from_date>p_to_date then
    raise exception 'Invalid report date range';
  end if;

  with base as (
    select c.*,s.grand_total,s.tax_total,s.sale_date,s.status
    from public.sale_commercial_summary_v610 c
    join public.sales s on s.id=c.sale_id and s.tenant_id=c.tenant_id
    where c.tenant_id=p_tenant_id
      and s.sale_date between p_from_date and p_to_date
      and s.status='posted'
  )
  select jsonb_build_object(
    'sale_count',count(*),
    'sales_total',coalesce(sum(grand_total),0),
    'tax_total',coalesce(sum(tax_total),0),
    'document_discount_total',coalesce(sum(document_discount_total),0),
    'classified_charge_total',coalesce(sum(classified_charge_total),0),
    'restaurant_sale_count',
      count(*) filter(where source_type='restaurant_order'),
    'normal_sale_count',
      count(*) filter(where source_type<>'restaurant_order'),
    'discounted_sale_count',
      count(*) filter(where document_discount_total>0),
    'charged_sale_count',
      count(*) filter(where classified_charge_total>0)
  )
  into v_summary
  from base;

  with base as (
    select c.*,s.grand_total
    from public.sale_commercial_summary_v610 c
    join public.sales s on s.id=c.sale_id and s.tenant_id=c.tenant_id
    where c.tenant_id=p_tenant_id
      and s.sale_date between p_from_date and p_to_date
      and s.status='posted'
  ), grouped as (
    select
      order_type,
      count(*) sale_count,
      sum(grand_total) sales_total,
      sum(document_discount_total) discount_total,
      sum(classified_charge_total) charge_total
    from base
    group by order_type
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'order_type',order_type,
    'sale_count',sale_count,
    'sales_total',sales_total,
    'discount_total',discount_total,
    'charge_total',charge_total
  ) order by sales_total desc),'[]'::jsonb)
  into v_order_types
  from grouped;

  with base as (
    select c.*
    from public.sale_commercial_summary_v610 c
    join public.sales s on s.id=c.sale_id and s.tenant_id=c.tenant_id
    where c.tenant_id=p_tenant_id
      and s.sale_date between p_from_date and p_to_date
      and s.status='posted'
  ), grouped as (
    select
      discount_type,
      count(*) sale_count,
      sum(document_discount_total) discount_total
    from base
    group by discount_type
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'discount_type',discount_type,
    'sale_count',sale_count,
    'discount_total',discount_total
  ) order by discount_total desc),'[]'::jsonb)
  into v_discount_types
  from grouped;

  with base as (
    select c.charge_breakdown
    from public.sale_commercial_summary_v610 c
    join public.sales s on s.id=c.sale_id and s.tenant_id=c.tenant_id
    where c.tenant_id=p_tenant_id
      and s.sale_date between p_from_date and p_to_date
      and s.status='posted'
  ), charge_rows as (
    select x.value row
    from base b
    cross join lateral jsonb_array_elements(
      coalesce(b.charge_breakdown,'[]'::jsonb)
    ) x(value)
  ), grouped as (
    select
      coalesce(row->>'charge_id','') charge_id,
      coalesce(row->>'code','') code,
      coalesce(row->>'name','Charge') name,
      coalesce(row->>'kind','other') kind,
      count(*) application_count,
      sum(coalesce(nullif(row->>'quantity','')::numeric,0)) quantity,
      sum(coalesce(nullif(row->>'taxable_value','')::numeric,0))
        taxable_total,
      sum(coalesce(nullif(row->>'tax_amount','')::numeric,0)) tax_total,
      sum(coalesce(nullif(row->>'line_total','')::numeric,0)) line_total
    from charge_rows
    group by 1,2,3,4
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'charge_id',charge_id,
    'code',code,
    'name',name,
    'kind',kind,
    'application_count',application_count,
    'quantity',quantity,
    'taxable_total',taxable_total,
    'tax_total',tax_total,
    'line_total',line_total
  ) order by line_total desc,name),'[]'::jsonb)
  into v_charges
  from grouped;

  return jsonb_build_object(
    'from_date',p_from_date,
    'to_date',p_to_date,
    'summary',coalesce(v_summary,'{}'::jsonb),
    'order_types',v_order_types,
    'discount_types',v_discount_types,
    'charges',v_charges
  );
end;
$$;

revoke all on function public.sales_commercial_trace_v610(uuid,uuid)
from public;
grant execute on function public.sales_commercial_trace_v610(uuid,uuid)
to authenticated,service_role;

revoke all on function public.reports_commercial_summary_v610(uuid,date,date)
from public;
grant execute on function public.reports_commercial_summary_v610(uuid,date,date)
to authenticated,service_role;
