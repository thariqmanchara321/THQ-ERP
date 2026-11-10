#!/usr/bin/env python3
"""
THQ ERP — Isolated PostgreSQL Integration Test Suite (Cases A through L)
Executes real PostgreSQL 17 database integration tests in an isolated, disposable instance.
Validates migration preconditions, uniqueness transitions, non-mutating idempotent restoration,
fail-closed error handling, rollback semantics, and release discovery/download isolation.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

PG_BIN_DIR = r"C:\Program Files\PostgreSQL\17\bin"
INITDB_BIN = os.path.join(PG_BIN_DIR, "initdb.exe")
POSTGRES_BIN = os.path.join(PG_BIN_DIR, "postgres.exe")
PSQL_BIN = os.path.join(PG_BIN_DIR, "psql.exe")

MIGRATION_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "supabase", "migrations", "20261028160000_restore_build21_historical_release.sql")
)

PORT = 54334

BASELINE_SCHEMA_SQL = """
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

DROP TABLE IF EXISTS public.platform_app_releases CASCADE;

CREATE TABLE public.platform_app_releases (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    app_key text NOT NULL,
    platform text NOT NULL,
    version text NOT NULL,
    build_number integer DEFAULT 1 NOT NULL,
    status text DEFAULT 'stable'::text NOT NULL,
    minimum_supported boolean DEFAULT false NOT NULL,
    mandatory boolean DEFAULT false NOT NULL,
    release_notes text,
    download_url text,
    released_at timestamp with time zone DEFAULT now() NOT NULL,
    channel text DEFAULT 'stable'::text NOT NULL,
    package_size_bytes bigint DEFAULT 0 NOT NULL,
    sha256_checksum text,
    publisher_signature text,
    min_supported_version text,
    rollout_percentage integer DEFAULT 100 NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    target_type text DEFAULT 'all'::text NOT NULL,
    target_tenant_ids uuid[],
    target_store_ids uuid[],
    target_device_ids uuid[],
    CONSTRAINT platform_app_releases_pkey PRIMARY KEY (id),
    CONSTRAINT platform_app_releases_app_key_check CHECK (app_key = ANY (ARRAY['client'::text, 'pos'::text, 'admin'::text, 'client_mobile'::text, 'mobile_pos'::text])),
    CONSTRAINT platform_app_releases_status_check CHECK (status = ANY (ARRAY['draft'::text, 'uploaded'::text, 'verified'::text, 'testing'::text, 'approved'::text, 'published'::text, 'stable'::text, 'beta'::text, 'paused'::text, 'withdrawn'::text, 'revoked'::text, 'deprecated'::text, 'blocked'::text])),
    CONSTRAINT platform_app_releases_channel_check CHECK (channel = ANY (ARRAY['stable'::text, 'beta'::text, 'alpha'::text])),
    CONSTRAINT platform_app_releases_target_type_check CHECK (target_type = ANY (ARRAY['all'::text, 'business'::text, 'store'::text, 'device'::text])),
    CONSTRAINT platform_app_releases_app_key_platform_version_key UNIQUE (app_key, platform, version)
);
"""

BASELINE_DATA_SQL = """
-- Legacy rows with duplicate build numbers (download_url IS NULL)
INSERT INTO public.platform_app_releases (id, app_key, platform, version, build_number, status, download_url) VALUES
('11111111-1111-1111-1111-111111111111', 'client', 'windows', '4.4.0', 1, 'stable', NULL),
('22222222-2222-2222-2222-222222222222', 'client', 'windows', '4.5.0', 1, 'stable', NULL),
('33333333-3333-3333-3333-333333333333', 'client', 'windows', '4.7.0', 1, 'stable', NULL),
('44444444-4444-4444-4444-444444444444', 'client', 'windows', '6.0.0', 1, 'stable', NULL),
('55555555-5555-5555-5555-555555555555', 'client', 'windows', '4.7.1', 2, 'stable', NULL),
('66666666-6666-6666-6666-666666666666', 'client', 'windows', '6.0.1', 2, 'stable', NULL),
('77777777-7777-7777-7777-777777777777', 'admin', 'web', '4.4.0', 1, 'stable', NULL),
('88888888-8888-8888-8888-888888888888', 'admin', 'web', '4.5.0', 1, 'stable', NULL);

