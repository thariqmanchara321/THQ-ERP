begin;

do $do$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='aggregate_yard_dashboard_v617';

  v_new := regexp_replace(
    v_def,
    'left join public\.inventory_units_v481 u[[:space:]]+on u\.id=p\.base_unit_id[[:space:]]+and u\.tenant_id=p\.tenant_id',
    $r$left join public.product_units_v481 pbu
    on pbu.tenant_id=pv.tenant_id
   and pbu.variant_id=pv.id
   and pbu.is_base
   and pbu.active
  left join public.inventory_units_v481 u
    on u.id=pbu.unit_id
   and u.tenant_id=pbu.tenant_id
   and u.active$r$,
    'g'
  );
  if v_new=v_def then
    raise exception 'aggregate_yard_dashboard_v617 unit join patch not found';
  end if;
  execute v_new;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='aggregate_yard_dashboard_v621';

  v_new := regexp_replace(
    v_def,
    'left join public\.inventory_units_v481 u[[:space:]]+on u\.id=p\.base_unit_id[[:space:]]+and u\.tenant_id=p\.tenant_id',
    $r$left join public.product_units_v481 pbu
    on pbu.tenant_id=pv.tenant_id
   and pbu.variant_id=pv.id
   and pbu.is_base
   and pbu.active
  left join public.inventory_units_v481 u
    on u.id=pbu.unit_id
   and u.tenant_id=pbu.tenant_id
   and u.active$r$,
    'g'
  );
  if v_new=v_def then
    raise exception 'aggregate_yard_dashboard_v621 unit join patch not found';
  end if;
  execute v_new;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='aggregate_yard_context_v617';

  v_new := regexp_replace(
    v_def,
    'left join public\.inventory_units_v481 bu[[:space:]]+on bu\.id=p\.base_unit_id[[:space:]]+and bu\.tenant_id=p\.tenant_id',
    $r$left join public.product_units_v481 pbu
        on pbu.tenant_id=v.tenant_id
       and pbu.variant_id=v.id
       and pbu.is_base
       and pbu.active
      left join public.inventory_units_v481 bu
        on bu.id=pbu.unit_id
       and bu.tenant_id=pbu.tenant_id
       and bu.active$r$,
    'g'
  );
  if v_new=v_def then
    raise exception 'aggregate_yard_context_v617 unit join patch not found';
  end if;
  execute v_new;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='aggregate_order_create_v618';

  v_new := regexp_replace(
    v_def,
    'left join public\.inventory_units_v481 bu[[:space:]]+on bu\.id=p\.base_unit_id[[:space:]]+and bu\.tenant_id=p\.tenant_id',
    $r$left join public.product_units_v481 pbu
      on pbu.tenant_id=pv.tenant_id
     and pbu.variant_id=pv.id
     and pbu.is_base
     and pbu.active
    left join public.inventory_units_v481 bu
      on bu.id=pbu.unit_id
     and bu.tenant_id=pbu.tenant_id
     and bu.active$r$,
    'g'
  );
  if v_new=v_def then
    raise exception 'aggregate_order_create_v618 unit join patch not found';
  end if;
  execute v_new;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='aggregate_direct_materials_v621';

  v_new := regexp_replace(
    v_def,
    'left join public\.inventory_units_v481 bu[[:space:]]+on bu\.id=p\.base_unit_id[[:space:]]+and bu\.tenant_id=p\.tenant_id',
    $r$left join public.product_units_v481 pbu
    on pbu.tenant_id=pv.tenant_id
   and pbu.variant_id=pv.id
   and pbu.is_base
   and pbu.active
  left join public.inventory_units_v481 bu
    on bu.id=pbu.unit_id
   and bu.tenant_id=pbu.tenant_id
   and bu.active$r$,
    'g'
  );
  if v_new=v_def then
    raise exception 'aggregate_direct_materials_v621 base join patch not found';
  end if;

  v_new := regexp_replace(
    v_new,
    '[[:space:]]+union[[:space:]]+select[[:space:]]+bu2\.code,[[:space:]]+bu2\.name,[[:space:]]+true,[[:space:]]+bu2\.allow_fractional,[[:space:]]+bu2\.decimal_places[[:space:]]+from public\.inventory_units_v481 bu2[[:space:]]+where bu2\.id=p\.base_unit_id[[:space:]]+and bu2\.tenant_id=p\.tenant_id[[:space:]]+and bu2\.active',
    '',
    'g'
  );

  v_new := regexp_replace(
    v_new,
    'and \([[:space:]]+p\.base_unit_id is not null[[:space:]]+or exists\([[:space:]]+select 1[[:space:]]+from public\.product_units_v481 pu[[:space:]]+where pu\.tenant_id=p_tenant_id[[:space:]]+and pu\.variant_id=pv\.id[[:space:]]+and pu\.active[[:space:]]+and pu\.allow_purchase[[:space:]]+and pu\.allow_sale[[:space:]]+\)[[:space:]]+\)',
    $r$and exists(
      select 1
      from public.product_units_v481 pu
      where pu.tenant_id=p_tenant_id
        and pu.variant_id=pv.id
        and pu.active
        and pu.allow_purchase
        and pu.allow_sale
    )$r$,
    'g'
  );
  execute v_new;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='aggregate_direct_load_create_v621';

  v_new := regexp_replace(
    v_def,
    'join public\.inventory_units_v481 u[[:space:]]+on u\.id=p\.base_unit_id[[:space:]]+and u\.tenant_id=p\.tenant_id[[:space:]]+and u\.active',
    $r$join public.product_units_v481 pbu
        on pbu.tenant_id=pv.tenant_id
       and pbu.variant_id=pv.id
       and pbu.is_base
       and pbu.active
      join public.inventory_units_v481 u
        on u.id=pbu.unit_id
       and u.tenant_id=pbu.tenant_id
       and u.active$r$,
    'g'
  );
  if v_new=v_def then
    raise exception 'aggregate_direct_load_create_v621 unit join patch not found';
  end if;
  execute v_new;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='inventory_get_product_detail';

  v_new := regexp_replace(
    v_def,
    'left join public\.inventory_units iu[[:space:]]+on iu\.id[[:space:]]*=[[:space:]]*p\.base_unit_id[[:space:]]+and iu\.tenant_id[[:space:]]*=[[:space:]]*p\.tenant_id',
    $r$left join public.product_units_v481 pbu
    on pbu.tenant_id = pv.tenant_id
   and pbu.variant_id = pv.id
   and pbu.is_base
   and pbu.active

  left join public.inventory_units_v481 iu
    on iu.id = pbu.unit_id
   and iu.tenant_id = pbu.tenant_id
   and iu.active$r$,
    'g'
  );
  if v_new=v_def then
    raise exception 'inventory_get_product_detail unit join patch not found';
  end if;
  execute v_new;
