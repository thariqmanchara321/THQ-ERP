-- Inventory Reports v6.3.5: additive reporting functions; existing writers unchanged.
begin;
CREATE OR REPLACE FUNCTION private.inventory_report_definitions_v635()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$ select '[{"key":"stock_snapshot","title":"Stock overview","category":"Stock","description":"Current physical, available, reserved, damaged and quarantined stock in each authorized store. Quantities use the configured base unit.","columns":[{"key":"sku","label":"SKU","type":"text","width":140},{"key":"product_name","label":"Product","type":"text","width":240},{"key":"location_name","label":"Store","type":"text","width":200},{"key":"unit_code","label":"Base unit","type":"text","width":105},{"key":"quantity","label":"On hand","type":"number","width":145},{"key":"available","label":"Available","type":"number","width":145},{"key":"reserved","label":"Reserved","type":"number","width":145},{"key":"damaged","label":"Damaged","type":"number","width":145},{"key":"quarantine","label":"Quarantine","type":"number","width":145},{"key":"tracking_mode","label":"Tracking","type":"text","width":160},{"key":"status","label":"Status","type":"text","width":160}],"basis":"current","requires_cost":false},{"key":"valuation","title":"Stock valuation","category":"Stock","description":"Current quantity \u00d7 current location average cost. Operational valuation, not a historical accounting valuation; held stock remains in physical stock value.","columns":[{"key":"sku","label":"SKU","type":"text","width":140},{"key":"product_name","label":"Product","type":"text","width":240},{"key":"location_name","label":"Store","type":"text","width":200},{"key":"unit_code","label":"Base unit","type":"text","width":105},{"key":"quantity","label":"Quantity","type":"number","width":145},{"key":"average_cost","label":"Average base cost","type":"money","width":165},{"key":"stock_value","label":"Stock Value","type":"money","width":165},{"key":"available_value","label":"Available Value","type":"money","width":165},{"key":"held_value","label":"Held Value","type":"money","width":165}],"basis":"current","requires_cost":true},{"key":"stock_statement","title":"Stock statement","category":"Movement","description":"Opening + receipts \u2212 issues = closing through the selected To date. Based on stock posting timestamps in the business timezone; ledger gaps remain visible.","columns":[{"key":"sku","label":"SKU","type":"text","width":140},{"key":"product_name","label":"Product","type":"text","width":240},{"key":"location_name","label":"Store","type":"text","width":200},{"key":"unit_code","label":"Base unit","type":"text","width":105},{"key":"opening_quantity","label":"Opening","type":"number","width":145},{"key":"receipts","label":"Receipts","type":"number","width":145},{"key":"issues","label":"Issues","type":"number","width":145},{"key":"closing_quantity","label":"Closing","type":"number","width":145},{"key":"ledger_variance","label":"Ledger gap","type":"number","width":145},{"key":"status","label":"Status","type":"text","width":160}],"basis":"as_of","requires_cost":false},{"key":"movements","title":"Movement ledger","category":"Movement","description":"Every stock posting: opening, purchases, sales, returns, transfers, counts and adjustments, with saved references and before/after balances. These are posting dates.","columns":[{"key":"created_at","label":"Posted at","type":"datetime","width":185},{"key":"sku","label":"SKU","type":"text","width":140},{"key":"product_name","label":"Product","type":"text","width":240},{"key":"location_name","label":"Store","type":"text","width":200},{"key":"unit_code","label":"Base unit","type":"text","width":105},{"key":"movement_type","label":"Movement","type":"text","width":160},{"key":"reference_number","label":"Document reference","type":"text","width":160},{"key":"quantity_in","label":"In","type":"number","width":145},{"key":"quantity_out","label":"Out","type":"number","width":145},{"key":"balance_before","label":"Before","type":"number","width":145},{"key":"balance_after","label":"After","type":"number","width":145},{"key":"note","label":"Notes","type":"text","width":280}],"basis":"period","requires_cost":false},{"key":"reorder","title":"Reorder planning","category":"Planning","description":"Low and out-of-stock items, base-unit sales velocity, days of cover and suggested replenishment. Suggestions respect location reorder/max stock settings.","columns":[{"key":"sku","label":"SKU","type":"text","width":140},{"key":"product_name","label":"Product","type":"text","width":240},{"key":"location_name","label":"Store","type":"text","width":200},{"key":"unit_code","label":"Base unit","type":"text","width":105},{"key":"available","label":"Available","type":"number","width":145},{"key":"reorder_level","label":"Reorder Level","type":"number","width":145},{"key":"max_stock","label":"Max Stock","type":"number","width":145},{"key":"net_sold_quantity","label":"Net sold","type":"number","width":145},{"key":"daily_sales","label":"Daily Sales","type":"number","width":145},{"key":"days_cover","label":"Days Cover","type":"number","width":145},{"key":"suggested_reorder","label":"Suggested order","type":"number","width":145},{"key":"status","label":"Status","type":"text","width":160}],"basis":"current","requires_cost":false},{"key":"activity","title":"Stock activity and age","category":"Planning","description":"Days since the last inbound stock posting and last sale posting. This is an activity age, not FIFO layer age. Slow/non-moving windows use the selected lookback days.","columns":[{"key":"sku","label":"SKU","type":"text","width":140},{"key":"product_name","label":"Product","type":"text","width":240},{"key":"location_name","label":"Store","type":"text","width":200},{"key":"unit_code","label":"Base unit","type":"text","width":105},{"key":"quantity","label":"Quantity","type":"number","width":145},{"key":"net_sold_quantity","label":"Net sold","type":"number","width":145},{"key":"daily_sales","label":"Daily Sales","type":"number","width":145},{"key":"days_since_inbound","label":"Days since receipt","type":"number","width":145},{"key":"days_since_sale","label":"Days since sale","type":"number","width":145},{"key":"days_cover","label":"Days Cover","type":"number","width":145},{"key":"activity_status","label":"Activity","type":"text","width":160}],"basis":"current","requires_cost":false},{"key":"batches","title":"Batch register","category":"Tracking","description":"Current stock by batch and store, expiry, manufacture date, quality and tracked quantities. Historical batch evidence is preserved when tracking modes change.","columns":[{"key":"sku","label":"SKU","type":"text","width":140},{"key":"product_name","label":"Product","type":"text","width":240},{"key":"location_name","label":"Store","type":"text","width":200},{"key":"unit_code","label":"Base unit","type":"text","width":105},{"key":"batch_number","label":"Batch","type":"text","width":160},{"key":"quality_label","label":"Quality","type":"text","width":160},{"key":"quantity","label":"Quantity","type":"number","width":145},{"key":"available","label":"Available","type":"number","width":145},{"key":"reserved","label":"Reserved","type":"number","width":145},{"key":"damaged","label":"Damaged","type":"number","width":145},{"key":"manufactured_on","label":"Manufactured","type":"date","width":150},{"key":"expiry_on","label":"Expiry","type":"date","width":150},{"key":"days_to_expiry","label":"Days To Expiry","type":"number","width":145},{"key":"status","label":"Status","type":"text","width":160}],"basis":"current","requires_cost":false},{"key":"expiry","title":"Expiry watch","category":"Tracking","description":"Current positive batch stock that is expired or expires within the selected expiry horizon, measured from today in the business timezone.","columns":[{"key":"sku","label":"SKU","type":"text","width":140},{"key":"product_name","label":"Product","type":"text","width":240},{"key":"location_name","label":"Store","type":"text","width":200},{"key":"unit_code","label":"Base unit","type":"text","width":105},{"key":"batch_number","label":"Batch","type":"text","width":160},{"key":"quantity","label":"Quantity","type":"number","width":145},{"key":"available","label":"Available","type":"number","width":145},{"key":"expiry_on","label":"Expiry","type":"date","width":150},{"key":"days_to_expiry","label":"Days To Expiry","type":"number","width":145},{"key":"status","label":"Status","type":"text","width":160}],"basis":"current","requires_cost":false},{"key":"serials","title":"Serial register","category":"Tracking","description":"Current serial status, location, receipt and sale dates, and linked business document numbers. Retired records remain reportable.","columns":[{"key":"sku","label":"SKU","type":"text","width":140},{"key":"product_name","label":"Product","type":"text","width":240},{"key":"location_name","label":"Store","type":"text","width":200},{"key":"unit_code","label":"Base unit","type":"text","width":105},{"key":"serial_number","label":"Serial number","type":"text","width":160},{"key":"status","label":"Status","type":"text","width":160},{"key":"received_at","label":"Received","type":"datetime","width":185},{"key":"sold_at","label":"Sold","type":"datetime","width":185},{"key":"purchase_number","label":"Purchase","type":"text","width":160},{"key":"sale_number","label":"Sale","type":"text","width":160}],"basis":"current","requires_cost":false},{"key":"warranties","title":"Warranty register","category":"Tracking","description":"Saved product warranties with serial/batch, customer, invoice and coverage dates. Date range selects coverage expiry dates; status is current.","columns":[{"key":"sku","label":"SKU","type":"text","width":140},{"key":"product_name","label":"Product","type":"text","width":240},{"key":"location_name","label":"Store","type":"text","width":200},{"key":"unit_code","label":"Base unit","type":"text","width":105},{"key":"serial_number","label":"Serial","type":"text","width":160},{"key":"batch_number","label":"Batch","type":"text","width":160},{"key":"customer_name","label":"Customer","type":"text","width":160},{"key":"sale_number","label":"Invoice","type":"text","width":160},{"key":"warranty_start","label":"Starts","type":"date","width":150},{"key":"warranty_expiry","label":"Ends","type":"date","width":150},{"key":"quantity","label":"Quantity","type":"number","width":145},{"key":"status","label":"Status","type":"text","width":160}],"basis":"expiry","requires_cost":false},{"key":"transfers","title":"Transfer register","category":"Operations","description":"Requested, approved, dispatched, in-transit, received and cancelled transfers. One line per product, with quantities and transport reference. Status is current.","columns":[{"key":"transfer_number","label":"Transfer","type":"text","width":160},{"key":"created_at","label":"Requested","type":"datetime","width":185},{"key":"product_name","label":"Product","type":"text","width":240},{"key":"sku","label":"SKU","type":"text","width":160},{"key":"unit_code","label":"Base unit","type":"text","width":160},{"key":"from_location","label":"From store","type":"text","width":200},{"key":"to_location","label":"To store","type":"text","width":200},{"key":"quantity","label":"Requested","type":"number","width":145},{"key":"dispatched_quantity","label":"Dispatched","type":"number","width":145},{"key":"received_quantity","label":"Received","type":"number","width":145},{"key":"in_transit_quantity","label":"In transit","type":"number","width":145},{"key":"status","label":"Status","type":"text","width":160},{"key":"transport_reference","label":"Transport reference","type":"text","width":160}],"basis":"period_current","requires_cost":false},{"key":"stock_counts","title":"Stock count variance","category":"Operations","description":"Saved physical counts, system quantities and variance; posted counts are distinguished from drafts. Dates select the count creation timestamp.","columns":[{"key":"count_number","label":"Count","type":"text","width":160},{"key":"created_at","label":"Created","type":"datetime","width":185},{"key":"sku","label":"SKU","type":"text","width":140},{"key":"product_name","label":"Product","type":"text","width":240},{"key":"location_name","label":"Store","type":"text","width":200},{"key":"unit_code","label":"Base unit","type":"text","width":105},{"key":"system_quantity","label":"System","type":"number","width":145},{"key":"counted_quantity","label":"Counted","type":"number","width":145},{"key":"variance","label":"Variance","type":"number","width":145},{"key":"status","label":"Status","type":"text","width":160},{"key":"reconciliation_note","label":"Notes","type":"text","width":260}],"basis":"period","requires_cost":false},{"key":"reconciliation","title":"Stock and tracking checks","category":"Checks","description":"Physical balance compared with the location movement ledger and current serial/batch tracking. Review gaps without changing inventory or merging the legacy ledger.","columns":[{"key":"sku","label":"SKU","type":"text","width":140},{"key":"product_name","label":"Product","type":"text","width":240},{"key":"location_name","label":"Store","type":"text","width":200},{"key":"unit_code","label":"Base unit","type":"text","width":105},{"key":"quantity","label":"Physical stock","type":"number","width":145},{"key":"ledger_quantity","label":"Location ledger","type":"number","width":145},{"key":"ledger_variance","label":"Ledger gap","type":"number","width":145},{"key":"tracking_mode","label":"Tracking","type":"text","width":160},{"key":"tracked_quantity","label":"Tracked","type":"number","width":145},{"key":"tracking_variance","label":"Tracking gap","type":"number","width":145},{"key":"status","label":"Status","type":"text","width":160}],"basis":"current","requires_cost":false},{"key":"tracking_events","title":"Trace history","category":"Tracking","description":"Saved batch/serial events, their document reference and store. Trace-only openings during a tracking conversion are identified and do not add physical stock.","columns":[{"key":"created_at","label":"Event at","type":"datetime","width":185},{"key":"sku","label":"SKU","type":"text","width":140},{"key":"product_name","label":"Product","type":"text","width":240},{"key":"location_name","label":"Store","type":"text","width":200},{"key":"unit_code","label":"Base unit","type":"text","width":105},{"key":"serial_number","label":"Serial","type":"text","width":160},{"key":"batch_number","label":"Batch","type":"text","width":160},{"key":"event_type","label":"Event","type":"text","width":160},{"key":"quantity","label":"Quantity","type":"number","width":145},{"key":"reference_number","label":"Document reference","type":"text","width":160},{"key":"trace_only","label":"Trace only","type":"text","width":160}],"basis":"period","requires_cost":false},{"key":"tracking_changes","title":"Tracking mode changes","category":"Checks","description":"Audited transitions between quantity, batch and serial tracking with revision, reason and authorized store stock snapshots. Historical documents and physical stock remain unchanged.","columns":[{"key":"created_at","label":"Changed at","type":"datetime","width":185},{"key":"sku","label":"SKU","type":"text","width":160},{"key":"product_name","label":"Product","type":"text","width":240},{"key":"from_mode","label":"From","type":"text","width":160},{"key":"to_mode","label":"To","type":"text","width":160},{"key":"revision","label":"Revision","type":"number","width":145},{"key":"reason","label":"Reason","type":"text","width":350}],"basis":"period","requires_cost":false}]'::jsonb $function$;
CREATE OR REPLACE FUNCTION private.inventory_report_assert_v635(t uuid, l uuid DEFAULT NULL::uuid, k text DEFAULT 'stock_snapshot'::text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
 if auth.uid() is null or not private.erp_user_has_tenant_access(t)
 or not private.erp_has_permission(t,'inventory.view') or not private.erp_has_permission(t,'reports.view') then
  raise exception 'Inventory and Reports view access required' using errcode='42501';
 end if;
 if not exists(select 1 from public.tenant_modules where tenant_id=t and module_key='inventory' and enabled)
 or not exists(select 1 from public.tenant_modules where tenant_id=t and module_key='reports' and enabled) then
  raise exception 'Inventory and Reports modules must be enabled' using errcode='42501';
 end if;
 if not exists(select 1 from jsonb_array_elements(private.inventory_report_definitions_v635()) d where d->>'key'=k) then
  raise exception 'Unknown inventory report' using errcode='22023';
 end if;
 if k='valuation' and not private.erp_has_permission(t,'inventory.view_cost') then
  raise exception 'Inventory cost view access required' using errcode='42501';
 end if;
 if l is not null and not private.reports_scope_v631(t,l,l,'view') then
  raise exception 'Store access denied' using errcode='42501';
 end if;
end $function$;
CREATE OR REPLACE FUNCTION private.inventory_report_stock_v635(t uuid, l uuid, f date, z date, days integer)
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
with settings as (select coalesce((select timezone from public.tenant_settings where tenant_id=t),'UTC') zone),
slots as (
 select x.location_id,x.variant_id from public.location_stock_balances x where x.tenant_id=t
 union select x.location_id,x.variant_id from public.location_product_settings x where x.tenant_id=t
 union select x.location_id,x.variant_id from public.location_stock_movements x where x.tenant_id=t
), base as (
 select v.id variant_id,bl.id location_id,p.name product_name,v.sku,v.barcode,bl.name location_name,bl.location_code,
  coalesce(u.code,'UNCONFIGURED') unit_code,coalesce(c.name,'Uncategorized') category,
  coalesce(tp.tracking_mode,'quantity') tracking_mode,coalesce(tp.tracking_revision,0) tracking_revision,
  coalesce(b.quantity,0) quantity,coalesce(b.reserved_quantity,0) reserved,coalesce(b.damaged_quantity,0) damaged,coalesce(b.quarantine_quantity,0) quarantine,
  coalesce(b.quantity,0)-coalesce(b.reserved_quantity,0)-coalesce(b.damaged_quantity,0)-coalesce(b.quarantine_quantity,0) available,
  coalesce(b.average_cost,v.cost_price,0) average_cost,coalesce(lp.reorder_level,v.reorder_level,0) reorder_level,coalesce(lp.max_stock,0) max_stock,lp.rack_code,
  coalesce(m.ledger_quantity,0) ledger_quantity,coalesce(m.receipts,0) receipts,coalesce(m.issues,0) issues,
  coalesce(b.quantity,0)-coalesce(m.after_start,0) opening_quantity,coalesce(b.quantity,0)-coalesce(m.after_end,0) closing_quantity,
  greatest(coalesce(m.sold,0),0) net_sold_quantity,m.last_sale,m.last_inbound,
  case coalesce(tp.tracking_mode,'quantity')
   when 'serial' then (select count(*)::numeric from public.inventory_serials_v483 s where s.tenant_id=t and s.variant_id=v.id and s.current_location_id=bl.id and s.status in('in_stock','reserved','damaged','quarantine'))
   when 'batch' then (select coalesce(sum(bb.quantity),0) from public.inventory_batch_balances_v483 bb join public.inventory_batches_v483 bt on bt.id=bb.batch_id and bt.tenant_id=bb.tenant_id where bb.tenant_id=t and bt.variant_id=v.id and bb.location_id=bl.id)
   else null end tracked_quantity,
  ((current_timestamp at time zone settings.zone)::date) today,settings.zone
 from slots s join public.business_locations bl on bl.id=s.location_id and bl.tenant_id=t
 join public.product_variants v on v.id=s.variant_id and v.tenant_id=t
 join public.products p on p.id=v.product_id and p.tenant_id=t
 left join public.product_categories c on c.id=p.category_id and c.tenant_id=t
 left join public.location_stock_balances b on b.tenant_id=t and b.location_id=s.location_id and b.variant_id=s.variant_id
 left join public.location_product_settings lp on lp.tenant_id=t and lp.location_id=s.location_id and lp.variant_id=s.variant_id
 left join public.product_tracking_policies_v483 tp on tp.tenant_id=t and tp.variant_id=v.id
 left join public.product_units_v481 pu on pu.tenant_id=t and pu.variant_id=v.id and pu.is_base and pu.active
 left join public.inventory_units_v481 u on u.tenant_id=t and u.id=pu.unit_id
 cross join settings
 left join lateral (
  select sum(coalesce(m.base_quantity_delta,m.quantity_delta)) ledger_quantity,
   sum(greatest(coalesce(m.base_quantity_delta,m.quantity_delta),0)) filter(where (m.created_at at time zone settings.zone)::date between f and z) receipts,
   sum(greatest(-coalesce(m.base_quantity_delta,m.quantity_delta),0)) filter(where (m.created_at at time zone settings.zone)::date between f and z) issues,
   sum(coalesce(m.base_quantity_delta,m.quantity_delta)) filter(where (m.created_at at time zone settings.zone)::date>=f) after_start,
   sum(coalesce(m.base_quantity_delta,m.quantity_delta)) filter(where (m.created_at at time zone settings.zone)::date>z) after_end,
   -sum(coalesce(m.base_quantity_delta,m.quantity_delta)) filter(where m.movement_type in('sale','sale_return','sales_return') and (m.created_at at time zone settings.zone)::date between (current_timestamp at time zone settings.zone)::date-days+1 and (current_timestamp at time zone settings.zone)::date) sold,
   max(m.created_at) filter(where m.movement_type='sale') last_sale,
   max(m.created_at) filter(where coalesce(m.base_quantity_delta,m.quantity_delta)>0) last_inbound
  from public.location_stock_movements m where m.tenant_id=t and m.location_id=s.location_id and m.variant_id=s.variant_id
 ) m on true
 where p.item_type<>'service' and (l is null or s.location_id=l)
  and private.reports_scope_v631(t,s.location_id,l,'view')
  and (coalesce(lp.active,true) or coalesce(b.quantity,0)<>0 or coalesce(m.ledger_quantity,0)<>0)
), computed as (
 select *,quantity-ledger_quantity ledger_variance,case when tracked_quantity is null then null else quantity-tracked_quantity end tracking_variance,
  round(quantity*average_cost,2) stock_value,round(available*average_cost,2) available_value,round((reserved+damaged+quarantine)*average_cost,2) held_value,
  round(net_sold_quantity/days,4) daily_sales,case when net_sold_quantity>0 then round(available*days/net_sold_quantity,1) else null end days_cover,
  case when last_sale is null then null else today-(last_sale at time zone zone)::date end days_since_sale,
  case when last_inbound is null then null else today-(last_inbound at time zone zone)::date end days_since_inbound,
  case when available<=0 then 'out_of_stock' when reorder_level>0 and available<=reorder_level then 'low_stock' when max_stock>0 and available>max_stock then 'overstock' else 'healthy' end status,
  case when quantity<=0 then 'no_stock' when net_sold_quantity<=0 then 'non_moving' when available>0 and available*days/net_sold_quantity>90 then 'slow_moving' else 'active' end activity_status,
  greatest(case when available<=reorder_level then greatest(case when max_stock>0 then max_stock else reorder_level*2 end-available,0) else 0 end,0) suggested_reorder
 from base
)
select to_jsonb(x)-'zone'-'today' from computed x order by product_name,sku,location_name,variant_id,location_id
$function$;
CREATE OR REPLACE FUNCTION private.inventory_report_rows_v635(t uuid, k text, f date, z date, l uuid, days integer, expiry_days integer)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare zone text:=coalesce((select timezone from public.tenant_settings where tenant_id=t),'UTC');today date:=(current_timestamp at time zone zone)::date;
begin
 perform private.inventory_report_assert_v635(t,l,k);
 if k in('stock_snapshot','valuation','stock_statement','reorder','activity','reconciliation') then
  return query select case when k='stock_statement' then x||jsonb_build_object('status',case when abs((x->>'ledger_variance')::numeric)>0.0001 then 'ledger_gap' else 'reconciled' end)
   when k='reconciliation' then x||jsonb_build_object('status',case when abs((x->>'ledger_variance')::numeric)>0.0001 or abs(coalesce((x->>'tracking_variance')::numeric,0))>0.0001 then 'review_required' else 'reconciled' end)
   else x end from private.inventory_report_stock_v635(t,l,f,z,days) x
   where k<>'reorder' or x->>'status' in('low_stock','out_of_stock');
 elsif k='movements' then
  return query with ledger as (
   select m.*,coalesce(m.base_quantity_delta,m.quantity_delta) delta,
    coalesce(b.quantity,0)-coalesce(sum(coalesce(m.base_quantity_delta,m.quantity_delta)) over(partition by m.location_id,m.variant_id order by m.created_at,m.id rows between 1 following and unbounded following),0) derived_after,
    coalesce(b.quantity,0)-sum(coalesce(m.base_quantity_delta,m.quantity_delta)) over(partition by m.location_id,m.variant_id) ledger_variance,
    p.name product_name,v.sku,bl.name location_name,coalesce(u.code,'UNCONFIGURED') base_unit
   from public.location_stock_movements m join public.product_variants v on v.id=m.variant_id and v.tenant_id=t
   join public.products p on p.id=v.product_id and p.tenant_id=t
   join public.business_locations bl on bl.id=m.location_id and bl.tenant_id=t
   left join public.location_stock_balances b on b.tenant_id=t and b.location_id=m.location_id and b.variant_id=m.variant_id
   left join public.product_units_v481 pu on pu.tenant_id=t and pu.variant_id=v.id and pu.is_base and pu.active
   left join public.inventory_units_v481 u on u.tenant_id=t and u.id=pu.unit_id
   where m.tenant_id=t and (l is null or m.location_id=l) and private.reports_scope_v631(t,m.location_id,l,'view')
  ) select jsonb_build_object('id',m.id,'variant_id',m.variant_id,'location_id',m.location_id,'created_at',m.created_at,
   'product_name',m.product_name,'sku',m.sku,'location_name',m.location_name,'unit_code',m.base_unit,'movement_type',m.movement_type,
   'quantity_in',greatest(m.delta,0),'quantity_out',greatest(-m.delta,0),'quantity',m.delta,
   'balance_before',coalesce(m.balance_before,m.derived_after-m.delta),'balance_after',coalesce(m.balance_after,m.derived_after),
   'ledger_variance',m.ledger_variance,'balance_basis',case when m.balance_after is null then 'Reconstructed from current stock' else 'Saved at posting' end,
   'reference_number',m.reference_number,'reference_type',m.reference_type,'note',m.note,'display_quantity',m.display_quantity,'display_unit',m.unit_code,'conversion_to_base',m.conversion_to_base)
   from ledger m where (m.created_at at time zone zone)::date between f and z order by m.created_at desc,m.id;
 elsif k in('batches','expiry') then
  return query select jsonb_build_object('id',b.id,'variant_id',b.variant_id,'location_id',x.location_id,'sku',v.sku,'product_name',p.name,'location_name',bl.name,
   'unit_code',coalesce(u.code,'UNCONFIGURED'),'batch_number',b.batch_number,'quality_label',b.quality_label,'quantity',x.quantity,'reserved',x.reserved_quantity,'damaged',x.damaged_quantity,
   'available',x.quantity-x.reserved_quantity-x.damaged_quantity,'manufactured_on',b.manufactured_on,'expiry_on',b.expiry_on,'days_to_expiry',b.expiry_on-today,
   'tracking_mode',coalesce(tp.tracking_mode,'quantity'),'status',case when b.expiry_on<today then 'expired' when b.expiry_on<=today+expiry_days then 'expiring_soon' else b.status end,
   'purchase_cost_base',b.purchase_cost_base,'selling_price_base',b.selling_price_base,'notes',b.notes)
  from public.inventory_batch_balances_v483 x join public.inventory_batches_v483 b on b.id=x.batch_id and b.tenant_id=t
  join public.product_variants v on v.id=b.variant_id and v.tenant_id=t join public.products p on p.id=v.product_id and p.tenant_id=t
  join public.business_locations bl on bl.id=x.location_id and bl.tenant_id=t
  left join public.product_tracking_policies_v483 tp on tp.tenant_id=t and tp.variant_id=v.id
  left join public.product_units_v481 pu on pu.tenant_id=t and pu.variant_id=v.id and pu.is_base and pu.active left join public.inventory_units_v481 u on u.tenant_id=t and u.id=pu.unit_id
  where x.tenant_id=t and (l is null or x.location_id=l) and private.reports_scope_v631(t,x.location_id,l,'view')
   and (k='batches' or (x.quantity>0 and b.expiry_on<=today+expiry_days)) order by b.expiry_on nulls last,b.batch_number,bl.name,b.id;
 elsif k='serials' then
  return query select jsonb_build_object('id',s.id,'variant_id',v.id,'location_id',s.current_location_id,'sku',v.sku,'product_name',p.name,'location_name',bl.name,
   'unit_code',coalesce(u.code,'UNCONFIGURED'),'serial_number',s.serial_number,'status',s.status,'received_at',s.received_at,'sold_at',s.sold_at,
   'purchase_number',pu.purchase_number,'sale_number',sa.sale_number,'notes',s.notes,'quantity',1)
  from public.inventory_serials_v483 s join public.product_variants v on v.id=s.variant_id and v.tenant_id=t join public.products p on p.id=v.product_id and p.tenant_id=t
  left join public.business_locations bl on bl.id=s.current_location_id and bl.tenant_id=t
  left join public.purchases pu on pu.id=s.purchase_id and pu.tenant_id=t left join public.sales sa on sa.id=s.sale_id and sa.tenant_id=t
  left join public.product_units_v481 punit on punit.tenant_id=t and punit.variant_id=v.id and punit.is_base and punit.active left join public.inventory_units_v481 u on u.tenant_id=t and u.id=punit.unit_id
  where s.tenant_id=t and (l is null or s.current_location_id=l) and private.reports_scope_v631(t,s.current_location_id,l,'view') order by s.serial_number,s.id;
 elsif k='warranties' then
  return query select jsonb_build_object('id',w.id,'variant_id',v.id,'location_id',o.location_id,'sku',v.sku,'product_name',p.name,'location_name',bl.name,'unit_code',coalesce(u.code,'UNCONFIGURED'),
   'serial_number',s.serial_number,'batch_number',b.batch_number,'sale_number',sa.sale_number,'customer_name',c.name,'warranty_start',w.warranty_start,'warranty_expiry',w.warranty_expiry,
   'quantity',w.quantity,'status',case when w.status='active' and w.warranty_expiry<today then 'expired' else w.status end,'terms',w.terms)
  from public.product_warranties_v483 w join public.product_variants v on v.id=w.variant_id and v.tenant_id=t join public.products p on p.id=v.product_id and p.tenant_id=t
  left join public.inventory_serials_v483 s on s.id=w.serial_id and s.tenant_id=t left join public.inventory_batches_v483 b on b.id=w.batch_id and b.tenant_id=t
  left join public.sales sa on sa.id=w.sale_id and sa.tenant_id=t left join public.customers c on c.id=w.customer_id and c.tenant_id=t
  left join public.document_origins o on o.tenant_id=t and o.entity_type='sale' and o.entity_id=w.sale_id left join public.business_locations bl on bl.id=o.location_id and bl.tenant_id=t
  left join public.product_units_v481 pu on pu.tenant_id=t and pu.variant_id=v.id and pu.is_base and pu.active left join public.inventory_units_v481 u on u.tenant_id=t and u.id=pu.unit_id
  where w.tenant_id=t and w.warranty_expiry between f and z and private.reports_scope_v631(t,o.location_id,l,'view') order by w.warranty_expiry,w.id;
 elsif k='transfers' then
  return query select jsonb_build_object('id',i.id,'variant_id',v.id,'sku',v.sku,'product_name',p.name,'unit_code',coalesce(u.code,'UNCONFIGURED'),
   'transfer_number',x.transfer_number,'created_at',x.created_at,'from_location',a.name,'to_location',b.name,'quantity',i.quantity,'dispatched_quantity',i.dispatched_quantity,
   'received_quantity',i.received_quantity,'in_transit_quantity',case when x.status in('dispatched','in_transit','partially_received') then greatest(i.dispatched_quantity-i.received_quantity,0) else 0 end,
   'status',x.status,'expected_arrival_date',x.expected_arrival_date,'transport_reference',x.transport_reference,'dispatch_note',x.dispatch_note,'receive_note',x.receive_note,'note',i.note)
  from public.stock_transfers x join public.stock_transfer_items i on i.transfer_id=x.id join public.product_variants v on v.id=i.variant_id and v.tenant_id=t
  join public.products p on p.id=v.product_id and p.tenant_id=t join public.business_locations a on a.id=x.from_location_id and a.tenant_id=t join public.business_locations b on b.id=x.to_location_id and b.tenant_id=t
  left join public.product_units_v481 pu on pu.tenant_id=t and pu.variant_id=v.id and pu.is_base and pu.active left join public.inventory_units_v481 u on u.tenant_id=t and u.id=pu.unit_id
  where x.tenant_id=t and (x.created_at at time zone zone)::date between f and z
   and (private.reports_scope_v631(t,x.from_location_id,l,'view') or private.reports_scope_v631(t,x.to_location_id,l,'view')) order by x.created_at desc,x.transfer_number,i.id;
 elsif k='stock_counts' then
  return query select jsonb_build_object('id',i.id,'variant_id',v.id,'location_id',x.location_id,'sku',v.sku,'product_name',p.name,'location_name',bl.name,'unit_code',coalesce(u.code,'UNCONFIGURED'),
   'count_number',x.count_number,'created_at',x.created_at,'posted_at',x.posted_at,'status',x.status,'system_quantity',i.system_quantity,'counted_quantity',i.counted_quantity,
   'variance',i.variance,'tracking_mode',i.tracking_mode,'reconciliation_note',i.reconciliation_note,'notes',x.notes)
  from public.stock_counts x join public.stock_count_items i on i.count_id=x.id join public.product_variants v on v.id=i.variant_id and v.tenant_id=t join public.products p on p.id=v.product_id and p.tenant_id=t
  join public.business_locations bl on bl.id=x.location_id and bl.tenant_id=t left join public.product_units_v481 pu on pu.tenant_id=t and pu.variant_id=v.id and pu.is_base and pu.active left join public.inventory_units_v481 u on u.tenant_id=t and u.id=pu.unit_id
  where x.tenant_id=t and (x.created_at at time zone zone)::date between f and z and private.reports_scope_v631(t,x.location_id,l,'view') order by x.created_at desc,x.count_number,i.id;
 elsif k='tracking_events' then
  return query select jsonb_build_object('id',e.id,'variant_id',v.id,'location_id',e.location_id,'sku',v.sku,'product_name',p.name,'location_name',bl.name,'unit_code',coalesce(u.code,'UNCONFIGURED'),
   'created_at',e.created_at,'serial_number',s.serial_number,'batch_number',b.batch_number,'event_type',e.event_type,'quantity',e.quantity,'reference_number',e.reference_number,
   'trace_only',coalesce((e.metadata->>'trace_only')::boolean,false))
  from public.inventory_trace_events_v483 e join public.product_variants v on v.id=e.variant_id and v.tenant_id=t join public.products p on p.id=v.product_id and p.tenant_id=t
  left join public.business_locations bl on bl.id=e.location_id and bl.tenant_id=t left join public.inventory_serials_v483 s on s.id=e.serial_id and s.tenant_id=t left join public.inventory_batches_v483 b on b.id=e.batch_id and b.tenant_id=t
  left join public.product_units_v481 pu on pu.tenant_id=t and pu.variant_id=v.id and pu.is_base and pu.active left join public.inventory_units_v481 u on u.tenant_id=t and u.id=pu.unit_id
  where e.tenant_id=t and (e.created_at at time zone zone)::date between f and z and private.reports_scope_v631(t,e.location_id,l,'view') order by e.created_at desc,e.id;
 elsif k='tracking_changes' then
  if to_regclass('private.tracking_conversions_v633') is not null then
   return query execute $q$select jsonb_build_object('id',x.id,'variant_id',v.id,'sku',v.sku,'product_name',p.name,'created_at',x.created_at,
    'from_mode',x.from_mode,'to_mode',x.to_mode,'revision',x.revision,'reason',x.reason,
    'stock_snapshot',coalesce((select jsonb_agg(jsonb_build_object('location_name',bl.name,'quantity',s->'quantity')) from jsonb_array_elements(x.stock_snapshot) s
      join public.business_locations bl on bl.tenant_id=$1 and bl.id=(s->>'location_id')::uuid where private.reports_scope_v631($1,bl.id,$4,'view')),'[]'::jsonb))
    from private.tracking_conversions_v633 x join public.product_variants v on v.tenant_id=$1 and v.id=x.variant_id join public.products p on p.tenant_id=$1 and p.id=v.product_id
    where x.tenant_id=$1 and (x.created_at at time zone $5)::date between $2 and $3
    and exists(select 1 from jsonb_array_elements(x.stock_snapshot) s where private.reports_scope_v631($1,(s->>'location_id')::uuid,$4,'view'))
    order by x.created_at desc,x.id$q$ using t,f,z,l,zone;
  end if;
 end if;
end $function$;
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
 select coalesce(jsonb_agg(r order by case when not desc_sort then r->sort_key end asc nulls last,case when desc_sort then r->sort_key end desc nulls last,r->>'product_name',r->>'sku',r->>'location_name',r->>'id',r->>'variant_id',r->>'location_id',ord),'[]'::jsonb)
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
 'stock_basis','location_stock_balances / location_stock_movements. Legacy stock_movements is excluded.',
 'valuation_basis','Current location average cost; stock statements show posting-date quantities, not historical costs.',
 'quantity_basis','Configured base units; quantities in different units are never combined.',
 'tracking_change_history_available',to_regclass('private.tracking_conversions_v633') is not null));
end $function$;
CREATE OR REPLACE FUNCTION public.inventory_reports_catalog_v635(p_tenant_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$
 select private.inventory_report_gateway_v635(p_tenant_id,'catalog','{}'::jsonb)
$function$;
CREATE OR REPLACE FUNCTION public.inventory_reports_run_v635(p_tenant_id uuid, p_request jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$
 select private.inventory_report_gateway_v635(p_tenant_id,'run',p_request)
$function$;
revoke all on function private.inventory_report_definitions_v635(),private.inventory_report_assert_v635(uuid,uuid,text),private.inventory_report_stock_v635(uuid,uuid,date,date,integer),private.inventory_report_rows_v635(uuid,text,date,date,uuid,integer,integer),private.inventory_report_gateway_v635(uuid,text,jsonb) from public,anon,authenticated;
grant usage on schema private to authenticated;
grant execute on function private.inventory_report_gateway_v635(uuid,text,jsonb) to authenticated;
revoke all on function public.inventory_reports_catalog_v635(uuid),public.inventory_reports_run_v635(uuid,jsonb) from public,anon;
grant execute on function public.inventory_reports_catalog_v635(uuid),public.inventory_reports_run_v635(uuid,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
