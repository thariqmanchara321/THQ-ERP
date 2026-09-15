-- THQ ERP v6.1 - Vehicle Logistics as a separate client module.
-- Already live on flexi-erp-dev as v610_vehicle_logistics_separate_client_module.

insert into public.modules(
  key,name,description,category,is_core,sort_order,is_active,is_beta,
  requires_configuration,minimum_plan_key
)
values(
  'vehicle_logistics',
  'Vehicle Logistics',
  'Vehicle fleet and physical stock movement trips linked to authoritative stock transfers',
  'Inventory',
  false,
  515,
  true,
  false,
  false,
  null
)
on conflict (key) do update set
  name=excluded.name,
  description=excluded.description,
  category=excluded.category,
  sort_order=excluded.sort_order,
  is_active=true,
  is_beta=false,
  requires_configuration=false;

insert into public.tenant_modules(
  tenant_id,module_key,enabled,config,created_at,updated_at
)
select tm.tenant_id,'vehicle_logistics',tm.enabled,tm.config,now(),now()
from public.tenant_modules tm
where tm.module_key='transport_service'
on conflict (tenant_id,module_key) do nothing;

insert into public.subscription_plan_modules(plan_id,module_key)
select spm.plan_id,'vehicle_logistics'
from public.subscription_plan_modules spm
where spm.module_key='transport_service'
on conflict (plan_id,module_key) do nothing;

insert into public.business_template_modules(template_id,module_key)
select btm.template_id,'vehicle_logistics'
from public.business_template_modules btm
where btm.module_key='transport_service'
on conflict (template_id,module_key) do nothing;

insert into public.module_business_types(module_key,business_type)
select 'vehicle_logistics',mbt.business_type
from public.module_business_types mbt
where mbt.module_key='transport_service'
on conflict do nothing;

insert into public.module_dependencies(module_key,depends_on_module_key)
values ('vehicle_logistics','stock_transfers')
on conflict do nothing;

do $$
declare
  v_parent_id uuid;
begin
  select id into v_parent_id
  from public.app_menu_nodes_v45
  where tenant_id is null
    and app_key='client'
    and node_key='operations'
    and node_type='group'
  limit 1;

  if v_parent_id is null then
    raise exception 'Client Operations menu group was not found';
  end if;

  update public.app_menu_nodes_v45
  set module_key='vehicle_logistics',
      parent_id=v_parent_id,
      label='Vehicle Logistics',
      icon_key='logistics',
      sort_order=55,
      enabled=true,
      updated_at=now()
  where tenant_id is null
    and app_key='client'
    and node_key='vehicle_logistics';

  if not found then
    insert into public.app_menu_nodes_v45(
      tenant_id,app_key,node_key,node_type,module_key,parent_id,label,
      icon_key,sort_order,enabled,collapsed_by_default,metadata
    ) values (
      null,'client','vehicle_logistics','module','vehicle_logistics',
      v_parent_id,'Vehicle Logistics','logistics',55,true,false,'{}'::jsonb
    );
  end if;
end $$;
