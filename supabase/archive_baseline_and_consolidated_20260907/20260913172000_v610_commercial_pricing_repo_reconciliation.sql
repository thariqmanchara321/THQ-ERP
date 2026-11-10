-- THQ ERP v6.1 commercial pricing repository reconciliation.
-- Idempotent source-of-truth migration for GST-classified charges,
-- product charge rules, document discounts and Restaurant commercial billing.

create table if not exists public.sales_charge_catalog_v610 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  charge_kind text not null default 'other',
  service_variant_id uuid not null references public.product_variants(id),
  default_quantity numeric not null default 1,
  auto_apply_dine_in boolean not null default false,
  auto_apply_takeaway boolean not null default false,
  auto_apply_delivery boolean not null default false,
  active boolean not null default true,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, code)
);

create table if not exists public.product_charge_rules_v610 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  product_variant_id uuid not null references public.product_variants(id) on delete cascade,
  charge_catalog_id uuid not null references public.sales_charge_catalog_v610(id) on delete cascade,
  order_type text not null default 'delivery',
  quantity_mode text not null default 'per_unit',
  quantity_value numeric not null default 1,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, product_variant_id, charge_catalog_id, order_type)
);

create table if not exists public.sale_commercial_summary_v610 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete cascade,
  source_type text not null default 'sale',
  source_id uuid,
  order_type text not null default 'sale',
  discount_type text not null default 'none',
  discount_value numeric not null default 0,
  document_discount_total numeric not null default 0,
  classified_charge_total numeric not null default 0,
  charge_breakdown jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  unique (tenant_id, sale_id)
);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.sales_charge_catalog_v610'::regclass
      and conname='sales_charge_catalog_v610_kind_check'
  ) then
    alter table public.sales_charge_catalog_v610
      add constraint sales_charge_catalog_v610_kind_check
      check (charge_kind in (
        'packaging','delivery','service','handling','convenience','other'
      ));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.sales_charge_catalog_v610'::regclass
      and conname='sales_charge_catalog_v610_qty_check'
  ) then
    alter table public.sales_charge_catalog_v610
      add constraint sales_charge_catalog_v610_qty_check
      check (default_quantity > 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.product_charge_rules_v610'::regclass
      and conname='product_charge_rules_v610_order_type_check'
  ) then
    alter table public.product_charge_rules_v610
      add constraint product_charge_rules_v610_order_type_check
      check (order_type in ('all','sale','dine_in','takeaway','delivery'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.product_charge_rules_v610'::regclass
      and conname='product_charge_rules_v610_quantity_mode_check'
  ) then
    alter table public.product_charge_rules_v610
      add constraint product_charge_rules_v610_quantity_mode_check
      check (quantity_mode in ('per_unit','per_line','fixed'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.product_charge_rules_v610'::regclass
      and conname='product_charge_rules_v610_quantity_value_check'
  ) then
    alter table public.product_charge_rules_v610
      add constraint product_charge_rules_v610_quantity_value_check
      check (quantity_value > 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.sale_commercial_summary_v610'::regclass
      and conname='sale_commercial_summary_v610_discount_type_check'
  ) then
    alter table public.sale_commercial_summary_v610
      add constraint sale_commercial_summary_v610_discount_type_check
      check (discount_type in ('none','fixed','percent'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.sale_commercial_summary_v610'::regclass
      and conname='sale_commercial_summary_v610_values_check'
  ) then
    alter table public.sale_commercial_summary_v610
      add constraint sale_commercial_summary_v610_values_check
      check (
        discount_value >= 0
        and document_discount_total >= 0
        and classified_charge_total >= 0
        and jsonb_typeof(charge_breakdown)='array'
      );
  end if;
end
$$;

alter table public.sales_charge_catalog_v610 enable row level security;
alter table public.product_charge_rules_v610 enable row level security;
alter table public.sale_commercial_summary_v610 enable row level security;

revoke all on table public.sales_charge_catalog_v610 from anon, authenticated;
revoke all on table public.product_charge_rules_v610 from anon, authenticated;
revoke all on table public.sale_commercial_summary_v610 from anon, authenticated;
grant all on table public.sales_charge_catalog_v610 to service_role;
grant all on table public.product_charge_rules_v610 to service_role;
grant all on table public.sale_commercial_summary_v610 to service_role;

create or replace function private.sales_charge_catalog_assert_v610(
  p_tenant_id uuid,
  p_service_variant_id uuid
)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if not exists (
    select 1
    from public.product_variants pv
    join public.products p
      on p.id=pv.product_id and p.tenant_id=pv.tenant_id
    where pv.id=p_service_variant_id
      and pv.tenant_id=p_tenant_id
      and pv.status='active'
      and p.status='active'
      and p.item_type='service'
  ) then
    raise exception
      'Commercial charge must reference an active service product variant';
  end if;
end;
$$;

create or replace function public.sales_charge_catalog_put_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_charge_id uuid,
  p_code text,
  p_name text,
  p_charge_kind text,
  p_service_variant_id uuid,
  p_default_quantity numeric,
  p_auto_dine_in boolean,
  p_auto_takeaway boolean,
  p_auto_delivery boolean,
  p_active boolean
)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_id uuid;
begin
  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,p_location_id,p_device_id,'restaurant','operate'
  );
  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'restaurant.manage')
    or private.erp_has_permission(p_tenant_id,'sales.manage')
  ) then
    raise exception 'Manage permission required';
  end if;

  perform private.sales_charge_catalog_assert_v610(
    p_tenant_id,p_service_variant_id
  );

  if p_charge_id is null then
    insert into public.sales_charge_catalog_v610(
      tenant_id,code,name,charge_kind,service_variant_id,default_quantity,
      auto_apply_dine_in,auto_apply_takeaway,auto_apply_delivery,active
    ) values (
      p_tenant_id,upper(trim(p_code)),trim(p_name),
      lower(trim(p_charge_kind)),p_service_variant_id,p_default_quantity,
      coalesce(p_auto_dine_in,false),coalesce(p_auto_takeaway,false),
      coalesce(p_auto_delivery,false),coalesce(p_active,true)
    ) returning id into v_id;
  else
    update public.sales_charge_catalog_v610
    set code=upper(trim(p_code)),
        name=trim(p_name),
        charge_kind=lower(trim(p_charge_kind)),
        service_variant_id=p_service_variant_id,
        default_quantity=p_default_quantity,
        auto_apply_dine_in=coalesce(p_auto_dine_in,false),
        auto_apply_takeaway=coalesce(p_auto_takeaway,false),
        auto_apply_delivery=coalesce(p_auto_delivery,false),
        active=coalesce(p_active,true),
        updated_at=now()
    where id=p_charge_id and tenant_id=p_tenant_id
    returning id into v_id;
  end if;

  if v_id is null then raise exception 'Commercial charge not found'; end if;
  return v_id;
