-- THQ ERP V4.8.2 — Product Identification
begin;

create table if not exists public.product_identifiers_v482(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
 variant_id uuid not null references public.product_variants(id) on delete cascade,
 identifier_type text not null check(identifier_type in('barcode','qr','manufacturer','supplier','internal','alternate_sku')),
 code text not null,supplier_id uuid references public.suppliers(id) on delete set null,label text,
 is_primary boolean not null default false,generated boolean not null default false,active boolean not null default true,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create unique index if not exists ux_product_identifiers_v482_code on public.product_identifiers_v482(tenant_id,lower(trim(code))) where active;
create unique index if not exists ux_product_identifiers_v482_primary_barcode on public.product_identifiers_v482(tenant_id,variant_id,identifier_type) where active and is_primary and identifier_type in('barcode','qr','internal');
create index if not exists idx_product_identifiers_v482_variant on public.product_identifiers_v482(tenant_id,variant_id,active,identifier_type);
alter table public.product_identifiers_v482 enable row level security;
drop policy if exists product_identifiers_v482_read on public.product_identifiers_v482;
create policy product_identifiers_v482_read on public.product_identifiers_v482 for select to authenticated using(private.erp_user_has_tenant_access(tenant_id));
revoke insert,update,delete on public.product_identifiers_v482 from authenticated; grant select on public.product_identifiers_v482 to authenticated;

create table if not exists public.product_identifier_sequences_v482(
 tenant_id uuid primary key references public.tenants(id) on delete cascade,next_barcode bigint not null default 1,next_qr bigint not null default 1,updated_at timestamptz not null default now());
alter table public.product_identifier_sequences_v482 enable row level security; revoke all on public.product_identifier_sequences_v482 from anon,authenticated;
insert into public.product_identifier_sequences_v482(tenant_id) select t.id from public.tenants t on conflict do nothing;

insert into public.product_identifiers_v482(tenant_id,variant_id,identifier_type,code,label,is_primary,generated)
select pv.tenant_id,pv.id,'barcode',trim(pv.barcode),'Legacy Barcode',true,false from public.product_variants pv where nullif(trim(coalesce(pv.barcode,'')),'') is not null on conflict do nothing;
insert into public.product_identifiers_v482(tenant_id,variant_id,identifier_type,code,label,is_primary,generated)
select pv.tenant_id,pv.id,'manufacturer',trim(pv.part_number),'Manufacturer / Part Code',true,false from public.product_variants pv where nullif(trim(coalesce(pv.part_number,'')),'') is not null on conflict do nothing;

create or replace function private.v482_sync_legacy_identifiers(p_tenant_id uuid,p_variant_id uuid) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_barcode text;v_part text;begin
 select i.code into v_barcode from public.product_identifiers_v482 i where i.tenant_id=p_tenant_id and i.variant_id=p_variant_id and i.identifier_type='barcode' and i.active order by i.is_primary desc,i.updated_at desc limit 1;
 select i.code into v_part from public.product_identifiers_v482 i where i.tenant_id=p_tenant_id and i.variant_id=p_variant_id and i.identifier_type='manufacturer' and i.active order by i.is_primary desc,i.updated_at desc limit 1;
 update public.product_variants set barcode=v_barcode,part_number=v_part,updated_at=now() where tenant_id=p_tenant_id and id=p_variant_id;
end$$;
revoke all on function private.v482_sync_legacy_identifiers(uuid,uuid) from public;

create or replace function private.v482_ean13_check_digit(p_digits12 text) returns text language plpgsql immutable set search_path=public,private,pg_temp as $$
declare i int;v_sum int:=0;v_digit int;begin
 if p_digits12 !~ '^[0-9]{12}$' then raise exception 'EAN seed must contain 12 digits';end if;
 for i in 1..12 loop v_digit:=substr(p_digits12,i,1)::int;v_sum:=v_sum+case when mod(i,2)=0 then v_digit*3 else v_digit end;end loop;
 return ((10-mod(v_sum,10))%10)::text;
end$$;
revoke all on function private.v482_ean13_check_digit(text) from public;
do $$declare r record;begin for r in select distinct i.tenant_id,i.variant_id from public.product_identifiers_v482 i loop perform private.v482_sync_legacy_identifiers(r.tenant_id,r.variant_id);end loop;end$$;

create or replace function public.product_identifiers_v482_list(p_tenant_id uuid,p_variant_id uuid) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 return query select jsonb_build_object('identifier_id',i.id,'variant_id',i.variant_id,'identifier_type',i.identifier_type,'code',i.code,'supplier_id',i.supplier_id,'supplier_name',s.name,'label',i.label,'is_primary',i.is_primary,'generated',i.generated,'active',i.active,'created_at',i.created_at)
 from public.product_identifiers_v482 i left join public.suppliers s on s.id=i.supplier_id where i.tenant_id=p_tenant_id and i.variant_id=p_variant_id order by i.active desc,i.is_primary desc,i.identifier_type,i.code;
end$$;
grant execute on function public.product_identifiers_v482_list(uuid,uuid) to authenticated;

create or replace function public.product_identifier_save_v482(p_tenant_id uuid,p_identifier_id uuid,p_variant_id uuid,p_identifier_type text,p_code text,p_supplier_id uuid,p_label text,p_is_primary boolean,p_active boolean default true)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_id uuid;v_type text:=lower(trim(coalesce(p_identifier_type,'')));v_code text:=trim(coalesce(p_code,''));begin
 if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Inventory manage permission required';end if;
 if v_type not in('barcode','qr','manufacturer','supplier','internal','alternate_sku') then raise exception 'Invalid identifier type';end if;
 if v_code='' then raise exception 'Identifier code is required';end if;
 if not exists(select 1 from public.product_variants pv where pv.tenant_id=p_tenant_id and pv.id=p_variant_id) then raise exception 'Product variant not found';end if;
 if exists(select 1 from public.product_variants pv where pv.tenant_id=p_tenant_id and pv.id<>p_variant_id and lower(trim(pv.sku))=lower(v_code)) then raise exception 'Code % is already used as another product SKU',v_code;end if;
 if p_supplier_id is not null and not exists(select 1 from public.suppliers s where s.tenant_id=p_tenant_id and s.id=p_supplier_id) then raise exception 'Supplier not found';end if;
 if p_is_primary then update public.product_identifiers_v482 set is_primary=false,updated_at=now() where tenant_id=p_tenant_id and variant_id=p_variant_id and identifier_type=v_type and active;end if;
 if p_identifier_id is null then
  insert into public.product_identifiers_v482(tenant_id,variant_id,identifier_type,code,supplier_id,label,is_primary,active) values(p_tenant_id,p_variant_id,v_type,v_code,p_supplier_id,nullif(trim(coalesce(p_label,'')),''),p_is_primary,p_active) returning id into v_id;
 else
  update public.product_identifiers_v482 set identifier_type=v_type,code=v_code,supplier_id=p_supplier_id,label=nullif(trim(coalesce(p_label,'')),''),is_primary=p_is_primary,active=p_active,updated_at=now() where id=p_identifier_id and tenant_id=p_tenant_id and variant_id=p_variant_id returning id into v_id;
  if v_id is null then raise exception 'Identifier not found';end if;
 end if;
 perform private.v482_sync_legacy_identifiers(p_tenant_id,p_variant_id);
 perform private.thq_sync_bump_v480(p_tenant_id,'catalogue','product_identifier',p_variant_id::text,'save');return v_id;
end$$;
grant execute on function public.product_identifier_save_v482(uuid,uuid,uuid,text,text,uuid,text,boolean,boolean) to authenticated;

create or replace function public.product_identifier_archive_v482(p_tenant_id uuid,p_identifier_id uuid) returns void language plpgsql security definer set search_path=public,private,pg_temp as $$declare v_variant uuid;begin
 if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Inventory manage permission required';end if;
 update public.product_identifiers_v482 set active=false,is_primary=false,updated_at=now() where id=p_identifier_id and tenant_id=p_tenant_id returning variant_id into v_variant;
 if v_variant is null then raise exception 'Identifier not found';end if;
 perform private.v482_sync_legacy_identifiers(p_tenant_id,v_variant);
 perform private.thq_sync_bump_v480(p_tenant_id,'catalogue','product_identifier',v_variant::text,'archive');
end$$;
grant execute on function public.product_identifier_archive_v482(uuid,uuid) to authenticated;

create or replace function public.product_identifier_generate_v482(p_tenant_id uuid,p_variant_id uuid,p_identifier_type text) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_type text:=lower(trim(coalesce(p_identifier_type,'')));v_seq bigint;v_seed text;v_code text;v_id uuid;v_short text;begin
 if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Inventory manage permission required';end if;
 if not exists(select 1 from public.product_variants pv where pv.tenant_id=p_tenant_id and pv.id=p_variant_id) then raise exception 'Product variant not found';end if;
 insert into public.product_identifier_sequences_v482(tenant_id) values(p_tenant_id) on conflict do nothing;
 if v_type='barcode' then
  select s.next_barcode into v_seq from public.product_identifier_sequences_v482 s where s.tenant_id=p_tenant_id for update;
  update public.product_identifier_sequences_v482 set next_barcode=next_barcode+1,updated_at=now() where tenant_id=p_tenant_id;
  v_seed:='28'||lpad(v_seq::text,10,'0');v_code:=v_seed||private.v482_ean13_check_digit(v_seed);
 elsif v_type='qr' then
  select s.next_qr into v_seq from public.product_identifier_sequences_v482 s where s.tenant_id=p_tenant_id for update;
  update public.product_identifier_sequences_v482 set next_qr=next_qr+1,updated_at=now() where tenant_id=p_tenant_id;
  v_short:=replace(left(p_variant_id::text,8),'-','');v_code:='THQ:PRODUCT:'||v_short||':'||lpad(v_seq::text,8,'0');
 else raise exception 'Only barcode or QR identifiers can be generated automatically';end if;
 v_id:=public.product_identifier_save_v482(p_tenant_id,null,p_variant_id,v_type,v_code,null,'Generated by THQ',not exists(select 1 from public.product_identifiers_v482 i where i.tenant_id=p_tenant_id and i.variant_id=p_variant_id and i.identifier_type=v_type and i.active and i.is_primary),true);
 update public.product_identifiers_v482 set generated=true where id=v_id;
 return jsonb_build_object('identifier_id',v_id,'identifier_type',v_type,'code',v_code);
end$$;
grant execute on function public.product_identifier_generate_v482(uuid,uuid,text) to authenticated;

create or replace function public.inventory_list_products_v482(p_tenant_id uuid,p_location_id uuid default null) returns setof jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare r jsonb;v_variant uuid;v_ids jsonb;v_codes text;begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 for r in select * from public.inventory_list_products_v481(p_tenant_id,p_location_id) loop
  begin v_variant:=(r->>'variant_id')::uuid;exception when others then v_variant:=null;end;
  if v_variant is not null then
   select coalesce(jsonb_agg(jsonb_build_object('identifier_id',i.id,'type',i.identifier_type,'code',i.code,'label',i.label,'is_primary',i.is_primary,'supplier_id',i.supplier_id) order by i.is_primary desc,i.identifier_type,i.code),'[]'::jsonb),string_agg(i.code,' ' order by i.code)
   into v_ids,v_codes from public.product_identifiers_v482 i where i.tenant_id=p_tenant_id and i.variant_id=v_variant and i.active;
  else v_ids:='[]'::jsonb;v_codes:='';end if;
  return next r||jsonb_build_object('identifiers',coalesce(v_ids,'[]'::jsonb),'search_codes',coalesce(v_codes,''));
 end loop;return;
end$$;
grant execute on function public.inventory_list_products_v482(uuid,uuid) to authenticated;

create or replace function public.inventory_product_lookup_v482(p_tenant_id uuid,p_code text,p_location_id uuid default null) returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_variant uuid;v_code text:=lower(trim(coalesce(p_code,'')));v jsonb;begin
 if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
 if v_code='' then return '{}'::jsonb;end if;
 select pv.id into v_variant from public.product_variants pv where pv.tenant_id=p_tenant_id and lower(trim(pv.sku))=v_code limit 1;
 if v_variant is null then select i.variant_id into v_variant from public.product_identifiers_v482 i where i.tenant_id=p_tenant_id and i.active and lower(trim(i.code))=v_code limit 1;end if;
 -- Compatibility fallback for historical installations where a legacy barcode/part number
 -- has not yet been promoted to the identifier table. SKU always has first priority.
 if v_variant is null then select pv.id into v_variant from public.product_variants pv where pv.tenant_id=p_tenant_id and (lower(trim(coalesce(pv.barcode,'')))=v_code or lower(trim(coalesce(pv.part_number,'')))=v_code) order by case when lower(trim(coalesce(pv.barcode,'')))=v_code then 0 else 1 end limit 1;end if;
 if v_variant is null then return '{}'::jsonb;end if;
 select r into v from public.inventory_list_products_v482(p_tenant_id,p_location_id) r where (r->>'variant_id')::uuid=v_variant limit 1;
 return coalesce(v,'{}'::jsonb);
end$$;
grant execute on function public.inventory_product_lookup_v482(uuid,text,uuid) to authenticated;

-- Prevent future SKU edits from colliding with an identifier owned by another product.
create or replace function private.v482_product_sku_guard() returns trigger language plpgsql set search_path=public,private,pg_temp as $$begin
 if exists(select 1 from public.product_identifiers_v482 i where i.tenant_id=new.tenant_id and i.variant_id<>new.id and i.active and lower(trim(i.code))=lower(trim(new.sku))) then raise exception 'SKU % is already used as another product identifier',new.sku;end if;
 return new;
end$$;
drop trigger if exists trg_v482_product_sku_guard on public.product_variants;
create trigger trg_v482_product_sku_guard before insert or update of sku on public.product_variants for each row execute function private.v482_product_sku_guard();

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(131,'4.8.2','Pricing & Product Identification','Multiple product identifiers, generated internal barcodes/QR codes and unified SKU/code lookup.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.8.2 migration 131 product identification applied' as status;
