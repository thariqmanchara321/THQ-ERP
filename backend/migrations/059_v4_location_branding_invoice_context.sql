-- FLEXI ERP V4 location identity / invoice branding completion.
begin;

create or replace function public.tenant_business_location_save_v4(
  p_tenant_id uuid,p_location_id uuid,p_parent_location_id uuid,p_location_code text,p_name text,p_location_type text,
  p_phone text,p_email text,p_gstin text,p_address_line1 text,p_address_line2 text,p_city text,p_state text,p_postal_code text,
  p_country text,p_invoice_prefix text,p_logo_url text,p_active boolean
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare v_id uuid;v_settings jsonb;
begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'locations.manage') then raise exception 'Permission denied';end if;
  if trim(coalesce(p_location_code,''))='' then raise exception 'Location code required';end if;
  if trim(coalesce(p_name,''))='' then raise exception 'Location name required';end if;
  if p_parent_location_id is not null and not exists(select 1 from public.business_locations where id=p_parent_location_id and tenant_id=p_tenant_id) then raise exception 'Invalid parent location';end if;
  v_settings:=jsonb_build_object('logo_url',nullif(trim(coalesce(p_logo_url,'')),''));
  if p_location_id is null then
    insert into public.business_locations(
      tenant_id,parent_location_id,location_code,name,location_type,phone,email,gstin,address_line1,address_line2,city,state,postal_code,country,invoice_prefix,settings,active
    ) values(
      p_tenant_id,p_parent_location_id,upper(trim(p_location_code)),trim(p_name),p_location_type,
      nullif(trim(coalesce(p_phone,'')),''),nullif(trim(coalesce(p_email,'')),''),nullif(upper(trim(coalesce(p_gstin,''))),''),
      nullif(trim(coalesce(p_address_line1,'')),''),nullif(trim(coalesce(p_address_line2,'')),''),nullif(trim(coalesce(p_city,'')),''),
      nullif(trim(coalesce(p_state,'')),''),nullif(trim(coalesce(p_postal_code,'')),''),coalesce(nullif(trim(coalesce(p_country,'')),''),'India'),
      nullif(upper(trim(coalesce(p_invoice_prefix,''))),''),v_settings,coalesce(p_active,true)
    ) returning id into v_id;
  else
    if not private.erp_user_location_allowed(p_tenant_id,p_location_id,'manage') and not private.erp_user_is_owner(p_tenant_id) then raise exception 'Location manage access denied';end if;
    update public.business_locations set
      parent_location_id=p_parent_location_id,location_code=upper(trim(p_location_code)),name=trim(p_name),location_type=p_location_type,
      phone=nullif(trim(coalesce(p_phone,'')),''),email=nullif(trim(coalesce(p_email,'')),''),gstin=nullif(upper(trim(coalesce(p_gstin,''))),''),
      address_line1=nullif(trim(coalesce(p_address_line1,'')),''),address_line2=nullif(trim(coalesce(p_address_line2,'')),''),city=nullif(trim(coalesce(p_city,'')),''),
      state=nullif(trim(coalesce(p_state,'')),''),postal_code=nullif(trim(coalesce(p_postal_code,'')),''),country=coalesce(nullif(trim(coalesce(p_country,'')),''),'India'),
      invoice_prefix=nullif(upper(trim(coalesce(p_invoice_prefix,''))),''),
      settings=coalesce(public.business_locations.settings,'{}'::jsonb)||v_settings,
      active=coalesce(p_active,true),updated_at=now()
    where id=p_location_id and tenant_id=p_tenant_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'Location not found';end if;
  return v_id;
end $$;
grant execute on function public.tenant_business_location_save_v4(uuid,uuid,uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,text,boolean) to authenticated;

-- Enrich invoice context with location branding while retaining established origin numbering.
create or replace function public.document_origin_get(p_tenant_id uuid,p_entity_type text,p_entity_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v jsonb;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if exists(select 1 from public.document_origins o where o.tenant_id=p_tenant_id and o.entity_type=p_entity_type and o.entity_id=p_entity_id and not private.erp_user_location_allowed(p_tenant_id,o.location_id,'view')) then raise exception 'Location access denied';end if;
  select jsonb_build_object(
    'location_id',o.location_id,'location_name',l.name,'location_code',l.location_code,'location_tracking_code',l.tracking_code,
    'local_number',n.local_number,'terminal_number',dn.terminal_number,'invoice_number',coalesce(dn.terminal_number,n.local_number),
    'gstin',l.gstin,'phone',l.phone,'email',l.email,
    'address_line1',l.address_line1,'address_line2',l.address_line2,'city',l.city,'state',l.state,'postal_code',l.postal_code,'country',l.country,
    'location_settings',coalesce(l.settings,'{}'::jsonb),'location_logo_url',l.settings->>'logo_url',
    'device_id',o.device_id,'device_code',d.device_code,'device_name',d.name,'device_invoice_prefix',d.invoice_prefix,'created_at',o.created_at,
    'created_by',o.created_by
  ) into v
  from public.document_origins o
  left join public.business_locations l on l.id=o.location_id
  left join public.business_devices d on d.id=o.device_id
  left join public.location_document_numbers n on n.entity_type=o.entity_type and n.entity_id=o.entity_id
  left join public.device_document_numbers dn on dn.entity_type=o.entity_type and dn.entity_id=o.entity_id
  where o.tenant_id=p_tenant_id and o.entity_type=p_entity_type and o.entity_id=p_entity_id;
  return v;
end $$;
grant execute on function public.document_origin_get(uuid,text,uuid) to authenticated;

commit;
select 'Flexi ERP V4 location branding and invoice context ready' as status;
