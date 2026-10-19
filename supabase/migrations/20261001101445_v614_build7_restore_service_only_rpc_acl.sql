
begin;

revoke execute on function public.gst_document_quote_registered_v520(uuid,text,uuid,uuid,date,text,text,jsonb,numeric,numeric) from authenticated;
revoke execute on function public.gst_portal_itc_import_service_v600(uuid,uuid,date,text,uuid,jsonb) from authenticated;
revoke execute on function public.gst_provider_connection_mark_v600(uuid,uuid,text,text,text,jsonb,text) from authenticated;
revoke execute on function public.gst_provider_job_claim_v600() from authenticated;
revoke execute on function public.gst_provider_job_complete_v600(uuid,boolean,jsonb,text,text,boolean) from authenticated;
revoke execute on function public.gst_transaction_cutover_contract_base_v520(uuid,text,uuid) from authenticated;
revoke execute on function public.gst_ui_contract_base_v520(uuid) from authenticated;
revoke execute on function public.restaurant_order_split_v610(uuid,uuid,uuid,uuid,jsonb,integer,text) from authenticated;
revoke execute on function public.transaction_explain_core_v600(uuid,text,uuid,integer) from authenticated;
revoke execute on function public.platform_business_delete_v471(uuid) from authenticated;
revoke execute on function public.system_claim_activation_v47(text,text,text,text,text,text,text) from authenticated;

-- All remain available to service_role where applicable.
grant execute on function public.gst_document_quote_registered_v520(uuid,text,uuid,uuid,date,text,text,jsonb,numeric,numeric) to service_role;
grant execute on function public.gst_portal_itc_import_service_v600(uuid,uuid,date,text,uuid,jsonb) to service_role;
grant execute on function public.gst_provider_connection_mark_v600(uuid,uuid,text,text,text,jsonb,text) to service_role;
grant execute on function public.gst_provider_job_claim_v600() to service_role;
grant execute on function public.gst_provider_job_complete_v600(uuid,boolean,jsonb,text,text,boolean) to service_role;
grant execute on function public.gst_transaction_cutover_contract_base_v520(uuid,text,uuid) to service_role;
grant execute on function public.gst_ui_contract_base_v520(uuid) to service_role;
grant execute on function public.restaurant_order_split_v610(uuid,uuid,uuid,uuid,jsonb,integer,text) to service_role;
grant execute on function public.transaction_explain_core_v600(uuid,text,uuid,integer) to service_role;
grant execute on function public.platform_business_delete_v471(uuid) to service_role;
grant execute on function public.system_claim_activation_v47(text,text,text,text,text,text,text) to service_role;

commit;
;
