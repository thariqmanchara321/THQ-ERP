import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/mobile_session.dart';

class MobileClientService {
  SupabaseClient get _supabase => Supabase.instance.client;

  List<Map<String, dynamic>> _rows(dynamic raw) =>
      (raw as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

  Map<String, dynamic> _map(dynamic raw) => raw is Map
      ? Map<String, dynamic>.from(raw)
      : <String, dynamic>{};

  Future<Map<String, dynamic>> dashboard(
    MobileSession s, {
    String? locationId,
  }) async =>
      _map(
        await _supabase.rpc(
          'mobile_client_dashboard_v487',
          params: {
            'p_tenant_id': s.tenantId,
            'p_device_id': s.deviceId,
            'p_day': _date(DateTime.now()),
            'p_location_id': locationId,
          },
        ),
      );

  Future<List<Map<String, dynamic>>> sales(
    MobileSession s, {
    String? locationId,
    int limit = 200,
  }) async =>
      _rows(
        await _supabase.rpc(
          'mobile_sales_status_v487',
          params: {
            'p_tenant_id': s.tenantId,
            'p_device_id': s.deviceId,
            'p_location_id': locationId,
            'p_limit': limit,
          },
        ),
      );

  Future<List<Map<String, dynamic>>> purchases(
    MobileSession s, {
    String? locationId,
    int limit = 200,
  }) async =>
      _rows(
        await _supabase.rpc(
          'mobile_purchases_status_v487',
          params: {
            'p_tenant_id': s.tenantId,
            'p_device_id': s.deviceId,
            'p_location_id': locationId,
            'p_limit': limit,
          },
        ),
      );

  Future<List<Map<String, dynamic>>> inventory(
    MobileSession s, {
    String? locationId,
    String query = '',
    int limit = 500,
  }) async =>
      _rows(
        await _supabase.rpc(
          'mobile_inventory_status_v487',
          params: {
            'p_tenant_id': s.tenantId,
            'p_device_id': s.deviceId,
            'p_location_id': locationId,
            'p_query': query,
            'p_limit': limit,
          },
        ),
      );

  Future<List<Map<String, dynamic>>> customerOutstanding(
    MobileSession s, {
    String? locationId,
    String query = '',
    int limit = 500,
  }) async =>
      _rows(
        await _supabase.rpc(
          'mobile_customer_outstanding_v487',
          params: {
            'p_tenant_id': s.tenantId,
            'p_device_id': s.deviceId,
            'p_location_id': locationId,
            'p_query': query,
            'p_limit': limit,
          },
        ),
      );

  Future<List<Map<String, dynamic>>> supplierOutstanding(
    MobileSession s, {
    String? locationId,
    String query = '',
    int limit = 500,
  }) async =>
      _rows(
        await _supabase.rpc(
          'mobile_supplier_outstanding_v487',
          params: {
            'p_tenant_id': s.tenantId,
            'p_device_id': s.deviceId,
            'p_location_id': locationId,
            'p_query': query,
            'p_limit': limit,
          },
        ),
      );

  Future<List<Map<String, dynamic>>> storePerformance(MobileSession s) async =>
      _rows(
        await _supabase.rpc(
          'mobile_store_status_v480',
          params: {
            'p_tenant_id': s.tenantId,
            'p_day': _date(DateTime.now()),
          },
        ),
      );

  Future<Map<String, dynamic>> report(
    MobileSession s, {
    required DateTime from,
    required DateTime to,
    String? locationId,
  }) async =>
      _map(
        await _supabase.rpc(
          'reports_get_summary_v4',
          params: {
            'p_tenant_id': s.tenantId,
            'p_from_date': _date(from),
            'p_to_date': _date(to),
            'p_location_id': locationId,
          },
        ),
      );

  Future<List<Map<String, dynamic>>> approvals(
    MobileSession s, {
    String status = 'pending',
    int limit = 300,
  }) async =>
      _rows(
        await _supabase.rpc(
          'mobile_approvals_v487',
          params: {
            'p_tenant_id': s.tenantId,
            'p_device_id': s.deviceId,
            'p_status': status,
            'p_limit': limit,
          },
        ),
      );

  Future<void> decide(
    MobileSession s, {
    required String type,
    required String id,
    required bool approve,
    String note = '',
  }) async {
    await _supabase.rpc(
      'mobile_approval_decide_v487',
      params: {
        'p_tenant_id': s.tenantId,
        'p_device_id': s.deviceId,
        'p_approval_type': type,
        'p_id': id,
        'p_approve': approve,
        'p_note': note,
      },
    );
  }

  Future<Map<String, dynamic>> receiveCustomerPayment(
    MobileSession s, {
    required String customerId,
    required double amount,
    required String method,
    String reference = '',
    String notes = '',
  }) async =>
      _map(
        await _supabase.rpc(
          'mobile_customer_payment_v487',
          params: {
            'p_tenant_id': s.tenantId,
            'p_device_id': s.deviceId,
            'p_customer_id': customerId,
            'p_amount': amount,
            'p_payment_method': method,
            'p_reference_number': reference,
            'p_notes': notes,
            'p_sale_id': null,
            'p_request_id': const Uuid().v4(),
          },
        ),
      );

  Future<List<Map<String, dynamic>>> notifications(
    MobileSession s, {
    int limit = 100,
  }) async =>
      _rows(
        await _supabase.rpc(
          'notifications_list_v4',
          params: {
            'p_tenant_id': s.tenantId,
            'p_limit': limit,
          },
        ),
      );

  Future<void> markNotificationRead(
    MobileSession s,
    String notificationId,
  ) async {
    await _supabase.rpc(
      'notification_mark_read_v4',
      params: {
        'p_tenant_id': s.tenantId,
        'p_notification_id': notificationId,
      },
    );
  }

  Future<int> markAllNotificationsRead(MobileSession s) async {
    final raw = await _supabase.rpc(
      'notifications_mark_all_read_v495',
      params: {'p_tenant_id': s.tenantId},
    );
    return raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  Future<Map<String, dynamic>> auditSummary(
    MobileSession s, {
    String? locationId,
    DateTime? from,
    DateTime? to,
  }) async =>
      _map(
        await _supabase.rpc(
          'audit_center_summary_v600',
          params: {
            'p_tenant_id': s.tenantId,
            'p_from': from?.toIso8601String(),
            'p_to': to?.toIso8601String(),
            'p_location_id': locationId,
          },
        ),
      );

  Future<List<Map<String, dynamic>>> auditFindings(
    MobileSession s, {
    String? severity,
    String? status,
    String? locationId,
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async =>
      _rows(
        await _supabase.rpc(
          'audit_findings_list_v600',
          params: {
            'p_tenant_id': s.tenantId,
            'p_severity': severity,
            'p_status': status,
            'p_from': from?.toIso8601String(),
            'p_to': to?.toIso8601String(),
            'p_location_id': locationId,
            'p_limit': limit,
          },
        ),
      );

  Future<List<Map<String, dynamic>>> serials(
    MobileSession s, {
    String? locationId,
    String query = '',
    int limit = 200,
  }) async =>
      _rows(
        await _supabase.rpc(
          'inventory_serial_search_v483',
          params: {
            'p_tenant_id': s.tenantId,
            'p_query': query,
            'p_location_id': locationId,
            'p_limit': limit,
          },
        ),
      );

  Future<List<Map<String, dynamic>>> batches(
    MobileSession s, {
    String? locationId,
    String query = '',
    int limit = 200,
  }) async =>
      _rows(
        await _supabase.rpc(
          'inventory_batch_search_v483',
          params: {
            'p_tenant_id': s.tenantId,
            'p_query': query,
            'p_location_id': locationId,
            'p_limit': limit,
          },
        ),
      );

  Future<List<Map<String, dynamic>>> warranties(
    MobileSession s, {
    String? locationId,
    String query = '',
    String? status,
    int? expiringDays,
    int limit = 300,
  }) async =>
      _rows(
        await _supabase.rpc(
          'warranty_register_v483',
          params: {
            'p_tenant_id': s.tenantId,
            'p_query': query,
            'p_status': status,
            'p_expiring_days': expiringDays,
            'p_limit': limit,
            'p_location_id': locationId,
          },
        ),
      );

  Future<Map<String, List<Map<String, dynamic>>>> globalSearch(
    MobileSession s, {
    required String query,
    String? locationId,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const <String, List<Map<String, dynamic>>>{};

    final groups = await Future.wait<List<Map<String, dynamic>>>([
      sales(s, locationId: locationId, limit: 150),
      purchases(s, locationId: locationId, limit: 150),
      inventory(s, locationId: locationId, query: query, limit: 80),
      customerOutstanding(s, locationId: locationId, query: query, limit: 80),
      supplierOutstanding(s, locationId: locationId, query: query, limit: 80),
    ]);

    bool contains(Map<String, dynamic> row) => row.values.any(
          (value) => value?.toString().toLowerCase().contains(q) == true,
        );

    return {
      'Sales': groups[0].where(contains).take(30).toList(),
      'Purchases': groups[1].where(contains).take(30).toList(),
      'Inventory': groups[2].take(30).toList(),
      'Customers': groups[3].take(30).toList(),
      'Suppliers': groups[4].take(30).toList(),
    };
  }

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
