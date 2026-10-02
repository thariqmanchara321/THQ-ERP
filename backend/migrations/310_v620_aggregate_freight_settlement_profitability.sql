-- THQ ERP v6.2.0 — Aggregate Freight Settlement & Load Profitability
-- Supabase: ALREADY LIVE AND VERIFIED.
--
-- Safety:
-- * freight_amount = committed transport cost before recoverable tax
-- * unpaid hired freight is operational only; it is NOT inserted into Supplier Payables
-- * paid freight uses the authoritative THQ Expense writer
-- * partial settlements are supported
-- * per-load Sale/Purchase profitability reads authoritative line values
-- * Sale/Purchase load linking is quantity-allocation guarded
-- * no parallel GST, stock, accounting, receivable or payable writer exists

insert into public.permissions(key,name,module_key,description)
values
 ('aggregate_yard.freight.view','View Material Yard Freight','aggregate_yard',
  'View Aggregate freight costs, transporter settlement and load contribution'),
 ('aggregate_yard.freight.manage','Manage Material Yard Freight','aggregate_yard',
  'Configure freight and settle hired-transporter costs through THQ Expenses')
on conflict(key) do update
set name=excluded.name,
    module_key=excluded.module_key,
    description=excluded.description;

alter table public.aggregate_loads_v617
  add column if not exists transporter_supplier_id uuid
    references public.suppliers(id) on delete set null;

comment on column public.aggregate_loads_v617.freight_amount is
'Committed freight/transport cost excluding recoverable tax. Operational cost only; actual paid settlements are linked through aggregate_freight_settlements_v620.';

create index if not exists aggregate_loads_v617_transporter_idx
on public.aggregate_loads_v617(
  tenant_id,transporter_supplier_id,created_at desc
)
where transporter_supplier_id is not null;

create table if not exists public.aggregate_freight_settlements_v620(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  load_id uuid not null
    references public.aggregate_loads_v617(id) on delete cascade,
  location_id uuid not null
    references public.business_locations(id) on delete restrict,
  transporter_supplier_id uuid not null
    references public.suppliers(id) on delete restrict,
  expense_id uuid not null
    references public.expenses(id) on delete restrict,
  expense_number_snapshot text not null,
  base_amount numeric not null check(base_amount>0),
  tax_amount numeric not null default 0 check(tax_amount>=0),
  round_off numeric not null default 0 check(round_off>=-1 and round_off<=1),
  total_paid numeric not null check(total_paid>0),
  payment_method text not null,
  reference_number text,
  request_id text not null,
  note text,
  settled_by uuid references auth.users(id),
  settled_at timestamptz not null default now(),
  unique(tenant_id,request_id),
  unique(expense_id)
);

create index if not exists aggregate_freight_settlements_v620_load_idx
on public.aggregate_freight_settlements_v620(
  tenant_id,load_id,settled_at desc
);

create index if not exists aggregate_freight_settlements_v620_supplier_idx
on public.aggregate_freight_settlements_v620(
  tenant_id,transporter_supplier_id,settled_at desc
);

alter table public.aggregate_freight_settlements_v620
enable row level security;

drop policy if exists aggregate_freight_settlements_v620_read
on public.aggregate_freight_settlements_v620;

create policy aggregate_freight_settlements_v620_read
on public.aggregate_freight_settlements_v620
for select to authenticated
using(
  private.erp_user_has_tenant_access(tenant_id)
  and exists(
    select 1
    from public.tenant_modules tm
    where tm.tenant_id=aggregate_freight_settlements_v620.tenant_id
      and tm.module_key='aggregate_yard'
      and tm.enabled
  )
  and exists(
    select 1
    from public.aggregate_loads_v617 l
    where l.id=aggregate_freight_settlements_v620.load_id
      and l.tenant_id=aggregate_freight_settlements_v620.tenant_id
      and (
        l.location_id is null
        or private.erp_document_scope_allowed(
          aggregate_freight_settlements_v620.tenant_id,
          l.location_id,
          l.location_id,
          'view'
        )
      )
  )
  and (
    private.erp_has_permission(tenant_id,'aggregate_yard.freight.view')
    or private.erp_has_permission(tenant_id,'aggregate_yard.freight.manage')
    or private.erp_has_permission(tenant_id,'aggregate_yard.manage')
  )
);

revoke all on public.aggregate_freight_settlements_v620
from public,anon,authenticated;
grant select on public.aggregate_freight_settlements_v620
to authenticated,service_role;

