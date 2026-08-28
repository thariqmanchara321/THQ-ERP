-- FLEXI ERP V4 richer runtime identity + unified global search.
begin;

create or replace function public.client_runtime_context_v4(p_tenant_id uuid,p_device_id uuid,p_app_key text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare v jsonb;v_all boolean;v_username text;v_roles jsonb;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_app_allowed(p_tenant_id,p_app_key) then raise exception 'This user is not enabled for this application';end if;
  if not exists(select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.app_type=p_app_key and d.status='active') then raise exception 'Device is not active';end if;
  v_all:=private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all');
  select username into v_username from public.user_login_names where user_id=auth.uid();
  select coalesce(jsonb_agg(r.key order by r.key),'[]'::jsonb) into v_roles from public.tenant_memberships tm join public.user_roles ur on ur.membership_id=tm.id and ur.tenant_id=tm.tenant_id join public.roles r on r.id=ur.role_id where tm.tenant_id=p_tenant_id and tm.user_id=auth.uid() and tm.status='active';
  select jsonb_build_object(
    'username',coalesce(v_username,''),'roles',coalesce(v_roles,'[]'::jsonb),'user_id',auth.uid(),
    'device_id',d.id,'device_code',d.device_code,'device_name',d.name,'device_modules',coalesce(to_jsonb(d.allowed_modules),'[]'::jsonb),
    'location_id',d.location_id,'location_code',l.location_code,'location_name',l.name,'device_invoice_prefix',d.invoice_prefix,
    'can_view_all_locations',v_all,
    'locations',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'code',x.location_code,'name',x.name,'type',x.location_type,'tracking_code',x.tracking_code,'access_level',case when v_all then 'manage' else a.access_level end) order by x.name)
      from public.business_locations x left join public.business_user_location_access a on a.tenant_id=p_tenant_id and a.user_id=auth.uid() and a.location_id=x.id
      where x.tenant_id=p_tenant_id and x.active and (v_all or a.user_id is not null)),'[]'::jsonb),
    'open_shift',case when p_app_key='pos' then coalesce((select jsonb_build_object('id',s.id,'shift_number',s.shift_number,'opened_at',s.opened_at,'opening_cash',s.opening_cash) from public.cashier_shifts s where s.tenant_id=p_tenant_id and s.device_id=d.id and s.status='open' order by s.opened_at desc limit 1),'{}'::jsonb) else '{}'::jsonb end
  ) into v from public.business_devices d join public.business_locations l on l.id=d.location_id where d.id=p_device_id and d.tenant_id=p_tenant_id;
  return coalesce(v,'{}'::jsonb);
end $$;
grant execute on function public.client_runtime_context_v4(uuid,uuid,text) to authenticated;

