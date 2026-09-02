import 'dart:convert';
import 'dart:io';

import 'package:erp_core/erp_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/customer.dart';
import '../models/inventory_product.dart';

class OfflineInvoiceRecord {
  final String requestId;
  final String localInvoiceNumber;
  final String status;
  final Map<String, dynamic> payload;
  final int attempts;
  final String? conflictCode;
  final String? conflictMessage;
  final Map<String, dynamic>? serverResponse;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool printRequested;

  const OfflineInvoiceRecord({
    required this.requestId,
    required this.localInvoiceNumber,
    required this.status,
    required this.payload,
    required this.attempts,
    required this.conflictCode,
    required this.conflictMessage,
    required this.serverResponse,
    required this.createdAt,
    required this.updatedAt,
    required this.printRequested,
  });
}

class OfflineQueueSummary {
  final int pending;
  final int conflict;
  final int error;
  final int synced;

  const OfflineQueueSummary({
    required this.pending,
    required this.conflict,
    required this.error,
    required this.synced,
  });

  int get needsAttention => pending + conflict + error;
}

class OfflinePosService {
  OfflinePosService._();
  static final OfflinePosService instance = OfflinePosService._();

  Database? _db;
  String? _databasePath;

  Future<void> initialize() async {
    if (_db != null) return;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'THQ ERP', 'POS'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _databasePath = p.join(dir.path, 'thq_pos_offline_v486.sqlite');
    final db = sqlite3.open(_databasePath!);
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('PRAGMA synchronous=FULL;');
    db.execute('PRAGMA foreign_keys=ON;');
    for (final statement in <String>[
      '''CREATE TABLE IF NOT EXISTS offline_meta(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS offline_products(
        tenant_id TEXT NOT NULL,
        location_id TEXT NOT NULL,
        variant_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        available_quantity REAL NOT NULL DEFAULT 0,
        refreshed_at TEXT NOT NULL,
        PRIMARY KEY(tenant_id,location_id,variant_id)
      )''',
      '''CREATE TABLE IF NOT EXISTS offline_customers(
        tenant_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        refreshed_at TEXT NOT NULL,
        PRIMARY KEY(tenant_id,customer_id)
      )''',
      '''CREATE TABLE IF NOT EXISTS offline_serials(
        tenant_id TEXT NOT NULL,
        location_id TEXT NOT NULL,
        serial_id TEXT NOT NULL,
        serial_number TEXT NOT NULL,
        variant_id TEXT NOT NULL,
        updated_at TEXT,
        reserved_request_id TEXT,
        PRIMARY KEY(tenant_id,serial_id),
        UNIQUE(tenant_id,serial_number)
      )''',
      '''CREATE TABLE IF NOT EXISTS offline_invoices(
        request_id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        location_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        local_invoice_number TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        conflict_code TEXT,
        conflict_message TEXT,
        server_response_json TEXT,
        print_requested INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''',
      'CREATE INDEX IF NOT EXISTS idx_offline_invoices_status ON offline_invoices(tenant_id,device_id,status,created_at)',
      'CREATE INDEX IF NOT EXISTS idx_offline_serials_variant ON offline_serials(tenant_id,location_id,variant_id,reserved_request_id)',
    ]) {
      db.execute(statement);
    }
    _db = db;
  }

  String? get databasePath => _databasePath;

  Database get _database {
    final value = _db;
    if (value == null) {
      throw StateError('Offline POS database is not initialized.');
    }
    return value;
  }

  Future<void> setMeta(String key, Object? value) async {
    await initialize();
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute(
      'INSERT INTO offline_meta(key,value,updated_at) VALUES(?,?,?) '
      'ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated_at=excluded.updated_at',
      [key, jsonEncode(value), now],
    );
  }

  Future<dynamic> getMeta(String key) async {
    await initialize();
    final rows = _database.select(
      'SELECT value FROM offline_meta WHERE key=?',
      [key],
    );
    if (rows.isEmpty) return null;
    try {
      return jsonDecode(rows.first['value'] as String);
    } catch (_) {
      return rows.first['value'];
    }
  }

