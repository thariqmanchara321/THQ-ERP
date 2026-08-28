-- MODULE CATALOG + INDUSTRY TEMPLATES + DEFAULT SUBSCRIPTION PLANS

-- Core/generic modules. Existing rows are updated without deleting tenant configuration.
insert into public.modules (key,name,description,category,is_core,sort_order) values
('dashboard','Dashboard','Business overview','Core',true,10),
('inventory','Inventory','Products, variants, stock ledger and locations','Core',false,20),
('sales','Sales','Sales invoices and customer payments','Core',false,30),
('pos','Point of Sale','Fast counter checkout using the Sales engine','Sales',false,35),
('purchases','Purchases','Supplier purchases and payments','Core',false,40),
('customers','Customers','Customer master and statements','CRM',false,50),
('suppliers','Suppliers','Supplier master and statements','CRM',false,60),
('expenses','Expenses','Business expense capture','Finance',false,70),
('accounting','Accounting','Operational accounting summaries and ledger','Finance',false,80),
('reports','Reports','Business reporting','Analytics',false,90),
('barcode','Barcode','Barcode scanning and labels','Operations',false,100),
('warranty','Warranty','Warranty tracking','Operations',false,110),
('vehicle_compatibility','Vehicle Compatibility','Vehicle-to-part compatibility','Automotive',false,120),
('settings','Business Settings','Tenant business configuration','Core',false,900),
('restaurant','Restaurant','Restaurant menu, table and kitchen extension','Restaurant',false,200),
('restaurant_orders','Restaurant Orders','Dine-in, takeaway and delivery order workflows','Restaurant',false,210),
('workshop','Workshop / Garage','Vehicles, job cards, technicians and estimates','Workshop',false,300),
('healthcare','Clinic / Hospital','Patient, appointment and clinical workflow extension','Healthcare',false,400),
('pharmacy','Pharmacy','Medicine, batch and expiry-oriented inventory extension','Healthcare',false,410),
('lab','Diagnostic Lab','Lab tests, orders, samples, results and reports','Healthcare',false,420)
on conflict (key) do update set
 name=excluded.name,
 description=excluded.description,
 category=excluded.category,
 is_core=excluded.is_core,
 sort_order=excluded.sort_order;

update public.modules set is_active=true where key in (
'dashboard','inventory','sales','pos','purchases','customers','suppliers','expenses','accounting','reports','barcode','warranty','vehicle_compatibility','settings','restaurant','restaurant_orders','workshop','healthcare','pharmacy','lab');

insert into public.module_dependencies(module_key,depends_on_module_key) values
('pos','sales'),('pos','inventory'),('pos','customers'),
('restaurant','pos'),('restaurant','inventory'),('restaurant','purchases'),
('restaurant_orders','restaurant'),('restaurant_orders','sales'),
('workshop','customers'),('workshop','inventory'),('workshop','sales'),
('vehicle_compatibility','inventory'),
('pharmacy','inventory'),('pharmacy','sales'),('pharmacy','purchases'),
('healthcare','customers'),
('lab','healthcare'),('lab','sales')
on conflict do nothing;

insert into public.module_business_types(module_key,business_type) values
('pos','General Retail'),('pos','Grocery'),('pos','Auto Electrical / Spare Parts'),('pos','Restaurant'),('pos','Cafe'),('pos','Pharmacy'),
('restaurant','Restaurant'),('restaurant','Cafe'),('restaurant','Bakery'),
('restaurant_orders','Restaurant'),('restaurant_orders','Cafe'),
('workshop','Workshop / Garage'),('workshop','Auto Service'),
('vehicle_compatibility','Auto Electrical / Spare Parts'),('vehicle_compatibility','Workshop / Garage'),
('healthcare','Clinic'),('healthcare','Hospital'),
('pharmacy','Pharmacy'),('pharmacy','Hospital'),
('lab','Diagnostic Lab'),('lab','Hospital')
on conflict do nothing;

-- Permissions used by the new client surfaces.
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='permissions' and column_name='description') then
    insert into public.permissions(key,name,module_key,description) values
      ('pos.use','Use Point of Sale','pos','Use the POS checkout interface'),
      ('settings.manage','Manage Business Settings','settings','Change tenant-level business settings')
    on conflict (key) do update set name=excluded.name,module_key=excluded.module_key,description=excluded.description;
  else
    insert into public.permissions(key,name,module_key) values
      ('pos.use','Use Point of Sale','pos'),
      ('settings.manage','Manage Business Settings','settings')
    on conflict (key) do update set name=excluded.name,module_key=excluded.module_key;
  end if;
end $$;

-- Existing owners receive new permissions when the relevant module is enabled.
insert into public.role_permissions(role_id,permission_key)
select r.id,p.key
from public.roles r
join public.permissions p on p.key in ('pos.use','settings.manage')
join public.tenant_modules tm on tm.tenant_id=r.tenant_id and tm.module_key=p.module_key and tm.enabled
where r.key='owner'
on conflict do nothing;