end;
$$;

create or replace function public.product_charge_rule_put_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_rule_id uuid,
  p_product_variant_id uuid,
  p_charge_catalog_id uuid,
  p_order_type text,
  p_quantity_mode text,
  p_quantity_value numeric,
  p_active boolean
)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_id uuid;
begin
  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,p_location_id,p_device_id,'restaurant','operate'
  );
  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'restaurant.manage')
    or private.erp_has_permission(p_tenant_id,'sales.manage')
  ) then
    raise exception 'Manage permission required';
  end if;

  if not exists (
    select 1 from public.product_variants
    where id=p_product_variant_id
      and tenant_id=p_tenant_id
      and status='active'
  ) then
    raise exception 'Product variant not found';
  end if;

  if not exists (
    select 1 from public.sales_charge_catalog_v610
    where id=p_charge_catalog_id
      and tenant_id=p_tenant_id
      and active
  ) then
    raise exception 'Commercial charge not found';
  end if;

  if p_rule_id is null then
    insert into public.product_charge_rules_v610(
      tenant_id,product_variant_id,charge_catalog_id,
      order_type,quantity_mode,quantity_value,active
    ) values (
      p_tenant_id,p_product_variant_id,p_charge_catalog_id,
      lower(trim(p_order_type)),lower(trim(p_quantity_mode)),
      p_quantity_value,coalesce(p_active,true)
    ) returning id into v_id;
  else
    update public.product_charge_rules_v610
    set product_variant_id=p_product_variant_id,
        charge_catalog_id=p_charge_catalog_id,
        order_type=lower(trim(p_order_type)),
        quantity_mode=lower(trim(p_quantity_mode)),
        quantity_value=p_quantity_value,
        active=coalesce(p_active,true),
        updated_at=now()
    where id=p_rule_id and tenant_id=p_tenant_id
    returning id into v_id;
  end if;

  if v_id is null then raise exception 'Product charge rule not found'; end if;
  return v_id;
end;
$$;

create or replace function public.product_charge_rules_list_v610(
  p_tenant_id uuid,
  p_product_variant_id uuid,
  p_location_id uuid,
  p_device_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_rows jsonb;
begin
  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,p_location_id,p_device_id,'restaurant','view'
  );
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',r.id,
      'product_variant_id',r.product_variant_id,
      'charge_catalog_id',r.charge_catalog_id,
      'order_type',r.order_type,
      'quantity_mode',r.quantity_mode,
      'quantity_value',r.quantity_value,
      'active',r.active,
      'charge_code',c.code,
      'charge_name',c.name,
      'charge_kind',c.charge_kind,
      'service_variant_id',c.service_variant_id
    ) order by c.name,r.order_type
  ),'[]'::jsonb)
  into v_rows
  from public.product_charge_rules_v610 r
  join public.sales_charge_catalog_v610 c
    on c.id=r.charge_catalog_id and c.tenant_id=r.tenant_id
  where r.tenant_id=p_tenant_id
    and r.product_variant_id=p_product_variant_id;

  return jsonb_build_object('rules',v_rows);
