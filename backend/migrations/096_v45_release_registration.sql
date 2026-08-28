-- THQ V4.5 release registration.
begin;

insert into public.platform_app_releases(app_key,platform,version,build_number,status,minimum_supported,mandatory,release_notes)
select x.app_key,x.platform,'4.5.0',1,'stable',false,false,
  'THQ V4.5: compact POS and Client UX, held-sale resume, three-action payment flow, Terminal Daily Day Close, sale/purchase returns integration, return-aware analytics, Excel product import, advanced client invoice designer, hierarchical Admin menu builder and audited transaction/payment corrections.'
from (values
 ('client','windows'),('client','android'),('client','web'),
 ('pos','windows'),('pos','android'),
 ('admin','web')
) x(app_key,platform)
where not exists(
  select 1 from public.platform_app_releases r
  where r.app_key=x.app_key and r.platform=x.platform and r.version='4.5.0' and r.build_number=1
);

commit;
select 'THQ V4.5 release registered' as status;
