-- THQ ERP V4.7.3
-- Live Operations Polish
-- - Terminal Daily historical invoice drill-down for the activated POS only.
-- - POS return lookup is deliberately restricted to today's invoices on the activated POS.
-- - Release contract advances to migration 119.
begin;

-- V4.7.3 Terminal Daily wrapper: the report remains summary-only. Held invoices
-- are live operational state, so they are shown only for today and never leaked
-- into a historical day's report.
create or replace function public.pos_terminal_day_v473(
  p_tenant_id uuid,
  p_device_id uuid,
  p_day date default current_date
)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v jsonb;
  v_held bigint:=0;
  v_timezone text:='UTC';
  v_business_today date;
begin
  select coalesce(ts.timezone,'UTC') into v_timezone from public.tenant_settings ts where ts.tenant_id=p_tenant_id;
  v_business_today:=(now() at time zone coalesce(v_timezone,'UTC'))::date;
  select public.pos_terminal_day_v472(p_tenant_id,p_device_id,p_day) into v;
  -- V4.7.3 keeps Terminal Daily intentionally summary-only. Individual shift
  -- rows belong to Cashier Shift; historical invoice rows are drill-down only.
  if v ? 'shift_summary' then
    v:=jsonb_set(
      v,
      '{shift_summary}',
      coalesce(v->'shift_summary','{}'::jsonb)-'shifts',
      true
    );
  end if;
  if coalesce(p_day,v_business_today)=v_business_today then
    select count(*) into v_held
    from public.pos_held_sales h
    where h.tenant_id=p_tenant_id and h.device_id=p_device_id;
  end if;
  return coalesce(v,'{}'::jsonb)||jsonb_build_object('held_count',v_held);
end $$;
grant execute on function public.pos_terminal_day_v473(uuid,uuid,date) to authenticated;

create or replace function public.pos_terminal_invoices_v473(
  p_tenant_id uuid,
  p_device_id uuid,
  p_day date default current_date,
  p_query text default '',
  p_limit integer default 200
)
returns table(
  sale_id uuid,
  sale_number text,
  invoice_number text,
  customer_name text,
  created_at timestamptz,
  grand_total numeric,
  paid_amount numeric,
  returned_amount numeric,
  outstanding_amount numeric,
  status text
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v_location uuid;
  q text := '%' || lower(trim(coalesce(p_query,''))) || '%';
  lim integer := greatest(1,least(coalesce(p_limit,200),500));
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  select d.location_id into v_location
  from public.business_devices d
  where d.id=p_device_id and d.tenant_id=p_tenant_id and d.status='active';

  if v_location is null then raise exception 'Active terminal not found'; end if;
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_user_location_allowed(p_tenant_id,v_location,'view') then
    raise exception 'Terminal access denied';
  end if;

  return query
  select
    s.id,
    s.sale_number::text,
    coalesce(dn.terminal_number,ln.local_number,s.sale_number)::text,
    coalesce(c.name,'')::text,
    s.created_at,
    s.grand_total::numeric,
    coalesce(py.paid,0)::numeric,
    coalesce(rt.returned,0)::numeric,
    greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)::numeric,
    s.status::text
  from public.sales s
  join public.document_origins o
    on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id and o.device_id=p_device_id
  join public.customers c on c.id=s.customer_id
  left join public.location_document_numbers ln
    on ln.tenant_id=p_tenant_id and ln.entity_type='sale' and ln.entity_id=s.id
  left join public.device_document_numbers dn
    on dn.tenant_id=p_tenant_id and dn.entity_type='sale' and dn.entity_id=s.id
  left join (
    select sp.sale_id,sum(sp.amount)::numeric paid
    from public.sale_payments sp group by sp.sale_id
  ) py on py.sale_id=s.id
  left join (
    select sr.sale_id,sum(sr.grand_total)::numeric returned
    from public.sales_returns sr where sr.refund_status<>'waived' group by sr.sale_id
  ) rt on rt.sale_id=s.id
  where s.tenant_id=p_tenant_id
    and s.sale_date=coalesce(p_day,current_date)
    and (
      trim(coalesce(p_query,''))='' or
      lower(coalesce(s.sale_number,'')) like q or
      lower(coalesce(dn.terminal_number,ln.local_number,'')) like q or
      lower(coalesce(c.name,'')) like q
    )
  order by s.created_at desc
  limit lim;
end $$;
grant execute on function public.pos_terminal_invoices_v473(uuid,uuid,date,text,integer) to authenticated;

