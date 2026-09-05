create or replace function private.v600_product_profit_rows(
  p_tenant_id uuid,
  p_from date,
  p_to date,
  p_location_id uuid default null,
  p_variant_id uuid default null
)
returns table(
  variant_id uuid,
  product_id uuid,
  product_name text,
  variant_name text,
  sku text,
  category_id uuid,
  category_name text,
  brand_id uuid,
  brand_name text,
  sold_qty numeric,
  sale_revenue numeric,
  sale_cogs numeric,
  sale_discount numeric,
  returned_qty numeric,
  return_revenue numeric,
  return_cogs numeric,
  net_revenue numeric,
  net_cogs numeric,
  gross_profit numeric,
  margin_pct numeric
)
language sql
stable
security definer
set search_path=''
as $$
with sale_facts as (
  select
    si.variant_id,
    sum(si.quantity)::numeric as sold_qty,
    sum(si.taxable_amount)::numeric as sale_revenue,
    sum(si.cost_total)::numeric as sale_cogs,
    sum(si.discount_amount)::numeric as sale_discount
  from public.sales s
  join public.sale_items si on si.tenant_id=s.tenant_id and si.sale_id=s.id
  left join lateral (
    select o.location_id
    from public.document_origins o
    where o.tenant_id=s.tenant_id and o.entity_type='sale' and o.entity_id=s.id
    order by o.created_at asc
    limit 1
  ) origin on true
  where s.tenant_id=p_tenant_id
    and s.status='posted'
    and s.sale_date between p_from and p_to
    and (p_location_id is null or origin.location_id=p_location_id)
    and (p_variant_id is null or si.variant_id=p_variant_id)
  group by si.variant_id
), return_facts as (
  select
    sri.variant_id,
    sum(sri.quantity)::numeric as returned_qty,
    sum(case when si.quantity<>0 then (si.taxable_amount/si.quantity)*sri.quantity else 0 end)::numeric as return_revenue,
    sum(case when si.quantity<>0 then (si.cost_total/si.quantity)*sri.quantity else 0 end)::numeric as return_cogs
  from public.sales_returns sr
  join public.sales_return_items sri on sri.sales_return_id=sr.id
  join public.sale_items si on si.id=sri.sale_item_id and si.variant_id=sri.variant_id
  where sr.tenant_id=p_tenant_id
    and sr.return_date between p_from and p_to
    and (p_location_id is null or sr.location_id=p_location_id)
    and (p_variant_id is null or sri.variant_id=p_variant_id)
  group by sri.variant_id
), variants as (
  select variant_id from sale_facts
  union
  select variant_id from return_facts
)
select
  v.id as variant_id,
  p.id as product_id,
  p.name as product_name,
  v.name as variant_name,
  v.sku,
  p.category_id,
  c.name as category_name,
  p.brand_id,
  b.name as brand_name,
  coalesce(sf.sold_qty,0)::numeric as sold_qty,
  round(coalesce(sf.sale_revenue,0),4)::numeric as sale_revenue,
  round(coalesce(sf.sale_cogs,0),4)::numeric as sale_cogs,
  round(coalesce(sf.sale_discount,0),4)::numeric as sale_discount,
  coalesce(rf.returned_qty,0)::numeric as returned_qty,
  round(coalesce(rf.return_revenue,0),4)::numeric as return_revenue,
  round(coalesce(rf.return_cogs,0),4)::numeric as return_cogs,
  round(coalesce(sf.sale_revenue,0)-coalesce(rf.return_revenue,0),4)::numeric as net_revenue,
  round(coalesce(sf.sale_cogs,0)-coalesce(rf.return_cogs,0),4)::numeric as net_cogs,
  round((coalesce(sf.sale_revenue,0)-coalesce(rf.return_revenue,0))-(coalesce(sf.sale_cogs,0)-coalesce(rf.return_cogs,0)),4)::numeric as gross_profit,
  case when (coalesce(sf.sale_revenue,0)-coalesce(rf.return_revenue,0))=0 then null
       else round((((coalesce(sf.sale_revenue,0)-coalesce(rf.return_revenue,0))-(coalesce(sf.sale_cogs,0)-coalesce(rf.return_cogs,0))) * 100.0)
                  /(coalesce(sf.sale_revenue,0)-coalesce(rf.return_revenue,0)),4)::numeric end as margin_pct
