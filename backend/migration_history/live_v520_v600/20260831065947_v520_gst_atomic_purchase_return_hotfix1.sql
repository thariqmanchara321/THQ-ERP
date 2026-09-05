create or replace function private.v4_purchase_return_accounting_trigger()
returns trigger
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
begin
  if private.gst_v520_authoritative_context_for_source(new.tenant_id,'purchase_return',new.id) then
    return new;
  end if;
  if coalesce(new.grand_total,0)>0 and (tg_op='INSERT' or coalesce(old.grand_total,0)<>coalesce(new.grand_total,0)) then
    perform private.v4_post_purchase_return(new.id);
  end if;
  return new;
end
$function$;
