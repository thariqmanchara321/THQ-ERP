import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_installation_service.dart';

class CommercialPricingService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<_CommercialOrigin> _origin(
    String tenantId, {
    String? locationId,
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null || activation.tenantId != tenantId) {
      throw StateError('This system is not activated for this business.');
    }
    return _CommercialOrigin(
      locationId: locationId ?? activation.locationId,
      deviceId: activation.deviceId,
    );
  }

  Future<List<Map<String, dynamic>>> chargeCatalog({
    required String tenantId,
    String? locationId,
    bool activeOnly = true,
  }) async {
    final origin = await _origin(tenantId, locationId: locationId);
    final raw = await _supabase.rpc(
      'sales_charge_catalog_list_pos_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': origin.locationId,
        'p_device_id': origin.deviceId,
        'p_active_only': activeOnly,
      },
    );
    if (raw is! Map) {
      throw StateError('Unexpected additional-charge catalogue response.');
    }
    final map = Map<String, dynamic>.from(raw);
    return (map['charges'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<String> saveChargeCatalog({
    required String tenantId,
    String? locationId,
    String? chargeId,
    required String code,
    required String name,
    required String chargeKind,
    required String serviceVariantId,
    double defaultQuantity = 1,
    bool active = true,
  }) async {
    final origin = await _origin(tenantId, locationId: locationId);
    final result = await _supabase.rpc(
      'sales_charge_catalog_put_pos_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': origin.locationId,
        'p_device_id': origin.deviceId,
        'p_charge_id': chargeId,
        'p_code': code,
        'p_name': name,
        'p_charge_kind': chargeKind,
        'p_service_variant_id': serviceVariantId,
        'p_default_quantity': defaultQuantity,
        'p_auto_dine_in': false,
        'p_auto_takeaway': false,
        'p_auto_delivery': false,
        'p_active': active,
      },
    );
    return result?.toString() ?? '';
  }

  Future<bool> additionalChargesEnabled({required String tenantId}) async {
    final raw = await _supabase.rpc(
      'sales_additional_charges_enabled_v611',
      params: {'p_tenant_id': tenantId},
    );
    return raw == true || raw?.toString().toLowerCase() == 'true';
  }

  Future<Map<String, dynamic>> quote({
    required String tenantId,
    required String locationId,
    required List<Map<String, dynamic>> items,
    String orderType = 'sale',
    String discountType = 'none',
    double discountValue = 0,
    List<Map<String, dynamic>> chargeSelections = const [],
  }) async {
    final origin = await _origin(tenantId, locationId: locationId);
    final raw = await _supabase.rpc(
      'sales_commercial_quote_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': origin.locationId,
        'p_device_id': origin.deviceId,
        'p_order_type': orderType,
        'p_items': items,
        'p_discount_type': discountType,
        'p_discount_value': discountValue,
        'p_charge_selections': chargeSelections,
      },
    );
    if (raw is! Map) {
      throw StateError('Unexpected commercial quote response.');
    }
    return Map<String, dynamic>.from(raw);
  }

  Future<Map<String, dynamic>> captureSummary({
    required String tenantId,
    required String locationId,
    required String saleId,
    required Map<String, dynamic> summary,
  }) async {
    final origin = await _origin(tenantId, locationId: locationId);
    final raw = await _supabase.rpc(
      'sales_commercial_summary_capture_v610',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': origin.locationId,
        'p_device_id': origin.deviceId,
        'p_sale_id': saleId,
        'p_source_type': 'sale',
        'p_source_id': null,
        'p_order_type': 'sale',
        'p_summary': summary,
      },
    );
    if (raw is! Map) {
      throw StateError('Unexpected commercial summary response.');
    }
    return Map<String, dynamic>.from(raw);
  }
}

class _CommercialOrigin {
  const _CommercialOrigin({required this.locationId, required this.deviceId});

  final String locationId;
  final String deviceId;
}
