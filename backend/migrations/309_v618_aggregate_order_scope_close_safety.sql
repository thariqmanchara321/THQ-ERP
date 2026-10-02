-- THQ ERP v6.1.8 — Aggregate Order Scope & Close Safety
-- Supabase: ALREADY LIVE. Keep this file for repository migration history.

drop policy if exists aggregate_order_lines_v618_read
on public.aggregate_order_lines_v618;

create policy aggregate_order_lines_v618_read
on public.aggregate_order_lines_v618
for select to authenticated
using(
  private.erp_user_has_tenant_access(tenant_id)
  and exists(
    select 1
    from public.aggregate_orders_v618 o
    where o.id=aggregate_order_lines_v618.order_id
      and o.tenant_id=aggregate_order_lines_v618.tenant_id
      and private.erp_document_scope_allowed(
        aggregate_order_lines_v618.tenant_id,
        o.location_id,
        o.location_id,
        'view'
      )
  )
  and exists(
    select 1 from public.tenant_modules tm
    where tm.tenant_id=aggregate_order_lines_v618.tenant_id
      and tm.module_key='aggregate_yard'
      and tm.enabled
  )
  and (
    private.erp_has_permission(tenant_id,'aggregate_yard.view')
    or private.erp_has_permission(tenant_id,'aggregate_yard.manage')
    or private.erp_has_permission(tenant_id,'aggregate_yard.orders.view')
    or private.erp_has_permission(tenant_id,'aggregate_yard.orders.manage')
  )
);

drop policy if exists aggregate_order_events_v618_read
on public.aggregate_order_events_v618;

create policy aggregate_order_events_v618_read
on public.aggregate_order_events_v618
for select to authenticated
using(
  private.erp_user_has_tenant_access(tenant_id)
  and exists(
    select 1
    from public.aggregate_orders_v618 o
    where o.id=aggregate_order_events_v618.order_id
      and o.tenant_id=aggregate_order_events_v618.tenant_id
      and private.erp_document_scope_allowed(
        aggregate_order_events_v618.tenant_id,
        o.location_id,
        o.location_id,
        'view'
      )
  )
  and exists(
    select 1 from public.tenant_modules tm
    where tm.tenant_id=aggregate_order_events_v618.tenant_id
      and tm.module_key='aggregate_yard'
      and tm.enabled
  )
  and (
    private.erp_has_permission(tenant_id,'aggregate_yard.view')
    or private.erp_has_permission(tenant_id,'aggregate_yard.manage')
    or private.erp_has_permission(tenant_id,'aggregate_yard.orders.view')
    or private.erp_has_permission(tenant_id,'aggregate_yard.orders.manage')
  )
);

create or replace function public.aggregate_order_close_v618(
  p_tenant_id uuid,
  p_order_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_order public.aggregate_orders_v618%rowtype;
  v_delivered numeric:=0;
  v_active_loads bigint:=0;
  v_status text;
begin
  perform private.aggregate_yard_assert_orders_manage_v618(p_tenant_id);

  select * into v_order
  from public.aggregate_orders_v618
  where id=p_order_id
    and tenant_id=p_tenant_id
  for update;

  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  if v_order.status='completed' then
    raise exception 'Completed order cannot be closed';
  end if;

  if v_order.status in('cancelled','closed_partial') then
    return jsonb_build_object(
      'order_id',v_order.id,
      'order_number',v_order.order_number,
      'status',v_order.status
    );
  end if;

  if nullif(trim(coalesce(p_reason,'')),'') is null then
    raise exception 'Close reason is required';
  end if;

  select count(*)
  into v_active_loads
  from public.aggregate_loads_v617 l
  where l.tenant_id=p_tenant_id
    and l.order_id=p_order_id
    and l.status in('draft','loading','dispatched','in_transit','arrived');

  if v_active_loads>0 then
    raise exception
      'Order has % active load(s). Complete or cancel those loads before closing the order.',
      v_active_loads;
  end if;

  select coalesce(sum(l.quantity),0)
  into v_delivered
  from public.aggregate_loads_v617 l
  where l.tenant_id=p_tenant_id
    and l.order_id=p_order_id
    and l.status in('delivered','completed');

  v_status:=case
    when v_delivered>0.0001 then 'closed_partial'
    else 'cancelled'
  end;

  update public.aggregate_orders_v618
  set status=v_status,
      close_reason=trim(p_reason),
      closed_by=auth.uid(),
      closed_at=now(),
      updated_by=auth.uid(),
      updated_at=now()
  where id=p_order_id
    and tenant_id=p_tenant_id;

  insert into public.aggregate_order_events_v618(
    tenant_id,order_id,event_type,from_status,to_status,note,metadata,created_by
  )
  values(
    p_tenant_id,p_order_id,'closed',v_order.status,v_status,
    trim(p_reason),
    jsonb_build_object('delivered_quantity_all_units',v_delivered),
    auth.uid()
  );

  return jsonb_build_object(
    'order_id',p_order_id,
    'order_number',v_order.order_number,
    'status',v_status
  );
end
$$;

revoke all
on function public.aggregate_order_close_v618(uuid,uuid,text)
from public,anon;

grant execute
on function public.aggregate_order_close_v618(uuid,uuid,text)
to authenticated,service_role;

insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  309,
  '6.1.8-aggregate-order-safety',
  'Aggregate Order Scope & Close Safety',
  'Hardens order line/event read policies with parent-order location scope and module checks, and prevents closing customer orders while active linked truck loads remain. No financial or stock writer changes.'
);
