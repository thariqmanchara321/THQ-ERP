import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pos_app/models/customer.dart';
import 'package:pos_app/models/inventory_product.dart';
import 'package:pos_app/services/offline_pos_service.dart';
import 'package:pos_app/services/pos_database_key_store.dart';
import 'package:pos_app/services/pos_database_security_manager.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;
  late InMemoryPosDatabaseKeyStore keyStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('thq_pos_enc_test_');
    dbPath = p.join(tempDir.path, 'thq_pos_offline_v486.sqlite');
    keyStore = InMemoryPosDatabaseKeyStore();
  });

  tearDown(() async {
    await OfflinePosService.instance.close();
    if (await tempDir.exists()) {
      for (int i = 0; i < 5; i++) {
        try {
          await tempDir.delete(recursive: true);
          break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    }
  });

  test('1. Newly created POS database is encrypted with SQLCipher', () async {
    final service = OfflinePosService.instance;
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);

    await service.setMeta('test_init', {'version': '8.2.2', 'encrypted': true});
    await service.close();

    final file = File(dbPath);
    expect(await file.exists(), isTrue);

    // Verify raw file header is NOT plaintext SQLite
    final bytes = await file.readAsBytes();
    final headerStr = utf8.decode(bytes.sublist(0, 16), allowMalformed: true);
    expect(headerStr, isNot('SQLite format 3\x00'));

    // Verify unkeyed open fails to query
    final unkeyedDb = sqlite3.open(dbPath);
    expect(
      () => unkeyedDb.select('SELECT * FROM offline_meta;'),
      throwsA(isA<SqliteException>()),
    );
    unkeyedDb.close();

    // Verify keyed open succeeds
    final keyHex = await keyStore.readKey(keyName: PosDatabaseSecurityManager.defaultKeyName);
    expect(keyHex, isNotNull);
    final keyedDb = sqlite3.open(dbPath);
    keyedDb.execute("PRAGMA key = \"x'$keyHex'\";");
    final metaRows = keyedDb.select('SELECT * FROM offline_meta;');
    expect(metaRows.length, 1);
    expect(metaRows.first['key'], 'test_init');
    keyedDb.close();
  });

  test('2. Plaintext migration succeeds with representative existing data', () async {
    // Populate an authentic plaintext SQLite database
    final plainDb = sqlite3.open(dbPath);
    plainDb.execute('PRAGMA journal_mode=WAL;');
    plainDb.execute('''CREATE TABLE offline_meta(
      key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL
    );''');
    plainDb.execute('''CREATE TABLE offline_products(
      tenant_id TEXT NOT NULL, location_id TEXT NOT NULL, variant_id TEXT NOT NULL,
      payload_json TEXT NOT NULL, available_quantity REAL NOT NULL DEFAULT 0,
      refreshed_at TEXT NOT NULL, PRIMARY KEY(tenant_id,location_id,variant_id)
    );''');
    plainDb.execute('''CREATE TABLE offline_invoices(
      request_id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL, location_id TEXT NOT NULL,
      device_id TEXT NOT NULL, local_invoice_number TEXT NOT NULL, payload_json TEXT NOT NULL,
      status TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, conflict_code TEXT,
      conflict_message TEXT, server_response_json TEXT, print_requested INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    );''');

    plainDb.execute("INSERT INTO offline_meta VALUES ('tenant_name', '\"THQ Retail Ltd\"', '2026-11-24T10:00:00Z');");
    plainDb.execute(
      "INSERT INTO offline_products VALUES ('t-1', 'loc-1', 'var-100', "
      "'{\"product_name\":\"Cement 50kg\",\"selling_price\":380.0}', 45.0, '2026-11-24T10:00:00Z');",
    );
    plainDb.execute(
      "INSERT INTO offline_invoices VALUES ('req-101', 't-1', 'loc-1', 'dev-1', 'OFF-20261124-001', "
      "'{\"total\":380.0,\"items\":[{\"name\":\"Cement 50kg\",\"quantity\":1}]}', "
      "'pending', 0, NULL, NULL, NULL, 1, '2026-11-24T10:05:00Z', '2026-11-24T10:05:00Z');",
    );
    plainDb.close();

    expect(PosDatabaseSecurityManager.isPlaintextDatabase(dbPath), isTrue);

    // Initialize service -> automatic migration kicks in
    final service = OfflinePosService.instance;
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);

    // Verify it is now encrypted
    expect(PosDatabaseSecurityManager.isPlaintextDatabase(dbPath), isFalse);

    // Verify data accessible via service
    final productList = await service.cachedProducts(tenantId: 't-1', locationId: 'loc-1');
    expect(productList.length, 1);
    expect(productList.first.productName, 'Cement 50kg');
    expect(productList.first.stockQuantity, 45.0);

    final invoice = await service.invoice('req-101');
    expect(invoice, isNotNull);
    expect(invoice!.localInvoiceNumber, 'OFF-20261124-001');
    expect(invoice.status, 'pending');

    await service.close();
  });

  test('3 & 4. Existing pending offline sales and sync queue survive migration intact', () async {
    final plainDb = sqlite3.open(dbPath);
    plainDb.execute('''CREATE TABLE offline_invoices(
      request_id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL, location_id TEXT NOT NULL,
      device_id TEXT NOT NULL, local_invoice_number TEXT NOT NULL, payload_json TEXT NOT NULL,
      status TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, conflict_code TEXT,
      conflict_message TEXT, server_response_json TEXT, print_requested INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    );''');

    // Create 4 invoices with various queue statuses
    plainDb.execute(
      "INSERT INTO offline_invoices VALUES ('inv-pending', 't-1', 'loc-1', 'dev-1', 'OFF-P01', "
      "'{\"total\":120.0}', 'pending', 1, NULL, NULL, NULL, 0, '2026-11-24T08:00:00Z', '2026-11-24T08:00:00Z');",
    );
    plainDb.execute(
      "INSERT INTO offline_invoices VALUES ('inv-syncing', 't-1', 'loc-1', 'dev-1', 'OFF-S01', "
      "'{\"total\":240.0}', 'syncing', 2, NULL, NULL, NULL, 1, '2026-11-24T08:15:00Z', '2026-11-24T08:15:00Z');",
    );
    plainDb.execute(
      "INSERT INTO offline_invoices VALUES ('inv-conflict', 't-1', 'loc-1', 'dev-1', 'OFF-C01', "
      "'{\"total\":360.0}', 'conflict', 3, 'PRICE_MISMATCH', 'Price mismatch detected', NULL, 0, '2026-11-24T08:30:00Z', '2026-11-24T08:30:00Z');",
    );
    plainDb.execute(
      "INSERT INTO offline_invoices VALUES ('inv-synced', 't-1', 'loc-1', 'dev-1', 'OFF-OK01', "
      "'{\"total\":480.0}', 'synced', 1, NULL, NULL, '{\"invoice_id\":\"srv-999\"}', 0, '2026-11-24T08:45:00Z', '2026-11-24T08:45:00Z');",
    );
    plainDb.close();

    final service = OfflinePosService.instance;
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);

    // Verify summary reflects all statuses
    final summary = await service.summary(tenantId: 't-1', deviceId: 'dev-1');
    expect(summary.pending, 2); // pending + syncing
    expect(summary.conflict, 1);
    expect(summary.error, 0);
    expect(summary.synced, 1);
    expect(summary.needsAttention, 3);

    // Verify full invoice records
    final conflictInvoice = await service.invoice('inv-conflict');
    expect(conflictInvoice!.status, 'conflict');
    expect(conflictInvoice.conflictCode, 'PRICE_MISMATCH');
    expect(conflictInvoice.conflictMessage, 'Price mismatch detected');
    expect(conflictInvoice.attempts, 3);

    final syncedInvoice = await service.invoice('inv-synced');
    expect(syncedInvoice!.status, 'synced');
    expect(syncedInvoice.serverResponse?['invoice_id'], 'srv-999');

    await service.close();
  });

  test('5. Encrypted database cannot be opened through ordinary unkeyed SQLite connection', () async {
    final service = OfflinePosService.instance;
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);
    await service.setMeta('confidential_note', 'POS local ledger secure');
    await service.close();

    // Plain unkeyed sqlite connection must fail with SqliteException
    final unkeyedDb = sqlite3.open(dbPath);
    expect(
      () => unkeyedDb.select('SELECT * FROM offline_meta;'),
      throwsA(isA<SqliteException>()),
    );
    unkeyedDb.close();
  });

  test('6. Incorrect or unavailable keys fail safely without overwriting data', () async {
    final service = OfflinePosService.instance;
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);
    await service.setMeta('vital_key', 'vital_data_12345');
    await service.close();

    // 1. Wrong key fails
    final wrongKeyDb = sqlite3.open(dbPath);
    wrongKeyDb.execute("PRAGMA key = \"x'0000000000000000000000000000000000000000000000000000000000000000'\";");
    expect(
      () => wrongKeyDb.select('SELECT * FROM offline_meta;'),
      throwsA(isA<SqliteException>()),
    );
    wrongKeyDb.close();

    // 2. Unavailable key throws PosDatabaseKeyMissingException without modifying database
    final emptyKeyStore = InMemoryPosDatabaseKeyStore();
    expect(
      () => PosDatabaseSecurityManager.ensureEncryptedAndOpen(
        databasePath: dbPath,
        keyStore: emptyKeyStore,
      ),
      throwsA(isA<PosDatabaseKeyMissingException>()),
    );

    // 3. Original data is intact when opened with correct key
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);
    final val = await service.getMeta('vital_key');
    expect(val, 'vital_data_12345');
    await service.close();
  });

  test('7. Interrupted migration recovers and retries safely', () async {
    // Create plaintext DB
    final plainDb = sqlite3.open(dbPath);
    plainDb.execute("CREATE TABLE offline_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL);");
    plainDb.execute("INSERT INTO offline_meta VALUES ('state', '\"pre_migration\"', '2026-11-24');");
    plainDb.close();

    // Simulate stale lock and leftover tmp file from crashed prior process
    final lockFile = File('$dbPath.migration.lock');
    await lockFile.writeAsString('{"stale": true}');
    // Artificially age the lock file by 15 minutes
    await lockFile.setLastModified(DateTime.now().subtract(const Duration(minutes: 15)));

    final tmpFile = File('$dbPath.migrating.tmp');
    await tmpFile.writeAsString('corrupted temp content');

    // Run migration
    final service = OfflinePosService.instance;
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);

    // Migration must have cleaned up the stale lock and temp file, and finished migration
    expect(await tmpFile.exists(), isFalse);
    expect(await lockFile.exists(), isFalse);

    final val = await service.getMeta('state');
    expect(val, 'pre_migration');
    expect(PosDatabaseSecurityManager.isPlaintextDatabase(dbPath), isFalse);
    await service.close();
  });

  test('8. Reopening the application successfully accesses encrypted database', () async {
    final service = OfflinePosService.instance;
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);
    await service.setMeta('session_token', 'offline-sess-99');
    await service.close();

    // Simulate second app launch
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);
    final token = await service.getMeta('session_token');
    expect(token, 'offline-sess-99');
    await service.close();
  });

  test('9. Backup and restore preserve encryption and data integrity', () async {
    final service = OfflinePosService.instance;
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);
    await service.setMeta('backup_anchor', 'state_at_backup');

    final backupFile = p.join(tempDir.path, 'encrypted_pos_backup.bak');
    await service.backupEncrypted(backupFile);

    // Verify backup exists and is encrypted
    expect(File(backupFile).existsSync(), isTrue);
    expect(PosDatabaseSecurityManager.isPlaintextDatabase(backupFile), isFalse);

    // Mutate active DB
    await service.setMeta('backup_anchor', 'state_mutated_after_backup');
    expect(await service.getMeta('backup_anchor'), 'state_mutated_after_backup');

    // Restore from backup
    await service.restoreEncrypted(backupFile);

    // Verify state restored
    expect(await service.getMeta('backup_anchor'), 'state_at_backup');
    await service.close();
  });

  test('10. WAL/checkpoint operations do not create unprotected database copies', () async {
    final service = OfflinePosService.instance;
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);

    // Perform multiple writes to populate WAL
    for (int i = 0; i < 50; i++) {
      await service.setMeta('wal_key_$i', 'wal_value_$i');
    }

    final walFile = File('$dbPath-wal');
    if (await walFile.exists() && await walFile.length() > 0) {
      final walBytes = await walFile.readAsBytes();
      // SQLCipher WAL files encrypt page frames and do not leak plaintext
      expect(utf8.decode(walBytes, allowMalformed: true), isNot(contains('wal_value_49')));
    }

    await service.close();
  });

  test('11. No plaintext temporary database remains after successful migration', () async {
    final plainDb = sqlite3.open(dbPath);
    plainDb.execute("CREATE TABLE offline_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL);");
    plainDb.execute("INSERT INTO offline_meta VALUES ('k', '\"v\"', '2026-11-24');");
    plainDb.close();

    final service = OfflinePosService.instance;
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);
    await service.close();

    // Check directory contents
    final files = tempDir.listSync();
    final fileNames = files.map((f) => p.basename(f.path)).toList();

    expect(fileNames, contains('thq_pos_offline_v486.sqlite'));
    expect(fileNames, isNot(contains('thq_pos_offline_v486.sqlite.plaintext.bak')));
    expect(fileNames, contains('thq_pos_offline_v486.sqlite.encrypted.bak'));
    expect(fileNames, isNot(contains('thq_pos_offline_v486.sqlite.migrating.tmp')));
    expect(fileNames, isNot(contains('thq_pos_offline_v486.sqlite.migration.lock')));
  });

  test('12. Existing POS offline billing and queue lifecycle methods work seamlessly with encryption', () async {
    final service = OfflinePosService.instance;
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);

    final product = InventoryProduct.fromMap({
      'product_id': 'p-cement',
      'variant_id': 'v-cement-50',
      'product_name': 'Ultra Cement',
      'variant_name': '50kg Bag',
      'selling_price': 400.0,
      'stock_quantity': 20.0,
      'sale_units': [
        {
          'unit_id': 'u-bag',
          'code': 'BAG',
          'name': 'Bag',
          'is_base': true,
          'conversion_to_base': 1.0,
          'sale_price': 400.0,
          'active': true,
        }
      ],
      'purchase_units': [],
      'identifiers': [],
      'search_codes': ['CEMENT50'],
    });

    final customer = Customer.fromMap({
      'customer_id': 'cust-regular',
      'customer_name': 'Ali Builders',
      'is_walk_in': false,
      'status': 'active',
    });

    await service.replaceCatalogue(
      tenantId: 't-99',
      locationId: 'loc-99',
      products: [product],
      customers: [customer],
      serials: [],
    );

    // Queue a sale
    final localNum = await service.queueSale(
      requestId: 'req-bill-001',
      tenantId: 't-99',
      locationId: 'loc-99',
      deviceId: 'dev-99',
      payload: {
        'items': [
          {
            'variant_id': 'v-cement-50',
            'quantity': 2.0,
            'base_quantity': 2.0,
            'price': 400.0,
          }
        ],
        'total': 800.0,
      },
      printRequested: true,
    );

    expect(localNum, startsWith('OFF-'));

    // Verify stock decremented in offline cache
    final updatedProducts = await service.cachedProducts(tenantId: 't-99', locationId: 'loc-99');
    expect(updatedProducts.first.stockQuantity, 18.0); // 20 - 2

    // Verify queue and state transitions
    await service.markSyncing('req-bill-001');
    var inv = await service.invoice('req-bill-001');
    expect(inv!.status, 'syncing');
    expect(inv.attempts, 1);

    await service.markConflict('req-bill-001', code: 'STOCK_LOCK', message: 'Online stock locked');
    inv = await service.invoice('req-bill-001');
    expect(inv!.status, 'conflict');
    expect(inv.conflictCode, 'STOCK_LOCK');

    await service.retry('req-bill-001');
    inv = await service.invoice('req-bill-001');
    expect(inv!.status, 'pending');

    await service.markSynced('req-bill-001', {'server_invoice_id': 'SRV-INV-555'});
    inv = await service.invoice('req-bill-001');
    expect(inv!.status, 'synced');
    expect(inv.serverResponse?['server_invoice_id'], 'SRV-INV-555');

    // Cancel test with stock restoration
    final cancelReqId = 'req-bill-002';
    await service.queueSale(
      requestId: cancelReqId,
      tenantId: 't-99',
      locationId: 'loc-99',
      deviceId: 'dev-99',
      payload: {
        'items': [
          {
            'variant_id': 'v-cement-50',
            'quantity': 3.0,
            'base_quantity': 3.0,
            'price': 400.0,
          }
        ],
        'total': 1200.0,
      },
      printRequested: false,
    );
    expect((await service.cachedProducts(tenantId: 't-99', locationId: 'loc-99')).first.stockQuantity, 15.0); // 18 - 3

    await service.cancel(cancelReqId);
    inv = await service.invoice(cancelReqId);
    expect(inv!.status, 'cancelled');
    // Stock restored!
    expect((await service.cachedProducts(tenantId: 't-99', locationId: 'loc-99')).first.stockQuantity, 18.0); // 15 + 3

    await service.close();
  });

  test('13. Key rotation via PRAGMA rekey safely re-encrypts database and updates key store', () async {
    final service = OfflinePosService.instance;
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);
    await service.setMeta('rotate_test', 'persisted_before_rekey');

    final oldKey = await keyStore.readKey(keyName: PosDatabaseSecurityManager.defaultKeyName);
    expect(oldKey, isNotNull);

    final newKey = PosDatabaseKeyStore.generateSecureKeyHex();
    expect(newKey, isNot(oldKey));

    await service.rotateKey(newKey);
    await service.close();

    // Verify database opens with new key
    final newKeyStore = InMemoryPosDatabaseKeyStore({PosDatabaseSecurityManager.defaultKeyName: newKey});
    await service.initialize(customDatabasePath: dbPath, keyStore: newKeyStore);
    expect(await service.getMeta('rotate_test'), 'persisted_before_rekey');
    await service.close();

    // Verify database CANNOT open with old key
    final oldKeyStore = InMemoryPosDatabaseKeyStore({PosDatabaseSecurityManager.defaultKeyName: oldKey!});
    expect(
      () => service.initialize(customDatabasePath: dbPath, keyStore: oldKeyStore),
      throwsA(isA<PosDatabaseEncryptionException>()),
    );
  });

  test('14. Successful migration followed by complete plaintext backup cleanup', () async {
    final plainDb = sqlite3.open(dbPath);
    plainDb.execute("CREATE TABLE offline_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL);");
    plainDb.execute("INSERT INTO offline_meta VALUES ('secret_k', '\"secret_v\"', '2026-11-24');");
    plainDb.close();

    final service = OfflinePosService.instance;
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);

    // Verify database is functional and encrypted
    expect(await service.getMeta('secret_k'), 'secret_v');
    expect(PosDatabaseSecurityManager.isPlaintextDatabase(dbPath), isFalse);
    await service.close();

    // Verify all plaintext copies and temporary migration files are gone
    expect(File('$dbPath.plaintext.bak').existsSync(), isFalse);
    expect(File('$dbPath.plaintext.bak-wal').existsSync(), isFalse);
    expect(File('$dbPath.plaintext.bak-shm').existsSync(), isFalse);
    expect(File('$dbPath.migrating.tmp').existsSync(), isFalse);
    expect(File('$dbPath.migration.lock').existsSync(), isFalse);

    // Verify encrypted backup is present and valid
    final encBak = File('$dbPath.encrypted.bak');
    expect(encBak.existsSync(), isTrue);
    expect(PosDatabaseSecurityManager.isPlaintextDatabase(encBak.path), isFalse);
  });

  test('15. Interrupted migration preserves recoverability across failure points', () async {
    // Scenario A: Process crashed after swap, leaving primary DB damaged and plaintext backup intact
    final backupPath = '$dbPath.plaintext.bak';
    final plainDb = sqlite3.open(backupPath);
    plainDb.execute("CREATE TABLE offline_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL);");
    plainDb.execute("INSERT INTO offline_meta VALUES ('recover_key', '\"recover_val\"', '2026-11-24');");
    plainDb.close();

    // Damaged primary DB
    await File(dbPath).writeAsString('corrupted broken sqlite data');

    final keyHex = PosDatabaseKeyStore.generateSecureKeyHex();
    await keyStore.writeKey(keyName: PosDatabaseSecurityManager.defaultKeyName, keyHex: keyHex);

    // Recovery runs on initialization
    final service = OfflinePosService.instance;
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);

    // Verify recovered and migrated
    expect(await service.getMeta('recover_key'), 'recover_val');
    expect(PosDatabaseSecurityManager.isPlaintextDatabase(dbPath), isFalse);
    expect(File(backupPath).existsSync(), isFalse);
    await service.close();

    // Scenario B: Process crashed after swap and primary DB was already verified valid
    // Create an unverified leftover .plaintext.bak next to the working encrypted DB
    await File(backupPath).writeAsString('leftover plaintext that should be cleaned up');
    await PosDatabaseSecurityManager.recoverInterruptedMigration(databasePath: dbPath, keyHex: keyHex);

    // Obsolete plaintext backup must be securely cleaned up because primary DB is valid
    expect(File(backupPath).existsSync(), isFalse);
  });

  test('16. Failed encrypted verification after swap preserves and rolls back to original database', () async {
    final plainDb = sqlite3.open(dbPath);
    plainDb.execute("CREATE TABLE offline_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL);");
    plainDb.execute("INSERT INTO offline_meta VALUES ('original_data', '\"untouched\"', '2026-11-24');");
    plainDb.close();

    final keyHex = PosDatabaseKeyStore.generateSecureKeyHex();

    // Migrate with a hook that injects verification failure after swap
    await expectLater(
      PosDatabaseSecurityManager.migratePlaintextToEncrypted(
        databasePath: dbPath,
        keyHex: keyHex,
        testHook: (stage, path) {
          if (stage == 'post_swap_verified') {
            throw const PosDatabaseMigrationException('Simulated post-swap verification error');
          }
        },
      ),
      throwsA(isA<PosDatabaseMigrationException>()),
    );

    // Database must be rolled back to original plaintext!
    expect(PosDatabaseSecurityManager.isPlaintextDatabase(dbPath), isTrue);

    final checkDb = sqlite3.open(dbPath);
    final rows = checkDb.select("SELECT value FROM offline_meta WHERE key='original_data';");
    expect(rows.first['value'], '"untouched"');
    checkDb.close();

    // Temporary migration artifacts must not leave unhandled locks
    expect(File('$dbPath.migrating.tmp').existsSync(), isFalse);
  });

  test('17. Plaintext cleanup failure is detected and reported via PosDatabasePlaintextCleanupException', () async {
    final plainDb = sqlite3.open(dbPath);
    plainDb.execute("CREATE TABLE offline_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL);");
    plainDb.execute("INSERT INTO offline_meta VALUES ('cleanup_detect', '\"val\"', '2026-11-24');");
    plainDb.close();

    final keyHex = PosDatabaseKeyStore.generateSecureKeyHex();

    // Migrate with hook that simulates cleanup failure
    await expectLater(
      PosDatabaseSecurityManager.migratePlaintextToEncrypted(
        databasePath: dbPath,
        keyHex: keyHex,
        testHook: (stage, path) {
          if (stage == 'cleanup_file') {
            throw FileSystemException('Access denied by OS test harness', path);
          }
        },
      ),
      throwsA(isA<PosDatabasePlaintextCleanupException>()),
    );

    // The primary database at dbPath was already verified and is encrypted
    expect(PosDatabaseSecurityManager.isPlaintextDatabase(dbPath), isFalse);
  });

  test('18. Encrypted recovery backup remains fully usable for database recovery', () async {
    final service = OfflinePosService.instance;
    final plainDb = sqlite3.open(dbPath);
    plainDb.execute("CREATE TABLE offline_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL);");
    plainDb.execute("INSERT INTO offline_meta VALUES ('pre_migration_state', '\"pristine\"', '2026-11-24');");
    plainDb.close();

    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);
    await service.setMeta('mutated_after_migration', 'modified');
    await service.close();

    final encBak = File('$dbPath.encrypted.bak');
    expect(encBak.existsSync(), isTrue);
    expect(PosDatabaseSecurityManager.isPlaintextDatabase(encBak.path), isFalse);

    // Restore from encrypted recovery backup
    await service.restoreEncrypted(encBak.path);

    expect(await service.getMeta('pre_migration_state'), 'pristine');
    expect(await service.getMeta('mutated_after_migration'), isNull);
    await service.close();
  });
}
