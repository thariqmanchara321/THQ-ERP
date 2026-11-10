-- THQ ERP v6.0 GST RPC-only table ACL hardening (TEST)
-- Direct client access is forbidden; service_role retains worker access.

REVOKE ALL ON TABLE public.gst_provider_jobs_v600 FROM anon, authenticated;
REVOKE ALL ON TABLE public.gst_turnover_profiles_v600 FROM anon, authenticated;
REVOKE ALL ON TABLE public.gst_return_periods_v600 FROM anon, authenticated;
REVOKE ALL ON TABLE public.gst_portal_import_batches_v600 FROM anon, authenticated;
REVOKE ALL ON TABLE public.gst_portal_itc_documents_v600 FROM anon, authenticated;

GRANT ALL ON TABLE public.gst_provider_jobs_v600 TO service_role;
GRANT ALL ON TABLE public.gst_turnover_profiles_v600 TO service_role;
GRANT ALL ON TABLE public.gst_return_periods_v600 TO service_role;
GRANT ALL ON TABLE public.gst_portal_import_batches_v600 TO service_role;
GRANT ALL ON TABLE public.gst_portal_itc_documents_v600 TO service_role;