end;
$$;

create or replace function public.sales_charge_catalog_list_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_active_only boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_rows jsonb;
begin
  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,p_location_id,p_device_id,'restaurant','view'
  );
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',c.id,'code',c.code,'name',c.name,'charge_kind',c.charge_kind,
      'service_variant_id',c.service_variant_id,
      'default_quantity',c.default_quantity,
      'auto_apply_dine_in',c.auto_apply_dine_in,
      'auto_apply_takeaway',c.auto_apply_takeaway,
      'auto_apply_delivery',c.auto_apply_delivery,
      'active',c.active,
      'product_name',p.name,'variant_name',pv.name,'sku',pv.sku,
      'selling_price',pv.selling_price,'tax_rate',p.tax_rate,
      'tax_code',p.tax_code
    ) order by c.name,c.code
  ),'[]'::jsonb)
  into v_rows
  from public.sales_charge_catalog_v610 c
  join public.product_variants pv
    on pv.id=c.service_variant_id and pv.tenant_id=c.tenant_id
  join public.products p
    on p.id=pv.product_id and p.tenant_id=pv.tenant_id
  where c.tenant_id=p_tenant_id
    and (not p_active_only or c.active);

  return jsonb_build_object('charges',v_rows);
end;
$$;

create or replace function private.sales_commercial_expand_v610(
  p_tenant_id uuid,
  p_order_type text,
  p_items jsonb,
  p_discount_type text default 'none',
  p_discount_value numeric default 0,
  p_charge_selections jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_order_type text:=lower(trim(coalesce(p_order_type,'sale')));
  v_discount_type text:=lower(trim(coalesce(p_discount_type,'none')));
  v_discount_value numeric:=greatest(coalesce(p_discount_value,0),0);
  v_items jsonb:='[]'::jsonb;
  v_charge_items jsonb:='[]'::jsonb;
  v_breakdown jsonb:='[]'::jsonb;
  v_line jsonb;
  v_count integer;
  v_index integer:=0;
  v_qty numeric;
  v_price numeric;
  v_existing_discount numeric;
  v_line_net numeric;
  v_base_net numeric:=0;
  v_doc_discount numeric:=0;
  v_alloc numeric:=0;
  v_remaining numeric:=0;
  v_charge_total numeric:=0;
  v_subtotal numeric:=0;
  v_discount_total numeric:=0;
  v_tax numeric:=0;
  v_taxable numeric:=0;
begin
  if v_order_type='counter' then v_order_type:='sale'; end if;
  if v_order_type not in ('sale','dine_in','takeaway','delivery') then
    raise exception 'Invalid commercial order type %',v_order_type;
  end if;
  if v_discount_type not in ('none','fixed','percent') then
    raise exception 'Invalid document discount type %',v_discount_type;
  end if;
  if v_discount_type='percent' and v_discount_value>100 then
    raise exception 'Document discount percent cannot exceed 100';
  end if;
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array'
     or jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then
    raise exception 'Commercial quote requires at least one item';
  end if;
  if jsonb_typeof(coalesce(p_charge_selections,'[]'::jsonb))<>'array' then
    raise exception 'Commercial charge selections must be an array';
  end if;

  v_count:=jsonb_array_length(p_items);

  for v_line in select value from jsonb_array_elements(p_items)
  loop
    v_qty:=greatest(coalesce(nullif(v_line->>'quantity','')::numeric,0),0);
    v_price:=greatest(coalesce(nullif(v_line->>'unit_price','')::numeric,0),0);
    v_existing_discount:=greatest(
      coalesce(nullif(v_line->>'discount_amount','')::numeric,0),0
    );
    v_line_net:=greatest(v_qty*v_price-v_existing_discount,0);
    v_base_net:=v_base_net+v_line_net;
  end loop;

  if v_discount_type='fixed' then
    v_doc_discount:=least(v_discount_value,v_base_net);
  elsif v_discount_type='percent' then
    v_doc_discount:=round(v_base_net*v_discount_value/100,6);
  else
    v_doc_discount:=0;
  end if;
  v_remaining:=v_doc_discount;

  for v_line in select value from jsonb_array_elements(p_items)
  loop
    v_index:=v_index+1;
    v_qty:=greatest(coalesce(nullif(v_line->>'quantity','')::numeric,0),0);
    v_price:=greatest(coalesce(nullif(v_line->>'unit_price','')::numeric,0),0);
    v_existing_discount:=greatest(
      coalesce(nullif(v_line->>'discount_amount','')::numeric,0),0
    );
    v_line_net:=greatest(v_qty*v_price-v_existing_discount,0);

    if v_remaining>0 and v_line_net>0 and v_base_net>0 then
      if v_index=v_count then
        v_alloc:=least(v_remaining,v_line_net);
      else
        v_alloc:=least(
          round(v_doc_discount*v_line_net/v_base_net,6),
          v_remaining,
          v_line_net
        );
      end if;
    else
      v_alloc:=0;
    end if;

    v_items:=v_items||jsonb_build_array(
      v_line||jsonb_build_object(
        'discount_amount',round(v_existing_discount+v_alloc,6)
      )
    );
    v_remaining:=greatest(v_remaining-v_alloc,0);
  end loop;

  with input_lines as (
    select
      nullif(x.value->>'variant_id','')::uuid variant_id,
      greatest(
        coalesce(nullif(x.value->>'quantity','')::numeric,0),0
      ) quantity
    from jsonb_array_elements(p_items) x(value)
  ),
  manual_contrib as (
    select
      nullif(s.value->>'charge_id','')::uuid charge_id,
      greatest(
        coalesce(nullif(s.value->>'quantity','')::numeric,1),0
      ) quantity,
      'manual'::text source
    from jsonb_array_elements(
      coalesce(p_charge_selections,'[]'::jsonb)
    ) s(value)
    where jsonb_typeof(s.value)='object'
      and nullif(s.value->>'charge_id','') is not null
  ),
  auto_contrib as (
    select
      c.id charge_id,
      c.default_quantity quantity,
      'order_default'::text source
    from public.sales_charge_catalog_v610 c
    where c.tenant_id=p_tenant_id
      and c.active
      and (
        (v_order_type='dine_in' and c.auto_apply_dine_in)
        or (v_order_type='takeaway' and c.auto_apply_takeaway)
        or (v_order_type='delivery' and c.auto_apply_delivery)
      )
  ),
  rule_contrib as (
    select
      r.charge_catalog_id charge_id,
      sum(
        case
          when r.quantity_mode='per_unit'
            then i.quantity*r.quantity_value
          when r.quantity_mode='per_line'
            then r.quantity_value
          else 0
        end
      ) + max(
        case when r.quantity_mode='fixed'
          then r.quantity_value else 0 end
      ) quantity,
      'product_rule'::text source
    from input_lines i
    join public.product_charge_rules_v610 r
      on r.tenant_id=p_tenant_id
     and r.product_variant_id=i.variant_id
     and r.active
     and r.order_type in ('all',v_order_type)
    group by r.charge_catalog_id
  ),
  combined as (
    select * from manual_contrib
    union all select * from auto_contrib
    union all select * from rule_contrib
  ),
  agg as (
    select
      charge_id,
      sum(quantity) quantity,
      jsonb_agg(distinct source) sources
    from combined
    where charge_id is not null and quantity>0
    group by charge_id
  ),
  rows as (
    select
      c.id charge_id,c.code,c.name,c.charge_kind,c.service_variant_id,
      a.quantity,a.sources,pv.selling_price unit_price,p.tax_rate,p.tax_code
    from agg a
    join public.sales_charge_catalog_v610 c
      on c.id=a.charge_id
     and c.tenant_id=p_tenant_id
     and c.active
    join public.product_variants pv
      on pv.id=c.service_variant_id
     and pv.tenant_id=c.tenant_id
     and pv.status='active'
    join public.products p
      on p.id=pv.product_id
     and p.tenant_id=pv.tenant_id
     and p.status='active'
     and p.item_type='service'
  )
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'variant_id',service_variant_id,
        'quantity',quantity,
        'unit_price',unit_price,
        'discount_amount',0,
        'tax_rate',tax_rate,
        'commercial_charge_id',charge_id,
        'commercial_charge_kind',charge_kind,
        'commercial_charge_code',code
      ) order by name,code
    ),'[]'::jsonb),
    coalesce(jsonb_agg(
      jsonb_build_object(
        'charge_id',charge_id,
        'code',code,
        'name',name,
        'kind',charge_kind,
        'variant_id',service_variant_id,
        'quantity',quantity,
        'unit_price',unit_price,
        'tax_rate',tax_rate,
        'tax_code',tax_code,
        'taxable_value',round(quantity*unit_price,2),
        'tax_amount',round(quantity*unit_price*tax_rate/100,2),
        'line_total',round(quantity*unit_price*(1+tax_rate/100),2),
        'sources',sources
      ) order by name,code
    ),'[]'::jsonb),
    coalesce(sum(quantity*unit_price),0)
  into v_charge_items,v_breakdown,v_charge_total
  from rows;

  v_items:=v_items||v_charge_items;

  select
    coalesce(sum(
      greatest(coalesce(nullif(x.value->>'quantity','')::numeric,0),0) *
      greatest(coalesce(nullif(x.value->>'unit_price','')::numeric,0),0)
    ),0),
    coalesce(sum(greatest(
      coalesce(nullif(x.value->>'discount_amount','')::numeric,0),0
    )),0),
    coalesce(sum(greatest(
      greatest(coalesce(nullif(x.value->>'quantity','')::numeric,0),0) *
      greatest(coalesce(nullif(x.value->>'unit_price','')::numeric,0),0) -
      greatest(coalesce(nullif(x.value->>'discount_amount','')::numeric,0),0),
      0
    )),0),
    coalesce(sum(
      greatest(
        greatest(coalesce(nullif(x.value->>'quantity','')::numeric,0),0) *
        greatest(coalesce(nullif(x.value->>'unit_price','')::numeric,0),0) -
        greatest(coalesce(nullif(x.value->>'discount_amount','')::numeric,0),0),
        0
      ) * greatest(coalesce(nullif(x.value->>'tax_rate','')::numeric,0),0) / 100
    ),0)
  into v_subtotal,v_discount_total,v_taxable,v_tax
  from jsonb_array_elements(v_items) x(value);

  return jsonb_build_object(
    'order_type',v_order_type,
    'discount_type',v_discount_type,
    'discount_value',v_discount_value,
    'document_discount_total',round(v_doc_discount,2),
    'classified_charge_total',round(v_charge_total,2),
    'charge_breakdown',v_breakdown,
    'items',v_items,
    'totals',jsonb_build_object(
      'subtotal',round(v_subtotal,2),
      'discount',round(v_discount_total,2),
      'taxable',round(v_taxable,2),
      'tax',round(v_tax,2),
      'before_round_off',round(v_taxable+v_tax,2),
      'automatic_round_off',
        round(round(v_taxable+v_tax,0)-(v_taxable+v_tax),2),
      'grand_total',
        round(
          v_taxable+v_tax+
          round(round(v_taxable+v_tax,0)-(v_taxable+v_tax),2),
          2
        )
    )
  );
