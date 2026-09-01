-- THQ ERP v4.9.0 Build 20 incremental database upgrade: migration 186 -> 190
-- Apply to a database whose latest completed migration is 186.
-- Generated from authoritative backend/migrations files.


-- ============================================================================
-- MIGRATION 187: 187_v490_purchase_loan_completion.sql
-- ============================================================================

-- THQ ERP v4.9.0 Build 20 — Purchasing/Loan completion and runtime fixes.
begin;

-- Fix loan warning CTE column names. The original UNION CTE inherited unnamed
-- literal columns, so ORDER BY w.severity failed with 42703 on PostgreSQL.
create or replace function public.loan_warnings_v490(
  p_tenant_id uuid,p_location_id uuid default null,p_limit integer default 250
) returns table(
  warning_type text,severity text,loan_id uuid,loan_number text,client_id uuid,client_name text,location_id uuid,
  event_date date,amount numeric,days_until integer,message text
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin
  perform private.loan_v490_access(p_tenant_id,p_location_id,'loans.view','view');
  return query
  with scoped as(
    select l.*,c.name client_name
    from public.loan_accounts_v490 l join public.customers c on c.id=l.client_id
    where l.tenant_id=p_tenant_id and l.status in('approved','active','defaulted')
      and (p_location_id is null or l.location_id=p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view')
  ), warnings(warning_type,severity,loan_id,loan_number,client_id,client_name,location_id,event_date,amount,days_until,message) as(
    select 'overdue_payment'::text,'danger'::text,l.id,l.loan_number,l.client_id,l.client_name,l.location_id,s.due_date,
      round(greatest(s.principal_due-s.principal_paid,0)+greatest(s.interest_due-s.interest_paid,0)+greatest(s.penalty_due-s.penalty_paid,0),2),
      (s.due_date-current_date)::integer,
      ('Installment #'||s.installment_no::text||' overdue by '||(current_date-s.due_date)::text||' day(s)')::text
    from scoped l join public.loan_schedule_v490 s on s.loan_id=l.id and s.tenant_id=l.tenant_id
    where l.status in('active','defaulted') and s.status<>'waived' and current_date>s.due_date+l.grace_days
      and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005
    union all
    select 'payment_due'::text,'warning'::text,l.id,l.loan_number,l.client_id,l.client_name,l.location_id,s.due_date,
      round(greatest(s.principal_due-s.principal_paid,0)+greatest(s.interest_due-s.interest_paid,0)+greatest(s.penalty_due-s.penalty_paid,0),2),
      (s.due_date-current_date)::integer,
      ('Installment #'||s.installment_no::text||' due in '||greatest(s.due_date-current_date,0)::text||' day(s)')::text
    from scoped l join public.loan_schedule_v490 s on s.loan_id=l.id and s.tenant_id=l.tenant_id
    where l.status in('active','defaulted') and s.status<>'waived'
      and s.due_date between current_date and current_date+l.payment_warning_days
      and (s.principal_due+s.interest_due+s.penalty_due)-(s.principal_paid+s.interest_paid+s.penalty_paid)>0.005
    union all
    select 'maturity'::text,'warning'::text,l.id,l.loan_number,l.client_id,l.client_name,l.location_id,l.maturity_date,
      round(l.principal_outstanding+l.interest_outstanding+l.penalty_outstanding,2),(l.maturity_date-current_date)::integer,
      ('Loan matures in '||greatest(l.maturity_date-current_date,0)::text||' day(s)')::text
    from scoped l where l.status in('active','defaulted') and l.maturity_date between current_date and current_date+l.maturity_warning_days
    union all
    select 'rate_review'::text,'info'::text,l.id,l.loan_number,l.client_id,l.client_name,l.location_id,l.next_rate_review_date,
      null::numeric,(l.next_rate_review_date-current_date)::integer,
      ('Variable interest rate review due in '||greatest(l.next_rate_review_date-current_date,0)::text||' day(s)')::text
    from scoped l where l.rate_type='variable' and l.next_rate_review_date is not null
      and l.next_rate_review_date between current_date and current_date+greatest(l.payment_warning_days,7)
  )
  select w.warning_type,w.severity,w.loan_id,w.loan_number,w.client_id,w.client_name,w.location_id,
         w.event_date,w.amount,w.days_until,w.message
  from warnings w
  order by case w.severity when 'danger' then 0 when 'warning' then 1 else 2 end,w.event_date,w.loan_number
  limit least(greatest(coalesce(p_limit,250),1),2000);
end $$;
grant execute on function public.loan_warnings_v490(uuid,uuid,integer) to authenticated;

-- Fix Purchase Price History. The original anonymous UNION subquery did not
-- expose document_number/purchase_date/supplier_name/product_name aliases.
create or replace function public.purchase_price_history_v484(
 p_tenant_id uuid,p_variant_id uuid default null,p_supplier_id uuid default null,p_location_id uuid default null,p_query text default '',p_limit integer default 1000
) returns table(
 source_type text,document_id uuid,document_number text,purchase_date date,location_id uuid,location_name text,supplier_id uuid,supplier_name text,
 variant_id uuid,product_name text,sku text,quantity numeric,unit_cost numeric,tax_rate numeric,line_total numeric
) language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare q text:='%'||lower(trim(coalesce(p_query,'')))||'%';begin
 perform private.purchasing_v484_permission(p_tenant_id,false);
 return query
 with history(source_type,document_id,document_number,purchase_date,location_id,location_name,supplier_id,supplier_name,variant_id,product_name,sku,quantity,unit_cost,tax_rate,line_total) as (
   select 'purchase_invoice_v484'::text, ih.id,ih.invoice_number::text,ih.invoice_date,ih.location_id,l.name::text,ih.supplier_id,s.name::text,ii.variant_id,p.name::text,pv.sku::text,ii.quantity::numeric,ii.unit_cost::numeric,ii.tax_rate::numeric,ii.line_total::numeric
   from public.purchase_invoices_v484 ih
   join public.purchase_invoice_items_v484 ii on ii.purchase_invoice_id=ih.id
   join public.product_variants pv on pv.id=ii.variant_id
   join public.products p on p.id=pv.product_id
   join public.suppliers s on s.id=ih.supplier_id
   join public.business_locations l on l.id=ih.location_id
   where ih.tenant_id=p_tenant_id and ih.status in('posted','part_paid','paid')
   union all
   select 'direct_purchase'::text,ph.id,ph.purchase_number::text,ph.purchase_date,o.location_id,l.name::text,ph.supplier_id,s.name::text,pi.variant_id,p.name::text,pv.sku::text,
          coalesce(pi.entered_quantity,pi.quantity)::numeric,coalesce(pi.entered_unit_cost,pi.unit_cost)::numeric,pi.tax_rate::numeric,pi.line_total::numeric
   from public.purchases ph
   join public.purchase_items pi on pi.purchase_id=ph.id
   join public.product_variants pv on pv.id=pi.variant_id
   join public.products p on p.id=pv.product_id
   join public.suppliers s on s.id=ph.supplier_id
   left join public.document_origins o on o.entity_type='purchase' and o.entity_id=ph.id and o.tenant_id=ph.tenant_id
   left join public.business_locations l on l.id=o.location_id
   where ph.tenant_id=p_tenant_id and coalesce(ph.status,'') not in('cancelled','void')
 )
 select h.source_type,h.document_id,h.document_number,h.purchase_date,h.location_id,h.location_name,h.supplier_id,h.supplier_name,
        h.variant_id,h.product_name,h.sku,h.quantity,h.unit_cost,h.tax_rate,h.line_total
 from history h
 where (p_variant_id is null or h.variant_id=p_variant_id)
   and (p_supplier_id is null or h.supplier_id=p_supplier_id)
   and (p_location_id is null or h.location_id=p_location_id)
   and (h.location_id is null or private.erp_document_scope_allowed(p_tenant_id,h.location_id,p_location_id,'view'))
   and (trim(coalesce(p_query,''))='' or lower(coalesce(h.document_number,'')) like q or lower(coalesce(h.supplier_name,'')) like q or lower(coalesce(h.product_name,'')) like q or lower(coalesce(h.sku,'')) like q)
 order by h.purchase_date desc,h.document_number desc
 limit greatest(1,least(coalesce(p_limit,1000),5000));
end $$;
grant execute on function public.purchase_price_history_v484(uuid,uuid,uuid,uuid,text,integer) to authenticated;

-- A compact, user-facing purchasing lifecycle summary used by the details UI.
create or replace function public.purchase_cycle_summary_v490(p_tenant_id uuid,p_purchase_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_loc uuid;v jsonb;begin
  select location_id into v_loc from public.purchase_orders_v480 where tenant_id=p_tenant_id and id=p_purchase_order_id;
  if v_loc is null then raise exception 'Purchase Order not found';end if;
  perform private.purchasing_v484_access(p_tenant_id,v_loc,false);
  select jsonb_build_object(
    'purchase_order_id',po.id,'order_number',po.order_number,'status',po.status,
    'request_id',po.request_id,'request_number',pr.request_number,
    'supplier_id',po.supplier_id,'supplier_name',s.name,'location_id',po.location_id,'location_name',l.name,
    'ordered_quantity',coalesce(sum(i.quantity),0),'received_quantity',coalesce(sum(i.received_quantity),0),
    'accepted_quantity',coalesce(sum(i.accepted_quantity),0),'damaged_quantity',coalesce(sum(i.damaged_quantity),0),
    'rejected_quantity',coalesce(sum(i.rejected_quantity),0),'invoiced_quantity',coalesce(sum(i.invoiced_quantity),0),
    'remaining_receive_quantity',coalesce(sum(greatest(i.quantity-i.received_quantity,0)),0),
    'remaining_invoice_quantity',coalesce(sum(greatest(i.accepted_quantity+i.damaged_quantity-i.invoiced_quantity,0)),0),
    'po_total',po.grand_total,
    'posted_invoice_total',coalesce((select sum(pi.grand_total) from public.purchase_invoices_v484 pi where pi.purchase_order_id=po.id and pi.status in('posted','part_paid','paid')),0),
    'invoice_balance_due',coalesce((select sum(pi.balance_due) from public.purchase_invoices_v484 pi where pi.purchase_order_id=po.id and pi.status in('posted','part_paid')),0),
    'grn_count',(select count(*) from public.goods_receipts_v484 g where g.purchase_order_id=po.id and g.status='posted'),
    'invoice_count',(select count(*) from public.purchase_invoices_v484 pi where pi.purchase_order_id=po.id and pi.status<>'void')
  ) into v
  from public.purchase_orders_v480 po
  join public.suppliers s on s.id=po.supplier_id
  join public.business_locations l on l.id=po.location_id
  left join public.purchase_requests_v484 pr on pr.id=po.request_id
  left join public.purchase_order_items_v480 i on i.purchase_order_id=po.id
  where po.tenant_id=p_tenant_id and po.id=p_purchase_order_id
  group by po.id,pr.request_number,s.name,l.name;
  return coalesce(v,'{}'::jsonb);
end $$;
grant execute on function public.purchase_cycle_summary_v490(uuid,uuid) to authenticated;

-- Keep the rounded v4.8.9 invoice posting semantics, but finish the PO
-- automatically once everything received is invoiced and all ordered quantity
-- has been physically processed.
create or replace function public.purchase_invoice_post_v484(p_tenant_id uuid,p_purchase_invoice_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare i public.purchase_invoices_v484%rowtype;li record;v_lines jsonb:='[]'::jsonb;v_net numeric;v_open boolean;v_old_status text;begin
  select * into i from public.purchase_invoices_v484 where tenant_id=p_tenant_id and id=p_purchase_invoice_id for update;
  if not found then raise exception 'Purchase Invoice not found';end if;
  perform private.purchasing_v484_access(p_tenant_id,i.location_id,true);
  if i.status in('posted','part_paid','paid') then return jsonb_build_object('success',true,'purchase_invoice_id',i.id,'invoice_number',i.invoice_number,'status',i.status,'idempotent',true);end if;
  if i.status<>'draft' then raise exception 'Only Draft invoices can be posted';end if;
  if i.grand_total<=0 then raise exception 'Purchase Invoice total must be positive';end if;
  v_net:=greatest(i.subtotal+i.additional_charges,0);
  if v_net>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'inventory_asset'),'debit',v_net,'credit',0,'party_type','supplier','party_id',i.supplier_id,'description','Purchase invoice / inventory'));end if;
  if i.tax_total>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'input_gst'),'debit',i.tax_total,'credit',0,'description','Input GST'));end if;
  if i.round_off>0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',i.round_off,'credit',0,'description','Purchase invoice round off'));end if;
  if i.round_off< -0.000001 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'rounding'),'debit',0,'credit',abs(i.round_off),'description','Purchase invoice round off'));end if;
  v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',private.v4_account_id(p_tenant_id,'accounts_payable'),'debit',0,'credit',i.grand_total,'party_type','supplier','party_id',i.supplier_id,'description','Supplier payable'));
  perform private.v4_journal_create(p_tenant_id,i.location_id,i.invoice_date,'Purchase Invoice '||i.invoice_number,'purchase_invoice_v484',i.id,i.invoice_number,v_lines);
  update public.purchase_invoices_v484 set status='posted',posted_by=auth.uid(),posted_at=now(),balance_due=grand_total-paid_total,updated_at=now() where id=i.id;
  for li in select purchase_order_item_id,sum(quantity) qty from public.purchase_invoice_items_v484 where purchase_invoice_id=i.id group by purchase_order_item_id loop
    update public.purchase_order_items_v480 set invoiced_quantity=invoiced_quantity+li.qty where id=li.purchase_order_item_id;
  end loop;

  select exists(
    select 1 from public.purchase_order_items_v480 poi
    where poi.purchase_order_id=i.purchase_order_id
      and (poi.received_quantity+0.000001<poi.quantity or poi.invoiced_quantity+0.000001<poi.accepted_quantity+poi.damaged_quantity)
  ) into v_open;
  if not v_open then
    select status into v_old_status from public.purchase_orders_v480 where id=i.purchase_order_id for update;
    if v_old_status not in('closed','cancelled') then
      update public.purchase_orders_v480 set status='closed',closed_at=coalesce(closed_at,now()),updated_at=now() where id=i.purchase_order_id;
      insert into public.purchase_order_status_history_v480(purchase_order_id,from_status,to_status,reason,changed_by)
      values(i.purchase_order_id,v_old_status,'closed','All received quantities invoiced; Purchase Order closed automatically',auth.uid());
    end if;
  end if;

  perform private.thq_sync_bump_v480(p_tenant_id,'accounting','purchase_invoice',i.id::text,'post');
  return jsonb_build_object('success',true,'purchase_invoice_id',i.id,'invoice_number',i.invoice_number,'status','posted','grand_total',i.grand_total,'round_off',i.round_off,'purchase_order_status',case when v_open then null else 'closed' end);