-- Templates.
insert into public.business_templates(key,name,business_type,description,is_system,sort_order,settings) values
('general_retail','General Retail','General Retail','Flexible retail/shop configuration',true,10,'{"pos.default_payment_method":"cash"}'::jsonb),
('auto_parts','Auto Electrical / Spare Parts','Auto Electrical / Spare Parts','Parts retail with inventory, purchasing, compatibility and warranty',true,20,'{"pos.default_payment_method":"cash","inventory.allow_negative_stock":false}'::jsonb),
('grocery','Grocery','Grocery','Fast POS and stock-oriented grocery setup',true,30,'{"pos.default_payment_method":"cash"}'::jsonb),
('restaurant','Restaurant / Cafe','Restaurant','Restaurant POS, stock, purchasing and restaurant workflow extensions',true,40,'{"pos.default_payment_method":"cash"}'::jsonb),
('workshop','Workshop / Garage','Workshop / Garage','Vehicle service, parts, job-card and billing-oriented setup',true,50,'{"inventory.allow_negative_stock":false}'::jsonb),
('pharmacy','Pharmacy','Pharmacy','Pharmacy inventory, POS, purchasing and expiry-oriented extension',true,60,'{"inventory.allow_negative_stock":false}'::jsonb),
('clinic','Clinic','Clinic','Patient/appointment-oriented healthcare setup with billing extensions',true,70,'{}'::jsonb),
('hospital','Hospital','Hospital','Healthcare platform configuration with pharmacy/lab extension points',true,80,'{}'::jsonb),
('diagnostic_lab','Diagnostic Lab','Diagnostic Lab','Diagnostic lab workflow with billing, inventory and result extension points',true,90,'{}'::jsonb),
('custom','Custom Business','Custom','Start with a minimal configuration and choose modules manually',true,999,'{}'::jsonb)
on conflict (key) do update set name=excluded.name,business_type=excluded.business_type,description=excluded.description,is_system=true,sort_order=excluded.sort_order,settings=excluded.settings;

-- Reset only system template module links so repeated migration is deterministic.
delete from public.business_template_modules btm
using public.business_templates bt
where bt.id=btm.template_id and bt.is_system=true and bt.key in ('general_retail','auto_parts','grocery','restaurant','workshop','pharmacy','clinic','hospital','diagnostic_lab','custom');

insert into public.business_template_modules(template_id,module_key)
select bt.id,x.module_key from public.business_templates bt join (values
('general_retail','dashboard'),('general_retail','inventory'),('general_retail','sales'),('general_retail','pos'),('general_retail','purchases'),('general_retail','customers'),('general_retail','suppliers'),('general_retail','expenses'),('general_retail','reports'),('general_retail','barcode'),('general_retail','settings'),
('auto_parts','dashboard'),('auto_parts','inventory'),('auto_parts','sales'),('auto_parts','pos'),('auto_parts','purchases'),('auto_parts','customers'),('auto_parts','suppliers'),('auto_parts','expenses'),('auto_parts','accounting'),('auto_parts','reports'),('auto_parts','barcode'),('auto_parts','warranty'),('auto_parts','vehicle_compatibility'),('auto_parts','settings'),
('grocery','dashboard'),('grocery','inventory'),('grocery','sales'),('grocery','pos'),('grocery','purchases'),('grocery','customers'),('grocery','suppliers'),('grocery','expenses'),('grocery','reports'),('grocery','barcode'),('grocery','settings'),
('restaurant','dashboard'),('restaurant','inventory'),('restaurant','sales'),('restaurant','pos'),('restaurant','purchases'),('restaurant','customers'),('restaurant','suppliers'),('restaurant','expenses'),('restaurant','reports'),('restaurant','restaurant'),('restaurant','restaurant_orders'),('restaurant','settings'),
('workshop','dashboard'),('workshop','inventory'),('workshop','sales'),('workshop','purchases'),('workshop','customers'),('workshop','suppliers'),('workshop','expenses'),('workshop','accounting'),('workshop','reports'),('workshop','vehicle_compatibility'),('workshop','workshop'),('workshop','settings'),
('pharmacy','dashboard'),('pharmacy','inventory'),('pharmacy','sales'),('pharmacy','pos'),('pharmacy','purchases'),('pharmacy','customers'),('pharmacy','suppliers'),('pharmacy','expenses'),('pharmacy','reports'),('pharmacy','barcode'),('pharmacy','pharmacy'),('pharmacy','settings'),
('clinic','dashboard'),('clinic','sales'),('clinic','customers'),('clinic','expenses'),('clinic','accounting'),('clinic','reports'),('clinic','healthcare'),('clinic','settings'),
('hospital','dashboard'),('hospital','inventory'),('hospital','sales'),('hospital','purchases'),('hospital','customers'),('hospital','suppliers'),('hospital','expenses'),('hospital','accounting'),('hospital','reports'),('hospital','healthcare'),('hospital','pharmacy'),('hospital','lab'),('hospital','settings'),
('diagnostic_lab','dashboard'),('diagnostic_lab','inventory'),('diagnostic_lab','sales'),('diagnostic_lab','customers'),('diagnostic_lab','expenses'),('diagnostic_lab','accounting'),('diagnostic_lab','reports'),('diagnostic_lab','healthcare'),('diagnostic_lab','lab'),('diagnostic_lab','settings'),
('custom','dashboard'),('custom','settings')
) x(template_key,module_key) on x.template_key=bt.key
on conflict do nothing;

