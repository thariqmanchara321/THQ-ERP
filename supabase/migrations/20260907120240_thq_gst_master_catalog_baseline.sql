-- =====================================================================
-- THQ ERP GST GLOBAL MASTER CATALOG
-- Production snapshot: 2026-09-07
--
-- Contains ONLY:
--   gst_state_master_v520
--   gst_tax_rate_master_v520
--   gst_policy_rules_v520
--
-- No tenant, user, transaction or GST document data.
-- =====================================================================
--
-- PostgreSQL database dump
--

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: gst_policy_rules_v520; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.gst_policy_rules_v520 (id, rule_key, effective_from, effective_to, rule_value, source_note, active, created_at, updated_at) VALUES ('89cf4feb-cc3c-4ce2-85a2-dd2190de7635', 'einvoice_aato_threshold_crore', '2023-08-01', NULL, '5', 'Notification 10/2023-CT; applicability must still be confirmed for the taxpayer', true, '2026-08-30 21:20:21.649139+00', '2026-08-30 21:20:21.649139+00');
INSERT INTO public.gst_policy_rules_v520 (id, rule_key, effective_from, effective_to, rule_value, source_note, active, created_at, updated_at) VALUES ('b24ef6f2-d21a-4792-8978-982ff8de1106', 'einvoice_reporting_window', '2025-04-01', NULL, '{"days": 30, "aato_crore": 10}', 'IRP 30-day reporting restriction effective 01-Apr-2025', true, '2026-08-30 21:20:21.649139+00', '2026-08-30 21:20:21.649139+00');
INSERT INTO public.gst_policy_rules_v520 (id, rule_key, effective_from, effective_to, rule_value, source_note, active, created_at, updated_at) VALUES ('f50e1402-8c4c-4208-8015-6c6d3c0af359', 'einvoice_rate_master_revision', '2025-09-21', NULL, '{"added_rate": 40}', 'IRP production release 21-Sep-2025', true, '2026-08-30 21:20:21.649139+00', '2026-08-30 21:20:21.649139+00');
INSERT INTO public.gst_policy_rules_v520 (id, rule_key, effective_from, effective_to, rule_value, source_note, active, created_at, updated_at) VALUES ('cf660863-986e-4e03-8f5b-d7faf9344b47', 'einvoice_rsp_totitem_relaxation', '2026-02-01', NULL, '{"enabled": true}', 'IRP production release 01-Feb-2026; HSN/RSP applicability required', true, '2026-08-30 21:20:21.649139+00', '2026-08-30 21:20:21.649139+00');
INSERT INTO public.gst_policy_rules_v520 (id, rule_key, effective_from, effective_to, rule_value, source_note, active, created_at, updated_at) VALUES ('49288f99-f765-454a-85f6-40e36dd0c3a1', 'ewaybill_document_age_limit', '2025-03-17', NULL, '{"days": 180}', 'IRP/E-Way Bill validation release; provider rules remain authoritative • Superseded by corrected effective date 01-Jan-2025', false, '2026-08-30 21:20:21.649139+00', '2026-08-30 21:35:22.334066+00');
INSERT INTO public.gst_policy_rules_v520 (id, rule_key, effective_from, effective_to, rule_value, source_note, active, created_at, updated_at) VALUES ('8f219131-b5a8-4ab1-9268-101636798193', 'ewaybill_document_age_limit', '2025-01-01', NULL, '{"days": 180}', 'E-Way Bill validation: document date cannot be older than 180 days at generation, effective 01-Jan-2025', true, '2026-08-30 21:35:22.334066+00', '2026-08-30 21:35:22.334066+00');
INSERT INTO public.gst_policy_rules_v520 (id, rule_key, effective_from, effective_to, rule_value, source_note, active, created_at, updated_at) VALUES ('21743b0c-75ad-4f47-ada6-6d13c3ea7803', 'ewaybill_extension_limit', '2025-01-01', NULL, '{"days": 360}', 'E-Way Bill validation: extension cannot exceed 360 days from generation, effective 01-Jan-2025', true, '2026-08-30 21:35:22.334066+00', '2026-08-30 21:35:22.334066+00');


