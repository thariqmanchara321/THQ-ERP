import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pos_session.dart';
import 'gst_v520_route_guard.dart';
import 'mobile_pos_local_store.dart';

class MobileSyncResult {
  final int attempted;
  final int synced;
  final int conflicts;
  final int pending;

  const MobileSyncResult(
    this.attempted,
    this.synced,
    this.conflicts,
    this.pending,
  );
}

class MobilePosSyncService {
  final MobilePosLocalStore _local = MobilePosLocalStore.instance;
  final GstV520RouteGuard _guard = GstV520RouteGuard();
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<void> refreshCatalogue(PosSession session) async {
    await _guard.route(
      tenantId: session.tenantId,
      channel: 'mobile_pos',
      routeKey: 'api_contract',
      deviceId: session.deviceId,
    );

    final productRaw = await _supabase.rpc(
      'mobile_pos_product_cache_v520',
      params: {
        'p_tenant_id': session.tenantId,
        'p_device_id': session.deviceId,
      },
    );
    final customerRaw = await _supabase.rpc(
      'pos_offline_customer_cache_v486',
      params: {
        'p_tenant_id': session.tenantId,
        'p_device_id': session.deviceId,
      },
    );
    final manifestRaw = await _supabase.rpc(
      'mobile_pos_cache_manifest_v520',
      params: {
        'p_tenant_id': session.tenantId,
        'p_device_id': session.deviceId,
      },
    );

    final serials = <Map<String, dynamic>>[];
    var after = '';
    for (var page = 0; page < 100; page++) {
      final raw = await _supabase.rpc(
        'pos_offline_available_serials_v486',
        params: {
          'p_tenant_id': session.tenantId,
          'p_device_id': session.deviceId,
          'p_after': after,
          'p_limit': 1000,
        },
      );
      final rows = (raw as List? ?? const [])
          .whereType<Map>()
          .map((x) => Map<String, dynamic>.from(x))
          .toList();
      serials.addAll(rows);
      if (rows.length < 1000) break;
      after = rows.last['serial_number']?.toString() ?? '';
      if (after.isEmpty) break;
    }

    await _local.replaceCatalogue(
      tenantId: session.tenantId,
      locationId: session.locationId,
      products: (productRaw as List? ?? const [])
          .whereType<Map>()
          .map((x) => Map<String, dynamic>.from(x))
          .toList(),
      customers: (customerRaw as List? ?? const [])
          .whereType<Map>()
          .map((x) => Map<String, dynamic>.from(x))
          .toList(),
      serials: serials,
      manifest: manifestRaw is Map
          ? Map<String, dynamic>.from(manifestRaw)
          : <String, dynamic>{},
    );
  }

  Future<MobileSyncResult> sync(
    PosSession session, {
    bool includeConflicts = false,
    String? only,
  }) async {
    final syncRpc = await _guard.route(
      tenantId: session.tenantId,
      channel: 'mobile_pos',
      routeKey: 'sale_sync',
      deviceId: session.deviceId,
    );

    final statuses = <String>{'pending', 'error'};
    if (includeConflicts) statuses.add('conflict');
    var rows = await _local.queue(
      session.tenantId,
      session.deviceId,
      statuses: statuses,
    );
    if (only != null) {
      rows = rows.where((x) => x.requestId == only).toList();
    }

    var synced = 0;
    var conflicts = 0;
    var pending = 0;

    for (final row in rows.reversed) {
      if (row.status == 'conflict') await _local.retry(row.requestId);
      await _local.markSyncing(row.requestId);
      try {
        final raw = await _supabase.rpc(
          syncRpc,
          params: {
            'p_tenant_id': session.tenantId,
            'p_device_id': session.deviceId,
            'p_location_id': session.locationId,
            'p_request_id': row.requestId,
            'p_payload': row.payload,
          },
        );
        final map = raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};

        if (map['ok'] == false || map['status'] == 'conflict') {
          await _local.markConflict(
            row.requestId,
            map['code']?.toString() ?? 'SERVER_VALIDATION',
            map['message']?.toString() ?? 'Server rejected invoice.',
          );
          conflicts++;
        } else {
          if (map['authoritative_gst'] == false ||
              map['gst_snapshot_id'] == null ||
              map['gst_journal_id'] == null) {
            throw StateError(
              'v5.2 Mobile POS sync is missing GST snapshot/journal evidence.',
            );
          }
          await _local.markSynced(row.requestId, map);
          synced++;
        }
      } catch (error) {
        await _local.markPending(row.requestId, error.toString());
        pending++;
        break;
      }
    }

    if (synced > 0) {
      try {
        await refreshCatalogue(session);
      } catch (_) {}
    }

    return MobileSyncResult(rows.length, synced, conflicts, pending);
  }
}
