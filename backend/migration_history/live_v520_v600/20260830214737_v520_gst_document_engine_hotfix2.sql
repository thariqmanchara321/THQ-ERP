begin;
do $hotfix$
declare v_oid oid;v_def text;
begin
 select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='gst_document_quote_v520' and pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_document_kind text, p_location_id uuid, p_party_id uuid, p_document_date date, p_supply_type text, p_place_of_supply_code text, p_items jsonb, p_additional_charges numeric, p_round_off numeric';
 if v_oid is null then raise exception 'gst_document_quote_v520 not found';end if;
 select pg_get_functiondef(v_oid) into v_def;
 if position('tr.rate=rate' in v_def)=0 then raise exception 'Expected rate ambiguity pattern not found';end if;
 v_def:=replace(v_def,'taxable numeric;rate numeric;cess_rate numeric;','taxable numeric;v_rate numeric;cess_rate numeric;');
 v_def:=replace(v_def,'rate:=coalesce(prod.tax_rate,0)','v_rate:=coalesce(prod.tax_rate,0)');
 v_def:=replace(v_def,'rate:=prof.gst_rate','v_rate:=prof.gst_rate');
 v_def:=replace(v_def,'tr.rate=rate','tr.rate=v_rate');
 v_def:=replace(v_def,'applied_rate:=rate;','applied_rate:=v_rate;');
 v_def:=replace(v_def,'''gst_rate'',rate,','''gst_rate'',v_rate,');
 execute v_def;
end $hotfix$;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(222,'5.2.0-foundation','Central GST Engine Hotfix 2','Fixes PL/pgSQL rate variable/column ambiguity found by rollback GST matrix testing. No business transaction data changed.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;