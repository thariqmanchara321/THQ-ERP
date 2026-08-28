-- THQ ERP V4.7 — release registration and upgrade verification.
begin;

insert into public.platform_app_releases(app_key,platform,version,build_number,status,minimum_supported,mandatory,release_notes)
select x.app_key,x.platform,'4.7.0',1,'stable',false,false,
  'THQ ERP V4.7 Foundation Lock: strict accounting posting, retry-safe transaction requests, installation history/atomic activation, row-locked available-stock enforcement, fail-closed app access and integrity health checks.'
from (values
 ('client','windows'),('client','android'),('client','web'),
 ('pos','windows'),('pos','android'),('admin','web')
) x(app_key,platform)
where not exists(select 1 from public.platform_app_releases r where r.app_key=x.app_key and r.platform=x.platform and r.version='4.7.0' and r.build_number=1);

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(109,'4.7.0','Foundation Lock & Production Stabilization','V4.7 release registered and required database objects verified.')
on conflict(migration_no) do update set notes=excluded.notes;

do $$begin
  if to_regclass('public.transaction_requests_v47') is null then raise exception 'V4.7 transaction request table missing';end if;
  if to_regclass('public.system_installations') is null then raise exception 'V4.7 system installations table missing';end if;
  if to_regprocedure('public.sales_create_v47(uuid,uuid,date,date,jsonb,numeric,numeric,text,text,text,uuid,uuid,text)') is null then raise exception 'V4.7 sales RPC missing';end if;
  if to_regprocedure('public.purchases_create_v47(uuid,uuid,text,date,date,jsonb,numeric,numeric,text,text,uuid,uuid,text)') is null then raise exception 'V4.7 purchase RPC missing';end if;
  if to_regprocedure('public.system_claim_activation_v47(text,text,text,text,text,text,text)') is null then raise exception 'V4.7 activation claim RPC missing';end if;
  if to_regprocedure('public.system_integrity_scan_v47(uuid)') is null then raise exception 'V4.7 integrity scanner missing';end if;
  if (select max(migration_no) from public.thq_schema_releases)<>109 then raise exception 'V4.7 schema release registration incomplete';end if;
end$$;

commit;
select 'THQ ERP V4.7 migrations 101-109 verified' as status;