  Future<void> replaceCatalogue({
    required String tenantId,
    required String locationId,
    required List<InventoryProduct> products,
    required List<Customer> customers,
    required List<Map<String, dynamic>> serials,
    Map<String, dynamic>? manifest,
  }) async {
    await initialize();
    final db = _database;
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute(
        'DELETE FROM offline_products WHERE tenant_id=? AND location_id=?',
        [tenantId, locationId],
      );
      final productStmt = db.prepare(
        'INSERT INTO offline_products(tenant_id,location_id,variant_id,payload_json,available_quantity,refreshed_at) VALUES(?,?,?,?,?,?)',
      );
      try {
        for (final product in products) {
          productStmt.execute([
            tenantId,
            locationId,
            product.variantId,
            jsonEncode(_productMap(product)),
            product.stockQuantity,
            now,
          ]);
        }
      } finally {
        productStmt.close();
      }

      db.execute('DELETE FROM offline_customers WHERE tenant_id=?', [tenantId]);
      final customerStmt = db.prepare(
        'INSERT INTO offline_customers(tenant_id,customer_id,payload_json,refreshed_at) VALUES(?,?,?,?)',
      );
      try {
        for (final customer in customers) {
          customerStmt.execute([
            tenantId,
            customer.id,
            jsonEncode(_customerMap(customer)),
            now,
          ]);
        }
      } finally {
        customerStmt.close();
      }

      db.execute(
        'DELETE FROM offline_serials WHERE tenant_id=? AND location_id=?',
        [tenantId, locationId],
      );
      final serialStmt = db.prepare(
        'INSERT INTO offline_serials(tenant_id,location_id,serial_id,serial_number,variant_id,updated_at,reserved_request_id) VALUES(?,?,?,?,?,?,NULL)',
      );
      try {
        for (final serial in serials) {
          final serialNumber = serial['serial_number']?.toString().trim() ?? '';
          final serialId =
              serial['serial_id']?.toString() ?? serial['id']?.toString() ?? '';
          final variantId = serial['variant_id']?.toString() ?? '';
          if (serialNumber.isEmpty || serialId.isEmpty || variantId.isEmpty) {
            continue;
          }
          serialStmt.execute([
            tenantId,
            locationId,
            serialId,
            serialNumber,
            variantId,
            serial['updated_at']?.toString(),
          ]);
        }
      } finally {
        serialStmt.close();
      }

      _reapplyUnsyncedReservations(db, tenantId, locationId);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    await setMeta('catalogue:$tenantId:$locationId:last_refresh', now);
    if (manifest != null) {
      await setMeta('manifest:$tenantId:$locationId', manifest);
      await setMeta(
        'shift:$tenantId:${manifest['device_id'] ?? ''}',
        manifest['current_shift'],
      );
    }
  }

  Future<List<InventoryProduct>> cachedProducts({
    required String tenantId,
    required String locationId,
  }) async {
    await initialize();
    final rows = _database.select(
      'SELECT payload_json,available_quantity FROM offline_products WHERE tenant_id=? AND location_id=? ORDER BY variant_id',
      [tenantId, locationId],
    );
    return rows.map((row) {
      final map = Map<String, dynamic>.from(
        jsonDecode(row['payload_json'] as String) as Map,
      );
      final available = (row['available_quantity'] as num).toDouble();
      map['stock_quantity'] = available < 0 ? 0.0 : available;
      return InventoryProduct.fromMap(map);
    }).toList();
  }

  Future<List<Customer>> cachedCustomers({required String tenantId}) async {
    await initialize();
    final rows = _database.select(
      'SELECT payload_json FROM offline_customers WHERE tenant_id=? ORDER BY customer_id',
      [tenantId],
    );
    return rows
        .map(
          (row) => Customer.fromMap(
            Map<String, dynamic>.from(
              jsonDecode(row['payload_json'] as String) as Map,
            ),
          ),
        )
        .toList();
  }

  Future<Map<String, dynamic>?> findAvailableSerial({
    required String tenantId,
    required String locationId,
    required String serialNumber,
  }) async {
    await initialize();
    final rows = _database.select(
      'SELECT serial_id,serial_number,variant_id,updated_at FROM offline_serials '
      'WHERE tenant_id=? AND location_id=? AND lower(serial_number)=lower(?) AND reserved_request_id IS NULL LIMIT 1',
      [tenantId, locationId, serialNumber.trim()],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'serial_id': row['serial_id'],
      'serial_number': row['serial_number'],
      'variant_id': row['variant_id'],
      'updated_at': row['updated_at'],
      'status': 'in_stock',
      'current_location_id': locationId,
    };
  }

