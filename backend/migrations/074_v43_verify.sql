-- Flexi ERP V4.3 design-system verification.
do $$
begin
  if to_regclass('public.ui_design_templates') is null then raise exception 'Missing ui_design_templates'; end if;
  if to_regclass('public.tenant_ui_designs') is null then raise exception 'Missing tenant_ui_designs'; end if;
  if to_regprocedure('public.platform_ui_design_templates_list_v43(text)') is null then raise exception 'Missing platform_ui_design_templates_list_v43'; end if;
  if to_regprocedure('public.platform_ui_design_template_upsert_v43(uuid,text,text,text,text,jsonb,boolean,boolean,integer)') is null then raise exception 'Missing platform_ui_design_template_upsert_v43'; end if;
  if to_regprocedure('public.platform_tenant_ui_design_set_v43(uuid,text,uuid,jsonb)') is null then raise exception 'Missing platform_tenant_ui_design_set_v43'; end if;
  if to_regprocedure('public.tenant_ui_design_get_v43(uuid,text)') is null then raise exception 'Missing tenant_ui_design_get_v43'; end if;
  if (select count(*) from public.ui_design_templates where app_key='client' and is_active) < 4 then raise exception 'Client design templates missing'; end if;
  if (select count(*) from public.ui_design_templates where app_key='pos' and is_active) < 4 then raise exception 'POS design templates missing'; end if;
  raise notice 'Flexi ERP V4.3 UI design system verification passed';
end $$;