end;
$$;

create or replace function public.sales_commercial_quote_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_order_type text,
  p_items jsonb,
  p_discount_type text default 'none',
  p_discount_value numeric default 0,
  p_charge_selections jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  perform private.erp_validate_transaction_origin(
    p_tenant_id,p_location_id,p_device_id,'sales'
  );
  return private.sales_commercial_expand_v610(
    p_tenant_id,p_order_type,p_items,
    p_discount_type,p_discount_value,p_charge_selections
  );
end;
$$;

create or replace function public.sales_charge_catalog_list_pos_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_active_only boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_rows jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  perform private.erp_validate_transaction_origin(
    p_tenant_id,p_location_id,p_device_id,'sales'
  );

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',c.id,'code',c.code,'name',c.name,'charge_kind',c.charge_kind,
      'service_variant_id',c.service_variant_id,
      'default_quantity',c.default_quantity,
      'auto_apply_dine_in',c.auto_apply_dine_in,
      'auto_apply_takeaway',c.auto_apply_takeaway,
      'auto_apply_delivery',c.auto_apply_delivery,
      'active',c.active,
      'product_name',p.name,'variant_name',pv.name,'sku',pv.sku,
      'selling_price',pv.selling_price,'tax_rate',p.tax_rate,
      'tax_code',p.tax_code
    ) order by c.name,c.code
  ),'[]'::jsonb)
  into v_rows
  from public.sales_charge_catalog_v610 c
  join public.product_variants pv
    on pv.id=c.service_variant_id and pv.tenant_id=c.tenant_id
  join public.products p
    on p.id=pv.product_id and p.tenant_id=pv.tenant_id
  where c.tenant_id=p_tenant_id
    and (not p_active_only or c.active);

  return jsonb_build_object('charges',v_rows);
