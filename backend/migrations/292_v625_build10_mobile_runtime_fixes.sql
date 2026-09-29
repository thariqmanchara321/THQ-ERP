begin;

-- THQ ERP v6.2.5 Build 10 — Mobile Runtime Fixes.
-- Fixes the Client Mobile sales read RPC and adds a read-only performance
-- summary for Today / All time with device/store scope enforcement.
-- No GST, accounting, inventory quantity, sale, purchase, return, payment,
-- offline, cashier, restaurant or logistics writer behavior is changed.

create or replace function public.mobile_sales_status_v487(
  p_tenant_id uuid,
  p_device_id uuid,
  p_location_id uuid default null,
  p_limit integer default 100
)
returns table(
  id uuid,
  sale_number text,
  sale_date date,
  customer_name text,
  status text,
  grand_total numeric,
  paid_total numeric,
  balance_due numeric,
  location_name text
)
language plpgsql
stable
security definer
set search_path = 'public','private','pg_temp'
as $function$
declare
  v_bound uuid;
  v_loc uuid;
begin
  v_bound := private.v487_client_mobile_location(p_tenant_id,p_device_id);
  v_loc := coalesce(
    p_location_id,
    case
      when private.erp_user_is_owner(p_tenant_id)
        or private.erp_has_permission(p_tenant_id,'locations.view_all')
        or private.erp_has_permission(p_tenant_id,'locations.manage_all')
      then null
      else v_bound
    end
  );

  if v_loc is not null
     and not private.erp_document_scope_allowed(
       p_tenant_id,v_loc,v_loc,'view'
     ) then
    raise exception 'Location access denied';
  end if;

  return query
  select
    s.id,
    s.sale_number,
    s.sale_date,
    coalesce(nullif(s.customer_name,''),c.name,'Walk-in customer')::text,
    coalesce(s.status,'posted')::text,
    s.grand_total::numeric,
    coalesce(py.paid,0)::numeric,
    greatest(
      s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),
      0
    )::numeric,
    coalesce(l.name,'')::text
  from public.sales s
  left join public.customers c
    on c.tenant_id=s.tenant_id
   and c.id=s.customer_id
  left join public.document_origins o
    on o.tenant_id=s.tenant_id
   and o.entity_type='sale'
   and o.entity_id=s.id
  left join public.business_locations l
    on l.tenant_id=s.tenant_id
   and l.id=o.location_id
  left join (
    select sp.sale_id,sum(sp.amount)::numeric paid
    from public.sale_payments sp
    where sp.tenant_id=p_tenant_id
    group by sp.sale_id
  ) py on py.sale_id=s.id
  left join (
    select sr.sale_id,sum(sr.grand_total)::numeric returned
    from public.sales_returns sr
    where sr.tenant_id=p_tenant_id
      and sr.refund_status<>'waived'
    group by sr.sale_id
  ) rt on rt.sale_id=s.id
  where s.tenant_id=p_tenant_id
    and (v_loc is null or o.location_id=v_loc)
    and private.erp_document_scope_allowed(
      p_tenant_id,o.location_id,v_loc,'view'
    )
  order by s.sale_date desc,s.created_at desc
  limit greatest(1,least(coalesce(p_limit,100),500));
end;
$function$;

revoke execute on function public.mobile_sales_status_v487(uuid,uuid,uuid,integer)
  from public, anon;
grant execute on function public.mobile_sales_status_v487(uuid,uuid,uuid,integer)
  to authenticated, service_role;

