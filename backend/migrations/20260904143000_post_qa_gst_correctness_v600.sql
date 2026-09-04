begin;

-- THQ ERP v6 post-QA GST correctness repair.
--
-- 1. The v5.2.2 sale writer deliberately creates the legacy source sale with
--    zero initial payment and applies authoritative multi-payment allocations
--    afterwards. The legacy source writer must therefore defer walk-in and
--    credit-limit checks only while an authoritative sale context is active.
-- 2. The authoritative v5.2.2 path re-applies the credit-limit check using the
--    actual credit allocation after payment allocation.
-- 3. Legacy-imported GST profiles remain review_required until a user with GST
--    manage permission explicitly validates profiles that pass the current
--    local HSN/SAC + GST-rate rules.

create or replace function private.gst_sale_credit_limit_assert_v600(
  p_tenant_id uuid,
  p_sale_id uuid,
  p_customer_id uuid,
  p_new_credit numeric
)
returns void
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_customer public.customers%rowtype;
  v_existing_outstanding numeric := 0;
  v_new_credit numeric := round(coalesce(p_new_credit, 0), 2);
begin
  if v_new_credit <= 0 then
    return;
  end if;

  select *
  into v_customer
  from public.customers
  where id = p_customer_id
    and tenant_id = p_tenant_id
    and status = 'active';

  if not found then
    raise exception 'Active customer not found';
  end if;

  if v_customer.is_walk_in then
    raise exception 'Credit requires a named customer';
  end if;

  if coalesce(v_customer.credit_limit, 0) <= 0 then
    return;
  end if;

  select coalesce(
    sum(
      greatest(
        coalesce(s.grand_total, 0) - coalesce(payments.paid_amount, 0),
        0
      )
    ),
    0
  )
  into v_existing_outstanding
  from public.sales s
  left join lateral (
    select coalesce(sum(sp.amount), 0) as paid_amount
    from public.sale_payments sp
    where sp.tenant_id = s.tenant_id
      and sp.sale_id = s.id
  ) payments on true
  where s.tenant_id = p_tenant_id
    and s.customer_id = p_customer_id
    and s.status = 'posted'
    and s.id <> p_sale_id;

  if v_existing_outstanding + v_new_credit >
     coalesce(v_customer.credit_limit, 0) + 0.0001 then
    raise exception
      'Customer credit limit exceeded. Limit: %, existing outstanding: %, new credit: %',
      v_customer.credit_limit,
      v_existing_outstanding,
      v_new_credit;
  end if;
end;
$function$;

revoke all on function private.gst_sale_credit_limit_assert_v600(
  uuid, uuid, uuid, numeric
) from public;

do $repair$
declare
  v_oid oid;
  v_def text;
  v_matches integer;
begin
  select p.oid
  into strict v_oid
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'sales_create'
    and pg_get_function_identity_arguments(p.oid) =
      'p_tenant_id uuid, p_customer_id uuid, p_sale_date date, p_due_date date, p_items jsonb, p_additional_charges numeric, p_initial_payment numeric, p_payment_method text, p_payment_reference text, p_notes text';

  select pg_get_functiondef(v_oid) into v_def;

  if v_def like '%gst_authoritative_tx_context_v520 gst_ctx%' then
    raise exception 'sales_create already contains the authoritative GST context repair';
  end if;

  select count(*)
  into v_matches
  from regexp_matches(
    v_def,
    'if[[:space:]]+v_is_walk_in[[:space:]]*=[[:space:]]*true[[:space:]]+and[[:space:]]+v_balance_due[[:space:]]*>[[:space:]]*0[.]0001[[:space:]]+then',
    'gi'
  );

  if v_matches <> 1 then
    raise exception
      'Expected exactly one legacy walk-in validation block, found %',
      v_matches;
  end if;

  v_def := regexp_replace(
    v_def,
    'if[[:space:]]+v_is_walk_in[[:space:]]*=[[:space:]]*true[[:space:]]+and[[:space:]]+v_balance_due[[:space:]]*>[[:space:]]*0[.]0001[[:space:]]+then',
    $replacement$
if v_is_walk_in = true
     and v_balance_due > 0.0001
     and not exists (
       select 1
       from private.gst_authoritative_tx_context_v520 gst_ctx
       where gst_ctx.txid = txid_current()
         and gst_ctx.tenant_id = p_tenant_id
         and gst_ctx.source_type = 'sale'
     ) then
$replacement$,
    'i'
  );

  select count(*)
  into v_matches
  from regexp_matches(
    v_def,
    'if[[:space:]]+v_is_walk_in[[:space:]]*=[[:space:]]*false[[:space:]]+and[[:space:]]+v_balance_due[[:space:]]*>[[:space:]]*0[[:space:]]+and[[:space:]]+v_credit_limit[[:space:]]*>[[:space:]]*0[[:space:]]+then',
    'gi'
  );

  if v_matches <> 1 then
    raise exception
      'Expected exactly one legacy credit-limit validation block, found %',
      v_matches;
  end if;

  v_def := regexp_replace(
    v_def,
    'if[[:space:]]+v_is_walk_in[[:space:]]*=[[:space:]]*false[[:space:]]+and[[:space:]]+v_balance_due[[:space:]]*>[[:space:]]*0[[:space:]]+and[[:space:]]+v_credit_limit[[:space:]]*>[[:space:]]*0[[:space:]]+then',
    $replacement$
if v_is_walk_in = false
     and v_balance_due > 0
     and v_credit_limit > 0
     and not exists (
       select 1
       from private.gst_authoritative_tx_context_v520 gst_ctx
       where gst_ctx.txid = txid_current()
         and gst_ctx.tenant_id = p_tenant_id
         and gst_ctx.source_type = 'sale'
     ) then
$replacement$,
    'i'
  );

  execute v_def;
