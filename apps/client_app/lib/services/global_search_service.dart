import 'package:supabase_flutter/supabase_flutter.dart';

class GlobalSearchResult {
  final String entityType;
  final String entityId;
  final String publicId;
  final String title;
  final String subtitle;
  final String moduleKey;
  final String? locationId;

  const GlobalSearchResult({
    required this.entityType,
    required this.entityId,
    required this.publicId,
    required this.title,
    required this.subtitle,
    required this.moduleKey,
    required this.locationId,
  });

  factory GlobalSearchResult.fromMap(Map<String, dynamic> map) =>
      GlobalSearchResult(
        entityType: map['entity_type']?.toString() ?? '',
        entityId: map['entity_id']?.toString() ?? '',
        publicId: map['public_id']?.toString() ?? '',
        title: map['title']?.toString() ?? '',
        subtitle: map['subtitle']?.toString() ?? '',
        moduleKey: map['module_key']?.toString() ?? '',
        locationId: map['location_id']?.toString(),
      );
}

class GlobalSearchService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<GlobalSearchResult>> search({
    required String tenantId,
    required String query,
  }) async {
    if (query.trim().isEmpty) return const [];
    final result = await _supabase.rpc(
      'global_search_v4',
      params: {'p_tenant_id': tenantId, 'p_query': query.trim(), 'p_limit': 60},
    );
    return (result as List? ?? const [])
        .map(
          (row) =>
              GlobalSearchResult.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }
}
