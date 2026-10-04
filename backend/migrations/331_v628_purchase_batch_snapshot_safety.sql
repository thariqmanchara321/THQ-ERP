begin;
-- Capture new receipt quality/rates independently of editable batch masters.
CREATE OR REPLACE FUNCTION private.v483_apply_purchase_trace(p_tenant_id uuid, p_purchase_id uuid, p_supplier_id uuid, p_location_id uuid, p_items jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  x jsonb;
  v_mode text;
  v_variant uuid;
  v_qty numeric;
  v_item_id uuid;
  v_serials jsonb;
  v_batches jsonb;
  v_count numeric;
  v_sum numeric;
  s jsonb;
  v_serial text;
  b jsonb;
  v_batch text;
  v_bqty numeric;
  v_mfg date;
  v_exp date;
  v_batch_id uuid;
  v_serial_id uuid;
  v_ref text;
  v_require boolean;
  v_seen_serials text[];
  v_seen_batches text[];
  v_quality text;
  v_purchase_cost numeric;
  v_selling_price numeric;
  v_batch_value numeric;
begin
  if exists(
    select 1
    from public.inventory_trace_events_v483
    where tenant_id=p_tenant_id
      and purchase_id=p_purchase_id
  ) then
    return;
  end if;

  select purchase_number
  into v_ref
  from public.purchases
  where tenant_id=p_tenant_id
    and id=p_purchase_id;

  for x in
    select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb))
  loop
    v_variant:=(x->>'variant_id')::uuid;
    v_mode:=private.v483_tracking_mode(p_tenant_id,v_variant);
    if v_mode='none' then
      continue;
    end if;

    v_seen_serials:='{}'::text[];
    v_seen_batches:='{}'::text[];
    v_qty:=coalesce(nullif(x->>'quantity','')::numeric,0);

    select id
    into v_item_id
    from public.purchase_items
    where purchase_id=p_purchase_id
      and variant_id=v_variant
    limit 1;

    if v_item_id is null then
      raise exception 'Purchase line not found for tracked product';
    end if;

    if v_mode='serial' then
      if v_qty<>trunc(v_qty) then
        raise exception
          'Serial-tracked product % requires whole base units',v_variant;
      end if;

      v_serials:=coalesce(x->'serial_numbers','[]'::jsonb);
      select count(*)::numeric
      into v_count
      from jsonb_array_elements(v_serials);

      if v_count<>v_qty then
        raise exception
          'Provide exactly % serial numbers for tracked purchase line',v_qty;
      end if;

      for s in select value from jsonb_array_elements(v_serials)
      loop
        v_serial:=trim(coalesce(
          case when jsonb_typeof(s)='string'
               then s#>>'{}'
               else s->>'serial_number'
          end,''
        ));

        if v_serial='' then
          raise exception 'Serial number cannot be blank';
        end if;

        if lower(v_serial)=any(v_seen_serials) then
          raise exception 'Duplicate serial number % on tracked purchase line',
            v_serial;
        end if;

        v_seen_serials:=array_append(v_seen_serials,lower(v_serial));

        insert into public.inventory_serials_v483(
          tenant_id,variant_id,serial_number,status,current_location_id,
          supplier_id,purchase_id,purchase_item_id,received_at,created_by
        )
        values(
          p_tenant_id,v_variant,v_serial,'in_stock',p_location_id,
          p_supplier_id,p_purchase_id,v_item_id,now(),auth.uid()
        )
        returning id into v_serial_id;

        insert into public.inventory_trace_events_v483(
          tenant_id,variant_id,serial_id,event_type,quantity,location_id,
          supplier_id,purchase_id,purchase_item_id,reference_number,
          source_key,created_by
        )
        values(
          p_tenant_id,v_variant,v_serial_id,'purchase',1,p_location_id,
          p_supplier_id,p_purchase_id,v_item_id,v_ref,
          'purchase:'||p_purchase_id::text||':serial:'||v_serial_id::text,
          auth.uid()
        );
      end loop;
    else
      v_batches:=coalesce(x->'batches','[]'::jsonb);

      select coalesce(
        sum(coalesce(nullif(value->>'quantity','')::numeric,0)),0
      )
      into v_sum
      from jsonb_array_elements(v_batches);

      if abs(v_sum-v_qty)>0.000001 then
        raise exception
          'Batch quantities must total base quantity %; received %',v_qty,v_sum;
      end if;

      select coalesce(sum(
        (value->>'quantity')::numeric * coalesce(
          nullif(value->>'purchase_cost_base','')::numeric,
          nullif(x->>'unit_cost','')::numeric
        )
      ),0) into v_batch_value from jsonb_array_elements(v_batches);
      if abs(v_batch_value-v_qty*coalesce(nullif(x->>'unit_cost','')::numeric,0))
          >greatest(v_qty*0.0001,0.0001) then
        raise exception 'Batch purchase costs must match the weighted invoice cost';
      end if;

      select require_batch_expiry
      into v_require
      from public.product_tracking_policies_v483
      where tenant_id=p_tenant_id
        and variant_id=v_variant;

      for b in select value from jsonb_array_elements(v_batches)
      loop
        v_batch:=trim(coalesce(b->>'batch_number',''));
        v_bqty:=coalesce(nullif(b->>'quantity','')::numeric,0);
        v_mfg:=nullif(b->>'manufactured_on','')::date;
        v_exp:=nullif(b->>'expiry_on','')::date;
        v_quality:=nullif(trim(coalesce(b->>'quality_label','')),'');
        v_purchase_cost:=coalesce(
          nullif(b->>'purchase_cost_base','')::numeric,
          nullif(x->>'unit_cost','')::numeric
        );
        v_selling_price:=nullif(b->>'selling_price_base','')::numeric;

        if v_batch='' or v_bqty<=0 then
          raise exception
            'Each batch requires a batch number and positive quantity';
        end if;
        if lower(v_batch)=any(v_seen_batches) then
          raise exception 'Duplicate batch % on tracked purchase line',v_batch;
        end if;
        v_seen_batches:=array_append(v_seen_batches,lower(v_batch));

        if coalesce(v_require,false) and v_exp is null then
          raise exception 'Expiry date is required for batch %',v_batch;
        end if;
        if v_purchase_cost is not null and v_purchase_cost<0 then
          raise exception 'Batch purchase cost cannot be negative';
        end if;
        if v_selling_price is not null and v_selling_price<0 then
          raise exception 'Batch selling rate cannot be negative';
        end if;

        insert into public.inventory_batches_v483(
          tenant_id,variant_id,batch_number,manufactured_on,expiry_on,
          supplier_id,first_purchase_id,first_purchase_item_id,
          quality_label,purchase_cost_base,selling_price_base,created_by
        )
        values(
          p_tenant_id,v_variant,v_batch,v_mfg,v_exp,
          p_supplier_id,p_purchase_id,v_item_id,
          v_quality,v_purchase_cost,v_selling_price,auth.uid()
        )
        on conflict(tenant_id,variant_id,lower(trim(batch_number)))
        do update set
          manufactured_on=coalesce(
            public.inventory_batches_v483.manufactured_on,
            excluded.manufactured_on
          ),
          expiry_on=coalesce(
            public.inventory_batches_v483.expiry_on,
            excluded.expiry_on
          ),
          supplier_id=coalesce(
            public.inventory_batches_v483.supplier_id,
            excluded.supplier_id
          ),
          quality_label=coalesce(
            public.inventory_batches_v483.quality_label,
            excluded.quality_label
          ),
          purchase_cost_base=coalesce(
            public.inventory_batches_v483.purchase_cost_base,
            excluded.purchase_cost_base
          ),
          selling_price_base=coalesce(
            excluded.selling_price_base,
            public.inventory_batches_v483.selling_price_base
          ),
          status='active',
          updated_at=now()
        returning id into v_batch_id;

        if exists(
          select 1
          from public.inventory_batches_v483
          where id=v_batch_id
            and (
              (
                manufactured_on is not null
                and v_mfg is not null
                and manufactured_on<>v_mfg
              )
              or (
                expiry_on is not null
                and v_exp is not null
                and expiry_on<>v_exp
              )
            )
        ) then
          raise exception
            'Batch % already exists with different manufacture/expiry dates',
            v_batch;
        end if;

        insert into public.inventory_batch_balances_v483(
          tenant_id,batch_id,location_id,quantity
        )
        values(p_tenant_id,v_batch_id,p_location_id,v_bqty)
        on conflict(tenant_id,batch_id,location_id)
        do update set
          quantity=public.inventory_batch_balances_v483.quantity
                   +excluded.quantity,
          updated_at=now();

        insert into public.inventory_trace_events_v483(
          tenant_id,variant_id,batch_id,event_type,quantity,location_id,
          supplier_id,purchase_id,purchase_item_id,reference_number,
          source_key,metadata,created_by
        )
        values(
          p_tenant_id,v_variant,v_batch_id,'purchase',v_bqty,p_location_id,
          p_supplier_id,p_purchase_id,v_item_id,v_ref,
          'purchase:'||p_purchase_id::text||':item:'||v_item_id::text||
            ':batch:'||v_batch_id::text,
          jsonb_build_object(
            'batch_number',v_batch,
            'quality_label',v_quality,
            'purchase_cost_base',v_purchase_cost,
            'selling_price_base',v_selling_price
          ),
          auth.uid()
        );
      end loop;
    end if;
  end loop;
end
$function$;
revoke all on function private.v483_apply_purchase_trace(uuid,uuid,uuid,uuid,jsonb)
  from public,anon,authenticated;
insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(331,'6.2.8-purchase-batch-snapshot-safety','Purchase Batch Snapshot Safety',
  'Captures quality and cost/rate metadata on new receipt trace events; rejects batch costs inconsistent with the invoice line; leaves historical receipts and invoices unchanged.')
on conflict(migration_no) do update set schema_version=excluded.schema_version,
  release_name=excluded.release_name,notes=excluded.notes;
commit;
