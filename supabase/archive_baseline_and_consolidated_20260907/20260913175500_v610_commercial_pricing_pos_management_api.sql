-- THQ ERP v6.1 POS-safe commercial charge management API.
create or replace function public.sales_charge_catalog_put_pos_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_charge_id uuid,
  p_code text,
  p_name text,
  p_charge_kind text,
  p_service_variant_id uuid,
  p_default_quantity numeric,
  p_auto_dine_in boolean,
  p_auto_takeaway boolean,
  p_auto_delivery boolean,
  p_active boolean
)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_id uuid;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  perform private.erp_validate_transaction_origin(
    p_tenant_id,p_location_id,p_device_id,'sales'
  );
  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'sales.manage')
    or private.erp_has_permission(p_tenant_id,'restaurant.manage')
  ) then
    raise exception 'Manage permission required';
  end if;

  perform private.sales_charge_catalog_assert_v610(
    p_tenant_id,p_service_variant_id
  );

  if p_charge_id is null then
    insert into public.sales_charge_catalog_v610(
      tenant_id,code,name,charge_kind,service_variant_id,default_quantity,
      auto_apply_dine_in,auto_apply_takeaway,auto_apply_delivery,active
    ) values (
      p_tenant_id,upper(trim(p_code)),trim(p_name),
      lower(trim(p_charge_kind)),p_service_variant_id,p_default_quantity,
      coalesce(p_auto_dine_in,false),coalesce(p_auto_takeaway,false),
      coalesce(p_auto_delivery,false),coalesce(p_active,true)
    ) returning id into v_id;
  else
    update public.sales_charge_catalog_v610
    set code=upper(trim(p_code)),
        name=trim(p_name),
        charge_kind=lower(trim(p_charge_kind)),
        service_variant_id=p_service_variant_id,
        default_quantity=p_default_quantity,
        auto_apply_dine_in=coalesce(p_auto_dine_in,false),
        auto_apply_takeaway=coalesce(p_auto_takeaway,false),
        auto_apply_delivery=coalesce(p_auto_delivery,false),
        active=coalesce(p_active,true),
        updated_at=now()
    where id=p_charge_id and tenant_id=p_tenant_id
    returning id into v_id;
  end if;

  if v_id is null then raise exception 'Commercial charge not found'; end if;
  return v_id;
end;
$$;

create or replace function public.product_charge_rule_put_pos_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_rule_id uuid,
  p_product_variant_id uuid,
  p_charge_catalog_id uuid,
  p_order_type text,
  p_quantity_mode text,
  p_quantity_value numeric,
  p_active boolean
)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_id uuid;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  perform private.erp_validate_transaction_origin(
    p_tenant_id,p_location_id,p_device_id,'sales'
  );
  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'sales.manage')
    or private.erp_has_permission(p_tenant_id,'restaurant.manage')
  ) then
    raise exception 'Manage permission required';
  end if;

  if not exists (
    select 1 from public.product_variants
    where id=p_product_variant_id
      and tenant_id=p_tenant_id
      and status='active'
  ) then
    raise exception 'Product variant not found';
  end if;

  if not exists (
    select 1 from public.sales_charge_catalog_v610
    where id=p_charge_catalog_id
      and tenant_id=p_tenant_id
      and active
  ) then
    raise exception 'Commercial charge not found';
  end if;

  if p_rule_id is null then
    insert into public.product_charge_rules_v610(
      tenant_id,product_variant_id,charge_catalog_id,
      order_type,quantity_mode,quantity_value,active
    ) values (
      p_tenant_id,p_product_variant_id,p_charge_catalog_id,
      lower(trim(p_order_type)),lower(trim(p_quantity_mode)),
      p_quantity_value,coalesce(p_active,true)
    ) returning id into v_id;
  else
    update public.product_charge_rules_v610
    set product_variant_id=p_product_variant_id,
        charge_catalog_id=p_charge_catalog_id,
        order_type=lower(trim(p_order_type)),
        quantity_mode=lower(trim(p_quantity_mode)),
        quantity_value=p_quantity_value,
        active=coalesce(p_active,true),
        updated_at=now()
    where id=p_rule_id and tenant_id=p_tenant_id
    returning id into v_id;
  end if;

  if v_id is null then raise exception 'Product charge rule not found'; end if;
  return v_id;
end;
$$;

create or replace function public.product_charge_rules_list_pos_v610(
  p_tenant_id uuid,
  p_product_variant_id uuid,
  p_location_id uuid,
  p_device_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare v_rows jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  perform private.erp_validate_transaction_origin(
    p_tenant_id,p_location_id,p_device_id,'sales'
  );

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',r.id,
      'product_variant_id',r.product_variant_id,
      'charge_catalog_id',r.charge_catalog_id,
      'order_type',r.order_type,
      'quantity_mode',r.quantity_mode,
      'quantity_value',r.quantity_value,
      'active',r.active,
      'charge_code',c.code,
      'charge_name',c.name,
      'charge_kind',c.charge_kind,
      'service_variant_id',c.service_variant_id
    ) order by c.name,r.order_type
  ),'[]'::jsonb)
  into v_rows
  from public.product_charge_rules_v610 r
  join public.sales_charge_catalog_v610 c
    on c.id=r.charge_catalog_id and c.tenant_id=r.tenant_id
  where r.tenant_id=p_tenant_id
    and r.product_variant_id=p_product_variant_id;

  return jsonb_build_object('rules',v_rows);
end;
$$;

revoke all on function public.sales_charge_catalog_put_pos_v610(
  uuid,uuid,uuid,uuid,text,text,text,uuid,numeric,boolean,boolean,boolean,boolean
) from public;
grant execute on function public.sales_charge_catalog_put_pos_v610(
  uuid,uuid,uuid,uuid,text,text,text,uuid,numeric,boolean,boolean,boolean,boolean
) to authenticated,service_role;

revoke all on function public.product_charge_rule_put_pos_v610(
  uuid,uuid,uuid,uuid,uuid,uuid,text,text,numeric,boolean
) from public;
grant execute on function public.product_charge_rule_put_pos_v610(
  uuid,uuid,uuid,uuid,uuid,uuid,text,text,numeric,boolean
) to authenticated,service_role;

revoke all on function public.product_charge_rules_list_pos_v610(
  uuid,uuid,uuid,uuid
) from public;
grant execute on function public.product_charge_rules_list_pos_v610(
  uuid,uuid,uuid,uuid
) to authenticated,service_role;
