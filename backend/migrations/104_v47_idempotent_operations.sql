-- THQ ERP V4.7 — retry-safe wrappers for other mutating core operations.
begin;

create or replace function public.expenses_create_v47(
  p_tenant_id uuid,p_category_id uuid,p_expense_date date,p_payee text,p_description text,p_amount numeric,p_tax_amount numeric,
  p_payment_method text,p_reference_number text,p_notes text,p_location_id uuid,p_device_id uuid,p_request_id text
) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin
  v:=private.v47_request_existing(p_tenant_id,p_request_id,'expense.create');if v is not null then return v;end if;
  v:=public.expenses_create_v32(p_tenant_id,p_category_id,p_expense_date,p_payee,p_description,p_amount,p_tax_amount,p_payment_method,p_reference_number,p_notes,p_location_id,p_device_id);
  return private.v47_request_complete(p_tenant_id,p_request_id,'expense.create',v);
end$$;
grant execute on function public.expenses_create_v47(uuid,uuid,date,text,text,numeric,numeric,text,text,text,uuid,uuid,text) to authenticated;

create or replace function public.sales_add_payment_v47(p_tenant_id uuid,p_sale_id uuid,p_amount numeric,p_payment_method text,p_reference_number text,p_notes text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'sale.payment');if v is not null then return v;end if;v:=public.sales_add_payment_v32(p_tenant_id,p_sale_id,p_amount,p_payment_method,p_reference_number,p_notes);return private.v47_request_complete(p_tenant_id,p_request_id,'sale.payment',v);end$$;
grant execute on function public.sales_add_payment_v47(uuid,uuid,numeric,text,text,text,text) to authenticated;

create or replace function public.purchases_add_payment_v47(p_tenant_id uuid,p_purchase_id uuid,p_amount numeric,p_payment_method text,p_reference_number text,p_notes text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'purchase.payment');if v is not null then return v;end if;v:=public.purchases_add_payment_v32(p_tenant_id,p_purchase_id,p_amount,p_payment_method,p_reference_number,p_notes);return private.v47_request_complete(p_tenant_id,p_request_id,'purchase.payment',v);end$$;
grant execute on function public.purchases_add_payment_v47(uuid,uuid,numeric,text,text,text,text) to authenticated;

create or replace function public.sales_return_create_v47(p_tenant_id uuid,p_sale_id uuid,p_items jsonb,p_reason text,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'sale.return');if v is not null then return v;end if;v:=public.sales_return_create_v4(p_tenant_id,p_sale_id,p_items,p_reason,p_device_id);return private.v47_request_complete(p_tenant_id,p_request_id,'sale.return',v);end$$;
grant execute on function public.sales_return_create_v47(uuid,uuid,jsonb,text,uuid,text) to authenticated;

create or replace function public.purchase_return_create_v47(p_tenant_id uuid,p_purchase_id uuid,p_items jsonb,p_reason text,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'purchase.return');if v is not null then return v;end if;v:=public.purchase_return_create_v4(p_tenant_id,p_purchase_id,p_items,p_reason,p_device_id);return private.v47_request_complete(p_tenant_id,p_request_id,'purchase.return',v);end$$;
grant execute on function public.purchase_return_create_v47(uuid,uuid,jsonb,text,uuid,text) to authenticated;

create or replace function public.inventory_adjust_stock_v47(p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_variant_id uuid,p_quantity_delta numeric,p_note text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'inventory.adjust');if v is not null then return v;end if;v:=public.inventory_adjust_stock_v4(p_tenant_id,p_location_id,p_device_id,p_variant_id,p_quantity_delta,p_note);return private.v47_request_complete(p_tenant_id,p_request_id,'inventory.adjust',v);end$$;
grant execute on function public.inventory_adjust_stock_v47(uuid,uuid,uuid,uuid,numeric,text,text) to authenticated;

create or replace function public.inventory_transfer_create_v47(p_tenant_id uuid,p_from_location_id uuid,p_to_location_id uuid,p_items jsonb,p_notes text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'inventory.transfer');if v is not null then return v;end if;v:=public.inventory_transfer_create_v4(p_tenant_id,p_from_location_id,p_to_location_id,p_items,p_notes);return private.v47_request_complete(p_tenant_id,p_request_id,'inventory.transfer',v);end$$;
grant execute on function public.inventory_transfer_create_v47(uuid,uuid,uuid,jsonb,text,text) to authenticated;

create or replace function public.cashier_shift_open_v47(p_tenant_id uuid,p_location_id uuid,p_device_id uuid,p_opening_cash numeric,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'shift.open');if v is not null then return v;end if;v:=public.cashier_shift_open_v4(p_tenant_id,p_location_id,p_device_id,p_opening_cash);return private.v47_request_complete(p_tenant_id,p_request_id,'shift.open',v);end$$;
grant execute on function public.cashier_shift_open_v47(uuid,uuid,uuid,numeric,text) to authenticated;

create or replace function public.cashier_shift_close_v47(p_tenant_id uuid,p_shift_id uuid,p_declared_cash numeric,p_note text,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'shift.close');if v is not null then return v;end if;v:=public.cashier_shift_close_v4(p_tenant_id,p_shift_id,p_declared_cash,p_note);return private.v47_request_complete(p_tenant_id,p_request_id,'shift.close',v);end$$;
grant execute on function public.cashier_shift_close_v47(uuid,uuid,numeric,text,text) to authenticated;


create or replace function public.sales_void_v47(p_tenant_id uuid,p_sale_id uuid,p_reason text,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'sale.void');if v is not null then return v;end if;perform public.sales_void_v4(p_tenant_id,p_sale_id,p_reason,p_device_id);v:=jsonb_build_object('success',true,'sale_id',p_sale_id);return private.v47_request_complete(p_tenant_id,p_request_id,'sale.void',v);end$$;
grant execute on function public.sales_void_v47(uuid,uuid,text,uuid,text) to authenticated;

create or replace function public.purchase_void_v47(p_tenant_id uuid,p_purchase_id uuid,p_reason text,p_device_id uuid,p_request_id text)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin v:=private.v47_request_existing(p_tenant_id,p_request_id,'purchase.void');if v is not null then return v;end if;perform public.purchase_void_v4(p_tenant_id,p_purchase_id,p_reason,p_device_id);v:=jsonb_build_object('success',true,'purchase_id',p_purchase_id);return private.v47_request_complete(p_tenant_id,p_request_id,'purchase.void',v);end$$;
grant execute on function public.purchase_void_v47(uuid,uuid,text,uuid,text) to authenticated;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(104,'4.7.0','Foundation Lock & Production Stabilization','Retry-safe wrappers for expenses, payments, returns, stock adjustments/transfers and shift open/close.')
on conflict(migration_no) do update set notes=excluded.notes;
commit;
select 'THQ ERP V4.7 migration 104 idempotent operations ready' as status;