end $$;
grant execute on function public.purchase_invoice_post_v484(uuid,uuid) to authenticated;

-- A single server-side health check for the two workflows. It lets the Client
-- present a clean actionable message instead of raw FunctionsHttp/PostgREST errors.
create or replace function public.finance_operations_health_v490(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare v_missing text[]:='{}'::text[];begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if to_regprocedure('public.loan_warnings_v490(uuid,uuid,integer)') is null then v_missing:=array_append(v_missing,'loan_warnings_v490');end if;
  if to_regprocedure('public.loan_payment_create_v490(uuid,uuid,numeric,date,text,text,text,uuid)') is null then v_missing:=array_append(v_missing,'loan_payment_create_v490');end if;
  if to_regprocedure('public.purchase_request_create_v484(uuid,uuid,jsonb,date,text,uuid,text,text)') is null then v_missing:=array_append(v_missing,'purchase_request_create_v484');end if;
  if to_regprocedure('public.goods_receipt_post_v484(uuid,uuid,uuid)') is null then v_missing:=array_append(v_missing,'goods_receipt_post_v484');end if;
  if to_regprocedure('public.purchase_invoice_post_v484(uuid,uuid)') is null then v_missing:=array_append(v_missing,'purchase_invoice_post_v484');end if;
  if to_regprocedure('public.purchase_price_history_v484(uuid,uuid,uuid,uuid,text,integer)') is null then v_missing:=array_append(v_missing,'purchase_price_history_v484');end if;
  return jsonb_build_object('ok',cardinality(v_missing)=0,'missing',to_jsonb(v_missing),'migration_required',187);
end $$;
grant execute on function public.finance_operations_health_v490(uuid) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(187,'4.9.0','Purchase & Loan Completion','Fixes loan warnings and purchase price history, adds purchase-cycle summary and automatic PO closing after complete receiving/invoicing.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 20 migration 187 purchase/loan completion applied' as status;

-- ============================================================================
-- MIGRATION 188: 188_v490_transaction_bulk_import.sql
-- ============================================================================

-- THQ ERP v4.9.0 Build 20 — auditable bulk Sales/Purchase import.
begin;

create table if not exists public.transaction_import_runs_v490(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  import_type text not null check(import_type in('sales','purchases')),
  location_id uuid not null references public.business_locations(id) on delete restrict,
  source_name text,
  source_key text not null,
  row_count integer not null default 0,
  document_count integer not null default 0,
  success_count integer not null default 0,
  failed_count integer not null default 0,
  skipped_count integer not null default 0,
  status text not null default 'processing' check(status in('processing','completed','completed_with_errors','failed')),
  result jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique(tenant_id,import_type,source_key)
);
create index if not exists idx_transaction_import_runs_v490 on public.transaction_import_runs_v490(tenant_id,created_at desc);
alter table public.transaction_import_runs_v490 enable row level security;
revoke all on public.transaction_import_runs_v490 from anon,authenticated;

create table if not exists public.transaction_import_documents_v490(
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.transaction_import_runs_v490(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  import_type text not null check(import_type in('sales','purchases')),
  external_key text not null,
  entity_id uuid,
  entity_number text,
  status text not null default 'processing' check(status in('processing','success','failed')),
  error_message text,
  response jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,import_type,external_key)
);
create index if not exists idx_transaction_import_documents_v490_run on public.transaction_import_documents_v490(run_id,status);
alter table public.transaction_import_documents_v490 enable row level security;
revoke all on public.transaction_import_documents_v490 from anon,authenticated;

create or replace function public.transaction_bulk_import_v490(
  p_tenant_id uuid,
  p_import_type text,
  p_location_id uuid,
  p_device_id uuid,
  p_source_name text,
  p_source_key text,
  p_documents jsonb
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  v_type text:=lower(trim(coalesce(p_import_type,'')));
  v_run uuid;v_existing public.transaction_import_runs_v490%rowtype;
  v_success integer:=0;v_failed integer:=0;v_skipped integer:=0;v_rows integer:=0;
  v_results jsonb:='[]'::jsonb;d jsonb;v_external text;v_doc public.transaction_import_documents_v490%rowtype;
  v_result jsonb;v_entity uuid;v_number text;v_request text;v_message text;
  v_party uuid;v_items jsonb;v_date date;v_due date;v_amount numeric;v_add numeric;v_round numeric;
begin
  if v_type not in('sales','purchases') then raise exception 'Import type must be sales or purchases';end if;
  if nullif(trim(coalesce(p_source_key,'')),'') is null then raise exception 'Import source key is required';end if;
  if p_documents is null or jsonb_typeof(p_documents)<>'array' or jsonb_array_length(p_documents)=0 then raise exception 'At least one document is required';end if;
  if jsonb_array_length(p_documents)>1000 then raise exception 'A single import is limited to 1000 documents';end if;
  if p_location_id is null then raise exception 'A concrete store/location is required';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'bulk_import.use') then raise exception 'Bulk Import permission required';end if;
  if v_type='purchases' then perform private.purchasing_v484_access(p_tenant_id,p_location_id,true);
  else
    if not private.erp_document_scope_allowed(p_tenant_id,p_location_id,p_location_id,'operate') then raise exception 'Location access denied';end if;
    if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'sales.manage') then raise exception 'Sales management permission required';end if;
  end if;

  select * into v_existing from public.transaction_import_runs_v490 where tenant_id=p_tenant_id and import_type=v_type and source_key=trim(p_source_key) for update;
  if found and v_existing.status in('completed','completed_with_errors') then
    return coalesce(v_existing.result,'{}'::jsonb)||jsonb_build_object('idempotent_replay',true,'run_id',v_existing.id);
  end if;
  if found then
    v_run:=v_existing.id;
    update public.transaction_import_runs_v490 set status='processing',source_name=nullif(trim(coalesce(p_source_name,'')),''),completed_at=null where id=v_run;
  else
    insert into public.transaction_import_runs_v490(tenant_id,import_type,location_id,source_name,source_key,document_count,created_by)
    values(p_tenant_id,v_type,p_location_id,nullif(trim(coalesce(p_source_name,'')),''),trim(p_source_key),jsonb_array_length(p_documents),auth.uid()) returning id into v_run;
  end if;

  for d in select value from jsonb_array_elements(p_documents) loop
    v_rows:=v_rows+greatest(coalesce(nullif(d->>'source_row_count','')::integer,1),1);
    v_external:=nullif(trim(coalesce(d->>'external_key',d->>'document_ref','')),'');
    if v_external is null then
      v_failed:=v_failed+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('status','failed','error','Each document requires external_key/document_ref'));
      continue;
    end if;

    select * into v_doc from public.transaction_import_documents_v490 where tenant_id=p_tenant_id and import_type=v_type and external_key=v_external for update;
    if found and v_doc.status='success' then
      v_skipped:=v_skipped+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('external_key',v_external,'status','success','entity_id',v_doc.entity_id,'entity_number',v_doc.entity_number,'idempotent_replay',true));
      continue;
    end if;
    if found then
      update public.transaction_import_documents_v490 set run_id=v_run,status='processing',error_message=null,updated_at=now() where id=v_doc.id;
    else
      insert into public.transaction_import_documents_v490(run_id,tenant_id,import_type,external_key,status)
      values(v_run,p_tenant_id,v_type,v_external,'processing') returning * into v_doc;
    end if;

    begin
      v_items:=coalesce(d->'items','[]'::jsonb);
      if jsonb_typeof(v_items)<>'array' or jsonb_array_length(v_items)=0 then raise exception 'Document has no items';end if;
      v_date:=coalesce(nullif(d->>'document_date','')::date,current_date);
      v_due:=nullif(d->>'due_date','')::date;
      v_add:=greatest(coalesce(nullif(d->>'additional_charges','')::numeric,0),0);
      v_round:=coalesce(nullif(d->>'round_off','')::numeric,0);
      v_amount:=greatest(coalesce(nullif(d->>'initial_payment','')::numeric,0),0);
      v_request:='bulk-'||v_type||'-'||md5(p_tenant_id::text||':'||v_external);

      if v_type='sales' then
        v_party:=nullif(d->>'customer_id','')::uuid;
        if v_party is null then raise exception 'Customer is required';end if;
        v_result:=public.sales_create_v489(
          p_tenant_id,v_party,v_date,v_due,v_items,v_add,v_round,v_amount,
          coalesce(nullif(lower(trim(d->>'payment_method')),''),'cash'),coalesce(d->>'payment_reference',''),coalesce(d->>'notes',''),
          p_location_id,p_device_id,v_request
        );
        v_entity:=nullif(v_result->>'sale_id','')::uuid;v_number:=coalesce(v_result->>'invoice_number',v_result->>'sale_number');
      else
        v_party:=nullif(d->>'supplier_id','')::uuid;
        if v_party is null then raise exception 'Supplier is required';end if;
        if nullif(trim(coalesce(d->>'supplier_invoice_number','')),'') is null then raise exception 'Supplier invoice number is required';end if;
        v_result:=public.purchases_create_v489(
          p_tenant_id,v_party,trim(d->>'supplier_invoice_number'),v_date,v_due,v_items,v_add,v_round,v_amount,
          coalesce(nullif(lower(trim(d->>'payment_method')),''),'bank'),coalesce(d->>'notes',''),p_location_id,p_device_id,v_request
        );
        v_entity:=nullif(v_result->>'purchase_id','')::uuid;v_number:=v_result->>'purchase_number';
      end if;
      if v_entity is null then raise exception 'Transaction creation returned no document ID';end if;
      update public.transaction_import_documents_v490 set status='success',entity_id=v_entity,entity_number=v_number,response=coalesce(v_result,'{}'::jsonb),error_message=null,updated_at=now() where id=v_doc.id;
      v_success:=v_success+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('external_key',v_external,'status','success','entity_id',v_entity,'entity_number',v_number,'response',v_result));
    exception when others then
      v_message:=sqlerrm;
      update public.transaction_import_documents_v490 set status='failed',error_message=v_message,response='{}'::jsonb,updated_at=now() where id=v_doc.id;
      v_failed:=v_failed+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('external_key',v_external,'status','failed','error',v_message));
    end;
  end loop;

  v_result:=jsonb_build_object(
    'success',v_failed=0,'run_id',v_run,'import_type',v_type,'source_key',trim(p_source_key),
    'success_count',v_success,'failed_count',v_failed,'skipped_count',v_skipped,'document_count',jsonb_array_length(p_documents),'row_count',v_rows,
    'documents',v_results
  );
  update public.transaction_import_runs_v490
  set row_count=v_rows,document_count=jsonb_array_length(p_documents),success_count=v_success,failed_count=v_failed,skipped_count=v_skipped,
      status=case when v_failed=0 then 'completed' else 'completed_with_errors' end,result=v_result,completed_at=now()
  where id=v_run;
  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','bulk_'||v_type,v_run::text,'import');
  return v_result;
