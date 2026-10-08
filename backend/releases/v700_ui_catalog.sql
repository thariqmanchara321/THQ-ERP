-- THQ 7.0.0 Build 14: additive release/UI catalog data only.
-- Applied to flexi-erp-dev (yguzrxcdvyimjrfvtcvp).
-- No DDL, financial writers, permissions, tenant assignments or mandatory gates change.
-- Existing defaults and saved tenant overrides remain available.
BEGIN;

INSERT INTO public.ui_design_templates
  (key, name, app_key, description, config, is_system, is_default, is_active, sort_order)
VALUES
  ('client_thq_v7', 'THQ V7 Navy & Teal', 'client',
   'Version 7 compact desktop workspace with navy surfaces and teal actions.',
   '{"design_system":"thq_v7","primary":"#22D3B2","secondary":"#78B4FF","accent":"#22D3B2","background":"#0A1725","surface":"#112438","sidebar":"#0E2031","border":"#274057","success":"#22D3B2","warning":"#F4CA7B","danger":"#FF9A9E","text_primary":"#EDF5FA","text_secondary":"#9CB2C4","radius":14,"density":"compact","card_style":"bordered","sidebar_style":"solid","gradient":false,"pos_layout":"retail_grid","pos_product_style":"solid_tiles","pos_cart_width":294}'::jsonb, true, false, true, 7),
  ('pos_thq_v7', 'THQ V7 Compact Cashier', 'pos',
   'Version 7 compact cashier layout with visible selected quantities and responsive invoice review.',
   '{"design_system":"thq_v7","primary":"#22D3B2","secondary":"#78B4FF","accent":"#22D3B2","background":"#0A1725","surface":"#112438","sidebar":"#0E2031","border":"#274057","success":"#22D3B2","warning":"#F4CA7B","danger":"#FF9A9E","text_primary":"#EDF5FA","text_secondary":"#9CB2C4","radius":14,"density":"compact","card_style":"bordered","sidebar_style":"solid","gradient":false,"pos_layout":"retail_grid","pos_product_style":"solid_tiles","pos_cart_width":294}'::jsonb, true, false, true, 7)
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.platform_app_releases
  (app_key, platform, version, build_number, status, minimum_supported, mandatory, release_notes, download_url)
VALUES
  ('client', 'windows', '7.0.0', 14, 'beta', false, false, 'Version 7 navy and teal UI; compact workspaces, responsive tables, reduced-motion controls, shared dialog timing and preserved transaction/auth/offline writers. Build 14. Native Windows and Android verification is required before stable distribution.', NULL),
  ('pos', 'windows', '7.0.0', 14, 'beta', false, false, 'Version 7 navy and teal UI; compact workspaces, responsive tables, reduced-motion controls, shared dialog timing and preserved transaction/auth/offline writers. Build 14. Native Windows and Android verification is required before stable distribution.', NULL),
  ('admin', 'web', '7.0.0', 14, 'beta', false, false, 'Version 7 navy and teal UI; compact workspaces, responsive tables, reduced-motion controls, shared dialog timing and preserved transaction/auth/offline writers. Build 14. Native Windows and Android verification is required before stable distribution.', NULL),
  ('client', 'android', '7.0.0', 14, 'beta', false, false, 'Version 7 navy and teal UI; compact workspaces, responsive tables, reduced-motion controls, shared dialog timing and preserved transaction/auth/offline writers. Build 14. Native Windows and Android verification is required before stable distribution.', NULL),
  ('pos', 'android', '7.0.0', 14, 'beta', false, false, 'Version 7 navy and teal UI; compact workspaces, responsive tables, reduced-motion controls, shared dialog timing and preserved transaction/auth/offline writers. Build 14. Native Windows and Android verification is required before stable distribution.', NULL)
ON CONFLICT (app_key, platform, version) DO NOTHING;

COMMIT;
