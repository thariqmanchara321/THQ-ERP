alter table public.restaurant_tables
  add column if not exists width_percent numeric not null default 14,
  add column if not exists height_percent numeric not null default 12,
  add column if not exists rotation_degrees numeric not null default 0,
  add column if not exists layout_locked boolean not null default false,
  add column if not exists layout_note text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.restaurant_tables'::regclass
      and conname='restaurant_tables_width_percent_check'
  ) then
    alter table public.restaurant_tables
      add constraint restaurant_tables_width_percent_check
      check (width_percent between 4 and 40);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.restaurant_tables'::regclass
      and conname='restaurant_tables_height_percent_check'
  ) then
    alter table public.restaurant_tables
      add constraint restaurant_tables_height_percent_check
      check (height_percent between 4 and 40);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.restaurant_tables'::regclass
      and conname='restaurant_tables_rotation_degrees_check'
  ) then
    alter table public.restaurant_tables
      add constraint restaurant_tables_rotation_degrees_check
      check (rotation_degrees >= 0 and rotation_degrees < 360);
  end if;
end
$$;

create or replace function public.restaurant_table_save_advanced_v610(
  p_tenant_id uuid,
  p_table_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_table_code text,
  p_name text,
  p_capacity integer,
  p_area text,
  p_floor_name text,
  p_operational_status text,
  p_shape text,
  p_position_x numeric,
  p_position_y numeric,
  p_width_percent numeric,
  p_height_percent numeric,
  p_rotation_degrees numeric,
  p_layout_locked boolean,
  p_layout_note text
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_id uuid;
  v_old public.restaurant_tables%rowtype;
  v_row public.restaurant_tables%rowtype;
  v_code text:=upper(trim(coalesce(p_table_code,'')));
  v_name text:=trim(coalesce(p_name,''));
  v_status text:=lower(trim(coalesce(p_operational_status,'available')));
  v_shape text:=lower(trim(coalesce(p_shape,'rect')));
  v_rotation numeric:=mod(mod(coalesce(p_rotation_degrees,0),360)+360,360);
begin
  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,p_location_id,p_device_id,'restaurant','operate'
  );

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'restaurant.manage')
  ) then
    raise exception 'Restaurant manage permission denied';
  end if;

  if v_code='' then raise exception 'Table code is required'; end if;
  if v_name='' then raise exception 'Table name is required'; end if;
  if coalesce(p_capacity,0)<=0 then
    raise exception 'Table capacity must be greater than zero';
  end if;
  if v_status not in ('available','reserved','cleaning','out_of_service') then
    raise exception 'Invalid restaurant table status %',v_status;
  end if;
  if v_shape not in ('rect','round','square') then
    raise exception 'Invalid restaurant table shape %',v_shape;
  end if;
  if p_position_x is not null and (p_position_x<0 or p_position_x>100) then
    raise exception 'Table position_x must be between 0 and 100';
  end if;
  if p_position_y is not null and (p_position_y<0 or p_position_y>100) then
    raise exception 'Table position_y must be between 0 and 100';
  end if;
  if coalesce(p_width_percent,14)<4 or coalesce(p_width_percent,14)>40 then
    raise exception 'Table width must be between 4 and 40 percent';
  end if;
  if coalesce(p_height_percent,12)<4 or coalesce(p_height_percent,12)>40 then
    raise exception 'Table height must be between 4 and 40 percent';
  end if;

  if p_table_id is null then
    insert into public.restaurant_tables(
      tenant_id,location_id,table_code,name,capacity,area,active,
      operational_status,floor_name,position_x,position_y,shape,
      width_percent,height_percent,rotation_degrees,layout_locked,layout_note
    ) values(
      p_tenant_id,p_location_id,v_code,v_name,p_capacity,
      nullif(trim(coalesce(p_area,'')),''),true,v_status,
      nullif(trim(coalesce(p_floor_name,'')),''),p_position_x,p_position_y,v_shape,
      coalesce(p_width_percent,14),coalesce(p_height_percent,12),v_rotation,
      coalesce(p_layout_locked,false),
      nullif(trim(coalesce(p_layout_note,'')),'')
    ) returning id into v_id;
  else
    select * into v_old
    from public.restaurant_tables
    where id=p_table_id and tenant_id=p_tenant_id
    for update;

    if not found then raise exception 'Restaurant table not found'; end if;

    if v_old.location_id is distinct from p_location_id then
      raise exception
        'Restaurant table cannot be moved between locations from the floor editor';
    end if;

    if v_status='out_of_service' and exists(
      select 1
      from public.restaurant_orders o
      where o.tenant_id=p_tenant_id
        and o.table_id=p_table_id
        and o.status not in ('billed','cancelled')
        and o.sale_id is null
    ) then
      raise exception
        'Table has a live order and cannot be marked out of service';
    end if;

    update public.restaurant_tables
    set table_code=v_code,
        name=v_name,
        capacity=p_capacity,
        area=nullif(trim(coalesce(p_area,'')),''),
        floor_name=nullif(trim(coalesce(p_floor_name,'')),''),
        operational_status=v_status,
        shape=v_shape,
        position_x=p_position_x,
        position_y=p_position_y,
        width_percent=coalesce(p_width_percent,width_percent),
        height_percent=coalesce(p_height_percent,height_percent),
        rotation_degrees=v_rotation,
        layout_locked=coalesce(p_layout_locked,false),
        layout_note=nullif(trim(coalesce(p_layout_note,'')),''),
        updated_at=now()
    where id=p_table_id and tenant_id=p_tenant_id
    returning id into v_id;
  end if;

  select * into v_row
  from public.restaurant_tables
  where id=v_id;

  insert into public.restaurant_table_events(
    tenant_id,order_id,from_table_id,to_table_id,event_type,note,created_by
  ) values(
    p_tenant_id,null,v_id,v_id,'state',
    case when p_table_id is null then 'Table created' else 'Table edited' end ||
      ' | code='||v_row.table_code||
      ' | name='||v_row.name||
      ' | capacity='||v_row.capacity||
      ' | floor='||coalesce(v_row.floor_name,'')||
      ' | shape='||v_row.shape||
      ' | size='||v_row.width_percent||'x'||v_row.height_percent||
      ' | rotation='||v_row.rotation_degrees||
      ' | locked='||v_row.layout_locked,
    auth.uid()
  );

  perform private.thq_sync_bump_v480(
    p_tenant_id,'configuration','restaurant_table',v_id::text,
    case when p_table_id is null
      then 'create_advanced'
      else 'edit_advanced'
    end
  );

  return jsonb_build_object(
    'success',true,
    'table',to_jsonb(v_row),
    'restaurant_engine','v6.1'
  );
