-- THQ ERP V4.7.2 — Terminal Operations Redesign
-- Cashier Shift and Terminal Daily are independent POS capabilities.
-- Cashier Shift owns shift timing/cash accountability. Terminal Daily is read-only reporting.
begin;

-- -----------------------------------------------------------------------------
-- Module definitions: independent per-terminal activation/deactivation.
-- -----------------------------------------------------------------------------
insert into public.modules(key,name,description,category,is_core,sort_order,is_active,is_beta,requires_configuration)
values
  ('cashier_shifts','Cashier Shift','Cashier start/end time, opening/closing cash and drawer accountability','POS',false,36,true,false,true),
  ('terminal_day','Terminal Daily','Read-only daily summary for one POS terminal; never opens or closes cashier shifts','POS',false,37,true,false,false)
on conflict(key) do update set
  name=excluded.name,
  description=excluded.description,
  category=excluded.category,
  sort_order=excluded.sort_order,
  is_active=true,
  requires_configuration=excluded.requires_configuration;

-- Both only depend on POS. Neither depends on the other.
delete from public.module_dependencies
where module_key in('cashier_shifts','terminal_day')
  and depends_on_module_key in('cashier_shifts','terminal_day');
insert into public.module_dependencies(module_key,depends_on_module_key)
values ('cashier_shifts','pos'),('terminal_day','pos')
on conflict do nothing;

-- -----------------------------------------------------------------------------
-- Shift edit audit. Shift timestamps/amounts are editable but original values
-- are preserved here. This is deliberately separate from attendance for now.
-- -----------------------------------------------------------------------------
alter table public.cashier_shifts add column if not exists opening_note text;
alter table public.cashier_shifts add column if not exists last_edited_by uuid references auth.users(id);
alter table public.cashier_shifts add column if not exists last_edited_at timestamptz;
alter table public.cashier_shifts add column if not exists edit_count integer not null default 0;

create table if not exists public.cashier_shift_edits(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  shift_id uuid not null references public.cashier_shifts(id) on delete cascade,
  changed_by uuid references auth.users(id),
  changed_at timestamptz not null default now(),
  reason text not null,
  before_state jsonb not null,
  after_state jsonb not null
);
create index if not exists ix_cashier_shift_edits_shift on public.cashier_shift_edits(shift_id,changed_at desc);
alter table public.cashier_shift_edits enable row level security;
revoke all on public.cashier_shift_edits from anon,authenticated;

-- -----------------------------------------------------------------------------
-- Helpers.
-- -----------------------------------------------------------------------------
create or replace function private.v472_shift_module_enabled(p_tenant_id uuid,p_device_id uuid)
returns boolean language sql stable security definer set search_path=public,private,pg_temp
as $$
  select exists(
    select 1
    from public.business_devices d
    where d.id=p_device_id
      and d.tenant_id=p_tenant_id
      and d.app_type='pos'
      and d.status='active'
      and 'cashier_shifts'=any(coalesce(d.allowed_modules,'{}'::text[]))
  )
  and exists(
    select 1 from public.tenant_modules tm
    where tm.tenant_id=p_tenant_id and tm.module_key='cashier_shifts' and tm.enabled
  )
$$;
revoke all on function private.v472_shift_module_enabled(uuid,uuid) from public;

create or replace function private.v472_terminal_day_module_enabled(p_tenant_id uuid,p_device_id uuid)
returns boolean language sql stable security definer set search_path=public,private,pg_temp
as $$
  select exists(
    select 1
    from public.business_devices d
    where d.id=p_device_id
      and d.tenant_id=p_tenant_id
      and d.app_type='pos'
      and d.status='active'
      and 'terminal_day'=any(coalesce(d.allowed_modules,'{}'::text[]))
  )
  and exists(
    select 1 from public.tenant_modules tm
    where tm.tenant_id=p_tenant_id and tm.module_key='terminal_day' and tm.enabled
  )
$$;
revoke all on function private.v472_terminal_day_module_enabled(uuid,uuid) from public;

-- Never strand an open shift by disabling its module. Terminal Daily may be
-- enabled/disabled at any time because it is read-only.
create or replace function private.v472_guard_operational_module_change()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if old.app_type='pos'
     and 'cashier_shifts'=any(coalesce(old.allowed_modules,'{}'::text[]))
     and not ('cashier_shifts'=any(coalesce(new.allowed_modules,'{}'::text[])))
     and exists(select 1 from public.cashier_shifts s where s.device_id=old.id and s.status='open') then
    raise exception 'End the open Cashier Shift before deactivating Cashier Shift for this POS';
  end if;
  return new;
