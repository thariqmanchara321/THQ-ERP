begin;
create or replace function public.gst_product_profile_save_v520(
 p_tenant_id uuid,p_variant_id uuid,p_supply_kind text,p_hsn_sac text,p_taxability text,p_gst_rate numeric,p_cess_rate numeric,p_cess_per_unit numeric,
 p_tax_inclusive boolean,p_reverse_charge boolean,p_notes text,p_effective_from date
) returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
 v_id uuid;v_kind text:=lower(trim(coalesce(p_supply_kind,'')));v_taxability text:=lower(trim(coalesce(p_taxability,'taxable')));
 v_hsn text:=nullif(regexp_replace(coalesce(p_hsn_sac,''),'\s','','g'),'');v_rate numeric:=coalesce(p_gst_rate,0);v_status text;
 v_old jsonb;v_old_effective date;v_effective date:=coalesce(p_effective_from,current_date);
begin
 if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.manage') then raise exception 'GST manage permission required';end if;
 if not exists(select 1 from public.product_variants where id=p_variant_id and tenant_id=p_tenant_id) then raise exception 'Product variant not found';end if;
 if v_kind not in('goods','service') then raise exception 'Supply kind must be goods or service';end if;
 if v_taxability not in('taxable','nil_rated','exempt','non_gst') then raise exception 'Invalid taxability';end if;
 if v_hsn is not null and v_hsn !~ '^[0-9]{4}([0-9]{2})?([0-9]{2})?$' then raise exception 'HSN/SAC must be 4, 6 or 8 digits';end if;
 if v_taxability<>'taxable' then v_rate:=0;end if;
 if v_rate<0 or v_rate>100 or coalesce(p_cess_rate,0)<0 or coalesce(p_cess_rate,0)>100 or coalesce(p_cess_per_unit,0)<0 then raise exception 'Invalid GST/Cess rate';end if;
 v_status:=case when v_hsn is not null and exists(select 1 from public.gst_tax_rate_master_v520 r where r.rate=v_rate and r.active and r.effective_from<=v_effective and (r.effective_to is null or r.effective_to>=v_effective)) then 'locally_validated' else 'review_required' end;
 select to_jsonb(g),g.id,g.effective_from into v_old,v_id,v_old_effective
 from public.gst_product_tax_profiles_v520 g
 where g.tenant_id=p_tenant_id and g.variant_id=p_variant_id and g.active and g.effective_to is null
 order by g.effective_from desc limit 1 for update;
 if v_id is not null and v_old_effective>=v_effective then
   update public.gst_product_tax_profiles_v520
   set supply_kind=v_kind,hsn_sac=v_hsn,taxability=v_taxability,gst_rate=v_rate,cess_rate=coalesce(p_cess_rate,0),cess_per_unit=coalesce(p_cess_per_unit,0),
       tax_inclusive=coalesce(p_tax_inclusive,false),reverse_charge=coalesce(p_reverse_charge,false),validation_status=v_status,source='manual',
       notes=nullif(trim(coalesce(p_notes,'')),''),effective_from=v_effective,updated_by=auth.uid(),updated_at=now()
   where id=v_id;
 else
   if v_id is not null then update public.gst_product_tax_profiles_v520 set effective_to=v_effective-1,updated_at=now(),updated_by=auth.uid() where id=v_id;end if;
   v_id:=gen_random_uuid();
   insert into public.gst_product_tax_profiles_v520(id,tenant_id,variant_id,supply_kind,hsn_sac,taxability,gst_rate,cess_rate,cess_per_unit,tax_inclusive,reverse_charge,validation_status,source,notes,active,effective_from,created_by,updated_by)
   values(v_id,p_tenant_id,p_variant_id,v_kind,v_hsn,v_taxability,v_rate,coalesce(p_cess_rate,0),coalesce(p_cess_per_unit,0),coalesce(p_tax_inclusive,false),coalesce(p_reverse_charge,false),v_status,'manual',nullif(trim(coalesce(p_notes,'')),''),true,v_effective,auth.uid(),auth.uid());
 end if;
 perform private.business_audit_write_v471(p_tenant_id,'gst.product_profile.save','product_variant',p_variant_id,null,v_old,(select to_jsonb(g) from public.gst_product_tax_profiles_v520 g where g.id=v_id));
 return v_id;
end $$;
revoke all on function public.gst_product_profile_save_v520(uuid,uuid,text,text,text,numeric,numeric,numeric,boolean,boolean,text,date) from public,anon;
grant execute on function public.gst_product_profile_save_v520(uuid,uuid,text,text,text,numeric,numeric,numeric,boolean,boolean,text,date) to authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(217,'5.2.0-foundation','GST Foundation Hotfix 3','Makes product tax profile changes safely effective-dated: same-day replacement in place and historical periods retained for prior-document reproducibility.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;