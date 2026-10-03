create or replace function private.gst_party_profile_upsert_core_v621(
  p_tenant_id uuid,
  p_id uuid,
  p_party_type text,
  p_party_id uuid,
  p_registration_type text,
  p_gstin text,
  p_legal_name text,
  p_trade_name text,
  p_state_code text,
  p_place_of_supply_code text,
  p_address_line1 text,
  p_address_line2 text,
  p_city text,
  p_postal_code text,
  p_country text,
  p_active boolean
)
returns uuid
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_id uuid;
  v_type text:=lower(trim(coalesce(p_party_type,'')));
  v_regtype text:=lower(trim(coalesce(p_registration_type,'unregistered')));
  v_gstin text:=nullif(upper(regexp_replace(coalesce(p_gstin,''),'\s','','g')),'');
  v_valid jsonb;
  v_state text:=nullif(trim(coalesce(p_state_code,'')),'');
  v_pos text:=nullif(trim(coalesce(p_place_of_supply_code,'')),'');
  v_before jsonb;
  v_status text;
  v_date date:=current_date;
  v_current public.gst_party_registrations_v520%rowtype;
begin
  if v_type not in('customer','supplier') then
    raise exception 'Party type must be customer or supplier';
  end if;
  if v_regtype not in(
    'registered','unregistered','composition','sez','export','exempt'
  ) then
    raise exception 'Invalid GST party registration type';
  end if;
  if v_type='customer' and not exists(
    select 1 from public.customers
    where id=p_party_id and tenant_id=p_tenant_id
  ) then
    raise exception 'Customer not found';
  end if;
  if v_type='supplier' and not exists(
    select 1 from public.suppliers
    where id=p_party_id and tenant_id=p_tenant_id
  ) then
    raise exception 'Supplier not found';
  end if;

  if v_regtype in('registered','composition','sez') then
    if v_gstin is null then
      raise exception 'GSTIN is required for this registration type';
    end if;
    v_valid:=public.gst_gstin_validate_v520(v_gstin);
    if not coalesce((v_valid->>'structurally_valid')::boolean,false) then
      raise exception 'GSTIN failed structural/checksum validation';
    end if;
    if v_state is null then v_state:=v_valid->>'state_code'; end if;
    if v_state is distinct from(v_valid->>'state_code') then
      raise exception 'Party GSTIN state and selected state differ';
    end if;
    v_pos:=coalesce(v_pos,v_state);
    v_status:='local_validated';
  elsif v_regtype='export' then
    v_gstin:=null;
    v_state:='96';
    v_pos:='96';
    v_status:='not_applicable';
  else
    v_gstin:=null;
    v_pos:=coalesce(v_pos,v_state);
    v_status:='not_applicable';
  end if;

  if v_state is not null and not exists(
    select 1 from public.gst_state_master_v520 s
    where s.code=v_state and s.active
  ) then
    raise exception 'Party GST state code is invalid';
  end if;
  if v_pos is not null and not exists(
    select 1 from public.gst_state_master_v520 s
    where s.code=v_pos and s.active
  ) then
    raise exception 'Party Place of Supply code is invalid';
  end if;

  select * into v_current
  from public.gst_party_registrations_v520
  where tenant_id=p_tenant_id
    and party_type=v_type
    and party_id=p_party_id
    and effective_to is null
    and is_default
  for update;

  if p_id is not null and (v_current.id is null or v_current.id<>p_id) then
    raise exception 'Only the current GST party profile can be changed';
  end if;
  if v_current.id is not null then v_before:=to_jsonb(v_current); end if;

  if v_current.id is not null and v_current.effective_from=v_date then
    v_id:=v_current.id;
    update public.gst_party_registrations_v520
    set registration_type=v_regtype,
        gstin=v_gstin,
        pan=case when v_gstin is null then null else substring(v_gstin,3,10) end,
        legal_name=nullif(trim(coalesce(p_legal_name,'')),''),
        trade_name=nullif(trim(coalesce(p_trade_name,'')),''),
        state_code=v_state,
        place_of_supply_code=v_pos,
        address_line1=nullif(trim(coalesce(p_address_line1,'')),''),
        address_line2=nullif(trim(coalesce(p_address_line2,'')),''),
        city=nullif(trim(coalesce(p_city,'')),''),
        postal_code=nullif(trim(coalesce(p_postal_code,'')),''),
        country=coalesce(nullif(trim(coalesce(p_country,'')),''),'India'),
        is_default=true,
        validation_status=v_status,
        active=coalesce(p_active,true),
        updated_by=auth.uid(),
        updated_at=now()
    where id=v_id;
  else
    if v_current.id is not null then
      update public.gst_party_registrations_v520
      set effective_to=v_date-1,
          is_default=false,
          updated_by=auth.uid(),
          updated_at=now()
      where id=v_current.id;
    end if;
    v_id:=gen_random_uuid();
    insert into public.gst_party_registrations_v520(
      id,tenant_id,party_type,party_id,registration_type,gstin,pan,
      legal_name,trade_name,state_code,place_of_supply_code,
      address_line1,address_line2,city,postal_code,country,
      is_default,validation_status,active,effective_from,
      created_by,updated_by
    )
    values(
      v_id,p_tenant_id,v_type,p_party_id,v_regtype,v_gstin,
      case when v_gstin is null then null else substring(v_gstin,3,10) end,
      nullif(trim(coalesce(p_legal_name,'')),''),
      nullif(trim(coalesce(p_trade_name,'')),''),
      v_state,v_pos,
      nullif(trim(coalesce(p_address_line1,'')),''),
      nullif(trim(coalesce(p_address_line2,'')),''),
      nullif(trim(coalesce(p_city,'')),''),
      nullif(trim(coalesce(p_postal_code,'')),''),
      coalesce(nullif(trim(coalesce(p_country,'')),''),'India'),
      true,v_status,coalesce(p_active,true),v_date,
      auth.uid(),auth.uid()
    );
  end if;

  perform private.business_audit_write_v471(
    p_tenant_id,'gst.party_profile.save','gst_party_registration',
    v_id,coalesce(v_gstin,p_party_id::text),v_before,
    (select to_jsonb(g) from public.gst_party_registrations_v520 g where g.id=v_id)
  );
  return v_id;
