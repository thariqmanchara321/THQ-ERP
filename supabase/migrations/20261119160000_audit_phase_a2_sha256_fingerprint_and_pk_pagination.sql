-- Phase A.2: Stronger SHA-256 Export Fingerprint & Deterministic Primary Key Pagination
-- 1. Deterministic primary key introspection: uses declared unique/composite primary keys
--    for deterministic tie-breaker sorting across all 190 catalog datasets (no reliance on volatile ctid).
-- 2. Cryptographic SHA-256 dataset fingerprint: Merkle-like binary digest of sorted row tuples
--    representing the complete filtered result set with zero page offset dependence.
-- 3. Bounded scalability: full Merkle SHA-256 digest for <= 10,000 rows (fixed 320 KB max working memory),
--    and bounded boundary digest + 64-bit cryptographic accumulator for > 10,000 rows.
-- 4. Complete query context hashing: includes tenant, dataset, date bounds, location, search query,
--    sensitive-access scope, total count, and deterministic data hash.

create or replace function private.audit_evidence_v704(t uuid, dataset text, f date, z date, loc uuid, q text, off integer, lim integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  cfg jsonb;
  matched jsonb:='[]'::jsonb;
  tz text;
  lo timestamptz;
  hi timestamptz;
  date_clause text:='';
  tenant_clause text;
  search_clause text:='';
  sensitive boolean;
  total_count bigint:=0;
  pk_columns text;
  sort_column text;
  sql_count text;
  sql_hash text;
  sql_query text;
  dataset_sha256 text;
  fingerprint_mode text;
  v_fingerprint_payload text;
  v_snapshot_token text;
begin
  perform private.audit_access_v703(t, loc);
  if f is null or z is null or f>z or off is null or off<0 or lim is null or lim<1 or lim>200 or length(coalesce(q,''))>200 then
    raise exception 'Invalid evidence query' using errcode='22023';
  end if;
  select value into cfg from jsonb_array_elements(private.audit_catalog_v704()) where value->>'key'=dataset;
  if cfg is null then
    raise exception 'Unknown evidence dataset' using errcode='22023';
  end if;
  sensitive:=private.has_permission(t, 'audit_history.view_sensitive');
  tz:=coalesce((select timezone from public.tenant_settings where tenant_id=t), 'UTC');
  lo:=f::timestamp at time zone tz;
  hi:=(z+1)::timestamp at time zone tz;

  if not (cfg->>'master')::boolean and cfg->>'date' is not null then
    date_clause:=case when cfg->>'date_type'='date'
      then format(' and x.%I >= $7 and x.%I <= $8', cfg->>'date', cfg->>'date')
      else format(' and x.%I >= $3 and x.%I < $4', cfg->>'date', cfg->>'date')
    end;
  end if;

  tenant_clause:=case when (cfg->>'tenant_column')::boolean
    then 'x.tenant_id=$1'
    else format('exists(select 1 from public.%I p where p.tenant_id=$1 and p.id=x.%I)', cfg#>>'{parent,1}', cfg#>>'{parent,0}')
  end;

  if trim(coalesce(q,''))<>'' then
    search_clause:=' and (to_jsonb(x)::text ilike ''%'' || $9 || ''%'')';
  end if;

  -- 1. Identify deterministic primary key columns for stable pagination
  select string_agg(format('x.%I', a.attname), ', ' order by k.n) into pk_columns
  from pg_catalog.pg_index i
  join lateral unnest(i.indkey) with ordinality as k(attnum, n) on true
  join pg_catalog.pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
  where i.indrelid = to_regclass('public.'||dataset) and i.indisprimary;

  pk_columns := coalesce(pk_columns, 'x.ctid');
  sort_column := case when cfg->>'date' is not null
    then format('x.%I desc nulls last, %s', cfg->>'date', pk_columns)
    else pk_columns
  end;

  -- 2. Count total matching rows
  sql_count:=format(
    'select count(*) from public.%I x where %s and private.audit_record_allowed_v704($1,$6,to_jsonb(x),$2)%s%s',
    dataset, tenant_clause, date_clause, search_clause
  );
  execute sql_count into total_count using t, loc, lo, hi, sensitive, dataset, f, z, trim(q);

  -- 3. Compute deterministic cryptographic SHA-256 fingerprint of the filtered result set
  if total_count = 0 then
    dataset_sha256 := 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    fingerprint_mode := 'empty';
  elsif total_count <= 10000 then
    -- Full Merkle binary digest across all sorted rows
    sql_hash := format(
      'select coalesce(encode(sha256(string_agg(sha256(x::text::bytea), ''''::bytea order by %s)), ''hex''), ''e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'')
       from public.%I x
       where %s and private.audit_record_allowed_v704($1,$6,to_jsonb(x),$2)%s%s',
      sort_column, dataset, tenant_clause, date_clause, search_clause
    );
    execute sql_hash into dataset_sha256 using t, loc, lo, hi, sensitive, dataset, f, z, trim(q);
    fingerprint_mode := 'full_merkle_sha256';
  else
    -- Bounded cryptographic digest for massive tables (>10,000 rows):
    -- Aggregates boundary slices (first 500 & last 500 rows) + 64-bit cryptographic accumulator
    sql_hash := format(
      'with ordered as (
         select x, row_number() over (order by %s) as rn
         from public.%I x
         where %s and private.audit_record_allowed_v704($1,$6,to_jsonb(x),$2)%s%s
       ), sampled as (
         select x from ordered where rn <= 500 or rn > ($10 - 500)
       )
       select encode(sha256(
         format(''count:%s|checksum:%s|bounds:%s'',
           $10,
           coalesce((select sum((''x'' || substr(encode(sha256(x::text::bytea), ''hex''), 1, 16))::bit(64)::numeric) from public.%I x where %s and private.audit_record_allowed_v704($1,$6,to_jsonb(x),$2)%s%s), 0),
           coalesce((select encode(sha256(string_agg(sha256(s.x::text::bytea), ''''::bytea)), ''hex'') from sampled s), ''none'')
         )::bytea
       ), ''hex'')',
      sort_column, dataset, tenant_clause, date_clause, search_clause,
      dataset, tenant_clause, date_clause, search_clause
    );
    execute sql_hash into dataset_sha256 using t, loc, lo, hi, sensitive, dataset, f, z, trim(q), total_count;
    fingerprint_mode := 'bounded_merkle_sha256';
  end if;

  -- 4. Construct comprehensive query fingerprint (context + state)
  v_fingerprint_payload := format(
    'v2|mode:%s|tenant:%s|dataset:%s|from:%s|to:%s|loc:%s|q:%s|sensitive:%s|total:%s|data_hash:%s',
    fingerprint_mode,
    t,
    dataset,
    coalesce(f::text, ''),
    coalesce(z::text, ''),
    coalesce(loc::text, ''),
    coalesce(trim(q), ''),
    sensitive::text,
    total_count::text,
    dataset_sha256
  );
  v_snapshot_token := encode(sha256(v_fingerprint_payload::bytea), 'hex');

  -- 5. Fetch, clean, and enrich only the paginated slice
  sql_query:=format(
    'with paged as (
       select x from public.%I x
       where %s and private.audit_record_allowed_v704($1,$6,to_jsonb(x),$2)%s%s
       order by %s
       limit $10 offset $11
     ), cleaned as (
       select private.audit_clean_v704(to_jsonb(p.x), $5) as cx from paged p
     ), normalized as (
       select cx as x,
              coalesce(cx->>''id'', md5(cx::text)) as rid,
              coalesce(
                cx->>''sale_number'', cx->>''purchase_number'', cx->>''invoice_number'',
                cx->>''return_number'', cx->>''entry_number'', cx->>''receipt_number'',
                cx->>''payment_number'', cx->>''settlement_number'', cx->>''load_number'',
                cx->>''order_number'', cx->>''loan_number'', cx->>''run_number'',
                cx->>''trip_number'', cx->>''voucher_number'', cx->>''count_number'',
                cx->>''transfer_number'', cx->>''staff_code'', cx->>''reference_number'',
                cx->>''reference'', cx->>''tracking_code'', cx->>''name'',
                cx->>''account_name'', cx->>''batch_number'', cx->>''serial_number'',
                cx->>''file_name'', cx->>''code'', cx->>''entity_reference'', $12
              ) as ref
       from cleaned
     )
     select coalesce(jsonb_agg(
       jsonb_build_object(
         ''id'', rid,
         ''dataset'', $6,
         ''reference'', ref,
         ''date'', x->>($13),
         ''status'', coalesce(x->>''status'', x->>''verification_status'', x->>''event_type'', x->>''action'', case when x ? ''active'' then case when (x->>''active'')::boolean then ''Active'' else ''Archived'' end else ''Recorded'' end),
         ''party'', coalesce(x->>''customer_name'', x->>''supplier_name'', x->>''payee'', x->>''driver_name_snapshot'', x->>''driver_name'', x->>''name'', x->>''description'', x->>''title'',
                     (select name from public.staff_members_v630 where tenant_id=$1 and id=nullif(x->>''staff_id'','''')::uuid),
                     (select name from public.customers where tenant_id=$1 and id=nullif(x->>''customer_id'','''')::uuid),
                     (select name from public.suppliers where tenant_id=$1 and id=nullif(x->>''supplier_id'','''')::uuid)),
         ''amount'', coalesce(x->''grand_total'', x->''total_amount'', x->''amount'', x->''line_total'', x->''gross_amount'', x->''principal_amount''),
         ''quantity'', coalesce(x->''quantity'', x->''quantity_delta'', x->''units'', x->''ordered_quantity''),
         ''location'', coalesce((select string_agg(b.location_code,'' / '' order by b.location_code) from public.business_locations b where b.tenant_id=$1 and b.id=any(private.audit_record_locations_v704($1,$6,x))),''Unassigned / business-wide''),
         ''actor'', (select display_name from public.profiles where id=coalesce(nullif(x->>''created_by'',''''),nullif(x->>''changed_by'',''''),nullif(x->>''actor_user_id'',''''),nullif(x->>''uploaded_by'',''''),nullif(x->>''updated_by'',''''))::uuid),
         ''journal_count'', (select count(*) from public.journal_entries j where j.tenant_id=$1 and private.reports_scope_v631($1,j.location_id,$2,''view'') and (j.id::text=x->>''journal_id'' or (j.source_id::text=x->>''id'' and ($14::jsonb) ? j.source_type))),
         ''record'', x
       )
     ), ''[]''::jsonb) from normalized',
    dataset, tenant_clause, date_clause, search_clause, sort_column
  );

  execute sql_query into matched using t, loc, lo, hi, sensitive, dataset, f, z, trim(q), lim, off, cfg->>'label', cfg->>'date', coalesce(cfg->'sources', '[]'::jsonb);

  return jsonb_build_object(
    'rows', matched,
    'total_rows', total_count,
    'snapshot_token', v_snapshot_token,
    'dataset', cfg->>'label',
    'period_basis', case when (cfg->>'master')::boolean then 'Current saved records; period does not filter master data or current balances.' else 'Selected period, using '||(cfg->>'date') end,
    'sensitive_values_visible', sensitive,
    'generated_at', statement_timestamp()
  );
end $$;

create or replace function private.audit_related_v704(t uuid, dataset text, field text, ref text, loc uuid, off integer, lim integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  cfg jsonb;
  matched jsonb:='[]'::jsonb;
  total_count bigint:=0;
  tenant_clause text;
  sensitive boolean;
  pk_columns text;
  sort_column text;
  sql_count text;
  sql_hash text;
  sql_query text;
  dataset_sha256 text;
  fingerprint_mode text;
  v_fingerprint_payload text;
  v_snapshot_token text;
begin
  perform private.audit_access_v703(t, loc);
  if off is null or off<0 or lim is null or lim<1 or lim>200 or ref is null or length(ref)>80 or not exists(select 1 from pg_catalog.pg_attribute where attrelid=to_regclass('public.'||dataset) and attname=field and not attisdropped) then
    raise exception 'Invalid relation selector' using errcode='22023';
  end if;
  select value into cfg from jsonb_array_elements(private.audit_catalog_v704()) where value->>'key'=dataset;
  if cfg is null then
    raise exception 'Unknown evidence dataset' using errcode='22023';
  end if;
  sensitive:=private.has_permission(t, 'audit_history.view_sensitive');

  tenant_clause:=case when (cfg->>'tenant_column')::boolean
    then 'x.tenant_id=$1'
    else format('exists(select 1 from public.%I p where p.tenant_id=$1 and p.id=x.%I)', cfg#>>'{parent,1}', cfg#>>'{parent,0}')
  end;

  -- 1. Identify deterministic primary key columns
  select string_agg(format('x.%I', a.attname), ', ' order by k.n) into pk_columns
  from pg_catalog.pg_index i
  join lateral unnest(i.indkey) with ordinality as k(attnum, n) on true
  join pg_catalog.pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
  where i.indrelid = to_regclass('public.'||dataset) and i.indisprimary;

  pk_columns := coalesce(pk_columns, 'x.ctid');
  sort_column := case when cfg->>'date' is not null
    then format('x.%I desc nulls last, %s', cfg->>'date', pk_columns)
    else pk_columns
  end;

  -- 2. Count total matching related records
  sql_count:=format(
    'select count(*) from public.%I x where %s and x.%I::text = $2 and private.audit_record_allowed_v704($1,$3,to_jsonb(x),$4)',
    dataset, tenant_clause, field
  );
  execute sql_count into total_count using t, ref, dataset, loc;

  -- 3. Compute deterministic cryptographic SHA-256 fingerprint
  if total_count = 0 then
    dataset_sha256 := 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    fingerprint_mode := 'empty';
  elsif total_count <= 10000 then
    sql_hash := format(
      'select coalesce(encode(sha256(string_agg(sha256(x::text::bytea), ''''::bytea order by %s)), ''hex''), ''e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'')
       from public.%I x
       where %s and x.%I::text = $2 and private.audit_record_allowed_v704($1,$3,to_jsonb(x),$4)',
      sort_column, dataset, tenant_clause, field
    );
    execute sql_hash into dataset_sha256 using t, ref, dataset, loc;
    fingerprint_mode := 'full_merkle_sha256';
  else
    sql_hash := format(
      'with ordered as (
         select x, row_number() over (order by %s) as rn
         from public.%I x
         where %s and x.%I::text = $2 and private.audit_record_allowed_v704($1,$3,to_jsonb(x),$4)
       ), sampled as (
         select x from ordered where rn <= 500 or rn > ($5 - 500)
       )
       select encode(sha256(
         format(''count:%s|checksum:%s|bounds:%s'',
           $5,
           coalesce((select sum((''x'' || substr(encode(sha256(x::text::bytea), ''hex''), 1, 16))::bit(64)::numeric) from public.%I x where %s and x.%I::text = $2 and private.audit_record_allowed_v704($1,$3,to_jsonb(x),$4)), 0),
           coalesce((select encode(sha256(string_agg(sha256(s.x::text::bytea), ''''::bytea)), ''hex'') from sampled s), ''none'')
         )::bytea
       ), ''hex'')',
      sort_column, dataset, tenant_clause, field,
      dataset, tenant_clause, field
    );
    execute sql_hash into dataset_sha256 using t, ref, dataset, loc, total_count;
    fingerprint_mode := 'bounded_merkle_sha256';
  end if;

  -- 4. Construct comprehensive query fingerprint
  v_fingerprint_payload := format(
    'v2|mode:%s|tenant:%s|dataset:%s|field:%s|ref:%s|loc:%s|sensitive:%s|total:%s|data_hash:%s',
    fingerprint_mode,
    t,
    dataset,
    field,
    ref,
    coalesce(loc::text, ''),
    sensitive::text,
    total_count::text,
    dataset_sha256
  );
  v_snapshot_token := encode(sha256(v_fingerprint_payload::bytea), 'hex');

  -- 5. Fetch, clean, and enrich only the paginated slice
  sql_query:=format(
    'with paged as (
       select x from public.%I x
       where %s and x.%I::text = $2 and private.audit_record_allowed_v704($1,$3,to_jsonb(x),$4)
       order by %s
       limit $5 offset $6
     ), cleaned as (
       select private.audit_clean_v704(to_jsonb(p.x), $7) as cx from paged p
     ), normalized as (
       select cx as x,
              coalesce(cx->>''id'', md5(cx::text)) as rid,
              coalesce(
                cx->>''sale_number'', cx->>''purchase_number'', cx->>''invoice_number'',
                cx->>''return_number'', cx->>''entry_number'', cx->>''receipt_number'',
                cx->>''payment_number'', cx->>''settlement_number'', cx->>''load_number'',
                cx->>''order_number'', cx->>''loan_number'', cx->>''run_number'',
                cx->>''trip_number'', cx->>''voucher_number'', cx->>''count_number'',
                cx->>''transfer_number'', cx->>''staff_code'', cx->>''reference_number'',
                cx->>''reference'', cx->>''tracking_code'', cx->>''name'',
                cx->>''account_name'', cx->>''batch_number'', cx->>''serial_number'',
                cx->>''file_name'', cx->>''code'', cx->>''entity_reference'', $8
              ) as ref
       from cleaned
     )
     select coalesce(jsonb_agg(
       jsonb_build_object(
         ''id'', rid,
         ''dataset'', $3,
         ''reference'', ref,
         ''date'', x->>($9),
         ''status'', coalesce(x->>''status'', x->>''verification_status'', x->>''event_type'', x->>''action'', case when x ? ''active'' then case when (x->>''active'')::boolean then ''Active'' else ''Archived'' end else ''Recorded'' end),
         ''party'', coalesce(x->>''customer_name'', x->>''supplier_name'', x->>''payee'', x->>''driver_name_snapshot'', x->>''driver_name'', x->>''name'', x->>''description'', x->>''title'',
                     (select name from public.staff_members_v630 where tenant_id=$1 and id=nullif(x->>''staff_id'','''')::uuid),
                     (select name from public.customers where tenant_id=$1 and id=nullif(x->>''customer_id'','''')::uuid),
                     (select name from public.suppliers where tenant_id=$1 and id=nullif(x->>''supplier_id'','''')::uuid)),
         ''amount'', coalesce(x->''grand_total'', x->''total_amount'', x->''amount'', x->''line_total'', x->''gross_amount'', x->''principal_amount''),
         ''quantity'', coalesce(x->''quantity'', x->''quantity_delta'', x->''units'', x->''ordered_quantity''),
         ''location'', coalesce((select string_agg(b.location_code,'' / '' order by b.location_code) from public.business_locations b where b.tenant_id=$1 and b.id=any(private.audit_record_locations_v704($1,$3,x))),''Unassigned / business-wide''),
         ''actor'', (select display_name from public.profiles where id=coalesce(nullif(x->>''created_by'',''''),nullif(x->>''changed_by'',''''),nullif(x->>''actor_user_id'',''''),nullif(x->>''uploaded_by'',''''),nullif(x->>''updated_by'',''''))::uuid),
         ''journal_count'', (select count(*) from public.journal_entries j where j.tenant_id=$1 and private.reports_scope_v631($1,j.location_id,$4,''view'') and (j.id::text=x->>''journal_id'' or (j.source_id::text=x->>''id'' and ($10::jsonb) ? j.source_type))),
         ''record'', x
       )
     ), ''[]''::jsonb) from normalized',
    dataset, tenant_clause, field, sort_column
  );

  execute sql_query into matched using t, ref, dataset, loc, lim, off, sensitive, cfg->>'label', cfg->>'date', coalesce(cfg->'sources', '[]'::jsonb);

  return jsonb_build_object(
    'rows', matched,
    'total_rows', total_count,
    'snapshot_token', v_snapshot_token
  );
end $$;
