begin;

create table public.expense_change_history_v600 (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  expense_id uuid not null
    references public.expenses(id)
    on delete cascade,
  action text not null
    check (action in ('created', 'edited')),
  reason text,
  before_data jsonb,
  after_data jsonb not null,
  changed_by uuid,
  changed_at timestamptz not null default now()
);

create index idx_expense_change_history_v600_expense
  on public.expense_change_history_v600
  (tenant_id, expense_id, changed_at desc);

alter table public.expense_change_history_v600
  enable row level security;

revoke all on table public.expense_change_history_v600
from public, anon, authenticated;

grant all on table public.expense_change_history_v600
to service_role;


create or replace function private.expense_change_history_capture_v600()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_reason text := nullif(
    current_setting('thq.expense_change_reason', true),
    ''
  );
begin
  if tg_op = 'INSERT' then

    insert into public.expense_change_history_v600(
      tenant_id,
      expense_id,
      action,
      reason,
      before_data,
      after_data,
      changed_by
    )
    values (
      new.tenant_id,
      new.id,
      'created',
      coalesce(v_reason, 'Expense created'),
      null,
      to_jsonb(new),
      coalesce(new.created_by, auth.uid())
    );

  elsif tg_op = 'UPDATE' then

    if to_jsonb(new) is distinct from to_jsonb(old) then
      insert into public.expense_change_history_v600(
        tenant_id,
        expense_id,
        action,
        reason,
        before_data,
        after_data,
        changed_by
      )
      values (
        new.tenant_id,
        new.id,
        'edited',
        v_reason,
        to_jsonb(old),
        to_jsonb(new),
        coalesce(new.updated_by, auth.uid())
      );
    end if;

  end if;

  return new;
end;
$function$;

revoke all
on function private.expense_change_history_capture_v600()
from public, anon, authenticated, service_role;


create trigger trg_expense_change_history_v600
after insert or update
on public.expenses
for each row
execute function private.expense_change_history_capture_v600();


create or replace function public.expenses_update_v600(
  p_tenant_id uuid,
  p_expense_id uuid,
  p_category_id uuid,
  p_expense_date date,
  p_payee text,
  p_description text,
  p_amount numeric,
  p_tax_amount numeric,
  p_round_off numeric,
  p_payment_method text,
  p_reference_number text,
  p_notes text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied'
      using errcode = '42501';
  end if;

  if not (
    private.erp_user_is_owner(p_tenant_id, auth.uid())
    or private.erp_has_permission(p_tenant_id, 'expenses.edit')
    or private.erp_has_permission(p_tenant_id, 'expenses.manage')
  ) then
    raise exception 'Expense edit permission required'
      using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'Edit reason is required for expense tracking';
  end if;

  perform set_config(
    'thq.expense_change_reason',
    trim(p_reason),
    true
  );

  perform public.expenses_update_v489(
    p_tenant_id,
    p_expense_id,
    p_category_id,
    p_expense_date,
    p_payee,
    p_description,
    p_amount,
    p_tax_amount,
    p_round_off,
    p_payment_method,
    p_reference_number,
    p_notes
  );
end;
$function$;

revoke all
on function public.expenses_update_v600(
  uuid,
  uuid,
  uuid,
  date,
  text,
  text,
  numeric,
  numeric,
  numeric,
  text,
  text,
  text,
  text
)
from public, anon;

grant execute
on function public.expenses_update_v600(
  uuid,
  uuid,
  uuid,
  date,
  text,
  text,
  numeric,
  numeric,
  numeric,
  text,
  text,
  text,
  text
)
to authenticated, service_role;


create or replace function public.expense_detail_v600(
  p_tenant_id uuid,
  p_expense_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_result jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied'
      using errcode = '42501';
  end if;

  if not (
    private.erp_user_is_owner(p_tenant_id, auth.uid())
    or private.erp_has_permission(p_tenant_id, 'expenses.view')
    or private.erp_has_permission(p_tenant_id, 'expenses.edit')
    or private.erp_has_permission(p_tenant_id, 'expenses.manage')
  ) then
    raise exception 'Expense view permission required'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'expense',
    jsonb_build_object(
      'id', e.id,
      'expense_number', e.expense_number,
      'expense_date', e.expense_date,
      'category_id', e.category_id,
      'category_name', c.name,
      'payee', e.payee,
      'description', e.description,
      'amount', e.amount,
      'tax_amount', e.tax_amount,
      'round_off', coalesce(e.round_off, 0),
      'total_amount', e.total_amount,
      'payment_method', e.payment_method,
      'reference_number', e.reference_number,
      'notes', e.notes,
      'status', e.status,
      'created_at', e.created_at,
      'updated_at', e.updated_at,
      'tracking_code', e.tracking_code
    ),

    'origin',
    jsonb_build_object(
      'location_id', o.location_id,
      'location_name', l.name,
      'device_id', o.device_id,
      'device_name', d.name,
      'device_code', d.device_code,
      'created_by', o.created_by,
      'created_at', o.created_at
    ),

    'journals',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', j.id,
          'entry_number', j.entry_number,
          'entry_date', j.entry_date,
          'description', j.description,
          'status', j.status,
          'source_reference', j.source_reference,
          'created_at', j.created_at,
          'posted_at', j.posted_at
        )
        order by j.created_at
      )
      from public.journal_entries j
      where j.tenant_id = e.tenant_id
        and j.source_type = 'expense'
        and j.source_id = e.id
    ), '[]'::jsonb),

    'history',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', h.id,
          'action', h.action,
          'reason', h.reason,
          'changed_by', h.changed_by,
          'changed_at', h.changed_at,
          'before', h.before_data,
          'after', h.after_data
        )
        order by h.changed_at desc
      )
      from public.expense_change_history_v600 h
      where h.tenant_id = e.tenant_id
        and h.expense_id = e.id
    ), '[]'::jsonb)
  )
  into v_result
  from public.expenses e
  join public.expense_categories c
    on c.id = e.category_id
  left join public.document_origins o
    on o.tenant_id = e.tenant_id
   and o.entity_type = 'expense'
   and o.entity_id = e.id
  left join public.business_locations l
    on l.id = o.location_id
  left join public.business_devices d
    on d.id = o.device_id
  where e.tenant_id = p_tenant_id
    and e.id = p_expense_id;

  if v_result is null then
    raise exception 'Expense not found';
  end if;

  return v_result;
