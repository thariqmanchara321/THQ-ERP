-- THQ ERP v5.2 GST & Compliance — master/rule corrections from audit.
-- Provider-neutral. No transaction or journal changes.
begin;

alter table public.gst_state_master_v520
  add column if not exists uses_utgst boolean not null default false;

update public.gst_state_master_v520
set uses_utgst = code in ('04','26','31','35','38'), updated_at=now();

update public.gst_policy_rules_v520
set active=false,
    source_note=coalesce(source_note,'')||' • Superseded by corrected effective date 01-Jan-2025',
    updated_at=now()
where rule_key='ewaybill_document_age_limit' and effective_from='2025-03-17';

insert into public.gst_policy_rules_v520(rule_key,effective_from,rule_value,source_note,active)
values
 ('ewaybill_document_age_limit','2025-01-01','{"days":180}'::jsonb,'E-Way Bill validation: document date cannot be older than 180 days at generation, effective 01-Jan-2025',true),
 ('ewaybill_extension_limit','2025-01-01','{"days":360}'::jsonb,'E-Way Bill validation: extension cannot exceed 360 days from generation, effective 01-Jan-2025',true)
on conflict(rule_key,effective_from) do update
set rule_value=excluded.rule_value,source_note=excluded.source_note,active=true,updated_at=now();

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(218,'5.2.0-foundation','GST Master & Rule Corrections','Corrects local SGST/UTGST jurisdiction metadata and E-Way Bill 180/360-day policy effective dates after foundation audit.')
on conflict(migration_no) do update
set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;