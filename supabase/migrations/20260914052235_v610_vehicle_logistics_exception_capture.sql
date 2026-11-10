create or replace function private.v610_logistics_exception_capture()
returns trigger
language plpgsql
set search_path to 'public','private','pg_temp'
as $$
declare
  r public.transport_logistics_receipts%rowtype;
begin
  select * into r from public.transport_logistics_receipts where id=new.receipt_id and tenant_id=new.tenant_id;
  if not found then return new; end if;
  if coalesce(new.damaged_quantity,0)>0 then
    insert into public.transport_logistics_exceptions(tenant_id,trip_id,receipt_id,receipt_line_id,stock_transfer_id,variant_id,exception_type,quantity,status,opened_by,updated_by)
    values(new.tenant_id,r.trip_id,r.id,new.id,r.stock_transfer_id,new.variant_id,'damaged',new.damaged_quantity,'open',auth.uid(),auth.uid())
    on conflict (receipt_line_id,exception_type) do nothing;
  end if;
  if coalesce(new.missing_quantity,0)>0 then
    insert into public.transport_logistics_exceptions(tenant_id,trip_id,receipt_id,receipt_line_id,stock_transfer_id,variant_id,exception_type,quantity,status,opened_by,updated_by)
    values(new.tenant_id,r.trip_id,r.id,new.id,r.stock_transfer_id,new.variant_id,'missing',new.missing_quantity,'open',auth.uid(),auth.uid())
    on conflict (receipt_line_id,exception_type) do nothing;
  end if;
  return new;
end
$$;
revoke all on function private.v610_logistics_exception_capture() from public, anon, authenticated;
drop trigger if exists transport_logistics_receipt_line_exception_capture on public.transport_logistics_receipt_lines;
create trigger transport_logistics_receipt_line_exception_capture after insert on public.transport_logistics_receipt_lines for each row execute function private.v610_logistics_exception_capture();

insert into public.transport_logistics_exceptions(tenant_id,trip_id,receipt_id,receipt_line_id,stock_transfer_id,variant_id,exception_type,quantity,status,opened_at,opened_by,updated_at,updated_by)
select l.tenant_id,r.trip_id,r.id,l.id,r.stock_transfer_id,l.variant_id,'damaged',l.damaged_quantity,'open',coalesce(r.received_at,r.created_at),null,coalesce(r.received_at,r.created_at),null
from public.transport_logistics_receipt_lines l
join public.transport_logistics_receipts r on r.id=l.receipt_id and r.tenant_id=l.tenant_id
where l.damaged_quantity>0
on conflict (receipt_line_id,exception_type) do nothing;

insert into public.transport_logistics_exceptions(tenant_id,trip_id,receipt_id,receipt_line_id,stock_transfer_id,variant_id,exception_type,quantity,status,opened_at,opened_by,updated_at,updated_by)
select l.tenant_id,r.trip_id,r.id,l.id,r.stock_transfer_id,l.variant_id,'missing',l.missing_quantity,'open',coalesce(r.received_at,r.created_at),null,coalesce(r.received_at,r.created_at),null
from public.transport_logistics_receipt_lines l
join public.transport_logistics_receipts r on r.id=l.receipt_id and r.tenant_id=l.tenant_id
where l.missing_quantity>0
on conflict (receipt_line_id,exception_type) do nothing;;
