begin;
do $hotfix$
declare v_oid oid;v_def text;
begin
 select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='gst_document_quote_v520' and pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_document_kind text, p_location_id uuid, p_party_id uuid, p_document_date date, p_supply_type text, p_place_of_supply_code text, p_items jsonb, p_additional_charges numeric, p_round_off numeric';
 if v_oid is null then raise exception 'gst_document_quote_v520 not found';end if;
 select pg_get_functiondef(v_oid) into v_def;
 if position('g.party_type=party_type' in v_def)=0 then raise exception 'Expected gst_document_quote_v520 ambiguity pattern not found';end if;
 v_def:=replace(v_def,'party_type text;','v_party_type text;');
 v_def:=replace(v_def,'party_type:=case','v_party_type:=case');
 v_def:=replace(v_def,'g.party_type=party_type','g.party_type=v_party_type');
 execute v_def;
end $hotfix$;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(221,'5.2.0-foundation','Central GST Engine Hotfix 1','Fixes PL/pgSQL party_type variable/column ambiguity found by rollback GST matrix testing. No business transaction data changed.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;