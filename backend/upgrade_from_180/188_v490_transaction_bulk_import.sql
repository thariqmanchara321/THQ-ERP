-- THQ ERP v4.9.0 Build 20 — auditable bulk Sales/Purchase import.
begin;

create table if not exists public.transaction_import_runs_v490(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  import_type text not null check(import_type in('sales','purchases')),
  location_id uuid not null references public.business_locations(id) on delete restrict,
  source_name text,
  source_key text not null,
  row_count integer not null default 0,
  document_count integer not null default 0,
  success_count integer not null default 0,
  failed_count integer not null default 0,
  skipped_count integer not null default 0,
  status text not null default 'processing' check(status in('processing','completed','completed_with_errors','failed')),
  result jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique(tenant_id,import_type,source_key)
);
create index if not exists idx_transaction_import_runs_v490 on public.transaction_import_runs_v490(tenant_id,created_at desc);
alter table public.transaction_import_runs_v490 enable row level security;
revoke all on public.transaction_import_runs_v490 from anon,authenticated;

create table if not exists public.transaction_import_documents_v490(
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.transaction_import_runs_v490(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  import_type text not null check(import_type in('sales','purchases')),
  external_key text not null,
  entity_id uuid,
  entity_number text,
  status text not null default 'processing' check(status in('processing','success','failed')),
  error_message text,
  response jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,import_type,external_key)
);
create index if not exists idx_transaction_import_documents_v490_run on public.transaction_import_documents_v490(run_id,status);
alter table public.transaction_import_documents_v490 enable row level security;
revoke all on public.transaction_import_documents_v490 from anon,authenticated;

create or replace function public.transaction_bulk_import_v490(
  p_tenant_id uuid,
  p_import_type text,
  p_location_id uuid,
  p_device_id uuid,
  p_source_name text,
  p_source_key text,
  p_documents jsonb
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v_type text:=lower(trim(coalesce(p_import_type,'')));
  v_run uuid;v_existing public.transaction_import_runs_v490%rowtype;
  v_success integer:=0;v_failed integer:=0;v_skipped integer:=0;v_rows integer:=0;
  v_results jsonb:='[]'::jsonb;d jsonb;v_external text;v_doc public.transaction_import_documents_v490%rowtype;
  v_result jsonb;v_entity uuid;v_number text;v_request text;v_message text;
  v_party uuid;v_items jsonb;v_date date;v_due date;v_amount numeric;v_add numeric;v_round numeric;
begin
  if v_type not in('sales','purchases') then raise exception 'Import type must be sales or purchases';end if;
  if nullif(trim(coalesce(p_source_key,'')),'') is null then raise exception 'Import source key is required';end if;
  if p_documents is null or jsonb_typeof(p_documents)<>'array' or jsonb_array_length(p_documents)=0 then raise exception 'At least one document is required';end if;
  if jsonb_array_length(p_documents)>1000 then raise exception 'A single import is limited to 1000 documents';end if;
  if p_location_id is null then raise exception 'A concrete store/location is required';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'bulk_import.use') then raise exception 'Bulk Import permission required';end if;
  if v_type='purchases' then perform private.purchasing_v484_access(p_tenant_id,p_location_id,true);
  else
    if not private.erp_document_scope_allowed(p_tenant_id,p_location_id,p_location_id,'operate') then raise exception 'Location access denied';end if;
    if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'sales.manage') then raise exception 'Sales management permission required';end if;
  end if;

  select * into v_existing from public.transaction_import_runs_v490 where tenant_id=p_tenant_id and import_type=v_type and source_key=trim(p_source_key) for update;
  if found and v_existing.status in('completed','completed_with_errors') then
    return coalesce(v_existing.result,'{}'::jsonb)||jsonb_build_object('idempotent_replay',true,'run_id',v_existing.id);
  end if;
  if found then
    v_run:=v_existing.id;
    update public.transaction_import_runs_v490 set status='processing',source_name=nullif(trim(coalesce(p_source_name,'')),''),completed_at=null where id=v_run;
  else
    insert into public.transaction_import_runs_v490(tenant_id,import_type,location_id,source_name,source_key,document_count,created_by)
    values(p_tenant_id,v_type,p_location_id,nullif(trim(coalesce(p_source_name,'')),''),trim(p_source_key),jsonb_array_length(p_documents),auth.uid()) returning id into v_run;
  end if;

  for d in select value from jsonb_array_elements(p_documents) loop
    v_rows:=v_rows+greatest(coalesce(nullif(d->>'source_row_count','')::integer,1),1);
    v_external:=nullif(trim(coalesce(d->>'external_key',d->>'document_ref','')),'');
    if v_external is null then
      v_failed:=v_failed+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('status','failed','error','Each document requires external_key/document_ref'));
      continue;
    end if;

    select * into v_doc from public.transaction_import_documents_v490 where tenant_id=p_tenant_id and import_type=v_type and external_key=v_external for update;
    if found and v_doc.status='success' then
      v_skipped:=v_skipped+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('external_key',v_external,'status','success','entity_id',v_doc.entity_id,'entity_number',v_doc.entity_number,'idempotent_replay',true));
      continue;
    end if;
    if found then
      update public.transaction_import_documents_v490 set run_id=v_run,status='processing',error_message=null,updated_at=now() where id=v_doc.id;
    else
      insert into public.transaction_import_documents_v490(run_id,tenant_id,import_type,external_key,status)
      values(v_run,p_tenant_id,v_type,v_external,'processing') returning * into v_doc;
    end if;

    begin
      v_items:=coalesce(d->'items','[]'::jsonb);
      if jsonb_typeof(v_items)<>'array' or jsonb_array_length(v_items)=0 then raise exception 'Document has no items';end if;
      v_date:=coalesce(nullif(d->>'document_date','')::date,current_date);
      v_due:=nullif(d->>'due_date','')::date;
      v_add:=greatest(coalesce(nullif(d->>'additional_charges','')::numeric,0),0);
      v_round:=coalesce(nullif(d->>'round_off','')::numeric,0);
      v_amount:=greatest(coalesce(nullif(d->>'initial_payment','')::numeric,0),0);
      v_request:='bulk-'||v_type||'-'||md5(p_tenant_id::text||':'||v_external);

      if v_type='sales' then
        v_party:=nullif(d->>'customer_id','')::uuid;
        if v_party is null then raise exception 'Customer is required';end if;
        v_result:=public.sales_create_v489(
          p_tenant_id,v_party,v_date,v_due,v_items,v_add,v_round,v_amount,
          coalesce(nullif(lower(trim(d->>'payment_method')),''),'cash'),coalesce(d->>'payment_reference',''),coalesce(d->>'notes',''),
          p_location_id,p_device_id,v_request
        );
        v_entity:=nullif(v_result->>'sale_id','')::uuid;v_number:=coalesce(v_result->>'invoice_number',v_result->>'sale_number');
      else
        v_party:=nullif(d->>'supplier_id','')::uuid;
        if v_party is null then raise exception 'Supplier is required';end if;
        if nullif(trim(coalesce(d->>'supplier_invoice_number','')),'') is null then raise exception 'Supplier invoice number is required';end if;
        v_result:=public.purchases_create_v489(
          p_tenant_id,v_party,trim(d->>'supplier_invoice_number'),v_date,v_due,v_items,v_add,v_round,v_amount,
          coalesce(nullif(lower(trim(d->>'payment_method')),''),'bank'),coalesce(d->>'notes',''),p_location_id,p_device_id,v_request
        );
        v_entity:=nullif(v_result->>'purchase_id','')::uuid;v_number:=v_result->>'purchase_number';
      end if;
      if v_entity is null then raise exception 'Transaction creation returned no document ID';end if;
      update public.transaction_import_documents_v490 set status='success',entity_id=v_entity,entity_number=v_number,response=coalesce(v_result,'{}'::jsonb),error_message=null,updated_at=now() where id=v_doc.id;
      v_success:=v_success+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('external_key',v_external,'status','success','entity_id',v_entity,'entity_number',v_number,'response',v_result));
    exception when others then
      v_message:=sqlerrm;
      update public.transaction_import_documents_v490 set status='failed',error_message=v_message,response='{}'::jsonb,updated_at=now() where id=v_doc.id;
      v_failed:=v_failed+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('external_key',v_external,'status','failed','error',v_message));
    end;
  end loop;

  v_result:=jsonb_build_object(
    'success',v_failed=0,'run_id',v_run,'import_type',v_type,'source_key',trim(p_source_key),
    'success_count',v_success,'failed_count',v_failed,'skipped_count',v_skipped,'document_count',jsonb_array_length(p_documents),'row_count',v_rows,
    'documents',v_results
  );
  update public.transaction_import_runs_v490
  set row_count=v_rows,document_count=jsonb_array_length(p_documents),success_count=v_success,failed_count=v_failed,skipped_count=v_skipped,
      status=case when v_failed=0 then 'completed' else 'completed_with_errors' end,result=v_result,completed_at=now()
  where id=v_run;
  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','bulk_'||v_type,v_run::text,'import');
  return v_result;
