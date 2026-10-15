import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/mobile_session.dart';

class MobileClientService {
  SupabaseClient get _supabase => Supabase.instance.client;

  List<Map<String, dynamic>> _rows(dynamic raw) => (raw as List? ?? const [])
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();

  Map<String, dynamic> _map(dynamic raw) =>
      raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

  Future<Map<String, dynamic>> dashboard(
    MobileSession s, {
    String? locationId,
  }) async => _map(
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

  Future<Map<String, dynamic>> performance(
    MobileSession s, {
    String? locationId,
    String period = 'today',
  }) async => _map(
    await _supabase.rpc(
      'mobile_client_performance_v625',
      params: {
        'p_tenant_id': s.tenantId,
        'p_device_id': s.deviceId,
        'p_period': period,
        'p_location_id': locationId,
      },
    ),
  );

  Future<List<Map<String, dynamic>>> sales(
    MobileSession s, {
    String? locationId,
    int limit = 200,
  }) async => _rows(
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
  }) async => _rows(
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
  }) async => _rows(
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
  }) async => _rows(
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
  }) async => _rows(
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
          params: {'p_tenant_id': s.tenantId, 'p_day': _date(DateTime.now())},
        ),
      );

  Future<Map<String, dynamic>> report(
    MobileSession s, {
    required DateTime from,
    required DateTime to,
    String? locationId,
  }) async => _map(
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
  }) async => _rows(
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
  }) async => _map(
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

  Future<Map<String, dynamic>> partyPaymentSummary(
    MobileSession s, {
    String query = '',
  }) async => _map(
    await _supabase.rpc(
      'payments_party_summary_v491',
      params: {
        'p_tenant_id': s.tenantId,
        'p_location_id': s.locationId,
        'p_query': query.trim(),
        'p_limit': 1000,
      },
    ),
  );

  Future<Map<String, dynamic>> paySupplier(
    MobileSession s, {
    required String supplierId,
    required double amount,
    required String method,
    String reference = '',
    String notes = '',
  }) async => _map(
    await _supabase.rpc(
      'supplier_payment_party_v626',
      params: {
        'p_tenant_id': s.tenantId,
        'p_location_id': s.locationId,
        'p_supplier_id': supplierId,
        'p_amount': amount,
        'p_payment_method': method,
        'p_reference_number': reference.trim(),
        'p_notes': notes.trim(),
        'p_device_id': s.deviceId,
        'p_request_id': const Uuid().v4(),
      },
    ),
  );

  Future<Map<String, dynamic>> closeOutstanding(
    MobileSession s, {
    required String partyType,
    required String partyId,
    required String adjustmentType,
    required double amount,
    required String reason,
  }) async => _map(
    await _supabase.rpc(
      'party_outstanding_close_v626',
      params: {
        'p_tenant_id': s.tenantId,
        'p_location_id': s.locationId,
        'p_party_type': partyType,
        'p_party_id': partyId,
        'p_adjustment_type': adjustmentType,
        'p_amount': amount,
        'p_reason': reason.trim(),
        'p_device_id': s.deviceId,
        'p_request_id': const Uuid().v4(),
      },
    ),
  );

  Future<List<Map<String, dynamic>>> notifications(
    MobileSession s, {
    int limit = 100,
  }) async => _rows(
    await _supabase.rpc(
      'notifications_list_v4',
      params: {'p_tenant_id': s.tenantId, 'p_limit': limit},
    ),
  );

  Future<void> markNotificationRead(
    MobileSession s,
    String notificationId,
  ) async {
    await _supabase.rpc(
      'notification_mark_read_v4',
      params: {'p_tenant_id': s.tenantId, 'p_notification_id': notificationId},
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
  }) async => _map(
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
  }) async => _rows(
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
  }) async => _rows(
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
  }) async => _rows(
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
  }) async => _rows(
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

  Future<List<ThqNavigationNode>> loadNavigation(String tenantId, [String appScope = 'client_mobile']) async {
    final result = await _supabase.rpc(
      'app_menu_tree_v45',
      params: {'p_tenant_id': tenantId, 'p_app_key': appScope},
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => ThqNavigationNode.fromMap(Map<String, dynamic>.from(row)))
        .where((node) => node.enabled)
        .toList()
      ..sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : a.label.compareTo(b.label);
      });
  }

  Future<ThqUserUiPreferences> loadUserPreferences([String appScope = 'client_mobile']) async {
    try {
      final result = await _supabase.rpc(
        'user_ui_preferences_get',
        params: {'p_app_scope': appScope},
      );
      if (result is List && result.isNotEmpty && result.first is Map) {
        return ThqUserUiPreferences.fromMap(
          Map<String, dynamic>.from(result.first as Map),
        );
      }
      if (result is Map) {
        return ThqUserUiPreferences.fromMap(
          Map<String, dynamic>.from(result),
        );
      }
    } catch (_) {}
    return ThqUserUiPreferences.defaults(appScope);
  }

  Future<void> saveUserPreferences(ThqUserUiPreferences preferences) async {
    await _supabase.rpc(
      'user_ui_preferences_save',
      params: {
        'p_app_scope': preferences.appScope,
        'p_favorites': preferences.favorites.toList(),
        'p_hidden_nodes': preferences.hiddenNodes.toList(),
        'p_sort_order': preferences.sortOrder,
        'p_quick_actions': preferences.quickActions.toList(),
        'p_table_density': preferences.tableDensity,
        'p_default_landing_module': preferences.defaultLandingModule,
        'p_dashboard_widgets': preferences.dashboardWidgets,
      },
    );
  }

  // --- Stock Transfers ---
  Future<List<Map<String, dynamic>>> stockTransfers(
    MobileSession s, {
    String? locationId,
    String? status,
    String query = '',
    int limit = 200,
  }) async => _rows(
    await _supabase.rpc(
      'inventory_transfers_list_v485',
      params: {
        'p_tenant_id': s.tenantId,
        'p_location_id': locationId,
        'p_status': status,
        'p_query': query.trim(),
        'p_limit': limit,
      },
    ),
  );

  Future<Map<String, dynamic>> stockTransferDetail(
    MobileSession s,
    String transferId,
  ) async => _map(
    await _supabase.rpc(
      'inventory_transfer_detail_v485',
      params: {
        'p_tenant_id': s.tenantId,
        'p_transfer_id': transferId,
      },
    ),
  );

  Future<Map<String, dynamic>> createStockTransfer(
    MobileSession s, {
    required String fromLocationId,
    required String toLocationId,
    required List<Map<String, dynamic>> items,
    required String notes,
    DateTime? expectedArrival,
    String transportReference = '',
  }) async => _map(
    await _supabase.rpc(
      'inventory_transfer_request_v485',
      params: {
        'p_tenant_id': s.tenantId,
        'p_from_location_id': fromLocationId,
        'p_to_location_id': toLocationId,
        'p_items': items,
        'p_notes': notes.trim(),
        'p_expected_arrival_date': expectedArrival?.toIso8601String().split('T').first,
        'p_transport_reference': transportReference.trim(),
        'p_request_id': const Uuid().v4(),
      },
    ),
  );

  Future<Map<String, dynamic>> receiveStockTransfer(
    MobileSession s, {
    required String transferId,
    String note = '',
  }) async => _map(
    await _supabase.rpc(
      'inventory_transfer_receive_v485',
      params: {
        'p_tenant_id': s.tenantId,
        'p_transfer_id': transferId,
        'p_device_id': s.deviceId,
        'p_receive_note': note.trim(),
      },
    ),
  );

  Future<Map<String, dynamic>> dispatchStockTransfer(
    MobileSession s, {
    required String transferId,
    String note = '',
    String transportReference = '',
  }) async => _map(
    await _supabase.rpc(
      'inventory_transfer_dispatch_v485',
      params: {
        'p_tenant_id': s.tenantId,
        'p_transfer_id': transferId,
        'p_device_id': s.deviceId,
        'p_dispatch_note': note.trim(),
        'p_transport_reference': transportReference.trim(),
      },
    ),
  );

  Future<List<Map<String, dynamic>>> warehouseLocations(MobileSession s) async => _rows(
    await _supabase.rpc(
      'warehouse_locations_v485',
      params: {'p_tenant_id': s.tenantId},
    ),
  );

  Future<List<Map<String, dynamic>>> warehouseInventory(
    MobileSession s, {
    String? locationId,
    String query = '',
  }) async => _rows(
    await _supabase.rpc(
      'warehouse_inventory_v485',
      params: {
        'p_tenant_id': s.tenantId,
        'p_location_id': locationId,
        'p_query': query.trim(),
        'p_limit': 1000,
      },
    ),
  );

  // --- Purchases Creation (Authoritative Fail-Closed Routing) ---
  Future<Map<String, dynamic>> createPurchase(
    MobileSession s, {
    required String supplierId,
    required DateTime purchaseDate,
    DateTime? dueDate,
    required List<Map<String, dynamic>> items,
    String? supplierInvoiceNumber,
    double additionalCharges = 0,
    double roundOff = 0,
    double initialPayment = 0,
    String paymentMethod = 'cash',
    String? paymentReference,
    String notes = '',
    String? locationId,
  }) async {
    final contractRaw = await _supabase.rpc(
      'gst_transaction_cutover_contract_v522',
      params: {
        'p_tenant_id': s.tenantId,
        'p_channel': 'mobile_pos',
        'p_device_id': s.deviceId,
      },
    );
    final contract = _map(contractRaw);
    final routes = _map(contract['channel_routes']);
    final rpc = routes['purchase']?.toString() ?? 'gst_purchase_create_v520';

    final result = await _supabase.rpc(
      rpc,
      params: {
        'p_tenant_id': s.tenantId,
        'p_supplier_id': supplierId,
        'p_supplier_invoice_number': supplierInvoiceNumber?.trim().isEmpty == true ? null : supplierInvoiceNumber?.trim(),
        'p_purchase_date': _date(purchaseDate),
        'p_due_date': dueDate == null ? null : _date(dueDate),
        'p_items': items,
        'p_additional_charges': additionalCharges,
        'p_round_off': roundOff,
        'p_initial_payment': initialPayment,
        'p_payment_method': paymentMethod,
        'p_payment_reference': paymentReference?.trim().isEmpty == true ? null : paymentReference?.trim(),
        'p_notes': notes.trim().isEmpty ? null : notes.trim(),
        'p_location_id': locationId ?? s.locationId,
        'p_device_id': s.deviceId,
        'p_request_id': const Uuid().v4(),
      },
    );
    return _map(result);
  }

  // --- Material Yard & Quarry ---
  Future<List<Map<String, dynamic>>> materialLoads(
    MobileSession s, {
    String? locationId,
    String? status,
    String? query,
    int limit = 300,
  }) async => _rows(
    await _supabase.rpc(
      'aggregate_load_list_v629',
      params: {
        'p_tenant_id': s.tenantId,
        'p_location_id': locationId ?? s.locationId,
        'p_status': status,
        'p_query': query?.trim().isEmpty == true ? null : query?.trim(),
        'p_limit': limit,
      },
    ),
  );

  Future<Map<String, dynamic>> materialYardAction(
    MobileSession s, {
    required String action,
    String? locationId,
    Map<String, dynamic> data = const {},
  }) async {
    final payload = {...data, 'device_id': s.deviceId};
    final result = await _supabase.rpc(
      'material_load_workspace_v630',
      params: {
        'p_tenant_id': s.tenantId,
        'p_action': action,
        'p_data': payload,
        'p_location_id': locationId ?? s.locationId,
      },
    );
    return _map(result);
  }

  Future<List<Map<String, dynamic>>> materialDailyRates(
    MobileSession s, {
    String? locationId,
    DateTime? date,
  }) async => _rows(
    await _supabase.rpc(
      'material_daily_rates_get_v708',
      params: {
        'p_tenant_id': s.tenantId,
        'p_location_id': locationId ?? s.locationId,
        'p_rate_date': _date(date ?? DateTime.now()),
      },
    ),
  );

  Future<void> saveMaterialDailyRates(
    MobileSession s, {
    required String locationId,
    required DateTime date,
    required List<Map<String, dynamic>> rates,
  }) async {
    await _supabase.rpc(
      'material_daily_rates_bulk_save_v708',
      params: {
        'p_tenant_id': s.tenantId,
        'p_location_id': locationId,
        'p_rate_date': _date(date),
        'p_rates': rates,
      },
    );
  }

  // --- Staff & Workforce ---
  Future<Map<String, dynamic>> staffAction(
    MobileSession s, {
    required String action,
    String? locationId,
    Map<String, dynamic> data = const {},
  }) async {
    final result = await _supabase.rpc(
      action == 'statement' ? 'staff_statement_v634' : 'staff_workspace_v630',
      params: action == 'statement'
          ? {
              'p_tenant_id': s.tenantId,
              'p_staff_id': data['staff_id'],
              'p_from': data['from'],
              'p_to': data['to'],
              'p_location_id': locationId ?? s.locationId,
            }
          : {
              'p_tenant_id': s.tenantId,
              'p_action': action,
              'p_data': data,
              'p_location_id': locationId ?? s.locationId,
            },
    );
    return _map(result);
  }

  // --- Reports Center ---
  Future<List<Map<String, dynamic>>> reportsCatalog(MobileSession s) async => _rows(
    await _supabase.rpc(
      'reports_center_catalog_v631',
      params: {'p_tenant_id': s.tenantId},
    ),
  );

  Future<Map<String, dynamic>> runReport(
    MobileSession s, {
    required String reportKey,
    required DateTime fromDate,
    required DateTime toDate,
    String? locationId,
    String query = '',
    int offset = 0,
    int limit = 100,
    Map<String, dynamic> filters = const {},
  }) async {
    final result = await _supabase.rpc(
      'reports_center_run_v631',
      params: {
        'p_tenant_id': s.tenantId,
        'p_report_key': reportKey,
        'p_from': _date(fromDate),
        'p_to': _date(toDate),
        'p_location_id': locationId ?? s.locationId,
        'p_query': query,
        'p_offset': offset,
        'p_limit': limit,
        'p_filters': filters,
      },
    );
    return _map(result);
  }

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
