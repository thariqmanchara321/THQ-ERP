-- =====================================================================
-- THQ ERP v6.0 FRESH-INSTALL BOOTSTRAP COMPLETION
--
-- Completes objects intentionally outside the public/private baseline:
--   * refresh permissions for pre-existing system roles
--   * restore auth.users -> public.handle_new_user profile hook
--   * create THQ asset storage bucket
--   * restore THQ asset storage RLS policies
--
-- No transaction-writer changes.
-- No GST fallback changes.
-- No destructive business-data changes.
-- =====================================================================

CREATE OR REPLACE FUNCTION private.seed_default_roles(
    target_tenant_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    r record;
    v_role_id uuid;
BEGIN
    FOR r IN
        SELECT *
        FROM (
            VALUES
                ('owner'::text,       'Owner'::text),
                ('manager',           'Manager'),
                ('cashier',           'Cashier'),
                ('salesperson',       'Salesperson'),
                ('store_keeper',      'Store Keeper'),
                ('accountant',        'Accountant')
        ) AS v(role_key, role_name)
    LOOP
        INSERT INTO public.roles (
            tenant_id,
            key,
            name,
            is_system
        )
        VALUES (
            target_tenant_id,
            r.role_key,
            r.role_name,
            true
        )
        ON CONFLICT (tenant_id, key)
        DO NOTHING;

        -- Important v6 fresh-install fix:
        -- the role may already exist because another tenant bootstrap
        -- trigger created it before the normal role seeder ran.
        SELECT id
        INTO v_role_id
        FROM public.roles
        WHERE tenant_id = target_tenant_id
          AND key = r.role_key;

        IF v_role_id IS NULL THEN
            RAISE EXCEPTION
                'Default role % could not be resolved for tenant %',
                r.role_key,
                target_tenant_id;
        END IF;

        -- Always refresh the canonical default permission set,
        -- even when the system role already existed.
        PERFORM private.grant_default_role_permissions(
            target_tenant_id,
            v_role_id,
            r.role_key
        );
    END LOOP;
END
$function$;


-- =====================================================================
-- AUTH PROFILE HOOK
-- =====================================================================

DROP TRIGGER IF EXISTS on_auth_user_created
ON auth.users;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();


-- =====================================================================
-- THQ ASSET STORAGE
-- =====================================================================

INSERT INTO storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
VALUES (
    'thq-assets',
    'thq-assets',
    true,
    5242880,
    ARRAY[
        'image/png',
        'image/jpeg'
    ]::text[]
)
ON CONFLICT (id)
DO NOTHING;


DROP POLICY IF EXISTS thq_assets_read_v495
ON storage.objects;

CREATE POLICY thq_assets_read_v495
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'thq-assets'
    AND public.thq_asset_path_allowed_v495(name)
);


DROP POLICY IF EXISTS thq_assets_insert_v495
ON storage.objects;

CREATE POLICY thq_assets_insert_v495
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'thq-assets'
    AND public.thq_asset_path_allowed_v495(name)
);


DROP POLICY IF EXISTS thq_assets_update_v495
ON storage.objects;

CREATE POLICY thq_assets_update_v495
ON storage.objects
FOR UPDATE
TO authenticated
USING (
    bucket_id = 'thq-assets'
    AND public.thq_asset_path_allowed_v495(name)
)
WITH CHECK (
    bucket_id = 'thq-assets'
    AND public.thq_asset_path_allowed_v495(name)
);


DROP POLICY IF EXISTS thq_assets_delete_v495
ON storage.objects;

CREATE POLICY thq_assets_delete_v495
ON storage.objects
FOR DELETE
TO authenticated
USING (
    bucket_id = 'thq-assets'
    AND public.thq_asset_path_allowed_v495(name)
);


-- =====================================================================
-- FAIL-CLOSED INSTALL ASSERTIONS
-- =====================================================================

DO $thq$
DECLARE
    v_def text;
    v_policy_count integer;
BEGIN
    SELECT pg_get_functiondef(
        'private.seed_default_roles(uuid)'::regprocedure
    )
    INTO v_def;

    IF position(
        'grant_default_role_permissions'
        IN v_def
    ) = 0
    OR position(
        'SELECT id'
        IN v_def
    ) = 0 THEN
        RAISE EXCEPTION
            'THQ fresh-install role bootstrap fix is missing';
    END IF;


    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger t
        JOIN pg_class c
          ON c.oid = t.tgrelid
        JOIN pg_namespace n
          ON n.oid = c.relnamespace
        JOIN pg_proc p
          ON p.oid = t.tgfoid
        JOIN pg_namespace fn
          ON fn.oid = p.pronamespace
        WHERE NOT t.tgisinternal
          AND n.nspname = 'auth'
          AND c.relname = 'users'
          AND t.tgname = 'on_auth_user_created'
          AND fn.nspname = 'public'
          AND p.proname = 'handle_new_user'
    ) THEN
        RAISE EXCEPTION
            'THQ auth user profile trigger is missing';
    END IF;


    IF NOT EXISTS (
        SELECT 1
        FROM storage.buckets
        WHERE id = 'thq-assets'
    ) THEN
        RAISE EXCEPTION
            'THQ asset storage bucket is missing';
    END IF;


    SELECT count(*)
    INTO v_policy_count
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname IN (
          'thq_assets_read_v495',
          'thq_assets_insert_v495',
          'thq_assets_update_v495',
          'thq_assets_delete_v495'
      );

    IF v_policy_count <> 4 THEN
        RAISE EXCEPTION
            'THQ asset storage policies are incomplete';
    END IF;
END
$thq$;
