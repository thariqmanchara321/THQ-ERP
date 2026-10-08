-- Add the Staff business code to existing read-only report projections.
-- Guarded edits preserve every other report branch and its access predicates.
do $migration$
declare def text; before_text text; after_text text; definitions jsonb; item jsonb; output jsonb:='[]';
begin
 def:=pg_get_functiondef('private.reports_rows_v631(uuid,text,date,date,uuid)'::regprocedure);
 for before_text,after_text in select * from (values
  ('e.*,m.name staff_name,x.paid_amount','e.*,m.name staff_name,m.staff_code,x.paid_amount'),
  ('p.*,m.name staff_name,l.name location_name','p.*,m.name staff_name,m.staff_code,l.name location_name'),
  ('l.location_id,m.name staff_name','l.location_id,m.name staff_name,m.staff_code')
 ) changes(old_text,new_text) loop
  if position(after_text in def)>0 then continue;end if;
  if position(before_text in def)=0 then raise exception 'Staff report baseline changed; cannot add readable codes safely';end if;
  def:=replace(def,before_text,after_text);
 end loop;
 execute def;
 definitions:=private.reports_definitions_v631();
 for item in select value from jsonb_array_elements(definitions) loop
  if item->>'key' in('staff_earnings','staff_payments','salary_allocations') and not exists(select 1 from jsonb_array_elements(item->'columns') c where c->>'key'='staff_code') then
   item:=jsonb_set(item,'{columns}',jsonb_build_array(jsonb_build_object('key','staff_code','label','Staff ID','type','text','total',false,'width',150))||(item->'columns'));
  end if;
  output:=output||jsonb_build_array(item);
 end loop;
 execute format('create or replace function private.reports_definitions_v631() returns jsonb language sql immutable set search_path=pg_catalog as %L',format('select %L::jsonb',output::text));
end $migration$;
