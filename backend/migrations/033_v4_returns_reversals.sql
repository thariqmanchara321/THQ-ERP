-- FLEXI ERP V4 controlled corrections: returns, credit/debit notes, and safe void rules.
begin;

create table if not exists public.transaction_corrections(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
  entity_type text not null check(entity_type in('sale','purchase','expense','payment')),
  entity_id uuid not null,correction_type text not null check(correction_type in('void','cancel','return','credit_note','debit_note','reverse_recreate')),
  reason text not null,status text not null default 'posted' check(status in('draft','posted','cancelled')),
  created_by uuid references auth.users(id),created_at timestamptz not null default now(),metadata jsonb not null default '{}'::jsonb
);
create index if not exists idx_transaction_corrections_entity on public.transaction_corrections(tenant_id,entity_type,entity_id,created_at desc);
alter table public.transaction_corrections enable row level security;revoke all on public.transaction_corrections from anon,authenticated;

create table if not exists public.sales_returns(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
  sale_id uuid not null references public.sales(id),return_number text not null,location_id uuid not null references public.business_locations(id),device_id uuid references public.business_devices(id),
  return_date date not null default current_date,reason text not null,subtotal numeric not null default 0,tax_total numeric not null default 0,grand_total numeric not null default 0,
  refund_status text not null default 'credit_due' check(refund_status in('credit_due','refunded','applied','waived')),
  created_by uuid references auth.users(id),created_at timestamptz not null default now(),unique(tenant_id,return_number)
);
create table if not exists public.sales_return_items(
  id uuid primary key default gen_random_uuid(),sales_return_id uuid not null references public.sales_returns(id) on delete cascade,
  sale_item_id uuid not null references public.sale_items(id),variant_id uuid not null references public.product_variants(id),quantity numeric not null check(quantity>0),unit_price numeric not null,discount_amount numeric not null default 0,tax_rate numeric not null default 0,line_total numeric not null
);
create table if not exists public.purchase_returns(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
  purchase_id uuid not null references public.purchases(id),return_number text not null,location_id uuid not null references public.business_locations(id),device_id uuid references public.business_devices(id),
  return_date date not null default current_date,reason text not null,subtotal numeric not null default 0,tax_total numeric not null default 0,grand_total numeric not null default 0,
  credit_status text not null default 'supplier_credit' check(credit_status in('supplier_credit','refunded','applied','waived')),
  created_by uuid references auth.users(id),created_at timestamptz not null default now(),unique(tenant_id,return_number)
);
create table if not exists public.purchase_return_items(
  id uuid primary key default gen_random_uuid(),purchase_return_id uuid not null references public.purchase_returns(id) on delete cascade,
  purchase_item_id uuid not null references public.purchase_items(id),variant_id uuid not null references public.product_variants(id),quantity numeric not null check(quantity>0),unit_cost numeric not null,discount_amount numeric not null default 0,tax_rate numeric not null default 0,line_total numeric not null
);

alter table public.sales_returns enable row level security;alter table public.sales_return_items enable row level security;
alter table public.purchase_returns enable row level security;alter table public.purchase_return_items enable row level security;
revoke all on public.sales_returns,public.sales_return_items,public.purchase_returns,public.purchase_return_items from anon,authenticated;
create sequence if not exists public.sales_return_number_seq;create sequence if not exists public.purchase_return_number_seq;

