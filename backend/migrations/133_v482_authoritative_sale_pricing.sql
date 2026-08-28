-- THQ ERP V4.8.2 — authoritative sale pricing.
begin;
alter table public.sale_items add column if not exists pricing_source text,add column if not exists price_list_id uuid references public.price_lists_v482(id) on delete set null,add column if not exists pricing_metadata jsonb not null default '{}'::jsonb;
create or replace function private.v482_price_sale_items(p_tenant_id uuid,p_customer_id uuid,p_items jsonb,p_location_id uuid) returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare x jsonb;v_out jsonb:='[]'::jsonb;v_variant uuid;v_unit uuid;v_qty numeric;v_price jsonb;begin
 for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
  v_variant:=nullif(x->>'variant_id','')::uuid;v_unit:=nullif(x->>'unit_id','')::uuid;v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);
  if v_variant is null or v_qty<=0 then raise exception 'Valid product and quantity are required';end if;
  v_price:=private.pricing_resolve_v482_internal(p_tenant_id,v_variant,p_customer_id,v_unit,v_qty,p_location_id);
  v_out:=v_out||jsonb_build_array(x||jsonb_build_object('unit_id',v_price->>'unit_id','unit_price',(v_price->>'unit_price')::numeric,'_pricing_source',v_price->>'source','_price_list_id',v_price->>'price_list_id','_price_list_name',v_price->>'price_list_name'));
 end loop;return v_out;
end$$;
revoke all on function private.v482_price_sale_items(uuid,uuid,jsonb,uuid) from public;
create or replace function public.sales_create_v482(p_tenant_id uuid,p_customer_id uuid,p_sale_date date,p_due_date date,p_items jsonb,p_additional_charges numeric,p_initial_payment numeric,p_payment_method text,p_payment_reference text,p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$declare v_priced jsonb;v_result jsonb;v_sale uuid;x jsonb;v_variant uuid;begin
 v_priced:=private.v482_price_sale_items(p_tenant_id,p_customer_id,p_items,p_location_id);
 v_result:=public.sales_create_v481(p_tenant_id,p_customer_id,p_sale_date,p_due_date,v_priced,p_additional_charges,p_initial_payment,p_payment_method,p_payment_reference,p_notes,p_location_id,p_device_id,p_request_id);
 v_sale:=nullif(v_result->>'sale_id','')::uuid;
 if v_sale is not null then
  for x in select value from jsonb_array_elements(v_priced) loop
   v_variant:=(x->>'variant_id')::uuid;
   update public.sale_items si set pricing_source=nullif(x->>'_pricing_source',''),price_list_id=nullif(x->>'_price_list_id','')::uuid,pricing_metadata=jsonb_strip_nulls(jsonb_build_object('price_list_name',nullif(x->>'_price_list_name',''),'resolved_at',now()))
   where si.sale_id=v_sale and si.variant_id=v_variant and si.entered_unit_id=nullif(x->>'unit_id','')::uuid;
  end loop;
 end if;
 return v_result||jsonb_build_object('pricing_engine','v4.8.2');
end$$;
grant execute on function public.sales_create_v482(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text) to authenticated;
create or replace function public.sales_get_detail_v482(p_tenant_id uuid,p_sale_id uuid) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$declare v jsonb;v_items jsonb;begin
 v:=public.sales_get_detail_v32(p_tenant_id,p_sale_id);
 select coalesce(jsonb_agg(i.value||jsonb_build_object('pricing_source',si.pricing_source,'price_list_id',si.price_list_id,'pricing_metadata',si.pricing_metadata)),'[]'::jsonb) into v_items
 from jsonb_array_elements(coalesce(v->'items','[]'::jsonb)) i(value) left join public.sale_items si on si.sale_id=p_sale_id and si.variant_id=nullif(i.value->>'variant_id','')::uuid and (si.entered_unit_code is null or si.entered_unit_code=coalesce(i.value->>'unit_code',si.entered_unit_code));
 return jsonb_set(v,'{items}',coalesce(v_items,'[]'::jsonb),true);
end$$;
grant execute on function public.sales_get_detail_v482(uuid,uuid) to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(133,'4.8.2','Pricing & Product Identification','Authoritative database price resolution for sales with pricing provenance on sale lines.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.2 migration 133 authoritative pricing applied' as status;
