-- THQ ERP V4.8.5 — stock reconciliation/reporting and THQ API contract.
begin;

create or replace function public.stock_counts_list_v485(
  p_tenant_id uuid,p_location_id uuid default null,p_from date default null,p_to date default null,p_limit integer default 500
) returns table(
  id uuid,count_number text,location_id uuid,location_name text,status text,reconciliation_status text,notes text,
  line_count bigint,total_system_quantity numeric,total_counted_quantity numeric,total_variance numeric,created_at timestamptz,posted_at timestamptz
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.stock_count') and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Stock count permission required';end if;
  return query
  select c.id,c.count_number,c.location_id,l.location_code||' • '||l.name,c.status,c.reconciliation_status,c.notes,
    count(i.id),coalesce(sum(i.system_quantity),0),coalesce(sum(i.counted_quantity),0),coalesce(sum(i.variance),0),c.created_at,c.posted_at
  from public.stock_counts c join public.business_locations l on l.id=c.location_id left join public.stock_count_items i on i.count_id=c.id
  where c.tenant_id=p_tenant_id and (p_location_id is null or c.location_id=p_location_id)
    and (p_from is null or c.created_at::date>=p_from) and (p_to is null or c.created_at::date<=p_to)
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all') or private.erp_user_location_allowed(p_tenant_id,c.location_id,'view'))
  group by c.id,l.location_code,l.name order by c.created_at desc limit greatest(1,least(coalesce(p_limit,500),2000));
end$$;
grant execute on function public.stock_counts_list_v485(uuid,uuid,date,date,integer) to authenticated;

create or replace function public.stock_count_detail_v485(p_tenant_id uuid,p_count_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_loc uuid;v jsonb;
begin
  select location_id into v_loc from public.stock_counts where tenant_id=p_tenant_id and id=p_count_id;
  if v_loc is null then raise exception 'Stock count not found';end if;
  perform private.v4_location_access(p_tenant_id,v_loc,'view');
  select jsonb_build_object(
    'count',to_jsonb(c)||jsonb_build_object('location_name',l.location_code||' • '||l.name),
    'items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('product_name',p.name,'sku',pv.sku) order by p.name,pv.sku)
      from public.stock_count_items i join public.product_variants pv on pv.id=i.variant_id join public.products p on p.id=pv.product_id where i.count_id=c.id),'[]'::jsonb)
  ) into v from public.stock_counts c join public.business_locations l on l.id=c.location_id where c.tenant_id=p_tenant_id and c.id=p_count_id;
  return v;
end$$;
grant execute on function public.stock_count_detail_v485(uuid,uuid) to authenticated;

