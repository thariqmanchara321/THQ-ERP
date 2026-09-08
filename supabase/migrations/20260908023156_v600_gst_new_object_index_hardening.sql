-- THQ ERP v6.0 GST new-object index hardening (TEST)
-- Remove duplicate provider snapshot index and add covering FK indexes only for the new GST layer.

DROP INDEX IF EXISTS public.idx_gst_provider_jobs_v600_snapshot;

CREATE INDEX IF NOT EXISTS idx_gst_provider_jobs_v600_registration_fk
  ON public.gst_provider_jobs_v600 (registration_id);
CREATE INDEX IF NOT EXISTS idx_gst_provider_jobs_v600_related_job_fk
  ON public.gst_provider_jobs_v600 (related_job_id);
CREATE INDEX IF NOT EXISTS idx_gst_provider_jobs_v600_return_period_fk
  ON public.gst_provider_jobs_v600 (return_period_id);
CREATE INDEX IF NOT EXISTS idx_gst_provider_jobs_v600_snapshot_fk
  ON public.gst_provider_jobs_v600 (snapshot_id);

CREATE INDEX IF NOT EXISTS idx_gst_return_periods_v600_registration_fk
  ON public.gst_return_periods_v600 (registration_id);
CREATE INDEX IF NOT EXISTS idx_gst_portal_batches_v600_registration_fk
  ON public.gst_portal_import_batches_v600 (registration_id);
CREATE INDEX IF NOT EXISTS idx_gst_portal_itc_docs_v600_registration_fk
  ON public.gst_portal_itc_documents_v600 (registration_id);