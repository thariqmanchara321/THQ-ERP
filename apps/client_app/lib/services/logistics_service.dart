import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_installation_service.dart';

class LogisticsService {
  SupabaseClient get _supabase => Supabase.instance.client;

  List<Map<String, dynamic>> _rows(dynamic result) =>
      (result as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

  Future<List<Map<String, dynamic>>> list({
    required String tenantId,
    String? locationId,
    String? status,
    String query = '',
  }) async => _rows(
    await _supabase.rpc(
      'logistics_trips_list_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_status': status,
        'p_query': query.trim(),
        'p_limit': 500,
      },
    ),
  );

  Future<Map<String, dynamic>> detail({
    required String tenantId,
    required String tripId,
  }) async {
    final result = await _supabase.rpc(
      'logistics_trip_detail_v1',
      params: {'p_tenant_id': tenantId, 'p_trip_id': tripId},
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw StateError('Unexpected logistics trip detail response.');
  }

  Future<Map<String, dynamic>> create({
    required String tenantId,
    required String vehicleId,
    required List<String> transferIds,
    DateTime? plannedDepartureAt,
    String driverName = '',
    String driverPhone = '',
    String notes = '',
  }) async {
    final result = await _supabase.rpc(
      'logistics_trip_create_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_vehicle_id': vehicleId,
        'p_transfer_ids': transferIds,
        'p_planned_departure_at': plannedDepartureAt?.toUtc().toIso8601String(),
        'p_driver_name': driverName.trim(),
        'p_driver_phone': driverPhone.trim(),
        'p_notes': notes.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> startLoading({
    required String tenantId,
    required String tripId,
  }) async {
    final result = await _supabase.rpc(
      'logistics_trip_start_loading_v1',
      params: {'p_tenant_id': tenantId, 'p_trip_id': tripId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> dispatch({
    required String tenantId,
    required String tripId,
    String note = '',
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    final result = await _supabase.rpc(
      'logistics_trip_dispatch_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_trip_id': tripId,
        'p_device_id': activation?.deviceId,
        'p_note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> arrive({
    required String tenantId,
    required String tripId,
    String note = '',
  }) async {
    final result = await _supabase.rpc(
      'logistics_trip_arrive_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_trip_id': tripId,
        'p_note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> receiveTransfer({
    required String tenantId,
    required String tripId,
    required String transferId,
    String note = '',
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    final result = await _supabase.rpc(
      'logistics_trip_receive_transfer_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_trip_id': tripId,
        'p_transfer_id': transferId,
        'p_device_id': activation?.deviceId,
        'p_note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> receiptContext({
    required String tenantId,
    required String tripId,
    required String transferId,
  }) async {
    final result = await _supabase.rpc(
      'logistics_transfer_receipt_context_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_trip_id': tripId,
        'p_transfer_id': transferId,
      },
    );
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    throw StateError('Unexpected logistics receipt context response.');
  }

  Future<Map<String, dynamic>> receiveTransferReconciled({
    required String tenantId,
    required String tripId,
    required String transferId,
    required List<Map<String, dynamic>> lines,
    String note = '',
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    final result = await _supabase.rpc(
      'logistics_trip_receive_transfer_reconciled_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_trip_id': tripId,
        'p_transfer_id': transferId,
        'p_device_id': activation?.deviceId,
        'p_lines': lines,
        'p_note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> reportsDashboard({
    required String tenantId,
    String? locationId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    String dateOnly(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

    final result = await _supabase.rpc(
      'logistics_reports_dashboard_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_from_date': dateOnly(fromDate),
        'p_to_date': dateOnly(toDate),
      },
    );
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    throw StateError('Unexpected logistics reports response.');
  }

  Future<List<Map<String, dynamic>>> operationsTrips({
    required String tenantId,
    String? locationId,
    int limit = 500,
  }) async => _rows(
    await _supabase.rpc(
      'logistics_operations_trips_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_limit': limit,
      },
    ),
  );

  Future<List<Map<String, dynamic>>> logisticsExceptions({
    required String tenantId,
    String? locationId,
    String? status,
    String? tripId,
    int limit = 500,
  }) async => _rows(
    await _supabase.rpc(
      'logistics_exceptions_list_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_status': status,
        'p_trip_id': tripId,
        'p_limit': limit,
      },
    ),
  );

  Future<Map<String, dynamic>> updateLogisticsException({
    required String tenantId,
    required String exceptionId,
    required String status,
    String? resolutionCode,
    String resolutionNote = '',
    String externalReference = '',
  }) async {
    final result = await _supabase.rpc(
      'logistics_exception_update_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_exception_id': exceptionId,
        'p_status': status,
        'p_resolution_code': resolutionCode,
        'p_resolution_note': resolutionNote.trim(),
        'p_external_reference': externalReference.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> logisticsEvidence({
    required String tenantId,
    required String tripId,
  }) async => _rows(
    await _supabase.rpc(
      'logistics_evidence_list_v1',
      params: {'p_tenant_id': tenantId, 'p_trip_id': tripId},
    ),
  );

  Future<Map<String, dynamic>> uploadLogisticsEvidence({
    required String tenantId,
    required String tripId,
    required String evidenceType,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    String note = '',
    String? stockTransferId,
    String? receiptId,
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError('Evidence file is empty.');
    }
    if (bytes.length > 5 * 1024 * 1024) {
      throw ArgumentError('Evidence file exceeds the 5 MB limit.');
    }

    const bucket = 'thq-assets';
    final sanitized = fileName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final safeName = sanitized.isEmpty ? 'proof.jpg' : sanitized;
    final storagePath =
        '$tenantId/logistics/$tripId/${DateTime.now().toUtc().microsecondsSinceEpoch}_$safeName';

    await _supabase.storage
        .from(bucket)
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );

    try {
      final result = await _supabase.rpc(
        'logistics_evidence_register_v1',
        params: {
          'p_tenant_id': tenantId,
          'p_trip_id': tripId,
          'p_evidence_type': evidenceType,
          'p_file_name': fileName,
          'p_storage_path': storagePath,
          'p_mime_type': mimeType,
          'p_file_size': bytes.length,
          'p_note': note.trim(),
          'p_stock_transfer_id': stockTransferId,
          'p_receipt_id': receiptId,
          'p_captured_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      return Map<String, dynamic>.from(result as Map);
    } catch (_) {
      try {
        await _supabase.storage.from(bucket).remove([storagePath]);
      } catch (_) {
        // Best-effort cleanup. Registration failure remains the primary error.
      }
      rethrow;
    }
  }

  String logisticsEvidencePublicUrl(String storagePath) =>
      _supabase.storage.from('thq-assets').getPublicUrl(storagePath);
  Future<Map<String, dynamic>> close({
    required String tenantId,
    required String tripId,
  }) async {
    final result = await _supabase.rpc(
      'logistics_trip_close_v1',
      params: {'p_tenant_id': tenantId, 'p_trip_id': tripId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> cancel({
    required String tenantId,
    required String tripId,
    required String reason,
  }) async {
    final result = await _supabase.rpc(
      'logistics_trip_cancel_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_trip_id': tripId,
        'p_reason': reason.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }
}
