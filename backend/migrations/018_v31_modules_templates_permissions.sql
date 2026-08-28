-- Flexi ERP V3.1 - module catalog, permissions, industry templates
begin;

insert into public.modules(key,name,description,category,is_core,sort_order) values
('locations','Locations / Branches','Child stores, branches and reporting locations','Platform',false,130),
('production','Production','Recipes/BOM, raw-material consumption and finished-goods production','Manufacturing',false,500),
('transport_service','Transport Service','Taxi/truck vehicles, trips, quantities, distance and linked billing','Service',false,520),
('payments','Payments','Receivables and payables center','Finance',false,95),
('bulk_import','Bulk Import','Bulk products, customers and suppliers import','Operations',false,105),
('logs','Logs & Issues','Application errors, issues and audit activity','Platform',false,910),
('invoice_templates','Invoice Templates','Business invoice template assignment and preview','Platform',false,920)
on conflict(key) do update set name=excluded.name,description=excluded.description,category=excluded.category,is_core=excluded.is_core,sort_order=excluded.sort_order;

update public.modules set is_active=true where key in ('locations','production','transport_service','payments','bulk_import','logs','invoice_templates');

insert into public.module_dependencies(module_key,depends_on_module_key) values
('production','inventory'),('production','purchases'),
('transport_service','customers'),('transport_service','sales'),
('restaurant','pos'),('restaurant','inventory'),('restaurant','purchases'),
('restaurant_orders','restaurant'),('restaurant_orders','sales'),
('bulk_import','inventory'),('payments','sales')
on conflict do nothing;

insert into public.module_business_types(module_key,business_type) values
('production','Manufacturing'),('production','Production'),('production','Bakery'),
('transport_service','Taxi / Transport'),('transport_service','Logistics'),('transport_service','Truck / Fleet'),
('locations','General Retail'),('locations','Restaurant'),('locations','Manufacturing'),('locations','Taxi / Transport')
on conflict do nothing;

do $$ begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='permissions' and column_name='description') then
    insert into public.permissions(key,name,module_key,description) values
    ('locations.view','View Locations','locations','View branches/child stores'),
    ('locations.manage','Manage Locations','locations','Create/change branches and child stores'),
    ('production.view','View Production','production','View recipes and production runs'),
    ('production.manage','Manage Production','production','Create/edit recipes and raw-material definitions'),
    ('production.run','Run Production','production','Post production runs and stock changes'),
    ('transport_service.view','View Transport Service','transport_service','View vehicles and service jobs'),
    ('transport_service.create','Create Transport Service Jobs','transport_service','Record taxi/truck jobs and trips'),
    ('transport_service.manage','Manage Transport Service','transport_service','Manage vehicles and service jobs'),
    ('restaurant.view','View Restaurant','restaurant','View tables/orders/KOT'),
    ('restaurant.order','Create Restaurant Orders','restaurant','Create dine-in/takeaway/delivery orders'),
    ('restaurant.kot','Send KOT','restaurant','Send kitchen order tickets'),
    ('restaurant.manage','Manage Restaurant','restaurant','Manage tables and order status'),
    ('sales.edit','Edit Sale Metadata','sales','Edit allowed fields on posted sales with audit'),
    ('sales.view_profit','View Sales Profit','sales','View cost and gross-profit information'),
    ('expenses.edit','Edit Expenses','expenses','Edit expenses with audit trail'),
    ('payments.view','View Pending Payments','payments','View receivables/payables'),
    ('payments.receive','Receive Customer Payments','payments','Receive outstanding customer payments'),
    ('bulk_import.use','Use Bulk Import','bulk_import','Import business masters in bulk'),
    ('logs.view','View Logs','logs','View tenant error and activity logs')
    on conflict(key) do update set name=excluded.name,module_key=excluded.module_key,description=excluded.description;
  else
    insert into public.permissions(key,name,module_key) values
    ('locations.view','View Locations','locations'),('locations.manage','Manage Locations','locations'),
    ('production.view','View Production','production'),('production.manage','Manage Production','production'),('production.run','Run Production','production'),
    ('transport_service.view','View Transport Service','transport_service'),('transport_service.create','Create Transport Service Jobs','transport_service'),('transport_service.manage','Manage Transport Service','transport_service'),
    ('restaurant.view','View Restaurant','restaurant'),('restaurant.order','Create Restaurant Orders','restaurant'),('restaurant.kot','Send KOT','restaurant'),('restaurant.manage','Manage Restaurant','restaurant'),
    ('sales.edit','Edit Sale Metadata','sales'),('sales.view_profit','View Sales Profit','sales'),('expenses.edit','Edit Expenses','expenses'),
    ('payments.view','View Pending Payments','payments'),('payments.receive','Receive Customer Payments','payments'),('bulk_import.use','Use Bulk Import','bulk_import'),('logs.view','View Logs','logs')
    on conflict(key) do update set name=excluded.name,module_key=excluded.module_key;
  end if;
