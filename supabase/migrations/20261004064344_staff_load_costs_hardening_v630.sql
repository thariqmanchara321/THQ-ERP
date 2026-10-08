-- Harden payroll SQL names, batch expense additions and financial report totals.


create or replace function private.staff_payment_post_v630(t uuid,s uuid,location uuid,data jsonb,target_earning uuid default null)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare member public.staff_members_v630%rowtype;p public.staff_payments_v630%rowtype;e record;
 v_payment_amount numeric:=round((data->>'amount')::numeric,2);remaining numeric;allocated numeric;allocated_total numeric:=0;lines jsonb:='[]';
 req text:=data->>'request_id';method text:=coalesce(data->>'payment_method','cash');day date:=coalesce((data->>'date')::date,current_date);journal uuid;
begin
 select * into member from public.staff_members_v630 where tenant_id=t and id=s for update;
 if not found then raise exception 'Staff member not found';end if;
 if member.location_id is not null and member.location_id<>location then raise exception 'Staff member belongs to a different location';end if;
 perform private.v4_location_access(t,location,'operate');
 if req is null or length(req)>256 or v_payment_amount is null or v_payment_amount<=0 or v_payment_amount>1000000000000 then raise exception 'A positive payment and stable request ID are required';end if;
 select * into p from public.staff_payments_v630 where tenant_id=t and request_id=req;
 if found then if p.staff_id<>s or p.location_id<>location or p.request_payload<>data then raise exception 'Staff payment retry has different data';end if;return p.id;end if;
 if method not in('cash','bank','upi','card','cheque') then raise exception 'Invalid payment method';end if;
 if method<>'cash' and nullif(trim(data->>'reference'),'') is null then raise exception 'Payment reference is required for non-cash payments';end if;
 if target_earning is not null and not exists(select 1 from public.staff_earnings_v630 x where x.tenant_id=t and x.staff_id=s and x.id=target_earning and x.amount-private.staff_earning_paid_v630(x.id)>=v_payment_amount) then raise exception 'Load wage payment exceeds the unpaid wage';end if;
 insert into public.staff_payments_v630(tenant_id,staff_id,location_id,payment_date,amount,payment_method,reference,payee_snapshot,notes,request_id,request_payload)
 values(t,s,location,day,v_payment_amount,method,data->>'reference',member.name,data->>'notes',req,data) returning * into p;
 remaining:=v_payment_amount;
 for e in select x.id,x.amount-private.staff_earning_paid_v630(x.id) outstanding from public.staff_earnings_v630 x
  where x.tenant_id=t and x.staff_id=s and x.location_id=location and (target_earning is null or x.id=target_earning)
  order by x.earning_date,x.created_at,x.id for update of x loop
  allocated:=least(remaining,e.outstanding);
  if allocated>0 then insert into public.staff_payment_allocations_v630(payment_id,earning_id,amount) values(p.id,e.id,allocated);remaining:=remaining-allocated;allocated_total:=allocated_total+allocated;end if;
  exit when remaining<=0;
 end loop;
 update public.staff_payments_v630 set advance_amount=remaining where id=p.id;
 if allocated_total>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',private.workforce_account_v630(t,'staff_payable_v630'),'debit',allocated_total,'party_type','staff','party_id',s));end if;
 if remaining>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',private.workforce_account_v630(t,'staff_advance_v630'),'debit',remaining,'party_type','staff','party_id',s));end if;
 lines:=lines||jsonb_build_array(jsonb_build_object('account_id',private.workforce_account_v630(t,case when method='cheque' then 'bank' else method end),'credit',v_payment_amount));
 journal:=private.v4_journal_create(t,location,day,'Staff payment: '||member.name,'staff_payment',p.id,coalesce(data->>'reference',member.staff_code),lines);
 update public.staff_payments_v630 set journal_id=journal where id=p.id;
 update public.staff_payment_allocations_v630 set journal_id=journal where payment_id=p.id and not from_advance;
 insert into public.workforce_audit_v630(tenant_id,staff_id,action,after_data) values(t,s,'payment.post',(select to_jsonb(x) from public.staff_payments_v630 x where id=p.id));
 return p.id;
end $$;

create or replace function private.staff_earning_post_v630(t uuid,s uuid,location uuid,data jsonb,cost uuid default null)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare member public.staff_members_v630%rowtype;e public.staff_earnings_v630%rowtype;p record;allocation uuid;
 gross numeric;net numeric;u numeric;r numeric;bonus numeric;deduct numeric;remaining numeric;allocated numeric;
 journal uuid;day date:=coalesce((data->>'date')::date,current_date);kind text:=coalesce(data->>'kind','payroll');req text:=data->>'request_id';