create or replace function public.global_search_v4(p_tenant_id uuid,p_query text,p_limit integer default 60)
returns table(entity_type text,entity_id uuid,public_id text,title text,subtitle text,module_key text,location_id uuid)
language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';lim integer:=greatest(5,least(coalesce(p_limit,60),150));begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;if trim(coalesce(p_query,''))='' then return;end if;
  return query select * from (
    select 'product'::text,pv.id,coalesce(p.tracking_code,pv.sku),p.name,concat_ws(' • ','SKU '||pv.sku,nullif(pv.part_number,''),nullif(pv.barcode,'')),'inventory'::text,null::uuid from public.products p join public.product_variants pv on pv.product_id=p.id and pv.tenant_id=p.tenant_id where p.tenant_id=p_tenant_id and (lower(p.name) like q or lower(pv.sku) like q or lower(coalesce(pv.barcode,'')) like q or lower(coalesce(pv.part_number,'')) like q or lower(coalesce(p.tracking_code,'')) like q)
    union all select 'customer',c.id,c.tracking_code,c.name,concat_ws(' • ',c.phone,c.email,c.tax_number),'customers',null::uuid from public.customers c where c.tenant_id=p_tenant_id and (lower(c.name) like q or lower(coalesce(c.phone,'')) like q or lower(coalesce(c.email,'')) like q or lower(coalesce(c.tracking_code,'')) like q)
    union all select 'supplier',s.id,s.tracking_code,s.name,concat_ws(' • ',s.phone,s.email,s.tax_number),'suppliers',null::uuid from public.suppliers s where s.tenant_id=p_tenant_id and (lower(s.name) like q or lower(coalesce(s.phone,'')) like q or lower(coalesce(s.email,'')) like q or lower(coalesce(s.tracking_code,'')) like q)
    union all select 'sale',s.id,s.tracking_code,coalesce(dn.terminal_number,ln.local_number,s.sale_number),c.name||' • '||s.grand_total::text,'sales',o.location_id from public.sales s join public.customers c on c.id=s.customer_id left join public.document_origins o on o.entity_type='sale' and o.entity_id=s.id left join public.location_document_numbers ln on ln.entity_type='sale' and ln.entity_id=s.id left join public.device_document_numbers dn on dn.entity_type='sale' and dn.entity_id=s.id where s.tenant_id=p_tenant_id and private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view') and (lower(s.sale_number) like q or lower(coalesce(dn.terminal_number,'')) like q or lower(c.name) like q or lower(coalesce(s.tracking_code,'')) like q)
    union all select 'purchase',p.id,p.tracking_code,coalesce(dn.terminal_number,ln.local_number,p.purchase_number),s.name||' • '||p.grand_total::text,'purchases',o.location_id from public.purchases p join public.suppliers s on s.id=p.supplier_id left join public.document_origins o on o.entity_type='purchase' and o.entity_id=p.id left join public.location_document_numbers ln on ln.entity_type='purchase' and ln.entity_id=p.id left join public.device_document_numbers dn on dn.entity_type='purchase' and dn.entity_id=p.id where p.tenant_id=p_tenant_id and private.erp_document_scope_allowed(p_tenant_id,o.location_id,null,'view') and (lower(p.purchase_number) like q or lower(coalesce(dn.terminal_number,'')) like q or lower(s.name) like q or lower(coalesce(p.tracking_code,'')) like q)
    union all select 'account',a.id,a.code,a.name,a.account_type,'accounting',null::uuid from public.accounting_accounts a where a.tenant_id=p_tenant_id and active and (lower(a.code) like q or lower(a.name) like q)
    union all select 'stock_transfer',t.id,t.transfer_number,t.transfer_number,fl.location_code||' → '||tl.location_code||' • '||t.status,'stock_transfers',t.from_location_id from public.stock_transfers t join public.business_locations fl on fl.id=t.from_location_id join public.business_locations tl on tl.id=t.to_location_id where t.tenant_id=p_tenant_id and lower(t.transfer_number) like q
    union all select 'task',t.id,null,t.title,coalesce(t.status,'')||' • '||coalesce(t.description,''),'tasks',t.location_id from public.business_tasks t where t.tenant_id=p_tenant_id and (lower(t.title) like q or lower(coalesce(t.description,'')) like q)
    union all select 'workshop_job',j.id,j.job_number,j.job_number,coalesce(v.vehicle_number,'')||' • '||j.status,'workshop',j.location_id from public.workshop_job_cards j join public.workshop_vehicles v on v.id=j.vehicle_id where j.tenant_id=p_tenant_id and (lower(j.job_number) like q or lower(v.vehicle_number) like q)
  )z limit lim;
end $$;
grant execute on function public.global_search_v4(uuid,text,integer) to authenticated;

-- Product IDs and SKU aliases stay simple and searchable.
create or replace function public.inventory_next_sku_v4(p_tenant_id uuid,p_prefix text default 'SKU') returns text language plpgsql security definer set search_path=public,private,pg_temp
as $$ declare n integer:=1;candidate text;begin if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;loop candidate:=upper(coalesce(nullif(trim(p_prefix),''),'SKU'))||'-'||lpad(n::text,6,'0');exit when not exists(select 1 from public.product_variants where tenant_id=p_tenant_id and lower(sku)=lower(candidate));n:=n+1;if n>9999999 then raise exception 'SKU sequence exhausted';end if;end loop;return candidate;end $$;
grant execute on function public.inventory_next_sku_v4(uuid,text) to authenticated;

commit;
select 'Flexi ERP V4 runtime/search ready' as status;
