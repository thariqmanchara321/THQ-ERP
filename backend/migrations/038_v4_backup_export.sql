-- FLEXI ERP V4 business backup/export manifests. The RPC returns JSON for portable tenant backups.
begin;
create table if not exists public.business_export_runs(
  id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,export_type text not null default 'full',status text not null default 'completed',requested_by uuid references auth.users(id),requested_at timestamptz not null default now(),completed_at timestamptz,record_counts jsonb not null default '{}'::jsonb,notes text
);
alter table public.business_export_runs enable row level security;revoke all on public.business_export_runs from anon,authenticated;

create or replace function public.business_backup_export_v4(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v_run uuid:=gen_random_uuid();v jsonb;begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'backup.export') then raise exception 'Backup/export permission required';end if;
  insert into public.business_export_runs(id,tenant_id,requested_by,status) values(v_run,p_tenant_id,auth.uid(),'running');
  v:=jsonb_build_object(
    'format','flexi-erp-v4','exported_at',now(),'tenant',(select to_jsonb(t) from public.tenants t where t.id=p_tenant_id),
    'locations',coalesce((select jsonb_agg(to_jsonb(x)) from public.business_locations x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'devices',coalesce((select jsonb_agg(to_jsonb(x)-'activation_hash'-'device_secret_hash') from public.business_devices x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'products',coalesce((select jsonb_agg(to_jsonb(x)) from public.products x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'variants',coalesce((select jsonb_agg(to_jsonb(x)) from public.product_variants x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'location_products',coalesce((select jsonb_agg(to_jsonb(x)) from public.location_product_settings x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'location_stock',coalesce((select jsonb_agg(to_jsonb(x)) from public.location_stock_balances x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'customers',coalesce((select jsonb_agg(to_jsonb(x)) from public.customers x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'suppliers',coalesce((select jsonb_agg(to_jsonb(x)) from public.suppliers x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'sales',coalesce((select jsonb_agg(to_jsonb(x)) from public.sales x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'sale_items',coalesce((select jsonb_agg(to_jsonb(i)) from public.sale_items i join public.sales s on s.id=i.sale_id where s.tenant_id=p_tenant_id),'[]'::jsonb),
    'sale_payments',coalesce((select jsonb_agg(to_jsonb(i)) from public.sale_payments i join public.sales s on s.id=i.sale_id where s.tenant_id=p_tenant_id),'[]'::jsonb),
    'purchases',coalesce((select jsonb_agg(to_jsonb(x)) from public.purchases x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'purchase_items',coalesce((select jsonb_agg(to_jsonb(i)) from public.purchase_items i join public.purchases p on p.id=i.purchase_id where p.tenant_id=p_tenant_id),'[]'::jsonb),
    'purchase_payments',coalesce((select jsonb_agg(to_jsonb(i)) from public.purchase_payments i join public.purchases p on p.id=i.purchase_id where p.tenant_id=p_tenant_id),'[]'::jsonb),
    'expenses',coalesce((select jsonb_agg(to_jsonb(x)) from public.expenses x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'accounts',coalesce((select jsonb_agg(to_jsonb(x)) from public.accounting_accounts x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'journals',coalesce((select jsonb_agg(to_jsonb(x)) from public.journal_entries x where x.tenant_id=p_tenant_id),'[]'::jsonb),
    'journal_lines',coalesce((select jsonb_agg(to_jsonb(l)) from public.journal_lines l join public.journal_entries j on j.id=l.journal_entry_id where j.tenant_id=p_tenant_id),'[]'::jsonb),
    'settings',coalesce((select to_jsonb(x) from public.tenant_settings x where x.tenant_id=p_tenant_id),'{}'::jsonb),
    'audit',coalesce((select jsonb_agg(to_jsonb(x)) from public.business_audit_log x where x.tenant_id=p_tenant_id),'[]'::jsonb)
  );
  update public.business_export_runs set status='completed',completed_at=now(),record_counts=jsonb_build_object('products',jsonb_array_length(v->'products'),'customers',jsonb_array_length(v->'customers'),'suppliers',jsonb_array_length(v->'suppliers'),'sales',jsonb_array_length(v->'sales'),'purchases',jsonb_array_length(v->'purchases'),'expenses',jsonb_array_length(v->'expenses')) where id=v_run;
  return jsonb_build_object('run_id',v_run,'backup',v);
exception when others then update public.business_export_runs set status='failed',notes=sqlerrm where id=v_run;raise;end $$;
grant execute on function public.business_backup_export_v4(uuid) to authenticated;

commit;
select 'Flexi ERP V4 backup/export RPC ready' as status;