create or replace function private.aggregate_yard_assert_freight_view_v620(
  p_tenant_id uuid
)
returns void
language plpgsql
stable security definer
set search_path=public,private,pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Tenant access required' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.tenant_modules
    where tenant_id=p_tenant_id
      and module_key='aggregate_yard'
      and enabled
  ) then
    raise exception 'Material Yard module is not enabled'
      using errcode='42501';
  end if;
  if not (
    private.erp_has_permission(p_tenant_id,'aggregate_yard.freight.view')
    or private.erp_has_permission(p_tenant_id,'aggregate_yard.freight.manage')
    or private.erp_has_permission(p_tenant_id,'aggregate_yard.manage')
  ) then
    raise exception 'Material Yard freight view permission required'
      using errcode='42501';
  end if;
end
$$;

revoke all
on function private.aggregate_yard_assert_freight_view_v620(uuid)
from public,anon,authenticated;

create or replace function private.aggregate_yard_assert_freight_manage_v620(
  p_tenant_id uuid
)
returns void
language plpgsql
stable security definer
set search_path=public,private,pg_temp
as $$
begin
  perform private.aggregate_yard_assert_freight_view_v620(p_tenant_id);
  if not (
    private.erp_has_permission(p_tenant_id,'aggregate_yard.freight.manage')
    or private.erp_has_permission(p_tenant_id,'aggregate_yard.manage')
  ) then
    raise exception 'Material Yard freight manage permission required'
      using errcode='42501';
  end if;
end
$$;

revoke all
on function private.aggregate_yard_assert_freight_manage_v620(uuid)
from public,anon,authenticated;

create or replace function private.aggregate_yard_grant_default_permissions_v617(
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  insert into public.role_permissions(role_id,permission_key)
  select r.id,p.key
  from public.roles r
  join public.permissions p on p.module_key='aggregate_yard'
  where r.tenant_id=p_tenant_id
    and (
      r.key='owner'
      or (
        r.key='manager'
        and p.key in(
          'aggregate_yard.view',
          'aggregate_yard.manage',
          'aggregate_yard.override_capacity',
          'aggregate_yard.orders.view',
          'aggregate_yard.orders.manage',
          'aggregate_yard.freight.view',
          'aggregate_yard.freight.manage'
        )
      )
      or (
        r.key='store_keeper'
        and p.key in(
          'aggregate_yard.view',
          'aggregate_yard.manage',
          'aggregate_yard.orders.view',
          'aggregate_yard.orders.manage',
          'aggregate_yard.freight.view'
        )
      )
      or (
        r.key='salesperson'
        and p.key in(
          'aggregate_yard.view',
          'aggregate_yard.orders.view',
          'aggregate_yard.orders.manage'
        )
      )
      or (
        r.key='accountant'
        and p.key in(
          'aggregate_yard.view',
          'aggregate_yard.orders.view',
          'aggregate_yard.freight.view'
        )
      )
    )
  on conflict do nothing;
end
$$;

revoke all
on function private.aggregate_yard_grant_default_permissions_v617(uuid)
from public,anon,authenticated;

create or replace function public.aggregate_freight_context_v620(
  p_tenant_id uuid
)
returns jsonb
language plpgsql
stable security definer
set search_path=public,private,pg_temp
as $$
declare
  v_can_settle boolean:=false;
  v_result jsonb;
begin
  perform private.aggregate_yard_assert_freight_view_v620(p_tenant_id);

  v_can_settle :=
    private.erp_module_enabled(p_tenant_id,'expenses')
    and private.erp_has_permission(p_tenant_id,'expenses.manage');

  select jsonb_build_object(
    'can_settle_expense',v_can_settle,
    'payment_methods',
      jsonb_build_array('cash','upi','card','bank','cheque','other'),
    'transporters',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'supplier_id',s.id,
            'name',s.name,
            'phone',s.phone
          )
          order by s.name
        )
        from public.suppliers s
        where s.tenant_id=p_tenant_id
          and s.status='active'
      ),'[]'::jsonb),
    'expense_categories',
      case
        when v_can_settle then coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'category_id',c.id,
              'name',c.name
            )
            order by c.name
          )
          from public.expense_categories c
          where c.tenant_id=p_tenant_id
            and c.active
        ),'[]'::jsonb)
        else '[]'::jsonb
      end
  )
  into v_result;

  return v_result;
end
$$;

revoke all
on function public.aggregate_freight_context_v620(uuid)
from public,anon;
grant execute
on function public.aggregate_freight_context_v620(uuid)
to authenticated,service_role;

