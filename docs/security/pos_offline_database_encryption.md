# THQ POS Desktop — Offline SQLite Database Encryption at Rest

**Remediation Finding:** `SEC-P2-02`  
**Application:** `apps/pos_app` (Windows Desktop Flutter)  
**Database:** `thq_pos_offline_v486.sqlite`  
**Encryption Standard:** AES-256 (Page-Level Full Database Encryption)  
**Engine:** SQLCipher 4.17.0 Community via `package:sqlite3` Dart hooks  

---

## 1. Architecture & Threat Model

The THQ POS desktop application stores operational business records locally to support offline billing, cached catalogs, serial number tracking, and an offline invoice synchronization queue.

### Threat Model
- **Protected Threat:** Physical device theft, unauthorized secondary user access to the filesystem, unauthorized extraction of SQLite `.sqlite`, `-wal`, or `-shm` files from the disk, and offline file-level forensic analysis.
- **Scope of Protection:** 100% of SQLite database pages are encrypted at rest using AES-256 in CBC mode with HMAC-SHA512 per-page authentication. This includes catalog data, customer data, offline sales, pending payment records, and journal/WAL files.
- **Environmental Boundary:** Cryptographic keys are bound to the authorized Windows operating system user account via Windows DPAPI. Access is restricted to the specific Windows user profile running the application.

---

## 2. Key Generation & Secure Storage

1. **Key Generation:**
   - Cryptographically secure 256-bit (32-byte) random key generated via `Random.secure()`.
   - Formatted as a 64-character lowercase hexadecimal string (`256-bit raw key`).
   - Fed directly to SQLCipher via raw key pragma: `PRAGMA key = "x'<64-char-hex>'";` to enforce exact key entropy without password derivation ambiguity.

2. **Key Storage:**
   - Managed via `PosDatabaseKeyStore` interface.
   - Primary production implementation: `DpapiPosDatabaseKeyStore`.
   - Utilizes `flutter_secure_storage` configured with `WindowsOptions(useBackwardCompatibility: false)`, storing secrets in the Windows Credential Store protected by the Windows Data Protection API (`CryptProtectData`).
   - Storage Key Identifier: `thq_pos_offline_db_key_v486`.

3. **Inaccessible Key Policy:**
   - If an existing encrypted database file is present on disk, but the key is missing from Windows secure storage, the application **strictly refuses** to overwrite or generate a fresh key.
   - A `PosDatabaseKeyMissingException` is raised, halting initialization and preserving the database file to prevent irreversible data loss.

---

## 3. Plaintext Database Migration Procedure

Existing POS installations running prior versions may have an unencrypted `thq_pos_offline_v486.sqlite` database containing cached products and queued transactions.

The `PosDatabaseSecurityManager` executes an automatic, safe, atomic, and leak-free migration:

1. **Interrupted Migration Recovery:**
   - Detects and clears stale lock files and temporary export files from previous crashes.
   - If an unverified `.plaintext.bak` exists alongside a damaged or missing primary database, restores `.plaintext.bak` back to `thq_pos_offline_v486.sqlite` before proceeding.
   - If the primary database is already verified and encrypted, safely purges obsolete `.plaintext.bak` remnants.
2. **Detection:**
   - Inspects the database file header for the ASCII string `SQLite format 3\0`.
   - Tests unkeyed database opening. If unkeyed read succeeds, the database is flagged as plaintext.
3. **Concurrency Lock & Restrictive Permissions:**
   - Acquires a migration lock file (`<path>.migration.lock`) with PID and timestamp.
   - Applies restrictive Windows ACL permissions (`icacls /inheritance:r /grant:r %USERNAME%:(F)`) to lock and temporary files.
4. **WAL Flush:**
   - Executes `PRAGMA wal_checkpoint(TRUNCATE);` on the plaintext database so all pending WAL pages are committed into the main file.
5. **Snapshot Baseline:**
   - Captures table row counts (`offline_invoices`, `offline_products`, `offline_customers`, `offline_serials`, `offline_meta`) and snapshots all pending queue records (`status IN ('pending', 'syncing', 'conflict', 'error')`).