begin
 select * into member from public.staff_members_v630 where tenant_id=t and id=s for update;
 if not found or not member.active then raise exception 'Active staff member not found';end if;
 if member.location_id is not null and member.location_id<>location then raise exception 'Staff member belongs to a different location';end if;
 perform private.v4_location_access(t,location,'operate');
 if req is null or length(req)>256 then raise exception 'A stable payroll request ID is required';end if;
 select * into e from public.staff_earnings_v630 where tenant_id=t and request_id=req;
 if found then if e.staff_id<>s or e.location_id<>location or e.request_payload<>data then raise exception 'Payroll retry has different data';end if;return e.id;end if;
 u:=coalesce((data->>'units')::numeric,1);r:=coalesce((data->>'rate')::numeric,member.base_rate);
 bonus:=coalesce((data->>'allowances')::numeric,0);deduct:=coalesce((data->>'deductions')::numeric,0);
 gross:=round(u*r+bonus,2);net:=round(gross-deduct,2);
 if u<0 or r<0 or bonus<0 or deduct<0 or gross>1000000000000 or net<=0 then raise exception 'Invalid salary, units, allowance or deduction amount';end if;
 if day<member.joined_on or (member.left_on is not null and day>member.left_on) then raise exception 'Earning date is outside the staff employment period';end if;
 if kind='payroll' then
  if nullif(data->>'period_from','') is null or nullif(data->>'period_to','') is null or (data->>'period_to')::date<(data->>'period_from')::date then raise exception 'A valid payroll period is required';end if;
  if exists(select 1 from public.staff_earnings_v630 previous where previous.tenant_id=t and previous.staff_id=s and previous.kind='payroll' and previous.period_from<=(data->>'period_to')::date and previous.period_to>=(data->>'period_from')::date) then raise exception 'This staff payroll period overlaps an already posted payroll';end if;
  if member.wage_basis='per_trip' then raise exception 'Per-trip staff wages are recorded on their loads; use a bonus for additional earnings';end if;
 end if;
 insert into public.staff_earnings_v630(tenant_id,staff_id,location_id,earning_date,kind,period_from,period_to,units,rate,allowances,deductions,gross_amount,amount,load_cost_id,request_id,request_payload,notes)
 values(t,s,location,day,kind,(data->>'period_from')::date,(data->>'period_to')::date,u,r,bonus,deduct,gross,net,cost,req,data,data->>'notes') returning * into e;
 journal:=private.v4_journal_create(t,location,day,'Staff earning: '||member.name,'staff_earning',e.id,member.staff_code,
  jsonb_build_array(jsonb_build_object('account_id',private.workforce_account_v630(t,'staff_salary_v630'),'debit',net,'description',member.name),
   jsonb_build_object('account_id',private.workforce_account_v630(t,'staff_payable_v630'),'credit',net,'party_type','staff','party_id',s)));
 update public.staff_earnings_v630 set journal_id=journal where id=e.id;
 remaining:=net;
 for p in select x.id,x.advance_amount-coalesce((select sum(a.amount) from public.staff_payment_allocations_v630 a where a.payment_id=x.id and a.from_advance),0) available
  from public.staff_payments_v630 x where x.tenant_id=t and x.staff_id=s and x.location_id=location order by x.payment_date,x.created_at,x.id for update of x loop
  allocated:=least(remaining,p.available);
  if allocated>0 then
   insert into public.staff_payment_allocations_v630(payment_id,earning_id,amount,from_advance) values(p.id,e.id,allocated,true) returning id into allocation;
   journal:=private.v4_journal_create(t,location,day,'Apply staff advance: '||member.name,'staff_advance_apply',allocation,member.staff_code,
    jsonb_build_array(jsonb_build_object('account_id',private.workforce_account_v630(t,'staff_payable_v630'),'debit',allocated,'party_type','staff','party_id',s),jsonb_build_object('account_id',private.workforce_account_v630(t,'staff_advance_v630'),'credit',allocated,'party_type','staff','party_id',s)));
   update public.staff_payment_allocations_v630 set journal_id=journal where id=allocation;
   remaining:=remaining-allocated;
  end if;
  exit when remaining<=0;
 end loop;
 insert into public.workforce_audit_v630(tenant_id,staff_id,action,after_data) values(t,s,'earning.post',(select to_jsonb(x) from public.staff_earnings_v630 x where id=e.id));
 return e.id;
