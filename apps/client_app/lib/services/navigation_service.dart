import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_menu_node.dart';

class NavigationService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<AppMenuNode>> load({
    required String tenantId,
    required String appKey,
  }) async {
    final result = await _supabase.rpc(
      'app_menu_tree_v45',
      params: {'p_tenant_id': tenantId, 'p_app_key': appKey},
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => AppMenuNode.fromMap(Map<String, dynamic>.from(row)))
        .where((node) => node.enabled)
        .toList()
      ..sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : a.label.compareTo(b.label);
      });
  }
}
