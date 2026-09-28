import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/pos_session.dart';

class MobileCashierShiftService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Map<String, dynamic> _map(dynamic raw) => raw is Map
      ? Map<String, dynamic>.from(raw)
      : <String, dynamic>{};

  Future<Map<String, dynamic>> current(PosSession session) async => _map(
        await _supabase.rpc(
          'cashier_shift_current_v472',
          params: {
            'p_tenant_id': session.tenantId,
            'p_device_id': session.deviceId,
          },
        ),
      );

  Future<Map<String, dynamic>> open(
    PosSession session, {
    required double openingCash,
    String note = '',
  }) async =>
      _map(
        await _supabase.rpc(
          'cashier_shift_open_v472',
          params: {
            'p_tenant_id': session.tenantId,
            'p_location_id': session.locationId,
            'p_device_id': session.deviceId,
            'p_opening_cash': openingCash,
            'p_opened_at': DateTime.now().toUtc().toIso8601String(),
            'p_note': note,
            'p_request_id': const Uuid().v4(),
          },
        ),
      );

  Future<Map<String, dynamic>> close(
    PosSession session, {
    required String shiftId,
    required double declaredCash,
    String note = '',
  }) async =>
      _map(
        await _supabase.rpc(
          'cashier_shift_close_v472',
          params: {
            'p_tenant_id': session.tenantId,
            'p_shift_id': shiftId,
            'p_declared_cash': declaredCash,
            'p_closed_at': DateTime.now().toUtc().toIso8601String(),
            'p_note': note,
            'p_request_id': const Uuid().v4(),
          },
        ),
      );
}
