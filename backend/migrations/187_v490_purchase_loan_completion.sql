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
