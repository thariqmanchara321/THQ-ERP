begin;

-- Production Supabase is already live with this migration.
-- Repository source mirror for THQ ERP v6.2.1 Direct Supply.

create or replace function public.aggregate_freight_configure_v620(
  p_tenant_id uuid,
  p_load_id uuid,
  p_freight_mode text,
  p_transporter_supplier_id uuid,
  p_freight_amount numeric,
  p_note text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_load public.aggregate_loads_v617%rowtype;
  v_mode text:=lower(trim(coalesce(p_freight_mode,'none')));
  v_amount numeric:=round(greatest(coalesce(p_freight_amount,0),0),2);
  v_paid numeric:=0;
  v_transporter_name text;
  v_effective_location_id uuid;
begin
  perform private.aggregate_yard_assert_freight_manage_v620(p_tenant_id);

  select * into v_load
  from public.aggregate_loads_v617
  where id=p_load_id and tenant_id=p_tenant_id
  for update;

  if v_load.id is null then raise exception 'Load not found'; end if;
  if v_load.status='cancelled' then
    raise exception 'Cancelled load freight cannot be changed';
  end if;

  select coalesce(m.operating_location_id,v_load.location_id)
  into v_effective_location_id
  from (select 1) x
  left join public.aggregate_direct_transit_locations_v621 m
    on m.tenant_id=p_tenant_id
   and m.transit_location_id=v_load.location_id;

  if v_effective_location_id is not null
     and not private.erp_document_scope_allowed(
       p_tenant_id,v_effective_location_id,v_effective_location_id,'view'
     ) then
    raise exception 'Location access required' using errcode='42501';
  end if;

  if v_mode not in('none','own','hired','supplier','customer','included') then
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
      v_amount,v_paid;
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

    select s.name into v_transporter_name
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
    tenant_id,load_id,event_type,note,metadata,created_by
  )
  values(
    p_tenant_id,p_load_id,'freight_configured',
    coalesce(nullif(trim(p_note),''),'Freight configuration updated'),
    jsonb_build_object(
      'old_mode',v_load.freight_mode,
      'new_mode',v_mode,
      'old_amount',v_load.freight_amount,
      'new_amount',v_amount,
      'old_transporter_supplier_id',v_load.transporter_supplier_id,
      'new_transporter_supplier_id',p_transporter_supplier_id,
      'already_settled_base',v_paid,
      'effective_location_id',v_effective_location_id
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
    'pending_base',greatest(v_amount-v_paid,0),
    'effective_location_id',v_effective_location_id
  );
end
$function$;

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
set search_path to 'public','private','pg_temp'
as $function$
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
  v_effective_location_id uuid;
begin
  perform private.aggregate_yard_assert_freight_manage_v620(p_tenant_id);

  if nullif(trim(coalesce(p_request_id,'')),'') is null then
    raise exception 'Request ID is required';
  end if;

  select * into v_existing
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

  select * into v_load
  from public.aggregate_loads_v617
  where id=p_load_id and tenant_id=p_tenant_id
  for update;

  if v_load.id is null then raise exception 'Load not found'; end if;
  if v_load.status='cancelled' then
    raise exception 'Cancelled load freight cannot be settled';
  end if;
  if v_load.location_id is null then
    raise exception 'A specific yard/store is required for freight settlement';
  end if;

  select coalesce(m.operating_location_id,v_load.location_id)
  into v_effective_location_id
  from (select 1) x
  left join public.aggregate_direct_transit_locations_v621 m
    on m.tenant_id=p_tenant_id
   and m.transit_location_id=v_load.location_id;

  if v_effective_location_id is null then
    raise exception 'A specific yard/store is required for freight settlement';
  end if;

  if not private.erp_document_scope_allowed(
    p_tenant_id,v_effective_location_id,v_effective_location_id,'view'
  ) then
    raise exception 'Location access required' using errcode='42501';
  end if;

  if v_load.freight_mode<>'hired' then
    raise exception 'Only hired-transporter freight is settled here';
  end if;
  if v_load.transporter_supplier_id is null then
    raise exception 'Select the transporter supplier before settlement';
  end if;

  select * into v_supplier
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
      v_amount,v_remaining;
  end if;
  if v_tax<0 then raise exception 'Tax cannot be negative'; end if;
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
    v_effective_location_id,
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
    tenant_id,load_id,location_id,transporter_supplier_id,
    expense_id,expense_number_snapshot,base_amount,tax_amount,
    round_off,total_paid,payment_method,reference_number,
    request_id,note,settled_by
  )
  values(
    p_tenant_id,p_load_id,v_effective_location_id,v_supplier.id,
    v_expense_id,v_expense_no,v_amount,v_tax,v_round,v_total,
    lower(trim(coalesce(p_payment_method,'cash'))),
    nullif(trim(coalesce(p_reference_number,'')),''),
    p_request_id,
    nullif(trim(coalesce(p_note,'')),''),
    auth.uid()
  )
  returning id into v_settlement_id;

  insert into public.aggregate_load_events_v617(
    tenant_id,load_id,event_type,note,metadata,created_by
  )
  values(
    p_tenant_id,p_load_id,'freight_settled',
    'Freight expense '||v_expense_no||' posted',
    jsonb_build_object(
      'settlement_id',v_settlement_id,
      'expense_id',v_expense_id,
      'expense_number',v_expense_no,
      'base_amount',v_amount,
      'tax_amount',v_tax,
      'round_off',v_round,
      'total_paid',v_total,
      'payment_method',lower(trim(coalesce(p_payment_method,'cash'))),
      'effective_location_id',v_effective_location_id
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
    'pending_base_after',greatest(v_load.freight_amount-v_paid-v_amount,0),
    'effective_location_id',v_effective_location_id,
    'idempotent_replay',false
  );
end
$function$;

create or replace function public.aggregate_freight_list_v620(
  p_tenant_id uuid,
  p_location_id uuid default null::uuid,
  p_query text default null::text,
  p_limit integer default 300
)
returns setof jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
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
    select fs.load_id,
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
    'location_id',coalesce(dm.operating_location_id,l.location_id),
    'transit_location_id',case when dm.transit_location_id is not null then l.location_id else null end,
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
      greatest(l.freight_amount-coalesce(pd.settled_base,0),0),2
    ),
    'freight_settlement_count',coalesce(pd.settlement_count,0),
    'freight_status',
      case
        when l.freight_mode<>'hired' or l.freight_amount<=0.005 then 'not_required'
        when coalesce(pd.settled_base,0)<=0.005 then 'pending'
        when coalesce(pd.settled_base,0)+0.005<l.freight_amount then 'part_paid'
        else 'settled'
      end,
    'sale_financials_visible',v_sale_fin,
    'purchase_financials_visible',v_purchase_fin,
    'material_revenue',
      case
        when v_sale_fin
          and l.direction in('outbound','direct_delivery')
          and sm.match_qty>0
        then round(sm.revenue_ex_tax*least(l.quantity/sm.match_qty,1),2)
        else null
      end,
    'material_cost',
      case
        when v_sale_fin
          and l.direction in('outbound','direct_delivery')
          and sm.match_qty>0
        then round(sm.cost_total*least(l.quantity/sm.match_qty,1),2)
        else null
      end,
    'material_gross_profit',
      case
        when v_sale_fin
          and l.direction in('outbound','direct_delivery')
          and sm.match_qty>0
        then round(
          (sm.revenue_ex_tax-sm.cost_total)
          *least(l.quantity/sm.match_qty,1),2
        )
        else null
      end,
    'contribution_after_freight',
      case
        when v_sale_fin
          and l.direction in('outbound','direct_delivery')
          and sm.match_qty>0
        then round(
          (
            (sm.revenue_ex_tax-sm.cost_total)
            *least(l.quantity/sm.match_qty,1)
          )-l.freight_amount,2
        )
        else null
      end,
    'sale_unclassified_additional_charges',
      case when v_sale_fin then round(coalesce(sa.additional_charges,0),2) else null end,
    'purchase_material_cost',
      case
        when v_purchase_fin
          and l.direction in('inbound','direct_delivery')
          and pm.match_qty>0
        then round(pm.cost_ex_tax*least(l.quantity/pm.match_qty,1),2)
        else null
      end,
    'inbound_landed_cost_after_freight',
      case
        when v_purchase_fin and l.direction='inbound' and pm.match_qty>0
        then round(
          (pm.cost_ex_tax*least(l.quantity/pm.match_qty,1))+l.freight_amount,2
        )
        else null
      end,
    'created_at',l.created_at
  )
  from public.aggregate_loads_v617 l
  left join public.aggregate_direct_transit_locations_v621 dm
    on dm.tenant_id=l.tenant_id
   and dm.transit_location_id=l.location_id
  left join public.customers c
    on c.id=l.customer_id and c.tenant_id=l.tenant_id
  left join public.suppliers sp
    on sp.id=l.supplier_id and sp.tenant_id=l.tenant_id
  left join public.suppliers ts
    on ts.id=l.transporter_supplier_id and ts.tenant_id=l.tenant_id
  left join public.aggregate_orders_v618 o
    on o.id=l.order_id and o.tenant_id=l.tenant_id
  left join public.sales sa
    on sa.id=l.sale_id and sa.tenant_id=l.tenant_id
  left join paid pd
    on pd.load_id=l.id
  left join lateral (
    select
      coalesce(sum(coalesce(si.entered_quantity,si.quantity)),0)::numeric as match_qty,
      coalesce(sum(si.taxable_amount),0)::numeric as revenue_ex_tax,
      coalesce(sum(si.cost_total),0)::numeric as cost_total
    from public.sale_items si
    where si.tenant_id=l.tenant_id
      and si.sale_id=l.sale_id
      and si.variant_id=l.variant_id
      and upper(coalesce(si.entered_unit_code,si.unit_code,''))=upper(l.unit_code)
  ) sm on true
  left join lateral (
    select
      coalesce(sum(coalesce(pi.entered_quantity,pi.quantity)),0)::numeric as match_qty,
      coalesce(sum(pi.taxable_amount),0)::numeric as cost_ex_tax
    from public.purchase_items pi
    where pi.tenant_id=l.tenant_id
      and pi.purchase_id=l.purchase_id
      and pi.variant_id=l.variant_id
      and upper(coalesce(pi.entered_unit_code,pi.unit_code,''))=upper(l.unit_code)
  ) pm on true
  where l.tenant_id=p_tenant_id
    and l.status<>'cancelled'
    and (
      p_location_id is null
      or coalesce(dm.operating_location_id,l.location_id)=p_location_id
    )
    and (
      coalesce(dm.operating_location_id,l.location_id) is null
      or private.erp_document_scope_allowed(
        p_tenant_id,
        coalesce(dm.operating_location_id,l.location_id),
        p_location_id,
        'view'
      )
    )
    and (
      p_query is null or trim(p_query)=''
      or l.load_number ilike '%'||trim(p_query)||'%'
      or l.product_name_snapshot ilike '%'||trim(p_query)||'%'
      or coalesce(l.vehicle_registration_snapshot,'') ilike '%'||trim(p_query)||'%'
      or coalesce(c.name,'') ilike '%'||trim(p_query)||'%'
      or coalesce(sp.name,'') ilike '%'||trim(p_query)||'%'
      or coalesce(ts.name,'') ilike '%'||trim(p_query)||'%'
      or coalesce(o.order_number,'') ilike '%'||trim(p_query)||'%'
    )
  order by l.created_at desc
  limit greatest(1,least(coalesce(p_limit,300),1000));
end
$function$;

revoke all on function public.aggregate_freight_configure_v620(uuid,uuid,text,uuid,numeric,text) from public,anon;
grant execute on function public.aggregate_freight_configure_v620(uuid,uuid,text,uuid,numeric,text) to authenticated,service_role;

revoke all on function public.aggregate_freight_settle_v620(uuid,uuid,uuid,date,numeric,numeric,numeric,text,text,text,uuid,text) from public,anon;
grant execute on function public.aggregate_freight_settle_v620(uuid,uuid,uuid,date,numeric,numeric,numeric,text,text,text,uuid,text) to authenticated,service_role;

revoke all on function public.aggregate_freight_list_v620(uuid,uuid,text,integer) from public,anon;
grant execute on function public.aggregate_freight_list_v620(uuid,uuid,text,integer) to authenticated,service_role;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  319,
  '6.2.1-aggregate-direct-freight-routing',
  'Aggregate Direct Supply Freight Routing',
  'Maps Direct Supply freight visibility and authorization back to the operating location, posts hired-freight Expense settlements to the operating yard/store instead of the hidden transit stock location, and includes linked Direct Supply Sales/Purchases in existing freight profitability metrics. The authoritative Expense, Sale, Purchase, GST and accounting writers remain unchanged.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