end;
$repair$;

do $repair$
declare
  v_oid oid;
  v_def text;
  v_old text :=
    'v_payment_result:=private.sale_payment_allocations_create_v522(p_tenant_id,v_sale_id,p_customer_id,(v_totals->>''grand_total'')::numeric,coalesce(p_payment_allocations,''[]''::jsonb));';
  v_new text :=
    'v_payment_result:=private.sale_payment_allocations_create_v522(p_tenant_id,v_sale_id,p_customer_id,(v_totals->>''grand_total'')::numeric,coalesce(p_payment_allocations,''[]''::jsonb));'
    || E'\n  perform private.gst_sale_credit_limit_assert_v600(p_tenant_id,v_sale_id,p_customer_id,coalesce((v_payment_result->>''credit_amount'')::numeric,0));';
begin
  select p.oid
  into strict v_oid
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'gst_sale_create_v522';

  select pg_get_functiondef(v_oid) into v_def;

  if v_def like '%gst_sale_credit_limit_assert_v600%' then
    raise exception 'gst_sale_create_v522 already contains the v6 credit-limit assertion';
  end if;

  if position(v_old in v_def) = 0 then
    raise exception 'Could not locate the v5.2.2 payment-allocation insertion point';
  end if;

  v_def := replace(v_def, v_old, v_new);

  if position(v_new in v_def) = 0 then
    raise exception 'Failed to insert the v6 credit-limit assertion';
  end if;

  execute v_def;
end;
$repair$;

create or replace function public.gst_product_profiles_validate_imported_v600(
  p_tenant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_row record;
  v_before jsonb;
  v_after jsonb;
  v_candidates integer := 0;
  v_validated integer := 0;
  v_remaining integer := 0;
  v_hsn text;
begin
  if not private.gst_v520_has_access(
    p_tenant_id,
    'gst_compliance.manage'
  ) then
    raise exception 'GST manage permission required';
  end if;

  for v_row in
    select
      g.id,
      g.variant_id,
      g.hsn_sac,
      g.gst_rate,
      g.effective_from
    from public.gst_product_tax_profiles_v520 g
    join public.product_variants pv
      on pv.id = g.variant_id
     and pv.tenant_id = g.tenant_id
    join public.products p
      on p.id = pv.product_id
     and p.tenant_id = pv.tenant_id
    where g.tenant_id = p_tenant_id
      and g.active
      and g.validation_status = 'review_required'
      and coalesce(g.source, '') like 'legacy%'
      and g.effective_from <= current_date
      and (g.effective_to is null or g.effective_to >= current_date)
      and pv.status = 'active'
      and p.status = 'active'
    order by g.created_at, g.id
    for update of g
  loop
    v_candidates := v_candidates + 1;
    v_hsn := nullif(
      regexp_replace(coalesce(v_row.hsn_sac, ''), '\s', '', 'g'),
      ''
    );

    if v_hsn is not null
       and v_hsn ~ '^[0-9]{4}([0-9]{2})?([0-9]{2})?$'
       and exists (
         select 1
         from public.gst_tax_rate_master_v520 r
         where r.rate = coalesce(v_row.gst_rate, 0)
           and r.active
           and r.effective_from <= v_row.effective_from
           and (
             r.effective_to is null
             or r.effective_to >= v_row.effective_from
           )
       ) then
      select to_jsonb(g)
      into v_before
      from public.gst_product_tax_profiles_v520 g
      where g.id = v_row.id;

      update public.gst_product_tax_profiles_v520
      set
        validation_status = 'locally_validated',
        updated_by = auth.uid(),
        updated_at = now()
      where id = v_row.id
        and tenant_id = p_tenant_id
        and validation_status = 'review_required';

      if found then
        v_validated := v_validated + 1;

        select to_jsonb(g)
        into v_after
        from public.gst_product_tax_profiles_v520 g
        where g.id = v_row.id;

        perform private.business_audit_write_v471(
          p_tenant_id,
          'gst.product_profile.validate_imported',
          'product_variant',
          v_row.variant_id,
          v_row.id::text,
          v_before,
          v_after
        );
      end if;
    end if;
  end loop;

  select count(*)
  into v_remaining
  from public.gst_product_tax_profiles_v520 g
  join public.product_variants pv
    on pv.id = g.variant_id
   and pv.tenant_id = g.tenant_id
  join public.products p
    on p.id = pv.product_id
   and p.tenant_id = pv.tenant_id
  where g.tenant_id = p_tenant_id
    and g.active
    and g.validation_status = 'review_required'
    and coalesce(g.source, '') like 'legacy%'
    and g.effective_from <= current_date
    and (g.effective_to is null or g.effective_to >= current_date)
    and pv.status = 'active'
    and p.status = 'active';

  return jsonb_build_object(
    'success', true,
    'candidates', v_candidates,
    'validated', v_validated,
    'skipped', greatest(v_candidates - v_validated, 0),
    'remaining_review', v_remaining
  );
end;
$function$;

revoke all on function public.gst_product_profiles_validate_imported_v600(uuid)
from public, anon;

grant execute on function public.gst_product_profiles_validate_imported_v600(uuid)
to authenticated, service_role;

comment on function public.gst_product_profiles_validate_imported_v600(uuid)
is 'Explicitly validates current legacy-imported GST product profiles against local THQ v5.2 rules. Never silently promotes invalid profiles.';

commit;