create or replace function public.sales_return_create_v4(p_tenant_id uuid,p_sale_id uuid,p_items jsonb,p_reason text,p_device_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_loc uuid;v_id uuid:=gen_random_uuid();v_no text;x jsonb;v_si public.sale_items%rowtype;v_prev numeric;v_qty numeric;v_line numeric;v_sub numeric:=0;v_tax numeric:=0;v_total numeric:=0;begin
  if trim(coalesce(p_reason,''))='' then raise exception 'Return reason is required';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'sales.return') and not private.erp_has_permission(p_tenant_id,'sales.manage') then raise exception 'Sales return permission required';end if;
  select location_id into v_loc from public.document_origins where tenant_id=p_tenant_id and entity_type='sale' and entity_id=p_sale_id;
  if v_loc is null then raise exception 'Original sale does not have a store origin';end if;perform private.v4_location_access(p_tenant_id,v_loc,'operate');
  v_no:='SRN-'||lpad(nextval('public.sales_return_number_seq')::text,6,'0');
  insert into public.sales_returns(id,tenant_id,sale_id,return_number,location_id,device_id,reason,created_by) values(v_id,p_tenant_id,p_sale_id,v_no,v_loc,p_device_id,trim(p_reason),auth.uid());
  for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    select * into v_si from public.sale_items where id=(x->>'sale_item_id')::uuid and sale_id=p_sale_id;if not found then raise exception 'Sale item not found';end if;
    v_qty:=(x->>'quantity')::numeric;if v_qty<=0 then raise exception 'Return quantity must be positive';end if;
    select coalesce(sum(i.quantity),0) into v_prev from public.sales_return_items i join public.sales_returns r on r.id=i.sales_return_id where r.sale_id=p_sale_id and i.sale_item_id=v_si.id;
    if v_prev+v_qty>v_si.quantity then raise exception 'Return quantity exceeds sold quantity';end if;
    v_line:=round(((v_si.unit_price*v_qty)-coalesce(v_si.discount_amount,0)*(v_qty/v_si.quantity))*(1+coalesce(v_si.tax_rate,0)/100.0),2);
    insert into public.sales_return_items(sales_return_id,sale_item_id,variant_id,quantity,unit_price,discount_amount,tax_rate,line_total)
    values(v_id,v_si.id,v_si.variant_id,v_qty,v_si.unit_price,coalesce(v_si.discount_amount,0)*(v_qty/v_si.quantity),coalesce(v_si.tax_rate,0),v_line);
    v_sub:=v_sub+(v_si.unit_price*v_qty)-coalesce(v_si.discount_amount,0)*(v_qty/v_si.quantity);v_tax:=v_tax+(v_line-((v_si.unit_price*v_qty)-coalesce(v_si.discount_amount,0)*(v_qty/v_si.quantity)));v_total:=v_total+v_line;
    perform public.inventory_adjust_stock(p_tenant_id,v_si.variant_id,v_qty,'Sale return • '||v_no);
    perform private.v4_location_stock_apply(p_tenant_id,v_loc,v_si.variant_id,v_qty,'sale_return','sales_return',v_id,v_no,trim(p_reason),p_device_id,false);
  end loop;
  update public.sales_returns set subtotal=v_sub,tax_total=v_tax,grand_total=v_total where id=v_id;
  insert into public.transaction_corrections(tenant_id,entity_type,entity_id,correction_type,reason,created_by,metadata) values(p_tenant_id,'sale',p_sale_id,'return',trim(p_reason),auth.uid(),jsonb_build_object('return_id',v_id,'return_number',v_no,'amount',v_total));
  return jsonb_build_object('return_id',v_id,'return_number',v_no,'grand_total',v_total,'refund_status','credit_due');
end $$;
grant execute on function public.sales_return_create_v4(uuid,uuid,jsonb,text,uuid) to authenticated;

