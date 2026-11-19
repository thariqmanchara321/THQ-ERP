-- Phase A.1: Corrective Review: Export, Redaction & Migration Integrity
-- 1. Complete sensitive-field redaction: emails, phones, addresses, bank accounts/IFSC, tax IDs
-- 2. Sensitive fields replaced with '[REDACTED]' instead of dropped, while credentials/secrets remain unconditionally excluded
-- 3. Recursive cleaning through nested JSON objects and arrays
-- 4. Multi-page CSV export snapshot consistency: stable snapshot token across pages, independent of offset
-- 5. Safe tie-breaker ordering fallback to ctid for datasets lacking an id column

create or replace function private.audit_clean_v704(v jsonb, sensitive boolean) returns jsonb
language plpgsql immutable set search_path='' as $$
declare
  outv jsonb;
  k text;
  x jsonb;
begin
  if jsonb_typeof(v) = 'object' then
    outv := '{}'::jsonb;
    for k, x in select * from jsonb_each(v) loop
      -- 1. Unconditionally exclude credentials, tokens, password hashes, and secrets
      if k ~* '(secret|password|token|credential|activation_hash|provider_config|stack_trace|api[_-]?key|authorization|cookie)' then
        continue;
      end if;

      -- 2. Sensitive fields: redact to '[REDACTED]' if caller lacks audit_history.view_sensitive
      if not sensitive and (
        -- Email variants
        k ~* '^(.*_)?email(_address)?$' or
        -- Phone, mobile, emergency contact, contact person variants
        k ~* '^(.*_)?(phone|mobile)(_.*)?$' or
        k in ('emergency_contact', 'contact_person') or
        -- Address variants
        k ~* '^(.*_)?address(_line[12])?$' or
        k in ('delivery_address', 'shipping_address', 'billing_address') or
        -- Bank account & IFSC variants (matches account_number, but preserves account_name and account_id)
        k ~* '^(.*_)?(ifsc(_code)?|bank_account|account_number(_masked)?)$' or
        k in ('bank_ifsc', 'ifsc_code', 'account_number_masked', 'payee_snapshot') or
        -- Personal identification / tax numbers
        k ~* '^(pan|aadhaar|id_proof_number|passport_number)$'
      ) then
        outv := outv || jsonb_build_object(k, '"[REDACTED]"'::jsonb);
      else
        -- Recurse into nested objects and arrays
        outv := outv || jsonb_build_object(k, private.audit_clean_v704(x, sensitive));
      end if;
    end loop;
    return outv;
  elsif jsonb_typeof(v) = 'array' then
    select coalesce(jsonb_agg(private.audit_clean_v704(value, sensitive)), '[]'::jsonb)
    into outv
    from jsonb_array_elements(v);
    return outv;
  end if;
  return v;
end $$;

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
  row_checksum bigint:=0;
  has_id boolean:=false;
  sort_id text;
  sort_column text;
  sql_query text;
  sql_count text;
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

  -- Count total matching rows and compute content checksum without constructing full JSON
  sql_count:=format(
    'select count(*), coalesce(sum((''x'' || substr(md5(x::text), 1, 8))::bit(32)::bigint), 0) from public.%I x where %s and private.audit_record_allowed_v704($1,$6,to_jsonb(x),$2)%s%s',
    dataset, tenant_clause, date_clause, search_clause
  );
  execute sql_count into total_count, row_checksum using t, loc, lo, hi, sensitive, dataset, f, z, trim(q);

  -- Safe tie-breaker sort: use x.id if present, otherwise fallback to x.ctid
  has_id:=exists(select 1 from pg_catalog.pg_attribute where attrelid=to_regclass('public.'||dataset) and attname='id' and not attisdropped);
  sort_id:=case when has_id then 'x.id' else 'x.ctid' end;
  sort_column:=case when cfg->>'date' is not null then format('x.%I desc nulls last, %s', cfg->>'date', sort_id) else sort_id end;

  -- Build stable snapshot token independent of offset
  v_snapshot_token:=md5(
    coalesce(dataset, '') || ':' ||
    total_count::text || ':' ||
    row_checksum::text || ':' ||
    coalesce(f::text, '') || ':' ||
    coalesce(z::text, '') || ':' ||
    coalesce(loc::text, '') || ':' ||
    coalesce(trim(q), '') || ':' ||
    sensitive::text
  );

  -- Fetch, clean, and enrich only the paginated slice
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
  row_checksum bigint:=0;
  tenant_clause text;
  sensitive boolean;
  has_id boolean:=false;
  sort_id text;
  sort_column text;
  sql_count text;
  sql_query text;
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

  -- Efficient direct relation count & content checksum
  sql_count:=format(
    'select count(*), coalesce(sum((''x'' || substr(md5(x::text), 1, 8))::bit(32)::bigint), 0) from public.%I x where %s and x.%I::text = $2 and private.audit_record_allowed_v704($1,$3,to_jsonb(x),$4)',
    dataset, tenant_clause, field
  );
  execute sql_count into total_count, row_checksum using t, ref, dataset, loc;

  -- Safe tie-breaker sort
  has_id:=exists(select 1 from pg_catalog.pg_attribute where attrelid=to_regclass('public.'||dataset) and attname='id' and not attisdropped);
  sort_id:=case when has_id then 'x.id' else 'x.ctid' end;
  sort_column:=case when cfg->>'date' is not null then format('x.%I desc nulls last, %s', cfg->>'date', sort_id) else sort_id end;

  -- Build stable snapshot token independent of offset
  v_snapshot_token:=md5(
    coalesce(dataset, '') || ':' ||
    total_count::text || ':' ||
    row_checksum::text || ':' ||
    coalesce(field, '') || ':' ||
    coalesce(ref, '') || ':' ||
    coalesce(loc::text, '') || ':' ||
    sensitive::text
  );

  -- Efficient direct relation page fetch with enrichment
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

create or replace function private.audit_evidence_export_v704(t uuid, dataset text, f date, z date, loc uuid, q text, off integer, lim integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  perform private.audit_access_v703(t, loc);
  if not private.has_permission(t, 'audit_center.export') then
    raise exception 'Audit export denied' using errcode='42501';
  end if;
  return private.audit_evidence_v704(t, dataset, f, z, loc, q, off, lim);
end $$;