exception when others then
  if v_run is not null then
    update public.transaction_import_runs_v490 set status='failed',result=jsonb_build_object('error',sqlerrm),completed_at=now() where id=v_run;
  end if;
  raise;
end $$;
grant execute on function public.transaction_bulk_import_v490(uuid,text,uuid,uuid,text,text,jsonb) to authenticated;

create or replace function public.transaction_bulk_import_history_v490(p_tenant_id uuid,p_import_type text default null,p_limit integer default 100)
returns table(run_id uuid,import_type text,location_id uuid,location_name text,source_name text,source_key text,row_count integer,document_count integer,success_count integer,failed_count integer,skipped_count integer,status text,created_at timestamptz,completed_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$ begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'bulk_import.use') then raise exception 'Bulk Import permission required';end if;
  return query
  select r.id,r.import_type,r.location_id,l.name::text,r.source_name,r.source_key,r.row_count,r.document_count,r.success_count,r.failed_count,r.skipped_count,r.status,r.created_at,r.completed_at
  from public.transaction_import_runs_v490 r join public.business_locations l on l.id=r.location_id
  where r.tenant_id=p_tenant_id and (p_import_type is null or trim(p_import_type)='' or r.import_type=lower(trim(p_import_type)))
    and private.erp_document_scope_allowed(p_tenant_id,r.location_id,null,'view')
  order by r.created_at desc limit greatest(1,least(coalesce(p_limit,100),1000));