-- POS operational lists are deliberately limited to the activated terminal and
-- selected local day. This prevents the live POS from loading historical/store-wide
-- transaction history; Terminal Daily owns historical lookup.
create or replace function public.pos_sales_today_v473(
  p_tenant_id uuid,
  p_device_id uuid,
  p_day date default current_date
)
returns table(
  sale_id uuid,sale_number text,invoice_number text,customer_id uuid,customer_name text,sale_date date,due_date date,
  subtotal numeric,discount_total numeric,tax_total numeric,additional_charges numeric,grand_total numeric,
  paid_amount numeric,balance_due numeric,payment_status text,cost_total numeric,gross_profit numeric,status text,created_at timestamptz,
  location_id uuid,location_name text,device_id uuid,device_name text
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_location uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select d.location_id into v_location from public.business_devices d
  where d.id=p_device_id and d.tenant_id=p_tenant_id and d.status='active';
  if v_location is null then raise exception 'Active terminal not found';end if;
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_user_location_allowed(p_tenant_id,v_location,'view') then raise exception 'Terminal access denied';end if;

  return query
  select s.id,s.sale_number::text,coalesce(dn.terminal_number,ln.local_number,s.sale_number)::text,
    s.customer_id,c.name::text,s.sale_date,s.due_date,
    s.subtotal,s.discount_total,s.tax_total,s.additional_charges,s.grand_total,
    coalesce(py.paid,0)::numeric,
    greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)::numeric,
    (case
      when greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)<=0.0001 then 'paid'
      when coalesce(py.paid,0)>0 then 'partial' else 'unpaid' end)::text,
    coalesce(s.cost_total,0)::numeric,coalesce(s.gross_profit,0)::numeric,s.status::text,s.created_at,
    o.location_id,l.name::text,o.device_id,d.name::text
  from public.sales s
  join public.customers c on c.id=s.customer_id
  join public.document_origins o
    on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id and o.device_id=p_device_id
  left join public.business_locations l on l.id=o.location_id
  left join public.business_devices d on d.id=o.device_id
  left join (
    select sp.sale_id as entity_sale_id,sum(sp.amount) as paid
    from public.sale_payments sp group by sp.sale_id
  ) py on py.entity_sale_id=s.id
  left join (
    select sr.sale_id,sum(sr.grand_total) as returned
    from public.sales_returns sr where sr.refund_status<>'waived' group by sr.sale_id
  ) rt on rt.sale_id=s.id
  left join public.location_document_numbers ln
    on ln.tenant_id=p_tenant_id and ln.entity_type='sale' and ln.entity_id=s.id
  left join public.device_document_numbers dn
    on dn.tenant_id=p_tenant_id and dn.entity_type='sale' and dn.entity_id=s.id
  where s.tenant_id=p_tenant_id and s.sale_date=coalesce(p_day,current_date)
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'sales.view') or private.erp_has_permission(p_tenant_id,'sales.manage'))
  order by s.created_at desc;
end $$;
grant execute on function public.pos_sales_today_v473(uuid,uuid,date) to authenticated;

create or replace function public.pos_purchases_today_v473(
  p_tenant_id uuid,
  p_device_id uuid,
  p_day date default current_date
)
returns table(
  purchase_id uuid,purchase_number text,invoice_number text,supplier_id uuid,supplier_name text,supplier_invoice_number text,purchase_date date,due_date date,
  subtotal numeric,discount_total numeric,tax_total numeric,additional_charges numeric,grand_total numeric,paid_amount numeric,balance_due numeric,payment_status text,status text,created_at timestamptz,
  location_id uuid,location_name text,device_id uuid,device_name text
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_location uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select d.location_id into v_location from public.business_devices d
  where d.id=p_device_id and d.tenant_id=p_tenant_id and d.status='active';
  if v_location is null then raise exception 'Active terminal not found';end if;
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_user_location_allowed(p_tenant_id,v_location,'view') then raise exception 'Terminal access denied';end if;

  return query
  select p.id,p.purchase_number::text,coalesce(dn.terminal_number,ln.local_number,p.purchase_number)::text,
    p.supplier_id,s.name::text,p.supplier_invoice_number::text,p.purchase_date,p.due_date,
    p.subtotal,p.discount_total,p.tax_total,p.additional_charges,p.grand_total,
    coalesce(py.paid,0)::numeric,
    greatest(p.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)::numeric,
    (case
      when greatest(p.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)<=0.0001 then 'paid'
      when coalesce(py.paid,0)>0 then 'partial' else 'unpaid' end)::text,
    p.status::text,p.created_at,o.location_id,l.name::text,o.device_id,d.name::text
  from public.purchases p
  join public.suppliers s on s.id=p.supplier_id
  join public.document_origins o
    on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id and o.device_id=p_device_id
  left join public.business_locations l on l.id=o.location_id
  left join public.business_devices d on d.id=o.device_id
  left join (
    select pp.purchase_id as entity_purchase_id,sum(pp.amount) as paid
    from public.purchase_payments pp group by pp.purchase_id
  ) py on py.entity_purchase_id=p.id
  left join (
    select pr.purchase_id,sum(pr.grand_total) as returned
    from public.purchase_returns pr where pr.credit_status<>'waived' group by pr.purchase_id
  ) rt on rt.purchase_id=p.id
  left join public.location_document_numbers ln
    on ln.tenant_id=p_tenant_id and ln.entity_type='purchase' and ln.entity_id=p.id
  left join public.device_document_numbers dn
    on dn.tenant_id=p_tenant_id and dn.entity_type='purchase' and dn.entity_id=p.id
  where p.tenant_id=p_tenant_id and p.purchase_date=coalesce(p_day,current_date)
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'purchases.view') or private.erp_has_permission(p_tenant_id,'purchases.manage'))
  order by p.created_at desc;
