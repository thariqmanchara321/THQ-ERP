-- THQ ERP v6.0 GST private helper hardening (TEST)
-- Internal helpers must never be directly invokable by client roles.

REVOKE ALL ON FUNCTION private.gst_aato_context_v600(uuid,date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.gst_append_only_guard_v600() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.gst_period_lock_guard_v600() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.gst_portal_itc_import_core_v600(uuid,uuid,date,text,uuid,jsonb,uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.gst_provider_connection_assert_v600(uuid,uuid,text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.gst_provider_enqueue_return_v600(uuid,uuid,uuid,text,uuid,text,jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.gst_provider_enqueue_v600(uuid,uuid,uuid,uuid,text,uuid,text,jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.gst_provider_job_guard_v600() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.gst_service_role_assert_v600() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.gst_snapshot_legal_context_before_insert_v600() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.gst_snapshot_line_unit_before_insert_v600() FROM PUBLIC, anon, authenticated, service_role;