end;
$$;

create or replace function public.restaurant_table_deactivate_v610(
  p_tenant_id uuid,
  p_table_id uuid,
  p_device_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  t public.restaurant_tables%rowtype;
  v_reason text:=nullif(trim(coalesce(p_reason,'')),'');
begin
  select * into t
  from public.restaurant_tables
  where id=p_table_id and tenant_id=p_tenant_id
  for update;

  if not found then raise exception 'Restaurant table not found'; end if;

  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,t.location_id,p_device_id,'restaurant','operate'
  );

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'restaurant.manage')
  ) then
    raise exception 'Restaurant manage permission denied';
  end if;

  if not t.active then
    return jsonb_build_object(
      'success',true,'idempotent',true,'table_id',t.id,'active',false
    );
  end if;

  if exists(
    select 1
    from public.restaurant_orders o
    where o.tenant_id=p_tenant_id
      and o.table_id=t.id
      and o.status not in ('billed','cancelled')
      and o.sale_id is null
  ) then
    raise exception
      'Table has a live order. Bill, cancel, transfer, split, or merge the order before deleting the table.';
  end if;

  if t.reservation_at is not null then
    raise exception
      'Table has an active reservation. Clear or move the reservation before deleting the table.';
  end if;

  if exists(
    select 1
    from public.restaurant_waitlist w
    where w.tenant_id=p_tenant_id
      and w.table_id=t.id
      and w.status in ('waiting','notified','seated')
  ) then
    raise exception
      'Table is linked to an active waitlist entry. Reassign or close it before deleting the table.';
  end if;

  update public.restaurant_tables
  set active=false,
      operational_status='out_of_service',
      updated_at=now()
  where id=t.id and tenant_id=p_tenant_id;

  insert into public.restaurant_table_events(
    tenant_id,order_id,from_table_id,to_table_id,event_type,note,created_by
  ) values(
    p_tenant_id,null,t.id,t.id,'state',
    'Table deactivated (soft delete)' ||
      case when v_reason is null then '' else ' | '||v_reason end,
    auth.uid()
  );

  perform private.thq_sync_bump_v480(
    p_tenant_id,'configuration','restaurant_table',t.id::text,'deactivate'
  );

  return jsonb_build_object(
    'success',true,
    'table_id',t.id,
    'table_code',t.table_code,
    'active',false,
    'soft_deleted',true,
    'history_preserved',true
  );
end;
$$;

