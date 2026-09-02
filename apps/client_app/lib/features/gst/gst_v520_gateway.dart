import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// THQ ERP v5.2 GST application gateway.
///
/// Purpose:
/// - Use the backend cutover contract as the source of truth for RPC routing.
/// - Never calculate GST independently in Flutter.
/// - Never fall back to a legacy v5.1 writer after a v5.2 route is selected.
/// - Keep request IDs stable across retries for idempotent transaction writers.
///
/// Backend migration dependency:
/// - 247: gst_transaction_cutover_contract_v520
///
/// Frozen legacy baseline remains:
/// - v5.1.0 Build 27 / backend contract migration 213
enum GstV520Channel { client, pos, posOffline, mobilePos }

extension GstV520ChannelWire on GstV520Channel {
  String get wireName {
    switch (this) {
      case GstV520Channel.client:
        return 'client';
      case GstV520Channel.pos:
        return 'pos';
      case GstV520Channel.posOffline:
        return 'pos_offline';
      case GstV520Channel.mobilePos:
        return 'mobile_pos';
    }
  }

  bool get requiresDevice =>
      this == GstV520Channel.posOffline || this == GstV520Channel.mobilePos;
}

class GstV520Exception implements Exception {
  const GstV520Exception(this.message);

  final String message;

  @override
  String toString() => 'GstV520Exception: $message';
}

class GstV520Gateway {
  GstV520Gateway({
    required SupabaseClient client,
    required String tenantId,
    required GstV520Channel channel,
    String? deviceId,
  }) : this._(client, tenantId: tenantId, channel: channel, deviceId: deviceId);

  GstV520Gateway._(
    this._client, {
    required this.tenantId,
    required this.channel,
    this.deviceId,
  });

  final SupabaseClient _client;
  final String tenantId;
  final GstV520Channel channel;

  /// Device ID for POS / Offline POS / Mobile POS.
  ///
  /// Client calls may leave this null and supply a device ID to an individual
  /// operation where that writer requires one.
  final String? deviceId;

  Map<String, dynamic>? _contract;

  bool get isInitialized => _contract != null;

  Map<String, dynamic> get contract {
    final value = _contract;
    if (value == null) {
      throw const GstV520Exception(
        'GST v5.2 gateway is not initialized. Call initialize() first.',
      );
    }
    return Map<String, dynamic>.unmodifiable(value);
  }

  Map<String, dynamic>? get deviceContract {
    final raw = contract['device_contract'];
    if (raw == null) return null;
    return _asMap(raw, fieldName: 'device_contract');
  }

  Map<String, dynamic> get channelRoutes {
    return Map<String, dynamic>.unmodifiable(
      _asMap(contract['channel_routes'], fieldName: 'channel_routes'),
    );
  }

  /// Loads the server-side cutover contract and validates fail-closed rules.
  ///
  /// Call this once after tenant/device activation and again after a manual
  /// Refresh/config invalidation.
  Future<Map<String, dynamic>> initialize() async {
    if (tenantId.trim().isEmpty) {
      throw const GstV520Exception('Tenant ID is required.');
    }

    if (channel.requiresDevice &&
        (deviceId == null || deviceId!.trim().isEmpty)) {
      throw GstV520Exception('Device ID is required for ${channel.wireName}.');
    }

    final params = <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_channel': channel.wireName,
      'p_device_id': deviceId,
    };

    final raw = await _rpcDirect(
      'gst_transaction_cutover_contract_v522',
      params,
    );
    final loaded = _asMap(raw, fieldName: 'cutover_contract');

    if (loaded['cutover_ready'] != true) {
      final blockingReason = loaded['blocking_reason']?.toString();
      final taxMode = loaded['tax_mode']?.toString() ?? 'unconfigured';
      final detail = blockingReason == 'tax_mode_unconfigured'
          ? 'Choose GST Registered or Non-GST in GST & Compliance first.'
          : (blockingReason == null || blockingReason.isEmpty
                ? 'Backend has not approved GST v5.2 application cutover.'
                : blockingReason);
      throw GstV520Exception(
        'GST v5.2 cutover blocked: $detail (tax mode: $taxMode).',
      );
    }

    if (loaded['activation_mode'] != 'explicit_app_rpc_switch') {
      throw GstV520Exception(
        'Unexpected GST cutover activation mode: '
        '${loaded['activation_mode']}.',
      );
    }

    final rules = _asMap(loaded['rules'], fieldName: 'rules');

