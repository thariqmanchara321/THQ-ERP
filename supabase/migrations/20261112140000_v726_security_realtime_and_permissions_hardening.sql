-- Migration: 20261112140000_v726_security_realtime_and_permissions_hardening.sql
-- THQ ERP — Phase 13 Hardening: Realtime Authorization, Permissions & Cost Protection

-- 1. Realtime Topic Authorization for Private Channels
CREATE OR REPLACE FUNCTION private.erp_realtime_topic_authorized(p_topic text)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_raw_tenant text;
  v_tenant_id uuid;
  v_hex text;
BEGIN
  -- Unauthenticated connections cannot read or write to private channels
  IF v_uid IS NULL THEN
    RETURN false;
  END IF;

  -- Platform super-administrators have universal authorized access
  IF EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'erp_user_is_platform_admin'
  ) THEN
    IF private.erp_user_is_platform_admin(v_uid) THEN
      RETURN true;
    END IF;
  END IF;

  -- Inspect channel topic formats:
  -- Pattern A: Wireless scanner topic 'thq_scan_<tenant_32hex_or_uuid>_<session_id>'
  IF p_topic LIKE 'thq_scan_%' THEN
    -- Try matching 32 hex character tenant string without dashes
    v_hex := substring(p_topic FROM '^thq_scan_([0-9a-fA-F]{32})_');
    IF v_hex IS NOT NULL THEN
      BEGIN
        v_tenant_id := (
          substr(v_hex, 1, 8) || '-' ||
          substr(v_hex, 9, 4) || '-' ||
          substr(v_hex, 13, 4) || '-' ||
          substr(v_hex, 17, 4) || '-' ||
          substr(v_hex, 21, 12)
        )::uuid;
      EXCEPTION WHEN OTHERS THEN
        v_tenant_id := NULL;
      END;
    ELSE
      -- Try matching standard UUID with dashes
      v_raw_tenant := substring(p_topic FROM '^thq_scan_([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})_');
      IF v_raw_tenant IS NOT NULL THEN
        BEGIN
          v_tenant_id := v_raw_tenant::uuid;
        EXCEPTION WHEN OTHERS THEN
          v_tenant_id := NULL;
        END;
      END IF;
    END IF;

  -- Pattern B: General tenant broadcast 'thq_tenant_<uuid>%'
  ELSIF p_topic LIKE 'thq_tenant_%' THEN
    v_raw_tenant := substring(p_topic FROM '^thq_tenant_([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})');
    IF v_raw_tenant IS NOT NULL THEN
      BEGIN
        v_tenant_id := v_raw_tenant::uuid;
      EXCEPTION WHEN OTHERS THEN
        v_tenant_id := NULL;
      END;
    END IF;

  -- Pattern C: POS terminal broadcast 'thq_pos_<uuid>%'
  ELSIF p_topic LIKE 'thq_pos_%' THEN
    v_raw_tenant := substring(p_topic FROM '^thq_pos_([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})');
    IF v_raw_tenant IS NOT NULL THEN
      BEGIN
        v_tenant_id := v_raw_tenant::uuid;
      EXCEPTION WHEN OTHERS THEN
        v_tenant_id := NULL;
      END;
    END IF;
  END IF;

  -- Enforce active tenant membership
  IF v_tenant_id IS NOT NULL THEN
    RETURN private.erp_user_has_tenant_access(v_tenant_id);
  END IF;

  -- Default deny for unknown topic schemas
  RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION private.erp_realtime_topic_authorized(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.erp_realtime_topic_authorized(text) TO authenticated, service_role;

-- 2. Enable and Apply RLS on realtime.messages
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'realtime' AND table_name = 'messages'
  ) THEN
    ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS "realtime_messages_read_tenant_members" ON realtime.messages;
    CREATE POLICY "realtime_messages_read_tenant_members"
    ON realtime.messages FOR SELECT TO authenticated
    USING (private.erp_realtime_topic_authorized(topic));

    DROP POLICY IF EXISTS "realtime_messages_write_tenant_members" ON realtime.messages;
    CREATE POLICY "realtime_messages_write_tenant_members"
    ON realtime.messages FOR INSERT TO authenticated
    WITH CHECK (private.erp_realtime_topic_authorized(topic));
  END IF;
