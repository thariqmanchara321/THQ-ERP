create or replace function public.restaurant_available_serials_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_variant_id uuid,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,
    p_location_id,
    p_device_id,
    'restaurant',
    'view'
  );

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'restaurant.order')
    or private.erp_has_permission(p_tenant_id,'restaurant.manage')
  ) then
    raise exception 'Restaurant order permission denied';
  end if;

  return jsonb_build_object(
    'serials',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'serial_id', s.id,
          'serial_number', s.serial_number,
          'variant_id', s.variant_id
        )
        order by s.serial_number
      )
      from (
        select x.*
        from public.inventory_serials_v483 x
        where x.tenant_id = p_tenant_id
          and x.variant_id = p_variant_id
          and x.current_location_id = p_location_id
          and x.status = 'in_stock'
          and x.reserved_transfer_id is null
        order by x.serial_number
        limit greatest(1, least(coalesce(p_limit,200),1000))
      ) s
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.restaurant_available_serials_v610(uuid,uuid,uuid,uuid,integer) from public;
grant execute on function public.restaurant_available_serials_v610(uuid,uuid,uuid,uuid,integer) to authenticated, service_role;
