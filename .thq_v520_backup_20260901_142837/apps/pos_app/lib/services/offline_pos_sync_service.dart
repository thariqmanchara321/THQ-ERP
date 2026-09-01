import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';
import '../models/customer.dart';
import '../models/inventory_product.dart';
import 'offline_pos_service.dart';
import 'pos_completion_service.dart';

class OfflineCatalogue {
  final List<InventoryProduct> products;
  final List<Customer> customers;
  final int serialCount;
  final Map<String, dynamic> manifest;

  const OfflineCatalogue({
    required this.products,
    required this.customers,
    required this.serialCount,
    required this.manifest,
  });
}

class OfflineSyncResult {
  final int attempted;
  final int synced;
  final int conflicts;
  final int pending;

  const OfflineSyncResult({
    required this.attempted,
    required this.synced,
    required this.conflicts,
    required this.pending,
  });
}

class OfflinePosSyncService {
  final OfflinePosService _local = OfflinePosService.instance;
  final PosCompletionService _completion = PosCompletionService();
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<OfflineCatalogue> refreshCatalogue(ClientSession session) async {
    final device = session.device;
    if (device == null) throw StateError('POS device context is required.');
    final tenantId = session.business.id;
    final productRaw = await _supabase.rpc(
      'pos_offline_product_cache_v486',
      params: {'p_tenant_id': tenantId, 'p_device_id': device.deviceId},
    );
    final customerRaw = await _supabase.rpc(
      'pos_offline_customer_cache_v486',
      params: {'p_tenant_id': tenantId, 'p_device_id': device.deviceId},
    );
    final manifestRaw = await _supabase.rpc(
      'pos_offline_cache_manifest_v486',
      params: {'p_tenant_id': tenantId, 'p_device_id': device.deviceId},
    );

    final products = (productRaw as List? ?? const [])
        .whereType<Map>()
        .map((row) => InventoryProduct.fromMap(Map<String, dynamic>.from(row)))
        .toList();
    final customers = (customerRaw as List? ?? const [])
        .whereType<Map>()
        .map((row) => Customer.fromMap(Map<String, dynamic>.from(row)))
        .toList();
    final manifest = manifestRaw is Map
        ? Map<String, dynamic>.from(manifestRaw)
        : <String, dynamic>{
            'tenant_id': tenantId,
            'device_id': device.deviceId,
            'location_id': device.locationId,
          };

    final serials = <Map<String, dynamic>>[];
    var after = '';
    const pageSize = 1000;
    while (true) {
      final raw = await _supabase.rpc(
        'pos_offline_available_serials_v486',
        params: {
          'p_tenant_id': tenantId,
          'p_device_id': device.deviceId,
          'p_after': after,
          'p_limit': pageSize,
        },
      );
      final page = (raw as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      serials.addAll(page);
      if (page.length < pageSize) break;
      final next = page.last['serial_number']?.toString() ?? '';
      if (next.isEmpty || next.toLowerCase() == after.toLowerCase()) break;
      after = next;
    }

    await _local.replaceCatalogue(
      tenantId: tenantId,
      locationId: device.locationId,
      products: products,
      customers: customers,
      serials: serials,
      manifest: manifest,
    );
    await _cacheInvoicePrinter(session);
    return OfflineCatalogue(
      products: await _local.cachedProducts(tenantId: tenantId, locationId: device.locationId),
      customers: await _local.cachedCustomers(tenantId: tenantId),
      serialCount: serials.length,
      manifest: manifest,
    );
  }

  Future<OfflineCatalogue> cachedCatalogue(ClientSession session) async {
    final device = session.device;
    if (device == null) throw StateError('POS device context is required.');
    final manifest = await _local.getMeta('manifest:${session.business.id}:${device.locationId}');
    return OfflineCatalogue(
      products: await _local.cachedProducts(tenantId: session.business.id, locationId: device.locationId),
      customers: await _local.cachedCustomers(tenantId: session.business.id),
      serialCount: 0,
      manifest: manifest is Map ? Map<String, dynamic>.from(manifest) : const <String, dynamic>{},
    );
  }

  Future<bool> hasVerifiedOpenShift(ClientSession session) async {
    final device = session.device;
    if (device == null) return false;
    final raw = await _local.getMeta('shift:${session.business.id}:${device.deviceId}');
    return raw is Map && raw.isNotEmpty;
  }

  Future<OfflineSyncResult> syncPending(
    ClientSession session, {
    bool includeConflicts = false,
    String? onlyRequestId,
  }) async {
    final device = session.device;
    if (device == null) throw StateError('POS device context is required.');
    final statuses = <String>{'pending', 'error'};
    if (includeConflicts) statuses.add('conflict');
    var rows = await _local.queue(
      tenantId: session.business.id,
      deviceId: device.deviceId,
      statuses: statuses,
    );
    if (onlyRequestId != null) {
      rows = rows.where((row) => row.requestId == onlyRequestId).toList();
    }
    var synced = 0;
    var conflicts = 0;
    var pending = 0;
    for (final record in rows.reversed) {
      if (record.status == 'conflict') await _local.retry(record.requestId);
      await _local.markSyncing(record.requestId);
      try {
        final result = await _supabase.rpc(
          'pos_offline_sale_sync_v486',
          params: {
            'p_tenant_id': session.business.id,
            'p_device_id': device.deviceId,
            'p_location_id': device.locationId,
            'p_request_id': record.requestId,
            'p_payload': record.payload,
          },
        );
        final map = result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};
        if (map['status']?.toString() == 'conflict' || map['ok'] == false) {
          await _local.markConflict(
            record.requestId,
            code: map['code']?.toString() ?? 'SERVER_VALIDATION',
            message: map['message']?.toString() ?? 'Server rejected the offline invoice.',
          );
          conflicts++;
        } else {
          await _local.markSynced(record.requestId, map);
          synced++;
        }
      } catch (error) {
        // A transport/API outage is not a failed sale. Keep the exact request queued.
        await _local.markPending(record.requestId, message: error.toString());
        pending++;
        break;
      }
    }
    if (synced > 0) {
      try {
        await refreshCatalogue(session);
      } catch (_) {
        // Queue state is already durable; catalogue refresh can wait for the next heartbeat.
      }
    }
    return OfflineSyncResult(
      attempted: rows.length,
      synced: synced,
      conflicts: conflicts,
      pending: pending,
    );
  }

  Future<void> _cacheInvoicePrinter(ClientSession session) async {
    final device = session.device;
    if (device == null) return;
    try {
      final profiles = await _completion.printerProfiles(
        tenantId: session.business.id,
        deviceId: device.deviceId,
      );
      Map<String, dynamic>? selected;
      for (final row in profiles) {
        if (row['purpose']?.toString() == 'invoice' && row['active'] != false && row['is_default'] == true) {
          selected = row;
          break;
        }
      }
      selected ??= profiles
          .where((row) => row['purpose']?.toString() == 'invoice' && row['active'] != false)
          .cast<Map<String, dynamic>>()
          .firstOrNull;
      if (selected != null) {
        await _local.setMeta('printer:${session.business.id}:${device.deviceId}', selected);
      }
    } catch (_) {
      // Keep the last cached printer profile when the server/printer configuration is unavailable.
    }
  }
}
