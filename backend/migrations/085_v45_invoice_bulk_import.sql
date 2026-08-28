-- THQ V4.5
-- Full invoice template overrides and store-aware Excel/bulk product import endpoint.
begin;

create or replace function public.tenant_invoice_template_save_v45(p_tenant_id uuid,p_paper_type text,p_template_id uuid,p_overrides jsonb)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v jsonb:=coalesce(p_overrides,'{}'::jsonb);begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'settings.manage') then raise exception 'Settings permission required';end if;
  if p_paper_type not in('a4','80mm') then raise exception 'Invalid paper type';end if;
  if not exists(select 1 from public.invoice_templates where id=p_template_id and paper_type=p_paper_type and is_active) then raise exception 'Invoice template not found';end if;
  -- All design values remain JSON so future fields can be added without schema migrations.
  insert into public.tenant_invoice_templates(tenant_id,paper_type,template_id,overrides,updated_at,updated_by)
  values(p_tenant_id,p_paper_type,p_template_id,v,now(),auth.uid())
  on conflict(tenant_id,paper_type) do update set template_id=excluded.template_id,overrides=excluded.overrides,updated_at=now(),updated_by=auth.uid();
  perform private.business_audit_write(p_tenant_id,'invoice_template.v45.save','invoice_template',p_template_id,p_paper_type,null,jsonb_build_object('paper_type',p_paper_type,'overrides',v));
end $$;
grant execute on function public.tenant_invoice_template_save_v45(uuid,text,uuid,jsonb) to authenticated;

create or replace function public.inventory_bulk_create_products_v45(p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare x jsonb;v_success int:=0;v_failed int:=0;v_errors jsonb:='[]'::jsonb;v_created jsonb:='[]'::jsonb;v_result jsonb;v_row int:=1;begin
  perform private.v4_location_access(p_tenant_id,p_location_id,'operate');
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Inventory manage permission required';end if;
  for x in select value from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    v_row:=v_row+1;
    begin
      if trim(coalesce(x->>'name',''))='' then raise exception 'Product name is required';end if;
      v_result:=public.inventory_create_product_v4(
        p_tenant_id,p_location_id,p_device_id,x->>'name',nullif(trim(coalesce(x->>'sku','')),''),coalesce(nullif(trim(x->>'item_type'),''),'stock'),x->>'description',
        nullif(trim(coalesce(x->>'category','')),''),nullif(trim(coalesce(x->>'brand','')),''),nullif(trim(coalesce(x->>'barcode','')),''),nullif(trim(coalesce(x->>'part_number','')),''),
        coalesce(nullif(x->>'cost_price','')::numeric,0),coalesce(nullif(x->>'selling_price','')::numeric,0),coalesce(nullif(x->>'list_price','')::numeric,0),coalesce(nullif(x->>'tax_rate','')::numeric,0),coalesce(nullif(x->>'reorder_level','')::numeric,0),coalesce(nullif(x->>'opening_stock','')::numeric,0)
      );
      v_success:=v_success+1;v_created:=v_created||jsonb_build_array(jsonb_build_object('row',v_row,'name',x->>'name','sku',v_result->>'sku','variant_id',v_result->>'variant_id'));
    exception when others then
      v_failed:=v_failed+1;v_errors:=v_errors||jsonb_build_array(jsonb_build_object('row',v_row,'name',coalesce(x->>'name',''),'error',sqlerrm));
    end;
  end loop;
  perform private.business_audit_write(p_tenant_id,'inventory.bulk_import','inventory',null,null,p_location_id,jsonb_build_object('success_count',v_success,'failed_count',v_failed,'device_id',p_device_id));
  return jsonb_build_object('success_count',v_success,'failed_count',v_failed,'errors',v_errors,'created',v_created,'location_id',p_location_id);
end $$;
grant execute on function public.inventory_bulk_create_products_v45(uuid,uuid,uuid,jsonb) to authenticated;

commit;
select 'THQ V4.5 invoice designer and bulk product import ready' as status;