create or replace function public.restaurant_table_reactivate_v610(
  p_tenant_id uuid,
  p_table_id uuid,
  p_device_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  t public.restaurant_tables%rowtype;
begin
  select * into t
  from public.restaurant_tables
  where id=p_table_id and tenant_id=p_tenant_id
  for update;

  if not found then raise exception 'Restaurant table not found'; end if;

  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,t.location_id,p_device_id,'restaurant','operate'
  );

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'restaurant.manage')
  ) then
    raise exception 'Restaurant manage permission denied';
  end if;

  update public.restaurant_tables
  set active=true,
      operational_status='available',
      updated_at=now()
  where id=t.id and tenant_id=p_tenant_id;

  insert into public.restaurant_table_events(
    tenant_id,order_id,from_table_id,to_table_id,event_type,note,created_by
  ) values(
    p_tenant_id,null,t.id,t.id,'state','Table reactivated',auth.uid()
  );

  perform private.thq_sync_bump_v480(
    p_tenant_id,'configuration','restaurant_table',t.id::text,'reactivate'
  );

  return jsonb_build_object(
    'success',true,'table_id',t.id,'active',true
  );
end;
$$;

create or replace function public.restaurant_table_duplicate_v610(
  p_tenant_id uuid,
  p_table_id uuid,
  p_device_id uuid,
  p_new_table_code text,
  p_new_name text
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  t public.restaurant_tables%rowtype;
  v_new public.restaurant_tables%rowtype;
begin
  select * into t
  from public.restaurant_tables
  where id=p_table_id and tenant_id=p_tenant_id;

  if not found then raise exception 'Restaurant table not found'; end if;

  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,t.location_id,p_device_id,'restaurant','operate'
  );

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'restaurant.manage')
  ) then
    raise exception 'Restaurant manage permission denied';
  end if;

  if trim(coalesce(p_new_table_code,''))='' or
     trim(coalesce(p_new_name,''))='' then
    raise exception 'New table code and name are required';
  end if;

  insert into public.restaurant_tables(
    tenant_id,location_id,table_code,name,capacity,area,active,
    operational_status,floor_name,position_x,position_y,shape,sort_order,
    width_percent,height_percent,rotation_degrees,layout_locked,layout_note
  ) values(
    p_tenant_id,t.location_id,
    upper(trim(p_new_table_code)),trim(p_new_name),
    t.capacity,t.area,true,'available',t.floor_name,
    least(coalesce(t.position_x,0)+3,100),
    least(coalesce(t.position_y,0)+3,100),
    t.shape,t.sort_order+1,t.width_percent,t.height_percent,
    t.rotation_degrees,false,t.layout_note
  ) returning * into v_new;

  insert into public.restaurant_table_events(
    tenant_id,order_id,from_table_id,to_table_id,event_type,note,created_by
  ) values(
    p_tenant_id,null,t.id,v_new.id,'state',
    'Table duplicated from '||t.table_code||' to '||v_new.table_code,
    auth.uid()
  );

  perform private.thq_sync_bump_v480(
    p_tenant_id,'configuration','restaurant_table',
    v_new.id::text,'duplicate'
  );

  return jsonb_build_object(
    'success',true,'table',to_jsonb(v_new)
  );
end;
$$;

create or replace function public.restaurant_table_layout_batch_set_advanced_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_tables jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  x jsonb;
  t public.restaurant_tables%rowtype;
  v_count integer:=0;
  v_seen uuid[]:=array[]::uuid[];
  v_id uuid;
  v_x numeric;
  v_y numeric;
  v_w numeric;
  v_h numeric;
  v_rot numeric;
  v_shape text;
  v_floor text;
  v_sort integer;
  v_locked boolean;
