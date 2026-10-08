-- Validate the confirmed customer before preparing or posting load costs.
CREATE OR REPLACE FUNCTION public.aggregate_load_sale_create_v630(p_tenant_id uuid, p_load_id uuid, p_customer_id uuid, p_sale_date date, p_due_date date, p_items jsonb, p_payment_allocations jsonb, p_notes text, p_location_id uuid, p_device_id uuid, p_request_id text, p_supply_type text, p_place_of_supply_code text, p_charge_selections jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare l public.aggregate_loads_v617%rowtype;result jsonb;items jsonb;id uuid;
begin
 l:=private.aggregate_load_document_lock_v629(p_tenant_id,p_load_id,'outbound',p_location_id);
 if l.customer_id is not null and l.customer_id is distinct from p_customer_id then raise exception 'Select the customer recorded on the confirmed Load Ticket';end if;
 perform private.load_costs_post_v630(p_tenant_id,p_load_id);
 items:=private.load_sale_items_v630(p_tenant_id,p_load_id,p_items,p_sale_date);
 result:=private.aggregate_load_sale_core_v630(p_tenant_id,p_load_id,p_customer_id,p_sale_date,p_due_date,items,p_payment_allocations,p_notes,p_location_id,p_device_id,p_request_id,p_supply_type,p_place_of_supply_code,p_charge_selections);
 id:=(result->>'sale_id')::uuid;
 insert into public.material_load_sale_snapshots_v630(sale_id,tenant_id,load_id,evidence)
 values(id,p_tenant_id,p_load_id,private.load_evidence_v630(p_tenant_id,p_load_id)||jsonb_build_object('invoice_items_entered',p_items,'invoice_terms_entered',jsonb_build_object('customer_id',p_customer_id,'sale_date',p_sale_date,'due_date',p_due_date,'notes',p_notes,'supply_type',p_supply_type,'place_of_supply_code',p_place_of_supply_code,'payment_allocations',p_payment_allocations,'charge_selections',p_charge_selections),'snapshot_at',now()))
 on conflict(sale_id) do nothing;
 return result||jsonb_build_object('load_costs_recorded',true);
end $function$;
