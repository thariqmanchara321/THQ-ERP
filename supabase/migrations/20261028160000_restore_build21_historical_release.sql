-- ============================================================================
-- THQ ERP — Safe Idempotent Historical Restoration of Build 21 (Non-Mutating)
-- Migration: 20261028160000_restore_build21_historical_release.sql
--
-- Objective:
--   1. Protect active releases via partial unique index:
--      (app_key, platform, version) WHERE status IN ('published', 'stable', 'beta')
--   2. Protect modern artifact builds via partial unique index:
--      (app_key, platform, build_number) WHERE download_url IS NOT NULL
--   3. Safely drop restrictive global constraint:
--      platform_app_releases_app_key_platform_version_key
--   4. Non-mutating restoration of Build 21 historical audit record:
--      - ID: 193b806e-2789-4b71-b467-d9b542537221
--      - Status: 'withdrawn' (non-discoverable, non-downloadable)
--      - Fail-closed if ID exists with differing metadata (NO upsert/update)
--      - Safe idempotent no-op if identical row already exists
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. PRE-FLIGHT VALIDATION
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_active_collisions integer;
BEGIN
  -- Verify table exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'platform_app_releases'
  ) THEN
    RAISE EXCEPTION 'Pre-flight check failed: Table public.platform_app_releases does not exist.';
  END IF;

  -- Assert no duplicate active releases exist
  SELECT count(*) INTO v_active_collisions
  FROM (
    SELECT app_key, platform, version
    FROM public.platform_app_releases
    WHERE status IN ('published', 'stable', 'beta')
    GROUP BY app_key, platform, version
    HAVING count(*) > 1
  ) c;

  IF v_active_collisions > 0 THEN
    RAISE EXCEPTION 'Pre-flight check failed: Found % duplicate active versions in platform_app_releases. Resolve collisions before applying index.', v_active_collisions;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 2. CREATE REPLACEMENT PARTIAL UNIQUE INDEXES
-- ----------------------------------------------------------------------------

-- A. Active version uniqueness (enforces semver uniqueness among active distributions)
CREATE UNIQUE INDEX IF NOT EXISTS platform_app_releases_active_version_key
  ON public.platform_app_releases (app_key, platform, version)
  WHERE status IN ('published', 'stable', 'beta');

-- B. Artifact build uniqueness (enforces monotonic build uniqueness for modern binaries)
CREATE UNIQUE INDEX IF NOT EXISTS platform_app_releases_artifact_build_key
  ON public.platform_app_releases (app_key, platform, build_number)
  WHERE download_url IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 3. DROP OLD RESTRICTIVE GLOBAL CONSTRAINT
-- Safe now that active-version unique index is verified and active.
-- ----------------------------------------------------------------------------
ALTER TABLE public.platform_app_releases
  DROP CONSTRAINT IF EXISTS platform_app_releases_app_key_platform_version_key;

-- ----------------------------------------------------------------------------
-- 4. NON-MUTATING RESTORATION OF HISTORICAL BUILD 21
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_existing record;
  v_distinct_cols text[] := '{}';
  v_expected_id uuid := '193b806e-2789-4b71-b467-d9b542537221'::uuid;
  v_expected_app_key text := 'client';
  v_expected_platform text := 'windows';
  v_expected_version text := '8.2.3';
  v_expected_build_number integer := 21;
  v_expected_status text := 'withdrawn';
  v_expected_minimum_supported boolean := false;
  v_expected_mandatory boolean := false;
  v_expected_release_notes text := 'THQ ERP v8.2.3 (Build 21) automated release. Historical release superseded by build 22.';
  v_expected_download_url text := 'installers/THQ-Business-v8.2.3-build21-windows-x64.exe';
  v_expected_released_at timestamptz := '2026-10-27 11:13:03+00'::timestamptz;
  v_expected_channel text := 'stable';
  v_expected_package_size_bytes bigint := 17316008;
  v_expected_sha256_checksum text := 'd8f5090fe49f268b724c6ef76cd7df7c029b21f8579264a24e9ed610c902f851';
  v_expected_publisher_signature text := 'CN=THQ ERP Internal QA Test - CLIENT-BC8AEE, O=THQ Systems, OU=QA Release Engineering';
  v_expected_min_supported_version text := '5.1.0';
  v_expected_rollout_percentage integer := 100;
  v_expected_created_by uuid := null;
  v_expected_target_type text := 'device';
  v_expected_target_tenant_ids uuid[] := array['a659b6de-885d-44ed-9fa7-93eefa7d47d2']::uuid[];
  v_expected_target_store_ids uuid[] := null;
  v_expected_target_device_ids uuid[] := array['bc8aeec1-9bce-4935-b349-168caf9a7fa4']::uuid[];