end;
$$;

create or replace function public.sales_commercial_summary_capture_v610(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_sale_id uuid,
  p_source_type text,
  p_source_id uuid,
  p_order_type text,
  p_summary jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_discount_type text:=
    lower(trim(coalesce(p_summary->>'discount_type','none')));
  v_discount_value numeric:=
    greatest(coalesce(nullif(p_summary->>'discount_value','')::numeric,0),0);
  v_doc_discount numeric:=
    greatest(
      coalesce(nullif(p_summary->>'document_discount_total','')::numeric,0),0
    );
  v_charge_total numeric:=
    greatest(
      coalesce(nullif(p_summary->>'classified_charge_total','')::numeric,0),0
    );
  v_breakdown jsonb:=
    coalesce(p_summary->'charge_breakdown','[]'::jsonb);
  v_grand numeric;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  perform private.erp_validate_transaction_origin(
    p_tenant_id,p_location_id,p_device_id,'sales'
  );

  select grand_total into v_grand
  from public.sales
  where id=p_sale_id
    and tenant_id=p_tenant_id
    and status='posted';

  if not found then raise exception 'Posted sale not found'; end if;
  if v_discount_type not in ('none','fixed','percent') then
    raise exception 'Invalid discount type';
  end if;
  if jsonb_typeof(v_breakdown)<>'array' then
    raise exception 'Charge breakdown must be an array';
  end if;

  insert into public.sale_commercial_summary_v610(
    tenant_id,sale_id,source_type,source_id,order_type,
    discount_type,discount_value,document_discount_total,
    classified_charge_total,charge_breakdown
  ) values (
    p_tenant_id,p_sale_id,
    lower(trim(coalesce(p_source_type,'sale'))),
    p_source_id,
    lower(trim(coalesce(p_order_type,'sale'))),
    v_discount_type,v_discount_value,v_doc_discount,
    v_charge_total,v_breakdown
  )
  on conflict(tenant_id,sale_id) do update set
    source_type=excluded.source_type,
    source_id=excluded.source_id,
    order_type=excluded.order_type,
    discount_type=excluded.discount_type,
    discount_value=excluded.discount_value,
    document_discount_total=excluded.document_discount_total,
    classified_charge_total=excluded.classified_charge_total,
    charge_breakdown=excluded.charge_breakdown;

  return jsonb_build_object(
    'success',true,
    'sale_id',p_sale_id,
    'grand_total',v_grand,
    'document_discount_total',v_doc_discount,
    'classified_charge_total',v_charge_total
  );
end;
$$;

create or replace function public.gst_restaurant_order_bill_v610(
  p_tenant_id uuid,
  p_order_id uuid,
  p_device_id uuid,
  p_customer_id uuid,
  p_due_date date,
  p_payment_allocations jsonb,
  p_tracking_assignments jsonb default '[]'::jsonb,
  p_discount_type text default 'none',
  p_discount_value numeric default 0,
  p_charge_selections jsonb default '[]'::jsonb,
  p_notes text default null,
  p_supply_type text default null,
  p_place_of_supply_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  o public.restaurant_orders%rowtype;
  v_customer uuid;
  v_base_items jsonb;
  v_commercial jsonb;
  v_items jsonb;
  v_wrapper_request text;
  v_sale_request text;
  v_req_payload jsonb;
  v_req_state jsonb;
  v_sale jsonb;
  v_sale_id uuid;
  v_snapshot uuid;
  v_journal uuid;
  v_response jsonb;
  v_summary jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'restaurant.order')
    or private.erp_has_permission(p_tenant_id,'restaurant.manage')
  ) then
    raise exception 'Restaurant billing permission denied';
  end if;

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'sales.manage')
  ) then
    raise exception
      'Sales permission required for Restaurant invoice posting';
  end if;

  if not (
    private.gst_v520_has_access(p_tenant_id,'gst_compliance.calculate')
    or private.gst_v520_has_access(p_tenant_id,'gst_compliance.view')
  ) then
    raise exception 'GST calculation permission required';
  end if;

  if p_order_id is null then
    raise exception 'Restaurant order is required';
  end if;

  if jsonb_typeof(coalesce(p_payment_allocations,'[]'::jsonb))<>'array' then
    raise exception 'Restaurant payment allocations must be an array';
  end if;

  if jsonb_typeof(coalesce(p_tracking_assignments,'[]'::jsonb))<>'array' then
    raise exception 'Restaurant tracking assignments must be an array';
  end if;

  if jsonb_typeof(coalesce(p_charge_selections,'[]'::jsonb))<>'array' then
    raise exception 'Restaurant charge selections must be an array';
  end if;

  v_wrapper_request:='gst-restaurant-order-v610:'||p_order_id::text;
  v_sale_request:='gst-restaurant-sale-v610:'||p_order_id::text;

  v_req_payload:=jsonb_build_object(
    'order_id',p_order_id,
    'device_id',p_device_id,
    'customer_id',p_customer_id,
    'due_date',p_due_date,
    'payment_allocations',
      coalesce(p_payment_allocations,'[]'::jsonb),
    'tracking_assignments',
      coalesce(p_tracking_assignments,'[]'::jsonb),
    'discount_type',
      lower(trim(coalesce(p_discount_type,'none'))),
    'discount_value',coalesce(p_discount_value,0),
    'charge_selections',
      coalesce(p_charge_selections,'[]'::jsonb),
    'notes',nullif(trim(coalesce(p_notes,'')),''),
    'supply_type',
      nullif(upper(trim(coalesce(p_supply_type,''))),''),
    'place_of_supply_code',
      nullif(trim(coalesce(p_place_of_supply_code,'')),'')
  );

  v_req_state:=private.gst_request_begin_v520(
    p_tenant_id,
    v_wrapper_request,
    'gst.restaurant.order.bill.v610',
    v_req_payload
  );

  if coalesce((v_req_state->>'existing')::boolean,false) then
    return v_req_state->'response';
  end if;

  select *
  into o
  from public.restaurant_orders
  where id=p_order_id
    and tenant_id=p_tenant_id
  for update;

  if not found then raise exception 'Restaurant order not found'; end if;

  perform private.erp_validate_vertical_device_scope(
    p_tenant_id,o.location_id,p_device_id,'restaurant','operate'
  );

  if o.status='cancelled' then
    raise exception 'Cancelled restaurant order cannot be billed';
  end if;

  if o.status='billed' or o.sale_id is not null then
    raise exception
      'Restaurant order is already billed; reconcile the existing invoice instead of converting it silently';
  end if;

  v_customer:=coalesce(o.customer_id,p_customer_id);

  if v_customer is null or not exists (
    select 1
    from public.customers c
    where c.id=v_customer
      and c.tenant_id=p_tenant_id
      and coalesce(c.status,'active')='active'
  ) then
    raise exception 'Choose an active customer before billing';
  end if;

  select coalesce(jsonb_agg(
    jsonb_strip_nulls(jsonb_build_object(
      'variant_id',i.variant_id,
      'quantity',
        greatest(i.quantity-coalesce(i.cancelled_quantity,0),0),
      'unit_id',i.unit_id,
      'unit_price',i.unit_price,
      'discount_amount',
        case
          when i.quantity>0 then round(
            i.discount_amount *
            (
              greatest(i.quantity-coalesce(i.cancelled_quantity,0),0)
              / i.quantity
            ),
            6
          )
          else 0
        end,
      'tax_rate',i.tax_rate,
      'serial_numbers',coalesce(a.serial_numbers,'[]'::jsonb),
      'batches',coalesce(a.batches,'[]'::jsonb)
    )) order by i.created_at,i.id
  ),'[]'::jsonb)
  into v_base_items
  from public.restaurant_order_items i
  left join lateral (
    select
      coalesce(x.value->'serial_numbers','[]'::jsonb) serial_numbers,
      coalesce(x.value->'batches','[]'::jsonb) batches
    from jsonb_array_elements(
      coalesce(p_tracking_assignments,'[]'::jsonb)
    ) x(value)
    where x.value->>'order_item_id'=i.id::text
    limit 1
  ) a on true
  where i.order_id=o.id
    and i.tenant_id=p_tenant_id
    and greatest(i.quantity-coalesce(i.cancelled_quantity,0),0)>0;

  if jsonb_array_length(v_base_items)=0 then
    raise exception 'Restaurant order has no billable items';
  end if;

  v_commercial:=private.sales_commercial_expand_v610(
    p_tenant_id,
    o.order_type,
    v_base_items,
    p_discount_type,
    p_discount_value,
    p_charge_selections
  );

  v_items:=v_commercial->'items';
  v_summary:=v_commercial-'items'-'totals';

  v_sale:=public.gst_sale_create_v522(
    p_tenant_id=>p_tenant_id,
    p_customer_id=>v_customer,
    p_sale_date=>current_date,
    p_due_date=>p_due_date,
    p_items=>v_items,
    p_payment_allocations=>
      coalesce(p_payment_allocations,'[]'::jsonb),
    p_notes=>concat_ws(
      ' | ',
      'Restaurant '||o.order_number,
      nullif(trim(coalesce(p_notes,'')),'')
    ),
    p_location_id=>o.location_id,
    p_device_id=>p_device_id,
    p_request_id=>v_sale_request,
    p_supply_type=>p_supply_type,
    p_place_of_supply_code=>p_place_of_supply_code
  );

  v_sale_id:=nullif(v_sale->>'sale_id','')::uuid;
  v_snapshot:=nullif(v_sale->>'gst_snapshot_id','')::uuid;
  v_journal:=nullif(v_sale->>'journal_id','')::uuid;

  if v_sale_id is null or v_snapshot is null or v_journal is null then
    raise exception
      'Restaurant GST v6.1 commercial Sale did not create complete authoritative evidence';
  end if;

  insert into public.sale_commercial_summary_v610(
    tenant_id,sale_id,source_type,source_id,order_type,
    discount_type,discount_value,document_discount_total,
    classified_charge_total,charge_breakdown
  ) values (
    p_tenant_id,
    v_sale_id,
    'restaurant_order',
    o.id,
    coalesce(v_commercial->>'order_type',o.order_type),
    coalesce(v_commercial->>'discount_type','none'),
    coalesce(
      nullif(v_commercial->>'discount_value','')::numeric,
      0
    ),
    coalesce(
      nullif(v_commercial->>'document_discount_total','')::numeric,
      0
    ),
    coalesce(
      nullif(v_commercial->>'classified_charge_total','')::numeric,
      0
    ),
    coalesce(v_commercial->'charge_breakdown','[]'::jsonb)
  )
  on conflict(tenant_id,sale_id) do update set
    source_type=excluded.source_type,
    source_id=excluded.source_id,
    order_type=excluded.order_type,
    discount_type=excluded.discount_type,
    discount_value=excluded.discount_value,
    document_discount_total=excluded.document_discount_total,
    classified_charge_total=excluded.classified_charge_total,
    charge_breakdown=excluded.charge_breakdown;

  update public.restaurant_orders
  set status='billed',
      sale_id=v_sale_id,
      billed_at=coalesce(billed_at,now()),
      updated_at=now()
  where id=o.id
    and tenant_id=p_tenant_id
    and status<>'cancelled'
    and sale_id is null;

  if not found then
    raise exception 'Restaurant order billing state changed concurrently';
  end if;

  update public.restaurant_kots
  set status='served',
      served_at=coalesce(served_at,now())
  where tenant_id=p_tenant_id
    and order_id=o.id
    and status not in ('served','cancelled');

  perform private.thq_sync_bump_v480(
    p_tenant_id,
    'transactions',
    'restaurant_order',
    o.id::text,
    'bill_v610_commercial'
  );

  v_response:=coalesce(v_sale,'{}'::jsonb)||jsonb_build_object(
    'success',true,
    'order_id',o.id,
    'order_number',o.order_number,
    'restaurant_billing','v6.1-commercial-gst-v5.2.2',
    'commercial_summary',v_summary,
    'tracking_assignments_applied',
      jsonb_array_length(
        coalesce(p_tracking_assignments,'[]'::jsonb)
      ),
    'legacy_fallback_used',false
  );

  perform private.business_audit_write_v471(
    p_tenant_id,
    'restaurant.order.bill.commercial_v610',
    'restaurant_order',
    o.id,
    o.order_number,
    to_jsonb(o),
    jsonb_build_object(
      'sale_id',v_sale_id,
      'sale_number',v_sale->>'sale_number',
      'grand_total',v_sale->>'grand_total',
      'payments',v_sale->'payments',
      'gst_snapshot_id',v_snapshot,
      'journal_id',v_journal,
      'commercial_summary',v_summary,
      'tracking_assignments',
        coalesce(p_tracking_assignments,'[]'::jsonb),
      'void_aware',true,
      'multi_payment',true
    )
  );

  v_response:=private.gst_request_complete_v520(
    p_tenant_id,
    v_wrapper_request,
    'gst.restaurant.order.bill.v610',
    'restaurant_order',
    o.id,
    v_snapshot,
    v_journal,
    v_response
  );

  return v_response;
