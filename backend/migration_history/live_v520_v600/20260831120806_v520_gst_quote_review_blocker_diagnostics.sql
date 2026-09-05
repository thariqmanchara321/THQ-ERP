do $migration$
declare
  v_def text;
  v_new text;
  v_old text;
begin
  select pg_get_functiondef(p.oid)
  into v_def
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='gst_document_quote_v520'
    and p.prokind='f'
    and pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_document_kind text, p_location_id uuid, p_party_id uuid, p_document_date date, p_supply_type text, p_place_of_supply_code text, p_items jsonb, p_additional_charges numeric, p_round_off numeric';

  if v_def is null then
    raise exception 'gst_document_quote_v520 definition not found';
  end if;

  v_new:=v_def;

  v_old:=$needle$profile_source:='legacy_product';profile_status:='review_required';warnings:=array_append(warnings,'Product '||prod.sku||' has no GST profile; generic legacy tax rate used');$needle$;
  if strpos(v_new,v_old)=0 then
    raise exception 'Expected missing-profile diagnostic block not found';
  end if;
  v_new:=replace(
    v_new,
    v_old,
    $replacement$profile_source:='legacy_product';profile_status:='review_required';warnings:=array_append(warnings,'Product '||prod.sku||' has no GST profile; generic legacy tax rate used');errors:=array_append(errors,'Product '||prod.sku||' has no validated GST profile; review and validate the product GST profile before compliance posting');$replacement$
  );

  v_old:=$needle$if prof.validation_status='review_required' then warnings:=array_append(warnings,'Product '||prod.sku||' GST profile requires review');end if;$needle$;
  if strpos(v_new,v_old)=0 then
    raise exception 'Expected review-required diagnostic block not found';
  end if;
  v_new:=replace(
    v_new,
    v_old,
    $replacement$if prof.validation_status='review_required' then warnings:=array_append(warnings,'Product '||prod.sku||' GST profile requires review');errors:=array_append(errors,'Product '||prod.sku||' GST profile requires review and validation before compliance posting');end if;$replacement$
  );

  execute v_new;
end
$migration$;

comment on function public.gst_document_quote_v520(uuid,text,uuid,uuid,date,text,text,jsonb,numeric,numeric)
is 'GST v5.2 central document quote. review_required/missing GST profiles remain hard compliance blockers and are now surfaced in errors as well as warnings.';