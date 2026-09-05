insert into public.modules(key,name,description,category,is_core,sort_order,is_active,is_beta,requires_configuration)
values ('audit_center','Audit Center','Risk-ranked transaction evidence, auditor review and explainability','Compliance',false,46,true,false,false)
on conflict (key) do update set
  name=excluded.name,
  description=excluded.description,
  category=excluded.category,
  sort_order=excluded.sort_order,
  is_active=true,
  is_beta=false;

insert into public.permissions(key,module_key,name,description) values
  ('audit_center.view','audit_center','View Audit Center','View risk findings and transaction evidence in Audit Center.'),
  ('audit_center.review','audit_center','Review Audit Findings','Mark findings under review and add reviewer notes.'),
  ('audit_center.resolve','audit_center','Resolve Audit Findings','Resolve, explain, dismiss or escalate audit findings.'),
  ('audit_center.export','audit_center','Export Audit Evidence','Export audit findings and evidence.'),
  ('audit_center.configure','audit_center','Configure Audit Risk Rules','Configure tenant audit risk thresholds.'),
  ('audit_history.view_sensitive','audit_center','View Sensitive Audit History','View before/after values and sensitive evidence in transaction history.'),
  ('profitability.view','reports','View Product Profitability','View product revenue, recognized COGS, profit and margin.'),
  ('explain.view','reports','Explain ERP Numbers','View deterministic metric equations and quantified drivers.')
on conflict (key) do update set
  module_key=excluded.module_key,
  name=excluded.name,
  description=excluded.description;

insert into public.roles(id,tenant_id,key,name,is_system)
select gen_random_uuid(), t.id, 'auditor', 'Auditor', true
from public.tenants t
where not exists (
  select 1 from public.roles r where r.tenant_id=t.id and r.key='auditor'
);

insert into public.role_permissions(role_id,permission_key)
select r.id,p.permission_key
from public.roles r
cross join lateral (
  values
    ('audit_center.view'::text),
    ('audit_center.review'::text),
    ('audit_center.export'::text),
    ('audit_history.view_sensitive'::text),
    ('profitability.view'::text),
    ('explain.view'::text)
) p(permission_key)
where r.key='auditor'
on conflict do nothing;

insert into public.role_permissions(role_id,permission_key)
select r.id,p.permission_key
from public.roles r
cross join lateral (
  values
    ('audit_center.view'::text),
    ('audit_center.review'::text),
    ('audit_center.resolve'::text),
    ('audit_center.export'::text),
    ('audit_center.configure'::text),
    ('audit_history.view_sensitive'::text),
    ('profitability.view'::text),
    ('explain.view'::text)
) p(permission_key)
where r.key='owner'
on conflict do nothing;

insert into public.role_permissions(role_id,permission_key)
select r.id,p.permission_key
from public.roles r
cross join lateral (
  values
    ('audit_center.view'::text),
    ('audit_center.review'::text),
    ('audit_center.resolve'::text),
    ('audit_center.export'::text),
    ('profitability.view'::text),
    ('explain.view'::text)
) p(permission_key)
where r.key in ('manager','accountant')
on conflict do nothing;

create table if not exists public.transaction_story_events_v600 (
  event_sequence bigint generated always as identity primary key,
  id uuid not null default gen_random_uuid() unique,
  tenant_id uuid not null,
  correlation_id uuid not null,
  root_entity_type text not null,
  root_entity_id uuid not null,
  entity_type text not null,
  entity_id uuid not null,
  entity_reference text,
  action text not null,
  event_time timestamptz not null default now(),
  actor_user_id uuid,
  actor_name text,
  actor_role_keys text[] not null default '{}'::text[],
  location_id uuid,
  device_id uuid,
  device_name text,
  device_code text,
  source_app text,
  request_id text,
  before_data jsonb,
  after_data jsonb,
  changed_fields text[] not null default '{}'::text[],
  reason text,
  approval_request_id uuid,
  approved_by uuid,
  approved_at timestamptz,
  approval_note text,
  source_module text,
  source_function text,
  related_entities jsonb not null default '[]'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  previous_event_hash text,
  event_hash text not null,
  recorded_at timestamptz not null default now(),
  constraint transaction_story_events_v600_action_chk check (length(trim(action)) > 0),
  constraint transaction_story_events_v600_entity_chk check (length(trim(entity_type)) > 0),
  constraint transaction_story_events_v600_related_chk check (jsonb_typeof(related_entities)='array')
);