exception when others then
  if v_run is not null then
    update public.transaction_import_runs_v490 set status='failed',result=jsonb_build_object('error',sqlerrm),completed_at=now() where id=v_run;
  end if;
  raise;
end $$;
grant execute on function public.transaction_bulk_import_v490(uuid,text,uuid,uuid,text,text,jsonb) to authenticated;

create or replace function public.transaction_bulk_import_history_v490(p_tenant_id uuid,p_import_type text default null,p_limit integer default 100)
returns table(run_id uuid,import_type text,location_id uuid,location_name text,source_name text,source_key text,row_count integer,document_count integer,success_count integer,failed_count integer,skipped_count integer,status text,created_at timestamptz,completed_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'bulk_import.use') then raise exception 'Bulk Import permission required';end if;
  return query
  select r.id,r.import_type,r.location_id,l.name::text,r.source_name,r.source_key,r.row_count,r.document_count,r.success_count,r.failed_count,r.skipped_count,r.status,r.created_at,r.completed_at
  from public.transaction_import_runs_v490 r join public.business_locations l on l.id=r.location_id
  where r.tenant_id=p_tenant_id and (p_import_type is null or trim(p_import_type)='' or r.import_type=lower(trim(p_import_type)))
    and private.erp_document_scope_allowed(p_tenant_id,r.location_id,null,'view')
  order by r.created_at desc limit greatest(1,least(coalesce(p_limit,100),1000));
end $$;
grant execute on function public.transaction_bulk_import_history_v490(uuid,text,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(188,'4.9.0','Transaction Bulk Import','Auditable, idempotent Excel bulk import engine for Sales and Direct Purchases using the normal stock, tax, payment and accounting transaction functions.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 20 migration 188 transaction bulk import applied' as status;
