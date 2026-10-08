-- Read-only Staff statement. Payroll, payment, load and GST writers are unchanged.
create or replace function public.staff_statement_v634(p_tenant_id uuid,p_staff_id uuid,p_from date,p_to date,p_location_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare result jsonb; workspace jsonb; member public.staff_members_v630%rowtype;
begin
 perform private.staff_assert_v630(p_tenant_id,'staff.view',p_location_id);
 if p_from is null or p_to is null or p_to<p_from then raise exception 'Select a valid statement period';end if;
 select * into member from public.staff_members_v630 where tenant_id=p_tenant_id and id=p_staff_id;
 if not found then raise exception 'Staff member not found';end if;
 if member.location_id is not null and not private.erp_document_scope_allowed(p_tenant_id,member.location_id,p_location_id,'view') then raise exception 'Staff member is outside the selected store scope' using errcode='42501';end if;
 workspace:=public.staff_workspace_v630(p_tenant_id,'detail',jsonb_build_object('staff_id',p_staff_id,'from',p_from,'to',p_to),p_location_id);
 with events as (
  select e.id,e.location_id,e.earning_date as date,e.created_at,'earning'::text as event_type,
   case e.kind when 'payroll' then 'Salary / wages' when 'bonus' then 'Bonus' else 'Load wage' end as description,
   coalesce(l.load_number,j.entry_number,'') as document_reference,e.amount as earning,0::numeric as payment,e.notes,
   coalesce(b.name,'') as location_name,''::text as payment_method,''::text as payment_reference
  from public.staff_earnings_v630 e
  left join public.material_load_costs_v630 c on c.id=e.load_cost_id and c.tenant_id=e.tenant_id
  left join public.aggregate_loads_v617 l on l.id=c.load_id and l.tenant_id=e.tenant_id
  left join public.journal_entries j on j.id=e.journal_id and j.tenant_id=e.tenant_id
  left join public.business_locations b on b.id=e.location_id and b.tenant_id=e.tenant_id
  where e.tenant_id=p_tenant_id and e.staff_id=p_staff_id and e.earning_date<=p_to and private.erp_document_scope_allowed(p_tenant_id,e.location_id,p_location_id,'view')
  union all
  select p.id,p.location_id,p.payment_date,p.created_at,'payment','Payment / advance',coalesce(j.entry_number,''),0,p.amount,p.notes,
   coalesce(b.name,''),p.payment_method,coalesce(p.reference,'')
  from public.staff_payments_v630 p
  left join public.journal_entries j on j.id=p.journal_id and j.tenant_id=p.tenant_id
  left join public.business_locations b on b.id=p.location_id and b.tenant_id=p.tenant_id
  where p.tenant_id=p_tenant_id and p.staff_id=p_staff_id and p.payment_date<=p_to and private.erp_document_scope_allowed(p_tenant_id,p.location_id,p_location_id,'view')
 ), running as (
  select *,sum(earning-payment) over(order by date,created_at,event_type,id rows between unbounded preceding and current row) as balance from events
 ), stores as (
  select location_id,max(location_name) as location_name,
   coalesce(sum(earning-payment) filter(where date<p_from),0) as opening_balance,
   sum(earning-payment) as closing_balance from events group by location_id
 )
 select jsonb_build_object(
  'complete',true,'profile',workspace->'staff'->0,'period',jsonb_build_object('from',p_from,'to',p_to),
  'summary',jsonb_build_object(
   'opening_balance',coalesce((select sum(earning-payment) from events where date<p_from),0),
   'period_earnings',coalesce((select sum(earning) from events where date>=p_from),0),
   'period_payments',coalesce((select sum(payment) from events where date>=p_from),0),
   'closing_balance',coalesce((select sum(earning-payment) from events),0),
   'closing_due',coalesce((select sum(greatest(closing_balance,0)) from stores),0),
   'closing_advance',coalesce((select sum(greatest(-closing_balance,0)) from stores),0),
   'current_due',workspace->'staff'->0->'outstanding','current_advance',workspace->'staff'->0->'advance_balance'),
  'ledger',coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('staff_code',member.staff_code) order by date,created_at,event_type,id) from running r where date>=p_from),'[]'),
  'balances_by_location',coalesce((select jsonb_agg(to_jsonb(s) order by location_name,location_id) from stores s),'[]'),
  'load_allocations',workspace->'load_allocations','history',workspace->'history'
 ) into result;
 result:=result||jsonb_build_object(
  'earnings',coalesce((select jsonb_agg(to_jsonb(e)||jsonb_build_object(
   'staff_code',member.staff_code,'staff_name',member.name,'location_name',b.name,'load_number',l.load_number,'entry_number',j.entry_number,
   'paid_through_end',coalesce((select sum(a.amount) from public.staff_payment_allocations_v630 a
    join public.staff_payments_v630 p on p.id=a.payment_id and p.tenant_id=e.tenant_id
    left join public.journal_entries aj on aj.id=a.journal_id and aj.tenant_id=e.tenant_id
    where a.earning_id=e.id and case when a.from_advance then coalesce(aj.entry_date,e.earning_date) else p.payment_date end<=p_to),0)
  ) order by e.earning_date,e.created_at,e.id)
  from public.staff_earnings_v630 e
  left join public.business_locations b on b.id=e.location_id and b.tenant_id=e.tenant_id
  left join public.material_load_costs_v630 c on c.id=e.load_cost_id and c.tenant_id=e.tenant_id
  left join public.aggregate_loads_v617 l on l.id=c.load_id and l.tenant_id=e.tenant_id
  left join public.journal_entries j on j.id=e.journal_id and j.tenant_id=e.tenant_id
  where e.tenant_id=p_tenant_id and e.staff_id=p_staff_id and e.earning_date between p_from and p_to and private.erp_document_scope_allowed(p_tenant_id,e.location_id,p_location_id,'view')),'[]'),
  'payments',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object(
   'staff_code',member.staff_code,'staff_name',member.name,'location_name',b.name,'entry_number',j.entry_number,
   'advance_remaining_through_end',p.advance_amount-coalesce((select sum(a.amount) from public.staff_payment_allocations_v630 a
    join public.staff_earnings_v630 e on e.id=a.earning_id and e.tenant_id=p.tenant_id
    left join public.journal_entries aj on aj.id=a.journal_id and aj.tenant_id=p.tenant_id
    where a.payment_id=p.id and a.from_advance and coalesce(aj.entry_date,e.earning_date)<=p_to),0),
   'allocations',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('earning_date',e.earning_date,'earning_type',e.kind,'entry_number',ej.entry_number,'staff_code',member.staff_code) order by e.earning_date,a.id)
    from public.staff_payment_allocations_v630 a join public.staff_earnings_v630 e on e.id=a.earning_id and e.tenant_id=p.tenant_id
    left join public.journal_entries aj on aj.id=a.journal_id and aj.tenant_id=p.tenant_id
    left join public.journal_entries ej on ej.id=e.journal_id and ej.tenant_id=p.tenant_id
    where a.payment_id=p.id and case when a.from_advance then coalesce(aj.entry_date,e.earning_date) else p.payment_date end<=p_to),'[]')
  ) order by p.payment_date,p.created_at,p.id)
  from public.staff_payments_v630 p
  left join public.business_locations b on b.id=p.location_id and b.tenant_id=p.tenant_id
  left join public.journal_entries j on j.id=p.journal_id and j.tenant_id=p.tenant_id
  where p.tenant_id=p_tenant_id and p.staff_id=p_staff_id and p.payment_date between p_from and p_to and private.erp_document_scope_allowed(p_tenant_id,p.location_id,p_location_id,'view')),'[]')
 );
 return result;
end $$;
revoke all on function public.staff_statement_v634(uuid,uuid,date,date,uuid) from public,anon;
grant execute on function public.staff_statement_v634(uuid,uuid,date,date,uuid) to authenticated;