--
-- Data for Name: gst_state_master_v520; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('01', 'Jammu and Kashmir', false, false, true, '2017-07-01', NULL, '["Jammu & Kashmir", "J&K"]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('02', 'Himachal Pradesh', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('03', 'Punjab', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('04', 'Chandigarh', true, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', true);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('05', 'Uttarakhand', false, false, true, '2017-07-01', NULL, '["Uttaranchal"]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('06', 'Haryana', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('07', 'Delhi', true, false, true, '2017-07-01', NULL, '["NCT of Delhi", "New Delhi"]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('08', 'Rajasthan', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('09', 'Uttar Pradesh', false, false, true, '2017-07-01', NULL, '["UP"]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('10', 'Bihar', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('11', 'Sikkim', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('12', 'Arunachal Pradesh', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('13', 'Nagaland', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('14', 'Manipur', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('15', 'Mizoram', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('16', 'Tripura', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('17', 'Meghalaya', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('18', 'Assam', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('19', 'West Bengal', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('20', 'Jharkhand', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('21', 'Odisha', false, false, true, '2017-07-01', NULL, '["Orissa"]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('22', 'Chhattisgarh', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('23', 'Madhya Pradesh', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('24', 'Gujarat', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('25', 'Daman and Diu (legacy)', true, false, false, '2017-07-01', NULL, '["Daman & Diu"]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('26', 'Dadra and Nagar Haveli and Daman and Diu', true, false, true, '2020-08-01', NULL, '["Dadra & Nagar Haveli and Daman & Diu", "DNHDD"]', '2026-08-30 21:35:22.334066+00', true);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('27', 'Maharashtra', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('28', 'Andhra Pradesh (legacy code)', false, false, false, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('29', 'Karnataka', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('30', 'Goa', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('31', 'Lakshadweep', true, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', true);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('32', 'Kerala', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('33', 'Tamil Nadu', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('34', 'Puducherry', true, false, true, '2017-07-01', NULL, '["Pondicherry"]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('35', 'Andaman and Nicobar Islands', true, false, true, '2017-07-01', NULL, '["Andaman & Nicobar Islands"]', '2026-08-30 21:35:22.334066+00', true);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('36', 'Telangana', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('37', 'Andhra Pradesh', false, false, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('38', 'Ladakh', true, false, true, '2020-01-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', true);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('96', 'Foreign Country', false, true, true, '2017-07-01', NULL, '["Other Country", "Export"]', '2026-08-30 21:35:22.334066+00', false);
INSERT INTO public.gst_state_master_v520 (code, name, is_union_territory, is_special_code, active, valid_from, valid_to, aliases, updated_at, uses_utgst) VALUES ('97', 'Other Territory', false, true, true, '2017-07-01', NULL, '[]', '2026-08-30 21:35:22.334066+00', false);


--
-- Data for Name: gst_tax_rate_master_v520; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.gst_tax_rate_master_v520 (id, rate, label, effective_from, effective_to, active, source_note, created_at) VALUES ('033e0df1-45ac-4064-b3bd-afd430ba4a77', 0.000, '0%', '2017-07-01', NULL, true, 'GST/IRP rate master', '2026-08-30 21:20:21.649139+00');
INSERT INTO public.gst_tax_rate_master_v520 (id, rate, label, effective_from, effective_to, active, source_note, created_at) VALUES ('f7eb9d1b-ccfb-4180-a7e4-a6521423acb5', 0.100, '0.1%', '2017-07-01', NULL, true, 'GST/IRP rate master', '2026-08-30 21:20:21.649139+00');
INSERT INTO public.gst_tax_rate_master_v520 (id, rate, label, effective_from, effective_to, active, source_note, created_at) VALUES ('dbe37245-9299-4e63-904e-ef51cf2aaaba', 0.250, '0.25%', '2017-07-01', NULL, true, 'GST/IRP rate master', '2026-08-30 21:20:21.649139+00');
INSERT INTO public.gst_tax_rate_master_v520 (id, rate, label, effective_from, effective_to, active, source_note, created_at) VALUES ('ea1576da-cb88-4bd9-b6c0-4246c4560cea', 1.000, '1%', '2017-07-01', NULL, true, 'GST/IRP rate master', '2026-08-30 21:20:21.649139+00');
INSERT INTO public.gst_tax_rate_master_v520 (id, rate, label, effective_from, effective_to, active, source_note, created_at) VALUES ('72fe2eb7-d02d-4010-88d2-c88c6cafa7b2', 1.500, '1.5%', '2017-07-01', NULL, true, 'GST/IRP rate master', '2026-08-30 21:20:21.649139+00');
INSERT INTO public.gst_tax_rate_master_v520 (id, rate, label, effective_from, effective_to, active, source_note, created_at) VALUES ('c9291129-f3b5-43e6-853a-1fe649f5521a', 3.000, '3%', '2017-07-01', NULL, true, 'GST/IRP rate master', '2026-08-30 21:20:21.649139+00');
INSERT INTO public.gst_tax_rate_master_v520 (id, rate, label, effective_from, effective_to, active, source_note, created_at) VALUES ('3b9b459b-8c45-435e-a2ec-df346ed7041b', 5.000, '5%', '2017-07-01', NULL, true, 'GST/IRP rate master', '2026-08-30 21:20:21.649139+00');
INSERT INTO public.gst_tax_rate_master_v520 (id, rate, label, effective_from, effective_to, active, source_note, created_at) VALUES ('52c63b5d-2b13-4a3c-a22d-08c280c14c25', 6.000, '6%', '2017-07-01', NULL, true, 'GST/IRP rate master', '2026-08-30 21:20:21.649139+00');
INSERT INTO public.gst_tax_rate_master_v520 (id, rate, label, effective_from, effective_to, active, source_note, created_at) VALUES ('6da4ff15-ac94-4e2e-a38b-0149ef998ba1', 7.500, '7.5%', '2017-07-01', NULL, true, 'GST/IRP rate master', '2026-08-30 21:20:21.649139+00');
INSERT INTO public.gst_tax_rate_master_v520 (id, rate, label, effective_from, effective_to, active, source_note, created_at) VALUES ('1b7012b6-4115-4724-b134-2db391b3188a', 12.000, '12%', '2017-07-01', NULL, true, 'GST/IRP rate master', '2026-08-30 21:20:21.649139+00');
INSERT INTO public.gst_tax_rate_master_v520 (id, rate, label, effective_from, effective_to, active, source_note, created_at) VALUES ('e61921fb-28af-482d-b085-a2d9c44cff3a', 18.000, '18%', '2017-07-01', NULL, true, 'GST/IRP rate master', '2026-08-30 21:20:21.649139+00');
INSERT INTO public.gst_tax_rate_master_v520 (id, rate, label, effective_from, effective_to, active, source_note, created_at) VALUES ('36b06432-811d-4121-9228-5efcda841e99', 28.000, '28%', '2017-07-01', NULL, true, 'GST/IRP rate master', '2026-08-30 21:20:21.649139+00');
INSERT INTO public.gst_tax_rate_master_v520 (id, rate, label, effective_from, effective_to, active, source_note, created_at) VALUES ('b85d1d9b-68bf-4322-8141-1e2d81afff50', 40.000, '40%', '2025-09-21', NULL, true, 'IRP production rate master update 21-Sep-2025', '2026-08-30 21:20:21.649139+00');


--
-- PostgreSQL database dump complete
--
