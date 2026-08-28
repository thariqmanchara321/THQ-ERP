-- FLEXI ERP V3.2 final vertical-module verification.
do $$
begin
  if to_regprocedure('public.production_recipes_list_v32(uuid)') is null then raise exception 'Missing production_recipes_list_v32';end if;
  if to_regprocedure('public.production_runs_list_v32(uuid,uuid,integer)') is null then raise exception 'Missing production_runs_list_v32';end if;
  if to_regprocedure('public.production_run_execute_v32(uuid,uuid,uuid,numeric,text)') is null then raise exception 'Missing production_run_execute_v32';end if;
  if to_regprocedure('public.service_vehicles_list_v32(uuid,uuid)') is null then raise exception 'Missing service_vehicles_list_v32';end if;
  if to_regprocedure('public.service_vehicle_save_v32(uuid,uuid,uuid,text,text,text,numeric,text,text,text,boolean)') is null then raise exception 'Missing service_vehicle_save_v32';end if;
  if to_regprocedure('public.service_jobs_list_v32(uuid,uuid,integer)') is null then raise exception 'Missing service_jobs_list_v32';end if;
  if to_regprocedure('public.service_job_create_v32(uuid,uuid,uuid,uuid,date,text,text,numeric,numeric,text,numeric,text)') is null then raise exception 'Missing service_job_create_v32';end if;
  if to_regprocedure('public.service_job_link_sale_by_reference_v32(uuid,uuid,text)') is null then raise exception 'Missing service_job_link_sale_by_reference_v32';end if;
  if to_regprocedure('public.restaurant_tables_list_v32(uuid,uuid,uuid)') is null then raise exception 'Missing restaurant_tables_list_v32';end if;
  if to_regprocedure('public.restaurant_table_save_v32(uuid,uuid,uuid,uuid,text,text,integer,text,boolean)') is null then raise exception 'Missing restaurant_table_save_v32';end if;
  if to_regprocedure('public.restaurant_orders_list_v32(uuid,uuid,uuid,boolean,integer)') is null then raise exception 'Missing restaurant_orders_list_v32';end if;
  if to_regprocedure('public.restaurant_order_detail_v32(uuid,uuid,uuid)') is null then raise exception 'Missing restaurant_order_detail_v32';end if;
  if to_regprocedure('public.restaurant_order_create_v32(uuid,uuid,uuid,text,uuid,uuid,integer,text,text,jsonb)') is null then raise exception 'Missing restaurant_order_create_v32';end if;
  if to_regprocedure('public.restaurant_kot_send_v32(uuid,uuid,uuid,text)') is null then raise exception 'Missing restaurant_kot_send_v32';end if;
  if to_regprocedure('public.restaurant_order_set_status_v32(uuid,uuid,uuid,text)') is null then raise exception 'Missing restaurant_order_set_status_v32';end if;
  if to_regprocedure('public.restaurant_order_mark_billed_by_reference_v32(uuid,uuid,uuid,text)') is null then raise exception 'Missing restaurant_order_mark_billed_by_reference_v32';end if;
end $$;
select 'Flexi ERP V3.2 complete backend verification passed' as status;