END $$;

-- 3. Hardened inventory_get_product_detail with Server-Side Cost Masking
CREATE OR REPLACE FUNCTION public.inventory_get_product_detail(
  p_tenant_id uuid,
  p_variant_id uuid
)
RETURNS TABLE(
  product_id uuid,
  variant_id uuid,
  product_name text,
  description text,
  item_type text,
  category_name text,
  brand_name text,
  unit_name text,
  unit_code text,
  sku text,
  barcode text,
  part_number text,
  cost_price numeric,
  selling_price numeric,
  list_price numeric,
  tax_rate numeric,
  reorder_level numeric,
  stock_quantity numeric,
  product_status text,
  variant_status text,
  created_at timestamp with time zone,
  updated_at timestamp with time zone
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $$
DECLARE
  v_can_view_cost boolean;
BEGIN
  IF NOT (
    private.has_permission(p_tenant_id, 'inventory.view')
    OR private.has_permission(p_tenant_id, 'inventory.manage')
  ) THEN
    RAISE EXCEPTION 'Access denied' USING errcode = '42501';
  END IF;

  v_can_view_cost := private.erp_user_is_owner(p_tenant_id)
    OR private.erp_has_permission(p_tenant_id, 'inventory.view_cost')
    OR private.erp_has_permission(p_tenant_id, 'inventory.manage');

  RETURN QUERY
  SELECT
    p.id,
    pv.id,
    p.name,
    p.description,
    p.item_type,
    pc.name,
    pb.name,
    iu.name,
    iu.code,
    pv.sku,
    pv.barcode,
    pv.part_number,
    CASE WHEN v_can_view_cost THEN pv.cost_price ELSE NULL END AS cost_price,
    pv.selling_price,
    pv.list_price,
    p.tax_rate,
    pv.reorder_level,
    COALESCE(SUM(sb.quantity), 0)::numeric,
    p.status,
    pv.status,
    p.created_at,
    GREATEST(p.updated_at, pv.updated_at)
  FROM public.products p
  JOIN public.product_variants pv
    ON pv.product_id = p.id
   AND pv.tenant_id = p.tenant_id
  LEFT JOIN public.product_categories pc
    ON pc.id = p.category_id
   AND pc.tenant_id = p.tenant_id
  LEFT JOIN public.product_brands pb
    ON pb.id = p.brand_id
   AND pb.tenant_id = p.tenant_id
  LEFT JOIN public.inventory_units iu
    ON iu.id = p.base_unit_id
   AND iu.tenant_id = p.tenant_id
  LEFT JOIN public.stock_balances sb
    ON sb.variant_id = pv.id
   AND sb.tenant_id = p.tenant_id
  WHERE p.tenant_id = p_tenant_id
    AND pv.id = p_variant_id
  GROUP BY
    p.id,
    pv.id,
    pc.name,
    pb.name,
    iu.name,
    iu.code;
END;
$$;

REVOKE ALL ON FUNCTION public.inventory_get_product_detail(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.inventory_get_product_detail(uuid, uuid) TO authenticated, service_role;

-- 4. Hardened pos_offline_product_cache_v486 with Cost Masking for Unauthorized Roles
CREATE OR REPLACE FUNCTION public.pos_offline_product_cache_v486(
  p_tenant_id uuid,
  p_device_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $$
DECLARE
  v_location uuid;
  v jsonb;
  v_can_view_cost boolean;
BEGIN
  v_location := private.v486_pos_device_location(p_tenant_id, p_device_id, null);
  v_can_view_cost := private.erp_user_is_owner(p_tenant_id)
    OR private.erp_has_permission(p_tenant_id, 'inventory.view_cost')
    OR private.erp_has_permission(p_tenant_id, 'inventory.manage');

  SELECT COALESCE(
    jsonb_agg(
      (
        CASE
          WHEN v_can_view_cost THEN x
          ELSE (x - 'cost_price' - 'purchase_cost') || jsonb_build_object('cost_price', null, 'purchase_cost', null)
        END
      ) || jsonb_build_object(
        'stock_quantity',
        CASE
          WHEN x->>'item_type' = 'stock' THEN GREATEST(
            COALESCE(lb.quantity, 0) - COALESCE(lb.reserved_quantity, 0) - COALESCE(lb.damaged_quantity, 0) - COALESCE(lb.quarantine_quantity, 0),
            0
          )
          ELSE COALESCE(NULLIF(x->>'stock_quantity', '')::numeric, 0)
        END,
        'offline_available_quantity',
        CASE
          WHEN x->>'item_type' = 'stock' THEN GREATEST(
            COALESCE(lb.quantity, 0) - COALESCE(lb.reserved_quantity, 0) - COALESCE(lb.damaged_quantity, 0) - COALESCE(lb.quarantine_quantity, 0),
            0
          )
          ELSE COALESCE(NULLIF(x->>'stock_quantity', '')::numeric, 0)
        END,
        'gst_profile',
        jsonb_strip_nulls(
          jsonb_build_object(
            'profile_id', gp.id,
            'supply_kind', gp.supply_kind,
            'hsn_sac', gp.hsn_sac,
            'taxability', gp.taxability,
            'gst_rate', COALESCE(gp.gst_rate, prod.tax_rate, 0),
            'cess_rate', COALESCE(gp.cess_rate, 0),
            'cess_per_unit', COALESCE(gp.cess_per_unit, 0),
            'tax_inclusive', COALESCE(gp.tax_inclusive, false),
            'reverse_charge', COALESCE(gp.reverse_charge, false),
            'validation_status', COALESCE(gp.validation_status, 'legacy_fallback'),
            'effective_from', gp.effective_from
          )
        )
      )
      ORDER BY x->>'product_name', x->>'sku'
    ),
    '[]'::jsonb
  ) INTO v
  FROM public.inventory_list_products_v483(p_tenant_id, v_location) AS t(x)
  LEFT JOIN public.location_stock_balances lb
    ON lb.tenant_id = p_tenant_id
   AND lb.location_id = v_location
   AND lb.variant_id = NULLIF(x->>'variant_id', '')::uuid
  LEFT JOIN public.location_product_settings lps
    ON lps.tenant_id = p_tenant_id
   AND lps.location_id = v_location
   AND lps.variant_id = NULLIF(x->>'variant_id', '')::uuid
  LEFT JOIN public.product_variants pv
    ON pv.id = NULLIF(x->>'variant_id', '')::uuid
   AND pv.tenant_id = p_tenant_id
  LEFT JOIN public.products prod
    ON prod.id = pv.product_id
   AND prod.tenant_id = pv.tenant_id
  LEFT JOIN LATERAL (
    SELECT g.*
    FROM public.gst_product_tax_profiles_v520 g
    WHERE g.tenant_id = p_tenant_id
      AND g.variant_id = pv.id
      AND g.active
      AND g.effective_from <= CURRENT_DATE
      AND (g.effective_to IS NULL OR g.effective_to >= CURRENT_DATE)
    ORDER BY g.effective_from DESC
    LIMIT 1
  ) gp ON true
  WHERE x->>'product_status' = 'active'
    AND x->>'variant_status' = 'active'
    AND COALESCE(lps.active, true);

  RETURN COALESCE(v, '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.pos_offline_product_cache_v486(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pos_offline_product_cache_v486(uuid, uuid) TO authenticated, service_role;