end $$;
drop trigger if exists trg_v472_guard_operational_module_change on public.business_devices;
create trigger trg_v472_guard_operational_module_change
before update of allowed_modules on public.business_devices
for each row execute function private.v472_guard_operational_module_change();

-- The same safety rule applies if Cashier Shift is disabled at business level.
-- Terminal Daily remains freely toggleable because it never owns operational state.
create or replace function private.v472_guard_tenant_operational_module_change()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_tenant_id uuid:=old.tenant_id;
  v_key text:=old.module_key;
  v_was_enabled boolean:=coalesce(old.enabled,false);
  v_will_enabled boolean:=case when tg_op='DELETE' then false else coalesce(new.enabled,false) end;
begin
  if v_key='cashier_shifts' and v_was_enabled and not v_will_enabled
     and exists(
       select 1 from public.cashier_shifts s
       where s.tenant_id=v_tenant_id and s.status='open'
     ) then
    raise exception 'End all open Cashier Shifts before deactivating Cashier Shift for this business';
  end if;
  if tg_op='DELETE' then return old;end if;
  return new;
end $$;

drop trigger if exists trg_v472_guard_tenant_operational_module_update on public.tenant_modules;
create trigger trg_v472_guard_tenant_operational_module_update
before update of enabled on public.tenant_modules
for each row execute function private.v472_guard_tenant_operational_module_change();
drop trigger if exists trg_v472_guard_tenant_operational_module_delete on public.tenant_modules;
create trigger trg_v472_guard_tenant_operational_module_delete
before delete on public.tenant_modules
for each row execute function private.v472_guard_tenant_operational_module_change();

create or replace function private.v472_shift_expected_cash(p_shift_id uuid)
returns numeric language sql stable security definer set search_path=public,private,pg_temp
as $$
  select coalesce(sum(m.amount),0)::numeric
  from public.cash_drawer_movements m
  where m.shift_id=p_shift_id
$$;
revoke all on function private.v472_shift_expected_cash(uuid) from public;

create or replace function private.v472_shift_period_conflicts(
  p_device_id uuid,p_shift_id uuid,p_opened_at timestamptz,p_closed_at timestamptz
) returns boolean language sql stable security definer set search_path=public,private,pg_temp
as $$
  select exists(
    select 1
    from public.cashier_shifts s
    where s.device_id=p_device_id
      and (p_shift_id is null or s.id<>p_shift_id)
      and s.opened_at < coalesce(p_closed_at,'infinity'::timestamptz)
      and coalesce(s.closed_at,'infinity'::timestamptz) > p_opened_at
  )
$$;
revoke all on function private.v472_shift_period_conflicts(uuid,uuid,timestamptz,timestamptz) from public;

