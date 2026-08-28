-- THQ ERP V4.8.1 — universal inventory movement ledger enrichment.
begin;

alter table public.location_stock_movements
  add column if not exists base_quantity_delta numeric,
  add column if not exists display_quantity numeric,
  add column if not exists unit_id uuid references public.inventory_units_v481(id) on delete set null,
  add column if not exists unit_code text,
  add column if not exists conversion_to_base numeric,
  add column if not exists balance_before numeric,
  add column if not exists balance_after numeric,
  add column if not exists source_line_id uuid,
  add column if not exists movement_group text,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

update public.location_stock_movements m set base_quantity_delta=coalesce(base_quantity_delta,quantity_delta),display_quantity=coalesce(display_quantity,quantity_delta),conversion_to_base=coalesce(conversion_to_base,1),movement_group=coalesce(movement_group,case when movement_type like 'transfer_%' then 'transfer' when movement_type like 'production_%' then 'production' else movement_type end) where base_quantity_delta is null or display_quantity is null or conversion_to_base is null or movement_group is null;

-- Expand movement vocabulary for industrial use now so inventory won't need redesign later.
do $$ declare c record; begin
  for c in select conname from pg_constraint where conrelid='public.location_stock_movements'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%movement_type%' loop
    execute format('alter table public.location_stock_movements drop constraint %I',c.conname);
  end loop;
end $$;
alter table public.location_stock_movements add constraint location_stock_movements_type_v481_check check(movement_type in(
 'opening','purchase','sale','sale_return','sales_return','purchase_return','adjustment','stock_adjustment','adjustment_in','adjustment_out','transfer_in','transfer_out','stock_count',
 'damage','damage_restore','quarantine_in','quarantine_out','production_in','production_out','production_consumption','production_output',
 'wastage','scrap','scrap_sale','rework_in','rework_out','reservation','reservation_release','grn','delivery'
));
create index if not exists idx_location_stock_movements_source_v481 on public.location_stock_movements(tenant_id,reference_type,reference_id,variant_id);
create index if not exists idx_location_stock_movements_time_v481 on public.location_stock_movements(tenant_id,created_at desc,movement_type);

create or replace function private.v4_location_stock_apply(
  p_tenant_id uuid,p_location_id uuid,p_variant_id uuid,p_delta numeric,
  p_movement_type text,p_reference_type text default null,p_reference_id uuid default null,
  p_reference_number text default null,p_note text default null,p_device_id uuid default null,
  p_allow_negative boolean default false
) returns numeric language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_before numeric:=0;v_after numeric;v_cost numeric:=0;v_reserved numeric:=0;v_damaged numeric:=0;v_quarantine numeric:=0;v_available numeric:=0;v_unit uuid;v_unit_code text;
begin
  insert into public.location_stock_balances(tenant_id,location_id,variant_id,quantity,average_cost,updated_at)
  values(p_tenant_id,p_location_id,p_variant_id,0,0,now()) on conflict(tenant_id,location_id,variant_id) do nothing;
  select b.quantity,b.reserved_quantity,b.damaged_quantity,b.quarantine_quantity into v_before,v_reserved,v_damaged,v_quarantine
  from public.location_stock_balances b where b.tenant_id=p_tenant_id and b.location_id=p_location_id and b.variant_id=p_variant_id for update;
  v_before:=coalesce(v_before,0);v_reserved:=coalesce(v_reserved,0);v_damaged:=coalesce(v_damaged,0);v_quarantine:=coalesce(v_quarantine,0);
  v_available:=v_before-v_reserved-v_damaged-v_quarantine;v_after:=v_before+coalesce(p_delta,0);
  if not p_allow_negative and coalesce(p_delta,0)<0 and v_available+coalesce(p_delta,0)<-0.000001 then raise exception 'Insufficient available stock at selected location. Available: %, requested: %',v_available,abs(p_delta);end if;
  if not p_allow_negative and v_after<0 then raise exception 'Insufficient physical stock at selected location';end if;
  select coalesce(pv.cost_price,0) into v_cost from public.product_variants pv where pv.id=p_variant_id and pv.tenant_id=p_tenant_id;
  select pu.unit_id,u.code into v_unit,v_unit_code from public.product_units_v481 pu join public.inventory_units_v481 u on u.id=pu.unit_id where pu.tenant_id=p_tenant_id and pu.variant_id=p_variant_id and pu.is_base and pu.active limit 1;
  insert into public.location_product_settings(tenant_id,location_id,variant_id,active) values(p_tenant_id,p_location_id,p_variant_id,true) on conflict(tenant_id,location_id,variant_id) do nothing;
  update public.location_stock_balances set quantity=v_after,average_cost=case when v_cost<>0 then v_cost else average_cost end,updated_at=now() where tenant_id=p_tenant_id and location_id=p_location_id and variant_id=p_variant_id;
  insert into public.location_stock_movements(tenant_id,location_id,variant_id,movement_type,quantity_delta,base_quantity_delta,display_quantity,unit_id,unit_code,conversion_to_base,balance_before,balance_after,unit_cost,reference_type,reference_id,reference_number,note,created_by,device_id,movement_group)
  values(p_tenant_id,p_location_id,p_variant_id,p_movement_type,p_delta,p_delta,p_delta,v_unit,v_unit_code,1,v_before,v_after,v_cost,p_reference_type,p_reference_id,p_reference_number,nullif(trim(coalesce(p_note,'')),''),auth.uid(),p_device_id,case when p_movement_type like 'transfer_%' then 'transfer' when p_movement_type like 'production_%' then 'production' else p_movement_type end);
  return v_after;
