-- FLEXI ERP V4.4 release registration and capability flags.
begin;

insert into public.platform_app_releases(app_key,platform,version,build_number,status,minimum_supported,mandatory,release_notes)
select x.app_key,x.platform,'4.4.0',1,'stable',false,false,'V4.4 completion: POS hardware/settings + hold/resume, report exports, client invoice designer, admin transaction control, barcode workflows, division overview and responsive cleanup.'
from (values
 ('client','windows'),('client','android'),('client','web'),
 ('pos','windows'),('pos','android'),
 ('admin','web')
) x(app_key,platform)
where not exists(select 1 from public.platform_app_releases r where r.app_key=x.app_key and r.platform=x.platform and r.version='4.4.0' and r.build_number=1);

commit;
select 'Flexi ERP V4.4 release registered' as status;
