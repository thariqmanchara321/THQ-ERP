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

  -- Client has always had a Restaurant workspace. v5.2 final billing must use
  -- the same authoritative restaurant GST writer as POS rather than leaving
  -- Client on restaurant_order_bill_v489.
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