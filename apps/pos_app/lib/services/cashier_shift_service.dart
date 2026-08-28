import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class CashierShiftService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>?> current({
    required String tenantId,
    required String deviceId,
  }) async {
    final result = await _supabase.rpc(
      'cashier_shift_current_v472',
      params: {'p_tenant_id': tenantId, 'p_device_id': deviceId},
    );
    if (result == null) return null;
    if (result is Map) {
      final row = Map<String, dynamic>.from(result);
      return row.isEmpty ? null : row;
    }
    if (result is List && result.isNotEmpty) {
      final row = Map<String, dynamic>.from(result.first as Map);
      return row.isEmpty ? null : row;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> history({
    required String tenantId,
    required String deviceId,
    DateTime? from,
    DateTime? to,
    int limit = 50,
  }) async {
    final now = DateTime.now();
    final result = await _supabase.rpc(
      'cashier_shift_history_v472',
      params: {
        'p_tenant_id': tenantId,
        'p_device_id': deviceId,
        'p_from': _date(from ?? now.subtract(const Duration(days: 30))),
        'p_to': _date(to ?? now),
        'p_limit': limit,
      },
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<Map<String, dynamic>> open({
    required String tenantId,
    required String locationId,
    required String deviceId,
    required double openingCash,
    required DateTime openedAt,
    String note = '',
  }) async {
    final result = await _supabase.rpc(
      'cashier_shift_open_v472',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_device_id': deviceId,
        'p_opening_cash': openingCash,
        'p_opened_at': openedAt.toIso8601String(),
        'p_note': note.trim(),
        'p_request_id': const Uuid().v4(),
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<void> cashMove({
    required String tenantId,
    required String shiftId,
    required String type,
    required double amount,
    required String note,
  }) async {
    await _supabase.rpc(
      'cashier_shift_cash_move_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_shift_id': shiftId,
        'p_type': type,
        'p_amount': amount,
        'p_note': note.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> close({
    required String tenantId,
    required String shiftId,
    required double declaredCash,
    required DateTime closedAt,
    required String note,
  }) async {
    final result = await _supabase.rpc(
      'cashier_shift_close_v472',
      params: {
        'p_tenant_id': tenantId,
        'p_shift_id': shiftId,
        'p_declared_cash': declaredCash,
        'p_closed_at': closedAt.toIso8601String(),
        'p_note': note.trim(),
        'p_request_id': const Uuid().v4(),
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> edit({
    required String tenantId,
    required String shiftId,
    required DateTime openedAt,
    required double openingCash,
    DateTime? closedAt,
    double? declaredCash,
    String note = '',
    required String reason,
  }) async {
    final result = await _supabase.rpc(
      'cashier_shift_edit_v472',
      params: {
        'p_tenant_id': tenantId,
        'p_shift_id': shiftId,
        'p_opened_at': openedAt.toIso8601String(),
        'p_opening_cash': openingCash,
        'p_closed_at': closedAt?.toIso8601String(),
        'p_declared_cash': declaredCash,
        'p_note': note.trim(),
        'p_reason': reason.trim(),
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> edits({
    required String tenantId,
    required String shiftId,
  }) async {
    final result = await _supabase.rpc(
      'cashier_shift_edits_v472',
      params: {'p_tenant_id': tenantId, 'p_shift_id': shiftId},
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
