begin;
do $hotfix$
declare v_oid oid;v_def text;
begin
 select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='gst_document_quote_v520' and pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_document_kind text, p_location_id uuid, p_party_id uuid, p_document_date date, p_supply_type text, p_place_of_supply_code text, p_items jsonb, p_additional_charges numeric, p_round_off numeric';
 if v_oid is null then raise exception 'gst_document_quote_v520 not found';end if;
 select pg_get_functiondef(v_oid) into v_def;
 if position('line_total numeric;' in v_def)=0 or position('grand:=round(taxable_total+' in v_def)=0 then raise exception 'Expected GST rounding patterns not found';end if;
 v_def:=replace(v_def,'line_total numeric;','line_total numeric;line_total_sum numeric:=0;calculation_rounding numeric;calculation_rounding_total numeric:=0;');
 v_def:=replace(v_def,'line_total:=case when inclusive and not rcm then round(gross,2) else round(taxable+collected_tax,2) end;','line_total:=case when inclusive and not rcm then round(gross,2) else round(taxable+collected_tax,2) end;calculation_rounding:=round(line_total-round(taxable+collected_tax,2),2);line_total_sum:=line_total_sum+line_total;calculation_rounding_total:=calculation_rounding_total+calculation_rounding;');
 v_def:=replace(v_def,'''line_total'',line_total,''profile_source''','''line_total'',line_total,''calculation_rounding'',calculation_rounding,''profile_source''');
 v_def:=replace(v_def,'grand:=round(taxable_total+cgst_total+sgst_total+utgst_total+igst_total+cess_total+coalesce(p_additional_charges,0)+coalesce(p_round_off,0),2);','grand:=round(line_total_sum+coalesce(p_additional_charges,0)+coalesce(p_round_off,0),2);');
 v_def:=replace(v_def,'''round_off'',round(coalesce(p_round_off,0),2),''grand_total''','''round_off'',round(coalesce(p_round_off,0),2),''calculation_rounding'',round(calculation_rounding_total,2),''grand_total''');
 execute v_def;
end $hotfix$;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(223,'5.2.0-foundation','Central GST Engine Hotfix 3','Reconciles tax-inclusive extraction/component rounding by summing finalized line totals and exposing calculation_rounding explicitly. No business transaction data changed.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;