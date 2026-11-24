import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'pos_database_key_store.dart';

/// Manages SQLCipher database encryption at rest, automatic plaintext migration,
/// key validation, encrypted backups, and safe recovery for the desktop POS database.
class PosDatabaseSecurityManager {
  static const String defaultKeyName = 'thq_pos_offline_db_key_v486';

  /// Ensures that the database at [databasePath] is properly encrypted with SQLCipher,
  /// migrating an existing plaintext database if detected, and returns an opened, verified [Database].
  static Future<Database> ensureEncryptedAndOpen({
    required String databasePath,
    required PosDatabaseKeyStore keyStore,
    String keyName = defaultKeyName,
  }) async {
    final dbFile = File(databasePath);
    final exists = await dbFile.exists();

    String? keyHex = await keyStore.readKey(keyName: keyName);

    if (!exists) {
      // 1. Fresh database initialization
      if (keyHex == null) {
        keyHex = PosDatabaseKeyStore.generateSecureKeyHex();
        await keyStore.writeKey(keyName: keyName, keyHex: keyHex);
      }
      return _openEncryptedDatabase(databasePath, keyHex);
    }

    // 2. Existing database file detected: check whether it is plaintext or already encrypted
    final isPlain = isPlaintextDatabase(databasePath);

    if (isPlain) {
      // Existing plaintext database must be migrated to SQLCipher
      if (keyHex == null) {
        keyHex = PosDatabaseKeyStore.generateSecureKeyHex();
        await keyStore.writeKey(keyName: keyName, keyHex: keyHex);
      }
      await migratePlaintextToEncrypted(
        databasePath: databasePath,
        keyHex: keyHex,
      );
      return _openEncryptedDatabase(databasePath, keyHex);
    }

    // 3. Database is already encrypted
    if (keyHex == null) {
      throw PosDatabaseKeyMissingException(
        'An encrypted POS offline database was found at "$databasePath", '
        'but no encryption key is available in Windows secure storage. '
        'The database file has been preserved to prevent data loss. '
        'Please restore the Windows credential or contact technical support.',
      );
    }

    return _openEncryptedDatabase(databasePath, keyHex);
  }

  /// Opens an encrypted SQLCipher database using [keyHex], verifies that the key
  /// successfully decrypts the database, and applies production PRAGMA configurations.
  static Database _openEncryptedDatabase(String databasePath, String keyHex) {
    final db = sqlite3.open(databasePath);
    try {
      db.execute("PRAGMA key = \"x'$keyHex'\";");
      db.execute('PRAGMA cipher_memory_security=ON;');

      // Verify that the key is valid by querying sqlite_master
      db.select('SELECT count(*) FROM sqlite_master;');

      // Standard production SQLite configurations
      db.execute('PRAGMA journal_mode=WAL;');
      db.execute('PRAGMA synchronous=FULL;');
      db.execute('PRAGMA foreign_keys=ON;');

      return db;
    } catch (e) {
      try {
        db.close();
      } catch (_) {}
      if (e is SqliteException) {
        throw PosDatabaseEncryptionException(
          'Failed to decrypt or authenticate the POS offline database. '
          'The encryption key may be mismatched, invalid, or the database file is corrupted.',
          e,
        );
      }
      rethrow;
    }
  }

