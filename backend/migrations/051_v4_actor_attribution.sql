-- FLEXI ERP V4 direct actor attribution on core transaction headers.
begin;
alter table public.sales add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table public.sales add column if not exists updated_by uuid references auth.users(id) on delete set null;
alter table public.purchases add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table public.purchases add column if not exists updated_by uuid references auth.users(id) on delete set null;
alter table public.expenses add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table public.expenses add column if not exists updated_by uuid references auth.users(id) on delete set null;

-- Backfill known creator from immutable origin/audit context when available.
update public.sales s set created_by=o.created_by
from public.document_origins o
where o.tenant_id=s.tenant_id and o.entity_type='sale' and o.entity_id=s.id and s.created_by is null;
update public.purchases p set created_by=o.created_by
from public.document_origins o
where o.tenant_id=p.tenant_id and o.entity_type='purchase' and o.entity_id=p.id and p.created_by is null;
update public.expenses e set created_by=o.created_by
from public.document_origins o
where o.tenant_id=e.tenant_id and o.entity_type='expense' and o.entity_id=e.id and e.created_by is null;

create or replace function private.v4_sync_document_actor()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp
as $$ begin
  if new.entity_type='sale' then
    update public.sales set created_by=coalesce(created_by,new.created_by) where id=new.entity_id and tenant_id=new.tenant_id;
  elsif new.entity_type='purchase' then
    update public.purchases set created_by=coalesce(created_by,new.created_by) where id=new.entity_id and tenant_id=new.tenant_id;
  elsif new.entity_type='expense' then
    update public.expenses set created_by=coalesce(created_by,new.created_by) where id=new.entity_id and tenant_id=new.tenant_id;
  end if;
  return new;
end $$;
drop trigger if exists trg_v4_sync_document_actor on public.document_origins;
create trigger trg_v4_sync_document_actor after insert on public.document_origins for each row execute function private.v4_sync_document_actor();

commit;
select 'Flexi ERP V4 transaction actor attribution ready' as status;