from variants x
join public.product_variants v on v.tenant_id=p_tenant_id and v.id=x.variant_id
join public.products p on p.tenant_id=p_tenant_id and p.id=v.product_id
left join public.product_categories c on c.tenant_id=p_tenant_id and c.id=p.category_id
left join public.product_brands b on b.tenant_id=p_tenant_id and b.id=p.brand_id
left join sale_facts sf on sf.variant_id=v.id
left join return_facts rf on rf.variant_id=v.id;
$$;
revoke all on function private.v600_product_profit_rows(uuid,date,date,uuid,uuid) from public,anon,authenticated;

create or replace function public.product_profitability_v600(
  p_tenant_id uuid,
  p_from date,
  p_to date,
  p_location_id uuid default null,
  p_variant_id uuid default null,
  p_category_id uuid default null,
  p_brand_id uuid default null,
  p_query text default null,
  p_limit integer default 500
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_rows jsonb;
  v_totals jsonb;
  v_days integer;
  v_prev_from date;
  v_prev_to date;
  v_prev jsonb;
begin
  if not private.has_permission(p_tenant_id,'profitability.view') then
    raise exception 'Permission denied' using errcode='42501';
  end if;
  if p_from is null or p_to is null or p_to<p_from then raise exception 'Valid from/to dates are required'; end if;

  select coalesce(jsonb_agg(to_jsonb(q) order by q.gross_profit asc,q.net_revenue desc),'[]'::jsonb)
  into v_rows
  from (
    select r.*
    from private.v600_product_profit_rows(p_tenant_id,p_from,p_to,p_location_id,p_variant_id) r
    where (p_category_id is null or r.category_id=p_category_id)
      and (p_brand_id is null or r.brand_id=p_brand_id)
      and (nullif(trim(coalesce(p_query,'')),'') is null
        or r.product_name ilike '%'||trim(p_query)||'%'
        or r.variant_name ilike '%'||trim(p_query)||'%'
        or r.sku ilike '%'||trim(p_query)||'%')
    order by r.gross_profit asc,r.net_revenue desc
    limit greatest(1,least(coalesce(p_limit,500),2000))
  ) q;

  select jsonb_build_object(
    'sales',round(coalesce(sum(r.net_revenue),0),4),
    'cost',round(coalesce(sum(r.net_cogs),0),4),
    'profit',round(coalesce(sum(r.gross_profit),0),4),
    'margin_pct',case when coalesce(sum(r.net_revenue),0)=0 then null else round(sum(r.gross_profit)*100.0/sum(r.net_revenue),4) end,
    'sold_qty',coalesce(sum(r.sold_qty),0),
    'returned_qty',coalesce(sum(r.returned_qty),0),
    'discount',round(coalesce(sum(r.sale_discount),0),4),
    'return_revenue',round(coalesce(sum(r.return_revenue),0),4),
    'return_cost',round(coalesce(sum(r.return_cogs),0),4)
  ) into v_totals
  from private.v600_product_profit_rows(p_tenant_id,p_from,p_to,p_location_id,p_variant_id) r
  where (p_category_id is null or r.category_id=p_category_id)
    and (p_brand_id is null or r.brand_id=p_brand_id)
    and (nullif(trim(coalesce(p_query,'')),'') is null
      or r.product_name ilike '%'||trim(p_query)||'%'
      or r.variant_name ilike '%'||trim(p_query)||'%'
      or r.sku ilike '%'||trim(p_query)||'%');

  v_days := (p_to-p_from)+1;
  v_prev_to := p_from-1;
  v_prev_from := v_prev_to-(v_days-1);
  select jsonb_build_object(
    'from',v_prev_from,'to',v_prev_to,
    'sales',round(coalesce(sum(r.net_revenue),0),4),
    'cost',round(coalesce(sum(r.net_cogs),0),4),
    'profit',round(coalesce(sum(r.gross_profit),0),4),
    'margin_pct',case when coalesce(sum(r.net_revenue),0)=0 then null else round(sum(r.gross_profit)*100.0/sum(r.net_revenue),4) end
  ) into v_prev
  from private.v600_product_profit_rows(p_tenant_id,v_prev_from,v_prev_to,p_location_id,p_variant_id) r
  where (p_category_id is null or r.category_id=p_category_id)
    and (p_brand_id is null or r.brand_id=p_brand_id);

  return jsonb_build_object(
    'period',jsonb_build_object('from',p_from,'to',p_to,'location_id',p_location_id),
    'basis','Net product revenue before GST minus recognized sale-item COGS; returns reverse original sale-item revenue and cost proportionally.',
    'totals',v_totals,
    'previous_period',v_prev,
    'products',v_rows
  );
end;
$$;
revoke all on function public.product_profitability_v600(uuid,date,date,uuid,uuid,uuid,uuid,text,integer) from public,anon;
grant execute on function public.product_profitability_v600(uuid,date,date,uuid,uuid,uuid,uuid,text,integer) to authenticated;

create or replace function public.product_profit_explain_v600(
  p_tenant_id uuid,
  p_variant_id uuid,
  p_from date,
  p_to date,
  p_location_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  cur record;
  prev record;
  v_days integer;
  v_prev_from date;
  v_prev_to date;
  v_cur_net_qty numeric;
  v_prev_net_qty numeric;
  v_cur_avg_revenue numeric;
  v_prev_avg_revenue numeric;
  v_cur_avg_cost numeric;
  v_prev_avg_cost numeric;
  v_cur_discount_rate numeric;
  v_prev_discount_rate numeric;
  v_cur_return_rate numeric;
  v_prev_return_rate numeric;
  v_drivers jsonb := '[]'::jsonb;
  v_profit_change numeric;
begin
  if not private.has_permission(p_tenant_id,'profitability.view') then raise exception 'Permission denied' using errcode='42501'; end if;
  if p_variant_id is null or p_from is null or p_to is null or p_to<p_from then raise exception 'Variant and valid period are required'; end if;

  select * into cur from private.v600_product_profit_rows(p_tenant_id,p_from,p_to,p_location_id,p_variant_id) limit 1;
  v_days := (p_to-p_from)+1; v_prev_to:=p_from-1; v_prev_from:=v_prev_to-(v_days-1);
  select * into prev from private.v600_product_profit_rows(p_tenant_id,v_prev_from,v_prev_to,p_location_id,p_variant_id) limit 1;

  if cur.variant_id is null then
    select v.id as variant_id,p.id as product_id,p.name as product_name,v.name as variant_name,v.sku,p.category_id,c.name as category_name,p.brand_id,b.name as brand_name,
      0::numeric sold_qty,0::numeric sale_revenue,0::numeric sale_cogs,0::numeric sale_discount,0::numeric returned_qty,0::numeric return_revenue,0::numeric return_cogs,
      0::numeric net_revenue,0::numeric net_cogs,0::numeric gross_profit,null::numeric margin_pct
    into cur
    from public.product_variants v join public.products p on p.id=v.product_id and p.tenant_id=v.tenant_id
    left join public.product_categories c on c.id=p.category_id and c.tenant_id=p.tenant_id
    left join public.product_brands b on b.id=p.brand_id and b.tenant_id=p.tenant_id
    where v.tenant_id=p_tenant_id and v.id=p_variant_id;
    if cur.variant_id is null then raise exception 'Product variant not found'; end if;
  end if;
  if prev.variant_id is null then
    prev := cur;
    prev.sold_qty:=0; prev.sale_revenue:=0; prev.sale_cogs:=0; prev.sale_discount:=0; prev.returned_qty:=0; prev.return_revenue:=0; prev.return_cogs:=0; prev.net_revenue:=0; prev.net_cogs:=0; prev.gross_profit:=0; prev.margin_pct:=null;
  end if;

  v_cur_net_qty := cur.sold_qty-cur.returned_qty;
  v_prev_net_qty := prev.sold_qty-prev.returned_qty;
  v_cur_avg_revenue := case when v_cur_net_qty=0 then null else cur.net_revenue/v_cur_net_qty end;
  v_prev_avg_revenue := case when v_prev_net_qty=0 then null else prev.net_revenue/v_prev_net_qty end;
  v_cur_avg_cost := case when v_cur_net_qty=0 then null else cur.net_cogs/v_cur_net_qty end;
  v_prev_avg_cost := case when v_prev_net_qty=0 then null else prev.net_cogs/v_prev_net_qty end;
  v_cur_discount_rate := case when (cur.sale_revenue+cur.sale_discount)=0 then null else cur.sale_discount*100.0/(cur.sale_revenue+cur.sale_discount) end;
  v_prev_discount_rate := case when (prev.sale_revenue+prev.sale_discount)=0 then null else prev.sale_discount*100.0/(prev.sale_revenue+prev.sale_discount) end;
  v_cur_return_rate := case when cur.sold_qty=0 then null else cur.returned_qty*100.0/cur.sold_qty end;
  v_prev_return_rate := case when prev.sold_qty=0 then null else prev.returned_qty*100.0/prev.sold_qty end;
  v_profit_change := cur.gross_profit-prev.gross_profit;

  v_drivers := v_drivers || jsonb_build_array(jsonb_build_object(
    'driver','net_sales_change','impact_on_profit',round(cur.net_revenue-prev.net_revenue,4),
    'current',round(cur.net_revenue,4),'previous',round(prev.net_revenue,4),
    'explanation','Exact gross-profit bridge component: change in net product revenue.'
  ));
  v_drivers := v_drivers || jsonb_build_array(jsonb_build_object(
    'driver','cogs_change','impact_on_profit',round(-(cur.net_cogs-prev.net_cogs),4),
    'current',round(cur.net_cogs,4),'previous',round(prev.net_cogs,4),
    'explanation','Exact gross-profit bridge component: higher COGS reduces profit; lower COGS increases profit.'
  ));
  if v_cur_avg_cost is not null and v_prev_avg_cost is not null and v_cur_avg_cost is distinct from v_prev_avg_cost then
    v_drivers := v_drivers || jsonb_build_array(jsonb_build_object('driver','average_recognized_cost_per_net_unit','current',round(v_cur_avg_cost,4),'previous',round(v_prev_avg_cost,4),'change_pct',case when v_prev_avg_cost=0 then null else round((v_cur_avg_cost-v_prev_avg_cost)*100.0/v_prev_avg_cost,4) end,'diagnostic',true));
  end if;
  if v_cur_avg_revenue is not null and v_prev_avg_revenue is not null and v_cur_avg_revenue is distinct from v_prev_avg_revenue then
    v_drivers := v_drivers || jsonb_build_array(jsonb_build_object('driver','average_net_revenue_per_net_unit','current',round(v_cur_avg_revenue,4),'previous',round(v_prev_avg_revenue,4),'change_pct',case when v_prev_avg_revenue=0 then null else round((v_cur_avg_revenue-v_prev_avg_revenue)*100.0/v_prev_avg_revenue,4) end,'diagnostic',true));
  end if;
  if v_cur_discount_rate is distinct from v_prev_discount_rate then
    v_drivers := v_drivers || jsonb_build_array(jsonb_build_object('driver','discount_rate','current_pct',case when v_cur_discount_rate is null then null else round(v_cur_discount_rate,4) end,'previous_pct',case when v_prev_discount_rate is null then null else round(v_prev_discount_rate,4) end,'diagnostic',true));
  end if;
  if v_cur_return_rate is distinct from v_prev_return_rate then
    v_drivers := v_drivers || jsonb_build_array(jsonb_build_object('driver','return_rate','current_pct',case when v_cur_return_rate is null then null else round(v_cur_return_rate,4) end,'previous_pct',case when v_prev_return_rate is null then null else round(v_prev_return_rate,4) end,'diagnostic',true));
  end if;

  return jsonb_build_object(
    'product',jsonb_build_object('variant_id',cur.variant_id,'product_id',cur.product_id,'product_name',cur.product_name,'variant_name',cur.variant_name,'sku',cur.sku,'category',cur.category_name,'brand',cur.brand_name),
    'period',jsonb_build_object('from',p_from,'to',p_to),
    'equation',jsonb_build_object('label','Net Sales - Recognized COGS = Gross Profit','net_sales',round(cur.net_revenue,4),'recognized_cogs',round(cur.net_cogs,4),'gross_profit',round(cur.gross_profit,4),'margin_pct',cur.margin_pct),
    'returns',jsonb_build_object('returned_qty',cur.returned_qty,'revenue_reversed',round(cur.return_revenue,4),'cogs_reversed',round(cur.return_cogs,4)),
    'previous_period',jsonb_build_object('from',v_prev_from,'to',v_prev_to,'net_sales',round(prev.net_revenue,4),'recognized_cogs',round(prev.net_cogs,4),'gross_profit',round(prev.gross_profit,4),'margin_pct',prev.margin_pct),
    'profit_change',round(v_profit_change,4),
    'drivers',v_drivers,
    'integrity_note','Exact bridge drivers sum to gross-profit change. Diagnostic rates describe contributing conditions but are not asserted as additive causal impacts.'
  );
end;
$$;
revoke all on function public.product_profit_explain_v600(uuid,uuid,date,date,uuid) from public,anon;
grant execute on function public.product_profit_explain_v600(uuid,uuid,date,date,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values (258,'6.0.0-build1','Product Profitability + Profit Explanation','Adds deterministic product profitability using sale-item recognized COGS, net revenue before GST and proportional reversal of original sale-item revenue/COGS for returns. Adds exact gross-profit bridge and non-causal diagnostic drivers for cost, selling revenue, discount and return rates. Current product master cost is never used to rewrite historical profit.')
on conflict (migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;