import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// THQ ERP v5.2 GST & Compliance data layer.
///
/// Backend requirements:
/// - gst_compliance_bootstrap_v520       (migration 248)
/// - gst_setup_lookups_v520              (migration 251)
/// - gst_ui_contract_v520 contract v4    (migration 252)
/// - GST v5.2 PUBLIC/anon execute hardening (migration 250)
///
/// Design rules:
/// - Flutter never calculates GST.
/// - The server UI contract is the source of truth for available tabs/RPCs.
/// - E-Invoice / E-Way Bill provider submission remains disabled.
/// - Legacy transactions are view-only legacy_unverified evidence.
/// - No v5.1 transaction fallback is performed from this service.
class GstComplianceV520Exception implements Exception {
  const GstComplianceV520Exception(this.message);

  final String message;

  @override
  String toString() => 'GstComplianceV520Exception: $message';
}

class GstComplianceV520Service {
  GstComplianceV520Service({required this.client, required this.tenantId});

  final SupabaseClient client;
  final String tenantId;

  GstComplianceBootstrapV520? _bootstrap;

  GstComplianceBootstrapV520 get bootstrap {
    final value = _bootstrap;
    if (value == null) {
      throw const GstComplianceV520Exception(
        'GST & Compliance is not initialized. Call initialize() first.',
      );
    }
    return value;
  }

  bool get isInitialized => _bootstrap != null;

  GstUiContractV520 get uiContract => bootstrap.uiContract;

  Map<String, dynamic> get capabilities => uiContract.capabilities;

  bool can(String capability) => capabilities[capability] == true;

  List<GstUiTabV520> get visibleTabs =>
      uiContract.tabs.where((tab) => tab.enabled).toList(growable: false);

  /// Initial load for the GST & Compliance workspace.
  ///
  /// One backend call returns:
  /// - UI contract
  /// - Overview workspace
  /// - GST masters
  /// - compliance readiness
  /// - first transaction page
  Future<GstComplianceBootstrapV520> initialize({
    DateTime? from,
    DateTime? to,
    String? locationId,
    int documentLimit = 50,
  }) async {
    _requireTenant();

    if (documentLimit < 1 || documentLimit > 100) {
      throw const GstComplianceV520Exception(
        'Document limit must be between 1 and 100.',
      );
    }

    final raw = await _rpc('gst_compliance_bootstrap_v520', <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_from': from == null ? null : _dateOnly(from),
      'p_to': to == null ? null : _dateOnly(to),
      'p_location_id': _nullableText(locationId),
      'p_document_limit': documentLimit,
    });

    final parsed = GstComplianceBootstrapV520.fromJson(
      _asMap(raw, fieldName: 'gst_compliance_bootstrap_v520'),
    );

