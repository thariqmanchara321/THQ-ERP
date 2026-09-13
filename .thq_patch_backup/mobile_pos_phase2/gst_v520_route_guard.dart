import 'package:supabase_flutter/supabase_flutter.dart';

/// Mobile POS GST cutover guard.
///
/// The filename/class name is retained for source compatibility, but this guard
/// enforces the v5.2.2 Build 30 transaction contract. It fails closed and never
/// falls back to a legacy writer after an authoritative route failure.
class GstV520RouteGuard {
  GstV520RouteGuard({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _approved = <String>{
    'gst_mobile_pos_sale_sync_v522',
    'mobile_pos_restaurant_bill_v520',
    'mobile_pos_api_contract_v520',
  };

  Future<String> route({
    required String tenantId,
    required String channel,
    required String routeKey,
    String? deviceId,
  }) async {
    final raw = await _client.rpc(
      'gst_transaction_cutover_contract_v522',
      params: {
        'p_tenant_id': tenantId,
        'p_channel': channel,
        'p_device_id': deviceId,
      },
    );

    if (raw is! Map) {
      throw StateError(
        'GST v5.2.2 cutover contract returned an invalid response.',
      );
    }
    final contract = Map<String, dynamic>.from(raw);

    if (contract['cutover_ready'] != true) {
      final reason = contract['blocking_reason']?.toString();
      final taxMode = contract['tax_mode']?.toString() ?? 'unconfigured';
      final detail = reason == 'tax_mode_unconfigured'
          ? 'Choose GST Registered or Non-GST in GST & Compliance first.'
          : (reason?.isNotEmpty == true ? reason! : 'Backend not ready.');
      throw StateError(
        'GST v5.2.2 transaction cutover is blocked: $detail '
        '(tax mode: $taxMode).',
      );
    }

    if (contract['activation_mode'] != 'explicit_app_rpc_switch') {
      throw StateError('Unexpected GST v5.2.2 activation mode.');
    }
    if (contract['version']?.toString() != '5.2.2' ||
        contract['build']?.toString() != '30') {
      throw StateError(
        'GST backend is not advertising the required v5.2.2 Build 30 contract.',
      );
    }
    if (contract['legacy_fallback_after_v522_failure'] != false) {
      throw StateError(
        'Unsafe GST v5.2.2 contract: legacy fallback must be disabled.',
      );
    }

    final rulesRaw = contract['rules'];
    final rules = rulesRaw is Map
        ? Map<String, dynamic>.from(rulesRaw)
        : <String, dynamic>{};

    // v5.2.2 extends the v5.2 base contract, so both base safety guarantees
    // and the Build 30 top-level fallback guarantee are required.
    if (rules['v520_route_requires_v520_writer'] != true ||
        rules['legacy_fallback_after_v520_route'] != false ||
        rules['tax_calculation'] != 'server_authoritative_only' ||
        rules['authoritative_evidence'] != 'same_transaction' ||
        rules['authoritative_accounting'] != 'same_transaction') {
      throw StateError(
        'Unsafe GST v5.2.2 base cutover rules. Transaction blocked.',
      );
    }

    final routesRaw = contract['channel_routes'];
    final routes = routesRaw is Map
        ? Map<String, dynamic>.from(routesRaw)
        : <String, dynamic>{};
    final rpc = routes[routeKey]?.toString().trim() ?? '';

    if (rpc.isEmpty || !_approved.contains(rpc)) {
      throw StateError(
        'GST v5.2.2 route "$routeKey" is not approved for $channel. '
        'Legacy fallback is disabled.',
      );
    }
    return rpc;
  }
}
