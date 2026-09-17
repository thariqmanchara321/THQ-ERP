-- THQ ERP v6.1 Logistics POS device enablement
-- Equivalent change is already live on flexi-erp-dev; source-control parity only.

update public.business_devices d
set allowed_modules = (
  select array_agg(distinct x order by x)
  from unnest(coalesce(d.allowed_modules,'{}'::text[]) || array['logistics_operations','vehicle_logistics']) x
), updated_at=now()
where d.app_type='pos'
  and d.status='active'
  and exists(
    select 1 from public.tenant_modules tm
    where tm.tenant_id=d.tenant_id and tm.module_key='logistics_operations' and tm.enabled
  );
