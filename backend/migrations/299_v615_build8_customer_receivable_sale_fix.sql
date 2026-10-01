begin;

insert into public.platform_app_releases(
  id,app_key,platform,version,build_number,status,minimum_supported,mandatory,
  release_notes,download_url,released_at
)
values
(
  gen_random_uuid(),'client','windows','6.1.5',8,'stable',false,false,
  'THQ ERP v6.1.5 Build 8 — Customer Receivable Sale Fix. Named-customer sales may leave unpaid invoice remainder in Accounts Receivable automatically while actual tendered amounts remain the only settled payments. Authoritative GST/accounting writers are unchanged.',
  null,now()
),
(
  gen_random_uuid(),'pos','windows','6.1.5',8,'stable',false,false,
  'THQ ERP v6.1.5 Build 8 — desktop release contract synchronization. No POS transaction-writer change.',
  null,now()
),
(
  gen_random_uuid(),'admin','web','6.1.5',8,'stable',false,false,
  'THQ ERP v6.1.5 Build 8 — desktop release contract synchronization. No Admin feature or transaction-authority change.',
  null,now()
)
on conflict(app_key,platform,version) do update
set build_number=excluded.build_number,
    status=excluded.status,
    minimum_supported=excluded.minimum_supported,
    mandatory=excluded.mandatory,
    release_notes=excluded.release_notes;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  299,'6.1.5-build8',
  'v6.1.5 Build 8 Customer Receivable Sale Fix',
  'Release-metadata checkpoint for named-customer automatic Accounts Receivable remainder handling in Client Sales. No authoritative GST, accounting, stock, payment or transaction writer changes.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
