-- THQ ERP v5.2 GST & Compliance
-- Migration 230: reconcile duplicate development-only GST helper overloads.
-- Keeps the stricter canonical 225/226 contracts; removes redundant alternate helpers.
begin;
drop function if exists private.gst_snapshot_create_v520(uuid,text,uuid,text,uuid,jsonb,uuid[],text);
drop function if exists private.gst_sha256_jsonb_v520(jsonb);
drop function if exists private.gst_legacy_mark_source_v520(uuid,text,uuid);
drop function if exists private.gst_legacy_backfill_v520(uuid);
drop function if exists public.gst_document_evidence_v520(uuid,text,uuid);
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(230,'5.2.0-foundation','GST Migration Contract Cleanup','Removes redundant development-only GST writer/legacy helper overloads and retains the stricter canonical source-bound authoritative snapshot contract and legacy evidence/tamper contract from migrations 225-226.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;