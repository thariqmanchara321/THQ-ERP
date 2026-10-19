-- THQ ERP — Live Record Cleanup for TENZO TRADERS (0af96a25-2f04-44e2-a00f-5c4688f34238)
-- Target:
--   Load: LOAD-20261015-000086 (c3dae298-5eb6-42d2-9e46-53fec168683d)
-- Material: METALL
-- Quantity: 150.0 CFT
-- Location: TENZO TRADERS - Main (a5cd9e4d-149f-41fd-8f84-721e51b63993)
-- Financial Status: Uninvoiced (sale_id IS NULL, purchase_id IS NULL, load cost 0.00, customer charges 0.00)
-- Pre-deletion backup archive: backup_tenzo_load_20261015_000086.json

begin;

-- 1. Set platform business delete bypass for this transaction
set local flexi.platform_business_delete = 'true';

-- 2. Verify load is NOT invoiced and has NO posted financial links before proceeding
do $$
declare
  v_load public.aggregate_loads_v617%rowtype;
begin
  select * into v_load
  from public.aggregate_loads_v617
  where id = 'c3dae298-5eb6-42d2-9e46-53fec168683d'
    and tenant_id = '0af96a25-2f04-44e2-a00f-5c4688f34238'
    and load_number = 'LOAD-20261015-000086';

  if not found then
    raise exception 'Target load LOAD-20261015-000086 not found for tenant TENZO TRADERS';
  end if;

  if v_load.sale_id is not null or v_load.purchase_id is not null then
    raise exception 'Refusing deletion: load % is already linked to invoice/sale or purchase (sale_id=%, purchase_id=%)',
      v_load.load_number, v_load.sale_id, v_load.purchase_id;
  end if;
end $$;

-- 3. Record business audit log for the deletion
select private.business_audit_write_v471(
  '0af96a25-2f04-44e2-a00f-5c4688f34238'::uuid,
  'aggregate_load.delete_manual_live',
  'aggregate_load',
  'c3dae298-5eb6-42d2-9e46-53fec168683d'::uuid,
  'LOAD-20261015-000086',
  (select to_jsonb(l) from public.aggregate_loads_v617 l where id = 'c3dae298-5eb6-42d2-9e46-53fec168683d'),
  null::jsonb
);

-- 4. Delete dependent child records
delete from public.material_load_requests_v630
where tenant_id = '0af96a25-2f04-44e2-a00f-5c4688f34238'
  and load_id = 'c3dae298-5eb6-42d2-9e46-53fec168683d';

delete from public.material_load_delivery_v630
where tenant_id = '0af96a25-2f04-44e2-a00f-5c4688f34238'
  and load_id = 'c3dae298-5eb6-42d2-9e46-53fec168683d';

delete from public.aggregate_load_events_v617
where tenant_id = '0af96a25-2f04-44e2-a00f-5c4688f34238'
  and load_id = 'c3dae298-5eb6-42d2-9e46-53fec168683d';

delete from public.transport_trip_hub_v611
where tenant_id = '0af96a25-2f04-44e2-a00f-5c4688f34238'
  and material_load_id = 'c3dae298-5eb6-42d2-9e46-53fec168683d';

-- 5. Delete the aggregate load record
delete from public.aggregate_loads_v617
where tenant_id = '0af96a25-2f04-44e2-a00f-5c4688f34238'
  and id = 'c3dae298-5eb6-42d2-9e46-53fec168683d'
  and load_number = 'LOAD-20261015-000086'
  and sale_id is null
  and purchase_id is null;

commit;
