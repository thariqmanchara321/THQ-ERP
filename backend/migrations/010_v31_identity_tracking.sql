-- FLEXI ERP V3.1 - Identity + immutable tracking foundation
-- Safe to run after successful migrations 001-009. Idempotent.

create extension if not exists citext;
create extension if not exists pgcrypto;
create schema if not exists private;

-- Public username directory. Auth emails remain implementation details.
create table if not exists public.user_login_names (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username citext not null unique,
  auth_email text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_login_names_username_len check (char_length(username::text) >= 4),
  constraint user_login_names_username_chars check (username::text ~ '^[A-Za-z0-9._-]+$')
);

alter table public.user_login_names enable row level security;
revoke all on table public.user_login_names from anon, authenticated;

-- Existing users keep their current Auth email/password. We only assign a username alias.
do $$
declare
  r record;
  base text;
  candidate text;
  suffix integer;
begin
  for r in
    select id, email
    from auth.users
    where email is not null
    order by created_at, id
  loop
    if exists (select 1 from public.user_login_names n where n.user_id=r.id) then
      continue;
    end if;

    base := lower(regexp_replace(coalesce(split_part(r.email,'@',1),'user'), '[^a-zA-Z0-9._-]+', '_', 'g'));
    if char_length(base) < 4 then
      base := 'user_' || substr(replace(r.id::text,'-',''),1,8);
    end if;

    candidate := base;
    suffix := 1;
    while exists(select 1 from public.user_login_names where username=candidate::citext) loop
      suffix := suffix + 1;
      candidate := base || '_' || suffix::text;
    end loop;

    insert into public.user_login_names(user_id, username, auth_email)
    values(r.id, candidate, r.email)
    on conflict(user_id) do nothing;
  end loop;
end $$;

create or replace function public.current_username()
returns text
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select username::text from public.user_login_names where user_id=auth.uid()
$$;
revoke all on function public.current_username() from public;
grant execute on function public.current_username() to authenticated;

-- Every business gets an immutable readable code in addition to UUID.
alter table public.tenants add column if not exists business_code text;
update public.tenants
set business_code='BIZ-'||upper(substr(replace(id::text,'-',''),1,12))
where business_code is null or trim(business_code)='';
create unique index if not exists ux_tenants_business_code on public.tenants(business_code);

create or replace function private.assign_business_code()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if new.business_code is null or trim(new.business_code)='' then
    new.business_code := 'BIZ-'||upper(substr(replace(new.id::text,'-',''),1,12));
  end if;
  return new;
end $$;
revoke all on function private.assign_business_code() from public;
drop trigger if exists trg_tenants_business_code on public.tenants;
create trigger trg_tenants_business_code
before insert on public.tenants
for each row execute function private.assign_business_code();

create or replace function private.prevent_business_code_change()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if old.business_code is distinct from new.business_code then
    raise exception 'Business code is immutable';
  end if;
  return new;
end $$;
revoke all on function private.prevent_business_code_change() from public;
drop trigger if exists trg_tenants_business_code_immutable on public.tenants;
create trigger trg_tenants_business_code_immutable
before update of business_code on public.tenants
for each row execute function private.prevent_business_code_change();

-- Generic tenant tracking counters.
create table if not exists public.entity_tracking_counters (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  entity_key text not null,
  last_number bigint not null default 0,
  primary key(tenant_id,entity_key)
);
alter table public.entity_tracking_counters enable row level security;
revoke all on table public.entity_tracking_counters from anon, authenticated;

create or replace function private.next_tracking_code(
  p_tenant_id uuid,
  p_entity_key text,
  p_prefix text
)
returns text
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_no bigint;
begin
  insert into public.entity_tracking_counters(tenant_id,entity_key,last_number)
  values(p_tenant_id,p_entity_key,1)
  on conflict(tenant_id,entity_key)
  do update set last_number=public.entity_tracking_counters.last_number+1
  returning last_number into v_no;
  return upper(p_prefix)||'-'||lpad(v_no::text,8,'0');
end $$;
revoke all on function private.next_tracking_code(uuid,text,text) from public;

create or replace function private.assign_tracking_code()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if new.tracking_code is null or trim(new.tracking_code)='' then
    new.tracking_code := private.next_tracking_code(new.tenant_id,TG_TABLE_NAME,TG_ARGV[0]);
  end if;
  return new;
end $$;
revoke all on function private.assign_tracking_code() from public;

create or replace function private.prevent_tracking_code_change()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  if old.tracking_code is distinct from new.tracking_code then
    raise exception 'Tracking code is immutable';
  end if;
  return new;
end $$;
revoke all on function private.prevent_tracking_code_change() from public;

-- Add readable IDs to existing tenant-scoped core records without assuming every table shape.
do $$
declare
  x record;
  y record;
  trg text;
  imm text;
  v_code text;
begin
  for x in select * from (values
    ('products','PRD'),
    ('product_variants','SKU'),
    ('inventory_locations','STK'),
    ('customers','CUS'),
    ('suppliers','SUP'),
    ('purchases','PURR'),
    ('sales','SALR'),
    ('expenses','EXPR')
  ) v(table_name,prefix)
  loop
    if to_regclass('public.'||x.table_name) is null then continue; end if;
    if not exists(
      select 1 from information_schema.columns
      where table_schema='public' and table_name=x.table_name and column_name='tenant_id'
    ) then continue; end if;

    execute format('alter table public.%I add column if not exists tracking_code text',x.table_name);
    execute format(
      'create unique index if not exists %I on public.%I(tenant_id,tracking_code) where tracking_code is not null',
      'ux_'||x.table_name||'_tracking_code',x.table_name
    );

    trg := 'trg_'||x.table_name||'_tracking_code';
    execute format('drop trigger if exists %I on public.%I',trg,x.table_name);
    execute format(
      'create trigger %I before insert on public.%I for each row execute function private.assign_tracking_code(%L)',
      trg,x.table_name,x.prefix
    );

    -- IMPORTANT: keep immutability disabled while existing rows are backfilled.
    -- This also makes the migration safe to rerun after a partially failed attempt.
    imm := 'trg_'||x.table_name||'_tracking_immutable';
    execute format('drop trigger if exists %I on public.%I',imm,x.table_name);

    for y in execute format(
      'select id,tenant_id from public.%I where tracking_code is null or btrim(tracking_code)='''' order by id',
      x.table_name
    ) loop
      v_code := private.next_tracking_code(y.tenant_id,x.table_name,x.prefix);
      execute format('update public.%I set tracking_code=$1 where id=$2',x.table_name) using v_code,y.id;
    end loop;

    -- Only protect tracking codes after every existing row has been assigned one.
    execute format(
      'create trigger %I before update of tracking_code on public.%I for each row execute function private.prevent_tracking_code_change()',
      imm,x.table_name
    );
  end loop;
end $$;

select 'V3.1 identity/tracking foundation ready' as status;