create or replace function public.aggregate_freight_configure_v620(
  p_tenant_id uuid,
  p_load_id uuid,
  p_freight_mode text,
  p_transporter_supplier_id uuid,
  p_freight_amount numeric,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_load public.aggregate_loads_v617%rowtype;
  v_mode text:=lower(trim(coalesce(p_freight_mode,'none')));
  v_amount numeric:=round(greatest(coalesce(p_freight_amount,0),0),2);
  v_paid numeric:=0;
  v_transporter_name text;
begin
  perform private.aggregate_yard_assert_freight_manage_v620(p_tenant_id);

  select *
  into v_load
  from public.aggregate_loads_v617
  where id=p_load_id
    and tenant_id=p_tenant_id
  for update;

  if v_load.id is null then
    raise exception 'Load not found';
  end if;
  if v_load.status='cancelled' then
    raise exception 'Cancelled load freight cannot be changed';
  end if;

  if v_load.location_id is not null
     and not private.erp_document_scope_allowed(
       p_tenant_id,
       v_load.location_id,
       v_load.location_id,
       'view'
     ) then
    raise exception 'Location access required' using errcode='42501';
  end if;

  if v_mode not in(
    'none','own','hired','supplier','customer','included'
  ) then
    raise exception 'Invalid freight mode';
  end if;

  select coalesce(sum(fs.base_amount),0)
  into v_paid
  from public.aggregate_freight_settlements_v620 fs
  where fs.tenant_id=p_tenant_id
    and fs.load_id=p_load_id;

  if v_amount+0.005<v_paid then
    raise exception
      'Freight cost % cannot be lower than already settled amount %',
      v_amount,
      v_paid;
  end if;

  if v_paid>0.005
     and (
       v_mode<>'hired'
       or p_transporter_supplier_id is distinct from
          v_load.transporter_supplier_id
     ) then
    raise exception
      'Freight mode/transporter cannot change after settlement has started';
  end if;

  if v_mode='hired' and v_amount>0.005 then
    if p_transporter_supplier_id is null then
      raise exception 'Select a transporter supplier for hired freight';
    end if;

    select s.name
    into v_transporter_name
    from public.suppliers s
    where s.id=p_transporter_supplier_id
      and s.tenant_id=p_tenant_id
      and s.status='active';

    if v_transporter_name is null then
      raise exception 'Active transporter supplier not found';
    end if;
  else
    p_transporter_supplier_id:=null;
  end if;

  update public.aggregate_loads_v617
  set freight_mode=v_mode,
      freight_amount=v_amount,
      transporter_supplier_id=p_transporter_supplier_id,
      updated_by=auth.uid(),
      updated_at=now()
  where id=p_load_id
    and tenant_id=p_tenant_id;

  insert into public.aggregate_load_events_v617(
    tenant_id,
    load_id,
    event_type,
    note,
    metadata,
    created_by
  )
  values(
    p_tenant_id,
    p_load_id,
    'freight_configured',
    coalesce(nullif(trim(p_note),''),'Freight configuration updated'),
    jsonb_build_object(
      'old_mode',v_load.freight_mode,
      'new_mode',v_mode,
      'old_amount',v_load.freight_amount,
      'new_amount',v_amount,
      'old_transporter_supplier_id',v_load.transporter_supplier_id,
      'new_transporter_supplier_id',p_transporter_supplier_id,
      'already_settled_base',v_paid
    ),
    auth.uid()
  );

  return jsonb_build_object(
    'load_id',p_load_id,
    'load_number',v_load.load_number,
    'freight_mode',v_mode,
    'freight_amount',v_amount,
    'transporter_supplier_id',p_transporter_supplier_id,
    'transporter_name',v_transporter_name,
    'settled_base',v_paid,
    'pending_base',greatest(v_amount-v_paid,0)
  );
end
$$;

revoke all
on function public.aggregate_freight_configure_v620(
  uuid,uuid,text,uuid,numeric,text
)
from public,anon;
grant execute
on function public.aggregate_freight_configure_v620(
  uuid,uuid,text,uuid,numeric,text
)
to authenticated,service_role;

create or replace function public.aggregate_freight_settle_v620(
  p_tenant_id uuid,
  p_load_id uuid,
  p_category_id uuid,
  p_settlement_date date,
  p_amount numeric,
  p_tax_amount numeric,
  p_round_off numeric,
  p_payment_method text,
  p_reference_number text,
  p_note text,
  p_device_id uuid,
  p_request_id text
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_load public.aggregate_loads_v617%rowtype;
  v_supplier public.suppliers%rowtype;
  v_paid numeric:=0;
  v_remaining numeric:=0;
  v_amount numeric:=round(coalesce(p_amount,0),2);
  v_tax numeric:=round(coalesce(p_tax_amount,0),2);
  v_round numeric:=round(coalesce(p_round_off,0),2);
  v_existing public.aggregate_freight_settlements_v620%rowtype;
  v_expense jsonb;
  v_expense_id uuid;
  v_expense_no text;
  v_total numeric;
  v_settlement_id uuid;
begin
  perform private.aggregate_yard_assert_freight_manage_v620(p_tenant_id);

  if nullif(trim(coalesce(p_request_id,'')),'') is null then
    raise exception 'Request ID is required';
  end if;

  select *
  into v_existing
  from public.aggregate_freight_settlements_v620
  where tenant_id=p_tenant_id
    and request_id=p_request_id;

  if v_existing.id is not null then
    return jsonb_build_object(
      'settlement_id',v_existing.id,
      'load_id',v_existing.load_id,
      'expense_id',v_existing.expense_id,
      'expense_number',v_existing.expense_number_snapshot,
      'base_amount',v_existing.base_amount,
      'tax_amount',v_existing.tax_amount,
      'round_off',v_existing.round_off,
      'total_paid',v_existing.total_paid,
      'idempotent_replay',true
    );
  end if;

  select *
  into v_load
  from public.aggregate_loads_v617
  where id=p_load_id
    and tenant_id=p_tenant_id
  for update;

  if v_load.id is null then
    raise exception 'Load not found';
  end if;
  if v_load.status='cancelled' then
    raise exception 'Cancelled load freight cannot be settled';
  end if;
  if v_load.location_id is null then
    raise exception 'A specific yard/store is required for freight settlement';
  end if;

  if not private.erp_document_scope_allowed(
    p_tenant_id,
    v_load.location_id,
    v_load.location_id,
    'view'
  ) then
    raise exception 'Location access required' using errcode='42501';
  end if;

  if v_load.freight_mode<>'hired' then
    raise exception 'Only hired-transporter freight is settled here';
  end if;

  if v_load.transporter_supplier_id is null then
    raise exception 'Select the transporter supplier before settlement';
  end if;

  select *
  into v_supplier
  from public.suppliers s
  where s.id=v_load.transporter_supplier_id
    and s.tenant_id=p_tenant_id
    and s.status='active';

  if v_supplier.id is null then
    raise exception 'Active transporter supplier not found';
  end if;

  select coalesce(sum(fs.base_amount),0)
  into v_paid
  from public.aggregate_freight_settlements_v620 fs
  where fs.tenant_id=p_tenant_id
    and fs.load_id=p_load_id;

  v_remaining:=greatest(v_load.freight_amount-v_paid,0);

  if v_remaining<=0.005 then
    raise exception 'Freight is already fully settled';
  end if;

  if v_amount<=0 then
    raise exception 'Settlement amount must be greater than zero';
  end if;

  if v_amount>v_remaining+0.005 then
    raise exception
      'Settlement % exceeds pending freight %',
      v_amount,
      v_remaining;
  end if;

  if v_tax<0 then
    raise exception 'Tax cannot be negative';
  end if;

  if abs(v_round)>0.999999 then
    raise exception 'Round off must be between -1.00 and 1.00';
  end if;

  v_expense:=public.expenses_create_v489(
    p_tenant_id,
    p_category_id,
    coalesce(p_settlement_date,current_date),
    v_supplier.name,
    'Freight settlement for '||v_load.load_number,
    v_amount,
    v_tax,
    v_round,
    lower(trim(coalesce(p_payment_method,'cash'))),
    nullif(trim(coalesce(p_reference_number,'')),''),
    concat_ws(
      ' | ',
      'Aggregate freight',
      v_load.load_number,
      nullif(trim(coalesce(p_note,'')),'')
    ),
    v_load.location_id,
    p_device_id,
    p_request_id||':aggregate_freight_expense'
  );

  v_expense_id:=nullif(v_expense->>'expense_id','')::uuid;
  v_expense_no:=coalesce(
    nullif(v_expense->>'expense_number',''),
    nullif(v_expense->>'number','')
  );

  v_total:=round(
    coalesce(
      nullif(v_expense->>'total_amount','')::numeric,
      v_amount+v_tax+v_round
    ),
    2
  );

  if v_expense_id is null or v_expense_no is null then
    raise exception 'Freight expense did not return a valid document';
  end if;

  insert into public.aggregate_freight_settlements_v620(
    tenant_id,
    load_id,
    location_id,
    transporter_supplier_id,
    expense_id,
    expense_number_snapshot,
    base_amount,
    tax_amount,
    round_off,
    total_paid,
    payment_method,
    reference_number,
    request_id,
    note,
    settled_by
  )
  values(
    p_tenant_id,
    p_load_id,
    v_load.location_id,
    v_supplier.id,
    v_expense_id,
    v_expense_no,
    v_amount,
    v_tax,
    v_round,
    v_total,
    lower(trim(coalesce(p_payment_method,'cash'))),
    nullif(trim(coalesce(p_reference_number,'')),''),
    p_request_id,
    nullif(trim(coalesce(p_note,'')),''),
    auth.uid()
  )
  returning id into v_settlement_id;

  insert into public.aggregate_load_events_v617(
    tenant_id,
    load_id,
    event_type,
    note,
    metadata,
    created_by
  )
  values(
    p_tenant_id,
    p_load_id,
    'freight_settled',
    'Freight expense '||v_expense_no||' posted',
    jsonb_build_object(
      'settlement_id',v_settlement_id,
      'expense_id',v_expense_id,
      'expense_number',v_expense_no,
      'base_amount',v_amount,
      'tax_amount',v_tax,
      'round_off',v_round,
      'total_paid',v_total,
      'payment_method',
        lower(trim(coalesce(p_payment_method,'cash')))
    ),
    auth.uid()
  );

  return jsonb_build_object(
    'settlement_id',v_settlement_id,
    'load_id',p_load_id,
    'load_number',v_load.load_number,
    'expense_id',v_expense_id,
    'expense_number',v_expense_no,
    'base_amount',v_amount,
    'tax_amount',v_tax,
    'round_off',v_round,
    'total_paid',v_total,
    'settled_base_after',v_paid+v_amount,
    'pending_base_after',
      greatest(v_load.freight_amount-v_paid-v_amount,0),
    'idempotent_replay',false
  );
end
$$;

revoke all
on function public.aggregate_freight_settle_v620(
  uuid,uuid,uuid,date,numeric,numeric,numeric,
  text,text,text,uuid,text
)
from public,anon;

grant execute
on function public.aggregate_freight_settle_v620(
  uuid,uuid,uuid,date,numeric,numeric,numeric,
  text,text,text,uuid,text
)
to authenticated,service_role;

create or replace function public.aggregate_freight_list_v620(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_query text default null,
  p_limit integer default 300
)
returns setof jsonb
language plpgsql
stable security definer
set search_path=public,private,pg_temp
as $$
declare
  v_sale_fin boolean:=false;
  v_purchase_fin boolean:=false;
begin
  perform private.aggregate_yard_assert_freight_view_v620(p_tenant_id);

  v_sale_fin :=
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'sales.view')
    or private.erp_has_permission(p_tenant_id,'sales.manage')
    or private.erp_has_permission(p_tenant_id,'accounting.view')
    or private.erp_has_permission(p_tenant_id,'accounting.manage');

  v_purchase_fin :=
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'purchases.view')
    or private.erp_has_permission(p_tenant_id,'purchases.manage')
    or private.erp_has_permission(p_tenant_id,'accounting.view')
    or private.erp_has_permission(p_tenant_id,'accounting.manage');

  return query
  with paid as (
    select
      fs.load_id,
      sum(fs.base_amount)::numeric as settled_base,
      sum(fs.tax_amount)::numeric as settled_tax,
      sum(fs.total_paid)::numeric as settled_total,
      count(*)::bigint as settlement_count
    from public.aggregate_freight_settlements_v620 fs
    where fs.tenant_id=p_tenant_id
    group by fs.load_id
  )
  select jsonb_build_object(
    'load_id',l.id,
    'load_number',l.load_number,
    'load_date',l.load_date,
    'direction',l.direction,
    'status',l.status,
    'location_id',l.location_id,
    'product_name',l.product_name_snapshot,
    'quantity',l.quantity,
    'unit_code',l.unit_code,
    'vehicle_registration',l.vehicle_registration_snapshot,
    'driver_name',l.driver_name_snapshot,
    'customer_name',c.name,
    'supplier_name',sp.name,
    'order_number',o.order_number,
    'sale_id',l.sale_id,
    'purchase_id',l.purchase_id,
    'freight_mode',l.freight_mode,
    'freight_cost',round(l.freight_amount,2),
    'transporter_supplier_id',l.transporter_supplier_id,
    'transporter_name',ts.name,
    'freight_settled_base',round(coalesce(pd.settled_base,0),2),
    'freight_settled_tax',round(coalesce(pd.settled_tax,0),2),
    'freight_settled_total',round(coalesce(pd.settled_total,0),2),
    'freight_pending_base',round(
      greatest(l.freight_amount-coalesce(pd.settled_base,0),0),
      2
    ),
    'freight_settlement_count',coalesce(pd.settlement_count,0),
    'freight_status',
      case
        when l.freight_mode<>'hired'
          or l.freight_amount<=0.005 then 'not_required'
        when coalesce(pd.settled_base,0)<=0.005 then 'pending'
        when coalesce(pd.settled_base,0)+0.005<l.freight_amount
          then 'part_paid'
        else 'settled'
      end,
    'sale_financials_visible',v_sale_fin,
    'purchase_financials_visible',v_purchase_fin,
    'material_revenue',
      case
        when v_sale_fin
         and l.direction='outbound'
         and sm.match_qty>0
        then round(
          sm.revenue_ex_tax
          *least(l.quantity/sm.match_qty,1),
          2
        )
        else null
      end,
    'material_cost',
      case
        when v_sale_fin
         and l.direction='outbound'
         and sm.match_qty>0
        then round(
          sm.cost_total
          *least(l.quantity/sm.match_qty,1),
          2
        )
        else null
      end,
    'material_gross_profit',
      case
        when v_sale_fin
         and l.direction='outbound'
         and sm.match_qty>0
        then round(
          (sm.revenue_ex_tax-sm.cost_total)
          *least(l.quantity/sm.match_qty,1),
          2
        )
        else null
      end,
    'contribution_after_freight',
      case
        when v_sale_fin
         and l.direction='outbound'
         and sm.match_qty>0
        then round(
          (
            (sm.revenue_ex_tax-sm.cost_total)
            *least(l.quantity/sm.match_qty,1)
          )-l.freight_amount,
          2
        )
        else null
      end,
    'sale_unclassified_additional_charges',
      case
        when v_sale_fin
        then round(coalesce(sa.additional_charges,0),2)
        else null
      end,
    'purchase_material_cost',
      case
        when v_purchase_fin
         and l.direction='inbound'
         and pm.match_qty>0
        then round(
          pm.cost_ex_tax
          *least(l.quantity/pm.match_qty,1),
          2
        )
        else null
      end,
    'inbound_landed_cost_after_freight',
      case
        when v_purchase_fin
         and l.direction='inbound'
         and pm.match_qty>0
        then round(
          (
            pm.cost_ex_tax
            *least(l.quantity/pm.match_qty,1)
          )+l.freight_amount,
          2
        )
        else null
      end,
    'created_at',l.created_at
  )
  from public.aggregate_loads_v617 l
  left join public.customers c
    on c.id=l.customer_id
   and c.tenant_id=l.tenant_id
  left join public.suppliers sp
    on sp.id=l.supplier_id
   and sp.tenant_id=l.tenant_id
  left join public.suppliers ts
    on ts.id=l.transporter_supplier_id
   and ts.tenant_id=l.tenant_id
  left join public.aggregate_orders_v618 o
    on o.id=l.order_id
   and o.tenant_id=l.tenant_id
  left join public.sales sa
    on sa.id=l.sale_id
   and sa.tenant_id=l.tenant_id
  left join paid pd
    on pd.load_id=l.id
  left join lateral (
    select
      coalesce(
        sum(coalesce(si.entered_quantity,si.quantity)),
        0
      )::numeric as match_qty,
      coalesce(sum(si.taxable_amount),0)::numeric as revenue_ex_tax,
      coalesce(sum(si.cost_total),0)::numeric as cost_total
    from public.sale_items si
    where si.tenant_id=l.tenant_id
      and si.sale_id=l.sale_id
      and si.variant_id=l.variant_id
      and upper(
        coalesce(si.entered_unit_code,si.unit_code,'')
      )=upper(l.unit_code)
  ) sm on true
  left join lateral (
    select
      coalesce(
        sum(coalesce(pi.entered_quantity,pi.quantity)),
        0
      )::numeric as match_qty,
      coalesce(sum(pi.taxable_amount),0)::numeric as cost_ex_tax
    from public.purchase_items pi
    where pi.tenant_id=l.tenant_id
      and pi.purchase_id=l.purchase_id
      and pi.variant_id=l.variant_id
      and upper(
        coalesce(pi.entered_unit_code,pi.unit_code,'')
      )=upper(l.unit_code)
  ) pm on true
  where l.tenant_id=p_tenant_id
    and l.status<>'cancelled'
    and (p_location_id is null or l.location_id=p_location_id)
    and (
      l.location_id is null
      or private.erp_document_scope_allowed(
        p_tenant_id,
        l.location_id,
        p_location_id,
        'view'
      )
    )
    and (
      p_query is null
      or trim(p_query)=''
      or l.load_number ilike '%'||trim(p_query)||'%'
      or l.product_name_snapshot ilike '%'||trim(p_query)||'%'
      or coalesce(l.vehicle_registration_snapshot,'')
           ilike '%'||trim(p_query)||'%'
      or coalesce(c.name,'') ilike '%'||trim(p_query)||'%'
      or coalesce(sp.name,'') ilike '%'||trim(p_query)||'%'
      or coalesce(ts.name,'') ilike '%'||trim(p_query)||'%'
      or coalesce(o.order_number,'') ilike '%'||trim(p_query)||'%'
    )
  order by l.created_at desc
  limit greatest(1,least(coalesce(p_limit,300),1000));
