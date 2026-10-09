-- Run in a trusted SQL test connection after both v702 migrations. No financial records are changed.
begin;
create temp table qa_checks(check_name text,checks integer);
do $$ declare t uuid;u uuid;candidate uuid;a record;p record;r jsonb;s jsonb;expected numeric;found numeric;n integer:=0;begin
for t in select distinct tenant_id from public.journal_entries loop
u:=null;
for candidate in select user_id from public.tenant_memberships where tenant_id=t and status='active' order by user_id loop
 perform set_config('request.jwt.claim.sub',candidate::text,true);
 if private.erp_user_is_owner(t) then u:=candidate;exit;end if;
end loop;
if u is null then raise exception 'Each test tenant requires an active owner';end if;
for a in select id from public.accounting_accounts where tenant_id=t loop
 r:=public.accounting_workspace_v702(t,'general_ledger','2026-10-04','2026-10-08',null,'',jsonb_build_object('account_id',a.id));
 select coalesce(sum(l.debit-l.credit),0) into expected from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id where j.tenant_id=t and l.account_id=a.id and j.entry_date<='2026-10-08' and private.reports_scope_v631(t,j.location_id,null,'view') and (j.status='posted' or j.status='reversed' and exists(select 1 from public.journal_entries rev where rev.tenant_id=t and rev.reversal_of=j.id and rev.status='posted'));
 select (x->>'value')::numeric into found from jsonb_array_elements(r->'summary') x where x->>'label'='Closing balance';
 if expected<>found then raise exception 'Account closing mismatch';end if;n:=n+1;
end loop;
for p in select id,'customers' k from public.customers where tenant_id=t union all select id,'suppliers' from public.suppliers where tenant_id=t loop
 r:=public.accounting_workspace_v702(t,p.k,'2026-10-04','2026-10-08',null,'',jsonb_build_object('party_id',p.id),null,false,0,1000);
 if jsonb_array_length(r->'rows')>0 then
  select (x->>'balance')::numeric into found from jsonb_array_elements(r->'rows') with ordinality arr(x,ord) order by ord desc limit 1;
  select (x->>'value')::numeric into expected from jsonb_array_elements(r->'summary') x where x->>'label'='Closing balance';
  if abs(found-expected)>.005 then raise exception 'Party closing mismatch';end if;
 end if;n:=n+1;
end loop;
r:=public.accounting_workspace_v702(t,'journal','1900-01-01','2026-10-08',null,'','{}',null,false,0,1000);
select count(*) into expected from public.journal_entries j where j.tenant_id=t and j.entry_date<='2026-10-08' and private.reports_scope_v631(t,j.location_id,null,'view');
if (r->>'total_rows')::numeric<>expected then raise exception 'Journal coverage mismatch';end if;n:=n+1;
for a in select x from jsonb_array_elements(r->'rows') x loop
 s:=public.accounting_workspace_v702(t,'journal','1900-01-01','2026-10-08',null,a.x->>'entry_number','{}',null,false,0,1000);
 if not exists(select 1 from jsonb_array_elements(s->'rows') x where x->>'journal_id'=a.x->>'journal_id') then raise exception 'Journal search lost journal';end if;n:=n+1;
end loop;

end loop;
perform set_config('request.jwt.claim.sub','',true);
begin perform public.accounting_workspace_v702(t,'journal','2026-01-01','2026-10-08');raise exception 'Anonymous access was allowed';exception when insufficient_privilege then n:=n+1;end;
perform set_config('request.jwt.claim.sub',u::text,true);
begin perform public.accounting_workspace_v702('00000000-0000-0000-0000-000000000000','journal','2026-01-01','2026-10-08');raise exception 'Invalid tenant access was allowed';exception when insufficient_privilege then n:=n+1;end;
if has_function_privilege('anon','public.accounting_workspace_v702(uuid,text,date,date,uuid,text,jsonb,text,boolean,integer,integer)','execute') then raise exception 'Anonymous execute grant';end if;
if has_function_privilege('authenticated','private.accounting_rows_v702(uuid,text,date,date,uuid,jsonb)','execute') then raise exception 'Private helper exposed';end if;
insert into qa_checks values('Account, party, journal coverage, search and authorization assertions',n+2);
end $$;
select * from qa_checks;
rollback;