end;
$function$;

revoke all
on function public.expense_detail_v600(uuid, uuid)
from public, anon;

grant execute
on function public.expense_detail_v600(uuid, uuid)
to authenticated, service_role;


create or replace function public.expense_summary_v600(
  p_tenant_id uuid,
  p_from date,
  p_to date,
  p_location_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_total numeric := 0;
  v_tax numeric := 0;
  v_count bigint := 0;
  v_categories jsonb := '[]'::jsonb;
  v_methods jsonb := '[]'::jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied'
      using errcode = '42501';
  end if;

  if p_from is null
     or p_to is null
     or p_to < p_from then
    raise exception 'Valid expense date range is required';
  end if;

  select
    count(*),
    coalesce(sum(e.total_amount), 0),
    coalesce(sum(e.tax_amount), 0)
  into
    v_count,
    v_total,
    v_tax
  from public.expenses e
  left join public.document_origins o
    on o.tenant_id = e.tenant_id
   and o.entity_type = 'expense'
   and o.entity_id = e.id
  where e.tenant_id = p_tenant_id
    and e.expense_date between p_from and p_to
    and e.status = 'posted'
    and (
      p_location_id is null
      or o.location_id = p_location_id
    );

  select coalesce(
    jsonb_agg(to_jsonb(x) order by x.total desc),
    '[]'::jsonb
  )
  into v_categories
  from (
    select
      c.id as category_id,
      c.name as category_name,
      count(*) as expense_count,
      round(sum(e.total_amount), 2) as total,
      round(sum(e.tax_amount), 2) as tax
    from public.expenses e
    join public.expense_categories c
      on c.id = e.category_id
    left join public.document_origins o
      on o.tenant_id = e.tenant_id
     and o.entity_type = 'expense'
     and o.entity_id = e.id
    where e.tenant_id = p_tenant_id
      and e.expense_date between p_from and p_to
      and e.status = 'posted'
      and (
        p_location_id is null
        or o.location_id = p_location_id
      )
    group by c.id, c.name
  ) x;

  select coalesce(
    jsonb_agg(to_jsonb(x) order by x.total desc),
    '[]'::jsonb
  )
  into v_methods
  from (
    select
      lower(coalesce(e.payment_method, 'unknown')) as payment_method,
      count(*) as expense_count,
      round(sum(e.total_amount), 2) as total
    from public.expenses e
    left join public.document_origins o
      on o.tenant_id = e.tenant_id
     and o.entity_type = 'expense'
     and o.entity_id = e.id
    where e.tenant_id = p_tenant_id
      and e.expense_date between p_from and p_to
      and e.status = 'posted'
      and (
        p_location_id is null
        or o.location_id = p_location_id
      )
    group by 1
  ) x;

  return jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'location_id', p_location_id,
    'expense_count', v_count,
    'total', round(v_total, 2),
    'tax', round(v_tax, 2),
    'net_before_tax', round(v_total - v_tax, 2),
    'categories', v_categories,
    'payment_methods', v_methods
  );
end;
$function$;

revoke all
on function public.expense_summary_v600(
  uuid,
  date,
  date,
  uuid
)
from public, anon;

grant execute
on function public.expense_summary_v600(
  uuid,
  date,
  date,
  uuid
)
to authenticated, service_role;

commit;