end
$$;

revoke all
on function public.aggregate_freight_list_v620(
  uuid,uuid,text,integer
)
from public,anon;
grant execute
on function public.aggregate_freight_list_v620(
  uuid,uuid,text,integer
)
to authenticated,service_role;

-- Harden the existing document link RPC so multiple loads cannot collectively
-- allocate more of a Sale/Purchase line than the authoritative document owns.
create or replace function public.aggregate_load_link_document_v617(
  p_tenant_id uuid,
  p_load_id uuid,
  p_document_type text,
  p_document_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_type text:=lower(trim(coalesce(p_document_type,'')));
  v_ref text;
  v_load public.aggregate_loads_v617%rowtype;
  v_document_qty numeric:=0;
  v_allocated_qty numeric:=0;
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  select *
  into v_load
  from public.aggregate_loads_v617
  where id=p_load_id
    and tenant_id=p_tenant_id
  for update;

  if v_load.id is null then
    raise exception 'Load not found';
  end if;

  if v_load.status='cancelled' then
    raise exception 'Cancelled load cannot be linked to a transaction';
  end if;

  if v_load.direction='direct_delivery' then
    raise exception
      'Direct-delivery commercial posting is disabled until the transit-stock workflow is installed';
  end if;

  if v_type='purchase' then
    if v_load.direction<>'inbound' then
      raise exception 'Only inbound loads may link a Purchase';
    end if;

    if v_load.purchase_id is not null
       and v_load.purchase_id<>p_document_id then
      raise exception 'Load is already linked to another Purchase';
    end if;

    perform 1
    from public.purchases p
    where p.id=p_document_id
      and p.tenant_id=p_tenant_id
    for update;

    if not found then
      raise exception 'Purchase not found';
    end if;

    select
      p.purchase_number,
      coalesce(
        sum(
          case
            when upper(
              coalesce(pi.entered_unit_code,pi.unit_code,'')
            )=upper(v_load.unit_code)
            then coalesce(pi.entered_quantity,pi.quantity)
            else 0
          end
        ),
        0
      )
    into v_ref,v_document_qty
    from public.purchases p
    join public.purchase_items pi
      on pi.purchase_id=p.id
     and pi.tenant_id=p.tenant_id
     and pi.variant_id=v_load.variant_id
    where p.id=p_document_id
      and p.tenant_id=p_tenant_id
    group by p.purchase_number;

    if v_ref is null or v_document_qty<=0 then
      raise exception
        'Purchase does not contain the load material in unit %',
        v_load.unit_code;
    end if;

    select coalesce(sum(x.quantity),0)
    into v_allocated_qty
    from public.aggregate_loads_v617 x
    where x.tenant_id=p_tenant_id
      and x.id<>p_load_id
      and x.purchase_id=p_document_id
      and x.variant_id=v_load.variant_id
      and upper(x.unit_code)=upper(v_load.unit_code)
      and x.status<>'cancelled';

    if v_allocated_qty+v_load.quantity>v_document_qty+0.0001 then
      raise exception
        'Purchase quantity % % is already allocated by other loads (% %). This load would over-link the document.',
        v_document_qty,
        v_load.unit_code,
        v_allocated_qty,
        v_load.unit_code;
    end if;

    update public.aggregate_loads_v617
    set purchase_id=p_document_id,
        updated_by=auth.uid(),
        updated_at=now()
    where id=p_load_id
      and tenant_id=p_tenant_id;

  elsif v_type='sale' then
    if v_load.direction<>'outbound' then
      raise exception 'Only outbound loads may link a Sale';
    end if;

    if v_load.sale_id is not null
       and v_load.sale_id<>p_document_id then
      raise exception 'Load is already linked to another Sale';
    end if;

    perform 1
    from public.sales s
    where s.id=p_document_id
      and s.tenant_id=p_tenant_id
    for update;

    if not found then
      raise exception 'Sale not found';
    end if;

    select
      s.sale_number,
      coalesce(
        sum(
          case
            when upper(
              coalesce(si.entered_unit_code,si.unit_code,'')
            )=upper(v_load.unit_code)
            then coalesce(si.entered_quantity,si.quantity)
            else 0
          end
        ),
        0
      )
    into v_ref,v_document_qty
    from public.sales s
    join public.sale_items si
      on si.sale_id=s.id
     and si.tenant_id=s.tenant_id
     and si.variant_id=v_load.variant_id
    where s.id=p_document_id
      and s.tenant_id=p_tenant_id
    group by s.sale_number;

    if v_ref is null or v_document_qty<=0 then
      raise exception
        'Sale does not contain the load material in unit %',
        v_load.unit_code;
    end if;

    select coalesce(sum(x.quantity),0)
    into v_allocated_qty
    from public.aggregate_loads_v617 x
    where x.tenant_id=p_tenant_id
      and x.id<>p_load_id
      and x.sale_id=p_document_id
      and x.variant_id=v_load.variant_id
      and upper(x.unit_code)=upper(v_load.unit_code)
      and x.status<>'cancelled';

    if v_allocated_qty+v_load.quantity>v_document_qty+0.0001 then
      raise exception
        'Sale quantity % % is already allocated by other loads (% %). This load would over-link the document.',
        v_document_qty,
        v_load.unit_code,
        v_allocated_qty,
        v_load.unit_code;
    end if;

    update public.aggregate_loads_v617
    set sale_id=p_document_id,
        updated_by=auth.uid(),
        updated_at=now()
    where id=p_load_id
      and tenant_id=p_tenant_id;

  else
    raise exception 'Document type must be purchase or sale';
  end if;

  if not exists(
    select 1
    from public.aggregate_load_events_v617 e
    where e.tenant_id=p_tenant_id
      and e.load_id=p_load_id
      and e.event_type='document_linked'
      and e.metadata->>'document_type'=v_type
      and e.metadata->>'document_id'=p_document_id::text
  ) then
    insert into public.aggregate_load_events_v617(
      tenant_id,
      load_id,
      event_type,
      note,
      metadata,
      created_by
    )
    values(
      p_tenant_id,
      p_load_id,
      'document_linked',
      initcap(v_type)||' '||v_ref||' linked',
      jsonb_build_object(
        'document_type',v_type,
        'document_id',p_document_id,
        'reference',v_ref,
        'validated_quantity',v_document_qty,
        'allocated_before',v_allocated_qty,
        'load_quantity',v_load.quantity,
        'unit_code',v_load.unit_code
      ),
      auth.uid()
    );
  end if;

  return jsonb_build_object(
    'load_id',p_load_id,
    'load_number',v_load.load_number,
    'document_type',v_type,
    'document_id',p_document_id,
    'reference',v_ref,
    'validated_quantity',v_document_qty,
    'allocated_before',v_allocated_qty,
    'load_quantity',v_load.quantity,
    'unit_code',v_load.unit_code
  );
end
$$;

revoke all
on function public.aggregate_load_link_document_v617(
  uuid,uuid,text,uuid
)
from public,anon;

grant execute
on function public.aggregate_load_link_document_v617(
  uuid,uuid,text,uuid
)
to authenticated,service_role;

insert into public.thq_schema_releases(
  migration_no,
  schema_version,
  release_name,
  notes
)
values(
  310,
  '6.2.0-aggregate-freight-profitability',
  'Aggregate Freight Settlement & Load Profitability',
  'Adds hired-transporter freight configuration, partial freight settlements posted atomically through the authoritative THQ Expense writer, freight settlement audit/history, per-load material contribution and inbound landed-cost reporting, finance-permission masking, and aggregate Sale/Purchase load-allocation guards. No parallel payable, GST, stock or accounting writer is introduced.'
);