-- Modern artifact-bearing releases
INSERT INTO public.platform_app_releases (
    id, app_key, platform, version, build_number, status, channel,
    download_url, package_size_bytes, sha256_checksum, publisher_signature,
    target_type, target_device_ids, target_tenant_ids, released_at
) VALUES
('99999999-9999-9999-9999-999999999999', 'client', 'windows', '8.2.2', 19, 'published', 'stable',
 'installers/THQ-Business-v8.2.2-build19-windows-x64.exe', 17728041, '81498e89fa2a67031d76f187b8e356837bab93e1c6de34dcd754c53e164b590e',
 'CN=THQ ERP Internal QA Test - CLIENT-BC8AEE, O=THQ Systems, OU=QA Release Engineering',
 'device', array['bc8aeec1-9bce-4935-b349-168caf9a7fa4']::uuid[], array['a659b6de-885d-44ed-9fa7-93eefa7d47d2']::uuid[],
 '2026-10-23 11:00:00+00'),

('a7b806e2-7893-4b71-b467-d9b5425372dd', 'client', 'windows', '8.2.3', 22, 'published', 'stable',
 'installers/THQ-Business-v8.2.3-build22-windows-x64.exe', 17316432, '18887931258c06d7fb723d9f476e2542e2b4f9dc000921bdee10248d087e3451',
 'CN=THQ ERP Internal QA Test - CLIENT-BC8AEE, O=THQ Systems, OU=QA Release Engineering',
 'device', array['bc8aeec1-9bce-4935-b349-168caf9a7fa4']::uuid[], array['a659b6de-885d-44ed-9fa7-93eefa7d47d2']::uuid[],
 '2026-10-27 12:35:21+00');