end $$;

create or replace function public.material_load_workspace_v630(p_tenant_id uuid,p_action text,p_data jsonb default '{}'::jsonb,p_location_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare t uuid:=p_tenant_id;load uuid:=nullif(p_data->>'load_id','')::uuid;location uuid:=p_location_id;
 l public.aggregate_loads_v617%rowtype;data jsonb:=coalesce(p_data->'load',p_data);result jsonb;prior public.material_load_requests_v630%rowtype;
 costs jsonb:=coalesce(p_data->'costs','[]'::jsonb);req text:=p_data->>'request_id';variant uuid;v_sku text;mode text;name text;
begin
 if p_action='context' then
  perform private.aggregate_yard_assert_view_v617(t);
  if location is not null then perform private.v4_location_access(t,location,'view');end if;
  return jsonb_build_object(
   'staff',coalesce((select jsonb_agg(jsonb_build_object('staff_id',s.id,'driver_id',s.driver_id,'name',s.name,'phone',s.phone,'wage_basis',s.wage_basis,'base_rate',case when private.erp_has_permission(t,'staff.view') then s.base_rate else null end,'location_id',s.location_id) order by s.name) from public.staff_members_v630 s where s.tenant_id=t and s.active and (s.location_id is null or private.erp_document_scope_allowed(t,s.location_id,location,'view')) and exists(select 1 from public.tenant_modules m where m.tenant_id=t and m.module_key='staff' and m.enabled)),'[]'::jsonb),
   'billing_services',coalesce((select jsonb_agg(jsonb_build_object('variant_id',v.id,'name',p.name,'tax_rate',p.tax_rate,'hsn_sac',g.hsn_sac,'taxability',g.taxability,'gst_rate',g.gst_rate,'validation_status',g.validation_status) order by p.name) from public.product_variants v join public.products p on p.id=v.product_id and p.tenant_id=v.tenant_id left join lateral(select * from private.gst_profile_for_variant_v520(t,v.id,current_date)) g on true where v.tenant_id=t and v.status='active' and p.status='active' and p.item_type='service'),'[]'::jsonb),
   'tax_mode',private.gst_tax_mode_resolve_v520(t,current_date),'can_manage_costs',private.erp_has_permission(t,'aggregate_yard.costs'),
   'can_create_billing_service',private.erp_has_permission(t,'inventory.manage') and private.erp_has_permission(t,'gst_compliance.manage')
  );
 elsif p_action='billing_service' then
  perform private.yard_cost_assert_v630(t,location,true);
  name:=nullif(trim(data->>'name'),'');if name is null then raise exception 'Charge service name is required';end if;
  mode:=private.gst_tax_mode_resolve_v520(t,current_date);
  if mode='unconfigured' then raise exception 'Configure the business tax mode first';end if;
  if mode='non_gst' and coalesce((data->>'gst_rate')::numeric,0)<>0 then raise exception 'Non-GST charges must have zero GST';end if;
  if mode='gst_registered' and nullif(trim(data->>'hsn_sac'),'') is null then raise exception 'Select the correct SAC for this charge service';end if;
  v_sku:='YARD-SVC-'||upper(left(coalesce(nullif(data->>'new_id',''),gen_random_uuid()::text),12));
  if exists(select 1 from public.product_variants where tenant_id=t and sku=v_sku) then raise exception 'Charge service already exists; refresh the list';end if;
  result:=public.inventory_create_product_v481(p_tenant_id=>t,p_location_id=>location,p_device_id=>nullif(data->>'device_id','')::uuid,p_name=>name,p_sku=>v_sku,p_item_type=>'service',p_description=>coalesce(data->>'description',name),p_category_name=>'Load Charges',p_brand_name=>'',p_barcode=>'',p_part_number=>'',p_cost_price=>0,p_selling_price=>0,p_list_price=>null,p_tax_rate=>coalesce((data->>'gst_rate')::numeric,0),p_reorder_level=>0,p_opening_stock=>0,p_base_unit_code=>'PCS',p_units=>'[]'::jsonb);
  variant:=(result->>'variant_id')::uuid;
  if mode='gst_registered' then perform public.gst_product_profile_save_v520(t,variant,'service',data->>'hsn_sac',coalesce(data->>'taxability','taxable'),coalesce((data->>'gst_rate')::numeric,0),0,0,false,false,'Load charge service setup',current_date);end if;
  return jsonb_build_object('variant_id',variant,'recorded',true);
 elsif p_action='report' then
  perform private.aggregate_yard_assert_view_v617(t);
  if location is not null then perform private.v4_location_access(t,location,'view');end if;
  if coalesce((data->>'to')::date,current_date)<coalesce((data->>'from')::date,date_trunc('month',current_date)::date) then raise exception 'End date must follow start date';end if;
  return jsonb_build_object('loads',coalesce((select jsonb_agg(private.load_evidence_v630(t,x.id) order by x.load_date desc,x.load_number) from public.aggregate_loads_v617 x where x.tenant_id=t and x.direction<>'direct_delivery' and x.load_date between coalesce((data->>'from')::date,date_trunc('month',current_date)::date) and coalesce((data->>'to')::date,current_date) and private.erp_document_scope_allowed(t,x.location_id,location,'view') and (nullif(data->>'vehicle_id','') is null or x.vehicle_id=(data->>'vehicle_id')::uuid) and (nullif(data->>'driver_id','') is null or x.driver_id=(data->>'driver_id')::uuid)),'[]'::jsonb));
 end if;
 if p_action='create' then
  perform private.aggregate_yard_assert_manage_v617(t);
  if req is null or length(req)>256 then raise exception 'A stable load request ID is required';end if;
  perform pg_advisory_xact_lock(hashtextextended(t::text||':load:'||req,0));
  select * into prior from public.material_load_requests_v630 where tenant_id=t and request_id=req;
  if found then if prior.payload<>p_data then raise exception 'Load retry has different data';end if;return jsonb_build_object('load_id',prior.load_id,'replayed',true);end if;
  result:=public.aggregate_load_create_v617(t,data->>'p_direction',nullif(data->>'p_location_id','')::uuid,(data->>'p_variant_id')::uuid,(data->>'p_quantity')::numeric,data->>'p_unit_code',data->>'p_measurement_method',(data->>'p_body_length_ft')::numeric,(data->>'p_body_width_ft')::numeric,(data->>'p_body_height_ft')::numeric,(data->>'p_gross_weight_kg')::numeric,(data->>'p_tare_weight_kg')::numeric,(data->>'p_net_weight_kg')::numeric,nullif(data->>'p_vehicle_id','')::uuid,nullif(data->>'p_driver_id','')::uuid,nullif(data->>'p_supplier_id','')::uuid,nullif(data->>'p_customer_id','')::uuid,data->>'p_source_name',data->>'p_destination_name',data->>'p_source_reference',data->>'p_freight_mode',(data->>'p_freight_amount')::numeric,(data->>'p_capacity_override')::boolean,data->>'p_capacity_override_reason',data->>'p_notes');
  load:=(result->>'load_id')::uuid;
  select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load;
  perform private.v4_location_access(t,l.location_id,'operate');
  if jsonb_array_length(costs)>0 then perform private.load_cost_save_v630(t,load,costs);end if;
  perform private.load_delivery_save_v630(t,load,coalesce(p_data->'delivery','{}'::jsonb)||jsonb_build_object('driver_license_snapshot',(select license_number from public.logistics_drivers_v61 where id=l.driver_id and tenant_id=t)));
  insert into public.material_load_requests_v630(tenant_id,request_id,payload,load_id) values(t,req,p_data,load);
  return result;
 end if;
 select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load for update;
 if not found then raise exception 'Load not found';end if;
 if p_action='detail' then return private.load_evidence_v630(t,load);end if;
 perform private.aggregate_yard_assert_manage_v617(t);perform private.v4_location_access(t,l.location_id,'operate');
 if p_action='edit' then
  result:=public.aggregate_load_edit_v628(t,load,data->>'p_direction',nullif(data->>'p_location_id','')::uuid,(data->>'p_variant_id')::uuid,(data->>'p_quantity')::numeric,data->>'p_unit_code',data->>'p_measurement_method',(data->>'p_body_length_ft')::numeric,(data->>'p_body_width_ft')::numeric,(data->>'p_body_height_ft')::numeric,(data->>'p_gross_weight_kg')::numeric,(data->>'p_tare_weight_kg')::numeric,(data->>'p_net_weight_kg')::numeric,nullif(data->>'p_vehicle_id','')::uuid,nullif(data->>'p_driver_id','')::uuid,nullif(data->>'p_supplier_id','')::uuid,nullif(data->>'p_customer_id','')::uuid,data->>'p_source_name',data->>'p_destination_name',data->>'p_source_reference',data->>'p_freight_mode',(data->>'p_freight_amount')::numeric,(data->>'p_capacity_override')::boolean,data->>'p_capacity_override_reason',data->>'p_notes');
  perform private.v4_location_access(t,(select location_id from public.aggregate_loads_v617 where id=load),'operate');
  if p_data ? 'costs' and private.erp_has_permission(t,'aggregate_yard.costs') then perform private.load_cost_save_v630(t,load,costs);end if;
  if p_data ? 'delivery' then perform private.load_delivery_save_v630(t,load,p_data->'delivery');end if;
 elsif p_action='confirm' then
  result:=public.aggregate_load_confirm_v628(t,load);perform private.load_costs_post_v630(t,load);
 elsif p_action='delivery' then perform private.load_delivery_save_v630(t,load,data);result:=jsonb_build_object('recorded',true);
 elsif p_action='payment' then result:=jsonb_build_object('payment_id',private.load_cost_payment_v630(t,(data->>'cost_id')::uuid,data));
 elsif p_action='add_cost' then
  perform private.load_cost_save_v630(t,load,case when p_data ? 'costs' then costs else jsonb_build_array(p_data->'cost') end,false);
  if l.status='completed' then perform private.load_costs_post_v630(t,load);end if;
  result:=jsonb_build_object('recorded',true);
 elsif p_action='cancel' then
  if l.status='completed' or l.sale_id is not null or l.purchase_id is not null then raise exception 'Only an unconfirmed load can be cancelled. Confirmed costs and linked documents retain their financial history.';end if;
  result:=public.aggregate_load_status_v617(t,load,'cancelled',coalesce(p_data->>'reason','Cancelled before confirmation'));
 elsif p_action='delete' then
  if exists(select 1 from public.material_load_costs_v630 where tenant_id=t and load_id=load) or exists(select 1 from public.material_load_delivery_v630 where tenant_id=t and load_id=load) then raise exception 'This load has saved costs or delivery records. Cancel it to retain its history instead of deleting it.';end if;
  result:=public.aggregate_load_delete_v628(t,load);
 else raise exception 'Unknown material load action';end if;
 return result;
end $$;

create or replace function public.reports_get_summary_v630(p_tenant_id uuid,p_from_date date,p_to_date date,p_location_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare result jsonb;extra numeric;extra_count bigint;owed numeric;
begin
 result:=public.reports_get_summary_v4(p_tenant_id,p_from_date,p_to_date,p_location_id);
 select coalesce(sum(jl.debit-jl.credit),0) into extra from public.journal_entries j join public.journal_lines jl on jl.journal_entry_id=j.id join public.accounting_accounts a on a.id=jl.account_id and a.tenant_id=j.tenant_id
 where j.tenant_id=p_tenant_id and j.status='posted' and j.entry_date between p_from_date and p_to_date and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view') and a.account_type='expense' and a.system_key ~ '^(staff_salary_v630|yard_.*_v630)$';
 select count(distinct j.id) into extra_count from public.journal_entries j where j.tenant_id=p_tenant_id and j.status='posted' and j.source_type in('staff_earning','load_cost') and j.entry_date between p_from_date and p_to_date and private.erp_document_scope_allowed(p_tenant_id,j.location_id,p_location_id,'view');
 select coalesce(sum(e.amount-private.staff_earning_paid_v630(e.id)),0) into owed from public.staff_earnings_v630 e where e.tenant_id=p_tenant_id and private.erp_document_scope_allowed(p_tenant_id,e.location_id,p_location_id,'view');
 select owed+coalesce(sum(c.amount-private.load_cost_paid_v630(c.id)),0) into owed from public.material_load_costs_v630 c join public.aggregate_loads_v617 l on l.id=c.load_id and l.tenant_id=c.tenant_id where c.tenant_id=p_tenant_id and c.status='posted' and c.staff_id is null and private.erp_document_scope_allowed(p_tenant_id,l.location_id,p_location_id,'view');
 return result||jsonb_build_object('staff_and_load_expenses',extra,'staff_and_load_payables',owed,'payables',coalesce((result->>'payables')::numeric,0)+owed,'expense_count',coalesce((result->>'expense_count')::bigint,0)+extra_count,'expenses',coalesce((result->>'expenses')::numeric,0)+extra,'net_profit',coalesce((result->>'net_profit')::numeric,0)-extra);
end $$;

