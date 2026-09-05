revoke execute on function public.gst_document_quote_v520(uuid,text,uuid,uuid,date,text,text,jsonb,numeric,numeric) from public, anon;
revoke execute on function public.gst_purchase_quote_v520(uuid,uuid,uuid,date,text,text,jsonb,numeric,numeric) from public, anon;
revoke execute on function public.gst_registration_config_v520(uuid,uuid,date) from public, anon;

grant execute on function public.gst_document_quote_v520(uuid,text,uuid,uuid,date,text,text,jsonb,numeric,numeric) to authenticated, service_role;
grant execute on function public.gst_purchase_quote_v520(uuid,uuid,uuid,date,text,text,jsonb,numeric,numeric) to authenticated, service_role;
grant execute on function public.gst_registration_config_v520(uuid,uuid,date) to authenticated, service_role;