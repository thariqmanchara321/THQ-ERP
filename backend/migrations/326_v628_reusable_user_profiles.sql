
begin;

create or replace function public.user_profile_link_tenant_v628(
  p_tenant_id uuid,
  p_user_id uuid,
  p_role_key text,
  p_location_ids uuid[] default '{}'::uuid[],
  p_access_level text default 'operate',
  p_client_enabled boolean default null,
  p_pos_enabled boolean default null,
  p_preserve_existing_role boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,auth,pg_temp
as $function$
declare
  v_membership public.tenant_memberships%rowtype;
  v_role public.roles%rowtype;
  v_membership_created boolean := false;
  v_role_assigned boolean := false;
  v_location_count integer := 0;
  v_requested_location_count integer := 0;
  v_username text;
  v_location_id uuid;
begin
  if p_tenant_id is null or p_user_id is null then
    raise exception 'Tenant and user are required';
  end if;

  if not exists(select 1 from public.tenants where id=p_tenant_id) then
    raise exception 'Business not found';
  end if;

  if not exists(select 1 from auth.users where id=p_user_id) then
    raise exception 'User profile not found';
  end if;

  select *
    into v_role
  from public.roles
  where tenant_id=p_tenant_id
    and key=trim(coalesce(p_role_key,''))
  limit 1;

  if not found then
    raise exception 'Selected role does not exist';
  end if;

  if coalesce(p_access_level,'') not in ('view','operate','manage') then
    raise exception 'Invalid location access level';
  end if;

  select username
    into v_username
  from public.user_login_names
  where user_id=p_user_id;

  select *
    into v_membership
  from public.tenant_memberships
  where tenant_id=p_tenant_id
    and user_id=p_user_id
  for update;

  if not found then
    insert into public.tenant_memberships(tenant_id,user_id,status)
    values(p_tenant_id,p_user_id,'active')
    returning * into v_membership;

    insert into public.user_roles(tenant_id,membership_id,role_id)
    values(p_tenant_id,v_membership.id,v_role.id)
    on conflict do nothing;

    v_membership_created := true;
    v_role_assigned := true;
  else
    if v_membership.status <> 'active' then
      update public.tenant_memberships
      set status='active'
      where id=v_membership.id
      returning * into v_membership;
    end if;

    if p_preserve_existing_role then
      if not exists(
        select 1
        from public.user_roles
        where tenant_id=p_tenant_id
          and membership_id=v_membership.id
      ) then
        insert into public.user_roles(tenant_id,membership_id,role_id)
        values(p_tenant_id,v_membership.id,v_role.id)
        on conflict do nothing;
        v_role_assigned := true;
      end if;
    else
      delete from public.user_roles
      where tenant_id=p_tenant_id
        and membership_id=v_membership.id;

      insert into public.user_roles(tenant_id,membership_id,role_id)
      values(p_tenant_id,v_membership.id,v_role.id)
      on conflict do nothing;
      v_role_assigned := true;
    end if;
  end if;

  if p_client_enabled is not null then
    insert into public.business_user_app_access(
      tenant_id,user_id,app_key,enabled,updated_at
    )
    values(
      p_tenant_id,p_user_id,'client',p_client_enabled,now()
    )
    on conflict(tenant_id,user_id,app_key)
    do update set
      enabled = case
        when v_membership_created then excluded.enabled
        else public.business_user_app_access.enabled or excluded.enabled
      end,
      updated_at=now();
  end if;

  if p_pos_enabled is not null then
    insert into public.business_user_app_access(
      tenant_id,user_id,app_key,enabled,updated_at
    )
    values(
      p_tenant_id,p_user_id,'pos',p_pos_enabled,now()
    )
    on conflict(tenant_id,user_id,app_key)
    do update set
      enabled = case
        when v_membership_created then excluded.enabled
        else public.business_user_app_access.enabled or excluded.enabled
      end,
      updated_at=now();
  end if;

  select count(distinct x)
    into v_requested_location_count
  from unnest(coalesce(p_location_ids,'{}'::uuid[])) as u(x);

  if v_requested_location_count > 0 then
    select count(*)
      into v_location_count
    from public.business_locations
    where tenant_id=p_tenant_id
      and active
      and id = any(p_location_ids);

    if v_location_count <> v_requested_location_count then
      raise exception 'One or more selected locations are invalid or inactive';
    end if;

    foreach v_location_id in array p_location_ids loop
      insert into public.business_user_location_access(
        tenant_id,user_id,location_id,access_level,updated_at
      )
      values(
        p_tenant_id,p_user_id,v_location_id,p_access_level,now()
      )
      on conflict(tenant_id,user_id,location_id)
      do update set
        access_level=excluded.access_level,
        updated_at=now();
    end loop;
  end if;

  perform private.business_audit_write_v471(
    p_tenant_id,
    'user.profile.link',
    'tenant_membership',
    v_membership.id,
    coalesce(v_username,p_user_id::text),
    null,
    jsonb_build_object(
      'user_id',p_user_id,
      'membership_created',v_membership_created,
      'role_key',v_role.key,
      'role_assigned',v_role_assigned,
      'locations_requested',v_requested_location_count,
      'access_level',p_access_level
    )
  );

  return jsonb_build_object(
    'success',true,
    'user_id',p_user_id,
    'username',v_username,
    'membership_id',v_membership.id,
    'membership_created',v_membership_created,
    'role_key',v_role.key,
    'role_assigned',v_role_assigned,
    'locations_linked',v_requested_location_count
  );
end
$function$;

revoke all on function public.user_profile_link_tenant_v628(
  uuid,uuid,text,uuid[],text,boolean,boolean,boolean
) from public,anon,authenticated;

grant execute on function public.user_profile_link_tenant_v628(
  uuid,uuid,text,uuid[],text,boolean,boolean,boolean
) to service_role;

insert into public.thq_schema_releases(
  migration_no,
  schema_version,
  release_name,
  notes
)
values(
  326,
  '6.2.8-reusable-user-profiles',
  'Reusable User Profiles Across Businesses and Locations',
  'Keeps username as one global login identity while allowing the same profile to be linked to multiple businesses and multiple locations. Existing passwords are preserved; location grants are additive.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;