6. **SQLCipher Export:**
   - Generates or retrieves the 256-bit key from Windows DPAPI storage.
   - Opens the plaintext database, executes `ATTACH DATABASE '<tmpPath>' AS encrypted KEY "x'<keyHex>'";`.
   - Runs `SELECT sqlcipher_export('encrypted');` and detaches.
7. **Pre-Swap Verification:**
   - Opens the temporary encrypted database with the key.
   - Executes `PRAGMA integrity_check;` and verifies result is `ok`.
   - Verifies row counts across all tables match the baseline snapshot.
   - Verifies all pending invoices match field-for-field (request ID, invoice number, status, payload JSON, attempts).
   - Verifies that an unkeyed connection to the temporary database fails with `SqliteException`.
8. **Atomic Swap & Safe Recovery Hold:**
   - Renames the original plaintext database to `<databasePath>.plaintext.bak` (along with any `-wal` or `-shm` files) as a temporary recovery hold with restrictive permissions.
   - Renames the temporary encrypted file to `thq_pos_offline_v486.sqlite`.
9. **Authoritative Post-Swap Verification:**
   - Verifies that the authoritative path opens with the encryption key and passes `PRAGMA integrity_check`.
   - Re-verifies all table record counts and pending sync invoices on the final path.
   - Simulates application restart by closing and reopening the connection cleanly.
   - **Rollback on Verification Failure:** If post-swap verification fails, the unverified database is removed and `<databasePath>.plaintext.bak` is immediately restored to the authoritative path.
10. **Encrypted Recovery Backup Retention:**
    - Creates a standalone encrypted backup at `<databasePath>.encrypted.bak`.
    - Verifies that `<databasePath>.encrypted.bak` opens with the key and passes integrity checks.
    - Ensures that any rollback retention is fully encrypted and never stored in plaintext.
11. **Secure Plaintext Cleanup & Error Detection:**
    - Overwrites all plaintext migration copies (`<databasePath>.plaintext.bak`, `.plaintext.bak-wal`, `.plaintext.bak-shm`, etc.) with zero bytes (best-effort wipe) and deletes the files.
    - If any plaintext file cannot be deleted (e.g. OS file lock), raises `PosDatabasePlaintextCleanupException` and reports the exact failed paths. Cleanup failures are never silently swallowed.

---

## 4. Encrypted Backup, Restore & Key Rotation

- **Encrypted Backup:**
  - `OfflinePosService.instance.backupEncrypted(targetPath)` checkpoints the active WAL and executes `VACUUM INTO '<targetPath>'`.
  - In SQLCipher, `VACUUM INTO` produces a vacuumed, standalone encrypted copy using the active encryption key.
  - The backup is immediately verified with `PRAGMA integrity_check`.
- **Encrypted Restore:**
  - `OfflinePosService.instance.restoreEncrypted(sourcePath)` validates that the source file is decryptable with the active key and passes integrity checks.
  - Safely backs up the current database to `.pre_restore.encrypted.bak` before restoring the verified backup.
- **Key Rotation:**
  - `OfflinePosService.instance.rotateKey(newKeyHex)` uses SQLCipher's native `PRAGMA rekey = "x'<newKeyHex>'";`.
  - Persists the new key in Windows DPAPI storage upon successful re-encryption.

---

## 5. Security Limitations & Operational Notes

1. **Active Memory:**
   - While the POS application is open and running, decrypted database pages reside in process memory. `PRAGMA cipher_memory_security=ON;` is enabled to zero out memory buffers immediately when released by SQLite.
2. **Filesystem Secure Deletion:**
   - File deletion in `PosDatabaseSecurityManager` performs best-effort application-layer zero-fill sanitization before unlinking. However, on modern SSDs with Flash Translation Layers (FTL), wear-leveling algorithms, and copy-on-write journaling filesystems (NTFS/ReFS), user-space file overwriting cannot guarantee physical flash cell eradication. Full-disk encryption (BitLocker) is recommended as a defense-in-depth measure.
3. **Windows User Context:**
   - If a POS terminal Windows user profile is deleted or the OS is reinstalled without migrating the Windows DPAPI master keys, the stored key will become inaccessible.
   - Administrators should back up the database key or maintain system-level volume backups.
4. **No Plaintext Fallback:**
   - The application does not permit fallback to unencrypted mode. If encryption cannot be initialized, the POS halts with a clear error.
