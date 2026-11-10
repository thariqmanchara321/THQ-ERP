-- Preserve the natural report order until a user selects a sort column.
-- Refine user-facing stock basis text; no data or writer changes.
begin;
CREATE OR REPLACE FUNCTION private.inventory_report_gateway_v635(t uuid, action text, args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare k text:=coalesce(args->>'key','stock_snapshot');l uuid:=nullif(args->>'location_id','')::uuid;
 f date:=coalesce((args->>'from')::date,date_trunc('month',current_date)::date);z date:=coalesce((args->>'to')::date,current_date);
 days integer:=coalesce((args->>'days')::integer,30);expiry_days integer:=coalesce((args->>'expiry_days')::integer,30);
 off integer:=coalesce((args->>'offset')::integer,0);lim integer:=coalesce((args->>'limit')::integer,100);
 q text:=lower(trim(coalesce(args->>'query','')));sort_key text:=args->>'sort_key';desc_sort boolean:=coalesce((args->>'sort_desc')::boolean,false);
 filters jsonb:=coalesce(args->'filters','{}');defs jsonb;def jsonb;rows jsonb;page jsonb;summary jsonb;unit_totals jsonb;n integer;cost boolean;
 zone text;company text;currency text;location text;
begin
 perform private.inventory_report_assert_v635(t,l,k);
 cost:=private.erp_has_permission(t,'inventory.view_cost');defs:=private.inventory_report_definitions_v635();
 if action='catalog' then return (select jsonb_agg(d) from jsonb_array_elements(defs) d where cost or not (d->>'requires_cost')::boolean);end if;
 if action<>'run' then raise exception 'Unknown inventory report action' using errcode='22023';end if;
 if f>z or f is null or z is null or days not between 1 and 365 or expiry_days not between 0 and 3650 or off<0 or lim<0 or lim>500 then
  raise exception 'Invalid dates, lookback, expiry horizon or page range' using errcode='22023';end if;
 if length(q)>200 or jsonb_typeof(filters)<>'object' then raise exception 'Invalid report filters' using errcode='22023';end if;
 if exists(select 1 from jsonb_object_keys(filters) x where x not in('status','tracking_mode','unit_code','variant_id')) then raise exception 'Unknown inventory filter' using errcode='22023';end if;
 select d into def from jsonb_array_elements(defs) d where d->>'key'=k;
 if sort_key is not null and not exists(select 1 from jsonb_array_elements(def->'columns') c where c->>'key'=sort_key) then raise exception 'Invalid sort column' using errcode='22023';end if;
 -- Redact costs at the server before search, summary, pagination and export.
 select coalesce(jsonb_agg(r order by case when sort_key is null then ord end,case when not desc_sort then r->sort_key end asc nulls last,case when desc_sort then r->sort_key end desc nulls last,r->>'product_name',r->>'sku',r->>'location_name',r->>'id',r->>'variant_id',r->>'location_id',ord),'[]'::jsonb)
 into rows from (
  select case when cost then x else x-'average_cost'-'stock_value'-'available_value'-'held_value'-'purchase_cost_base'-'selling_price_base' end r,ord
  from private.inventory_report_rows_v635(t,k,f,z,l,days,expiry_days) with ordinality a(x,ord)
 ) a where (q='' or position(q in lower(r::text))>0)
 and not exists(select 1 from jsonb_each_text(filters) e where e.value<>'' and coalesce(r->>e.key,'')<>e.value);
 n:=jsonb_array_length(rows);
 if lim=0 and n>50000 then raise exception 'More than 50,000 matching rows. Narrow the period, store or product before exporting; no rows were exported.' using errcode='54000';end if;
 select coalesce(jsonb_agg(x),'[]'::jsonb) into page from (select value x from jsonb_array_elements(rows) with ordinality a(value,ord) order by ord offset off limit case when lim=0 then null else lim end) p;
 select coalesce(jsonb_agg(jsonb_build_object('unit_code',unit_code,'quantity',quantity,'available',available,'receipts',receipts,'issues',issues,'opening_quantity',opening_quantity,'closing_quantity',closing_quantity)),'[]'::jsonb)
 into unit_totals from (select coalesce(r->>'unit_code','UNCONFIGURED') unit_code,
 sum((r->>'quantity')::numeric) quantity,sum((r->>'available')::numeric) available,sum((r->>'receipts')::numeric) receipts,sum((r->>'issues')::numeric) issues,
 sum((r->>'opening_quantity')::numeric) opening_quantity,sum((r->>'closing_quantity')::numeric) closing_quantity from jsonb_array_elements(rows) r where r ? 'unit_code' group by r->>'unit_code' order by r->>'unit_code') u;
 summary:=jsonb_build_array(jsonb_build_object('key','records','label','Matching records','value',n,'type','number'));
 if k in('stock_snapshot','valuation','reorder','activity','reconciliation','stock_statement') then
  summary:=summary||(select jsonb_build_array(
   jsonb_build_object('key','low_stock','label','Low / out of stock','value',count(*) filter(where r->>'status' in('low_stock','out_of_stock')),'type','number'),
   jsonb_build_object('key','review','label','Stock / tracking gaps','value',count(*) filter(where abs(coalesce((r->>'ledger_variance')::numeric,0))>0.0001 or abs(coalesce((r->>'tracking_variance')::numeric,0))>0.0001),'type','number'),
   jsonb_build_object('key','non_moving','label','Non-moving stock lines','value',count(*) filter(where r->>'activity_status'='non_moving'),'type','number')) from jsonb_array_elements(rows) r);
  if cost and k<>'stock_statement' then summary:=summary||jsonb_build_array(jsonb_build_object('key','stock_value','label','Current stock value','value',(select coalesce(sum((r->>'stock_value')::numeric),0) from jsonb_array_elements(rows) r),'type','money'));end if;
 end if;
 select name into company from public.tenants where id=t;
 select timezone,currency_code into zone,currency from public.tenant_settings where tenant_id=t;
 select name into location from public.business_locations where tenant_id=t and id=l;
 return jsonb_build_object('definition',def,'columns',def->'columns','rows',page,'summary',summary,'unit_totals',unit_totals,'total_rows',n,'offset',off,
 'complete',off=0 and jsonb_array_length(page)=n,'context',jsonb_build_object('company',company,'currency',coalesce(currency,'INR'),'timezone',coalesce(zone,'UTC'),
 'location',coalesce(location,'All authorized stores'),'from',f,'to',z,'query',q,'filters',filters,'sort_key',sort_key,'sort_desc',desc_sort,'generated_at',current_timestamp,
 'summary_basis','All matching rows; physical quantities grouped by base unit','lookback_days',days,'expiry_days',expiry_days,'cost_visible',cost,
 'stock_basis','Current store balances and posted movements. Opening and closing quantities use stock posting dates.',
 'valuation_basis','Current location average cost; stock statements show posting-date quantities, not historical costs.',
 'quantity_basis','Configured base units; quantities in different units are never combined.',
 'tracking_change_history_available',to_regclass('private.tracking_conversions_v633') is not null));
end $function$;

notify pgrst,'reload schema';
commit;
