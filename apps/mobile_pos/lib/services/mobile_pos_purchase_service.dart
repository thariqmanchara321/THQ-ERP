import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/pos_models.dart';
import '../models/pos_session.dart';
import 'gst_v520_route_guard.dart';

class MobilePosPurchaseService {
  MobilePosPurchaseService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client,
        _guard = GstV520RouteGuard(client: client ?? Supabase.instance.client);

  final SupabaseClient _client;
  final GstV520RouteGuard _guard;

  Future<List<MobileSupplier>> suppliers(PosSession session) async {
    final raw = await _client.rpc(
      'suppliers_list_v32',
      params: {'p_tenant_id': session.tenantId},
    );
    return (raw as List? ?? const [])
        .whereType<Map>()
        .map((row) => MobileSupplier.fromMap(Map<String, dynamic>.from(row)))
        .where((supplier) => supplier.id.isNotEmpty && supplier.isActive)
        .toList();
  }

  Future<Map<String, dynamic>> quote({
    required PosSession session,
    required String supplierId,
    required DateTime purchaseDate,
    required List<Map<String, dynamic>> items,
    required double roundOff,
  }) async {
    final raw = await _client.rpc(
      'gst_purchase_quote_v520',
      params: {
        'p_tenant_id': session.tenantId,
        'p_location_id': session.locationId,
        'p_supplier_id': supplierId,
        'p_document_date': _dateOnly(purchaseDate),
        'p_supply_type': null,
        'p_place_of_supply_code': null,
        'p_items': items,
        'p_additional_charges': 0,
        'p_round_off': roundOff,
      },
    );
    if (raw is! Map) {
      throw StateError('Unexpected authoritative GST purchase quote response.');
    }
    return Map<String, dynamic>.from(raw);
  }

  Future<Map<String, dynamic>> create({
    required PosSession session,
    required String supplierId,
    required String supplierInvoiceNumber,
    required DateTime purchaseDate,
    DateTime? dueDate,
    required List<Map<String, dynamic>> items,
    required double roundOff,
    required double initialPayment,
    required String paymentMethod,
    String paymentReference = '',
    String notes = '',
    String? requestId,
  }) async {
    final rpc = await _guard.route(
      tenantId: session.tenantId,
      channel: 'mobile_pos',
      routeKey: 'purchase',
      deviceId: session.deviceId,
    );

    try {
      final raw = await _client.rpc(
        rpc,
        params: {
          'p_tenant_id': session.tenantId,
          'p_supplier_id': supplierId,
          'p_supplier_invoice_number': supplierInvoiceNumber.trim(),
          'p_purchase_date': _dateOnly(purchaseDate),
          'p_due_date': dueDate == null ? null : _dateOnly(dueDate),
          'p_items': items,
          'p_additional_charges': 0,
          'p_round_off': roundOff,
          'p_initial_payment': initialPayment,
          'p_payment_method': paymentMethod,
          'p_payment_reference': paymentReference.trim().isEmpty
              ? null
              : paymentReference.trim(),
          'p_notes': notes.trim().isEmpty ? null : notes.trim(),
          'p_location_id': session.locationId,
          'p_device_id': session.deviceId,
          'p_request_id': requestId ?? const Uuid().v4(),
          'p_supply_type': null,
          'p_place_of_supply_code': null,
        },
      );
      if (raw is! Map) throw StateError('Unexpected response from $rpc.');
      final result = Map<String, dynamic>.from(raw);
      if (result['authoritative_gst'] != true ||
          result['purchase_id'] == null ||
          result['gst_snapshot_id'] == null ||
          result['journal_id'] == null) {
        throw StateError(
          'Purchase response is missing authoritative GST evidence.',
        );
      }
      return result;
    } catch (error) {
      throw StateError(
        'Authoritative GST Mobile POS purchase failed. Legacy purchase fallback '
        'is disabled. Retry the unchanged purchase. $error',
      );
    }
  }

  String _dateOnly(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
