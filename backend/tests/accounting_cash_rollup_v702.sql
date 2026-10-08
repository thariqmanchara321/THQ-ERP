-- Transaction-only fixtures. Rollback restores the real line provider; no financial rows are inserted.
begin;
-- Combined physical cash balance when no individual cash account is selected. Reporting only.
-- Requires both accounting v702 migrations.
create or replace function private.accounting_lines_v702(t uuid,z date,loc uuid) returns setof jsonb language sql stable set search_path='' as $$ select x from jsonb_array_elements('[{"journal_id":"j1","account_id":"00000000-0000-0000-0000-000000000001","date":"2026-10-01","created_at":"2026-10-01T12:00:00Z","reference":"j1","source_type":"fixture","debit":100,"credit":0,"money_method":"cash"},{"journal_id":"j2","account_id":"00000000-0000-0000-0000-000000000002","date":"2026-10-02","created_at":"2026-10-02T12:00:00Z","reference":"j2","source_type":"fixture","debit":50,"credit":0,"money_method":"cash"},{"journal_id":"j3","account_id":"00000000-0000-0000-0000-000000000001","date":"2026-10-03","created_at":"2026-10-03T12:00:00Z","reference":"j3","source_type":"fixture","debit":0,"credit":20,"money_method":"cash"},{"journal_id":"j3","account_id":"00000000-0000-0000-0000-000000000002","date":"2026-10-03","created_at":"2026-10-03T12:00:00Z","reference":"j3","source_type":"fixture","debit":20,"credit":0,"money_method":"cash"},{"journal_id":"j4","account_id":"00000000-0000-0000-0000-000000000002","date":"2026-10-04","created_at":"2026-10-04T12:00:00Z","reference":"j4","source_type":"fixture","debit":0,"credit":10,"money_method":"cash"},{"journal_id":"b1","account_id":"00000000-0000-0000-0000-000000000003","date":"2026-10-01","created_at":"2026-10-01T12:00:00Z","reference":"b1","source_type":"fixture","debit":30,"credit":0,"money_method":"bank"},{"journal_id":"b2","account_id":"00000000-0000-0000-0000-000000000004","date":"2026-10-02","created_at":"2026-10-02T12:00:00Z","reference":"b2","source_type":"fixture","debit":70,"credit":0,"money_method":"bank"}]'::jsonb) x where (x->>'date')::date<=z $$;
do $$ declare rows jsonb;last_balance numeric;begin
select jsonb_agg(x) into rows from private.accounting_rows_v702('00000000-0000-0000-0000-000000000000','cash','2026-10-03','2026-10-04',null,'{}') x;
if jsonb_array_length(rows)<>2 then raise exception 'Cash transfer was not grouped';end if;
if (rows->0->>'opening')::numeric<>150 then raise exception 'Combined opening is incorrect';end if;
if (rows->0->>'balance')::numeric<>150 or (rows->0->>'money_in')::numeric<>0 or (rows->0->>'money_out')::numeric<>0 then raise exception 'Internal cash transfer changed physical balance';end if;
if (rows->1->>'balance')::numeric<>140 then raise exception 'Combined physical cash closing is incorrect';end if;
select jsonb_agg(x) into rows from private.accounting_rows_v702('00000000-0000-0000-0000-000000000000','cash','2026-10-03','2026-10-04',null,'{"account_id":"00000000-0000-0000-0000-000000000001"}') x;
if (rows->0->>'balance')::numeric<>80 then raise exception 'Individual cash account closing is incorrect';end if;
select jsonb_agg(x) into rows from private.accounting_rows_v702('00000000-0000-0000-0000-000000000000','bank','2026-10-01','2026-10-04',null,'{}') x;
if jsonb_array_length(rows)<>2 or (rows->0->>'balance')::numeric<>30 or (rows->1->>'balance')::numeric<>70 then raise exception 'Bank balances must remain account-specific';end if;
end $$;
select '6 cash / bank fixture assertions passed' result;
rollback;