create index if not exists transaction_story_v600_tenant_time_idx
  on public.transaction_story_events_v600(tenant_id,event_time desc,event_sequence desc);
create index if not exists transaction_story_v600_entity_idx
  on public.transaction_story_events_v600(tenant_id,entity_type,entity_id,event_sequence);
create index if not exists transaction_story_v600_root_idx
  on public.transaction_story_events_v600(tenant_id,root_entity_type,root_entity_id,event_sequence);
create index if not exists transaction_story_v600_corr_idx
  on public.transaction_story_events_v600(tenant_id,correlation_id,event_sequence);
create index if not exists transaction_story_v600_device_idx
  on public.transaction_story_events_v600(tenant_id,device_id,event_time desc) where device_id is not null;
create index if not exists transaction_story_v600_actor_idx
  on public.transaction_story_events_v600(tenant_id,actor_user_id,event_time desc) where actor_user_id is not null;

alter table public.transaction_story_events_v600 enable row level security;
revoke all on public.transaction_story_events_v600 from anon, authenticated;

create or replace function private.v600_changed_fields(p_before jsonb,p_after jsonb)
returns text[]
language sql
immutable
security invoker
set search_path=''
as $$
  select coalesce(array_agg(k order by k),'{}'::text[])
  from (
    select key as k
    from jsonb_object_keys(coalesce(p_before,'{}'::jsonb)) key
    union
    select key as k
    from jsonb_object_keys(coalesce(p_after,'{}'::jsonb)) key
  ) s
  where coalesce(p_before,'{}'::jsonb)->k is distinct from coalesce(p_after,'{}'::jsonb)->k;
$$;

create or replace function private.v600_block_story_mutation()
returns trigger
language plpgsql
security invoker
set search_path=''
as $$
begin
  raise exception 'THQ v6.0 transaction story is append-only; % is not permitted', tg_op
    using errcode='55000';
end;
$$;

revoke all on function private.v600_changed_fields(jsonb,jsonb) from public,anon,authenticated;
revoke all on function private.v600_block_story_mutation() from public,anon,authenticated;

drop trigger if exists trg_v600_story_immutable on public.transaction_story_events_v600;
create trigger trg_v600_story_immutable
before update or delete on public.transaction_story_events_v600
for each row execute function private.v600_block_story_mutation();

