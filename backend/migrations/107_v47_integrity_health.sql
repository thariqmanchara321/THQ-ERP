-- THQ ERP V4.7 — integrity scanner used for release/support health checks.
begin;

create or replace function public.system_integrity_scan_v47(p_tenant_id uuid)
returns table(severity text,code text,issue_count bigint,description text)
language plpgsql security definer set search_path=public,private,pg_temp
as $$begin
  if not private.platform_v2_is_admin() and not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;

  return query
  select 'critical'::text,'UNBALANCED_POSTED_JOURNAL'::text,count(*)::bigint,'Posted journal debit and credit totals do not match.'::text
  from (
    select j.id from public.journal_entries j join public.journal_lines l on l.journal_entry_id=j.id
    where j.tenant_id=p_tenant_id and j.status='posted' group by j.id having abs(sum(l.debit)-sum(l.credit))>0.01
  ) q;

  return query
  select 'critical','NEGATIVE_AVAILABLE_STOCK',count(*)::bigint,'Location available stock is below zero.'
  from public.location_stock_balances b where b.tenant_id=p_tenant_id and (coalesce(b.quantity,0)-coalesce(b.reserved_quantity,0)-coalesce(b.damaged_quantity,0)-coalesce(b.quarantine_quantity,0)) < -0.000001;

  return query
  select 'critical','SALE_WITHOUT_JOURNAL',count(*)::bigint,'Non-void sale has no posted sale journal.'
  from public.sales s where s.tenant_id=p_tenant_id and coalesce(s.status,'') not in('void','cancelled')
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='sale' and j.source_id=s.id and j.status='posted');

  return query
  select 'critical','PURCHASE_WITHOUT_JOURNAL',count(*)::bigint,'Non-void purchase has no posted purchase journal.'
  from public.purchases p where p.tenant_id=p_tenant_id and coalesce(p.status,'') not in('void','cancelled')
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='purchase' and j.source_id=p.id and j.status='posted');

  return query
  select 'critical','EXPENSE_WITHOUT_JOURNAL',count(*)::bigint,'Posted expense has no posted expense journal.'
  from public.expenses e where e.tenant_id=p_tenant_id and e.status='posted'
    and not exists(select 1 from public.journal_entries j where j.tenant_id=p_tenant_id and j.source_type='expense' and j.source_id=e.id and j.status='posted');

  return query
  select 'warning','SALE_WITHOUT_ORIGIN',count(*)::bigint,'Sale has no store/system origin record.'
  from public.sales s where s.tenant_id=p_tenant_id and not exists(select 1 from public.document_origins o where o.tenant_id=p_tenant_id and o.entity_type='sale' and o.entity_id=s.id);

  return query
  select 'warning','PURCHASE_WITHOUT_ORIGIN',count(*)::bigint,'Purchase has no store/system origin record.'
  from public.purchases p where p.tenant_id=p_tenant_id and not exists(select 1 from public.document_origins o where o.tenant_id=p_tenant_id and o.entity_type='purchase' and o.entity_id=p.id);

  return query
  select 'critical','ACTIVE_SYSTEM_WITHOUT_INSTALLATION',count(*)::bigint,'Active logical system does not have an active physical installation binding.'
  from public.business_devices d where d.tenant_id=p_tenant_id and d.status='active'
    and not exists(select 1 from public.system_installations si where si.system_id=d.id and si.status='active');

  return query
  select 'critical','INSTALLATION_BINDING_MISMATCH',count(*)::bigint,'Compatibility system binding and active installation history disagree.'
  from public.business_devices d join public.system_installations si on si.system_id=d.id and si.status='active'
  where d.tenant_id=p_tenant_id and (d.status<>'active' or coalesce(d.installation_id,'')<>coalesce(si.installation_id,''));

  return query
  select 'critical','SALE_OVERPAYMENT',count(*)::bigint,'Sale payments exceed the sale grand total.'
  from public.sales s where s.tenant_id=p_tenant_id and coalesce((select sum(sp.amount) from public.sale_payments sp where sp.sale_id=s.id),0) > s.grand_total+0.01;

  return query
  select 'critical','PURCHASE_OVERPAYMENT',count(*)::bigint,'Purchase payments exceed the purchase grand total.'
  from public.purchases p where p.tenant_id=p_tenant_id and coalesce((select sum(pp.amount) from public.purchase_payments pp where pp.purchase_id=p.id),0) > p.grand_total+0.01;
end $$;
grant execute on function public.system_integrity_scan_v47(uuid) to authenticated;

create or replace function public.system_health_summary_v47(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v_critical bigint;v_warning bigint;begin
  select coalesce(sum(issue_count) filter(where severity='critical'),0),coalesce(sum(issue_count) filter(where severity='warning'),0)
  into v_critical,v_warning from public.system_integrity_scan_v47(p_tenant_id);
  return jsonb_build_object('tenant_id',p_tenant_id,'schema',public.thq_backend_contract_v47(),'critical',v_critical,'warning',v_warning,'release_ready',v_critical=0,'checked_at',now());
end$$;
grant execute on function public.system_health_summary_v47(uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(107,'4.7.0','Foundation Lock & Production Stabilization','System integrity scanner for journals, stock, origins, activation bindings and overpayments.')
on conflict(migration_no) do update set notes=excluded.notes;
commit;
select 'THQ ERP V4.7 migration 107 integrity health ready' as status;
