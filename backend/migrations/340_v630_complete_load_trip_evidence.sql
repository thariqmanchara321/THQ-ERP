-- Preserve default driver contacts and include the complete physical load/trip event record.

create or replace function private.load_delivery_save_v630(t uuid,load uuid,data jsonb)
returns void language plpgsql security definer set search_path=public,private,pg_temp as $$
declare l public.aggregate_loads_v617%rowtype;old jsonb;start_meter numeric;end_meter numeric;depart timestamptz;arrive timestamptz;latitude numeric;longitude numeric;
begin
 select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load for update;
 if not found then raise exception 'Load not found';end if;
 perform private.aggregate_yard_assert_manage_v617(t);perform private.v4_location_access(t,l.location_id,'operate');
 select details into old from public.material_load_delivery_v630 where tenant_id=t and load_id=load;
 if old is null then
  select jsonb_build_object('driver_contact_name',d.name,'driver_contact_phone',d.phone,'driver_license_snapshot',d.license_number) into old from public.logistics_drivers_v61 d where d.tenant_id=t and d.id=l.driver_id;
  data:=coalesce(old,'{}'::jsonb)||jsonb_strip_nulls(data-'load_id');
 else data:=old||(data-'load_id');end if;
 if jsonb_typeof(data)<>'object' or octet_length(data::text)>64000 then raise exception 'Invalid delivery details';end if;
 latitude:=nullif(data->>'delivery_latitude','')::numeric;longitude:=nullif(data->>'delivery_longitude','')::numeric;
 if (latitude is null)<>(longitude is null) or latitude not between -90 and 90 or longitude not between -180 and 180 then raise exception 'Enter both valid delivery latitude and longitude, or leave both blank';end if;
 start_meter:=nullif(data->>'odometer_start','')::numeric;end_meter:=nullif(data->>'odometer_end','')::numeric;
 depart:=nullif(data->>'dispatch_at','')::timestamptz;arrive:=nullif(data->>'delivered_at','')::timestamptz;
 if start_meter<0 or end_meter<0 or end_meter<start_meter or start_meter>1000000000 or end_meter>1000000000 then raise exception 'Check the start and end odometer readings';end if;
 if arrive<depart then raise exception 'Delivery time must follow departure';end if;
 insert into public.material_load_delivery_v630(load_id,tenant_id,details) values(load,t,coalesce(old,'{}'::jsonb)||data)
 on conflict(load_id) do update set details=excluded.details,updated_by=auth.uid(),updated_at=now();
 insert into public.workforce_audit_v630(tenant_id,load_id,action,before_data,after_data) values(t,load,'delivery.save',old,coalesce(old,'{}'::jsonb)||data);
end $$;

create or replace function private.load_evidence_v630(t uuid,load uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare l public.aggregate_loads_v617%rowtype;result jsonb;
begin
 select * into l from public.aggregate_loads_v617 where tenant_id=t and id=load;
 if not found then raise exception 'Load not found';end if;
 perform private.yard_cost_assert_v630(t,l.location_id,false);
 result:=public.aggregate_load_detail_v629(t,load);
 return result||jsonb_build_object(
  'load_record',to_jsonb(l),
  'trip',coalesce((select to_jsonb(h) from public.transport_trip_hub_v611 h where h.tenant_id=t and h.material_load_id=load),'{}'::jsonb),
  'driver_current',coalesce((select to_jsonb(d) from public.logistics_drivers_v61 d where d.tenant_id=t and d.id=l.driver_id),'{}'::jsonb),
  'vehicle_current',coalesce((select to_jsonb(v)||jsonb_build_object('yard_profile',(select to_jsonb(p) from public.aggregate_vehicle_profiles_v617 p where p.tenant_id=t and p.vehicle_id=v.id)) from public.service_vehicles v where v.tenant_id=t and v.id=l.vehicle_id),'{}'::jsonb),
  'load_events',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at,e.id) from public.aggregate_load_events_v617 e where e.tenant_id=t and e.load_id=load),'[]'::jsonb),
  'location_name',(select name from public.business_locations where tenant_id=t and id=l.location_id),
  'legacy_freight_payments',coalesce((select jsonb_agg(to_jsonb(f) order by f.settled_at) from public.aggregate_freight_settlements_v620 f where f.tenant_id=t and f.load_id=load),'[]'::jsonb),
  'sale',coalesce((select to_jsonb(s) from public.sales s where s.tenant_id=t and s.id=l.sale_id),'{}'::jsonb),
  'customer_payments',coalesce((select jsonb_agg(to_jsonb(p)) from public.sale_payments p where p.tenant_id=t and p.sale_id=l.sale_id),'[]'::jsonb),
  'delivery',coalesce((select details from public.material_load_delivery_v630 where tenant_id=t and load_id=load),'{}'::jsonb),
  'costs',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('paid_amount',coalesce(private.load_cost_paid_v630(c.id),0),'outstanding',case when c.staff_mode='salary_allocation' or c.status<>'posted' then 0 else c.amount-coalesce(private.load_cost_paid_v630(c.id),0) end,'billing_service',(select p.name from public.product_variants v join public.products p on p.id=v.product_id and p.tenant_id=v.tenant_id where v.id=c.billing_variant_id and v.tenant_id=t)) order by c.created_at,c.id) from public.material_load_costs_v630 c where c.tenant_id=t and c.load_id=load),'[]'::jsonb),
  'cost_payments',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('cost_description',c.description,'payee',c.payee) order by p.payment_date,p.created_at) from public.material_load_cost_payments_v630 p join public.material_load_costs_v630 c on c.id=p.cost_id and c.tenant_id=p.tenant_id where c.tenant_id=t and c.load_id=load),'[]'::jsonb),
  'staff_payments',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'payment_date',p.payment_date,'amount',a.amount,'payment_method',p.payment_method,'reference',p.reference,'payee',p.payee_snapshot,'cost_id',c.id,'cost_description',c.description,'from_advance',a.from_advance,'journal_id',a.journal_id,'notes',p.notes) order by p.payment_date,p.created_at) from public.material_load_costs_v630 c join public.staff_payment_allocations_v630 a on a.earning_id=c.staff_earning_id join public.staff_payments_v630 p on p.id=a.payment_id and p.tenant_id=c.tenant_id where c.tenant_id=t and c.load_id=load),'[]'::jsonb),
  'cost_total',coalesce((select sum(amount) from public.material_load_costs_v630 where tenant_id=t and load_id=load and status<>'void'),0),
  'customer_charge_total',coalesce((select sum(bill_amount) from public.material_load_costs_v630 where tenant_id=t and load_id=load and status<>'void'),0),
  'history',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at) from public.workforce_audit_v630 a where a.tenant_id=t and a.load_id=load),'[]'::jsonb)
 );
end $$;
