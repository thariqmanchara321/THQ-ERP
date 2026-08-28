-- THQ ERP V4.7.1 — POS hold/resume and terminal operations completion.
begin;

-- Cashier Shift and Terminal Daily are POS operational capabilities. Ensure they are
-- available at business level whenever POS is enabled; per-terminal assignment still
-- controls whether an individual POS sees them.
insert into public.tenant_modules(tenant_id,module_key,enabled)
select tm.tenant_id,'cashier_shifts',true from public.tenant_modules tm where tm.module_key='pos' and tm.enabled
on conflict(tenant_id,module_key) do update set enabled=true;
insert into public.tenant_modules(tenant_id,module_key,enabled)
select tm.tenant_id,'terminal_day',true from public.tenant_modules tm where tm.module_key='pos' and tm.enabled
on conflict(tenant_id,module_key) do update set enabled=true;

-- New businesses enabling POS later should receive the operational POS capabilities.
create or replace function private.v471_pos_operational_modules_sync()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if new.module_key='pos' and new.enabled then
    insert into public.tenant_modules(tenant_id,module_key,enabled) values(new.tenant_id,'cashier_shifts',true)
      on conflict(tenant_id,module_key) do update set enabled=true;
    insert into public.tenant_modules(tenant_id,module_key,enabled) values(new.tenant_id,'terminal_day',true)
      on conflict(tenant_id,module_key) do update set enabled=true;
  end if;
  return new;
end $$;
drop trigger if exists trg_v471_pos_operational_modules_sync on public.tenant_modules;
create trigger trg_v471_pos_operational_modules_sync after insert or update of enabled on public.tenant_modules
for each row when(new.module_key='pos') execute function private.v471_pos_operational_modules_sync();

-- Compact held-sale feed for the billing screen. It returns the held state too, allowing
-- the product screen to restore without a second lookup if desired.
create or replace function public.pos_held_sales_feed_v471(p_tenant_id uuid,p_device_id uuid)
returns table(id uuid,hold_code text,label text,customer_id uuid,customer_name text,item_count integer,total numeric,held_by text,created_at timestamptz,state jsonb)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$declare v_location uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select location_id into v_location from public.business_devices where id=p_device_id and tenant_id=p_tenant_id and status='active';
  if v_location is null then raise exception 'Active terminal not found';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_user_location_allowed(p_tenant_id,v_location,'view') then raise exception 'Terminal access denied';end if;
  return query select h.id,h.hold_code,h.label,h.customer_id,c.name::text,
    coalesce(jsonb_array_length(coalesce(h.state->'items','[]'::jsonb)),0),coalesce((h.state->>'total')::numeric,0),
    coalesce(ul.username::text,''),h.created_at,h.state
  from public.pos_held_sales h left join public.customers c on c.id=h.customer_id left join public.user_login_names ul on ul.user_id=h.held_by
  where h.tenant_id=p_tenant_id and h.device_id=p_device_id order by h.created_at desc;
end $$;
grant execute on function public.pos_held_sales_feed_v471(uuid,uuid) to authenticated;

-- Return-aware Terminal Daily plus customer account receipts collected at this terminal.
create or replace function public.pos_terminal_day_v471(p_tenant_id uuid,p_device_id uuid,p_day date default current_date)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$declare v jsonb;v_receipts numeric:=0;v_receipt_count bigint:=0;v_receipt_rows jsonb:='[]'::jsonb;begin
  select public.pos_terminal_day_v45(p_tenant_id,p_device_id,p_day) into v;
  select coalesce(sum(r.amount),0),count(*) into v_receipts,v_receipt_count from public.customer_receipts r
  where r.tenant_id=p_tenant_id and r.device_id=p_device_id and r.receipt_date=p_day;
  select coalesce(jsonb_agg(jsonb_build_object('receipt_id',r.id,'receipt_number',r.receipt_number,'customer_id',r.customer_id,
    'customer_name',c.name,'amount',r.amount,'payment_method',r.payment_method,'reference_number',r.reference_number,'created_at',r.created_at)
    order by r.created_at desc),'[]'::jsonb) into v_receipt_rows
  from public.customer_receipts r join public.customers c on c.id=r.customer_id
  where r.tenant_id=p_tenant_id and r.device_id=p_device_id and r.receipt_date=p_day;
  return coalesce(v,'{}'::jsonb)||jsonb_build_object('customer_receipts',v_receipts,'customer_receipt_count',v_receipt_count,'customer_receipt_rows',v_receipt_rows);
end $$;
grant execute on function public.pos_terminal_day_v471(uuid,uuid,date) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(113,'4.7.1','Operational Stabilization Patch','POS held-sale feed, POS operational module provisioning, and customer receipts in Terminal Daily.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;
commit;
select 'THQ ERP V4.7.1 migration 113 POS operations ready' as status;
