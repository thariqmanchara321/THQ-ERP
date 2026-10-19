
create or replace function private.aggregate_direct_assert_manage_v621(
  p_tenant_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
begin
  perform private.aggregate_direct_assert_view_v621(p_tenant_id);

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'aggregate_yard.direct.manage')
  ) then
    raise exception 'Direct Supply manage permission required'
      using errcode='42501';
  end if;
end
$$;

revoke all
on function private.aggregate_direct_assert_manage_v621(uuid)
from public,anon,authenticated;

create or replace function private.erp_user_location_allowed(
  p_tenant_id uuid,
  p_location_id uuid,
  p_required text default 'view',
  p_user_id uuid default auth.uid()
)
returns boolean
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_level text;
  v_rank int;
  v_required int;
  v_operating_location_id uuid;
  v_required_norm text:=lower(coalesce(p_required,'view'));
begin
  select m.operating_location_id
  into v_operating_location_id
  from public.aggregate_direct_transit_locations_v621 m
  where m.tenant_id=p_tenant_id
    and m.transit_location_id=p_location_id;

  if v_operating_location_id is not null then
    if not exists(
      select 1
      from public.tenant_modules tm
      where tm.tenant_id=p_tenant_id
        and tm.module_key='aggregate_yard'
        and tm.enabled
    ) then
      return false;
    end if;

    if private.erp_user_is_owner(p_tenant_id,p_user_id) then
      return true;
    end if;

    if v_required_norm in('operate','manage') then
      if not private.erp_has_permission(
        p_tenant_id,'aggregate_yard.direct.manage',p_user_id
      ) then
        return false;
      end if;
    else
      if not (
        private.erp_has_permission(
          p_tenant_id,'aggregate_yard.direct.view',p_user_id
        )
        or private.erp_has_permission(
          p_tenant_id,'aggregate_yard.direct.manage',p_user_id
        )
      ) then
        return false;
      end if;
    end if;

    if private.erp_has_permission(
      p_tenant_id,'locations.manage_all',p_user_id
    ) then
      return true;
    end if;

    if v_required_norm='view'
       and private.erp_has_permission(
         p_tenant_id,'locations.view_all',p_user_id
       ) then
      return true;
    end if;

    p_location_id:=v_operating_location_id;
  end if;

  if private.erp_user_is_owner(p_tenant_id,p_user_id) then
    return true;
  end if;

  select access_level
  into v_level
  from public.business_user_location_access
  where tenant_id=p_tenant_id
    and user_id=p_user_id
    and location_id=p_location_id;

  if v_level is null then
    return false;
  end if;

  v_rank:=case v_level
    when 'manage' then 3
    when 'operate' then 2
    else 1
  end;

  v_required:=case v_required_norm
    when 'manage' then 3
    when 'operate' then 2
    else 1
  end;

  return v_rank>=v_required;
end
$$;

revoke all
on function private.erp_user_location_allowed(uuid,uuid,text,uuid)
from public,anon,authenticated;

create or replace function private.aggregate_direct_ensure_transit_v621(
  p_tenant_id uuid,
  p_operating_location_id uuid
)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_existing uuid;
  v_source public.business_locations%rowtype;
  v_transit_id uuid;
  v_suffix text;
  v_code text;
  v_prefix text;
begin
  select *
  into v_source
  from public.business_locations l
  where l.id=p_operating_location_id
    and l.tenant_id=p_tenant_id
    and l.active
  for update;

  if v_source.id is null then
    raise exception 'Operating location not found';
  end if;

  select m.transit_location_id
  into v_existing
  from public.aggregate_direct_transit_locations_v621 m
  where m.tenant_id=p_tenant_id
    and m.operating_location_id=p_operating_location_id;

  if v_existing is not null then
    update public.business_locations t
    set parent_location_id=v_source.id,
        name='Direct Supply Transit • '||v_source.name,
        location_type='warehouse',
        phone=v_source.phone,
        email=v_source.email,
        gstin=v_source.gstin,
        address_line1=v_source.address_line1,
        address_line2=v_source.address_line2,
        city=v_source.city,
        state=v_source.state,
        postal_code=v_source.postal_code,
        country=v_source.country,
        active=true,
        settings=coalesce(t.settings,'{}'::jsonb)
          || jsonb_build_object(
            'aggregate_virtual_transit',true,
            'system_managed',true,
            'operating_location_id',v_source.id,
            'operating_location_code',v_source.location_code
          ),
        hierarchy_role='operational',
        sort_order=9999,
        updated_at=now()
    where t.id=v_existing
      and t.tenant_id=p_tenant_id;

    if not found then
      raise exception 'Mapped Direct Supply transit location is missing';
    end if;

    return v_existing;
  end if;

  if exists(
    select 1
    from public.aggregate_direct_transit_locations_v621 m
    where m.tenant_id=p_tenant_id
      and m.transit_location_id=p_operating_location_id
  ) then
    raise exception 'A transit location cannot be used as the operating location';
  end if;

  v_suffix:=upper(substr(replace(p_operating_location_id::text,'-',''),1,8));
  v_code:='AGGDST-'||v_suffix;
  v_prefix:='DST'||substr(v_suffix,1,6);

  if exists(
    select 1
    from public.business_locations l
    where l.tenant_id=p_tenant_id
      and upper(l.location_code)=upper(v_code)
  ) then
    raise exception
      'Reserved Direct Supply transit code % is already in use',
      v_code;
  end if;

  insert into public.business_locations(
    tenant_id,parent_location_id,location_code,tracking_code,name,
    location_type,phone,email,gstin,address_line1,address_line2,
    city,state,postal_code,country,invoice_prefix,active,settings,
    hierarchy_role,sort_order
  )
  values(
    p_tenant_id,v_source.id,v_code,null,
    'Direct Supply Transit • '||v_source.name,
    'warehouse',v_source.phone,v_source.email,v_source.gstin,
    v_source.address_line1,v_source.address_line2,v_source.city,
    v_source.state,v_source.postal_code,v_source.country,v_prefix,
    true,
    jsonb_build_object(
      'aggregate_virtual_transit',true,
      'system_managed',true,
      'operating_location_id',v_source.id,
      'operating_location_code',v_source.location_code
    ),
    'operational',9999
  )
  returning id into v_transit_id;

  insert into public.aggregate_direct_transit_locations_v621(
    tenant_id,operating_location_id,transit_location_id,created_by
  )
  values(
    p_tenant_id,v_source.id,v_transit_id,auth.uid()
  );

  return v_transit_id;
end
$$;

revoke all
on function private.aggregate_direct_ensure_transit_v621(uuid,uuid)
from public,anon,authenticated;

insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  312,
  '6.2.1-aggregate-direct-access-safety',
  'Aggregate Direct Supply Access Safety',
  'Makes Direct Supply management require the dedicated permission, bridges hidden transit-location access back to the authorized operating location for Purchase/Sale document origin checks, and self-heals the system transit location legal/address fields on use. Existing non-transit location authorization behavior is unchanged.'
);;