    _validateBootstrap(parsed);
    _bootstrap = parsed;
    return parsed;
  }

  Future<GstComplianceBootstrapV520> refresh({
    DateTime? from,
    DateTime? to,
    String? locationId,
    int documentLimit = 50,
  }) {
    return initialize(
      from: from,
      to: to,
      locationId: locationId,
      documentLimit: documentLimit,
    );
  }

  // ---------------------------------------------------------------------------
  // OVERVIEW / READINESS / MASTERS
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> loadOverview({
    required DateTime from,
    required DateTime to,
    String? locationId,
  }) async {
    _requireInitialized();
    final rpc = uiContract.rpcForTab('overview', 'rpc');

    return _rpcMap(rpc, <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_from': _dateOnly(from),
      'p_to': _dateOnly(to),
      'p_location_id': _nullableText(locationId),
    });
  }

  Future<Map<String, dynamic>> loadMasters({DateTime? date}) async {
    _requireInitialized();

    return _rpcMap(uiContract.mastersRpc, <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_date': _dateOnly(date ?? DateTime.now()),
    });
  }

  Future<Map<String, dynamic>> loadReadiness() async {
    _requireInitialized();

    return _rpcMap(uiContract.readinessRpc, <String, dynamic>{
      'p_tenant_id': tenantId,
    });
  }

  /// Active THQ entities used by GST setup dialogs.
  ///
  /// Kinds: all, locations, products, customers, suppliers.
  /// The backend applies GST permission and location-scope rules.
  Future<Map<String, dynamic>> loadSetupLookups({
    required String kind,
    String query = '',
    int limit = 200,
  }) async {
    _requireInitialized();

    const allowedKinds = <String>{
      'all',
      'locations',
      'products',
      'customers',
      'suppliers',
    };

    final normalizedKind = kind.trim().toLowerCase();
    if (!allowedKinds.contains(normalizedKind)) {
      throw GstComplianceV520Exception(
        'Unsupported GST setup lookup kind "$kind".',
      );
    }

    if (limit < 1 || limit > 500) {
      throw const GstComplianceV520Exception(
        'GST setup lookup limit must be between 1 and 500.',
      );
    }

    if (normalizedKind != 'locations') {
      _requireManage();
    } else {
      _requireView();
    }

    return _rpcMap(uiContract.setupLookupRpc, <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_kind': normalizedKind,
      'p_query': query.trim(),
      'p_limit': limit,
    });
  }

  // ---------------------------------------------------------------------------
  // REGISTRATIONS
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> listRegistrations() async {
    _requireView();
    final rpc = uiContract.rpcForTab('registrations', 'list_rpc');

    return _rpcList(rpc, <String, dynamic>{'p_tenant_id': tenantId});
  }

  Future<String> saveRegistration({
    String? id,
    required String gstin,
    required String legalName,
    String? tradeName,
    required String registrationType,
    required String stateCode,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? postalCode,
    bool einvoiceEnabled = false,
    bool ewaybillEnabled = false,
    bool returnsEnabled = true,
    String? providerKey,
    bool active = true,
    required DateTime effectiveFrom,
  }) async {
    _requireCapability('configure');

    if (gstin.trim().isEmpty) {
      throw const GstComplianceV520Exception('GSTIN is required.');
    }
    if (legalName.trim().isEmpty) {
      throw const GstComplianceV520Exception('Legal name is required.');
    }
    if (stateCode.trim().isEmpty) {
      throw const GstComplianceV520Exception('State code is required.');
    }

    // Provider toggles may be stored for configuration/readiness,
    // but this service never submits to GSP/IRP.
    final rpc = uiContract.rpcForTab('registrations', 'save_rpc');

    final raw = await _rpc(rpc, <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_id': _nullableText(id),
      'p_gstin': gstin.trim().toUpperCase(),
      'p_legal_name': legalName.trim(),
      'p_trade_name': _nullableText(tradeName),
      'p_registration_type': registrationType.trim(),
      'p_state_code': stateCode.trim(),
      'p_address_line1': _nullableText(addressLine1),
      'p_address_line2': _nullableText(addressLine2),
      'p_city': _nullableText(city),
      'p_postal_code': _nullableText(postalCode),
      'p_einvoice_enabled': einvoiceEnabled,
      'p_ewaybill_enabled': ewaybillEnabled,
      'p_returns_enabled': returnsEnabled,
      'p_provider_key': _nullableText(providerKey),
      'p_active': active,
      'p_effective_from': _dateOnly(effectiveFrom),
    });

    final savedId = raw?.toString().trim() ?? '';
    if (savedId.isEmpty) {
      throw const GstComplianceV520Exception(
        'GST registration save returned no ID.',
      );
    }

    return savedId;
  }

  Future<Map<String, dynamic>> loadRegistrationConfig({
    required String registrationId,
    DateTime? date,
  }) async {
    _requireView();

    final rpc = uiContract.rpcForTab('registrations', 'config_rpc');

    return _rpcMap(rpc, <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_registration_id': registrationId,
      'p_date': _dateOnly(date ?? DateTime.now()),
    });
  }

  /// Maps a THQ business location to a GST registration.
  ///
  /// This closes the readiness blocker where a registration exists but a
  /// business location has no effective GST registration mapping.
  Future<void> mapLocationToRegistration({
    required String locationId,
    required String registrationId,
    required DateTime effectiveFrom,
  }) async {
    _requireCapability('configure');

    final rpc = uiContract.rpcForTab('registrations', 'location_map_rpc');

    await _rpc(rpc, <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_location_id': locationId,
      'p_registration_id': registrationId,
      'p_effective_from': _dateOnly(effectiveFrom),
    });
  }

  // ---------------------------------------------------------------------------
  // PRODUCT GST
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> listProductProfiles({
    String query = '',
    String? status,
    int limit = 500,
  }) async {
    _requireView();
    final rpc = uiContract.rpcForTab('products', 'list_rpc');

    return _rpcList(rpc, <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_query': query.trim(),
      'p_status': _nullableText(status),
      'p_limit': limit,
    });
  }

  Future<String> saveProductProfile({
    required String variantId,
    required String supplyKind,
    required String hsnSac,
    required String taxability,
    required num gstRate,
    num cessRate = 0,
    num cessPerUnit = 0,
    bool taxInclusive = false,
    bool reverseCharge = false,
    String? notes,
    required DateTime effectiveFrom,
  }) async {
    _requireManage();

    if (hsnSac.trim().isEmpty) {
      throw const GstComplianceV520Exception('HSN/SAC is required.');
    }
    if (gstRate < 0) {
      throw const GstComplianceV520Exception('GST rate cannot be negative.');
    }

    final rpc = uiContract.rpcForTab('products', 'save_rpc');

    final raw = await _rpc(rpc, <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_variant_id': variantId,
      'p_supply_kind': supplyKind.trim(),
      'p_hsn_sac': hsnSac.trim(),
      'p_taxability': taxability.trim(),
      'p_gst_rate': gstRate,
      'p_cess_rate': cessRate,
      'p_cess_per_unit': cessPerUnit,
      'p_tax_inclusive': taxInclusive,
      'p_reverse_charge': reverseCharge,
      'p_notes': _nullableText(notes),
      'p_effective_from': _dateOnly(effectiveFrom),
    });

    final id = raw?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw const GstComplianceV520Exception(
        'Product GST profile save returned no ID.',
      );
    }
    return id;
  }

  // ---------------------------------------------------------------------------
  // PARTY GST
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> listPartyProfiles({
    String? partyType,
    String query = '',
    int limit = 300,
  }) async {
    _requireView();
    final rpc = uiContract.rpcForTab('parties', 'list_rpc');

    return _rpcList(rpc, <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_party_type': _nullableText(partyType),
      'p_query': query.trim(),
      'p_limit': limit,
    });
  }

  Future<String> savePartyProfile({
    String? id,
    required String partyType,
    required String partyId,
    required String registrationType,
    String? gstin,
    String? legalName,
    String? tradeName,
    String? stateCode,
    String? placeOfSupplyCode,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? postalCode,
    String country = 'IN',
    bool active = true,
  }) async {
    _requireManage();

    final rpc = uiContract.rpcForTab('parties', 'save_rpc');

    final raw = await _rpc(rpc, <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_id': _nullableText(id),
      'p_party_type': partyType.trim(),
      'p_party_id': partyId,
      'p_registration_type': registrationType.trim(),
      'p_gstin': _nullableUpper(gstin),
      'p_legal_name': _nullableText(legalName),
      'p_trade_name': _nullableText(tradeName),
      'p_state_code': _nullableText(stateCode),
      'p_place_of_supply_code': _nullableText(placeOfSupplyCode),
      'p_address_line1': _nullableText(addressLine1),
      'p_address_line2': _nullableText(addressLine2),
      'p_city': _nullableText(city),
      'p_postal_code': _nullableText(postalCode),
      'p_country': country.trim().isEmpty ? 'IN' : country.trim(),
      'p_active': active,
    });

    final savedId = raw?.toString().trim() ?? '';
    if (savedId.isEmpty) {
      throw const GstComplianceV520Exception(
        'Party GST profile save returned no ID.',
      );
    }
    return savedId;
  }

  // ---------------------------------------------------------------------------
  // GST TRANSACTIONS / EVIDENCE
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> listDocuments({
    DateTime? from,
    DateTime? to,
    String? locationId,
    String? sourceType,
    String evidenceStatus = 'all',
    String query = '',
    int limit = 100,
    int offset = 0,
  }) async {
    _requireView();

    if (limit < 1 || limit > 500) {
      throw const GstComplianceV520Exception(
        'Document list limit must be between 1 and 500.',
      );
    }
    if (offset < 0) {
      throw const GstComplianceV520Exception(
        'Document offset cannot be negative.',
      );
    }

    final rpc = uiContract.rpcForTab('transactions', 'list_rpc');

    return _rpcMap(rpc, <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_from': from == null ? null : _dateOnly(from),
      'p_to': to == null ? null : _dateOnly(to),
      'p_location_id': _nullableText(locationId),
      'p_source_type': _nullableText(sourceType),
      'p_evidence_status': evidenceStatus.trim().isEmpty
          ? 'all'
          : evidenceStatus.trim(),
      'p_query': query.trim(),
      'p_limit': limit,
      'p_offset': offset,
    });
  }

  Future<Map<String, dynamic>> loadDocumentEvidence({
    required String sourceType,
    required String sourceId,
  }) async {
    _requireView();
    final rpc = uiContract.rpcForTab('transactions', 'detail_rpc');

    return _rpcMap(rpc, <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_source_type': sourceType.trim(),
      'p_source_id': sourceId,
    });
  }

  // ---------------------------------------------------------------------------
  // TAX SUMMARY / RETURNS PREVIEW
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> loadTaxSummary({
    required DateTime from,
    required DateTime to,
    String? locationId,
  }) async {
    _requireView();
    final rpc = uiContract.rpcForTab('tax_summary', 'rpc');

    return _rpcMap(rpc, <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_from': _dateOnly(from),
      'p_to': _dateOnly(to),
      'p_location_id': _nullableText(locationId),
    });
  }

  /// Return filing preview only.
  ///
  /// This intentionally does not submit returns or call a GSP.
  Future<Map<String, dynamic>> loadReturnsPreview({
    required DateTime from,
    required DateTime to,
    String? locationId,
  }) async {
    _requireCapability('returns');

    final tab = uiContract.tab('returns');
    if (tab.data['submission_enabled'] == true) {
      throw const GstComplianceV520Exception(
        'Unexpected server contract: return submission must still be disabled.',
      );
    }

    final rpc = tab.requireString('preview_rpc');

    return _rpcMap(rpc, <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_from': _dateOnly(from),
      'p_to': _dateOnly(to),
      'p_location_id': _nullableText(locationId),
    });
  }

  // ---------------------------------------------------------------------------
  // GST ACCOUNTING
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> loadAccountingHealth() async {
    _requireCapability('reconcile');

    final rpc = uiContract.rpcForTab('accounting', 'health_rpc');

    return _rpcMap(rpc, <String, dynamic>{'p_tenant_id': tenantId});
  }

  Future<Map<String, dynamic>> loadAccountingControl({
    required DateTime from,
    required DateTime to,
    String? locationId,
  }) async {
    _requireCapability('reconcile');

    final rpc = uiContract.rpcForTab('accounting', 'control_rpc');

    return _rpcMap(rpc, <String, dynamic>{
      'p_tenant_id': tenantId,
      'p_from': _dateOnly(from),
      'p_to': _dateOnly(to),
      'p_location_id': _nullableText(locationId),
    });
  }

  // ---------------------------------------------------------------------------
  // PROVIDER FEATURES - INTENTIONALLY BLOCKED
  // ---------------------------------------------------------------------------

  Never submitEinvoice() {
    throw const GstComplianceV520Exception(
      'E-Invoice submission is disabled. '
      'GSP/IRP provider integration has not started.',
    );
  }

  Never submitEwayBill() {
    throw const GstComplianceV520Exception(
      'E-Way Bill submission is disabled. '
      'GSP/IRP provider integration has not started.',
    );
  }

  Never cancelIrn() {
    throw const GstComplianceV520Exception(
      'IRN cancellation is disabled until the GSP/IRP phase.',
    );
  }

  // ---------------------------------------------------------------------------
  // CONTRACT / PERMISSION GUARDS
  // ---------------------------------------------------------------------------

  void _validateBootstrap(GstComplianceBootstrapV520 value) {
    if (value.uiContract.contractVersion < 4) {
      throw GstComplianceV520Exception(
        'GST UI contract v4 or newer is required; received '
        '${value.uiContract.contractVersion}.',
      );
    }

    if (value.rules['tax_calculation'] != 'server_authoritative_only') {
      throw const GstComplianceV520Exception(
        'Unsafe GST contract: server must remain tax authority.',
      );
    }

    if (value.rules['v520_failure_fallback'] != false) {
      throw const GstComplianceV520Exception(
        'Unsafe GST contract: v5.2 failure fallback must be false.',
      );
    }

    if (value.rules['provider_submission'] != false) {
      throw const GstComplianceV520Exception(
        'Unexpected GST provider state: provider submission must be disabled.',
      );
    }

    final registrationTab = value.uiContract.tab('registrations');
    registrationTab.requireString('location_map_rpc');

    if (value.uiContract.setupLookupRpc != 'gst_setup_lookups_v520') {
      throw GstComplianceV520Exception(
        'Unexpected GST setup lookup RPC '
        '"${value.uiContract.setupLookupRpc}".',
      );
    }
  }

  void _requireTenant() {
    if (tenantId.trim().isEmpty) {
      throw const GstComplianceV520Exception('Tenant ID is required.');
    }
  }

  void _requireInitialized() {
    if (_bootstrap == null) {
      throw const GstComplianceV520Exception(
        'GST & Compliance is not initialized.',
      );
    }
  }

  void _requireView() {
    _requireInitialized();
    _requireCapability('view');
  }

  void _requireManage() {
    _requireInitialized();
    _requireCapability('manage');
  }

  void _requireCapability(String capability) {
    if (!can(capability)) {
      throw GstComplianceV520Exception(
        'GST permission "$capability" is required.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // RPC HELPERS
  // ---------------------------------------------------------------------------

  Future<dynamic> _rpc(String rpc, Map<String, dynamic> params) async {
    _assertApprovedRpc(rpc);

    try {
      return await client.rpc(rpc, params: params);
    } catch (error) {
      throw GstComplianceV520Exception('GST v5.2 RPC "$rpc" failed: $error');
    }
  }

  Future<Map<String, dynamic>> _rpcMap(
    String rpc,
    Map<String, dynamic> params,
  ) async {
    final raw = await _rpc(rpc, params);
    return _asMap(raw, fieldName: rpc);
  }

  Future<List<Map<String, dynamic>>> _rpcList(
    String rpc,
    Map<String, dynamic> params,
  ) async {
    final raw = await _rpc(rpc, params);
    return _asListOfMaps(raw, fieldName: rpc);
  }

  static void _assertApprovedRpc(String rpc) {
    const approved = <String>{
      'gst_compliance_bootstrap_v520',
      'gst_compliance_workspace_v520',
      'gst_compliance_readiness_v520',
      'gst_setup_lookups_v520',
      'gst_masters_v520',
      'gst_registrations_list_v520',
      'gst_registration_save_v520',
      'gst_registration_config_v520',
      'gst_location_registration_set_v520',
      'gst_product_profiles_list_v520',
      'gst_product_profile_save_v520',
      'gst_party_profiles_list_v520',
      'gst_party_profile_save_v520',
      'gst_documents_list_v520',
      'gst_document_evidence_v520',
      'gst_period_summary_v520',
      'gst_accounting_health_v520',
      'gst_accounting_control_v520',
    };

    if (!approved.contains(rpc)) {
      throw GstComplianceV520Exception(
        'Server published unapproved GST UI RPC "$rpc".',
      );
    }
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

    throw GstComplianceV520Exception(
      'Expected JSON object from "$fieldName", got '
      '${raw.runtimeType}.',
    );
  }

  static List<Map<String, dynamic>> _asListOfMaps(
    dynamic raw, {
    required String fieldName,
  }) {
    dynamic value = raw;

    if (value is String) {
      value = jsonDecode(value);
    }

    if (value is! List) {
      throw GstComplianceV520Exception(
        'Expected JSON list from "$fieldName", got '
        '${value.runtimeType}.',
      );
    }

    return value
        .map<Map<String, dynamic>>((entry) {
          if (entry is Map<String, dynamic>) {
            return Map<String, dynamic>.from(entry);
          }
          if (entry is Map) {
            return entry.map((key, value) => MapEntry(key.toString(), value));
          }
          throw GstComplianceV520Exception(
            'Invalid list item returned by "$fieldName".',
          );
        })
        .toList(growable: false);
  }

  static String _dateOnly(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String? _nullableText(String? value) {
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }
    return cleaned;
  }

  static String? _nullableUpper(String? value) {
    return _nullableText(value)?.toUpperCase();
  }
}

// =============================================================================
// BOOTSTRAP / CONTRACT MODELS
// =============================================================================

class GstComplianceBootstrapV520 {
  const GstComplianceBootstrapV520({
    required this.release,
    required this.contractVersion,
    required this.serverDate,
    required this.period,
    required this.rules,
    required this.uiContract,
    required this.workspace,
    required this.masters,
    required this.readiness,
    required this.documents,
    required this.defaults,
  });

  final String release;
  final int contractVersion;
  final String serverDate;
  final Map<String, dynamic> period;
  final Map<String, dynamic> rules;
  final GstUiContractV520 uiContract;
  final Map<String, dynamic> workspace;
  final Map<String, dynamic> masters;
  final Map<String, dynamic> readiness;
  final Map<String, dynamic> documents;
  final Map<String, dynamic> defaults;

  factory GstComplianceBootstrapV520.fromJson(Map<String, dynamic> json) {
    return GstComplianceBootstrapV520(
      release: json['release']?.toString() ?? '',
      contractVersion: _asInt(json['contract_version']),
      serverDate: json['server_date']?.toString() ?? '',
      period: _map(json['period'], 'period'),
      rules: _map(json['rules'], 'rules'),
      uiContract: GstUiContractV520.fromJson(
        _map(json['ui_contract'], 'ui_contract'),
      ),
      workspace: _map(json['workspace'], 'workspace'),
      masters: _map(json['masters'], 'masters'),
      readiness: _map(json['readiness'], 'readiness'),
      documents: _map(json['documents'], 'documents'),
      defaults: _map(json['defaults'], 'defaults'),
    );
  }

  static Map<String, dynamic> _map(dynamic raw, String name) {
    if (raw is Map<String, dynamic>) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    throw GstComplianceV520Exception(
      'Bootstrap field "$name" is not a JSON object.',
    );
  }

  static int _asInt(dynamic raw) {
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}

class GstUiContractV520 {
  const GstUiContractV520({
    required this.release,
    required this.contractVersion,
    required this.workspace,
    required this.bootstrapRpc,
    required this.setupLookupRpc,
    required this.capabilities,
    required this.tabs,
    required this.mastersRpc,
    required this.readinessRpc,
    required this.rules,
  });

  final String release;
  final int contractVersion;
  final String workspace;
  final String bootstrapRpc;
  final String setupLookupRpc;
  final Map<String, dynamic> capabilities;
  final List<GstUiTabV520> tabs;
  final String mastersRpc;
  final String readinessRpc;
  final Map<String, dynamic> rules;

  factory GstUiContractV520.fromJson(Map<String, dynamic> json) {
    final rawTabs = json['tabs'];
    if (rawTabs is! List) {
      throw const GstComplianceV520Exception(
        'GST UI contract tabs must be a list.',
      );
    }

    return GstUiContractV520(
      release: json['release']?.toString() ?? '',
      contractVersion:
          int.tryParse(json['contract_version']?.toString() ?? '') ?? 0,
      workspace: json['workspace']?.toString() ?? 'GST & Compliance',
      bootstrapRpc:
          json['bootstrap_rpc']?.toString() ?? 'gst_compliance_bootstrap_v520',
      setupLookupRpc:
          json['setup_lookup_rpc']?.toString() ?? 'gst_setup_lookups_v520',
      capabilities: _map(json['capabilities'], 'capabilities'),
      tabs: rawTabs
          .map((entry) => GstUiTabV520.fromJson(_map(entry, 'tab')))
          .toList(growable: false),
      mastersRpc: json['masters_rpc']?.toString() ?? '',
      readinessRpc: json['readiness_rpc']?.toString() ?? '',
      rules: _map(json['rules'], 'rules'),
    );
  }

  GstUiTabV520 tab(String key) {
    for (final tab in tabs) {
      if (tab.key == key) {
        return tab;
      }
    }

    throw GstComplianceV520Exception(
      'GST UI tab "$key" is not present in the server contract.',
    );
  }

  String rpcForTab(String tabKey, String rpcKey) {
    return tab(tabKey).requireString(rpcKey);
  }

  static Map<String, dynamic> _map(dynamic raw, String name) {
    if (raw is Map<String, dynamic>) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    throw GstComplianceV520Exception(
      'GST UI contract "$name" is not a JSON object.',
    );
  }
}

class GstUiTabV520 {
  const GstUiTabV520({
    required this.key,
    required this.label,
    required this.permission,
    required this.enabled,
    required this.data,
  });

  final String key;
  final String label;
  final String permission;
  final bool enabled;
  final Map<String, dynamic> data;

  factory GstUiTabV520.fromJson(Map<String, dynamic> json) {
    return GstUiTabV520(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      permission: json['permission']?.toString() ?? '',
      enabled: json['enabled'] == true,
      data: Map<String, dynamic>.from(json),
    );
  }

  String requireString(String field) {
    final value = data[field]?.toString().trim() ?? '';
    if (value.isEmpty) {
      throw GstComplianceV520Exception(
        'GST UI tab "$key" is missing "$field".',
      );
    }
    return value;
  }
}

// =============================================================================
// SIMPLE CONTROLLER
// =============================================================================

/// Lightweight state controller that does not depend on Provider/Riverpod/Bloc.
///
/// Your existing THQ Client can wrap this in its current state-management layer.
class GstComplianceV520Controller {
  GstComplianceV520Controller(this.service);

  final GstComplianceV520Service service;

  bool loading = false;
  Object? error;

  DateTime from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime to = DateTime.now();
  String? locationId;

  GstComplianceBootstrapV520? data;

  Future<GstComplianceBootstrapV520> load() async {
    loading = true;
    error = null;

    try {
      final result = await service.initialize(
        from: from,
        to: to,
        locationId: locationId,
      );
      data = result;
      return result;
    } catch (e) {
      error = e;
      rethrow;
    } finally {
      loading = false;
    }
  }

  Future<GstComplianceBootstrapV520> refresh() => load();

  Future<GstComplianceBootstrapV520> changePeriod({
    required DateTime from,
    required DateTime to,
    String? locationId,
  }) async {
    if (from.isAfter(to)) {
      throw const GstComplianceV520Exception(
        'From date cannot be after To date.',
      );
    }

    this.from = from;
    this.to = to;
    this.locationId = locationId;
    return load();
  }

  bool can(String capability) => service.can(capability);

  List<GstUiTabV520> get visibleTabs => service.visibleTabs;
}