begin
  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,p_location_id,p_device_id,'restaurant','operate'
  );

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'restaurant.manage')
  ) then
    raise exception 'Restaurant manage permission denied';
  end if;

  if jsonb_typeof(coalesce(p_tables,'[]'::jsonb))<>'array' then
    raise exception 'Restaurant table layout payload must be an array';
  end if;

  if jsonb_array_length(coalesce(p_tables,'[]'::jsonb))=0 then
    raise exception 'Choose at least one restaurant table to update';
  end if;

  if jsonb_array_length(p_tables)>500 then
    raise exception 'Restaurant table layout batch cannot exceed 500 tables';
  end if;

  for x in select value from jsonb_array_elements(p_tables) loop
    v_id:=nullif(x->>'table_id','')::uuid;
    if v_id is null then
      raise exception 'Each layout row requires table_id';
    end if;

    if v_id=any(v_seen) then
      raise exception 'Restaurant table % was supplied more than once',v_id;
    end if;
    v_seen:=array_append(v_seen,v_id);

    select * into t
    from public.restaurant_tables
    where id=v_id
      and tenant_id=p_tenant_id
      and location_id=p_location_id
    for update;

    if not found then
      raise exception
        'Restaurant table % was not found in this location',v_id;
    end if;

    v_x:=case
      when x?'position_x' then nullif(x->>'position_x','')::numeric
      else t.position_x
    end;
    v_y:=case
      when x?'position_y' then nullif(x->>'position_y','')::numeric
      else t.position_y
    end;
    v_w:=case
      when x?'width_percent'
        then coalesce(nullif(x->>'width_percent','')::numeric,t.width_percent)
      else t.width_percent
    end;
    v_h:=case
      when x?'height_percent'
        then coalesce(nullif(x->>'height_percent','')::numeric,t.height_percent)
      else t.height_percent
    end;
    v_rot:=case
      when x?'rotation_degrees'
        then mod(
          mod(
            coalesce(
              nullif(x->>'rotation_degrees','')::numeric,
              t.rotation_degrees
            ),
            360
          )+360,
          360
        )
      else t.rotation_degrees
    end;
    v_shape:=case
      when x?'shape'
        then lower(trim(coalesce(nullif(x->>'shape',''),t.shape)))
      else t.shape
    end;
    v_floor:=case
      when x?'floor_name'
        then nullif(trim(coalesce(x->>'floor_name','')),'')
      else t.floor_name
    end;
    v_sort:=case
      when x?'sort_order'
        then coalesce(nullif(x->>'sort_order','')::integer,t.sort_order)
      else t.sort_order
    end;
    v_locked:=case
      when x?'layout_locked'
        then coalesce((x->>'layout_locked')::boolean,t.layout_locked)
      else t.layout_locked
    end;

    if v_x is not null and (v_x<0 or v_x>100) then
      raise exception 'Table position_x must be between 0 and 100';
    end if;
    if v_y is not null and (v_y<0 or v_y>100) then
      raise exception 'Table position_y must be between 0 and 100';
    end if;
    if v_w<4 or v_w>40 then
      raise exception 'Table width must be between 4 and 40 percent';
    end if;
    if v_h<4 or v_h>40 then
      raise exception 'Table height must be between 4 and 40 percent';
    end if;
    if v_shape not in ('rect','round','square') then
      raise exception 'Invalid restaurant table shape %',v_shape;
    end if;

    update public.restaurant_tables
    set floor_name=v_floor,
        position_x=v_x,
        position_y=v_y,
        shape=v_shape,
        sort_order=v_sort,
        width_percent=v_w,
        height_percent=v_h,
        rotation_degrees=v_rot,
        layout_locked=v_locked,
        updated_at=now()
    where id=v_id and tenant_id=p_tenant_id;

    insert into public.restaurant_table_events(
      tenant_id,order_id,from_table_id,to_table_id,event_type,note,created_by
    ) values(
      p_tenant_id,null,v_id,v_id,'state',
      'Advanced layout updated | floor='||coalesce(v_floor,'')||
      ' | x='||coalesce(v_x::text,'')||
      ' | y='||coalesce(v_y::text,'')||
      ' | size='||v_w||'x'||v_h||
      ' | rotation='||v_rot||
      ' | shape='||v_shape||
      ' | locked='||v_locked,
      auth.uid()
    );

    perform private.thq_sync_bump_v480(
      p_tenant_id,'configuration','restaurant_table',
      v_id::text,'layout_advanced'
    );

    v_count:=v_count+1;
  end loop;

  return jsonb_build_object(
    'success',true,
    'updated_count',v_count,
    'position_scale','percent_0_100',
    'restaurant_engine','v6.1'
  );
end;
$$;

revoke all on function public.restaurant_table_save_advanced_v610(
  uuid,uuid,uuid,uuid,text,text,integer,text,text,text,text,
  numeric,numeric,numeric,numeric,numeric,boolean,text
) from public;
grant execute on function public.restaurant_table_save_advanced_v610(
  uuid,uuid,uuid,uuid,text,text,integer,text,text,text,text,
  numeric,numeric,numeric,numeric,numeric,boolean,text
) to authenticated,service_role;

revoke all on function public.restaurant_table_deactivate_v610(
  uuid,uuid,uuid,text
) from public;
grant execute on function public.restaurant_table_deactivate_v610(
  uuid,uuid,uuid,text
) to authenticated,service_role;

revoke all on function public.restaurant_table_reactivate_v610(
  uuid,uuid,uuid
) from public;
grant execute on function public.restaurant_table_reactivate_v610(
  uuid,uuid,uuid
) to authenticated,service_role;

revoke all on function public.restaurant_table_duplicate_v610(
  uuid,uuid,uuid,text,text
) from public;
grant execute on function public.restaurant_table_duplicate_v610(
  uuid,uuid,uuid,text,text
) to authenticated,service_role;

revoke all on function public.restaurant_table_layout_batch_set_advanced_v610(
  uuid,uuid,uuid,jsonb
) from public;
grant execute on function public.restaurant_table_layout_batch_set_advanced_v610(
  uuid,uuid,uuid,jsonb
) to authenticated,service_role;