    if (rules['v520_route_requires_v520_writer'] != true) {
      throw const GstV520Exception(
        'Backend cutover contract does not require v5.2 writers.',
      );
    }

    if (rules['legacy_fallback_after_v520_route'] != false) {
      throw const GstV520Exception(
        'Unsafe GST cutover contract: legacy fallback must be disabled.',
      );
    }

    if (rules['tax_calculation'] != 'server_authoritative_only') {
      throw const GstV520Exception(
        'Unsafe GST cutover contract: server must remain tax authority.',
      );
    }

    final routes = _asMap(
      loaded['channel_routes'],
      fieldName: 'channel_routes',
    );
    if (routes.isEmpty) {
      throw GstV520Exception(
        'No v5.2 GST routes published for ${channel.wireName}.',
      );
    }

    _contract = loaded;
    return contract;
  }

  /// Re-fetches the current backend cutover contract.
  Future<Map<String, dynamic>> refreshContract() => initialize();

  // ---------------------------------------------------------------------------
  // CLIENT: SALES
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> createSale({
    required String customerId,
    required DateTime saleDate,
    required DateTime dueDate,
    required List<Map<String, dynamic>> items,
    required String requestId,
    num additionalCharges = 0,
    num roundOff = 0,
    num initialPayment = 0,
    String paymentMethod = 'cash',
    String? paymentReference,
    String? notes,
    String? locationId,
    String? deviceId,
    String? supplyType,
    String? placeOfSupplyCode,
  }) async {
    _requireRequestId(requestId);

    final params = <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_customer_id': customerId,
      'p_sale_date': _dateOnly(saleDate),
      'p_due_date': _dateOnly(dueDate),
      'p_items': items,
      'p_additional_charges': additionalCharges,
      'p_round_off': roundOff,
      'p_initial_payment': initialPayment,
      'p_payment_method': paymentMethod,
      'p_request_id': requestId,
    };

    _putIfNotNull(params, 'p_payment_reference', paymentReference);
    _putIfNotNull(params, 'p_notes', notes);
    _putIfNotNull(params, 'p_location_id', locationId);
    _putIfNotNull(params, 'p_device_id', deviceId ?? this.deviceId);
    _putIfNotNull(params, 'p_supply_type', supplyType);
    _putIfNotNull(params, 'p_place_of_supply_code', placeOfSupplyCode);

    return _callRoute('sale', params);
  }

  // ---------------------------------------------------------------------------
  // CLIENT: PURCHASE
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> createPurchase({
    required String supplierId,
    required String supplierInvoiceNumber,
    required DateTime purchaseDate,
    required DateTime dueDate,
    required List<Map<String, dynamic>> items,
    required String requestId,
    num additionalCharges = 0,
    num roundOff = 0,
    num initialPayment = 0,
    String paymentMethod = 'cash',
    String? paymentReference,
    String? notes,
    String? locationId,
    String? deviceId,
    String? supplyType,
    String? placeOfSupplyCode,
  }) async {
    _requireRequestId(requestId);

    final params = <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_supplier_id': supplierId,
      'p_supplier_invoice_number': supplierInvoiceNumber,
      'p_purchase_date': _dateOnly(purchaseDate),
      'p_due_date': _dateOnly(dueDate),
      'p_items': items,
      'p_additional_charges': additionalCharges,
      'p_round_off': roundOff,
      'p_initial_payment': initialPayment,
      'p_payment_method': paymentMethod,
      'p_request_id': requestId,
    };

    _putIfNotNull(params, 'p_payment_reference', paymentReference);
    _putIfNotNull(params, 'p_notes', notes);
    _putIfNotNull(params, 'p_location_id', locationId);
    _putIfNotNull(params, 'p_device_id', deviceId ?? this.deviceId);
    _putIfNotNull(params, 'p_supply_type', supplyType);
    _putIfNotNull(params, 'p_place_of_supply_code', placeOfSupplyCode);

    return _callRoute('purchase', params);
  }

  // ---------------------------------------------------------------------------
  // CLIENT: PURCHASING V2 PURCHASE INVOICE
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> createPurchaseInvoiceV2({
    required String purchaseOrderId,
    required String supplierInvoiceNumber,
    required DateTime invoiceDate,
    required DateTime dueDate,
    required List<Map<String, dynamic>> items,
    required String requestId,
    num additionalCharges = 0,
    num roundOff = 0,
    String? notes,
    String? supplyType,
    String? placeOfSupplyCode,
  }) async {
    _requireRequestId(requestId);

    final params = <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_purchase_order_id': purchaseOrderId,
      'p_supplier_invoice_number': supplierInvoiceNumber,
      'p_invoice_date': _dateOnly(invoiceDate),
      'p_due_date': _dateOnly(dueDate),
      'p_items': items,
      'p_additional_charges': additionalCharges,
      'p_round_off': roundOff,
      'p_request_id': requestId,
    };

    _putIfNotNull(params, 'p_notes', notes);
    _putIfNotNull(params, 'p_supply_type', supplyType);
    _putIfNotNull(params, 'p_place_of_supply_code', placeOfSupplyCode);

    return _callRoute('purchase_invoice_v2', params);
  }

  // ---------------------------------------------------------------------------
  // CLIENT / POS: SALES RETURN
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> createSalesReturn({
    required String saleId,
    required DateTime returnDate,
    required List<Map<String, dynamic>> items,
    required String reason,
    required String requestId,
    String? locationId,
    String? deviceId,
  }) async {
    _requireRequestId(requestId);

    final params = <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_sale_id': saleId,
      'p_return_date': _dateOnly(returnDate),
      'p_items': items,
      'p_reason': reason,
      'p_request_id': requestId,
    };

    _putIfNotNull(params, 'p_location_id', locationId);
    _putIfNotNull(params, 'p_device_id', deviceId ?? this.deviceId);

    return _callRoute('sales_return', params);
  }

  // ---------------------------------------------------------------------------
  // CLIENT: PURCHASE RETURN
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> createPurchaseReturn({
    required String purchaseId,
    required DateTime returnDate,
    required List<Map<String, dynamic>> items,
    required String reason,
    required String requestId,
    String? locationId,
    String? deviceId,
  }) async {
    _requireRequestId(requestId);

    final params = <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_purchase_id': purchaseId,
      'p_return_date': _dateOnly(returnDate),
      'p_items': items,
      'p_reason': reason,
      'p_request_id': requestId,
    };

    _putIfNotNull(params, 'p_location_id', locationId);
    _putIfNotNull(params, 'p_device_id', deviceId ?? this.deviceId);

    return _callRoute('purchase_return', params);
  }

  // ---------------------------------------------------------------------------
  // CLIENT: SERVICE / WORKSHOP BILLING
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> billServiceJob({
    required String jobId,
    required String billingVariantId,
    required DateTime dueDate,
    required num initialPayment,
    required String paymentMethod,
    required String requestId,
    required String deviceId,
    String? paymentReference,
    String? supplyType,
    String? placeOfSupplyCode,
  }) async {
    _requireRequestId(requestId);

    final params = <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_job_id': jobId,
      'p_billing_variant_id': billingVariantId,
      'p_due_date': _dateOnly(dueDate),
      'p_initial_payment': initialPayment,
      'p_payment_method': paymentMethod,
      'p_device_id': deviceId,
      'p_request_id': requestId,
    };

    _putIfNotNull(params, 'p_payment_reference', paymentReference);
    _putIfNotNull(params, 'p_supply_type', supplyType);
    _putIfNotNull(params, 'p_place_of_supply_code', placeOfSupplyCode);

    return _callRoute('service_bill', params);
  }

  // ---------------------------------------------------------------------------
  // ONLINE POS / MOBILE POS: RESTAURANT BILLING
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> billRestaurantOrder({
    required String orderId,
    required String deviceId,
    required num initialPayment,
    required String paymentMethod,
    String? customerId,
    DateTime? dueDate,
    String? paymentReference,
    num roundOff = 0,
    String? supplyType,
    String? placeOfSupplyCode,
  }) async {
    final params = <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_order_id': orderId,
      'p_device_id': deviceId,
      'p_customer_id': customerId,
      'p_due_date': dueDate == null ? null : _dateOnly(dueDate),
      'p_initial_payment': initialPayment,
      'p_payment_method': paymentMethod,
      'p_payment_reference': paymentReference,
      'p_round_off': roundOff,
      'p_supply_type': supplyType,
      'p_place_of_supply_code': placeOfSupplyCode,
    };

    return _callRoute('restaurant_bill', params);
  }

  // ---------------------------------------------------------------------------
  // OFFLINE POS
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> syncOfflinePosSale({
    required String locationId,
    required String requestId,
    required Map<String, dynamic> payload,
  }) async {
    _requireRequestId(requestId);
    final resolvedDeviceId = _requiredGatewayDevice();

    return _callRoute('sale_sync', <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_device_id': resolvedDeviceId,
      'p_location_id': locationId,
      'p_request_id': requestId,
      'p_payload': payload,
    });
  }

  // ---------------------------------------------------------------------------
  // MOBILE POS
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> syncMobilePosSale({
    required String requestId,
    required Map<String, dynamic> payload,
  }) async {
    _requireRequestId(requestId);
    final resolvedDeviceId = _requiredGatewayDevice();

    return _callRoute('sale_sync', <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_device_id': resolvedDeviceId,
      'p_request_id': requestId,
      'p_payload': payload,
    });
  }

  // ---------------------------------------------------------------------------
  // GST & COMPLIANCE WORKSPACE
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> loadGstWorkspace() async {
    return _callRoute('gst_workspace', <String, dynamic>{
      'p_tenant_id': tenantId,
    });
  }

  // ---------------------------------------------------------------------------
  // LOW-LEVEL GUARDED ROUTING
  // ---------------------------------------------------------------------------

  String routeFor(String routeKey) {
    final routes = channelRoutes;
    final raw = routes[routeKey];

    if (raw == null || raw.toString().trim().isEmpty) {
      throw GstV520Exception(
        'GST v5.2 route "$routeKey" is not enabled for '
        '${channel.wireName}. No legacy fallback will be attempted.',
      );
    }

    final rpc = raw.toString().trim();

    if (!_isApprovedV520Rpc(rpc)) {
      throw GstV520Exception(
        'Backend published an unapproved GST route "$rpc".',
      );
    }

    return rpc;
  }

  Future<Map<String, dynamic>> _callRoute(
    String routeKey,
    Map<String, dynamic> params,
  ) async {
    final rpc = routeFor(routeKey);

    try {
      final raw = await _client.rpc(rpc, params: params);
      return _asMap(raw, fieldName: rpc);
    } catch (error) {
      throw GstV520Exception(
        'Authoritative GST v5.2 RPC "$rpc" failed. '
        'Legacy v5.1 fallback is disabled for this transaction. '
        'Retry only with the same request ID when the writer supports '
        'idempotent retry. Original error: $error',
      );
    }
  }

  Future<dynamic> _rpcDirect(String rpc, Map<String, dynamic> params) async {
    try {
      return await _client.rpc(rpc, params: params);
    } catch (error) {
      throw GstV520Exception('GST v5.2 contract RPC "$rpc" failed: $error');
    }
  }

  static bool _isApprovedV520Rpc(String rpc) {
    const approved = <String>{
      'gst_sale_create_v520',
      'gst_sale_create_v522',
      'gst_pos_sale_create_v522',
      'gst_pos_offline_sale_sync_v522',
      'gst_mobile_pos_sale_sync_v522',
      'gst_purchase_create_v520',
      'gst_purchase_invoice_create_v520',
      'gst_sales_return_create_v520',
      'gst_purchase_return_create_v520',
      'gst_service_job_bill_v520',
      'gst_restaurant_order_bill_v520',
      'gst_pos_offline_sale_sync_v520',
      'gst_mobile_pos_sale_sync_v520',
      'mobile_pos_restaurant_bill_v520',
      'gst_ui_contract_v520',
      'pos_offline_api_contract_v520',
      'mobile_pos_api_contract_v520',
    };

    return approved.contains(rpc);
  }

  static Map<String, dynamic> _asMap(dynamic raw, {required String fieldName}) {
    if (raw is Map<String, dynamic>) {
      return Map<String, dynamic>.from(raw);
    }

    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }

    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    }

    throw GstV520Exception(
      'Expected JSON object from "$fieldName", got '
      '${raw.runtimeType}.',
    );
  }

  static void _putIfNotNull(
    Map<String, dynamic> target,
    String key,
    dynamic value,
  ) {
    if (value != null) {
      target[key] = value;
    }
  }

  static void _requireRequestId(String requestId) {
    if (requestId.trim().isEmpty) {
      throw const GstV520Exception(
        'A stable request ID is required for GST v5.2 writes.',
      );
    }
  }

  String _requiredGatewayDevice() {
    final value = deviceId?.trim();
    if (value == null || value.isEmpty) {
      throw GstV520Exception('Device ID is required for ${channel.wireName}.');
    }
    return value;
  }

  static String _dateOnly(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
