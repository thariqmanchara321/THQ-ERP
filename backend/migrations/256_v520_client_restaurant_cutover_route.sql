-- THQ ERP v5.2
-- Client Restaurant authoritative GST cutover route.
-- Applied to flexi-erp-dev as:
--   v520_client_restaurant_cutover_route
--
-- The Client app already contains a Restaurant workspace. The base cutover
-- contract exposed restaurant billing for POS/Mobile POS but accidentally
-- omitted it from Client channel_routes. This additive wrapper fix advertises
-- gst_restaurant_order_bill_v520 for Client while retaining the tax-mode
-- hardening introduced by v5.2 migrations 253/254.

create or replace function public.gst_transaction_cutover_contract_v520(
  p_tenant_id uuid,
  p_channel text default 'client'::text,
  p_device_id uuid default null::uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
declare
  v jsonb;
  v_mode text := private.gst_tax_mode_resolve_v520(p_tenant_id,current_date);
  v_channel text := lower(trim(coalesce(p_channel,'client')));
begin
  v := public.gst_transaction_cutover_contract_base_v520(
    p_tenant_id,
    p_channel,
    p_device_id
  );

  if v_channel = 'client' then
    v := jsonb_set(
      v,
      '{channel_routes}',
      coalesce(v->'channel_routes','{}'::jsonb) ||
        jsonb_build_object('restaurant_bill','gst_restaurant_order_bill_v520'),
      true
    );
  end if;

  v := coalesce(v,'{}'::jsonb) || jsonb_build_object(
    'tax_mode',v_mode,
    'tax_mode_configured',v_mode<>'unconfigured',
    'gst_applicable',v_mode='gst_registered',
    'tax_mode_rpc','gst_tax_mode_get_v520',
    'tax_mode_save_rpc','gst_tax_mode_set_v520'
  );
  v := jsonb_set(v,'{cutover_ready}',to_jsonb(v_mode<>'unconfigured'),true);
  v := jsonb_set(
    v,
    '{rules}',
    coalesce(v->'rules','{}'::jsonb) || jsonb_build_object(
      'tenant_tax_mode_required',true,
      'non_gst_uses_v520_writer',true,
      'non_gst_gst_amounts_zero',true,
      'non_gst_legacy_fallback',false
    ),
    true
  );
  if v_mode='unconfigured' then
    v := v || jsonb_build_object('blocking_reason','tax_mode_unconfigured');
  end if;
  return v;
end;
$$;
