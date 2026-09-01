-- THQ ERP v4.9.5 — invoice branding, asset upload and print-ready template defaults.
begin;

-- Secure public asset bucket for tenant branding. Paths are always <tenant_uuid>/...
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('thq-assets','thq-assets',true,5242880,array['image/png','image/jpeg'])
on conflict(id) do update set public=true,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create or replace function public.thq_asset_path_allowed_v495(p_name text)
returns boolean language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_tenant uuid;
begin
  begin
    v_tenant:=split_part(coalesce(p_name,''),'/',1)::uuid;
  exception when others then
    return false;
  end;
  return private.erp_user_has_tenant_access(v_tenant);
end $$;
grant execute on function public.thq_asset_path_allowed_v495(text) to authenticated;

-- Storage policies are tenant-scoped by the first path segment.
drop policy if exists thq_assets_read_v495 on storage.objects;
drop policy if exists thq_assets_insert_v495 on storage.objects;
drop policy if exists thq_assets_update_v495 on storage.objects;
drop policy if exists thq_assets_delete_v495 on storage.objects;
create policy thq_assets_read_v495 on storage.objects for select to authenticated
  using(bucket_id='thq-assets' and public.thq_asset_path_allowed_v495(name));
create policy thq_assets_insert_v495 on storage.objects for insert to authenticated
  with check(bucket_id='thq-assets' and public.thq_asset_path_allowed_v495(name));
create policy thq_assets_update_v495 on storage.objects for update to authenticated
  using(bucket_id='thq-assets' and public.thq_asset_path_allowed_v495(name))
  with check(bucket_id='thq-assets' and public.thq_asset_path_allowed_v495(name));
create policy thq_assets_delete_v495 on storage.objects for delete to authenticated
  using(bucket_id='thq-assets' and public.thq_asset_path_allowed_v495(name));

-- Normalize system A4 template capabilities. Existing tenant overrides remain intact.
update public.invoice_templates
set config = coalesce(config,'{}'::jsonb) || jsonb_build_object(
  'show_logo',true,
  'show_gstin',true,
  'show_phone',true,
  'show_address',true,
  'show_customer',true,
  'show_tax_breakup',true,
  'show_payment_details',true,
  'show_terms',true,
  'columns',coalesce(config->'columns','["item","sku","hsn","qty","unit","rate","discount","tax","tax_amount","total"]'::jsonb)
)
where paper_type='a4' and is_system=true;


-- Enrich invoice sale detail with the customer's printable contact/address fields.
create or replace function public.sales_get_detail_v495(p_tenant_id uuid,p_sale_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v jsonb; c record; sale_doc jsonb;
begin
  v:=public.sales_get_detail_v482(p_tenant_id,p_sale_id);
  select cu.phone,cu.email,cu.address_line1,cu.address_line2,cu.city,cu.state,cu.postal_code,cu.country
    into c
  from public.sales s join public.customers cu on cu.id=s.customer_id
  where s.id=p_sale_id and s.tenant_id=p_tenant_id;
  sale_doc:=coalesce(v->'sale','{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
    'customer_phone',c.phone,'customer_email',c.email,'customer_address_line1',c.address_line1,'customer_address_line2',c.address_line2,
    'customer_city',c.city,'customer_state',c.state,'customer_postal_code',c.postal_code,'customer_country',c.country
  ));
  return jsonb_set(v,'{sale}',sale_doc,true);
end $$;
grant execute on function public.sales_get_detail_v495(uuid,uuid) to authenticated;

create or replace function public.invoice_template_capabilities_v495(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return jsonb_build_object(
    'paper_types',jsonb_build_array('a4','80mm'),
    'logo_formats',jsonb_build_array('png','jpg','jpeg'),
    'max_logo_bytes',5242880,
    'columns',jsonb_build_array('item','sku','hsn','qty','unit','rate','discount','tax','tax_amount','taxable','total'),
    'print_dialog',true,
    'pdf_download',true,
    'xlsx_reports',true
  );
end $$;
grant execute on function public.invoice_template_capabilities_v495(uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(198,'4.9.5','Invoice & Print Foundation','Tenant logo assets, selectable invoice columns, richer A4 template defaults and print/export capability metadata.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP v4.9.5 migration 198 applied' as status;
