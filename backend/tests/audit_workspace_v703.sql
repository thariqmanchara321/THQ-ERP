-- Read-only financial assertions; claims and temporary test output roll back.
begin;
create temp table audit_qa(check_name text, assertions integer);
do $$
declare t uuid;u uuid;candidate uuid;r jsonb;s jsonb;a record;doc record;m text;expected numeric;actual numeric;n integer:=0; f date:='2026-09-01';z date:='2026-10-09';foreign_location uuid;begin
for t in select distinct tenant_id from public.journal_entries loop
 u:=null;
 for candidate in select user_id from public.tenant_memberships where tenant_id=t and status='active' loop
  perform set_config('request.jwt.claim.sub',candidate::text,true);
  if private.erp_user_is_owner(t) then u:=candidate;exit;end if;
 end loop;
 if u is null then raise exception 'No active owner for test tenant';end if;
 r:=public.audit_workspace_page_v703(t,'accounts',f,z,null,'','','','account_name',false,0,200,'');
 select count(*) into expected from public.accounting_accounts where tenant_id=t;
 if (r->>'total_rows')::numeric<>expected then raise exception 'Account coverage mismatch';end if;n:=n+1;
 for a in select id from public.accounting_accounts where tenant_id=t loop
  s:=public.audit_ledger_v703(t,a.id,f,z);
  select coalesce(sum(l.debit-l.credit),0) into expected from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id where j.tenant_id=t and l.account_id=a.id and j.entry_date<=z and private.reports_scope_v631(t,j.location_id,null,'view') and (j.status='posted' or j.status='reversed' and exists(select 1 from public.journal_entries rev where rev.tenant_id=t and rev.reversal_of=j.id and rev.status='posted'));
  if (s->>'closing')::numeric<>expected then raise exception 'Account closing mismatch';end if;
  select (x->>'closing')::numeric into actual from jsonb_array_elements(r->'rows') x where x->>'account_id'=a.id::text;
  if actual is distinct from expected then raise exception 'Account table differs from ledger';end if;n:=n+2;
 end loop;
 r:=public.audit_workspace_page_v703(t,'journals','1900-01-01',z,null,'','','','date',true,0,200,'');
 select count(*) into expected from public.journal_entries j where tenant_id=t and entry_date<=z and private.reports_scope_v631(t,j.location_id,null,'view');
 if (r->>'total_rows')::numeric<>expected then raise exception 'Journal source coverage mismatch';end if;n:=n+1;
 for doc in select id,source_type from public.journal_entries where tenant_id=t and entry_date<=z loop
  s:=public.audit_journal_v703(t,doc.id);
  if s->>'id'<>doc.id::text then raise exception 'Journal link lost';end if;
  r:=public.audit_workspace_page_v703(t,'journals','1900-01-01',z,null,'','','','date',true,0,200,doc.source_type);
  if doc.source_type is not null and exists(select 1 from jsonb_array_elements(r->'rows') x where x->>'source_type'<>doc.source_type) then raise exception 'Source filter leaked another source';end if;
  r:=public.transaction_explain_v600(t,'journal_entry',doc.id);
  if not exists(select 1 from jsonb_array_elements(r->'journals') x where x->>'id'=doc.id::text) then raise exception 'Story lost requested journal';end if;
  n:=n+3;
 end loop;
 for m in select unnest(array['sales','cogs','gross_profit','net_profit','inventory_value','receivables','payables','cash','bank','upi','card','gst_payable']) loop
  r:=public.explain_metric_v703(t,m,f,z);
  select coalesce(sum((x->>'value')::numeric),0) into expected from jsonb_array_elements(r->'components') x;
  if expected<>(r->>'value')::numeric then raise exception 'Metric account contribution mismatch: %',m;end if;
  if not (r#>>'{driver_reconciliation,reconciles}')::boolean then raise exception 'Source bridge mismatch: %',m;end if;
  if (r->>'value')::numeric-(r#>>'{previous,value}')::numeric<>(r->>'change')::numeric then raise exception 'Period change mismatch';end if;n:=n+3;
 end loop;
 r:=public.accounting_workspace_v702(t,'profit_loss',f,z);
 select (x->>'value')::numeric into expected from jsonb_array_elements(r->'summary') x where x->>'label'='Net Profit';
 s:=public.explain_metric_v703(t,'net_profit',f,z);
 if expected<>(s->>'value')::numeric then raise exception 'Audit and accounting net profit differ';end if;n:=n+1;
 r:=public.audit_workspace_page_v703(t,'findings','1900-01-01',z,null,'','','','date',true,0,200,'');
 for a in select x from jsonb_array_elements(r->'rows') x loop
  if a.x->>'id' is distinct from a.x->>'finding_id' then raise exception 'Finding contract ID mismatch';end if;
  s:=public.audit_finding_detail_v600(t,(a.x->>'id')::uuid);
  if s#>>'{finding,id}'<>a.x->>'id' then raise exception 'Finding detail link broken';end if;n:=n+2;
 end loop;
 r:=public.audit_workspace_page_v703(t,'activity','1900-01-01',z);
 if r->>'snapshot_token' is null then raise exception 'Export snapshot missing';end if;n:=n+1;
 select id into foreign_location from public.business_locations where tenant_id<>t limit 1;
 if foreign_location is not null then
  begin perform public.audit_workspace_page_v703(t,'accounts',f,z,foreign_location);raise exception 'Foreign store was allowed';exception when insufficient_privilege then n:=n+1;end;
 end if;
end loop;
perform set_config('request.jwt.claim.sub','',true);
begin perform public.audit_workspace_page_v703(t,'accounts',f,z);raise exception 'Anonymous access was allowed';exception when insufficient_privilege then n:=n+1;end;
perform set_config('request.jwt.claim.sub',u::text,true);
begin perform public.audit_workspace_page_v703('00000000-0000-0000-0000-000000000000','accounts',f,z);raise exception 'Foreign tenant was allowed';exception when insufficient_privilege then n:=n+1;end;
if has_function_privilege('anon','public.audit_workspace_page_v703(uuid,text,date,date,uuid,text,text,text,text,boolean,integer,integer,text)','execute') then raise exception 'Anonymous execute grant';end if;n:=n+1;
insert into audit_qa values('Account totals, ledger links, all journal sources, stories, metric bridges, finding IDs, export snapshots and tenant/store access',n);
end $$;
select * from audit_qa;
rollback;
