-- FLEXI ERP V4 cashier shifts and cash drawer reconciliation.
begin;
create table if not exists public.cashier_shifts(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,location_id uuid not null references public.business_locations(id),device_id uuid not null references public.business_devices(id),user_id uuid not null references auth.users(id),
  shift_number text not null,status text not null default 'open' check(status in('open','closed','reviewed')),opened_at timestamptz not null default now(),closed_at timestamptz,
  opening_cash numeric not null default 0,expected_cash numeric,declared_cash numeric,difference numeric,closing_note text,reviewed_by uuid references auth.users(id),reviewed_at timestamptz,
  unique(tenant_id,shift_number)
);
create unique index if not exists ux_one_open_shift_per_device on public.cashier_shifts(device_id) where status='open';
create table if not exists public.cash_drawer_movements(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,shift_id uuid not null references public.cashier_shifts(id) on delete cascade,
  movement_type text not null check(movement_type in('opening','sale','refund','cash_in','cash_out','expense','closing_adjustment')),
  amount numeric not null,reference_type text,reference_id uuid,reference_number text,note text,created_by uuid references auth.users(id),created_at timestamptz not null default now()
);
alter table public.cashier_shifts enable row level security;alter table public.cash_drawer_movements enable row level security;revoke all on public.cashier_shifts,public.cash_drawer_movements from anon,authenticated;
create sequence if not exists public.cashier_shift_number_seq;

create or replace function public.cashier_shift_open_v4(p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_opening_cash numeric default 0)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_id uuid:=gen_random_uuid();v_no text;begin
  perform private.erp_validate_transaction_origin(p_tenant_id,p_location_id,p_device_id,'sales');
  if exists(select 1 from public.cashier_shifts where device_id=p_device_id and status='open') then raise exception 'This terminal already has an open shift';end if;
  v_no:='SHIFT-'||lpad(nextval('public.cashier_shift_number_seq')::text,6,'0');
  insert into public.cashier_shifts(id,tenant_id,location_id,device_id,user_id,shift_number,opening_cash) values(v_id,p_tenant_id,p_location_id,p_device_id,auth.uid(),v_no,greatest(coalesce(p_opening_cash,0),0));
  insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,note,created_by) values(p_tenant_id,v_id,'opening',greatest(coalesce(p_opening_cash,0),0),'Opening cash',auth.uid());
  return jsonb_build_object('shift_id',v_id,'shift_number',v_no,'opening_cash',greatest(coalesce(p_opening_cash,0),0),'status','open');
end $$;
grant execute on function public.cashier_shift_open_v4(uuid,uuid,uuid,numeric) to authenticated;

create or replace function public.cashier_shift_cash_move_v4(p_tenant_id uuid,p_shift_id uuid,p_type text,p_amount numeric,p_note text)
returns void language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v public.cashier_shifts%rowtype;begin
  select * into v from public.cashier_shifts where id=p_shift_id and tenant_id=p_tenant_id and status='open';if not found then raise exception 'Open shift not found';end if;
  if v.user_id<>auth.uid() and not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'pos.shift_manage') then raise exception 'Shift access denied';end if;
  if p_type not in('cash_in','cash_out') then raise exception 'Invalid cash movement';end if;if coalesce(p_amount,0)<=0 then raise exception 'Amount must be positive';end if;
  insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,note,created_by) values(p_tenant_id,p_shift_id,p_type,case when p_type='cash_out' then -abs(p_amount) else abs(p_amount) end,nullif(trim(coalesce(p_note,'')),''),auth.uid());
end $$;
grant execute on function public.cashier_shift_cash_move_v4(uuid,uuid,text,numeric,text) to authenticated;

create or replace function public.cashier_shift_close_v4(p_tenant_id uuid,p_shift_id uuid,p_declared_cash numeric,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v public.cashier_shifts%rowtype;v_expected numeric;v_diff numeric;begin
  select * into v from public.cashier_shifts where id=p_shift_id and tenant_id=p_tenant_id and status='open' for update;if not found then raise exception 'Open shift not found';end if;
  if v.user_id<>auth.uid() and not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'pos.shift_manage') then raise exception 'Shift access denied';end if;
  select coalesce(sum(amount),0) into v_expected from public.cash_drawer_movements where shift_id=p_shift_id;v_diff:=coalesce(p_declared_cash,0)-v_expected;
  update public.cashier_shifts set status='closed',closed_at=now(),expected_cash=v_expected,declared_cash=coalesce(p_declared_cash,0),difference=v_diff,closing_note=nullif(trim(coalesce(p_note,'')),'') where id=p_shift_id;
  return jsonb_build_object('shift_id',p_shift_id,'expected_cash',v_expected,'declared_cash',coalesce(p_declared_cash,0),'difference',v_diff,'status','closed');
end $$;
grant execute on function public.cashier_shift_close_v4(uuid,uuid,numeric,text) to authenticated;

create or replace function public.cashier_shift_current_v4(p_tenant_id uuid,p_device_id uuid)
returns jsonb language sql stable security definer set search_path=public,private,pg_temp
as $$
select coalesce((
  select to_jsonb(s) || jsonb_build_object(
    'cash_movement_total',coalesce(sum(m.amount),0),
    'expected_cash',coalesce(sum(m.amount),0),
    'cash_sales',coalesce(sum(case when m.movement_type='sale' then m.amount else 0 end),0),
    'cash_in',coalesce(sum(case when m.movement_type='cash_in' then m.amount else 0 end),0),
    'cash_out',abs(coalesce(sum(case when m.movement_type='cash_out' then m.amount else 0 end),0)),
    'cash_expenses',abs(coalesce(sum(case when m.movement_type='expense' then m.amount else 0 end),0)),
    'refunds',abs(coalesce(sum(case when m.movement_type='refund' then m.amount else 0 end),0))
  )
  from public.cashier_shifts s
  left join public.cash_drawer_movements m on m.shift_id=s.id
  where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open'
  group by s.id
  limit 1
),'{}'::jsonb)
$$;
grant execute on function public.cashier_shift_current_v4(uuid,uuid) to authenticated;

commit;
select 'Flexi ERP V4 cashier shifts ready' as status;
