-- THQ ERP v6.0
-- Customer outstanding correctness and activity timeline hardening.

create or replace function public.customer_outstanding_v46(
  p_tenant_id uuid,
  p_customer_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_outstanding numeric:=0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'sales.view')
    or private.erp_has_permission(p_tenant_id,'sales.manage')
    or private.erp_has_permission(p_tenant_id,'customers.view')
    or private.erp_has_permission(p_tenant_id,'customers.manage')
    or private.erp_has_permission(p_tenant_id,'accounting.view')
  ) then
    raise exception 'Customer balance view permission required';
  end if;
  if not exists(
    select 1 from public.customers c
    where c.tenant_id=p_tenant_id and c.id=p_customer_id
  ) then
    raise exception 'Customer not found';
  end if;

  select round(coalesce(sum(greatest(
    s.grand_total
    - coalesce(pay.paid,0)
    - coalesce(ret.returned,0),
    0
  )),0),2)
  into v_outstanding
  from public.sales s
  left join lateral (
    select coalesce(sum(sp.amount),0) paid
    from public.sale_payments sp
    where sp.tenant_id=s.tenant_id and sp.sale_id=s.id
  ) pay on true
  left join lateral (
    select coalesce(sum(sr.grand_total),0) returned
    from public.sales_returns sr
    where sr.tenant_id=s.tenant_id
      and sr.sale_id=s.id
      and coalesce(sr.refund_status,'')<>'waived'
  ) ret on true
  where s.tenant_id=p_tenant_id
    and s.customer_id=p_customer_id
    and coalesce(s.status,'') not in('void','cancelled');

  return jsonb_build_object(
    'customer_id',p_customer_id,
    'outstanding',v_outstanding
  );
end
$function$;

create or replace function public.entity_activity_timeline_v4(
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_limit integer default 100
)
returns table(
  activity_time timestamp with time zone,
  activity_type text,
  title text,
  description text,
  user_name text,
  location_code text,
  device_code text,
  metadata jsonb
)
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  return query
  select * from (
    select
      a.created_at,
      'audit'::text,
      a.action::text,
      coalesce(a.entity_reference,a.entity_type,'')::text,
      coalesce(u.username::text,''::text),
      coalesce(l.location_code::text,''::text),
      coalesce(d.device_code::text,''::text),
      coalesce(a.metadata,'{}'::jsonb)
        || jsonb_build_object(
          'before',a.before_data,
          'after',a.after_data,
          'reason',a.reason
        )
    from public.business_audit_log a
    left join public.user_login_names u on u.user_id=a.user_id
    left join public.business_locations l on l.id=a.location_id
    left join public.business_devices d on d.id=a.device_id
    where a.tenant_id=p_tenant_id
      and a.entity_type=p_entity_type
      and a.entity_id=p_entity_id

    union all

    select
      c.created_at,
      'correction'::text,
      c.correction_type::text,
      c.reason::text,
      coalesce(u.username::text,''::text),
      coalesce(l.location_code::text,''::text),
      coalesce(d.device_code::text,''::text),
      coalesce(c.metadata,'{}'::jsonb)
    from public.transaction_corrections c
    left join public.user_login_names u on u.user_id=c.created_by
    left join public.document_origins o
      on o.tenant_id=c.tenant_id
     and o.entity_type=c.entity_type
     and o.entity_id=c.entity_id
    left join public.business_locations l on l.id=o.location_id
    left join public.business_devices d on d.id=o.device_id
    where c.tenant_id=p_tenant_id
      and c.entity_type=p_entity_type
      and c.entity_id=p_entity_id

    union all

    select
      p.created_at,
      'print'::text,
      p.action::text,
      coalesce(p.invoice_number::text,''::text),
      coalesce(u.username::text,''::text),
      coalesce(l.location_code::text,''::text),
      coalesce(d.device_code::text,''::text),
      jsonb_build_object(
        'copy_number',p.copy_number,
        'template_id',p.template_id,
        'printer_profile_id',p.printer_profile_id
      )
    from public.invoice_print_events p
    left join public.user_login_names u on u.user_id=p.created_by
    left join public.business_devices d on d.id=p.device_id
    left join public.business_locations l on l.id=d.location_id
    where p.tenant_id=p_tenant_id
      and p.entity_type=p_entity_type
      and p.entity_id=p_entity_id
  ) x
  order by activity_time desc
  limit greatest(1,least(coalesce(p_limit,100),500));
end
$function$;

revoke execute on function public.customer_outstanding_v46(uuid,uuid)
from public, anon;
revoke execute on function public.entity_activity_timeline_v4(uuid,text,uuid,integer)
from public, anon;

grant execute on function public.customer_outstanding_v46(uuid,uuid)
to authenticated, service_role;
grant execute on function public.entity_activity_timeline_v4(uuid,text,uuid,integer)
to authenticated, service_role;
