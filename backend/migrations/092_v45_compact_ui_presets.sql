-- THQ V4.5
-- Compact information-dense defaults requested for Client and POS while keeping all
-- colors/layout values editable from THQ Admin Design Studio.
begin;

update public.ui_design_templates
set config = config || '{"density":"compact","radius":12,"header_style":"compact","table_style":"compact"}'::jsonb,
    updated_at = now()
where key = 'client_aurora' and app_key = 'client';

update public.ui_design_templates
set config = config || '{"density":"compact","radius":10,"pos_cart_width":340,"header_style":"compact","table_style":"compact","pos_product_style":"solid_tiles"}'::jsonb,
    updated_at = now()
where key = 'pos_aurora_grid' and app_key = 'pos';

insert into public.ui_design_templates(
  key,name,app_key,description,config,is_system,is_default,is_active,sort_order
) values
(
  'client_thq_clean','THQ Clean','client',
  'Compact, aligned THQ workspace optimized for showing more business data without visual clutter.',
  '{"primary":"#4F46E5","secondary":"#A5B4FC","accent":"#6366F1","background":"#F4F6FA","surface":"#FFFFFF","sidebar":"#FFFFFF","border":"#E5E7EB","success":"#15805E","warning":"#C88400","danger":"#C94343","radius":10,"density":"compact","card_style":"bordered","header_style":"compact","sidebar_style":"solid","table_style":"compact","gradient":false}'::jsonb,
  true,false,true,5
),
(
  'pos_thq_cashier','THQ Cashier','pos',
  'Dense two-panel cashier layout with compact controls, high product visibility and fixed checkout actions.',
  '{"primary":"#1F2937","secondary":"#94A3B8","accent":"#4F46E5","background":"#F1F3F6","surface":"#FFFFFF","sidebar":"#FFFFFF","border":"#D9DEE7","success":"#15805E","warning":"#C88400","danger":"#C94343","radius":9,"density":"compact","card_style":"bordered","sidebar_style":"solid","pos_layout":"compact_grid","pos_product_style":"solid_tiles","pos_cart_width":340,"gradient":false}'::jsonb,
  true,false,true,5
)
on conflict(key) do update set
  name=excluded.name,description=excluded.description,config=excluded.config,
  is_active=true,sort_order=excluded.sort_order,updated_at=now();

commit;
select 'THQ V4.5 compact UI presets ready' as status;