create or replace function public.mobile_client_performance_v625(
  p_tenant_id uuid,
  p_device_id uuid,
  p_period text default 'today',
  p_location_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public','private','pg_temp'
as $function$
declare
  v_bound uuid;
  v_location uuid;
  v_period text := lower(trim(coalesce(p_period,'today')));
  v_from date;
  v_to date := current_date;
  v_daily jsonb;
  v_report jsonb;
begin
  v_bound := private.v487_client_mobile_location(p_tenant_id,p_device_id);

  v_location := coalesce(
    p_location_id,
    case
      when private.erp_user_is_owner(p_tenant_id)
        or private.erp_has_permission(p_tenant_id,'locations.view_all')
        or private.erp_has_permission(p_tenant_id,'locations.manage_all')
      then null
      else v_bound
    end
  );

  if v_location is not null
     and not private.erp_document_scope_allowed(
       p_tenant_id,v_location,v_location,'view'
     ) then
    raise exception 'Location access denied';
  end if;

  if v_period not in ('today','all_time') then
    raise exception 'Unsupported mobile performance period';
  end if;

  if v_period='today' then
    v_from := current_date;
  else
    select least(
      coalesce((
        select min(s.sale_date)
        from public.sales s
        left join public.document_origins o
          on o.tenant_id=s.tenant_id
         and o.entity_type='sale'
         and o.entity_id=s.id
        where s.tenant_id=p_tenant_id
          and private.erp_document_scope_allowed(
            p_tenant_id,o.location_id,v_location,'view'
          )
      ),current_date),
      coalesce((
        select min(p.purchase_date)
        from public.purchases p
        left join public.document_origins o
          on o.tenant_id=p.tenant_id
         and o.entity_type='purchase'
         and o.entity_id=p.id
        where p.tenant_id=p_tenant_id
          and private.erp_document_scope_allowed(
            p_tenant_id,o.location_id,v_location,'view'
          )
      ),current_date),
      coalesce((
        select min(e.expense_date)
        from public.expenses e
        left join public.document_origins o
          on o.tenant_id=e.tenant_id
         and o.entity_type='expense'
         and o.entity_id=e.id
        where e.tenant_id=p_tenant_id
          and private.erp_document_scope_allowed(
            p_tenant_id,o.location_id,v_location,'view'
          )
      ),current_date)
    )
    into v_from;
  end if;

  v_daily := public.mobile_client_dashboard_v487(
    p_tenant_id,p_device_id,current_date,v_location
  );
  v_report := public.reports_get_summary_v4(
    p_tenant_id,v_from,v_to,v_location
  );

  return coalesce(v_daily,'{}'::jsonb)
    || coalesce(v_report,'{}'::jsonb)
    || jsonb_build_object(
      'period',v_period,
      'from_date',v_from,
      'to_date',v_to,
      'location_id',v_location,
      'scope',case when v_location is null then 'business' else 'store' end,
      'net_sales',coalesce((v_report->>'sales')::numeric,0),
      'invoice_count',coalesce((v_report->>'sale_count')::bigint,0)
    );
end;
$function$;

revoke execute on function public.mobile_client_performance_v625(uuid,uuid,text,uuid)
  from public, anon;
grant execute on function public.mobile_client_performance_v625(uuid,uuid,text,uuid)
  to authenticated, service_role;

insert into public.platform_app_releases(
  id,app_key,platform,version,build_number,status,
  minimum_supported,mandatory,release_notes,download_url,released_at
)
values
(
  gen_random_uuid(),'client','android','6.2.5',10,'stable',false,false,
  'THQ ERP v6.2.5 Build 10 — Mobile Runtime Fixes. Repairs Client Mobile sales loading and adds Today / All time business performance with entire-business or per-store scope. No transaction writer behavior changes.',
  null,now()
),
(
  gen_random_uuid(),'pos','android','6.2.5',10,'stable',false,false,
  'THQ ERP v6.2.5 Build 10 — Mobile Runtime Fixes. Adds clear selected-product highlighting and selected quantity badges in Mobile POS. Existing v5.2 authoritative GST and offline transaction authority remain unchanged.',
  null,now()
)
on conflict(app_key,platform,version) do update
set build_number=excluded.build_number,
    status=excluded.status,
    minimum_supported=excluded.minimum_supported,
    mandatory=excluded.mandatory,
    release_notes=excluded.release_notes;

insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  292,
  '6.2.5-build10',
  'v6.2.5 Build 10 Mobile Runtime Fixes',
  'Repairs the read-only Client Mobile sales status RPC, adds read-only scoped mobile performance summaries, and synchronizes Client/POS Android release metadata. No authoritative transaction writer behavior changes.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