end $$;

-- Owners get every permission that belongs to an enabled module.
insert into public.role_permissions(role_id,permission_key)
select r.id,p.key
from public.roles r
join public.tenant_modules tm on tm.tenant_id=r.tenant_id and tm.enabled
join public.permissions p on p.module_key=tm.module_key
where r.key='owner'
on conflict do nothing;

-- Sensible restaurant/POS defaults for cashier where modules are enabled.
insert into public.role_permissions(role_id,permission_key)
select r.id,p.key
from public.roles r
join public.tenant_modules tm on tm.tenant_id=r.tenant_id and tm.enabled
join public.permissions p on p.key in ('pos.use','restaurant.view','restaurant.order','restaurant.kot') and p.module_key=tm.module_key
where r.key='cashier'
on conflict do nothing;

insert into public.business_templates(key,name,business_type,description,is_system,sort_order,settings) values
('manufacturing','Production / Manufacturing','Manufacturing','Raw materials, recipes/BOM, production runs, finished stock and finance',true,100,'{"inventory.allow_negative_stock":false}'::jsonb),
('transport','Taxi / Truck / Transport','Taxi / Transport','Vehicles, service trips, distance/quantity billing and finance',true,110,'{}'::jsonb)
on conflict(key) do update set name=excluded.name,business_type=excluded.business_type,description=excluded.description,is_system=true,sort_order=excluded.sort_order,settings=excluded.settings;

delete from public.business_template_modules btm using public.business_templates bt
where bt.id=btm.template_id and bt.key in ('manufacturing','transport');

insert into public.business_template_modules(template_id,module_key)
select bt.id,x.module_key from public.business_templates bt join (values
('manufacturing','dashboard'),('manufacturing','inventory'),('manufacturing','purchases'),('manufacturing','suppliers'),('manufacturing','production'),('manufacturing','sales'),('manufacturing','customers'),('manufacturing','expenses'),('manufacturing','accounting'),('manufacturing','reports'),('manufacturing','payments'),('manufacturing','bulk_import'),('manufacturing','logs'),('manufacturing','settings'),
('transport','dashboard'),('transport','sales'),('transport','customers'),('transport','transport_service'),('transport','expenses'),('transport','accounting'),('transport','reports'),('transport','payments'),('transport','logs'),('transport','settings')
) x(template_key,module_key) on x.template_key=bt.key
on conflict do nothing;

-- Upgrade Restaurant template to real order/KOT workflow plus payment/log tools.
insert into public.business_template_modules(template_id,module_key)
select bt.id,x.module_key from public.business_templates bt cross join lateral (values ('payments'),('logs'),('invoice_templates')) x(module_key)
where bt.key='restaurant' on conflict do nothing;

-- Add advanced modules to Professional/Enterprise plans when such plans exist.
insert into public.subscription_plan_modules(plan_id,module_key)
select sp.id,m.key from public.subscription_plans sp cross join public.modules m
where sp.key in ('professional','enterprise') and m.key in ('locations','production','transport_service','restaurant','restaurant_orders','payments','bulk_import','logs','invoice_templates')
on conflict do nothing;

commit;
