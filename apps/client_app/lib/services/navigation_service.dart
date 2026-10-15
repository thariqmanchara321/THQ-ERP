import 'package:erp_core/erp_core.dart';
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

  Future<ThqUserUiPreferences> loadUserPreferences(String appScope) async {
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
}