end $$;
revoke all on function private.v4_location_stock_apply(uuid,uuid,uuid,numeric,text,text,uuid,text,text,uuid,boolean) from public;

create or replace function public.inventory_movement_history_v481(p_tenant_id uuid,p_variant_id uuid default null,p_location_id uuid default null,p_movement_type text default null,p_from timestamptz default null,p_to timestamptz default null,p_limit integer default 500)
returns table(movement_id uuid,location_id uuid,location_name text,variant_id uuid,product_name text,sku text,movement_type text,movement_group text,display_quantity numeric,unit_code text,base_quantity_delta numeric,balance_before numeric,balance_after numeric,unit_cost numeric,reference_type text,reference_number text,note text,occurred_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  return query select m.id,m.location_id,l.name,m.variant_id,p.name,pv.sku,m.movement_type,m.movement_group,coalesce(m.display_quantity,m.quantity_delta),m.unit_code,coalesce(m.base_quantity_delta,m.quantity_delta),m.balance_before,m.balance_after,m.unit_cost,m.reference_type,m.reference_number,m.note,m.created_at
  from public.location_stock_movements m join public.business_locations l on l.id=m.location_id join public.product_variants pv on pv.id=m.variant_id join public.products p on p.id=pv.product_id
  where m.tenant_id=p_tenant_id and (p_variant_id is null or m.variant_id=p_variant_id) and (p_location_id is null or m.location_id=p_location_id) and (p_movement_type is null or m.movement_type=p_movement_type) and (p_from is null or m.created_at>=p_from) and (p_to is null or m.created_at<p_to)
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_user_location_allowed(p_tenant_id,m.location_id,'view'))
  order by m.created_at desc limit greatest(1,least(coalesce(p_limit,500),5000));
end $$;
grant execute on function public.inventory_movement_history_v481(uuid,uuid,uuid,text,timestamptz,timestamptz,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(126,'4.8.1','Inventory & Unit Engine','Universal movement ledger enriched with unit/display/base quantities, before/after balances, source metadata and future production/wastage/scrap movement types.')
on conflict(migration_no) do update set notes=excluded.notes;
commit;
select 'THQ ERP V4.8.1 migration 126 movement ledger applied' as status;
