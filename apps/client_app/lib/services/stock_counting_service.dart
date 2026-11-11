import 'dart:async';

import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service orchestrating Physical Stock Counting & Reconciliation (Phase 9).
///
/// Communicates with validated Supabase RPCs:
/// - `inventory_stock_count_snapshot_v485`
/// - `inventory_stock_count_post_v485`
/// - `stock_counts_list_v485`
/// - `stock_count_detail_v485`
class StockCountingService {
  StockCountingService._();
  static final StockCountingService instance = StockCountingService._();

  RpcCaller? _customRpc;

  /// Injects a custom RPC caller for automated testing.
  void setCustomRpc(RpcCaller? caller) {
    _customRpc = caller;
  }

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<dynamic> _invokeRpc(String fn, {Map<String, dynamic>? params}) async {
    if (_customRpc != null) {
      return _customRpc!(fn, params: params);
    }
    return _supabase.rpc(fn, params: params);
  }

  /// Captures a live system stock snapshot for a business location.
  Future<List<StockCountItem>> fetchSnapshot({
    required String tenantId,
    required String locationId,
    String query = '',
  }) async {
    final result = await _invokeRpc(
      'inventory_stock_count_snapshot_v485',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_query': query.trim(),
      },
    );

    if (result is List) {
      return result
          .whereType<Map>()
          .map((e) => StockCountItem.fromSnapshotMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  /// Posts an approved physical stock count, creating ledger adjustments and updating balances.
  ///
  /// Guarantees idempotency via [requestId].
  Future<Map<String, dynamic>> postStockCount({
    required String tenantId,
    required String locationId,
    required List<Map<String, dynamic>> items,
    String notes = '',
    String? deviceId,
    required String requestId,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('Cannot post an empty stock count.');
    }

    final result = await _invokeRpc(
      'inventory_stock_count_post_v485',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_items': items,
        'p_notes': notes.trim().isEmpty ? null : notes.trim(),
        'p_device_id': deviceId,
        'p_request_id': requestId,
      },
    );

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    throw StateError('Unexpected response from inventory_stock_count_post_v485: $result');
  }

  /// Lists historical stock count sessions for audit and reconciliation verification.
  Future<List<StockCountAuditRecord>> listPastCounts({
    required String tenantId,
    String? locationId,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    final result = await _invokeRpc(
      'stock_counts_list_v485',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_from': from?.toIso8601String().substring(0, 10),
        'p_to': to?.toIso8601String().substring(0, 10),
        'p_limit': limit,
      },
    );

    if (result is List) {
      return result
          .whereType<Map>()
          .map((e) => StockCountAuditRecord.fromRpcMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  /// Retrieves full line-item details for an audit count session.
  Future<Map<String, dynamic>> getCountDetail({
    required String tenantId,
    required String countId,
  }) async {
    final result = await _invokeRpc(
      'stock_count_detail_v485',
      params: {
        'p_tenant_id': tenantId,
        'p_count_id': countId,
      },
    );

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return const {};
  }

  /// Checks for concurrent inventory movements between snapshot capture and post.
  ///
  /// Returns a map of variantId -> description if live system stock moved during counting.
  Future<Map<String, double>> checkConcurrentStockChanges({
    required String tenantId,
    required String locationId,
    required List<StockCountItem> originalItems,
  }) async {
    try {
      final currentSnapshot = await fetchSnapshot(
        tenantId: tenantId,
        locationId: locationId,
      );

      final currentMap = {
        for (final item in currentSnapshot) item.variantId: item.systemQuantity,
      };

      final changes = <String, double>{};
      for (final orig in originalItems) {
        final currentQty = currentMap[orig.variantId];
        if (currentQty != null && (currentQty - orig.systemQuantity).abs() > 0.0001) {
          changes[orig.variantId] = currentQty;
        }
      }
      return changes;
    } catch (_) {
      return const {};
    }
  }
}