end;
$$;

revoke all on function public.sales_charge_catalog_put_v610(
  uuid,uuid,uuid,uuid,text,text,text,uuid,numeric,boolean,boolean,boolean,boolean
) from public;
grant execute on function public.sales_charge_catalog_put_v610(
  uuid,uuid,uuid,uuid,text,text,text,uuid,numeric,boolean,boolean,boolean,boolean
) to authenticated,service_role;

revoke all on function public.product_charge_rule_put_v610(
  uuid,uuid,uuid,uuid,uuid,uuid,text,text,numeric,boolean
) from public;
grant execute on function public.product_charge_rule_put_v610(
  uuid,uuid,uuid,uuid,uuid,uuid,text,text,numeric,boolean
) to authenticated,service_role;

revoke all on function public.product_charge_rules_list_v610(
  uuid,uuid,uuid,uuid
) from public;
grant execute on function public.product_charge_rules_list_v610(
  uuid,uuid,uuid,uuid
) to authenticated,service_role;

revoke all on function public.sales_charge_catalog_list_v610(
  uuid,uuid,uuid,boolean
) from public;
grant execute on function public.sales_charge_catalog_list_v610(
  uuid,uuid,uuid,boolean
) to authenticated,service_role;

revoke all on function public.sales_commercial_quote_v610(
  uuid,uuid,uuid,text,jsonb,text,numeric,jsonb
) from public;
grant execute on function public.sales_commercial_quote_v610(
  uuid,uuid,uuid,text,jsonb,text,numeric,jsonb
) to authenticated,service_role;

revoke all on function public.sales_charge_catalog_list_pos_v610(
  uuid,uuid,uuid,boolean
) from public;
grant execute on function public.sales_charge_catalog_list_pos_v610(
  uuid,uuid,uuid,boolean
) to authenticated,service_role;

revoke all on function public.sales_commercial_summary_capture_v610(
  uuid,uuid,uuid,uuid,text,uuid,text,jsonb
) from public;
grant execute on function public.sales_commercial_summary_capture_v610(
  uuid,uuid,uuid,uuid,text,uuid,text,jsonb
) to authenticated,service_role;

revoke all on function public.gst_restaurant_order_bill_v610(
  uuid,uuid,uuid,uuid,date,jsonb,jsonb,text,numeric,jsonb,text,text,text
) from public;
grant execute on function public.gst_restaurant_order_bill_v610(
  uuid,uuid,uuid,uuid,date,jsonb,jsonb,text,numeric,jsonb,text,text,text
) to authenticated,service_role;
