begin;

-- THQ ERP v6.0.1 Build 2 P1 stabilization
-- 1) Keep inventory line cost precision at 4 decimals.
-- 2) Establish a 2-decimal currency boundary on posted authoritative Sale
--    header cost_total / gross_profit so the operational header agrees with GL.
-- 3) Normalize only authoritative GST sale headers. Legacy-unverified source
--    transactions are intentionally not rewritten.

create or replace function private.gst_sale_reconcile_source_v520(
  p_tenant_id uuid,
  p_sale_id uuid,
  p_quote jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  qline jsonb;
  v_item public.sale_items%rowtype;
  v_ids jsonb := '[]'::jsonb;
  v_count integer;
  v_quote_count integer := jsonb_array_length(coalesce(p_quote->'lines','[]'::jsonb));
  v_tax numeric := coalesce((p_quote->'totals'->>'tax_collected_total')::numeric,0);
  v_sub numeric := coalesce((p_quote->'totals'->>'subtotal')::numeric,0);
  v_disc numeric := coalesce((p_quote->'totals'->>'discount')::numeric,0);
  v_taxable numeric := coalesce((p_quote->'totals'->>'taxable_value')::numeric,0);
  v_round numeric := coalesce((p_quote->'totals'->>'round_off')::numeric,0);
  v_grand numeric := coalesce((p_quote->'totals'->>'grand_total')::numeric,0);
  v_cost numeric;
  v_recipient_gstin text := nullif(p_quote->>'recipient_gstin','');
begin
  select count(*)
    into v_count
  from public.sale_items si
  where si.tenant_id=p_tenant_id
    and si.sale_id=p_sale_id;

  if v_count<>v_quote_count then
    raise exception 'Persisted Sale line count does not match GST quote';
  end if;

  for qline in
    select value
    from jsonb_array_elements(p_quote->'lines')
  loop
    select *
      into v_item
    from public.sale_items si
    where si.tenant_id=p_tenant_id
      and si.sale_id=p_sale_id
      and si.variant_id=(qline->>'variant_id')::uuid;

    if not found then
      raise exception 'Persisted Sale line is missing for GST product %',qline->>'sku';
    end if;

    if abs(v_item.quantity-coalesce((qline->>'quantity')::numeric,0))>0.000001 then
      raise exception 'Persisted Sale quantity differs from GST quote for %',qline->>'sku';
    end if;

    if abs(v_item.unit_price-coalesce((qline->>'unit_price')::numeric,0))>0.0001 then
      raise exception 'Persisted Sale price changed after GST quote for %; retry the transaction',qline->>'sku';
    end if;

    update public.sale_items
    set subtotal=round(
          coalesce((qline->>'quantity')::numeric,0)
          * coalesce((qline->>'unit_price')::numeric,0),
          4
        ),
        discount_amount=coalesce((qline->>'discount')::numeric,0),
        taxable_amount=coalesce((qline->>'taxable_value')::numeric,0),
        tax_rate=coalesce((qline->>'applied_gst_rate')::numeric,0),
        tax_amount=coalesce((qline->>'tax_amount')::numeric,0),
        line_total=coalesce((qline->>'line_total')::numeric,0),
        gross_profit=round(
          coalesce((qline->>'taxable_value')::numeric,0)
          - coalesce(cost_total,0),
          4
        )
    where id=v_item.id;

    v_ids := v_ids || jsonb_build_array(v_item.id::text);
  end loop;

  -- IMPORTANT: journal COGS is posted as round(sum(line cost), 2).
  -- Use the exact same currency boundary for the posted Sale header.
  select round(coalesce(sum(cost_total),0),2)
    into v_cost
  from public.sale_items
  where tenant_id=p_tenant_id
    and sale_id=p_sale_id;

  update public.sales
  set subtotal=round(v_sub,4),
      discount_total=round(v_disc,4),
      taxable_total=round(v_taxable,4),
      tax_total=round(v_tax,4),
      additional_charges=0,
      round_off=round(v_round,2),
      grand_total=round(v_grand,2),
      cost_total=round(v_cost,2),
      gross_profit=round(v_taxable-v_cost,2),
      customer_tax_number=coalesce(v_recipient_gstin,customer_tax_number),
      updated_at=now()
  where tenant_id=p_tenant_id
    and id=p_sale_id
    and status='posted';

  if not found then
    raise exception 'Posted Sale source disappeared during GST reconciliation';
  end if;

  return v_ids;
end
$function$;


-- Normalize existing authoritative GST Sale headers only.
-- Do not rewrite legacy_unverified source documents.
with authoritative_sales as (
  select distinct s.tenant_id, s.id as sale_id
  from public.sales s
  join public.gst_document_snapshots_v520 gs
    on gs.tenant_id=s.tenant_id
   and gs.source_type='sale'
   and gs.source_id=s.id
  where s.status='posted'
    and not exists (
      select 1
      from public.gst_legacy_document_markers_v520 lm
      where lm.tenant_id=s.tenant_id
        and lm.source_type='sale'
        and lm.source_id=s.id
    )
),
costs as (
  select a.tenant_id,
         a.sale_id,
         round(coalesce(sum(si.cost_total),0),2) as rounded_cost
  from authoritative_sales a
  left join public.sale_items si
    on si.tenant_id=a.tenant_id
   and si.sale_id=a.sale_id
  group by a.tenant_id,a.sale_id
)
update public.sales s
set cost_total=c.rounded_cost,
    gross_profit=round(s.taxable_total-c.rounded_cost,2)
from costs c
where s.tenant_id=c.tenant_id
  and s.id=c.sale_id
  and (
    s.cost_total is distinct from c.rounded_cost
    or s.gross_profit is distinct from round(s.taxable_total-c.rounded_cost,2)
  );


-- Abort the migration if any authoritative GST Sale header still violates
-- the new currency boundary.
do $verify$
declare
  v_mismatch_count integer;
begin
  with authoritative_sales as (
    select distinct s.tenant_id, s.id as sale_id
    from public.sales s
    join public.gst_document_snapshots_v520 gs
      on gs.tenant_id=s.tenant_id
     and gs.source_type='sale'
     and gs.source_id=s.id
    where s.status='posted'
      and not exists (
        select 1
        from public.gst_legacy_document_markers_v520 lm
        where lm.tenant_id=s.tenant_id
          and lm.source_type='sale'
          and lm.source_id=s.id
      )
  ),
  expected as (
    select a.tenant_id,
           a.sale_id,
           round(coalesce(sum(si.cost_total),0),2) as rounded_cost
    from authoritative_sales a
    left join public.sale_items si
      on si.tenant_id=a.tenant_id
     and si.sale_id=a.sale_id
    group by a.tenant_id,a.sale_id
  )
  select count(*)
    into v_mismatch_count
  from expected e
  join public.sales s
    on s.tenant_id=e.tenant_id
   and s.id=e.sale_id
  where s.cost_total is distinct from e.rounded_cost
     or s.gross_profit is distinct from round(s.taxable_total-e.rounded_cost,2);

  if v_mismatch_count<>0 then
    raise exception
      'Authoritative GST Sale currency-boundary verification failed for % header(s)',
      v_mismatch_count;
  end if;
end
$verify$;


insert into public.thq_schema_releases(
  migration_no,
  schema_version,
  release_name,
  notes
)
values(
  271,
  '6.0.1-build2-p1',
  'v6.0.1 Build 2 P1 Currency/UI Stabilization',
  'Establishes a two-decimal posted Sale header cost/profit boundary aligned with authoritative GST Sale journals while retaining four-decimal inventory line cost precision. Normalizes authoritative GST Sale headers only; legacy_unverified source transactions remain untouched. Companion source patch hardens the GST top bars against horizontal RenderFlex overflow.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
