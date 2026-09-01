-- THQ ERP v4.9.5 release contract and verification.
begin;

-- v4.9.5 remains additive/backward-compatible for already-installed 4.9.0+ desktop clients.
-- New v4.9.5 applications require migration 201 locally.
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
  select jsonb_build_object(
    'product','THQ ERP',
    'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
    'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
    'minimum_app_version','4.9.0',
    'release','Invoices, Workflow, Output & Search',
    'api_version','v1',
    'backward_compatible',true
  )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v495_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  miss text[]:='{}';
  p text;
  req text[]:=array[
    'invoice_template_capabilities_v495','sales_get_detail_v495',
    'business_tasks_list_v495','business_task_save_v495','business_task_from_notification_v495',
    'notifications_mark_all_read_v495','notifications_list_v4',
    'selector_search_v495','document_output_log_v495'
  ];
begin
  foreach p in array req loop
    if not exists(
      select 1 from pg_proc x join pg_namespace n on n.oid=x.pronamespace
      where n.nspname='public' and x.proname=p
    ) then miss:=array_append(miss,p); end if;
  end loop;

  if not exists(select 1 from storage.buckets where id='thq-assets') then miss:=array_append(miss,'storage.thq-assets');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='business_tasks' and column_name='reminder_at') then miss:=array_append(miss,'business_tasks.reminder_at');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='business_tasks' and column_name='source_notification_id') then miss:=array_append(miss,'business_tasks.source_notification_id');end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='business_tasks' and column_name='metadata') then miss:=array_append(miss,'business_tasks.metadata');end if;
  if not exists(select 1 from public.thq_schema_releases where migration_no=200 and schema_version='4.9.5') then miss:=array_append(miss,'migration.200');end if;

  return jsonb_build_object(
    'ready',cardinality(miss)=0,
    'missing',to_jsonb(miss),
    'schema_version','4.9.5',
    'migration_no',201,
    'minimum_compatible_app','4.9.0',
    'invoice_branding',true,
    'selectable_invoice_columns',true,
    'printer_pdf_output',true,
    'accounting_report_export',true,
    'task_notification_sync',true,
    'searchable_selectors',true
  );
end $$;
grant execute on function public.thq_v495_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(201,'4.9.5','Invoices, Workflow, Output & Search','Invoice branding and selectable columns, printer/PDF/export infrastructure, synchronized task notifications and starts-with searchable selectors.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.9.5 migration 201 release applied' as status;