BEGIN
  -- A. Check if Build 21 record already exists under the designated ID
  SELECT * INTO v_existing FROM public.platform_app_releases WHERE id = v_expected_id;

  IF FOUND THEN
    -- Check all deterministic identity fields using NULL-safe IS DISTINCT FROM
    IF v_existing.app_key IS DISTINCT FROM v_expected_app_key THEN v_distinct_cols := array_append(v_distinct_cols, 'app_key'); END IF;
    IF v_existing.platform IS DISTINCT FROM v_expected_platform THEN v_distinct_cols := array_append(v_distinct_cols, 'platform'); END IF;
    IF v_existing.version IS DISTINCT FROM v_expected_version THEN v_distinct_cols := array_append(v_distinct_cols, 'version'); END IF;
    IF v_existing.build_number IS DISTINCT FROM v_expected_build_number THEN v_distinct_cols := array_append(v_distinct_cols, 'build_number'); END IF;
    IF v_existing.status IS DISTINCT FROM v_expected_status THEN v_distinct_cols := array_append(v_distinct_cols, 'status'); END IF;
    IF v_existing.minimum_supported IS DISTINCT FROM v_expected_minimum_supported THEN v_distinct_cols := array_append(v_distinct_cols, 'minimum_supported'); END IF;
    IF v_existing.mandatory IS DISTINCT FROM v_expected_mandatory THEN v_distinct_cols := array_append(v_distinct_cols, 'mandatory'); END IF;
    IF v_existing.release_notes IS DISTINCT FROM v_expected_release_notes THEN v_distinct_cols := array_append(v_distinct_cols, 'release_notes'); END IF;
    IF v_existing.download_url IS DISTINCT FROM v_expected_download_url THEN v_distinct_cols := array_append(v_distinct_cols, 'download_url'); END IF;
    IF v_existing.released_at IS DISTINCT FROM v_expected_released_at THEN v_distinct_cols := array_append(v_distinct_cols, 'released_at'); END IF;
    IF v_existing.channel IS DISTINCT FROM v_expected_channel THEN v_distinct_cols := array_append(v_distinct_cols, 'channel'); END IF;
    IF v_existing.package_size_bytes IS DISTINCT FROM v_expected_package_size_bytes THEN v_distinct_cols := array_append(v_distinct_cols, 'package_size_bytes'); END IF;
    IF v_existing.sha256_checksum IS DISTINCT FROM v_expected_sha256_checksum THEN v_distinct_cols := array_append(v_distinct_cols, 'sha256_checksum'); END IF;
    IF v_existing.publisher_signature IS DISTINCT FROM v_expected_publisher_signature THEN v_distinct_cols := array_append(v_distinct_cols, 'publisher_signature'); END IF;
    IF v_existing.min_supported_version IS DISTINCT FROM v_expected_min_supported_version THEN v_distinct_cols := array_append(v_distinct_cols, 'min_supported_version'); END IF;
    IF v_existing.rollout_percentage IS DISTINCT FROM v_expected_rollout_percentage THEN v_distinct_cols := array_append(v_distinct_cols, 'rollout_percentage'); END IF;
    IF v_existing.created_by IS DISTINCT FROM v_expected_created_by THEN v_distinct_cols := array_append(v_distinct_cols, 'created_by'); END IF;
    IF v_existing.target_type IS DISTINCT FROM v_expected_target_type THEN v_distinct_cols := array_append(v_distinct_cols, 'target_type'); END IF;
    IF v_existing.target_tenant_ids IS DISTINCT FROM v_expected_target_tenant_ids THEN v_distinct_cols := array_append(v_distinct_cols, 'target_tenant_ids'); END IF;
    IF v_existing.target_store_ids IS DISTINCT FROM v_expected_target_store_ids THEN v_distinct_cols := array_append(v_distinct_cols, 'target_store_ids'); END IF;
    IF v_existing.target_device_ids IS DISTINCT FROM v_expected_target_device_ids THEN v_distinct_cols := array_append(v_distinct_cols, 'target_device_ids'); END IF;

    IF array_length(v_distinct_cols, 1) > 0 THEN
      RAISE EXCEPTION 'Historical Build 21 record % already exists but differs in fields: %! Migration aborted fail-closed without mutating existing record.',
        v_expected_id, array_to_string(v_distinct_cols, ', ');
    ELSE
      RAISE NOTICE 'Historical Build 21 record % is already restored with identical metadata. No changes made.', v_expected_id;
      RETURN;
    END IF;
  END IF;

  -- B. Check for index conflict with existing artifact-bearing records
  PERFORM 1 FROM public.platform_app_releases
  WHERE app_key = v_expected_app_key
    AND platform = v_expected_platform
    AND build_number = v_expected_build_number
    AND download_url IS NOT NULL;

  IF FOUND THEN
    RAISE EXCEPTION 'Artifact build conflict: A record for app_key=%, platform=%, build_number=% with non-null download_url already exists under a different ID! Migration aborted.',
      v_expected_app_key, v_expected_platform, v_expected_build_number;
  END IF;

  -- C. Perform non-mutating atomic INSERT
  INSERT INTO public.platform_app_releases (
    id, app_key, platform, version, build_number, status,
    minimum_supported, mandatory, release_notes, download_url, released_at,
    channel, package_size_bytes, sha256_checksum, publisher_signature,
    min_supported_version, rollout_percentage, created_by, updated_at,
    target_type, target_tenant_ids, target_store_ids, target_device_ids
  ) VALUES (
    v_expected_id, v_expected_app_key, v_expected_platform, v_expected_version, v_expected_build_number, v_expected_status,
    v_expected_minimum_supported, v_expected_mandatory, v_expected_release_notes, v_expected_download_url, v_expected_released_at,
    v_expected_channel, v_expected_package_size_bytes, v_expected_sha256_checksum, v_expected_publisher_signature,
    v_expected_min_supported_version, v_expected_rollout_percentage, v_expected_created_by, now(),
    v_expected_target_type, v_expected_target_tenant_ids, v_expected_target_store_ids, v_expected_target_device_ids
  );

  RAISE NOTICE 'SUCCESS: Restored Build 21 historical audit record % (status: withdrawn).', v_expected_id;
END $$;

-- ----------------------------------------------------------------------------
-- 5. POST-INSERT INTEGRITY ASSERTION
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_rec record;
BEGIN
  SELECT * INTO v_rec FROM public.platform_app_releases WHERE id = '193b806e-2789-4b71-b467-d9b542537221';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post-insert verification failed: Build 21 record was not found.';
  END IF;
  IF v_rec.status IS DISTINCT FROM 'withdrawn' THEN
    RAISE EXCEPTION 'Post-insert verification failed: Build 21 status is %, expected withdrawn.', v_rec.status;
  END IF;
  IF v_rec.build_number IS DISTINCT FROM 21 THEN
    RAISE EXCEPTION 'Post-insert verification failed: Build 21 build_number is %, expected 21.', v_rec.build_number;
  END IF;
END $$;

COMMIT;
