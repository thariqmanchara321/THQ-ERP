begin;

-- THQ ERP v6.2.4 Build 9 - Mobile Production Polish.
-- Release registry synchronization only for both Android mobile applications.
-- No GST, accounting, inventory, sales, purchase, return, payment, offline,
-- cashier, restaurant or logistics writer behavior is changed.

insert into public.platform_app_releases(
  id, app_key, platform, version, build_number, status,
  minimum_supported, mandatory, release_notes, download_url, released_at
)
values
(
  gen_random_uuid(),'client','android','6.2.4',9,'stable',false,false,
  'THQ ERP v6.2.4 Build 9 - Mobile Production Polish. Finalizes shared mobile responsive framing, accessibility-safe text scaling, system navigation polish, compact release awareness and smoke-test coverage. No transaction writer behavior changes.',
  null,now()
),
(
  gen_random_uuid(),'pos','android','6.2.4',9,'stable',false,false,
  'THQ ERP v6.2.4 Build 9 - Mobile Production Polish. Finalizes shared mobile responsive framing, accessibility-safe text scaling, system navigation polish, compact release awareness and smoke-test coverage. Existing v5.2 authoritative GST and offline transaction authority remain unchanged.',
  null,now()
)
on conflict(app_key,platform,version) do update
set build_number=excluded.build_number,
    status=excluded.status,
    minimum_supported=excluded.minimum_supported,
    mandatory=excluded.mandatory,
    release_notes=excluded.release_notes;

insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  291,
  '6.2.4-build9',
  'v6.2.4 Build 9 Mobile Production Polish',
  'Release registry checkpoint for Client Mobile and Mobile POS production polish. No authoritative GST, accounting, stock, sales, purchase, payment, offline, cashier, restaurant or logistics writer behavior changes.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