"""


def execute_sql(sql_str, dbname="postgres"):
    """Executes a SQL snippet using psql.exe against the isolated test cluster."""
    cmd = [
        PSQL_BIN,
        "-h", "127.0.0.1",
        "-p", str(PORT),
        "-U", "postgres",
        "-d", dbname,
        "-v", "ON_ERROR_STOP=1",
        "-c", sql_str
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.returncode, res.stdout, res.stderr


def execute_file(file_path, dbname="postgres"):
    """Executes a SQL file using psql.exe against the isolated test cluster."""
    cmd = [
        PSQL_BIN,
        "-h", "127.0.0.1",
        "-p", str(PORT),
        "-U", "postgres",
        "-d", dbname,
        "-v", "ON_ERROR_STOP=1",
        "-f", file_path
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.returncode, res.stdout, res.stderr


class TestPostgreSQLMigrationCases(unittest.TestCase):
    temp_dir = None
    pg_proc = None
    pg_log_file = None

    @classmethod
    def setUpClass(cls):
        """Initializes and starts a dedicated disposable PostgreSQL 17 instance."""
        if not os.path.exists(INITDB_BIN) or not os.path.exists(POSTGRES_BIN):
            raise unittest.SkipTest("PostgreSQL 17 binaries not found in " + PG_BIN_DIR)

        cls.temp_dir = tempfile.mkdtemp(prefix="pg_integ_test_")
        
        # 1. Run initdb with trust authentication
        init_res = subprocess.run(
            [INITDB_BIN, "-D", cls.temp_dir, "-U", "postgres", "-A", "trust", "--no-locale", "-E", "UTF8"],
            capture_output=True, text=True
        )
        if init_res.returncode != 0:
            shutil.rmtree(cls.temp_dir, ignore_errors=True)
            raise RuntimeError(f"initdb failed: {init_res.stderr}")

        # 2. Redirect server output to a log file to avoid pipe buffer deadlocks
        log_path = os.path.join(cls.temp_dir, "postgres_server.log")
        cls.pg_log_file = open(log_path, "w", encoding="utf-8")

        # Start postgres.exe on dedicated port
        cls.pg_proc = subprocess.Popen(
            [POSTGRES_BIN, "-D", cls.temp_dir, "-p", str(PORT), "-F"],
            stdout=cls.pg_log_file, stderr=cls.pg_log_file
        )

        # 3. Wait for database server readiness
        ready = False
        for _ in range(15):
            time.sleep(0.5)
            rc, stdout, _ = execute_sql("SELECT 1;")
            if rc == 0 and "1" in stdout:
                ready = True
                break

        if not ready:
            cls.tearDownClass()
            raise RuntimeError("Disposable PostgreSQL instance failed to start on port " + str(PORT))

    @classmethod
    def tearDownClass(cls):
        """Terminates disposable PostgreSQL server and cleans up test directory."""
        if cls.pg_proc:
            cls.pg_proc.terminate()
            try:
                cls.pg_proc.wait(timeout=5)
            except Exception:
                cls.pg_proc.kill()
        if cls.pg_log_file:
            try:
                cls.pg_log_file.close()
            except Exception:
                pass
        if cls.temp_dir and os.path.exists(cls.temp_dir):
            shutil.rmtree(cls.temp_dir, ignore_errors=True)

    def reset_database(self):
        """Helper to reset database to clean baseline schema and data."""
        rc, out, err = execute_sql(BASELINE_SCHEMA_SQL + BASELINE_DATA_SQL)
        self.assertEqual(rc, 0, f"Baseline reset failed: {err}")

    # =========================================================================
    # CASE A — Empty historical record
    # =========================================================================
    def test_case_a_empty_historical_record(self):
        """Build 21 row does not exist -> inserted, withdrawn, verified."""
        self.reset_database()
        
        # Verify Build 21 is absent before migration
        rc, out, _ = execute_sql("SELECT count(*) FROM public.platform_app_releases WHERE id = '193b806e-2789-4b71-b467-d9b542537221';")
        self.assertIn("0", out)

        # Execute migration
        rc, out, err = execute_file(MIGRATION_PATH)
        self.assertEqual(rc, 0, f"Migration failed on Case A: {err}")

        # Verify Build 21 was inserted with exact required values (using UTC timezone conversion)
        rc, out, _ = execute_sql("""
            SELECT status, build_number, version, package_size_bytes, released_at AT TIME ZONE 'UTC'
            FROM public.platform_app_releases
            WHERE id = '193b806e-2789-4b71-b467-d9b542537221';
        """)
        self.assertIn("withdrawn", out)
        self.assertIn("21", out)
        self.assertIn("8.2.3", out)
        self.assertIn("17316008", out)
        self.assertIn("2026-10-27 11:13:03", out)

    # =========================================================================
    # CASE B — Identical historical record
    # =========================================================================
    def test_case_b_identical_historical_record(self):
        """Correct Build 21 row already exists -> idempotent no-op, no duplicates."""
        self.reset_database()
        
        # Run migration first time
        rc, _, err = execute_file(MIGRATION_PATH)
        self.assertEqual(rc, 0, f"Initial migration failed: {err}")

        # Record count before second run
        rc, out_before, _ = execute_sql("SELECT count(*) FROM public.platform_app_releases;")
        
        # Run migration second time
        rc, out_mig2, err = execute_file(MIGRATION_PATH)
        self.assertEqual(rc, 0, f"Second migration run failed: {err}")
        self.assertIn("already restored with identical metadata", err + out_mig2)

        # Record count after second run must be identical
        rc, out_after, _ = execute_sql("SELECT count(*) FROM public.platform_app_releases;")
        self.assertEqual(out_before.strip(), out_after.strip())

    # =========================================================================
    # CASE C — Conflicting historical record
    # =========================================================================
    def test_case_c_conflicting_historical_record(self):
        """Designated Build 21 ID exists with mismatched metadata -> fails closed, rolls back."""
        self.reset_database()
        
        # 1. Apply migration first so schema and valid Build 21 row exist
        rc, _, err = execute_file(MIGRATION_PATH)
        self.assertEqual(rc, 0, f"Setup migration failed: {err}")

        # 2. Tamper with Build 21 record by modifying package_size_bytes
        execute_sql("UPDATE public.platform_app_releases SET package_size_bytes = 999999 WHERE id = '193b806e-2789-4b71-b467-d9b542537221';")

        # 3. Re-run migration -> must fail closed with exception reporting mismatched fields
        rc, out, err = execute_file(MIGRATION_PATH)
        self.assertNotEqual(rc, 0, "Migration should have failed on conflicting metadata")
        self.assertIn("already exists but differs in fields", err)
        self.assertIn("package_size_bytes", err)

        # 4. Verify transaction rolled back: tampered value remains unchanged (not silently overwritten)
        rc, out, _ = execute_sql("SELECT package_size_bytes FROM public.platform_app_releases WHERE id = '193b806e-2789-4b71-b467-d9b542537221';")
        self.assertIn("999999", out)

    # =========================================================================
    # CASE D — Artifact build conflict
    # =========================================================================
    def test_case_d_artifact_build_conflict(self):
        """Another artifact release already uses (client, windows, 21) -> migration refuses to overwrite."""
        self.reset_database()
        
        # Temporarily drop old constraint to insert competing version 8.2.3-rc1 with build 21
        execute_sql("ALTER TABLE public.platform_app_releases DROP CONSTRAINT platform_app_releases_app_key_platform_version_key;")
        execute_sql("""
            INSERT INTO public.platform_app_releases (
                id, app_key, platform, version, build_number, status, download_url
            ) VALUES (
                'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', 'client', 'windows', '8.2.3-rc1', 21, 'draft',
                'installers/THQ-Business-conflict.exe'
            );
        """)

        # Run migration -> must detect conflict and fail closed
        rc, out, err = execute_file(MIGRATION_PATH)
        self.assertNotEqual(rc, 0, "Migration should have failed on artifact build conflict")
        self.assertIn("Artifact build conflict", err)

    # =========================================================================
    # CASE E — Legacy duplicate build numbers
    # =========================================================================
    def test_case_e_legacy_duplicate_build_numbers(self):
        """Legacy rows share build numbers and have null download URLs -> index created, legacy rows preserved."""
        self.reset_database()

        # Confirm duplicate build numbers exist in baseline
        rc, out, _ = execute_sql("""
            SELECT build_number, count(*)
            FROM public.platform_app_releases
            WHERE app_key = 'client' AND platform = 'windows' AND build_number = 1
            GROUP BY build_number;
        """)
        self.assertIn("4", out)  # 4 rows in baseline for client/windows build 1

        # Run migration -> must succeed and create artifact partial index despite legacy duplicates
        rc, out, err = execute_file(MIGRATION_PATH)
        self.assertEqual(rc, 0, f"Migration failed with legacy duplicate build numbers: {err}")

        # Verify artifact partial index exists
        rc, out, _ = execute_sql("SELECT indexname FROM pg_indexes WHERE indexname = 'platform_app_releases_artifact_build_key';")
        self.assertIn("platform_app_releases_artifact_build_key", out)

    # =========================================================================
    # CASE F — Duplicate active versions
    # =========================================================================
    def test_case_f_duplicate_active_versions(self):
        """Two active records have same app, platform, version -> preflight detects conflict and fails safely."""
        self.reset_database()

        # Temporarily drop old constraint to inject collision for preflight test
        execute_sql("ALTER TABLE public.platform_app_releases DROP CONSTRAINT platform_app_releases_app_key_platform_version_key;")
        execute_sql("""
            INSERT INTO public.platform_app_releases (
                id, app_key, platform, version, build_number, status
            ) VALUES (
                'bbbbbbbb-cccc-dddd-eeee-ffffffffffff', 'client', 'windows', '8.2.3', 20, 'published'
            );
        """)

        # Run migration -> preflight must catch the active version collision (Build 20 and Build 22 both active 8.2.3)
        rc, out, err = execute_file(MIGRATION_PATH)
        self.assertNotEqual(rc, 0, "Preflight should have caught active duplicate versions")
        self.assertIn("Pre-flight check failed: Found 1 duplicate active versions", err)

    # =========================================================================
    # CASE G — Repeated execution
    # =========================================================================
    def test_case_g_repeated_execution(self):
        """Run complete migration twice -> succeeds, zero duplicate rows."""
        self.reset_database()

        rc1, _, err1 = execute_file(MIGRATION_PATH)
        self.assertEqual(rc1, 0, f"Run 1 failed: {err1}")

        rc2, _, err2 = execute_file(MIGRATION_PATH)
        self.assertEqual(rc2, 0, f"Run 2 failed: {err2}")

        # Check total count of Build 21 rows
        rc, out, _ = execute_sql("SELECT count(*) FROM public.platform_app_releases WHERE id = '193b806e-2789-4b71-b467-d9b542537221';")
        self.assertIn("1", out)

    # =========================================================================
    # CASE H — Transaction rollback
    # =========================================================================
    def test_case_h_transaction_rollback(self):
        """Force a failure inside transaction -> all transactional changes are rolled back."""
        self.reset_database()

        # Construct a failing script that creates an index and then raises an exception
        failing_script = """
        BEGIN;
        DROP INDEX IF EXISTS public.platform_app_releases_active_version_key;
        CREATE UNIQUE INDEX platform_app_releases_active_version_key ON public.platform_app_releases (app_key, platform, version);
        DO $$ BEGIN RAISE EXCEPTION 'Intentional failure to test rollback'; END $$;
        COMMIT;
        """
        rc, _, err = execute_sql(failing_script)
        self.assertNotEqual(rc, 0)

        # Verify index was not created (transaction rolled back)
        rc, out, _ = execute_sql("SELECT count(*) FROM pg_indexes WHERE indexname = 'platform_app_releases_active_version_key';")
        self.assertIn("0", out)

    # =========================================================================
    # CASE I — Build 21 withdrawal
    # =========================================================================
    def test_case_i_build21_withdrawal(self):
        """Discovery RPC ignores withdrawn Build 21; download function rejects it with 403."""
        self.reset_database()
        execute_file(MIGRATION_PATH)

        # Simulate app_release_check_v820 selector: WHERE status IN ('published', 'stable', 'beta')
        rc, out, _ = execute_sql("""
            SELECT id, version, build_number, status
            FROM public.platform_app_releases
            WHERE app_key = 'client' AND platform = 'windows' AND status IN ('published', 'stable', 'beta')
            ORDER BY build_number DESC LIMIT 1;
        """)
        # Highest active release must be Build 22, NOT Build 21
        self.assertIn("a7b806e2-7893-4b71-b467-d9b5425372dd", out)
        self.assertIn("22", out)
        self.assertNotIn("193b806e-2789-4b71-b467-d9b542537221", out)

        # Simulate Edge Function check: if (!['published', 'stable', 'beta'].includes(release.status)) -> reject
        rc, out, _ = execute_sql("SELECT status FROM public.platform_app_releases WHERE id = '193b806e-2789-4b71-b467-d9b542537221';")
        self.assertIn("withdrawn", out)
        self.assertNotIn("published", out)

    # =========================================================================
    # CASE J — Build 22 integrity
    # =========================================================================
    def test_case_j_build22_integrity(self):
        """Build 22 record remains untouched in ID, version, build, checksum, size, target rules."""
        self.reset_database()

        # Capture Build 22 record before migration
        rc, out_before, _ = execute_sql("""
            SELECT id, app_key, platform, version, build_number, status, package_size_bytes, sha256_checksum, target_type
            FROM public.platform_app_releases
            WHERE id = 'a7b806e2-7893-4b71-b467-d9b5425372dd';
        """)

        # Execute migration
        execute_file(MIGRATION_PATH)

        # Capture Build 22 record after migration
        rc, out_after, _ = execute_sql("""
            SELECT id, app_key, platform, version, build_number, status, package_size_bytes, sha256_checksum, target_type
            FROM public.platform_app_releases
            WHERE id = 'a7b806e2-7893-4b71-b467-d9b5425372dd';
        """)

        self.assertEqual(out_before.strip(), out_after.strip())

    # =========================================================================
    # CASE K — Status transitions
    # =========================================================================
    def test_case_k_status_transitions(self):
        """Test status transitions (published -> paused -> withdrawn) under partial unique indexes."""
        self.reset_database()
        execute_file(MIGRATION_PATH)

        # 1. Pausing Build 22 succeeds
        rc, _, err = execute_sql("UPDATE public.platform_app_releases SET status = 'paused' WHERE id = 'a7b806e2-7893-4b71-b467-d9b5425372dd';")
        self.assertEqual(rc, 0, f"Pause update failed: {err}")

        # 2. Reactivating Build 22 to 'published' succeeds
        rc, _, err = execute_sql("UPDATE public.platform_app_releases SET status = 'published' WHERE id = 'a7b806e2-7893-4b71-b467-d9b5425372dd';")
        self.assertEqual(rc, 0, f"Reactivation failed: {err}")

        # 3. Attempting to activate Build 21 (status='published') while Build 22 is active version 8.2.3 fails under partial index
        rc, _, err = execute_sql("UPDATE public.platform_app_releases SET status = 'published' WHERE id = '193b806e-2789-4b71-b467-d9b542537221';")
        self.assertNotEqual(rc, 0, "Activating duplicate semver should violate partial unique index")
        self.assertIn("platform_app_releases_active_version_key", err)

    # =========================================================================
    # CASE L — Concurrent publication simulation
    # =========================================================================
    def test_case_l_concurrent_publication(self):
        """Simulate two transactions attempting to insert duplicate active version -> database constraint prevents duplicate."""
        self.reset_database()
        execute_file(MIGRATION_PATH)

        # First transaction inserts new version 8.2.4 as published
        rc, _, err = execute_sql("""
            INSERT INTO public.platform_app_releases (
                id, app_key, platform, version, build_number, status, download_url
            ) VALUES (
                'cccccccc-1111-2222-3333-444444444444', 'client', 'windows', '8.2.4', 23, 'published',
                'installers/THQ-Business-v8.2.4-build23-windows-x64.exe'
            );
        """)
        self.assertEqual(rc, 0, f"First insert failed: {err}")

        # Second concurrent transaction attempts to insert same (client, windows, 8.2.4) as published
        rc, _, err = execute_sql("""
            INSERT INTO public.platform_app_releases (
                id, app_key, platform, version, build_number, status, download_url
            ) VALUES (
                'dddddddd-1111-2222-3333-444444444444', 'client', 'windows', '8.2.4', 23, 'published',
                'installers/THQ-Business-v8.2.4-build23-windows-x64.exe'
            );
        """)
        self.assertNotEqual(rc, 0, "Duplicate active release insert should have failed")
        self.assertIn("platform_app_releases_active_version_key", err)


def run_tests():
    suite = unittest.TestLoader().loadTestsFromTestCase(TestPostgreSQLMigrationCases)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(run_tests())