-- -----------------------------------------------------------------------------
-- Open shift. Time defaults in the UI to now, but is accepted explicitly so
-- authorized users can correct the start time. Opening cash is equally editable.
-- -----------------------------------------------------------------------------
create or replace function public.cashier_shift_open_v472(
  p_tenant_id uuid,
  p_location_id uuid,
  p_device_id uuid,
  p_opening_cash numeric,
  p_opened_at timestamptz,
  p_note text,
  p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_existing jsonb;
  v_id uuid:=gen_random_uuid();
  v_no text;
  v_opened timestamptz:=coalesce(p_opened_at,now());
  v_cash numeric:=greatest(coalesce(p_opening_cash,0),0);
  v_location uuid;
begin
  v_existing:=private.v47_request_existing(p_tenant_id,p_request_id,'shift.open.v472');
  if v_existing is not null then return v_existing;end if;

  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.v472_shift_module_enabled(p_tenant_id,p_device_id) then raise exception 'Cashier Shift is disabled for this POS';end if;

  select d.location_id into v_location
  from public.business_devices d
  where d.id=p_device_id and d.tenant_id=p_tenant_id and d.status='active' for update;
  if v_location is null then raise exception 'Active POS terminal not found';end if;
  if v_location<>p_location_id then raise exception 'POS location changed. Refresh and try again';end if;
  if v_opened>now()+interval '5 minutes' then raise exception 'Shift start time cannot be in the future';end if;
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_user_location_allowed(p_tenant_id,v_location,'operate') then raise exception 'Terminal access denied';end if;

  if exists(select 1 from public.cashier_shifts s where s.device_id=p_device_id and s.status='open') then
    raise exception 'This terminal already has an open shift';
  end if;
  if private.v472_shift_period_conflicts(p_device_id,null,v_opened,null) then
    raise exception 'Shift start time overlaps an existing shift on this terminal';
  end if;

  v_no:='SHIFT-'||lpad(nextval('public.cashier_shift_number_seq')::text,6,'0');
  insert into public.cashier_shifts(
    id,tenant_id,location_id,device_id,user_id,shift_number,status,opened_at,opening_cash,opening_note
  ) values(
    v_id,p_tenant_id,v_location,p_device_id,auth.uid(),v_no,'open',v_opened,v_cash,nullif(trim(coalesce(p_note,'')),'')
  );
  insert into public.cash_drawer_movements(
    tenant_id,shift_id,movement_type,amount,note,created_by,created_at
  ) values(
    p_tenant_id,v_id,'opening',v_cash,'Opening cash',auth.uid(),v_opened
  );

  return private.v47_request_complete(
    p_tenant_id,p_request_id,'shift.open.v472',
    jsonb_build_object(
      'shift_id',v_id,'shift_number',v_no,'status','open',
      'opened_at',v_opened,'opening_cash',v_cash
    )
  );
end $$;
grant execute on function public.cashier_shift_open_v472(uuid,uuid,uuid,numeric,timestamptz,text,text) to authenticated;

-- -----------------------------------------------------------------------------
-- Close shift. End time defaults in UI to now but can be edited before save.
-- No Terminal Daily state is touched here.
-- -----------------------------------------------------------------------------
create or replace function public.cashier_shift_close_v472(
  p_tenant_id uuid,
  p_shift_id uuid,
  p_declared_cash numeric,
  p_closed_at timestamptz,
  p_note text,
  p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_existing jsonb;
  v public.cashier_shifts%rowtype;
  v_closed timestamptz:=coalesce(p_closed_at,now());
  v_expected numeric;
  v_declared numeric:=greatest(coalesce(p_declared_cash,0),0);
  v_diff numeric;
begin
  v_existing:=private.v47_request_existing(p_tenant_id,p_request_id,'shift.close.v472');
  if v_existing is not null then return v_existing;end if;

  select s.* into v from public.cashier_shifts s
  where s.id=p_shift_id and s.tenant_id=p_tenant_id and s.status='open' for update;
  if not found then raise exception 'Open shift not found';end if;
  if v.user_id<>auth.uid() and not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'pos.shift_manage') then raise exception 'Shift access denied';end if;
  if v_closed<v.opened_at then raise exception 'Shift end time cannot be before shift start time';end if;
  if v_closed>now()+interval '5 minutes' then raise exception 'Shift end time cannot be in the future';end if;
  if private.v472_shift_period_conflicts(v.device_id,v.id,v.opened_at,v_closed) then
    raise exception 'Shift end time overlaps another shift on this terminal';
  end if;

  v_expected:=private.v472_shift_expected_cash(v.id);
  v_diff:=v_declared-v_expected;
  update public.cashier_shifts set
    status='closed',closed_at=v_closed,expected_cash=v_expected,declared_cash=v_declared,
    difference=v_diff,closing_note=nullif(trim(coalesce(p_note,'')),'')
  where cashier_shifts.id=v.id;

  return private.v47_request_complete(
    p_tenant_id,p_request_id,'shift.close.v472',
    jsonb_build_object(
      'shift_id',v.id,'shift_number',v.shift_number,'status','closed',
      'opened_at',v.opened_at,'closed_at',v_closed,
      'opening_cash',v.opening_cash,'expected_cash',v_expected,
      'declared_cash',v_declared,'difference',v_diff
    )
  );
end $$;
grant execute on function public.cashier_shift_close_v472(uuid,uuid,numeric,timestamptz,text,text) to authenticated;

-- -----------------------------------------------------------------------------
-- Editable shifts with an immutable correction trail.
-- Current cashier may edit their own OPEN shift. Closed shifts (or another
-- cashier's shift) require owner or pos.shift_manage.
-- -----------------------------------------------------------------------------
create or replace function public.cashier_shift_edit_v472(
  p_tenant_id uuid,
  p_shift_id uuid,
  p_opened_at timestamptz,
  p_opening_cash numeric,
  p_closed_at timestamptz,
  p_declared_cash numeric,
  p_note text,
  p_reason text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v public.cashier_shifts%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_opened timestamptz;
  v_closed timestamptz;
  v_opening numeric;
  v_declared numeric;
  v_expected numeric;
  v_reason text:=nullif(trim(coalesce(p_reason,'')),'');
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if v_reason is null then raise exception 'Edit reason is required';end if;
  select s.* into v from public.cashier_shifts s where s.id=p_shift_id and s.tenant_id=p_tenant_id for update;
  if not found then raise exception 'Shift not found';end if;

  if v.status='open' and v.user_id=auth.uid() then
    null;
  elsif not private.erp_user_is_owner(p_tenant_id)
        and not private.erp_has_permission(p_tenant_id,'pos.shift_manage') then
    raise exception 'Owner or Shift Manage permission is required to edit this shift';
  end if;

  v_opened:=coalesce(p_opened_at,v.opened_at);
  v_opening:=greatest(coalesce(p_opening_cash,v.opening_cash,0),0);
  if v_opened>now()+interval '5 minutes' then raise exception 'Shift start time cannot be in the future';end if;
  if v.status='open' then
    v_closed:=null;
    v_declared:=null;
  else
    v_closed:=coalesce(p_closed_at,v.closed_at);
    v_declared:=greatest(coalesce(p_declared_cash,v.declared_cash,0),0);
    if v_closed is null then raise exception 'Closed shift requires an end time';end if;
    if v_closed<v_opened then raise exception 'Shift end time cannot be before shift start time';end if;
    if v_closed>now()+interval '5 minutes' then raise exception 'Shift end time cannot be in the future';end if;
  end if;

  if private.v472_shift_period_conflicts(v.device_id,v.id,v_opened,v_closed) then
    raise exception 'Edited shift time overlaps another shift on this terminal';
  end if;

  v_before:=to_jsonb(v);
  update public.cashier_shifts set
    opened_at=v_opened,
    opening_cash=v_opening,
    closed_at=v_closed,
    declared_cash=v_declared,
    closing_note=case when v.status='closed' then nullif(trim(coalesce(p_note,closing_note,'')),'') else closing_note end,
    last_edited_by=auth.uid(),
    last_edited_at=now(),
    edit_count=coalesce(edit_count,0)+1
  where cashier_shifts.id=v.id;

  update public.cash_drawer_movements set amount=v_opening,created_at=v_opened
  where shift_id=v.id and movement_type='opening';
  if not found then
    insert into public.cash_drawer_movements(
      tenant_id,shift_id,movement_type,amount,note,created_by,created_at
    ) values(p_tenant_id,v.id,'opening',v_opening,'Opening cash (recreated by shift correction)',auth.uid(),v_opened);
  end if;

  v_expected:=private.v472_shift_expected_cash(v.id);
  if v.status='closed' then
    update public.cashier_shifts set expected_cash=v_expected,difference=v_declared-v_expected where cashier_shifts.id=v.id;
  end if;

  select to_jsonb(s) into v_after from public.cashier_shifts s where s.id=v.id;
  insert into public.cashier_shift_edits(tenant_id,shift_id,changed_by,reason,before_state,after_state)
  values(p_tenant_id,v.id,auth.uid(),v_reason,v_before,v_after);

  return v_after||jsonb_build_object('expected_cash_now',v_expected);
end $$;
grant execute on function public.cashier_shift_edit_v472(uuid,uuid,timestamptz,numeric,timestamptz,numeric,text,text) to authenticated;

-- -----------------------------------------------------------------------------
-- Current shift and history. These are reporting/read functions only.
-- -----------------------------------------------------------------------------
create or replace function public.cashier_shift_current_v472(p_tenant_id uuid,p_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_location uuid;v_result jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select d.location_id into v_location from public.business_devices d
  where d.id=p_device_id and d.tenant_id=p_tenant_id and d.status='active';
  if v_location is null then raise exception 'Active terminal not found';end if;
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_user_location_allowed(p_tenant_id,v_location,'view') then raise exception 'Terminal access denied';end if;

  select coalesce(to_jsonb(x),'{}'::jsonb) into v_result from (
    select s.*,
      coalesce(ul.username,'')::text cashier_name,
      coalesce(sum(m.amount),0)::numeric cash_movement_total,
      coalesce(sum(m.amount),0)::numeric expected_cash_now,
      coalesce(sum(case when m.movement_type='sale' then m.amount else 0 end),0)::numeric cash_sales,
      coalesce(sum(case when m.movement_type='receipt' then m.amount else 0 end),0)::numeric customer_receipts,
      coalesce(sum(case when m.movement_type='cash_in' then m.amount else 0 end),0)::numeric cash_in,
      abs(coalesce(sum(case when m.movement_type='cash_out' then m.amount else 0 end),0))::numeric cash_out,
      abs(coalesce(sum(case when m.movement_type='expense' then m.amount else 0 end),0))::numeric cash_expenses,
      abs(coalesce(sum(case when m.movement_type='refund' then m.amount else 0 end),0))::numeric refunds
    from public.cashier_shifts s
    left join public.cash_drawer_movements m on m.shift_id=s.id
    left join public.user_login_names ul on ul.user_id=s.user_id
    where s.tenant_id=p_tenant_id and s.device_id=p_device_id and s.status='open'
    group by s.id,ul.username
    order by s.opened_at desc limit 1
  ) x;
  return coalesce(v_result,'{}'::jsonb);
end $$;
grant execute on function public.cashier_shift_current_v472(uuid,uuid) to authenticated;

create or replace function public.cashier_shift_history_v472(
  p_tenant_id uuid,p_device_id uuid,p_from date,p_to date,p_limit integer default 50
) returns table(
  id uuid,shift_number text,user_id uuid,cashier_name text,status text,
  opened_at timestamptz,closed_at timestamptz,opening_cash numeric,
  expected_cash numeric,declared_cash numeric,difference numeric,closing_note text,
  edit_count integer,last_edited_at timestamptz
) language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v_location uuid;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select d.location_id into v_location from public.business_devices d
  where d.id=p_device_id and d.tenant_id=p_tenant_id and d.status='active';
  if v_location is null then raise exception 'Active terminal not found';end if;
  if not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_user_location_allowed(p_tenant_id,v_location,'view') then raise exception 'Terminal access denied';end if;

  return query
  select s.id,s.shift_number,s.user_id,coalesce(ul.username,'')::text,s.status,
    s.opened_at,s.closed_at,s.opening_cash,
    case when s.status='open' then private.v472_shift_expected_cash(s.id) else coalesce(s.expected_cash,private.v472_shift_expected_cash(s.id)) end,
    s.declared_cash,s.difference,s.closing_note,coalesce(s.edit_count,0),s.last_edited_at
  from public.cashier_shifts s
  left join public.user_login_names ul on ul.user_id=s.user_id
  where s.tenant_id=p_tenant_id and s.device_id=p_device_id
    and s.opened_at::date<=coalesce(p_to,current_date)
    and coalesce(s.closed_at::date,s.opened_at::date)>=coalesce(p_from,current_date-30)
  order by s.opened_at desc
  limit greatest(1,least(coalesce(p_limit,50),200));
end $$;
grant execute on function public.cashier_shift_history_v472(uuid,uuid,date,date,integer) to authenticated;

create or replace function public.cashier_shift_edits_v472(p_tenant_id uuid,p_shift_id uuid)
returns table(id uuid,changed_by uuid,changed_by_name text,changed_at timestamptz,reason text,before_state jsonb,after_state jsonb)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare v public.cashier_shifts%rowtype;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  select s.* into v from public.cashier_shifts s where s.id=p_shift_id and s.tenant_id=p_tenant_id;
  if not found then raise exception 'Shift not found';end if;
  if v.user_id<>auth.uid() and not private.erp_user_is_owner(p_tenant_id)
     and not private.erp_has_permission(p_tenant_id,'pos.shift_manage') then raise exception 'Shift edit history access denied';end if;
  return query select e.id,e.changed_by,coalesce(ul.username,'')::text,e.changed_at,e.reason,e.before_state,e.after_state
  from public.cashier_shift_edits e left join public.user_login_names ul on ul.user_id=e.changed_by
  where e.tenant_id=p_tenant_id and e.shift_id=p_shift_id order by e.changed_at desc;
end $$;
grant execute on function public.cashier_shift_edits_v472(uuid,uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Terminal Daily: pure report. It never opens/closes/edits shifts. Shift data is
-- included only as a read-only summary for that day's terminal activity.
-- -----------------------------------------------------------------------------
create or replace function public.pos_terminal_day_v472(p_tenant_id uuid,p_device_id uuid,p_day date default current_date)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v jsonb;
  v_purchase_total numeric:=0;v_purchase_count bigint:=0;v_purchase_returns numeric:=0;
  v_sales_discount numeric:=0;v_sales_tax numeric:=0;v_sales_paid numeric:=0;v_sales_outstanding numeric:=0;
  v_purchase_discount numeric:=0;v_purchase_tax numeric:=0;v_purchase_paid numeric:=0;v_purchase_outstanding numeric:=0;
  v_receipt_cash numeric:=0;v_receipt_upi numeric:=0;v_receipt_card numeric:=0;v_receipt_bank numeric:=0;v_receipt_other numeric:=0;
  v_cash_in numeric:=0;v_cash_out numeric:=0;
  v_shift_count bigint:=0;v_open_shift_count bigint:=0;v_first_start timestamptz;v_last_end timestamptz;
  v_shift_opening numeric:=0;v_shift_closing numeric:=0;v_shift_difference numeric:=0;v_shift_rows jsonb:='[]'::jsonb;
begin
  if not private.v472_terminal_day_module_enabled(p_tenant_id,p_device_id) then
    raise exception 'Terminal Daily is disabled for this POS';
  end if;
  -- Reuse mature sale/return/expense/receipt calculations, then explicitly remove
  -- the legacy single-shift object so Terminal Daily owns no shift state.
  select public.pos_terminal_day_v471(p_tenant_id,p_device_id,p_day) into v;
  v:=coalesce(v,'{}'::jsonb)-array['shift','invoices','returns','customer_receipt_rows'];

  -- Daily sales summary. Outstanding is return-aware and reflects the current
  -- balance of invoices billed on this terminal/day; no transaction rows are returned.
  select
    coalesce(sum(s.discount_total),0),
    coalesce(sum(s.tax_total),0),
    coalesce(sum(coalesce(py.paid,0)),0),
    coalesce(sum(greatest(s.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)),0)
  into v_sales_discount,v_sales_tax,v_sales_paid,v_sales_outstanding
  from public.sales s
  join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id and o.device_id=p_device_id
  left join (select sale_id,sum(amount) paid from public.sale_payments group by sale_id) py on py.sale_id=s.id
  left join (select sale_id,sum(grand_total) returned from public.sales_returns where refund_status<>'waived' group by sale_id) rt on rt.sale_id=s.id
  where s.tenant_id=p_tenant_id and s.sale_date=p_day and coalesce(s.status,'') not in('cancelled','void');

  select count(*),coalesce(sum(p.grand_total),0),coalesce(sum(p.discount_total),0),coalesce(sum(p.tax_total),0),
    coalesce(sum(coalesce(py.paid,0)),0),
    coalesce(sum(greatest(p.grand_total-coalesce(rt.returned,0)-coalesce(py.paid,0),0)),0)
  into v_purchase_count,v_purchase_total,v_purchase_discount,v_purchase_tax,v_purchase_paid,v_purchase_outstanding
  from public.purchases p
  join public.document_origins o on o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id and o.device_id=p_device_id
  left join (select purchase_id,sum(amount) paid from public.purchase_payments group by purchase_id) py on py.purchase_id=p.id
  left join (select purchase_id,sum(grand_total) returned from public.purchase_returns where credit_status<>'waived' group by purchase_id) rt on rt.purchase_id=p.id
  where p.tenant_id=p_tenant_id and p.purchase_date=p_day and coalesce(p.status,'') not in('cancelled','void');

  select
    coalesce(sum(r.amount) filter(where lower(r.payment_method)='cash'),0),
    coalesce(sum(r.amount) filter(where lower(r.payment_method)='upi'),0),
    coalesce(sum(r.amount) filter(where lower(r.payment_method)='card'),0),
    coalesce(sum(r.amount) filter(where lower(r.payment_method)='bank'),0),
    coalesce(sum(r.amount) filter(where lower(r.payment_method) not in('cash','upi','card','bank')),0)
  into v_receipt_cash,v_receipt_upi,v_receipt_card,v_receipt_bank,v_receipt_other
  from public.customer_receipts r
  where r.tenant_id=p_tenant_id and r.device_id=p_device_id and r.receipt_date=p_day;

  select
    coalesce(sum(m.amount) filter(where m.movement_type='cash_in'),0),
    abs(coalesce(sum(m.amount) filter(where m.movement_type='cash_out'),0))
  into v_cash_in,v_cash_out
  from public.cash_drawer_movements m
  join public.cashier_shifts s on s.id=m.shift_id
  where s.tenant_id=p_tenant_id and s.device_id=p_device_id and m.created_at::date=p_day;

  select count(*),count(*) filter(where s.status='open'),min(s.opened_at),max(s.closed_at),
    coalesce(sum(s.opening_cash),0),coalesce(sum(s.declared_cash) filter(where s.status<>'open'),0),
    coalesce(sum(s.difference) filter(where s.status<>'open'),0)
  into v_shift_count,v_open_shift_count,v_first_start,v_last_end,v_shift_opening,v_shift_closing,v_shift_difference
  from public.cashier_shifts s
  where s.tenant_id=p_tenant_id and s.device_id=p_device_id
    and s.opened_at::date<=p_day and coalesce(s.closed_at::date,p_day)>=p_day;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'shift_number',s.shift_number,'cashier',coalesce(ul.username,''),'status',s.status,
    'opened_at',s.opened_at,'closed_at',s.closed_at,'opening_cash',s.opening_cash,
    'closing_cash',s.declared_cash,'expected_cash',case when s.status='open' then private.v472_shift_expected_cash(s.id) else s.expected_cash end,
    'difference',s.difference
  ) order by s.opened_at),'[]'::jsonb) into v_shift_rows
  from public.cashier_shifts s left join public.user_login_names ul on ul.user_id=s.user_id
  where s.tenant_id=p_tenant_id and s.device_id=p_device_id
    and s.opened_at::date<=p_day and coalesce(s.closed_at::date,p_day)>=p_day;

  return v||jsonb_build_object(
    'sales_discount',v_sales_discount,'sales_tax',v_sales_tax,'sales_paid',v_sales_paid,
    'sales_outstanding',v_sales_outstanding,
    'net_sales',coalesce((v->>'gross_sales')::numeric,0)-coalesce((v->>'sales_returns')::numeric,0),
    'purchase_count',v_purchase_count,'purchases',v_purchase_total,
    'purchase_discount',v_purchase_discount,'purchase_tax',v_purchase_tax,'purchase_paid',v_purchase_paid,
    'purchase_outstanding',v_purchase_outstanding,
    'net_purchases',v_purchase_total-coalesce((v->>'purchase_returns')::numeric,0),
    'customer_receipts_cash',v_receipt_cash,'customer_receipts_upi',v_receipt_upi,
    'customer_receipts_card',v_receipt_card,'customer_receipts_bank',v_receipt_bank,
    'customer_receipts_other',v_receipt_other,
    'cash_in',v_cash_in,'cash_out',v_cash_out,
    'total_collected',coalesce((v->>'cash')::numeric,0)+coalesce((v->>'upi')::numeric,0)+coalesce((v->>'card')::numeric,0)+coalesce((v->>'bank')::numeric,0)+coalesce((v->>'other_payments')::numeric,0)+coalesce((v->>'customer_receipts')::numeric,0),
    'shift_summary',jsonb_build_object(
      'shift_count',v_shift_count,'open_shift_count',v_open_shift_count,
      'first_start',v_first_start,'last_end',v_last_end,
      'opening_cash',v_shift_opening,'closing_cash',v_shift_closing,'difference',v_shift_difference,
      'shifts',v_shift_rows
    )
  );
end $$;
grant execute on function public.pos_terminal_day_v472(uuid,uuid,date) to authenticated;

-- Backend release contract.
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp
as $$
  select jsonb_build_object(
    'product','THQ ERP',
    'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
    'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
    'minimum_app_version','4.7.2',
    'release','Terminal Operations Redesign'
  )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  118,'4.7.2','Terminal Operations Redesign',
  'Separates read-only Terminal Daily from editable/audited Cashier Shift; adds editable automatic shift times and amounts, shift history, and independent module behavior.'
)
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP V4.7.2 migration 118 terminal operations redesign applied' as status;