  /// Checks whether the SQLite database at [databasePath] is unencrypted plaintext.
  static bool isPlaintextDatabase(String databasePath) {
    final file = File(databasePath);
    if (!file.existsSync() || file.lengthSync() < 16) return false;

    // Fast check: Unencrypted SQLite databases start with ASCII "SQLite format 3\0"
    try {
      final raf = file.openSync(mode: FileMode.read);
      try {
        final headerBytes = raf.readSync(16);
        final headerStr = utf8.decode(headerBytes, allowMalformed: true);
        if (headerStr != 'SQLite format 3\x00') {
          return false;
        }
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return false;
    }

    // Deep check: Attempt unkeyed read
    try {
      final testDb = sqlite3.open(databasePath);
      try {
        testDb.select('SELECT count(*) FROM sqlite_master;');
        return true;
      } finally {
        testDb.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Migrates an existing plaintext SQLite database to SQLCipher encryption using `sqlcipher_export`.
  /// Preserves all data, verifies integrity and records, and keeps a protected recovery backup.
  static Future<void> migratePlaintextToEncrypted({
    required String databasePath,
    required String keyHex,
  }) async {
    final lockFile = File('$databasePath.migration.lock');
    if (await lockFile.exists()) {
      final modified = await lockFile.lastModified();
      if (DateTime.now().difference(modified).inMinutes < 10) {
        throw const PosDatabaseMigrationException(
          'A POS database migration is currently in progress or was recently interrupted. '
          'Please wait or ensure no other instance of THQ POS is running.',
        );
      }
      await lockFile.delete();
    }

    // Acquire migration lock
    await lockFile.writeAsString(
      jsonEncode({
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'pid': pid,
      }),
    );

    final tmpEncPath = '$databasePath.migrating.tmp';
    final tmpFile = File(tmpEncPath);
    if (await tmpFile.exists()) {
      await tmpFile.delete();
    }

    try {
      // 1. Flush any pending WAL pages on the plaintext database
      try {
        final plainDb = sqlite3.open(databasePath);
        try {
          plainDb.execute('PRAGMA wal_checkpoint(TRUNCATE);');
        } finally {
          plainDb.close();
        }
      } catch (_) {}

      // 2. Snapshot original record counts and pending sync invoices for validation
      final originalStats = _captureDatabaseStats(databasePath, keyHex: null);

      // 3. Export plaintext database to temporary encrypted target via SQLCipher
      final exportDb = sqlite3.open(databasePath);
      final sqlTmpPath = tmpEncPath.replaceAll(r'\', '/');
      try {
        exportDb.execute("ATTACH DATABASE '$sqlTmpPath' AS encrypted KEY \"x'$keyHex'\";");
        exportDb.execute("SELECT sqlcipher_export('encrypted');");
        exportDb.execute('DETACH DATABASE encrypted;');
      } finally {
        exportDb.close();
      }

      // 4. Verify the temporary encrypted database
      final migratedStats = _captureDatabaseStats(tmpEncPath, keyHex: keyHex);

      // Check integrity
      final checkDb = sqlite3.open(tmpEncPath);
      try {
        checkDb.execute("PRAGMA key = \"x'$keyHex'\";");
        final integrityRows = checkDb.select('PRAGMA integrity_check;');
        if (integrityRows.isEmpty || integrityRows.first.values.first != 'ok') {
          throw PosDatabaseMigrationException(
            'Migrated encrypted database failed SQLite integrity check: $integrityRows',
          );
        }
      } finally {
        checkDb.close();
      }

      // Check that unkeyed access fails
      try {
        final unkeyedDb = sqlite3.open(tmpEncPath);
        bool unkeyedFailed = false;
        try {
          unkeyedDb.select('SELECT count(*) FROM sqlite_master;');
        } catch (_) {
          unkeyedFailed = true;
        } finally {
          unkeyedDb.close();
        }
        if (!unkeyedFailed) {
          throw const PosDatabaseMigrationException(
            'Migrated database allows unkeyed access. Encryption was not applied.',
          );
        }
      } catch (e) {
        if (e is PosDatabaseMigrationException) rethrow;
      }

      // Compare counts and pending invoices
      _assertStatsMatch(originalStats, migratedStats);

      // 5. Atomic swap with recovery backup
      final backupPath = '$databasePath.plaintext.bak';
      await _safeRename(File(databasePath), backupPath);

      // Also backup WAL/SHM if present
      final walFile = File('$databasePath-wal');
      if (await walFile.exists()) {
        await _safeRename(walFile, '$backupPath-wal');
      }
      final shmFile = File('$databasePath-shm');
      if (await shmFile.exists()) {
        await _safeRename(shmFile, '$backupPath-shm');
      }

      // Rename validated encrypted database to authoritative path
      await _safeRename(File(tmpEncPath), databasePath);
    } catch (e) {
      if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
      throw PosDatabaseMigrationException('Database encryption migration failed.', e);
    } finally {
      if (await lockFile.exists()) {
        try {
          await lockFile.delete();
        } catch (_) {}
      }
    }
  }

  static Future<void> _safeRename(File from, String toPath) async {
    for (int i = 0; i < 15; i++) {
      try {
        final target = File(toPath);
        if (await target.exists()) {
          await target.delete();
        }
        await from.rename(toPath);
        return;
      } catch (e) {
        if (i == 14) rethrow;
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  /// Creates a consistent, encrypted backup of the active database at [targetBackupPath].
  static Future<void> backupEncrypted({
    required Database db,
    required String targetBackupPath,
    required String keyHex,
  }) async {
    final targetFile = File(targetBackupPath);
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    // Checkpoint active WAL so all changes are unified
    db.execute('PRAGMA wal_checkpoint(TRUNCATE);');

    // In SQLCipher, VACUUM INTO produces an encrypted, standalone database copy with the same key
    final sqlBackupPath = targetBackupPath.replaceAll(r'\', '/');
    db.execute("VACUUM INTO '$sqlBackupPath';");

    // Verify backup copy
    final testDb = sqlite3.open(targetBackupPath);
    try {
      testDb.execute("PRAGMA key = \"x'$keyHex'\";");
      final rows = testDb.select('PRAGMA integrity_check;');
      if (rows.isEmpty || rows.first.values.first != 'ok') {
        throw PosDatabaseEncryptionException('Backup verification failed: $rows');
      }
    } finally {
      testDb.close();
    }
  }

  /// Restores an encrypted backup from [sourceBackupPath] to [databasePath] after verifying integrity.
  static Future<void> restoreEncrypted({
    required String databasePath,
    required String sourceBackupPath,
    required String keyHex,
  }) async {
    final sourceFile = File(sourceBackupPath);
    if (!await sourceFile.exists()) {
      throw PosDatabaseEncryptionException('Backup source file does not exist: $sourceBackupPath');
    }

    // Verify source backup can be decrypted and has valid integrity
    final testDb = sqlite3.open(sourceBackupPath);
    try {
      testDb.execute("PRAGMA key = \"x'$keyHex'\";");
      final rows = testDb.select('PRAGMA integrity_check;');
      if (rows.isEmpty || rows.first.values.first != 'ok') {
        throw PosDatabaseEncryptionException('Source backup file failed integrity check: $rows');
      }
    } finally {
      testDb.close();
    }

    // Create a safety backup of current database before replacing
    final safetyBak = '$databasePath.pre_restore.bak';
    final curFile = File(databasePath);
    if (await curFile.exists()) {
      final bakFile = File(safetyBak);
      if (await bakFile.exists()) await bakFile.delete();
      await curFile.copy(safetyBak);
    }

    // Clean up current WAL and SHM files
    final walFile = File('$databasePath-wal');
    if (await walFile.exists()) await walFile.delete();
    final shmFile = File('$databasePath-shm');
    if (await shmFile.exists()) await shmFile.delete();

    // Replace database with validated backup
    await sourceFile.copy(databasePath);
  }

  /// Rotates the encryption key using SQLCipher's `PRAGMA rekey`.
  static Future<void> rotateKey({
    required Database db,
    required PosDatabaseKeyStore keyStore,
    required String newKeyHex,
    String keyName = defaultKeyName,
  }) async {
    // Validate new key
    if (newKeyHex.length != 64 || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(newKeyHex)) {
      throw const PosDatabaseEncryptionException('New key format is invalid. Must be 64 hex characters.');
    }

    db.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    db.execute("PRAGMA rekey = \"x'$newKeyHex'\";");

    // Verify rekey was successful on active connection
    db.select('SELECT count(*) FROM sqlite_master;');

    // Persist new key in Windows secure storage
    await keyStore.writeKey(keyName: keyName, keyHex: newKeyHex);
  }

  static Map<String, dynamic> _captureDatabaseStats(String path, {required String? keyHex}) {
    final db = sqlite3.open(path);
    try {
      if (keyHex != null) {
        db.execute("PRAGMA key = \"x'$keyHex'\";");
      }

      final tables = db.select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';");
      final tableCounts = <String, int>{};
      for (final row in tables) {
        final tableName = row['name'] as String;
        final countRows = db.select('SELECT count(*) AS c FROM "$tableName";');
        tableCounts[tableName] = (countRows.first['c'] as int?) ?? 0;
      }

      final pendingInvoices = <Map<String, dynamic>>[];
      if (tableCounts.containsKey('offline_invoices')) {
        final rows = db.select(
          "SELECT request_id,local_invoice_number,status,payload_json,attempts FROM offline_invoices "
          "WHERE status IN ('pending','syncing','conflict','error') ORDER BY request_id;",
        );
        for (final row in rows) {
          pendingInvoices.add({
            'request_id': row['request_id'],
            'local_invoice_number': row['local_invoice_number'],
            'status': row['status'],
            'attempts': row['attempts'],
            'payload_json': row['payload_json'],
          });
        }
      }

      return {
        'table_counts': tableCounts,
        'pending_invoices': pendingInvoices,
      };
    } finally {
      db.close();
    }
  }

  static void _assertStatsMatch(Map<String, dynamic> original, Map<String, dynamic> migrated) {
    final origCounts = original['table_counts'] as Map<String, int>;
    final migCounts = migrated['table_counts'] as Map<String, int>;

    for (final entry in origCounts.entries) {
      final migratedCount = migCounts[entry.key];
      if (migratedCount != entry.value) {
        throw PosDatabaseMigrationException(
          'Record count mismatch for table "${entry.key}": expected ${entry.value}, found $migratedCount.',
        );
      }
    }

    final origPending = original['pending_invoices'] as List<Map<String, dynamic>>;
    final migPending = migrated['pending_invoices'] as List<Map<String, dynamic>>;

    if (origPending.length != migPending.length) {
      throw PosDatabaseMigrationException(
        'Pending offline invoices count mismatch: expected ${origPending.length}, found ${migPending.length}.',
      );
    }

    for (int i = 0; i < origPending.length; i++) {
      final o = origPending[i];
      final m = migPending[i];
      if (o['request_id'] != m['request_id'] ||
          o['local_invoice_number'] != m['local_invoice_number'] ||
          o['status'] != m['status'] ||
          o['payload_json'] != m['payload_json']) {
        throw PosDatabaseMigrationException(
          'Pending invoice data mismatch for request_id "${o['request_id']}".',
        );
      }
    }
  }
}