end;
$function$;

revoke all on function private.gst_party_profile_upsert_core_v621(
  uuid,uuid,text,uuid,text,text,text,text,text,text,text,text,text,text,text,boolean
) from public,anon,authenticated;

create or replace function public.gst_party_profile_save_v520(
  p_tenant_id uuid,p_id uuid,p_party_type text,p_party_id uuid,
  p_registration_type text,p_gstin text,p_legal_name text,p_trade_name text,
  p_state_code text,p_place_of_supply_code text,p_address_line1 text,
  p_address_line2 text,p_city text,p_postal_code text,p_country text,
  p_active boolean
)
returns uuid
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.manage') then
    raise exception 'GST manage permission required';
  end if;
  return private.gst_party_profile_upsert_core_v621(
    p_tenant_id,p_id,p_party_type,p_party_id,p_registration_type,
    p_gstin,p_legal_name,p_trade_name,p_state_code,p_place_of_supply_code,
    p_address_line1,p_address_line2,p_city,p_postal_code,p_country,p_active
  );
end;
$function$;

create or replace function public.customer_master_save_v621(
  p_tenant_id uuid,p_customer_id uuid,p_name text,p_contact_person text,
  p_phone text,p_email text,p_address_line1 text,p_address_line2 text,
  p_city text,p_state text,p_postal_code text,p_country text,
  p_credit_limit numeric,p_notes text,p_status text,
  p_gst_registration_type text,p_gstin text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_id uuid:=p_customer_id;
  v_profile_id uuid;
  v_regtype text:=lower(trim(coalesce(p_gst_registration_type,'unregistered')));
  v_gstin text:=nullif(upper(regexp_replace(coalesce(p_gstin,''),'\s','','g')),'');
  v_valid jsonb;
  v_state_code text;
  v_input_state_code text;
  v_state_name text:=nullif(trim(coalesce(p_state,'')),'');
  v_country text:=coalesce(nullif(trim(coalesce(p_country,'')),''),'India');
  v_tax_number text;
  v_validation_status text;
begin
  if not private.has_permission(p_tenant_id,'customers.manage') then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if v_regtype not in(
    'registered','unregistered','composition','sez','export','exempt'
  ) then raise exception 'Invalid GST status'; end if;

  if v_regtype in('registered','composition','sez') then
    if v_gstin is null then raise exception 'GSTIN is required for this GST status'; end if;
    v_valid:=public.gst_gstin_validate_v520(v_gstin);
    if not coalesce((v_valid->>'structurally_valid')::boolean,false) then
      raise exception 'GSTIN failed structural/checksum validation';
    end if;
    v_state_code:=v_valid->>'state_code';
    v_input_state_code:=public.gst_state_code_resolve_v520(v_state_name);
    if v_state_name is not null and v_input_state_code is null then
      raise exception 'State is not recognized by the GST state master';
    end if;
    if v_input_state_code is not null and v_input_state_code<>v_state_code then
      raise exception 'Customer State does not match the GSTIN state';
    end if;
    select s.name into v_state_name from public.gst_state_master_v520 s where s.code=v_state_code;
    v_tax_number:=v_gstin;
  elsif v_regtype='export' then
    v_state_code:='96';v_state_name:='Foreign Country';v_tax_number:=null;
  else
    v_state_code:=public.gst_state_code_resolve_v520(v_state_name);v_tax_number:=null;
  end if;

  if v_id is null then
    v_id:=public.customers_create(
      p_tenant_id,p_name,p_contact_person,p_phone,p_email,v_tax_number,
      p_address_line1,p_address_line2,p_city,v_state_name,p_postal_code,
      v_country,p_credit_limit,p_notes
    );
  else
    perform public.customers_update(
      p_tenant_id,v_id,p_name,p_contact_person,p_phone,p_email,v_tax_number,
      p_address_line1,p_address_line2,p_city,v_state_name,p_postal_code,
      v_country,p_credit_limit,p_notes,coalesce(p_status,'active')
    );
  end if;

  v_profile_id:=private.gst_party_profile_upsert_core_v621(
    p_tenant_id,null,'customer',v_id,v_regtype,v_gstin,p_name,null,
    v_state_code,v_state_code,p_address_line1,p_address_line2,p_city,
    p_postal_code,v_country,coalesce(p_status,'active')='active'
  );
  select g.validation_status into v_validation_status
  from public.gst_party_registrations_v520 g where g.id=v_profile_id;

  return jsonb_build_object(
    'success',true,'customer_id',v_id,'gst_profile_id',v_profile_id,
    'gst_registration_type',v_regtype,
    'gst_validation_status',v_validation_status,'gst_state_code',v_state_code
  );
end;
$function$;

create or replace function public.supplier_master_save_v621(
  p_tenant_id uuid,p_supplier_id uuid,p_name text,p_contact_person text,
  p_phone text,p_email text,p_address_line1 text,p_address_line2 text,
  p_city text,p_state text,p_postal_code text,p_country text,p_notes text,
  p_status text,p_gst_registration_type text,p_gstin text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_id uuid:=p_supplier_id;
  v_profile_id uuid;
  v_regtype text:=lower(trim(coalesce(p_gst_registration_type,'unregistered')));
  v_gstin text:=nullif(upper(regexp_replace(coalesce(p_gstin,''),'\s','','g')),'');
  v_valid jsonb;
  v_state_code text;
  v_input_state_code text;
  v_state_name text:=nullif(trim(coalesce(p_state,'')),'');
  v_country text:=coalesce(nullif(trim(coalesce(p_country,'')),''),'India');
  v_tax_number text;
  v_validation_status text;
begin
  if not private.has_permission(p_tenant_id,'suppliers.manage') then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if v_regtype not in(
    'registered','unregistered','composition','sez','export','exempt'
  ) then raise exception 'Invalid GST status'; end if;

  if v_regtype in('registered','composition','sez') then
    if v_gstin is null then raise exception 'GSTIN is required for this GST status'; end if;
    v_valid:=public.gst_gstin_validate_v520(v_gstin);
    if not coalesce((v_valid->>'structurally_valid')::boolean,false) then
      raise exception 'GSTIN failed structural/checksum validation';
    end if;
    v_state_code:=v_valid->>'state_code';
    v_input_state_code:=public.gst_state_code_resolve_v520(v_state_name);
    if v_state_name is not null and v_input_state_code is null then
      raise exception 'State is not recognized by the GST state master';
    end if;
    if v_input_state_code is not null and v_input_state_code<>v_state_code then
      raise exception 'Supplier State does not match the GSTIN state';
    end if;
    select s.name into v_state_name from public.gst_state_master_v520 s where s.code=v_state_code;
    v_tax_number:=v_gstin;
  elsif v_regtype='export' then
    v_state_code:='96';v_state_name:='Foreign Country';v_tax_number:=null;
  else
    v_state_code:=public.gst_state_code_resolve_v520(v_state_name);v_tax_number:=null;
  end if;

  if v_id is null then
    v_id:=public.suppliers_create(
      p_tenant_id,p_name,p_contact_person,p_phone,p_email,v_tax_number,
      p_address_line1,p_address_line2,p_city,v_state_name,p_postal_code,
      v_country,p_notes
    );
  else
    perform public.suppliers_update(
      p_tenant_id,v_id,p_name,p_contact_person,p_phone,p_email,v_tax_number,
      p_address_line1,p_address_line2,p_city,v_state_name,p_postal_code,
      v_country,p_notes,coalesce(p_status,'active')
    );
  end if;

  v_profile_id:=private.gst_party_profile_upsert_core_v621(
    p_tenant_id,null,'supplier',v_id,v_regtype,v_gstin,p_name,null,
    v_state_code,v_state_code,p_address_line1,p_address_line2,p_city,
    p_postal_code,v_country,coalesce(p_status,'active')='active'
  );
  select g.validation_status into v_validation_status
  from public.gst_party_registrations_v520 g where g.id=v_profile_id;

  return jsonb_build_object(
    'success',true,'supplier_id',v_id,'gst_profile_id',v_profile_id,
    'gst_registration_type',v_regtype,
    'gst_validation_status',v_validation_status,'gst_state_code',v_state_code
  );
end;
$function$;

create or replace function public.customers_list_v621(p_tenant_id uuid)
returns setof jsonb language sql stable security definer
set search_path to 'public','private','pg_temp'
as $function$
  select r || jsonb_build_object(
    'gst_configured',g.id is not null,'gst_profile_id',g.id,
    'gst_registration_type',g.registration_type,'gst_gstin',g.gstin,
    'gst_state_code',g.state_code,
    'gst_place_of_supply_code',g.place_of_supply_code,
    'gst_validation_status',g.validation_status
  )
  from public.customers_list_v482(p_tenant_id) r
  left join lateral (
    select gp.* from public.gst_party_registrations_v520 gp
    where gp.tenant_id=p_tenant_id and gp.party_type='customer'
      and gp.party_id=coalesce(nullif(r->>'customer_id',''),nullif(r->>'id',''))::uuid
      and current_date between gp.effective_from and coalesce(gp.effective_to,'infinity'::date)
    order by gp.is_default desc,gp.active desc,gp.effective_from desc,gp.created_at desc limit 1
  ) g on true;
$function$;

create or replace function public.suppliers_list_v621(p_tenant_id uuid)
returns setof jsonb language sql stable security definer
set search_path to 'public','private','pg_temp'
as $function$
  select r || jsonb_build_object(
    'gst_configured',g.id is not null,'gst_profile_id',g.id,
    'gst_registration_type',g.registration_type,'gst_gstin',g.gstin,
    'gst_state_code',g.state_code,
    'gst_place_of_supply_code',g.place_of_supply_code,
    'gst_validation_status',g.validation_status
  )
  from public.suppliers_list_v32(p_tenant_id) r
  left join lateral (
    select gp.* from public.gst_party_registrations_v520 gp
    where gp.tenant_id=p_tenant_id and gp.party_type='supplier'
      and gp.party_id=coalesce(nullif(r->>'supplier_id',''),nullif(r->>'id',''))::uuid
      and current_date between gp.effective_from and coalesce(gp.effective_to,'infinity'::date)
    order by gp.is_default desc,gp.active desc,gp.effective_from desc,gp.created_at desc limit 1
  ) g on true;
$function$;

revoke all on function public.customer_master_save_v621(
  uuid,uuid,text,text,text,text,text,text,text,text,text,text,numeric,text,text,text,text
) from public,anon;
grant execute on function public.customer_master_save_v621(
  uuid,uuid,text,text,text,text,text,text,text,text,text,text,numeric,text,text,text,text
) to authenticated,service_role;

revoke all on function public.supplier_master_save_v621(
  uuid,uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,text
) from public,anon;
grant execute on function public.supplier_master_save_v621(
  uuid,uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,text
) to authenticated,service_role;

revoke all on function public.customers_list_v621(uuid) from public,anon;
grant execute on function public.customers_list_v621(uuid) to authenticated,service_role;
revoke all on function public.suppliers_list_v621(uuid) from public,anon;
grant execute on function public.suppliers_list_v621(uuid) to authenticated,service_role;

revoke execute on function public.gst_party_profile_save_v520(
  uuid,uuid,text,uuid,text,text,text,text,text,text,text,text,text,text,text,boolean
) from anon;

insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  324,
  '6.2.1-party-master-gst-integration',
  'Customer Supplier GST Master Integration',
  'Adds atomic Customer/Supplier master save RPCs that synchronize the normalized GST party profile in the same transaction. Registered/Composition/SEZ GSTINs are structurally validated and state-linked; Export uses code 96; Unregistered/Exempt use the master state when resolvable. Existing GST document snapshots and historical master rows are not rewritten.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;