create or replace function public.inventory_stock_reconciliation_v485(
  p_tenant_id uuid,p_location_id uuid default null,p_query text default '',p_only_variance boolean default false,p_limit integer default 2000
) returns table(
  location_id uuid,location_name text,variant_id uuid,product_name text,sku text,tracking_mode text,
  location_quantity numeric,tracked_quantity numeric,reserved_quantity numeric,damaged_quantity numeric,quarantine_quantity numeric,available_quantity numeric,
  company_stock_quantity numeric,all_locations_quantity numeric,tracked_reconciled boolean,company_reconciled boolean,
  latest_count_number text,latest_counted_quantity numeric,latest_count_variance numeric,latest_count_at timestamptz,reconciliation_status text
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query
  with base as (
    select b.location_id,l.location_code||' • '||l.name location_name,b.variant_id,p.name product_name,pv.sku,
      private.v483_tracking_mode(p_tenant_id,b.variant_id) tracking_mode,b.quantity,b.reserved_quantity,b.damaged_quantity,b.quarantine_quantity,
      coalesce((select sum(sb.quantity) from public.stock_balances sb where sb.tenant_id=p_tenant_id and sb.variant_id=b.variant_id),0) company_qty,
      coalesce((select sum(lb.quantity) from public.location_stock_balances lb where lb.tenant_id=p_tenant_id and lb.variant_id=b.variant_id),0) locations_qty
    from public.location_stock_balances b join public.business_locations l on l.id=b.location_id join public.product_variants pv on pv.id=b.variant_id join public.products p on p.id=pv.product_id
    where b.tenant_id=p_tenant_id and (p_location_id is null or b.location_id=p_location_id)
      and (trim(coalesce(p_query,''))='' or lower(p.name) like q or lower(pv.sku) like q or lower(coalesce(pv.barcode,'')) like q)
      and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all') or private.erp_user_location_allowed(p_tenant_id,b.location_id,'view'))
  ), calc as (
    select base.*,
      case when base.tracking_mode='none' then base.quantity else private.v483_location_tracked_quantity(p_tenant_id,base.variant_id,base.location_id,base.tracking_mode) end tracked_qty,
      lc.count_number latest_count_number,li.counted_quantity latest_counted_quantity,li.variance latest_count_variance,lc.posted_at latest_count_at
    from base
    left join lateral (
      select c.id,c.count_number,c.posted_at from public.stock_counts c join public.stock_count_items ci on ci.count_id=c.id
      where c.tenant_id=p_tenant_id and c.location_id=base.location_id and ci.variant_id=base.variant_id and c.status='posted'
      order by c.posted_at desc nulls last,c.created_at desc limit 1
    ) lc on true
    left join public.stock_count_items li on li.count_id=lc.id and li.variant_id=base.variant_id
  )
  select calc.location_id,calc.location_name,calc.variant_id,calc.product_name,calc.sku,calc.tracking_mode,
    calc.quantity,calc.tracked_qty,calc.reserved_quantity,calc.damaged_quantity,calc.quarantine_quantity,
    greatest(calc.quantity-calc.reserved_quantity-calc.damaged_quantity-calc.quarantine_quantity,0),calc.company_qty,calc.locations_qty,
    abs(calc.quantity-calc.tracked_qty)<=0.000001,abs(calc.company_qty-calc.locations_qty)<=0.000001,
    calc.latest_count_number,calc.latest_counted_quantity,calc.latest_count_variance,calc.latest_count_at,
    case
      when abs(calc.company_qty-calc.locations_qty)>0.000001 then 'COMPANY/LOCATION MISMATCH'
      when calc.tracking_mode<>'none' and abs(calc.quantity-calc.tracked_qty)>0.000001 then 'TRACKING MISMATCH'
      when calc.reserved_quantity>0.000001 then 'RESERVED / PENDING TRANSFER'
      when calc.latest_count_variance is not null and abs(calc.latest_count_variance)>0.000001 then 'COUNT VARIANCE RECONCILED'
      else 'OK'
    end
  from calc
  where not coalesce(p_only_variance,false)
     or abs(calc.company_qty-calc.locations_qty)>0.000001
     or (calc.tracking_mode<>'none' and abs(calc.quantity-calc.tracked_qty)>0.000001)
     or abs(coalesce(calc.latest_count_variance,0))>0.000001
  order by case when abs(calc.company_qty-calc.locations_qty)>0.000001 or (calc.tracking_mode<>'none' and abs(calc.quantity-calc.tracked_qty)>0.000001) then 0 else 1 end,calc.location_name,calc.product_name,calc.sku
  limit greatest(1,least(coalesce(p_limit,2000),10000));
end$$;
grant execute on function public.inventory_stock_reconciliation_v485(uuid,uuid,text,boolean,integer) to authenticated;

create or replace function public.thq_api_contract_v480() returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
  'product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json',
  'resources',jsonb_build_array(
    'sync','attention','inventory-intelligence','inventory-movements','units','product-units','pricing','product-identifiers','product-lookup','label-templates',
    'tracking-policy','serials','batches','batch-history','warranties','customer-credit','supplier-payables','reorder-suggestions',
    'purchase-requests','purchase-orders','goods-receipts','purchase-invoices','supplier-payments-v2','supplier-ledger-v2','purchase-price-history','purchasing-dashboard',
    'warehouses','warehouse-inventory','stock-transfers','stock-counts','stock-reconciliation','business-summary','store-summary'
  ),
  'core_financial_posting','direct_hardened_rpc','authoritative_sale_pricing','pricing_resolve_v482','inventory_tracking','v4.8.3',
  'purchasing_engine','v4.8.4','warehouse_engine','v4.8.5','transfer_stock_event','dispatch_receive','stock_count_engine','trace_aware',
  'stock_receipt_event','goods_receipt','supplier_liability_event','purchase_invoice','mobile_ready',true
 )
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(152,'4.8.5','Warehouse & Transfers','Stock-count history/detail, company-vs-location and serial/batch reconciliation reporting, and THQ API v1 warehouse/transfer/count resources.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.5 migration 152 reconciliation/API contract applied' as status;
