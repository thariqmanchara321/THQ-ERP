-- Rollback-only fixtures: no operational test records are retained.
do $test$
declare
 t uuid:=gen_random_uuid(); usr uuid:=gen_random_uuid(); membership uuid:=gen_random_uuid();
 loc uuid:=gen_random_uuid(); role_id uuid; s uuid; r jsonb; again jsonb; q jsonb;
 payload jsonb; checks jsonb:='{}'; blocked boolean; attendance_before text; loc2 uuid:=gen_random_uuid(); statement jsonb; n int; ehash text; phash text;
begin
 begin
  insert into public.tenants(id,name,slug,business_type) values(t,'Staff separation rollback','staff-separation-rollback-'||t,'material_yard');
  insert into auth.users(id,aud,role,email) values(usr,'authenticated','authenticated','staff-separation-rollback-'||usr||'@example.invalid');
  insert into public.tenant_memberships(id,tenant_id,user_id) values(membership,t,usr);
  select id into role_id from public.roles where tenant_id=t and key='owner' limit 1;
  if role_id is null then insert into public.roles(tenant_id,key,name) values(t,'owner','Owner') returning id into role_id;end if;
  insert into public.role_permissions(role_id,permission_key) select role_id,key from public.permissions on conflict do nothing;
  insert into public.user_roles(tenant_id,membership_id,role_id) values(t,membership,role_id);
  perform set_config('request.jwt.claim.sub',usr::text,true);
  perform private.v47_ensure_accounting_for_tenant(t);
  insert into public.business_locations(id,tenant_id,location_code,name) values(loc,t,'ROLLBACK-'||loc,'Staff rollback location');
  insert into public.tenant_modules(tenant_id,module_key,enabled) values(t,'staff',true) on conflict(tenant_id,module_key) do update set enabled=true;
  r:=public.staff_workspace_v630(t,'save',jsonb_build_object('name','Rollback staff','wage_basis','daily','base_rate',100,'joined_on',current_date-10),loc);
  s:=(r->>'staff_id')::uuid;
  if not exists(select 1 from public.staff_members_v630 where id=s and base_rate=100) then raise exception 'Staff profile save failed';end if;
  checks:=checks||jsonb_build_object('staff_profile_save','PASS');

  insert into public.business_locations(id,tenant_id,location_code,name) values(loc2,t,'SECOND-'||loc2,'Second rollback store');
  perform public.staff_workspace_v630(t,'payroll',jsonb_build_object('staff_id',s,'date',current_date-8,'kind','bonus','units',1,'rate',1000,'request_id',gen_random_uuid()),loc);
  perform public.staff_workspace_v630(t,'payment',jsonb_build_object('staff_id',s,'date',current_date-6,'amount',300,'payment_method','cash','request_id',gen_random_uuid()),loc);
  perform public.staff_workspace_v630(t,'payroll',jsonb_build_object('staff_id',s,'date',current_date-4,'kind','payroll','period_from',current_date-4,'period_to',current_date-4,'units',1,'rate',500,'request_id',gen_random_uuid()),loc);
  perform public.staff_workspace_v630(t,'payment',jsonb_build_object('staff_id',s,'date',current_date-2,'amount',900,'payment_method','bank','reference','BANK-TEST','request_id',gen_random_uuid()),loc);
  perform public.staff_workspace_v630(t,'payment',jsonb_build_object('staff_id',s,'date',current_date+2,'amount',100,'payment_method','cash','request_id',gen_random_uuid()),loc);
  select md5(string_agg(to_jsonb(e)::text,',' order by id)) into ehash from public.staff_earnings_v630 e where tenant_id=t;
  select md5(string_agg(to_jsonb(p)::text,',' order by id)) into phash from public.staff_payments_v630 p where tenant_id=t;
  statement:=public.staff_statement_v634(t,s,current_date-5,current_date-1,loc);
  if not (statement->>'complete')::boolean or (statement->'summary'->>'opening_balance')::numeric<>700 or (statement->'summary'->>'period_earnings')::numeric<>500 or (statement->'summary'->>'period_payments')::numeric<>900 or (statement->'summary'->>'closing_balance')::numeric<>300 then raise exception 'Incorrect dated statement totals: %',statement->'summary';end if;
  if (statement->'summary'->>'current_due')::numeric<>200 or jsonb_array_length(statement->'ledger')<>2 or (statement->'ledger'->0->>'balance')::numeric<>1200 or (statement->'ledger'->1->>'balance')::numeric<>300 then raise exception 'Incorrect running or current balances';end if;
  if (statement->'earnings'->0->>'paid_through_end')::numeric<>200 or jsonb_array_length(statement->'payments'->0->'allocations')<>2 then raise exception 'Future payment leaked into dated payslip or allocations missing';end if;
  if statement->'profile'->>'staff_code' is null or statement->'ledger'->0->>'document_reference'='' then raise exception 'Readable Staff or document reference missing';end if;
  if exists(select 1 from private.reports_rows_v631(t,'staff_earnings',current_date-10,current_date,loc) row where row->>'staff_code' is null) or exists(select 1 from private.reports_rows_v631(t,'staff_payments',current_date-10,current_date,loc) row where row->>'staff_code' is null) then raise exception 'Staff ID missing from shared reports';end if;
  checks:=checks||jsonb_build_object('staff_codes_in_shared_reports','PASS');
  checks:=checks||jsonb_build_object('dated_opening_period_closing','PASS','stable_running_balance','PASS','later_payment_excluded_from_payslip','PASS','readable_staff_and_document_codes','PASS');
  q:=public.staff_statement_v634(t,s,current_date-1,current_date-1,loc);
  if jsonb_array_length(q->'ledger')<>0 or (q->'summary'->>'opening_balance')::numeric<>300 or (q->'summary'->>'closing_balance')::numeric<>300 then raise exception 'Empty period carry-forward failed';end if;
  checks:=checks||jsonb_build_object('empty_period_carries_opening','PASS');
  if ehash<>(select md5(string_agg(to_jsonb(e)::text,',' order by id)) from public.staff_earnings_v630 e where tenant_id=t) or phash<>(select md5(string_agg(to_jsonb(p)::text,',' order by id)) from public.staff_payments_v630 p where tenant_id=t) then raise exception 'Read-only statement modified financial records';end if;
  checks:=checks||jsonb_build_object('statement_read_only','PASS');
  blocked:=false;begin perform public.staff_statement_v634(t,s,current_date-10,current_date,loc2);exception when insufficient_privilege then blocked:=true;end;
  if not blocked then raise exception 'Staff outside selected store accepted';end if;
  update public.staff_members_v630 set location_id=null where id=s and tenant_id=t;
  perform public.staff_workspace_v630(t,'payment',jsonb_build_object('staff_id',s,'date',current_date-3,'amount',400,'payment_method','cash','request_id',gen_random_uuid()),loc2);
  q:=public.staff_statement_v634(t,s,current_date-5,current_date-2,null);
  if (q->'summary'->>'closing_balance')::numeric<>-100 or (q->'summary'->>'closing_due')::numeric<>300 or (q->'summary'->>'closing_advance')::numeric<>400 then raise exception 'Cross-store advance masked a due';end if;
  perform public.staff_workspace_v630(t,'payroll',jsonb_build_object('staff_id',s,'date',current_date-1,'kind','bonus','units',1,'rate',100,'request_id',gen_random_uuid()),loc2);
  q:=public.staff_statement_v634(t,s,current_date-5,current_date-2,null);
  if (select (x->>'advance_remaining_through_end')::numeric from jsonb_array_elements(q->'payments') x where (x->>'advance_amount')::numeric=400)<>400 then raise exception 'Later advance application leaked into old statement';end if;
  q:=public.staff_statement_v634(t,s,current_date-5,current_date-1,null);
  if (select (x->>'advance_remaining_through_end')::numeric from jsonb_array_elements(q->'payments') x where (x->>'advance_amount')::numeric=400)<>300 then raise exception 'Advance application omitted';end if;
  checks:=checks||jsonb_build_object('separate_store_due_and_advance','PASS','advance_application_as_of_end','PASS');
  for n in 1..65 loop
   perform public.staff_workspace_v630(t,'payroll',jsonb_build_object('staff_id',s,'date',current_date,'kind','bonus','units',1,'rate',1,'request_id',gen_random_uuid()),loc);
  end loop;
  q:=public.staff_statement_v634(t,s,current_date,current_date,loc);
  if jsonb_array_length(q->'ledger')<>65 or jsonb_array_length(q->'earnings')<>65 then raise exception 'Statement truncated records';end if;
  checks:=checks||jsonb_build_object('complete_over_50_records','PASS');
  blocked:=false;begin perform public.staff_statement_v634(t,s,current_date,current_date-1,loc);exception when others then blocked:=true;end;
  if not blocked then raise exception 'Invalid statement range accepted';end if;
  blocked:=false;begin perform public.staff_statement_v634(gen_random_uuid(),s,current_date,current_date,loc);exception when insufficient_privilege then blocked:=true;end;
  if not blocked then raise exception 'Cross tenant statement accepted';end if;
  perform set_config('request.jwt.claim.sub','',true);
  blocked:=false;begin perform public.staff_statement_v634(t,s,current_date,current_date,loc);exception when insufficient_privilege then blocked:=true;end;
  if not blocked or has_function_privilege('anon','public.staff_statement_v634(uuid,uuid,date,date,uuid)','execute') then raise exception 'Statement auth or anonymous guard failed';end if;
  checks:=checks||jsonb_build_object('valid_period_and_store_scope','PASS','tenant_auth_and_rpc_acl','PASS');
  raise exception using errcode='ZT001',message='Rollback all Staff statement fixtures';
 exception when sqlstate 'ZT001' then null;end;
 perform set_config('thq_v634_staff_test.result',checks::text,false);
end $test$;
select current_setting('thq_v634_staff_test.result')::jsonb as tests;
