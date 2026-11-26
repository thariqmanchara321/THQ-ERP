import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pos_session.dart';
import 'gst_v520_route_guard.dart';
import 'mobile_pos_local_store.dart';

class MobileSyncResult extends OfflineSyncResult {
  const MobileSyncResult(
    super.attempted,
    super.synced,
    super.conflicts,
    super.pending,
  ) : super.positional();
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

  bool isSyncInProgress(PosSession session) =>
      OfflineSyncCoordinator.isSyncLocked(session.tenantId, session.deviceId);

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

    final coordinator = OfflineSyncCoordinator(storage: _local);

    final result = await coordinator.syncQueue(
      tenantId: session.tenantId,
      locationId: session.locationId,
      deviceId: session.deviceId,
      includeConflicts: includeConflicts,
      onlyRequestId: only,
      rpcExecutor: ({
        required String tenantId,
        required String locationId,
        required String deviceId,
        required String requestId,
        required Map<String, dynamic> payload,
      }) async {
        return await _supabase.rpc(
          syncRpc,
          params: {
            'p_tenant_id': tenantId,
            'p_device_id': deviceId,
            'p_location_id': locationId,
            'p_request_id': requestId,
            'p_payload': payload,
          },
        );
      },
    );

    if (result.synced > 0) {
      try {
        await refreshCatalogue(session);
      } catch (_) {}
    }

    return MobileSyncResult(
      result.attempted,
      result.synced,
      result.conflicts,
      result.pending,
    );
  }
}
