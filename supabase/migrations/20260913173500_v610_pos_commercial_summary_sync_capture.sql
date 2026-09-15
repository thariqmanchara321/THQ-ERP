-- THQ ERP v6.1: persist POS commercial metadata after authoritative offline/online sync.
create or replace function private.pos_offline_commercial_summary_capture_v610()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_summary jsonb;
  v_discount_type text;
  v_discount_value numeric;
  v_doc_discount numeric;
  v_charge_total numeric;
  v_breakdown jsonb;
  v_order_type text;
begin
  if new.status <> 'synced' or new.sale_id is null then
    return new;
  end if;

  v_summary := coalesce(new.payload_snapshot->'commercial_summary','{}'::jsonb);
  if jsonb_typeof(v_summary) <> 'object' or v_summary = '{}'::jsonb then
    return new;
  end if;

  v_discount_type := lower(trim(coalesce(v_summary->>'discount_type','none')));
  if v_discount_type not in ('none','fixed','percent') then
    raise exception 'Invalid commercial discount type in offline POS payload';
  end if;

  v_discount_value := greatest(coalesce(nullif(v_summary->>'discount_value','')::numeric,0),0);
  v_doc_discount := greatest(coalesce(nullif(v_summary->>'document_discount_total','')::numeric,0),0);
  v_charge_total := greatest(coalesce(nullif(v_summary->>'classified_charge_total','')::numeric,0),0);
  v_breakdown := coalesce(v_summary->'charge_breakdown','[]'::jsonb);
  if jsonb_typeof(v_breakdown) <> 'array' then
    raise exception 'Commercial charge breakdown must be an array';
  end if;

  v_order_type := lower(trim(coalesce(
    v_summary->>'order_type',
    new.payload_snapshot->>'order_type',
    'sale'
  )));

  insert into public.sale_commercial_summary_v610(
    tenant_id,sale_id,source_type,source_id,order_type,
    discount_type,discount_value,document_discount_total,
    classified_charge_total,charge_breakdown
  ) values (
    new.tenant_id,new.sale_id,'sale',null,v_order_type,
    v_discount_type,v_discount_value,v_doc_discount,
    v_charge_total,v_breakdown
  )
  on conflict(tenant_id,sale_id) do update set
    source_type=excluded.source_type,
    source_id=excluded.source_id,
    order_type=excluded.order_type,
    discount_type=excluded.discount_type,
    discount_value=excluded.discount_value,
    document_discount_total=excluded.document_discount_total,
    classified_charge_total=excluded.classified_charge_total,
    charge_breakdown=excluded.charge_breakdown;

  return new;
end;
$$;

drop trigger if exists trg_pos_offline_commercial_summary_capture_v610
  on public.pos_offline_sync_v486;

create trigger trg_pos_offline_commercial_summary_capture_v610
after insert or update of status,sale_id on public.pos_offline_sync_v486
for each row
execute function private.pos_offline_commercial_summary_capture_v610();
