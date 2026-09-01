-- THQ ERP V4.8.7 — mobile approvals and customer payment actions.
begin;
create or replace function public.mobile_approvals_v487(p_tenant_id uuid,p_device_id uuid,p_status text default 'pending',p_limit integer default 200)
returns table(approval_type text,id uuid,reference text,module_key text,action_key text,location_id uuid,location_name text,amount numeric,status text,summary text,requested_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
begin
  perform private.v487_client_mobile_location(p_tenant_id,p_device_id);
  return query
  select * from (
    select 'approval_request'::text,a.id,coalesce(a.entity_type,'')||case when a.entity_id is null then '' else ' '||a.entity_id::text end,a.module_key,a.action_key,null::uuid,null::text,a.amount,a.status,coalesce(a.reason,a.action_key),a.requested_at
      from public.approval_requests a where a.tenant_id=p_tenant_id and (p_status is null or p_status='' or a.status=p_status)
    union all
    select 'purchase_request'::text,r.id,r.request_number,'purchases','approve_purchase_request',r.location_id,l.name,
      coalesce((select sum(i.quantity*i.estimated_unit_cost) from public.purchase_request_items_v484 i where i.request_id=r.id),0)::numeric,r.status,coalesce(r.purpose,'Purchase Request'),coalesce(r.submitted_at,r.created_at)
      from public.purchase_requests_v484 r join public.business_locations l on l.id=r.location_id
      where r.tenant_id=p_tenant_id and (p_status is null or p_status='' or (p_status='pending' and r.status='submitted') or r.status=p_status)
        and private.erp_document_scope_allowed(p_tenant_id,r.location_id,null,'view')
    union all
    select 'purchase_order'::text,o.id,o.order_number,'purchases','approve_purchase_order',o.location_id,l.name,o.grand_total,o.status,'Purchase Order • '||s.name,coalesce(o.submitted_at,o.created_at)
      from public.purchase_orders_v480 o join public.business_locations l on l.id=o.location_id join public.suppliers s on s.id=o.supplier_id
      where o.tenant_id=p_tenant_id and (p_status is null or p_status='' or (p_status='pending' and o.status='submitted') or o.status=p_status)
        and private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view')
  ) q order by requested_at desc limit greatest(1,least(coalesce(p_limit,200),1000));
end$$;
grant execute on function public.mobile_approvals_v487(uuid,uuid,text,integer) to authenticated;

create or replace function public.mobile_approval_decide_v487(p_tenant_id uuid,p_device_id uuid,p_approval_type text,p_id uuid,p_approve boolean,p_note text default '')
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_type text:=lower(trim(coalesce(p_approval_type,'')));v_result jsonb;
begin
  perform private.v487_client_mobile_location(p_tenant_id,p_device_id);
  if v_type='approval_request' then
    perform public.approval_request_decide_v4(p_tenant_id,p_id,p_approve,p_note);
    return jsonb_build_object('success',true,'approval_type',v_type,'id',p_id,'status',case when p_approve then 'approved' else 'rejected' end);
  elsif v_type='purchase_request' then
    return public.purchase_request_status_v484(p_tenant_id,p_id,case when p_approve then 'approved' else 'rejected' end,p_note);
  elsif v_type='purchase_order' then
    return public.purchase_order_decide_v484(p_tenant_id,p_id,p_approve,p_note);
  end if;
  raise exception 'Unsupported mobile approval type';
end$$;
grant execute on function public.mobile_approval_decide_v487(uuid,uuid,text,uuid,boolean,text) to authenticated;

create or replace function public.mobile_customer_payment_v487(
  p_tenant_id uuid,p_device_id uuid,p_customer_id uuid,p_amount numeric,p_payment_method text,p_reference_number text default '',p_notes text default '',p_sale_id uuid default null,p_request_id text default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;
begin
  v_location:=private.v487_client_mobile_location(p_tenant_id,p_device_id);
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'sales.manage') and not private.erp_has_permission(p_tenant_id,'payments.receive') then raise exception 'Customer payment permission required';end if;
  return public.customer_receive_payment_v471(p_tenant_id,p_customer_id,p_amount,p_payment_method,p_reference_number,p_notes,p_sale_id,v_location,p_device_id,coalesce(nullif(trim(p_request_id),''),gen_random_uuid()::text));
end$$;
grant execute on function public.mobile_customer_payment_v487(uuid,uuid,uuid,numeric,text,text,text,uuid,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(164,'4.8.7','Client Mobile','Unified mobile approvals for generic approvals, Purchase Requests and Purchase Orders plus secure customer payment receipt.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.7 migration 164 mobile approvals/payments applied' as status;
