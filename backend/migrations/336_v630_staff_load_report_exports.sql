-- Keep complete staff/load evidence in financial exports, subject to module permissions.
create or replace function public.reports_export_dataset_v630(p_tenant_id uuid,p_from date,p_to date,p_location_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare result jsonb;loads jsonb:='[]';staff jsonb:='{}';
begin
 result:=public.reports_export_dataset_v44(p_tenant_id,p_from,p_to,p_location_id);
 if exists(select 1 from public.tenant_modules where tenant_id=p_tenant_id and module_key='aggregate_yard' and enabled) and (private.erp_user_is_owner(p_tenant_id,auth.uid()) or private.erp_has_permission(p_tenant_id,'aggregate_yard.view')) then
  loads:=public.material_load_workspace_v630(p_tenant_id,'report',jsonb_build_object('from',p_from,'to',p_to),p_location_id)->'loads';
 end if;
 if exists(select 1 from public.tenant_modules where tenant_id=p_tenant_id and module_key='staff' and enabled) and private.erp_has_permission(p_tenant_id,'staff.view') then
  staff:=public.staff_workspace_v630(p_tenant_id,'report',jsonb_build_object('from',p_from,'to',p_to),p_location_id);
 end if;
 return result||jsonb_build_object('summary',public.reports_get_summary_v630(p_tenant_id,p_from,p_to,p_location_id),
  'material_loads',loads,
  'load_costs',coalesce((select jsonb_agg(c.value||jsonb_build_object('load_number',l.value->>'load_number','load_date',l.value->>'load_date','vehicle_registration',l.value->>'vehicle_registration','driver_name',l.value->>'driver_name')) from jsonb_array_elements(loads) l(value) cross join lateral jsonb_array_elements(l.value->'costs') c(value)),'[]'::jsonb),
  'staff',coalesce(staff->'staff','[]'::jsonb),'staff_attendance',coalesce(staff->'attendance','[]'::jsonb),'staff_earnings',coalesce(staff->'earnings','[]'::jsonb),'staff_payments',coalesce(staff->'payments','[]'::jsonb));
end $$;
revoke all on function public.reports_export_dataset_v630(uuid,date,date,uuid) from public,anon;
grant execute on function public.reports_export_dataset_v630(uuid,date,date,uuid) to authenticated;