create or replace function public.purchase_return_create_v4(p_tenant_id uuid,p_purchase_id uuid,p_items jsonb,p_reason text,p_device_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_loc uuid;v_id uuid:=gen_random_uuid();v_no text;x jsonb;v_pi public.purchase_items%rowtype;v_prev numeric;v_qty numeric;v_line numeric;v_sub numeric:=0;v_tax numeric:=0;v_total numeric:=0;begin
  if trim(coalesce(p_reason,''))='' then raise exception 'Return reason is required';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'purchases.return') and not private.erp_has_permission(p_tenant_id,'purchases.manage') then raise exception 'Purchase return permission required';end if;
  select location_id into v_loc from public.document_origins where tenant_id=p_tenant_id and entity_type='purchase' and entity_id=p_purchase_id;
  if v_loc is null then raise exception 'Original purchase does not have a store origin';end if;perform private.v4_location_access(p_tenant_id,v_loc,'operate');
  v_no:='PRN-'||lpad(nextval('public.purchase_return_number_seq')::text,6,'0');
  insert into public.purchase_returns(id,tenant_id,purchase_id,return_number,location_id,device_id,reason,created_by) values(v_id,p_tenant_id,p_purchase_id,v_no,v_loc,p_device_id,trim(p_reason),auth.uid());
  for x in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    select * into v_pi from public.purchase_items where id=(x->>'purchase_item_id')::uuid and purchase_id=p_purchase_id;if not found then raise exception 'Purchase item not found';end if;
    v_qty:=(x->>'quantity')::numeric;if v_qty<=0 then raise exception 'Return quantity must be positive';end if;
    select coalesce(sum(i.quantity),0) into v_prev from public.purchase_return_items i join public.purchase_returns r on r.id=i.purchase_return_id where r.purchase_id=p_purchase_id and i.purchase_item_id=v_pi.id;
    if v_prev+v_qty>v_pi.quantity then raise exception 'Return quantity exceeds purchased quantity';end if;
    if coalesce((select quantity-reserved_quantity-damaged_quantity-quarantine_quantity from public.location_stock_balances where tenant_id=p_tenant_id and location_id=v_loc and variant_id=v_pi.variant_id),0)<v_qty then raise exception 'Insufficient branch stock for purchase return';end if;
    v_line:=round(((v_pi.unit_cost*v_qty)-coalesce(v_pi.discount_amount,0)*(v_qty/v_pi.quantity))*(1+coalesce(v_pi.tax_rate,0)/100.0),2);
    insert into public.purchase_return_items(purchase_return_id,purchase_item_id,variant_id,quantity,unit_cost,discount_amount,tax_rate,line_total)
    values(v_id,v_pi.id,v_pi.variant_id,v_qty,v_pi.unit_cost,coalesce(v_pi.discount_amount,0)*(v_qty/v_pi.quantity),coalesce(v_pi.tax_rate,0),v_line);
    v_sub:=v_sub+(v_pi.unit_cost*v_qty)-coalesce(v_pi.discount_amount,0)*(v_qty/v_pi.quantity);v_tax:=v_tax+(v_line-((v_pi.unit_cost*v_qty)-coalesce(v_pi.discount_amount,0)*(v_qty/v_pi.quantity)));v_total:=v_total+v_line;
    perform public.inventory_adjust_stock(p_tenant_id,v_pi.variant_id,-v_qty,'Purchase return • '||v_no);
    perform private.v4_location_stock_apply(p_tenant_id,v_loc,v_pi.variant_id,-v_qty,'purchase_return','purchase_return',v_id,v_no,trim(p_reason),p_device_id,false);
  end loop;
  update public.purchase_returns set subtotal=v_sub,tax_total=v_tax,grand_total=v_total where id=v_id;
  insert into public.transaction_corrections(tenant_id,entity_type,entity_id,correction_type,reason,created_by,metadata) values(p_tenant_id,'purchase',p_purchase_id,'return',trim(p_reason),auth.uid(),jsonb_build_object('return_id',v_id,'return_number',v_no,'amount',v_total));
  return jsonb_build_object('return_id',v_id,'return_number',v_no,'grand_total',v_total,'credit_status','supplier_credit');
end $$;
grant execute on function public.purchase_return_create_v4(uuid,uuid,jsonb,text,uuid) to authenticated;

