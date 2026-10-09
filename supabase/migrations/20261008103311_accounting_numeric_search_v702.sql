-- Numeric account codes, SKUs and payment references remain searchable alongside exact money values.
create or replace function private.accounting_search_v702(r jsonb,q text) returns boolean
language plpgsql immutable set search_path='' as $$
declare n numeric;clean text:=replace(replace(trim(coalesce(q,'')),',',''),'₹','');
begin
 if trim(coalesce(q,''))='' then return true;end if;
 if clean ~ '^-?[0-9]+(\.[0-9]+)?$' then
  n:=clean::numeric;
  return exists(select 1 from jsonb_path_query(r,'$.** ? (@.type() == "number")') v where v::numeric=n)
   or exists(select 1 from jsonb_path_query(r,'$.** ? (@.type() == "string")') v where strpos(lower(v#>>'{}'),lower(trim(q)))>0);
 end if;
 return strpos(lower(r::text),lower(trim(q)))>0;
end $$;
revoke all on function private.accounting_search_v702(jsonb,text) from public,anon,authenticated;
notify pgrst,'reload schema';