create or replace function private.v600_story_write(
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_entity_reference text,
  p_action text,
  p_event_time timestamptz default null,
  p_actor_user_id uuid default null,
  p_location_id uuid default null,
  p_device_id uuid default null,
  p_before jsonb default null,
  p_after jsonb default null,
  p_reason text default null,
  p_approval_request_id uuid default null,
  p_source_module text default null,
  p_source_function text default null,
  p_source_app text default null,
  p_root_entity_type text default null,
  p_root_entity_id uuid default null,
  p_request_id text default null,
  p_related_entities jsonb default '[]'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_id uuid := gen_random_uuid();
  v_actor uuid := coalesce(p_actor_user_id,auth.uid());
  v_actor_name text;
  v_roles text[] := '{}'::text[];
  v_device_name text;
  v_device_code text;
  v_source_app text := p_source_app;
  v_location uuid := p_location_id;
  v_device uuid := p_device_id;
  v_root_type text := coalesce(nullif(trim(p_root_entity_type),''),p_entity_type);
  v_root_id uuid := coalesce(p_root_entity_id,p_entity_id);
  v_corr uuid;
  v_prev_hash text;
  v_hash text;
  v_changed text[];
  v_approved_by uuid;
  v_approved_at timestamptz;
  v_approval_note text;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
  v_event_time timestamptz := coalesce(p_event_time,now());
  v_payload jsonb;
begin
  if p_tenant_id is null or p_entity_id is null or nullif(trim(p_entity_type),'') is null or nullif(trim(p_action),'') is null then
    raise exception 'tenant, entity type, entity id and action are required for THQ transaction story';
  end if;

  if not exists (select 1 from public.tenants t where t.id=p_tenant_id) then
    raise exception 'Unknown tenant for THQ transaction story';
  end if;

  if v_actor is not null then
    select u.username::text into v_actor_name
    from public.user_login_names u
    where u.user_id=v_actor;

    select coalesce(array_agg(distinct r.key order by r.key),'{}'::text[])
      into v_roles
    from public.tenant_memberships m
    join public.user_roles ur on ur.membership_id=m.id and ur.tenant_id=m.tenant_id
    join public.roles r on r.id=ur.role_id and r.tenant_id=m.tenant_id
    where m.tenant_id=p_tenant_id and m.user_id=v_actor and m.status='active';
  end if;

  if v_device is not null then
    select d.name,d.device_code,coalesce(v_source_app,d.app_type),coalesce(v_location,d.location_id)
      into v_device_name,v_device_code,v_source_app,v_location
    from public.business_devices d
    where d.tenant_id=p_tenant_id and d.id=v_device;
  end if;

  if p_approval_request_id is not null then
    select a.decided_by,a.decided_at,a.decision_note,coalesce(v_reason,a.reason)
      into v_approved_by,v_approved_at,v_approval_note,v_reason
    from public.approval_requests a
    where a.tenant_id=p_tenant_id and a.id=p_approval_request_id;
  end if;

  v_corr := extensions.uuid_generate_v5(
    extensions.uuid_ns_url(),
    'thq:v600:'||p_tenant_id::text||':'||lower(v_root_type)||':'||v_root_id::text
  );

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_corr::text,0));

  select e.event_hash into v_prev_hash
  from public.transaction_story_events_v600 e
  where e.tenant_id=p_tenant_id and e.correlation_id=v_corr
  order by e.event_sequence desc
  limit 1;

  v_changed := private.v600_changed_fields(p_before,p_after);

  v_payload := jsonb_build_object(
    'id',v_id,'tenant_id',p_tenant_id,'correlation_id',v_corr,
    'root_entity_type',v_root_type,'root_entity_id',v_root_id,
    'entity_type',p_entity_type,'entity_id',p_entity_id,'entity_reference',p_entity_reference,
    'action',p_action,'event_time',v_event_time,'actor_user_id',v_actor,'actor_name',v_actor_name,
    'actor_role_keys',v_roles,'location_id',v_location,'device_id',v_device,
    'device_name',v_device_name,'device_code',v_device_code,'source_app',v_source_app,
    'request_id',p_request_id,'before_data',p_before,'after_data',p_after,'changed_fields',v_changed,
    'reason',v_reason,'approval_request_id',p_approval_request_id,'approved_by',v_approved_by,
    'approved_at',v_approved_at,'approval_note',v_approval_note,'source_module',p_source_module,
    'source_function',p_source_function,'related_entities',coalesce(p_related_entities,'[]'::jsonb),
    'metadata',coalesce(p_metadata,'{}'::jsonb),'previous_event_hash',v_prev_hash
  );

  v_hash := encode(extensions.digest(coalesce(v_prev_hash,'')||v_payload::text,'sha256'),'hex');

  insert into public.transaction_story_events_v600(
    id,tenant_id,correlation_id,root_entity_type,root_entity_id,
    entity_type,entity_id,entity_reference,action,event_time,
    actor_user_id,actor_name,actor_role_keys,location_id,device_id,device_name,device_code,source_app,
    request_id,before_data,after_data,changed_fields,reason,approval_request_id,approved_by,approved_at,approval_note,
    source_module,source_function,related_entities,metadata,previous_event_hash,event_hash
  ) values (
    v_id,p_tenant_id,v_corr,v_root_type,v_root_id,
    p_entity_type,p_entity_id,p_entity_reference,p_action,v_event_time,
    v_actor,v_actor_name,v_roles,v_location,v_device,v_device_name,v_device_code,v_source_app,
    p_request_id,p_before,p_after,v_changed,v_reason,p_approval_request_id,v_approved_by,v_approved_at,v_approval_note,
    p_source_module,p_source_function,coalesce(p_related_entities,'[]'::jsonb),coalesce(p_metadata,'{}'::jsonb),v_prev_hash,v_hash
  );

  return v_id;
end;
$$;

revoke all on function private.v600_story_write(uuid,text,uuid,text,text,timestamptz,uuid,uuid,uuid,jsonb,jsonb,text,uuid,text,text,text,text,uuid,text,jsonb,jsonb) from public,anon,authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values (
  255,
  '6.0.0-build1',
  'THQ Transaction Story Foundation',
  'v6.0 Build 1 foundation: Audit Center module and permissions, dedicated auditor role, append-only tamper-evident transaction story, correlation IDs, actor/device/approval snapshots and change-field evidence. Does not alter v5.2 GST/accounting calculation or posting rules.'
)
on conflict (migration_no) do update set
  schema_version=excluded.schema_version,
  release_name=excluded.release_name,
  notes=excluded.notes;