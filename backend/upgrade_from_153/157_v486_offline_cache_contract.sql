-- THQ ERP V4.8.6 — offline product/customer/serial cache contract.
begin;

create or replace function public.pos_offline_product_cache_v486(p_tenant_id uuid,p_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;v jsonb;
begin
  v_location:=private.v486_pos_device_location(p_tenant_id,p_device_id,null);
  select coalesce(jsonb_agg(
    x||jsonb_build_object(
      'stock_quantity',case when x->>'item_type'='stock' then greatest(coalesce(lb.quantity,0)-coalesce(lb.reserved_quantity,0)-coalesce(lb.damaged_quantity,0)-coalesce(lb.quarantine_quantity,0),0) else coalesce(nullif(x->>'stock_quantity','')::numeric,0) end,
      'offline_available_quantity',case when x->>'item_type'='stock' then greatest(coalesce(lb.quantity,0)-coalesce(lb.reserved_quantity,0)-coalesce(lb.damaged_quantity,0)-coalesce(lb.quarantine_quantity,0),0) else coalesce(nullif(x->>'stock_quantity','')::numeric,0) end
    ) order by x->>'product_name',x->>'sku'
  ),'[]'::jsonb) into v
  from public.inventory_list_products_v483(p_tenant_id,v_location) as t(x)
  left join public.location_stock_balances lb on lb.tenant_id=p_tenant_id and lb.location_id=v_location and lb.variant_id=nullif(x->>'variant_id','')::uuid
  left join public.location_product_settings lps on lps.tenant_id=p_tenant_id and lps.location_id=v_location and lps.variant_id=nullif(x->>'variant_id','')::uuid
  where x->>'product_status'='active' and x->>'variant_status'='active' and coalesce(lps.active,true);
  return coalesce(v,'[]'::jsonb);
end$$;
grant execute on function public.pos_offline_product_cache_v486(uuid,uuid) to authenticated;

create or replace function public.pos_offline_customer_cache_v486(p_tenant_id uuid,p_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v jsonb;
begin
  perform private.v486_pos_device_location(p_tenant_id,p_device_id,null);
  select coalesce(jsonb_agg(x order by x->>'customer_name'),'[]'::jsonb) into v from public.customers_list_v482(p_tenant_id) as t(x) where x->>'status'='active';
  return coalesce(v,'[]'::jsonb);
end$$;
grant execute on function public.pos_offline_customer_cache_v486(uuid,uuid) to authenticated;

create or replace function public.pos_offline_available_serials_v486(
  p_tenant_id uuid,p_device_id uuid,p_after text default '',p_limit integer default 1000
) returns table(serial_id uuid,serial_number text,variant_id uuid,updated_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;v_after text:=lower(trim(coalesce(p_after,'')));
begin
  v_location:=private.v486_pos_device_location(p_tenant_id,p_device_id,null);
  return query
  select s.id,s.serial_number,s.variant_id,s.updated_at
  from public.inventory_serials_v483 s
  where s.tenant_id=p_tenant_id and s.current_location_id=v_location and s.status='in_stock'
    and lower(s.serial_number)>v_after
    and not exists(select 1 from public.stock_transfer_allocations_v485 a join public.stock_transfers t on t.id=a.transfer_id where a.tenant_id=p_tenant_id and a.serial_id=s.id and t.status in('requested','approved','in_transit'))
  order by lower(s.serial_number),s.id limit greatest(1,least(coalesce(p_limit,1000),2000));
end$$;
grant execute on function public.pos_offline_available_serials_v486(uuid,uuid,text,integer) to authenticated;

create or replace function public.pos_offline_cache_manifest_v486(p_tenant_id uuid,p_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_location uuid;v_shift jsonb;
begin
  v_location:=private.v486_pos_device_location(p_tenant_id,p_device_id,null);
  begin v_shift:=public.cashier_shift_current_v472(p_tenant_id,p_device_id);exception when others then v_shift:=null;end;
  return jsonb_build_object(
    'tenant_id',p_tenant_id,'device_id',p_device_id,'location_id',v_location,'generated_at',now(),
    'schema_version','4.8.6','migration_no',157,'current_shift',v_shift
  );
end$$;
grant execute on function public.pos_offline_cache_manifest_v486(uuid,uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(157,'4.8.6','Offline POS','Offline product/customer cache and paged available-serial cache using true available location stock.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.6 migration 157 offline cache contract applied' as status;