  Future<String> queueSale({
    required String requestId,
    required String tenantId,
    required String locationId,
    required String deviceId,
    required Map<String, dynamic> payload,
    required bool printRequested,
  }) async {
    await initialize();
    final db = _database;
    final existing = db.select(
      'SELECT local_invoice_number FROM offline_invoices WHERE request_id=?',
      [requestId],
    );
    if (existing.isNotEmpty) {
      return existing.first['local_invoice_number'] as String;
    }
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}-${now.millisecond.toString().padLeft(3, '0')}';
    final localNumber = 'OFF-$stamp';
    final payloadWithLocal = Map<String, dynamic>.from(payload)
      ..['local_invoice_number'] = localNumber;
    final iso = now.toUtc().toIso8601String();
    db.execute('BEGIN IMMEDIATE');
    try {
      _applyReservation(
        db,
        tenantId,
        locationId,
        requestId,
        payloadWithLocal,
        -1,
      );
      db.execute(
        'INSERT INTO offline_invoices(request_id,tenant_id,location_id,device_id,local_invoice_number,payload_json,status,attempts,print_requested,created_at,updated_at) '
        "VALUES(?,?,?,?,?,?,'pending',0,?,?,?)",
        [
          requestId,
          tenantId,
          locationId,
          deviceId,
          localNumber,
          jsonEncode(payloadWithLocal),
          printRequested ? 1 : 0,
          iso,
          iso,
        ],
      );
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return localNumber;
  }

  Future<List<OfflineInvoiceRecord>> queue({
    required String tenantId,
    required String deviceId,
    Set<String>? statuses,
    int limit = 500,
  }) async {
    await initialize();
    final statusList = statuses?.toList() ?? const <String>[];
    var sql =
        'SELECT * FROM offline_invoices WHERE tenant_id=? AND device_id=?';
    final args = <Object?>[tenantId, deviceId];
    if (statusList.isNotEmpty) {
      sql +=
          ' AND status IN (${List.filled(statusList.length, '?').join(',')})';
      args.addAll(statusList);
    }
    sql += ' ORDER BY created_at DESC LIMIT ?';
    args.add(limit);
    return _database.select(sql, args).map(_invoiceFromRow).toList();
  }

  Future<OfflineInvoiceRecord?> invoice(String requestId) async {
    await initialize();
    final rows = _database.select(
      'SELECT * FROM offline_invoices WHERE request_id=? LIMIT 1',
      [requestId],
    );
    return rows.isEmpty ? null : _invoiceFromRow(rows.first);
  }

  Future<OfflineQueueSummary> summary({
    required String tenantId,
    required String deviceId,
  }) async {
    await initialize();
    final rows = _database.select(
      "SELECT status,count(*) AS c FROM offline_invoices WHERE tenant_id=? AND device_id=? GROUP BY status",
      [tenantId, deviceId],
    );
    final counts = <String, int>{};
    for (final row in rows) {
      counts[row['status'] as String] = (row['c'] as int?) ?? 0;
    }
    return OfflineQueueSummary(
      pending: (counts['pending'] ?? 0) + (counts['syncing'] ?? 0),
      conflict: counts['conflict'] ?? 0,
      error: counts['error'] ?? 0,
      synced: counts['synced'] ?? 0,
    );
  }

  Future<void> markSyncing(String requestId) async =>
      _setStatus(requestId, 'syncing', incrementAttempts: true);
  Future<void> markPending(String requestId, {String? message}) async =>
      _setStatus(requestId, 'pending', message: message);
  Future<void> markError(String requestId, String message) async =>
      _setStatus(requestId, 'error', message: message);

  Future<void> markConflict(
    String requestId, {
    required String code,
    required String message,
  }) async {
    await initialize();
    _database.execute(
      "UPDATE offline_invoices SET status='conflict',conflict_code=?,conflict_message=?,updated_at=? WHERE request_id=?",
      [code, message, DateTime.now().toUtc().toIso8601String(), requestId],
    );
  }

  Future<void> markSynced(
    String requestId,
    Map<String, dynamic> response,
  ) async {
    await initialize();
    _database.execute(
      "UPDATE offline_invoices SET status='synced',conflict_code=NULL,conflict_message=NULL,server_response_json=?,updated_at=? WHERE request_id=?",
      [
        jsonEncode(response),
        DateTime.now().toUtc().toIso8601String(),
        requestId,
      ],
    );
  }

  Future<void> retry(String requestId) async {
    await initialize();
    _database.execute(
      "UPDATE offline_invoices SET status='pending',conflict_code=NULL,conflict_message=NULL,updated_at=? WHERE request_id=? AND status IN ('conflict','error')",
      [DateTime.now().toUtc().toIso8601String(), requestId],
    );
  }

