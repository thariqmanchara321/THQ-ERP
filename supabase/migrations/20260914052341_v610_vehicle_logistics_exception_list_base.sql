create or replace function public.logistics_exceptions_list_v1(p_tenant_id uuid,p_location_id uuid default null,p_status text default null,p_trip_id uuid default null,p_limit integer default 500)
returns setof jsonb
language sql
stable
security definer
set search_path to 'public','private','pg_temp'
as $$
  select jsonb_build_object('id',e.id,'trip_id',e.trip_id,'exception_type',e.exception_type,'quantity',e.quantity,'status',e.status)
  from public.transport_logistics_exceptions e
  where e.tenant_id=p_tenant_id
    and (p_trip_id is null or e.trip_id=p_trip_id)
    and (p_status is null or trim(p_status)='' or e.status=lower(trim(p_status)))
  order by e.opened_at desc
  limit greatest(1,least(coalesce(p_limit,500),2000));
$$;
revoke all on function public.logistics_exceptions_list_v1(uuid,uuid,text,uuid,integer) from public, anon;
grant execute on function public.logistics_exceptions_list_v1(uuid,uuid,text,uuid,integer) to authenticated, service_role;;
