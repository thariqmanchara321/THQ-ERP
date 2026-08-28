-- FLEXI ERP V4.4
-- Barcode lookup + uniqueness enforcement for future writes.
begin;

create or replace function private.v44_product_barcode_unique()
returns trigger language plpgsql set search_path=public,private,pg_temp
as $$ begin
  if nullif(trim(coalesce(new.barcode,'')),'') is not null and exists(
    select 1 from public.product_variants x
    where x.tenant_id=new.tenant_id and x.id<>new.id and lower(trim(coalesce(x.barcode,'')))=lower(trim(new.barcode))
  ) then
    raise exception 'Barcode % already belongs to another product',new.barcode;
  end if;
  return new;
end $$;

drop trigger if exists trg_v44_product_barcode_unique on public.product_variants;
create trigger trg_v44_product_barcode_unique
before insert or update of barcode,tenant_id on public.product_variants
for each row execute function private.v44_product_barcode_unique();

create or replace function public.inventory_barcode_lookup_v44(p_tenant_id uuid,p_barcode text,p_location_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$ declare v jsonb;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if trim(coalesce(p_barcode,''))='' then return '{}'::jsonb;end if;
  select jsonb_build_object(
    'variant_id',pv.id,'product_id',p.id,'product_name',p.name,'sku',pv.sku,'barcode',pv.barcode,'part_number',pv.part_number,
    'item_type',p.item_type,'selling_price',coalesce(lps.selling_price,pv.selling_price),'cost_price',pv.cost_price,'tax_rate',pv.tax_rate,
    'location_id',p_location_id,'stock_quantity',coalesce(lsb.quantity,0),'available_quantity',coalesce(lsb.quantity-lsb.reserved_quantity-lsb.damaged_quantity-lsb.quarantine_quantity,0)
  ) into v
  from public.product_variants pv join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id
  left join public.location_product_settings lps on lps.tenant_id=p_tenant_id and lps.variant_id=pv.id and lps.location_id=p_location_id
  left join public.location_stock_balances lsb on lsb.tenant_id=p_tenant_id and lsb.variant_id=pv.id and lsb.location_id=p_location_id
  where pv.tenant_id=p_tenant_id and lower(trim(coalesce(pv.barcode,'')))=lower(trim(p_barcode))
  order by pv.created_at limit 1;
  return coalesce(v,'{}'::jsonb);
end $$;
grant execute on function public.inventory_barcode_lookup_v44(uuid,text,uuid) to authenticated;

commit;
select 'Flexi ERP V4.4 barcode workflows ready' as status;