end $$;
grant execute on function public.transaction_bulk_import_history_v490(uuid,text,integer) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(188,'4.9.0','Transaction Bulk Import','Auditable, idempotent Excel bulk import engine for Sales and Direct Purchases using the normal stock, tax, payment and accounting transaction functions.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 20 migration 188 transaction bulk import applied' as status;

-- ============================================================================
-- MIGRATION 189: 189_v490_purchase_controls.sql
-- ============================================================================

-- THQ ERP v4.9.0 Build 20 — Purchasing operational controls and reversals.
begin;

create or replace function public.goods_receipt_cancel_v490(
  p_tenant_id uuid,p_goods_receipt_id uuid,p_reason text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare g public.goods_receipts_v484%rowtype;begin
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Cancellation reason is required';end if;
  select * into g from public.goods_receipts_v484 where tenant_id=p_tenant_id and id=p_goods_receipt_id for update;
  if not found then raise exception 'GRN not found';end if;
  perform private.purchasing_v484_access(p_tenant_id,g.location_id,true);
  if g.status='cancelled' then return jsonb_build_object('success',true,'goods_receipt_id',g.id,'status','cancelled','idempotent',true);end if;
  if g.status<>'draft' then raise exception 'Only Draft GRNs can be cancelled. Posted receipts require a controlled purchase return/reversal so stock traceability is preserved';end if;
  update public.goods_receipts_v484 set status='cancelled',cancelled_by=auth.uid(),cancelled_at=now(),notes=concat_ws(E'\n',notes,'Cancelled: '||trim(p_reason)),updated_at=now() where id=g.id;
  perform private.thq_sync_bump_v480(p_tenant_id,'transactions','goods_receipt',g.id::text,'cancel');
  return jsonb_build_object('success',true,'goods_receipt_id',g.id,'grn_number',g.grn_number,'status','cancelled');
end $$;
grant execute on function public.goods_receipt_cancel_v490(uuid,uuid,text) to authenticated;

create or replace function public.purchase_invoice_void_v490(
  p_tenant_id uuid,p_purchase_invoice_id uuid,p_reason text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare i public.purchase_invoices_v484%rowtype;li record;v_po_status text;v_new_po_status text;v_has_received boolean;v_complete_received boolean;begin
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Void reason is required';end if;
  select * into i from public.purchase_invoices_v484 where tenant_id=p_tenant_id and id=p_purchase_invoice_id for update;
  if not found then raise exception 'Purchase Invoice not found';end if;
  perform private.purchasing_v484_access(p_tenant_id,i.location_id,true);
  if i.status='void' then return jsonb_build_object('success',true,'purchase_invoice_id',i.id,'status','void','idempotent',true);end if;
  if i.status not in('draft','posted') then raise exception 'Only Draft or unpaid Posted invoices can be voided';end if;
  if coalesce(i.paid_total,0)>0.005 or exists(
    select 1 from public.supplier_payment_allocations_v484 a
    join public.supplier_payments_v484 p on p.id=a.supplier_payment_id
    where a.purchase_invoice_id=i.id and p.status='posted'
  ) then raise exception 'Invoice has supplier payments. Void/reverse those payments first';end if;

  if i.status='posted' then
    update public.journal_entries set status='reversed'
    where tenant_id=p_tenant_id and source_type='purchase_invoice_v484' and source_id=i.id and status='posted';
    insert into public.supplier_ledger_entries_v484(
      tenant_id,supplier_id,location_id,entry_date,entry_type,source_id,reference_number,description,debit,credit,created_by
    ) values(
      p_tenant_id,i.supplier_id,i.location_id,current_date,'void',i.id,i.invoice_number,
      'Void purchase invoice: '||trim(p_reason),0,i.grand_total,auth.uid()
    ) on conflict(tenant_id,entry_type,source_id) do nothing;
    for li in select purchase_order_item_id,sum(quantity) qty from public.purchase_invoice_items_v484 where purchase_invoice_id=i.id group by purchase_order_item_id loop
      update public.purchase_order_items_v480
      set invoiced_quantity=greatest(invoiced_quantity-li.qty,0)
      where id=li.purchase_order_item_id;
    end loop;
  end if;

  update public.purchase_invoices_v484
  set status='void',balance_due=0,updated_at=now(),notes=concat_ws(E'\n',notes,'Voided: '||trim(p_reason))
  where id=i.id;

  if i.purchase_order_id is not null then
    select status into v_po_status from public.purchase_orders_v480 where id=i.purchase_order_id for update;
    select exists(select 1 from public.purchase_order_items_v480 where purchase_order_id=i.purchase_order_id and received_quantity>0.000001),
           not exists(select 1 from public.purchase_order_items_v480 where purchase_order_id=i.purchase_order_id and received_quantity+0.000001<quantity)
    into v_has_received,v_complete_received;
    v_new_po_status:=case when v_complete_received then 'received' when v_has_received then 'partially_received' else case when v_po_status='draft' then 'draft' else 'ordered' end end;
    if v_po_status='closed' or v_po_status='received' then
      update public.purchase_orders_v480 set status=v_new_po_status,closed_at=null,updated_at=now() where id=i.purchase_order_id;
      insert into public.purchase_order_status_history_v480(purchase_order_id,from_status,to_status,reason,changed_by)
      values(i.purchase_order_id,v_po_status,v_new_po_status,'Reopened because invoice '||i.invoice_number||' was voided',auth.uid());
    end if;
  end if;

  perform private.thq_sync_bump_v480(p_tenant_id,'accounting','purchase_invoice',i.id::text,'void');
  return jsonb_build_object('success',true,'purchase_invoice_id',i.id,'invoice_number',i.invoice_number,'status','void','purchase_order_status',v_new_po_status);
end $$;
grant execute on function public.purchase_invoice_void_v490(uuid,uuid,text) to authenticated;

create or replace function public.supplier_payment_create_v490(
  p_tenant_id uuid,p_location_id uuid,p_supplier_id uuid,p_payment_date date,p_amount numeric,p_payment_method text,
  p_allocations jsonb default '[]'::jsonb,p_reference_number text default null,p_notes text default null,p_device_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v jsonb;v_payment uuid;v_no text;v_shift uuid;begin
  if p_device_id is not null and not exists(
    select 1 from public.business_devices d where d.id=p_device_id and d.tenant_id=p_tenant_id and d.location_id=p_location_id and d.status='active'
  ) then raise exception 'Invalid device for supplier payment location';end if;
  v:=public.supplier_payment_create_v484(p_tenant_id,p_location_id,p_supplier_id,p_payment_date,p_amount,p_payment_method,p_allocations,p_reference_number,p_notes);
  v_payment:=nullif(v->>'supplier_payment_id','')::uuid;v_no:=v->>'payment_number';
  if v_payment is not null and p_device_id is not null and lower(trim(coalesce(p_payment_method,'')))='cash' then
    select id into v_shift from public.cashier_shifts where tenant_id=p_tenant_id and device_id=p_device_id and status='open' order by opened_at desc limit 1;
    if v_shift is not null and not exists(select 1 from public.cash_drawer_movements where reference_type='supplier_payment_v490' and reference_id=v_payment) then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(p_tenant_id,v_shift,'cash_out',-abs(p_amount),'supplier_payment_v490',v_payment,v_no,'Supplier cash payment',auth.uid());
    end if;
  end if;
  return v||jsonb_build_object('payment_engine','v4.9.0');
end $$;
grant execute on function public.supplier_payment_create_v490(uuid,uuid,uuid,date,numeric,text,jsonb,text,text,uuid) to authenticated;

create or replace function public.supplier_payment_void_v490(
  p_tenant_id uuid,p_supplier_payment_id uuid,p_reason text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare p public.supplier_payments_v484%rowtype;a record;v_device uuid;v_shift uuid;begin
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Void reason is required';end if;
  select * into p from public.supplier_payments_v484 where tenant_id=p_tenant_id and id=p_supplier_payment_id for update;
  if not found then raise exception 'Supplier payment not found';end if;
  perform private.purchasing_v484_access(p_tenant_id,p.location_id,true);
  if p.status='void' then return jsonb_build_object('success',true,'supplier_payment_id',p.id,'status','void','idempotent',true);end if;

  update public.supplier_payments_v484 set status='void',voided_by=auth.uid(),voided_at=now(),void_reason=trim(p_reason) where id=p.id;
  for a in select purchase_invoice_id from public.supplier_payment_allocations_v484 where supplier_payment_id=p.id loop
    perform private.v484_refresh_invoice_payment_status(a.purchase_invoice_id);
  end loop;
  update public.journal_entries set status='reversed'
  where tenant_id=p_tenant_id and source_type='supplier_payment_v484' and source_id=p.id and status='posted';
  insert into public.supplier_ledger_entries_v484(
    tenant_id,supplier_id,location_id,entry_date,entry_type,source_id,reference_number,description,debit,credit,created_by
  ) values(
    p_tenant_id,p.supplier_id,p.location_id,current_date,'void',p.id,p.payment_number,
    'Void supplier payment: '||trim(p_reason),p.amount,0,auth.uid()
  ) on conflict(tenant_id,entry_type,source_id) do nothing;

  select d.id into v_device
  from public.business_devices d join public.cashier_shifts s on s.device_id=d.id and s.tenant_id=p_tenant_id and s.status='open'
  where d.tenant_id=p_tenant_id and d.location_id=p.location_id and d.status='active'
    and exists(select 1 from public.cash_drawer_movements m where m.shift_id=s.id and m.reference_type='supplier_payment_v490' and m.reference_id=p.id)
  order by s.opened_at desc limit 1;
  if v_device is not null and lower(p.payment_method)='cash' then
    select id into v_shift from public.cashier_shifts where tenant_id=p_tenant_id and device_id=v_device and status='open' order by opened_at desc limit 1;
    if v_shift is not null and not exists(select 1 from public.cash_drawer_movements where reference_type='supplier_payment_void_v490' and reference_id=p.id) then
      insert into public.cash_drawer_movements(tenant_id,shift_id,movement_type,amount,reference_type,reference_id,reference_number,note,created_by)
      values(p_tenant_id,v_shift,'cash_in',abs(p.amount),'supplier_payment_void_v490',p.id,p.payment_number,'Supplier payment void: '||trim(p_reason),auth.uid());
    end if;
  end if;
  perform private.thq_sync_bump_v480(p_tenant_id,'accounting','supplier_payment',p.id::text,'void');
  return jsonb_build_object('success',true,'supplier_payment_id',p.id,'payment_number',p.payment_number,'status','void');
end $$;
grant execute on function public.supplier_payment_void_v490(uuid,uuid,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(189,'4.9.0','Purchase Controls','Draft GRN cancellation, controlled Purchase Invoice void/reopen, supplier payment cash-drawer integration and payment reversal.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 20 migration 189 purchase controls applied' as status;

-- ============================================================================
-- MIGRATION 190: 190_v490_purchase_loan_operations_release.sql
-- ============================================================================

-- THQ ERP v4.9.0 Build 20 — Purchase + Loan operations release contract.
begin;

-- Bulk Import now also includes transaction templates/imports, not only masters.
update public.modules
set description='Bulk products, customers, suppliers, sales and purchases import'
where key='bulk_import';

-- Publish the complete API surface used by Build 20. The previous API contract
-- stays source-compatible; these resources are additive.
create or replace function public.thq_api_contract_v480()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
  select jsonb_build_object(
    'product','THQ ERP','api_version','v1','adapter','supabase','transport','https/json',
    'resources',jsonb_build_array(
      'sync','attention','runtime-health','restaurant-operations',
      'inventory-intelligence','inventory-movements','units','product-units','pricing','product-identifiers','product-lookup','label-templates',
      'tracking-policy','serials','batches','batch-history','warranties','customer-credit','supplier-payables','reorder-suggestions',
      'purchase-requests','purchase-orders','goods-receipts','purchase-invoices','supplier-payments-v2','supplier-ledger-v2','purchase-price-history','purchasing-dashboard','purchase-cycle',
      'loans','loan-dashboard','loan-warnings','customer-loans',
      'finance-operations-health','transaction-bulk-import',
      'warehouses','warehouse-inventory','stock-transfers','stock-counts','stock-reconciliation','business-summary','store-summary',
      'offline-pos','client-mobile','mobile-pos'
    ),
    'core_financial_posting','direct_hardened_rpc',
    'unit_engine','v4.8.1','authoritative_sale_pricing','v4.8.2','inventory_tracking','v4.8.3',
    'purchasing_engine','v4.8.4','warehouse_engine','v4.8.5','offline_pos_engine','v4.8.6',
    'client_mobile_release','4.8.7','mobile_pos_release','4.8.8',
    'round_off_engine','v4.8.9','restaurant_engine','v4.8.9','operations_intelligence','v4.8.9',
    'loan_engine','v4.9.0','loan_accounting','double_entry','loan_warnings',true,
    'purchase_cycle_engine','v4.9.0','transaction_bulk_import','v4.9.0','purchase_reversals','v4.9.0',
    'mobile_ready',true
  )
$$;
grant execute on function public.thq_api_contract_v480() to authenticated;

-- Build 20 remains on the 4.9.0 compatibility line. Older 4.9.0 clients can
-- keep working after these additive migrations while Build 20 requires the
-- corrected Purchase/Loan functions for its enhanced workspaces.
create or replace function public.thq_backend_contract_v47()
returns jsonb language sql stable security definer set search_path=public,private,pg_temp as $$
 select jsonb_build_object(
   'product','THQ ERP',
   'schema_version',coalesce((select schema_version from public.thq_schema_releases order by migration_no desc limit 1),'unknown'),
   'migration_no',coalesce((select max(migration_no) from public.thq_schema_releases),0),
   'minimum_app_version','4.9.0',
   'release','Purchase & Loan Operations',
   'api_version','v1',
   'backward_compatible',true
 )
$$;
grant execute on function public.thq_backend_contract_v47() to authenticated;

create or replace function public.thq_v490_build20_verify()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare
  v_missing text[]:='{}'::text[];
  v_proc text;
  v_required_procs text[]:=array[
    'loan_create_v490','loan_update_v490','loan_submit_v490','loan_decide_v490','loan_disburse_v490',
    'loan_payment_create_v490','loan_payment_reverse_v490','loan_rate_change_v490','loan_status_v490',
    'loan_list_v490','loan_detail_v490','loan_dashboard_v490','loan_warnings_v490','customer_loan_summary_v490',
    'purchase_request_create_v484','purchase_request_list_v484','purchase_request_detail_v484','purchase_request_status_v484',
    'purchase_order_create_v484','purchase_order_list_v484','purchase_order_detail_v484','purchase_order_decide_v484',
    'goods_receipt_create_v484','goods_receipt_post_v484','goods_receipt_cancel_v490','goods_receipt_detail_v484',
    'purchase_invoice_create_v489','purchase_invoice_post_v484','purchase_invoice_void_v490','purchase_invoice_detail_v484',
    'supplier_payment_create_v490','supplier_payment_void_v490','suppliers_get_statement_v484','purchase_price_history_v484',
    'purchasing_dashboard_v484','purchase_cycle_summary_v490','finance_operations_health_v490',
    'transaction_bulk_import_v490','transaction_bulk_import_history_v490','thq_api_contract_v480'
  ];
begin
  foreach v_proc in array v_required_procs loop
    if not exists(
      select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_proc
    ) then v_missing:=array_append(v_missing,v_proc);end if;
  end loop;

  if to_regclass('public.loan_accounts_v490') is null then v_missing:=array_append(v_missing,'loan_accounts_v490');end if;
  if to_regclass('public.loan_schedule_v490') is null then v_missing:=array_append(v_missing,'loan_schedule_v490');end if;
  if to_regclass('public.loan_payments_v490') is null then v_missing:=array_append(v_missing,'loan_payments_v490');end if;
  if to_regclass('public.transaction_import_runs_v490') is null then v_missing:=array_append(v_missing,'transaction_import_runs_v490');end if;
  if to_regclass('public.transaction_import_documents_v490') is null then v_missing:=array_append(v_missing,'transaction_import_documents_v490');end if;

  if not exists(select 1 from public.modules where key='loans' and is_active) then v_missing:=array_append(v_missing,'module.loans');end if;
  if not exists(select 1 from public.modules where key='purchases' and is_active) then v_missing:=array_append(v_missing,'module.purchases');end if;
  if not exists(select 1 from public.modules where key='purchase_details' and is_active) then v_missing:=array_append(v_missing,'module.purchase_details');end if;
  if not exists(select 1 from public.modules where key='sales' and is_active) then v_missing:=array_append(v_missing,'module.sales');end if;
  if not exists(select 1 from public.modules where key='bulk_import' and is_active) then v_missing:=array_append(v_missing,'module.bulk_import');end if;
  if not exists(select 1 from public.permissions where key='loans.collect') then v_missing:=array_append(v_missing,'permission.loans.collect');end if;
  if not exists(select 1 from public.permissions where key='purchases.manage') then v_missing:=array_append(v_missing,'permission.purchases.manage');end if;
  if not exists(select 1 from public.permissions where key='bulk_import.use') then v_missing:=array_append(v_missing,'permission.bulk_import.use');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='loan_receivable') then v_missing:=array_append(v_missing,'mapping.loan_receivable');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='accounts_payable') then v_missing:=array_append(v_missing,'mapping.accounts_payable');end if;
  if not exists(select 1 from public.accounting_account_mappings where mapping_key='input_gst') then v_missing:=array_append(v_missing,'mapping.input_gst');end if;

  return jsonb_build_object(
    'ready',cardinality(v_missing)=0,
    'missing',to_jsonb(v_missing),
    'schema_version','4.9.0',
    'migration_no',190,
    'minimum_app_version','4.9.0',
    'api_version','v1',
    'loan_runtime_fix',true,
    'loan_collection_and_details',true,
    'loan_accounting',true,
    'purchase_price_history_fix',true,
    'purchase_request_to_payment_cycle',true,
    'grn_stock_traceability',true,
    'purchase_invoice_accounts_payable',true,
    'supplier_payment_allocation',true,
    'controlled_purchase_reversals',true,
    'bulk_sales_import',true,
    'bulk_purchase_import',true,
    'backward_compatible_backend_contract',true
  );
end $$;
grant execute on function public.thq_v490_build20_verify() to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  190,
  '4.9.0',
  'Purchase & Loan Operations',
  'Build 20 completes loan collection/details, repairs loan warnings and purchase price history, completes PR/PO/GRN/invoice/supplier-payment operations and adds auditable bulk Sales/Purchase import.'
)
on conflict(migration_no) do update set
  schema_version=excluded.schema_version,
  release_name=excluded.release_name,
  notes=excluded.notes;

commit;
select 'THQ ERP v4.9.0 Build 20 migration 190 purchase/loan operations release applied' as status;