-- Default plans. Prices are editable examples, not hard-coded product policy.
insert into public.subscription_plans(key,name,description,monthly_price,yearly_price,currency_code,is_active,sort_order,limits) values
('trial','Trial','Evaluation plan',0,0,'INR',true,5,'{"max_users":3,"max_locations":1,"max_products":500,"max_invoices_per_month":300}'::jsonb),
('starter','Starter','Small-business essentials',499,4990,'INR',true,10,'{"max_users":5,"max_locations":1,"max_products":3000,"max_invoices_per_month":1500}'::jsonb),
('business','Business','Accounting, reporting and broader operational tools',999,9990,'INR',true,20,'{"max_users":15,"max_locations":3,"max_products":15000,"max_invoices_per_month":10000}'::jsonb),
('professional','Professional','Industry modules and multi-location growth',1999,19990,'INR',true,30,'{"max_users":50,"max_locations":10,"max_products":100000,"max_invoices_per_month":50000}'::jsonb),
('enterprise','Enterprise','Custom limits and enterprise support',0,0,'INR',true,40,'{"max_users":999999,"max_locations":999999,"max_products":999999999,"max_invoices_per_month":999999999}'::jsonb)
on conflict (key) do update set name=excluded.name,description=excluded.description,monthly_price=excluded.monthly_price,yearly_price=excluded.yearly_price,currency_code=excluded.currency_code,is_active=excluded.is_active,sort_order=excluded.sort_order,limits=excluded.limits;

-- Deterministic plan entitlements.
delete from public.subscription_plan_modules spm using public.subscription_plans sp where sp.id=spm.plan_id and sp.key in ('trial','starter','business','professional','enterprise');
insert into public.subscription_plan_modules(plan_id,module_key)
select sp.id,x.module_key from public.subscription_plans sp join (values
('trial','dashboard'),('trial','inventory'),('trial','sales'),('trial','pos'),('trial','purchases'),('trial','customers'),('trial','suppliers'),('trial','expenses'),('trial','reports'),('trial','settings'),
('starter','dashboard'),('starter','inventory'),('starter','sales'),('starter','pos'),('starter','purchases'),('starter','customers'),('starter','suppliers'),('starter','expenses'),('starter','reports'),('starter','barcode'),('starter','settings'),
('business','dashboard'),('business','inventory'),('business','sales'),('business','pos'),('business','purchases'),('business','customers'),('business','suppliers'),('business','expenses'),('business','accounting'),('business','reports'),('business','barcode'),('business','warranty'),('business','vehicle_compatibility'),('business','settings'),
('professional','dashboard'),('professional','inventory'),('professional','sales'),('professional','pos'),('professional','purchases'),('professional','customers'),('professional','suppliers'),('professional','expenses'),('professional','accounting'),('professional','reports'),('professional','barcode'),('professional','warranty'),('professional','vehicle_compatibility'),('professional','restaurant'),('professional','restaurant_orders'),('professional','workshop'),('professional','healthcare'),('professional','pharmacy'),('professional','lab'),('professional','settings'),
('enterprise','dashboard'),('enterprise','inventory'),('enterprise','sales'),('enterprise','pos'),('enterprise','purchases'),('enterprise','customers'),('enterprise','suppliers'),('enterprise','expenses'),('enterprise','accounting'),('enterprise','reports'),('enterprise','barcode'),('enterprise','warranty'),('enterprise','vehicle_compatibility'),('enterprise','restaurant'),('enterprise','restaurant_orders'),('enterprise','workshop'),('enterprise','healthcare'),('enterprise','pharmacy'),('enterprise','lab'),('enterprise','settings')
) x(plan_key,module_key) on x.plan_key=sp.key
on conflict do nothing;

insert into public.platform_settings(key,value,description) values
('default_currency','"INR"'::jsonb,'Default currency for new tenants'),
('default_timezone','"Asia/Kolkata"'::jsonb,'Default timezone for new tenants'),
('default_locale','"en_IN"'::jsonb,'Default locale for new tenants'),
('maintenance_mode','false'::jsonb,'Platform-wide maintenance switch'),
('trial_days','14'::jsonb,'Default trial duration in days'),
('support_email','""'::jsonb,'Support contact displayed by clients')
on conflict (key) do nothing;

-- Cashier is a sensible default POS role when POS is already enabled.
insert into public.role_permissions(role_id,permission_key)
select r.id,'pos.use'
from public.roles r
join public.tenant_modules tm on tm.tenant_id=r.tenant_id and tm.module_key='pos' and tm.enabled
where r.key='cashier'
on conflict do nothing;
