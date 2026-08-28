/// Transport-neutral THQ API request contract.
///
/// Flutter applications should depend on this contract rather than on a
/// Supabase-specific shape. The current adapter is a Supabase Edge Function;
/// future adapters can sit behind the same API without changing callers.
class ThqApiRequest {
  final String tenantId;
  final String resource;
  final String action;
  final Map<String, dynamic> payload;

  const ThqApiRequest({
    required this.tenantId,
    required this.resource,
    this.action = 'get',
    this.payload = const <String, dynamic>{},
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'tenant_id': tenantId,
        'resource': resource,
        'action': action,
        'payload': payload,
      };
}

class ThqSyncVersions {
  final int configuration;
  final int catalogue;
  final int parties;
  final int transactions;
  final int inventory;
  final int finance;
  final DateTime? updatedAt;

  const ThqSyncVersions({
    required this.configuration,
    required this.catalogue,
    required this.parties,
    required this.transactions,
    required this.inventory,
    required this.finance,
    this.updatedAt,
  });

  factory ThqSyncVersions.fromMap(Map<String, dynamic> map) => ThqSyncVersions(
        configuration: (map['configuration'] as num?)?.toInt() ?? 1,
        catalogue: (map['catalogue'] as num?)?.toInt() ?? 1,
        parties: (map['parties'] as num?)?.toInt() ?? 1,
        transactions: (map['transactions'] as num?)?.toInt() ?? 1,
        inventory: (map['inventory'] as num?)?.toInt() ?? 1,
        finance: (map['finance'] as num?)?.toInt() ?? 1,
        updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? ''),
      );

  bool configurationOrMasterChangedFrom(ThqSyncVersions other) =>
      configuration != other.configuration ||
      catalogue != other.catalogue ||
      parties != other.parties;

  bool anyChangedFrom(ThqSyncVersions other) =>
      configuration != other.configuration ||
      catalogue != other.catalogue ||
      parties != other.parties ||
      transactions != other.transactions ||
      inventory != other.inventory ||
      finance != other.finance;
}

abstract final class ThqApiContract {
  static const String version = 'v1';
  static const String adapter = 'supabase';
}
