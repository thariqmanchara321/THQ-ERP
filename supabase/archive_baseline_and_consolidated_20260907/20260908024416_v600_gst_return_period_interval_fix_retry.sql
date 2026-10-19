CREATE OR REPLACE FUNCTION public.gst_return_period_ensure_v600(
  p_tenant_id uuid,
  p_registration_id uuid,
  p_period_start date,
  p_frequency text DEFAULT 'monthly'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_frequency text:=lower(trim(coalesce(p_frequency,'monthly')));
  v_start date;
  v_end date;
  v_id uuid;
begin
  if not private.gst_v520_has_access(p_tenant_id,'gst_compliance.returns') then
    raise exception 'GST returns permission required';
  end if;

  if not exists(
    select 1
    from public.gst_registrations_v520 r
    where r.id=p_registration_id
      and r.tenant_id=p_tenant_id
      and r.active
  ) then
    raise exception 'GST registration not found';
  end if;

  if v_frequency not in('monthly','quarterly') then
    raise exception 'Return frequency must be monthly or quarterly';
  end if;

  v_start:=date_trunc('month',p_period_start)::date;
  v_end:=case
    when v_frequency='monthly'
      then (v_start + interval '1 month' - interval '1 day')::date
    else (v_start + interval '3 months' - interval '1 day')::date
  end;

  insert into public.gst_return_periods_v600(
    tenant_id,registration_id,period_start,period_end,frequency,created_by
  )
  values(
    p_tenant_id,p_registration_id,v_start,v_end,v_frequency,auth.uid()
  )
  on conflict(tenant_id,registration_id,period_start,period_end)
  do update set updated_at=public.gst_return_periods_v600.updated_at
  returning id into v_id;

  return (
    select to_jsonb(x)
    from public.gst_return_periods_v600 x
    where x.id=v_id
  );
end
$function$;

REVOKE ALL ON FUNCTION public.gst_return_period_ensure_v600(uuid,uuid,date,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gst_return_period_ensure_v600(uuid,uuid,date,text) TO authenticated, service_role;