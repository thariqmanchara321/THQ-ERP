-- THQ ERP v5.2 - authoritative GST component detail for invoice rendering.
-- Live migration applied to flexi-erp-dev on 2026-09-01.
-- Read-only contract: does not modify sale posting, GST snapshots, accounting or journals.

create or replace function public.sales_get_detail_v520(
  p_tenant_id uuid,
  p_sale_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_result jsonb;
  v_gst jsonb;
begin
  v_result := public.sales_get_detail_v495(p_tenant_id, p_sale_id);

  select jsonb_build_object(
    'authoritative', true,
    'snapshot_id', s.id,
    'document_class', s.document_class,
    'tax_mode', s.tax_mode,
    'supply_type', s.supply_type,
    'interstate', s.interstate,
    'place_of_supply_code', s.place_of_supply_code,
    'supplier_gstin', s.supplier_gstin,
    'recipient_gstin', s.recipient_gstin,
    'taxable_total', s.taxable_total,
    'cgst_total', s.cgst_total,
    'sgst_total', s.sgst_total,
    'utgst_total', s.utgst_total,
    'igst_total', s.igst_total,
    'cess_total', s.cess_total,
    'tax_collected_total', s.tax_collected_total,
    'government_tax_total', s.government_tax_total,
    'lines', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'source_line_id', l.source_line_id,
          'line_no', l.line_no,
          'hsn_sac', l.hsn_sac,
          'gst_rate', l.applied_gst_rate,
          'taxable_value', l.taxable_value,
          'cgst', l.cgst,
          'sgst', l.sgst,
          'utgst', l.utgst,
          'igst', l.igst,
          'cess', l.cess,
          'tax_amount', l.tax_amount
        ) order by l.line_no
      )
      from public.gst_document_line_snapshots_v520 l
      where l.snapshot_id = s.id
    ), '[]'::jsonb)
  )
  into v_gst
  from public.gst_document_snapshots_v520 s
  where s.tenant_id = p_tenant_id
    and s.source_type = 'sale'
    and s.source_id = p_sale_id
  order by s.created_at desc
  limit 1;

  return v_result || jsonb_build_object('gst', v_gst);
end;
$function$;

revoke all on function public.sales_get_detail_v520(uuid, uuid) from public;
revoke all on function public.sales_get_detail_v520(uuid, uuid) from anon;
grant execute on function public.sales_get_detail_v520(uuid, uuid) to authenticated;
grant execute on function public.sales_get_detail_v520(uuid, uuid) to service_role;
