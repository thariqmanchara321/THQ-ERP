-- Run through a privileged SQL connection. Uses existing authorized members.
-- Only temporary verification results are written; no ERP records are changed.
begin;
create temporary table inventory_report_checks(name text, detail jsonb) on commit drop;
do $check$
declare
 t uuid; actor uuid; restricted_actor uuid; loc uuid; d jsonb; doc jsonb;
 stock jsonb; statement jsonb; page jsonb; filtered jsonb; unit text;
 rejected boolean; expected jsonb; costs text[] := array['average_cost','stock_value','available_value','held_value','purchase_cost_base','selling_price_base'];
begin
 select tm.tenant_id,tm.user_id into t,actor
 from public.tenant_memberships tm
 join public.user_roles ur on ur.tenant_id=tm.tenant_id and ur.membership_id=tm.id
 join public.roles r on r.id=ur.role_id
 where tm.status='active' and r.key='owner'
 and exists(select 1 from public.tenant_modules m where m.tenant_id=tm.tenant_id and m.module_key='inventory' and m.enabled)
 and exists(select 1 from public.tenant_modules m where m.tenant_id=tm.tenant_id and m.module_key='reports' and m.enabled)
 order by (select count(*) from public.location_stock_movements m where m.tenant_id=tm.tenant_id) desc limit 1;
 if t is null then raise exception 'No active owner with Inventory and Reports enabled'; end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 if jsonb_array_length(public.inventory_reports_catalog_v635(t))<>15 then raise exception 'Expected 15 reports';end if;
 for d in select value from jsonb_array_elements(public.inventory_reports_catalog_v635(t)) loop
  doc:=public.inventory_reports_run_v635(t,jsonb_build_object('key',d->>'key','from','2000-01-01','to','2100-01-01','limit',0));
  if not (doc->>'complete')::boolean or jsonb_array_length(doc->'rows')<>(doc->>'total_rows')::integer then raise exception 'Incomplete report %',d->>'key';end if;
  insert into inventory_report_checks values('complete_'||(d->>'key'),jsonb_build_object('rows',doc->'total_rows','units',jsonb_array_length(doc->'unit_totals')));
 end loop;
 stock:=public.inventory_reports_run_v635(t,'{"key":"stock_snapshot","limit":0}');
 statement:=public.inventory_reports_run_v635(t,jsonb_build_object('key','stock_statement','from','2026-01-01','to',current_date,'limit',0));
 if exists(select 1 from jsonb_array_elements(stock->'rows') x where abs((x->>'quantity')::numeric-(x->>'available')::numeric-(x->>'reserved')::numeric-(x->>'damaged')::numeric-(x->>'quarantine')::numeric)>0.0001) then raise exception 'Available quantity arithmetic failed';end if;
 if exists(select 1 from jsonb_array_elements(stock->'rows') x where abs((x->>'stock_value')::numeric-round((x->>'quantity')::numeric*(x->>'average_cost')::numeric,2))>0.001) then raise exception 'Valuation arithmetic failed';end if;
 if exists(select 1 from jsonb_array_elements(statement->'rows') x where abs((x->>'opening_quantity')::numeric+(x->>'receipts')::numeric-(x->>'issues')::numeric-(x->>'closing_quantity')::numeric)>0.0001) then raise exception 'Opening + receipts - issues = closing failed';end if;
 if exists(select 1 from jsonb_array_elements(stock->'unit_totals') u where abs((u->>'quantity')::numeric-(select sum((x->>'quantity')::numeric) from jsonb_array_elements(stock->'rows') x where x->>'unit_code'=u->>'unit_code'))>0.0001) then raise exception 'Unit totals failed';end if;
 insert into inventory_report_checks values('stock_arithmetic_valuation_and_separate_units','true');
 page:=public.inventory_reports_run_v635(t,'{"key":"stock_snapshot","offset":25,"limit":25}');
 select coalesce(jsonb_agg(x order by ord),'[]') into expected from jsonb_array_elements(stock->'rows') with ordinality a(x,ord) where ord between 26 and 50;
 if page->'rows'<>expected or page->'summary'<>stock->'summary' or page->'unit_totals'<>stock->'unit_totals' then raise exception 'Pagination changes rows or all-matching totals';end if;
 insert into inventory_report_checks values('pagination_matches_complete_export','true');
 unit:=stock->'rows'->0->>'unit_code';
 if unit is not null then
  filtered:=public.inventory_reports_run_v635(t,jsonb_build_object('key','stock_snapshot','limit',0,'filters',jsonb_build_object('unit_code',unit)));
  if exists(select 1 from jsonb_array_elements(filtered->'rows') x where x->>'unit_code'<>unit) or (filtered->>'total_rows')::integer<>(select count(*) from jsonb_array_elements(stock->'rows') x where x->>'unit_code'=unit) then raise exception 'Unit filter mismatch';end if;
 end if;
 insert into inventory_report_checks values('server_unit_filter','true');
 select id into loc from public.business_locations where tenant_id=t order by location_code limit 1;
 if loc is not null then
  doc:=public.inventory_reports_run_v635(t,jsonb_build_object('key','stock_snapshot','location_id',loc,'limit',0));
  if exists(select 1 from jsonb_array_elements(doc->'rows') x where (x->>'location_id')::uuid<>loc) then raise exception 'Location filter leaks rows';end if;
 end if;
 insert into inventory_report_checks values('store_scope','true');
 doc:=public.inventory_reports_run_v635(t,'{"key":"movements","from":"2000-01-01","to":"2100-01-01","limit":0}');
 if exists(select 1 from (select (x->>'created_at')::timestamptz ts,lead((x->>'created_at')::timestamptz) over(order by ord) next_ts from jsonb_array_elements(doc->'rows') with ordinality a(x,ord)) a where ts<next_ts) then raise exception 'Default movement order is not newest first';end if;
 if exists(select 1 from jsonb_array_elements(doc->'rows') x where abs((x->>'balance_after')::numeric-(x->>'balance_before')::numeric-(x->>'quantity')::numeric)>0.0001) then raise exception 'Movement before/after mismatch';end if;
 insert into inventory_report_checks values('movement_order_and_balances','true');
 rejected:=false;
 begin perform public.inventory_reports_run_v635(t,'{"from":"2026-10-10","to":"2026-10-01"}');exception when invalid_parameter_value then rejected:=true;end;
 if not rejected then raise exception 'Reversed dates accepted';end if;
 rejected:=false;
 begin perform public.inventory_reports_run_v635(t,'{"filters":{"unexpected":"x"}}');exception when invalid_parameter_value then rejected:=true;end;
 if not rejected then raise exception 'Unknown filter accepted';end if;
 rejected:=false;
 begin perform public.inventory_reports_run_v635(t,'{"sort_key":"untrusted"}');exception when invalid_parameter_value then rejected:=true;end;
 if not rejected then raise exception 'Unknown sort accepted';end if;
 insert into inventory_report_checks values('invalid_dates_filters_sort_denied','true');
 rejected:=false;
 begin perform public.inventory_reports_run_v635(t,jsonb_build_object('location_id',gen_random_uuid()));exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'Unknown store accepted';end if;
 perform set_config('request.jwt.claim.sub','',true);rejected:=false;
 begin perform public.inventory_reports_catalog_v635(t);exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'Unauthenticated access accepted';end if;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);rejected:=false;
 begin perform public.inventory_reports_catalog_v635(t);exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'Non-member access accepted';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);rejected:=false;
 begin perform public.inventory_reports_catalog_v635(gen_random_uuid());exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'Cross-tenant access accepted';end if;
 insert into inventory_report_checks values('anonymous_nonmember_cross_tenant_and_store_denied','true');
 -- Select an existing non-cost member; never change permissions for a test.
 select tm.user_id into restricted_actor from public.tenant_memberships tm
 join public.user_roles ur on ur.membership_id=tm.id and ur.tenant_id=tm.tenant_id
 join public.roles r on r.id=ur.role_id
 left join public.role_permissions rp on rp.role_id=r.id
 where tm.tenant_id=t and tm.status='active'
 group by tm.user_id having not bool_or(r.key='owner')
 and bool_or(rp.permission_key='inventory.view') and bool_or(rp.permission_key='reports.view')
 and not bool_or(coalesce(rp.permission_key='inventory.view_cost',false)) limit 1;
 if restricted_actor is not null then
  perform set_config('request.jwt.claim.sub',restricted_actor::text,true);
  if exists(select 1 from jsonb_array_elements(public.inventory_reports_catalog_v635(t)) x where x->>'key'='valuation') then raise exception 'Valuation exposed to non-cost member';end if;
  for d in select value from jsonb_array_elements(public.inventory_reports_catalog_v635(t)) loop
   doc:=public.inventory_reports_run_v635(t,jsonb_build_object('key',d->>'key','from','2000-01-01','to','2100-01-01','limit',0));
   if (doc->'context'->>'cost_visible')::boolean or exists(select 1 from jsonb_array_elements(doc->'rows') x where x ?| costs) or exists(select 1 from jsonb_array_elements(doc->'summary') x where x->>'type'='money') then raise exception 'Cost exposure in %',d->>'key';end if;
   if exists(select 1 from jsonb_array_elements(doc->'rows') x where x ? 'location_id' and not private.reports_scope_v631(t,(x->>'location_id')::uuid,null,'view')) then raise exception 'Unauthorized store in %',d->>'key';end if;
  end loop;
  rejected:=false;
  begin perform public.inventory_reports_run_v635(t,'{"key":"valuation"}');exception when insufficient_privilege then rejected:=true;end;
  if not rejected then raise exception 'Direct valuation call accepted without cost permission';end if;
  insert into inventory_report_checks values('cost_redaction_catalog_direct_rpc_and_store_scope','true');
 else
  insert into inventory_report_checks values('cost_redaction_fixture_missing','"No existing non-cost member; no permissions modified"');
 end if;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname like 'inventory_report%v635' and n.nspname in('public','private') and has_function_privilege('anon',p.oid,'execute')) then raise exception 'Anonymous execute grant';end if;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname in('inventory_reports_catalog_v635','inventory_reports_run_v635') and n.nspname='public' and p.prosecdef) then raise exception 'Public wrapper must be invoker';end if;
 if has_function_privilege('authenticated','private.inventory_report_rows_v635(uuid,text,date,date,uuid,integer,integer)','execute') or has_function_privilege('authenticated','private.inventory_report_stock_v635(uuid,uuid,date,date,integer)','execute') then raise exception 'Direct helper grant';end if;
 insert into inventory_report_checks values('rpc_and_helper_grants','true');
end $check$;
select name,detail from inventory_report_checks order by name;
rollback;
