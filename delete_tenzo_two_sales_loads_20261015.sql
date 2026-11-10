-- THQ ERP — Live Record Cleanup for TENZO TRADERS (0af96a25-2f04-44e2-a00f-5c4688f34238)
-- Deletes two accidental confirmed outbound loads with abnormal dimension calculations (211,548.00 CFT each)
-- Targets:
--   1. LOAD-20261014-000072 (1e0a1262-0898-4447-bbcc-32c2d72bb626)
--   2. LOAD-20261014-000073 (4deee950-3be9-4fd1-bb9f-1a4e232139cd)
-- Neither load has an invoice / sale posted (sale_id is NULL).
-- Pre-deletion backup archive: backup_tenzo_loads_20261015.json

begin;

-- Set platform business delete bypass for this transaction
set local flexi.platform_business_delete = 'true';

-- Record business audit log for each deletion
select private.business_audit_write_v471(
  '0af96a25-2f04-44e2-a00f-5c4688f34238'::uuid,
  'aggregate_load.delete_manual_live',
  'aggregate_load',
  '4deee950-3be9-4fd1-bb9f-1a4e232139cd'::uuid,
  'LOAD-20261014-000073',
  (select to_jsonb(l) from public.aggregate_loads_v617 l where id = '4deee950-3be9-4fd1-bb9f-1a4e232139cd'),
  null::jsonb
);

select private.business_audit_write_v471(
  '0af96a25-2f04-44e2-a00f-5c4688f34238'::uuid,
  'aggregate_load.delete_manual_live',
  'aggregate_load',
  '1e0a1262-0898-4447-bbcc-32c2d72bb626'::uuid,
  'LOAD-20261014-000072',
  (select to_jsonb(l) from public.aggregate_loads_v617 l where id = '1e0a1262-0898-4447-bbcc-32c2d72bb626'),
  null::jsonb
);

-- Delete dependent child rows
delete from public.material_load_requests_v630
where tenant_id = '0af96a25-2f04-44e2-a00f-5c4688f34238'
  and load_id in ('4deee950-3be9-4fd1-bb9f-1a4e232139cd', '1e0a1262-0898-4447-bbcc-32c2d72bb626');

delete from public.material_load_delivery_v630
where tenant_id = '0af96a25-2f04-44e2-a00f-5c4688f34238'
  and load_id in ('4deee950-3be9-4fd1-bb9f-1a4e232139cd', '1e0a1262-0898-4447-bbcc-32c2d72bb626');

delete from public.aggregate_load_events_v617
where tenant_id = '0af96a25-2f04-44e2-a00f-5c4688f34238'
  and load_id in ('4deee950-3be9-4fd1-bb9f-1a4e232139cd', '1e0a1262-0898-4447-bbcc-32c2d72bb626');

delete from public.transport_trip_hub_v611
where tenant_id = '0af96a25-2f04-44e2-a00f-5c4688f34238'
  and material_load_id in ('4deee950-3be9-4fd1-bb9f-1a4e232139cd', '1e0a1262-0898-4447-bbcc-32c2d72bb626');

-- Delete the aggregate loads
delete from public.aggregate_loads_v617
where tenant_id = '0af96a25-2f04-44e2-a00f-5c4688f34238'
  and id in ('4deee950-3be9-4fd1-bb9f-1a4e232139cd', '1e0a1262-0898-4447-bbcc-32c2d72bb626');

commit;