-- Safe void only when no money has changed hands and no returns exist. Otherwise use return/refund workflow.
create or replace function public.sales_void_v4(p_tenant_id uuid,p_sale_id uuid,p_reason text,p_device_id uuid default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_loc uuid;v_ref text;r record;begin
  if trim(coalesce(p_reason,''))='' then raise exception 'Void reason is required';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'sales.void') then raise exception 'Sales void permission required';end if;
  if exists(select 1 from public.sale_payments where sale_id=p_sale_id and amount<>0) then raise exception 'Paid sale cannot be voided directly. Use return/refund workflow.';end if;
  if exists(select 1 from public.sales_returns where sale_id=p_sale_id) then raise exception 'Sale with returns cannot be voided';end if;
  select o.location_id,s.sale_number into v_loc,v_ref from public.sales s join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id where s.id=p_sale_id and s.tenant_id=p_tenant_id for update;
  if v_loc is null then raise exception 'Sale not found or has no branch origin';end if;perform private.v4_location_access(p_tenant_id,v_loc,'operate');
  for r in select si.variant_id,si.quantity,p.item_type from public.sale_items si join public.product_variants pv on pv.id=si.variant_id join public.products p on p.id=pv.product_id where si.sale_id=p_sale_id loop
    if r.item_type='stock' then perform public.inventory_adjust_stock(p_tenant_id,r.variant_id,r.quantity,'Void sale • '||v_ref);perform private.v4_location_stock_apply(p_tenant_id,v_loc,r.variant_id,r.quantity,'sale_return','sale',p_sale_id,v_ref,'Void • '||trim(p_reason),p_device_id,false);end if;
  end loop;
  update public.sales set status='void' where id=p_sale_id and tenant_id=p_tenant_id;
  insert into public.transaction_corrections(tenant_id,entity_type,entity_id,correction_type,reason,created_by) values(p_tenant_id,'sale',p_sale_id,'void',trim(p_reason),auth.uid());
end $$;
grant execute on function public.sales_void_v4(uuid,uuid,text,uuid) to authenticated;

create or replace function public.purchase_void_v4(p_tenant_id uuid,p_purchase_id uuid,p_reason text,p_device_id uuid default null)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_loc uuid;v_ref text;r record;begin
  if trim(coalesce(p_reason,''))='' then raise exception 'Void reason is required';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'purchases.void') then raise exception 'Purchase void permission required';end if;
  if exists(select 1 from public.purchase_payments where purchase_id=p_purchase_id and amount<>0) then raise exception 'Paid purchase cannot be voided directly. Use purchase return/refund workflow.';end if;
  if exists(select 1 from public.purchase_returns where purchase_id=p_purchase_id) then raise exception 'Purchase with returns cannot be voided';end if;
  select o.location_id,p.purchase_number into v_loc,v_ref from public.purchases p join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id where p.id=p_purchase_id and p.tenant_id=p_tenant_id for update;
  if v_loc is null then raise exception 'Purchase not found or has no branch origin';end if;perform private.v4_location_access(p_tenant_id,v_loc,'operate');
  for r in select pi.variant_id,pi.quantity,pr.item_type from public.purchase_items pi join public.product_variants pv on pv.id=pi.variant_id join public.products pr on pr.id=pv.product_id where pi.purchase_id=p_purchase_id loop
    if r.item_type='stock' then
      if coalesce((select quantity from public.location_stock_balances where tenant_id=p_tenant_id and location_id=v_loc and variant_id=r.variant_id),0)<r.quantity then raise exception 'Cannot void purchase because branch stock has already been consumed';end if;
      perform public.inventory_adjust_stock(p_tenant_id,r.variant_id,-r.quantity,'Void purchase • '||v_ref);perform private.v4_location_stock_apply(p_tenant_id,v_loc,r.variant_id,-r.quantity,'purchase_return','purchase',p_purchase_id,v_ref,'Void • '||trim(p_reason),p_device_id,false);
    end if;
  end loop;
  update public.purchases set status='void' where id=p_purchase_id and tenant_id=p_tenant_id;
  insert into public.transaction_corrections(tenant_id,entity_type,entity_id,correction_type,reason,created_by) values(p_tenant_id,'purchase',p_purchase_id,'void',trim(p_reason),auth.uid());
end $$;
grant execute on function public.purchase_void_v4(uuid,uuid,text,uuid) to authenticated;

commit;
select 'Flexi ERP V4 returns and controlled reversal foundation ready' as status;