end
$do$;

do $verify$
declare
  v_bad integer;
  v_missing_base integer;
begin
  select count(*) into v_bad
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname in (
      'aggregate_yard_dashboard_v617',
      'aggregate_yard_dashboard_v621',
      'aggregate_yard_context_v617',
      'aggregate_order_create_v618',
      'aggregate_direct_materials_v621',
      'aggregate_direct_load_create_v621'
    )
    and pg_get_functiondef(p.oid) ~
      'inventory_units_v481[[:space:][:print:]]*base_unit_id';

  if v_bad<>0 then
    raise exception
      'Cross-generation unit join remains in % aggregate function(s)',v_bad;
  end if;

  select count(*) into v_missing_base
  from public.product_variants pv
  join public.products p
    on p.id=pv.product_id and p.tenant_id=pv.tenant_id
  left join public.product_units_v481 pu
    on pu.tenant_id=pv.tenant_id
   and pu.variant_id=pv.id
   and pu.is_base
   and pu.active
  where pv.status='active'
    and p.status='active'
    and pu.unit_id is null;

  if v_missing_base<>0 then
    raise exception
      '% active variant(s) have no authoritative v4.81 base unit',
      v_missing_base;
  end if;
end
$verify$;

insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  322,
  '6.2.1-v481-unit-authority-hardening',
  'v4.81 Unit Authority Hardening',
  'Removes cross-generation joins between legacy products.base_unit_id and inventory_units_v481 in Material Yard, Customer Orders and Direct Supply. Inventory product detail now reports the authoritative product_units_v481 base unit. No historical legacy unit IDs are rewritten.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
