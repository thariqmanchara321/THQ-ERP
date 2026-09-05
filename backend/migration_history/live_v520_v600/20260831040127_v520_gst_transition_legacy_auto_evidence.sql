-- THQ ERP v5.2 GST transition safety
-- Migration 235: automatically classify finalized transactions created by the still-active v5.1 apps
-- as legacy_unverified unless they are being assembled inside the guarded v5.2 authoritative context.

create or replace function private.gst_v520_authoritative_context()
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select lower(coalesce(current_setting('thq.gst_v520_authoritative', true), 'off')) = 'on';
$$;

create or replace function private.gst_mark_legacy_source_v520(
  p_tenant_id uuid,
  p_source_type text,
  p_source_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_payload jsonb;
  v_id uuid;
  v_source_number text;
  v_document_date date;
  v_location_id uuid;
  v_taxable numeric;
  v_tax numeric;
  v_grand numeric;
begin
  if p_tenant_id is null or p_source_id is null then
    return null;
  end if;
  if private.gst_v520_authoritative_context() then
    return null;
  end if;
  if exists (select 1 from public.gst_document_snapshots_v520 s where s.tenant_id=p_tenant_id and s.source_type=p_source_type and s.source_id=p_source_id) then
    return null;
  end if;
  select m.id into v_id from public.gst_legacy_document_markers_v520 m where m.tenant_id=p_tenant_id and m.source_type=p_source_type and m.source_id=p_source_id;
  if v_id is not null then return v_id; end if;
  v_payload := private.gst_legacy_source_payload_v520(p_tenant_id,p_source_type,p_source_id);
  if v_payload is null then return null; end if;
  v_source_number := nullif(v_payload->>'number','');
  v_document_date := nullif(v_payload->>'date','')::date;
  v_location_id := nullif(v_payload->>'location_id','')::uuid;
  v_taxable := coalesce(nullif(v_payload->>'taxable_total','')::numeric,nullif(v_payload->>'subtotal','')::numeric);
  v_tax := coalesce(nullif(v_payload->>'tax_total','')::numeric,0);
  v_grand := coalesce(nullif(v_payload->>'grand_total','')::numeric,0);
  if v_source_number is null or v_document_date is null then raise exception 'Legacy GST evidence source identity is incomplete for % %',p_source_type,p_source_id; end if;
  insert into public.gst_legacy_document_markers_v520(tenant_id,source_type,source_id,source_number,document_date,location_id,legacy_taxable_total,legacy_tax_total,legacy_grand_total,source_hash)
  values(p_tenant_id,p_source_type,p_source_id,v_source_number,v_document_date,v_location_id,v_taxable,v_tax,v_grand,encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex'))
  on conflict(tenant_id,source_type,source_id) do nothing returning id into v_id;
  if v_id is null then select m.id into v_id from public.gst_legacy_document_markers_v520 m where m.tenant_id=p_tenant_id and m.source_type=p_source_type and m.source_id=p_source_id; end if;
  return v_id;
end;
$$;

create or replace function private.gst_legacy_origin_after_insert_v520()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if new.entity_type in('sale','purchase') then perform private.gst_mark_legacy_source_v520(new.tenant_id,new.entity_type,new.entity_id); end if;
  return new;
end;
$$;

create or replace function private.gst_legacy_return_after_finalize_v520()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if tg_table_name='sales_returns' and coalesce(new.grand_total,0)>0 then perform private.gst_mark_legacy_source_v520(new.tenant_id,'sales_return',new.id);
  elsif tg_table_name='purchase_returns' and coalesce(new.grand_total,0)>0 then perform private.gst_mark_legacy_source_v520(new.tenant_id,'purchase_return',new.id); end if;
  return new;
end;
$$;

create or replace function private.gst_legacy_purchase_invoice_after_post_v520()
returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if new.status not in('draft','void') and (old.status is distinct from new.status or tg_op='INSERT') then perform private.gst_mark_legacy_source_v520(new.tenant_id,'purchase_invoice_v484',new.id); end if;
  return new;
end;
$$;

drop trigger if exists trg_gst_legacy_origin_after_insert_v520 on public.document_origins;
create trigger trg_gst_legacy_origin_after_insert_v520 after insert on public.document_origins for each row when (new.entity_type in('sale','purchase')) execute function private.gst_legacy_origin_after_insert_v520();

drop trigger if exists trg_gst_legacy_sales_return_finalize_v520 on public.sales_returns;
create trigger trg_gst_legacy_sales_return_finalize_v520 after update of subtotal,tax_total,grand_total on public.sales_returns for each row when (new.grand_total>0) execute function private.gst_legacy_return_after_finalize_v520();

drop trigger if exists trg_gst_legacy_purchase_return_finalize_v520 on public.purchase_returns;
create trigger trg_gst_legacy_purchase_return_finalize_v520 after update of subtotal,tax_total,grand_total on public.purchase_returns for each row when (new.grand_total>0) execute function private.gst_legacy_return_after_finalize_v520();

drop trigger if exists trg_gst_legacy_purchase_invoice_post_v520 on public.purchase_invoices_v484;
create trigger trg_gst_legacy_purchase_invoice_post_v520 after insert or update of status on public.purchase_invoices_v484 for each row when (new.status not in('draft','void')) execute function private.gst_legacy_purchase_invoice_after_post_v520();

revoke all on function private.gst_v520_authoritative_context() from public,anon,authenticated;
revoke all on function private.gst_mark_legacy_source_v520(uuid,text,uuid) from public,anon,authenticated;
revoke all on function private.gst_legacy_origin_after_insert_v520() from public,anon,authenticated;
revoke all on function private.gst_legacy_return_after_finalize_v520() from public,anon,authenticated;
revoke all on function private.gst_legacy_purchase_invoice_after_post_v520() from public,anon,authenticated;
grant execute on function private.gst_v520_authoritative_context() to service_role;
grant execute on function private.gst_mark_legacy_source_v520(uuid,text,uuid) to service_role;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes) values(235,'5.2.0-foundation','GST Transition Legacy Auto Evidence','Automatically creates immutable legacy_unverified GST evidence for finalized v5.1 Sales/Purchases/Returns/Purchasing V2 invoices while v5.2 is under construction. Guarded authoritative context skips legacy marking for future v5.2 atomic writers.') on conflict(migration_no) do update set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;