  Future<void> cancel(String requestId) async {
    await initialize();
    final db = _database;
    final rows = db.select(
      'SELECT tenant_id,location_id,payload_json,status FROM offline_invoices WHERE request_id=?',
      [requestId],
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    final status = row['status'] as String;
    if (status == 'synced' || status == 'cancelled') {
      throw StateError(
        status == 'synced'
            ? 'A synchronized invoice cannot be cancelled locally.'
            : 'Invoice is already cancelled.',
      );
    }
    final payload = Map<String, dynamic>.from(
      jsonDecode(row['payload_json'] as String) as Map,
    );
    db.execute('BEGIN IMMEDIATE');
    try {
      _applyReservation(
        db,
        row['tenant_id'] as String,
        row['location_id'] as String,
        requestId,
        payload,
        1,
      );
      db.execute(
        "UPDATE offline_invoices SET status='cancelled',conflict_code=NULL,conflict_message=NULL,updated_at=? WHERE request_id=?",
        [DateTime.now().toUtc().toIso8601String(), requestId],
      );
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> _setStatus(
    String requestId,
    String status, {
    String? message,
    bool incrementAttempts = false,
  }) async {
    await initialize();
    _database.execute(
      'UPDATE offline_invoices SET status=?,conflict_message=?,attempts=attempts+?,updated_at=? WHERE request_id=?',
      [
        status,
        message,
        incrementAttempts ? 1 : 0,
        DateTime.now().toUtc().toIso8601String(),
        requestId,
      ],
    );
  }

  void _reapplyUnsyncedReservations(
    Database db,
    String tenantId,
    String locationId,
  ) {
    final rows = db.select(
      "SELECT request_id,payload_json FROM offline_invoices WHERE tenant_id=? AND location_id=? AND status IN ('pending','syncing','conflict','error') ORDER BY created_at",
      [tenantId, locationId],
    );
    for (final row in rows) {
      final payload = Map<String, dynamic>.from(
        jsonDecode(row['payload_json'] as String) as Map,
      );
      _applyReservation(
        db,
        tenantId,
        locationId,
        row['request_id'] as String,
        payload,
        -1,
        strictSerial: false,
      );
    }
  }

  void _applyReservation(
    Database db,
    String tenantId,
    String locationId,
    String requestId,
    Map<String, dynamic> payload,
    int direction, {
    bool strictSerial = true,
  }) {
    final items = (payload['items'] as List? ?? const []).whereType<Map>();
    for (final raw in items) {
      final item = Map<String, dynamic>.from(raw);
      final variantId = item['variant_id']?.toString() ?? '';
      if (variantId.isEmpty) continue;
      final baseQty = _number(
        item['base_quantity'],
        _number(item['quantity']) * _number(item['conversion_to_base'], 1),
      );
      if (baseQty > 0) {
        if (direction < 0) {
          final stock = db.select(
            'SELECT available_quantity FROM offline_products WHERE tenant_id=? AND location_id=? AND variant_id=?',
            [tenantId, locationId, variantId],
          );
          if (stock.isNotEmpty &&
              (stock.first['available_quantity'] as num).toDouble() + 0.000001 <
                  baseQty) {
            throw StateError('Not enough offline stock for this product.');
          }
        }
        db.execute(
          'UPDATE offline_products SET available_quantity=available_quantity+(? * ?) WHERE tenant_id=? AND location_id=? AND variant_id=?',
          [direction, baseQty, tenantId, locationId, variantId],
        );
      }
      final serials = (item['serial_numbers'] as List? ?? const [])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty);
      for (final serial in serials) {
        if (direction < 0) {
          final changed = db.select(
            'SELECT serial_id FROM offline_serials WHERE tenant_id=? AND location_id=? AND lower(serial_number)=lower(?) AND reserved_request_id IS NULL',
            [tenantId, locationId, serial],
          );
          if (changed.isEmpty) {
            if (strictSerial) {
              throw StateError(
                'Serial $serial is not available in the offline cache.',
              );
            }
            continue;
          }
          db.execute(
            'UPDATE offline_serials SET reserved_request_id=? WHERE tenant_id=? AND location_id=? AND lower(serial_number)=lower(?) AND reserved_request_id IS NULL',
            [requestId, tenantId, locationId, serial],
          );
        } else {
          db.execute(
            'UPDATE offline_serials SET reserved_request_id=NULL WHERE tenant_id=? AND location_id=? AND lower(serial_number)=lower(?) AND reserved_request_id=?',
            [tenantId, locationId, serial, requestId],
          );
        }
      }
    }
  }

  OfflineInvoiceRecord _invoiceFromRow(Row row) {
    Map<String, dynamic>? server;
    final serverJson = row['server_response_json']?.toString();
    if (serverJson != null && serverJson.isNotEmpty) {
      try {
        server = Map<String, dynamic>.from(jsonDecode(serverJson) as Map);
      } catch (_) {
        server = null;
      }
    }
    return OfflineInvoiceRecord(
      requestId: row['request_id'] as String,
      localInvoiceNumber: row['local_invoice_number'] as String,
      status: row['status'] as String,
      payload: Map<String, dynamic>.from(
        jsonDecode(row['payload_json'] as String) as Map,
      ),
      attempts: (row['attempts'] as int?) ?? 0,
      conflictCode: row['conflict_code']?.toString(),
      conflictMessage: row['conflict_message']?.toString(),
      serverResponse: server,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
      printRequested: ((row['print_requested'] as int?) ?? 0) == 1,
    );
  }

  double _number(dynamic value, [double fallback = 0]) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? fallback;

  Map<String, dynamic> _productMap(InventoryProduct product) => {
    'product_id': product.productId,
    'variant_id': product.variantId,
    'product_name': product.productName,
    'variant_name': product.variantName,
    'item_type': product.itemType,
    'category_name': product.categoryName,
    'brand_name': product.brandName,
    'unit_name': product.unitName,
    'unit_code': product.unitCode,
    'base_unit_code': product.baseUnitCode,
    'base_unit': {
      'code': product.baseUnitCode,
      'name': product.baseUnitName,
      'allow_fractional': product.allowFractional,
      'quantity_step': product.quantityStep,
    },
    'sale_units': product.saleUnits.map(_unitMap).toList(),
    'purchase_units': product.purchaseUnits.map(_unitMap).toList(),
    'sku': product.sku,
    'barcode': product.barcode,
    'part_number': product.partNumber,
    'identifiers': product.identifiers
        .map(
          (e) => {
            'identifier_id': e.id,
            'variant_id': e.variantId,
            'identifier_type': e.type,
            'code': e.code,
            'supplier_id': e.supplierId,
            'supplier_name': e.supplierName,
            'label': e.label,
            'is_primary': e.isPrimary,
            'generated': e.generated,
            'active': e.active,
          },
        )
        .toList(),
    'search_codes': product.searchCodes,
    'cost_price': product.costPrice,
    'selling_price': product.sellingPrice,
    'list_price': product.listPrice,
    'tax_rate': product.taxRate,
    'reorder_level': product.reorderLevel,
    'stock_quantity': product.stockQuantity,
    'tracking_mode': product.trackingMode,
    'tracked_stock_quantity': product.trackedStockQuantity,
    'product_status': product.productStatus,
    'variant_status': product.variantStatus,
    'updated_at': product.updatedAt?.toUtc().toIso8601String(),
  };

  Map<String, dynamic> _unitMap(ProductUnitOption unit) => {
    'unit_id': unit.unitId,
    'code': unit.code,
    'name': unit.name,
    'decimal_places': unit.decimalPlaces,
    'allow_fractional': unit.allowFractional,
    'is_base': unit.isBase,
    'allow_purchase': unit.allowPurchase,
    'allow_sale': unit.allowSale,
    'is_default_purchase': unit.isDefaultPurchase,
    'is_default_sale': unit.isDefaultSale,
    'conversion_to_base': unit.conversionToBase,
    'quantity_step': unit.quantityStep,
    'sale_price': unit.salePrice,
    'purchase_cost': unit.purchaseCost,
    'cutting_allowed': unit.cuttingAllowed,
    'cutting_charge': unit.cuttingCharge,
    'active': unit.active,
  };

  Map<String, dynamic> _customerMap(Customer customer) => {
    'customer_id': customer.id,
    'customer_name': customer.name,
    'public_id': customer.publicId,
    'contact_person': customer.contactPerson,
    'phone': customer.phone,
    'email': customer.email,
    'tax_number': customer.taxNumber,
    'address_line1': customer.addressLine1,
    'address_line2': customer.addressLine2,
    'city': customer.city,
    'state': customer.state,
    'postal_code': customer.postalCode,
    'country': customer.country,
    'credit_limit': customer.creditLimit,
    'price_list_id': customer.priceListId,
    'price_list_name': customer.priceListName,
    'notes': customer.notes,
    'is_walk_in': customer.isWalkIn,
    'status': customer.status,
    'created_at': customer.createdAt?.toUtc().toIso8601String(),
    'updated_at': customer.updatedAt?.toUtc().toIso8601String(),
  };
}