end $$;
grant execute on function public.pos_purchases_today_v473(uuid,uuid,date) to authenticated;

create or replace function public.pos_expenses_today_v473(
  p_tenant_id uuid,
  p_device_id uuid,
  p_day date default current_date
)
returns table(
  expense_id uuid,expense_number text,invoice_number text,category_id uuid,category_name text,expense_date date,payee text,description text,
  amount numeric,tax_amount numeric,total_amount numeric,payment_method text,reference_number text,notes text,status text,created_at timestamptz,
  location_id uuid,location_name text,device_id uuid,device_name text
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_location uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select d.location_id into v_location from public.business_devices d
  where d.id=p_device_id and d.tenant_id=p_tenant_id and d.status='active';
  if v_location is null then raise exception 'Active terminal not found';end if;
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_user_location_allowed(p_tenant_id,v_location,'view') then raise exception 'Terminal access denied';end if;

  return query
  select e.id,e.expense_number::text,coalesce(dn.terminal_number,ln.local_number,e.expense_number)::text,
    e.category_id,c.name::text,e.expense_date,e.payee::text,e.description::text,
    e.amount,e.tax_amount,e.total_amount,e.payment_method::text,e.reference_number::text,e.notes::text,e.status::text,e.created_at,
    o.location_id,l.name::text,o.device_id,d.name::text
  from public.expenses e
  join public.expense_categories c on c.id=e.category_id
  join public.document_origins o
    on o.tenant_id=p_tenant_id and o.entity_type='expense' and o.entity_id=e.id and o.device_id=p_device_id
  left join public.business_locations l on l.id=o.location_id
  left join public.business_devices d on d.id=o.device_id
  left join public.location_document_numbers ln
    on ln.tenant_id=p_tenant_id and ln.entity_type='expense' and ln.entity_id=e.id
  left join public.device_document_numbers dn
    on dn.tenant_id=p_tenant_id and dn.entity_type='expense' and dn.entity_id=e.id
  where e.tenant_id=p_tenant_id and e.expense_date=coalesce(p_day,current_date)
  order by e.created_at desc;
end $$;
grant execute on function public.pos_expenses_today_v473(uuid,uuid,date) to authenticated;

create or replace function public.pos_return_documents_today_v473(
  p_tenant_id uuid,
  p_device_id uuid,
  p_day date default current_date,
  p_type text default 'all',
  p_query text default '',
  p_limit integer default 200
)
returns table(
  entity_type text,
  entity_id uuid,
  document_number text,
  document_date date,
  party text,
  grand_total numeric,
  status text,
  return_status text,
  location_id uuid,
  device_id uuid,
  matched_product text
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v_location uuid;
  q text := '%' || lower(trim(coalesce(p_query,''))) || '%';
  lim integer := greatest(1,least(coalesce(p_limit,200),500));
begin
  if p_type not in('all','sale','purchase') then raise exception 'Invalid return search type'; end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied'; end if;

  select d.location_id into v_location
  from public.business_devices d
  where d.id=p_device_id and d.tenant_id=p_tenant_id and d.status='active';
  if v_location is null then raise exception 'Active terminal not found'; end if;
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_user_location_allowed(p_tenant_id,v_location,'view') then
    raise exception 'Terminal access denied';
  end if;

  return query
  select z.entity_type,z.entity_id,z.document_number,z.document_date,z.party,z.grand_total,
         z.status,z.return_status,z.location_id,z.device_id,z.matched_product
  from (
    select
      'sale'::text entity_type,
      s.id entity_id,
      coalesce(dn.terminal_number,ln.local_number,s.sale_number)::text document_number,
      s.sale_date document_date,
      c.name::text party,
      s.grand_total,
      s.status::text status,
      coalesce(public.transaction_return_status_v45(p_tenant_id,'sale',s.id)->>'status','not_returned') return_status,
      o.location_id,
      o.device_id,
      (
        select concat_ws(' • ',pr.name,pv.sku,nullif(pv.barcode,''),nullif(pv.part_number,''))
        from public.sale_items si
        join public.product_variants pv on pv.id=si.variant_id
        join public.products pr on pr.id=pv.product_id
        where si.sale_id=s.id
          and (trim(coalesce(p_query,''))='' or lower(pr.name) like q or lower(coalesce(pv.sku,'')) like q
               or lower(coalesce(pv.barcode,'')) like q or lower(coalesce(pv.part_number,'')) like q)
        order by si.id limit 1
      )::text matched_product
    from public.sales s
    join public.customers c on c.id=s.customer_id
    join public.document_origins o
      on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id and o.device_id=p_device_id
    left join public.location_document_numbers ln
      on ln.tenant_id=p_tenant_id and ln.entity_type='sale' and ln.entity_id=s.id
    left join public.device_document_numbers dn
      on dn.tenant_id=p_tenant_id and dn.entity_type='sale' and dn.entity_id=s.id
    where p_type in('all','sale')
      and s.tenant_id=p_tenant_id
      and s.sale_date=coalesce(p_day,current_date)
      and coalesce(s.status,'') not in('void','cancelled')
      and (
        trim(coalesce(p_query,''))='' or lower(coalesce(s.sale_number,'')) like q
        or lower(coalesce(dn.terminal_number,ln.local_number,'')) like q
        or lower(coalesce(c.name,'')) like q
        or exists(
          select 1 from public.sale_items si
          join public.product_variants pv on pv.id=si.variant_id
          join public.products pr on pr.id=pv.product_id
          where si.sale_id=s.id and (
            lower(pr.name) like q or lower(coalesce(pv.sku,'')) like q
            or lower(coalesce(pv.barcode,'')) like q or lower(coalesce(pv.part_number,'')) like q
          )
        )
      )

    union all

    select
      'purchase'::text,
      p.id,
      p.purchase_number::text,
      p.purchase_date,
      sp.name::text,
      p.grand_total,
      p.status::text,
      coalesce(public.transaction_return_status_v45(p_tenant_id,'purchase',p.id)->>'status','not_returned'),
      o.location_id,
      o.device_id,
      (
        select concat_ws(' • ',pr.name,pv.sku,nullif(pv.barcode,''),nullif(pv.part_number,''))
        from public.purchase_items pi
        join public.product_variants pv on pv.id=pi.variant_id
        join public.products pr on pr.id=pv.product_id
        where pi.purchase_id=p.id
          and (trim(coalesce(p_query,''))='' or lower(pr.name) like q or lower(coalesce(pv.sku,'')) like q
               or lower(coalesce(pv.barcode,'')) like q or lower(coalesce(pv.part_number,'')) like q)
        order by pi.id limit 1
      )::text
    from public.purchases p
    join public.suppliers sp on sp.id=p.supplier_id
    join public.document_origins o
      on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id and o.device_id=p_device_id
    where p_type in('all','purchase')
      and p.tenant_id=p_tenant_id
      and p.purchase_date=coalesce(p_day,current_date)
      and coalesce(p.status,'') not in('void','cancelled')
      and (
        trim(coalesce(p_query,''))='' or lower(coalesce(p.purchase_number,'')) like q
        or lower(coalesce(p.supplier_invoice_number,'')) like q or lower(coalesce(sp.name,'')) like q
        or exists(
          select 1 from public.purchase_items pi
          join public.product_variants pv on pv.id=pi.variant_id
          join public.products pr on pr.id=pv.product_id
          where pi.purchase_id=p.id and (
            lower(pr.name) like q or lower(coalesce(pv.sku,'')) like q
            or lower(coalesce(pv.barcode,'')) like q or lower(coalesce(pv.part_number,'')) like q
          )
        )
      )
  ) z
  order by z.document_date desc,z.document_number desc
  limit lim;
end $$;
grant execute on function public.pos_return_documents_today_v473(uuid,uuid,date,text,text,integer) to authenticated;

create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp
as $$
  select jsonb_build_object(
    'product','THQ ERP',
    'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
    'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
    'minimum_app_version','4.7.3',
    'release','Live Operations Polish'
  )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  119,'4.7.3','Live Operations Polish',
  'Adds manual live-operations support, exact-terminal current-day POS lists/returns, historical Terminal Daily invoice lookup, and advances the V4.7 release contract.'
)
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP V4.7.3 migration 119 Live Operations Polish applied' as status;
