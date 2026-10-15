import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThqAppScope Canonical Resolution Tests', () {
    test('resolves standard keys and logical names correctly', () {
      expect(ThqAppScope.fromString('client'), ThqAppScope.businessDesktop);
      expect(ThqAppScope.fromString('business_desktop'), ThqAppScope.businessDesktop);
      expect(ThqAppScope.canonicalKey('business_desktop'), 'client');

      expect(ThqAppScope.fromString('pos'), ThqAppScope.posDesktop);
      expect(ThqAppScope.fromString('pos_desktop'), ThqAppScope.posDesktop);
      expect(ThqAppScope.canonicalKey('pos_desktop'), 'pos');

      expect(ThqAppScope.fromString('client_mobile'), ThqAppScope.mobileErp);
      expect(ThqAppScope.fromString('mobile_erp'), ThqAppScope.mobileErp);
      expect(ThqAppScope.canonicalKey('mobile_erp'), 'client_mobile');

      expect(ThqAppScope.fromString('mobile_pos'), ThqAppScope.posMobile);
      expect(ThqAppScope.fromString('pos_mobile'), ThqAppScope.posMobile);
      expect(ThqAppScope.canonicalKey('pos_mobile'), 'mobile_pos');

      expect(ThqAppScope.fromString('admin'), ThqAppScope.admin);
      expect(ThqAppScope.canonicalKey('admin'), 'admin');
    });

    test('handles unknown and null values with safe fallback to businessDesktop', () {
      expect(ThqAppScope.fromString(null), ThqAppScope.businessDesktop);
      expect(ThqAppScope.fromString('unknown_scope'), ThqAppScope.businessDesktop);
      expect(ThqAppScope.canonicalKey('unknown'), 'client');
    });
  });

  group('ThqModuleDefinition Tests', () {
    test('supports scope checking correctly', () {
      const module = ThqModuleDefinition(
        key: 'aggregate_yard',
        name: 'Material Yard & Quarry',
        supportedScopes: ['client', 'client_mobile'],
      );

      expect(module.supportsScope('client'), isTrue);
      expect(module.supportsScope('business_desktop'), isTrue);
      expect(module.supportsScope('mobile_erp'), isTrue);
      expect(module.supportsScope('client_mobile'), isTrue);
      expect(module.supportsScope('pos'), isFalse);
      expect(module.supportsScope('mobile_pos'), isFalse);
    });

    test('serializes and deserializes consistently', () {
      final map = {
        'key': 'sales',
        'name': 'Sales Register',
        'description': 'Billing and invoices',
        'category': 'Sales',
        'sort_order': 10,
        'is_core': true,
        'is_active': true,
        'is_beta': false,
        'requires_configuration': false,
        'minimum_plan_key': 'starter',
        'dependencies': ['inventory'],
        'supported_scopes': ['client', 'pos', 'client_mobile', 'mobile_pos'],
      };

      final parsed = ThqModuleDefinition.fromMap(map);
      expect(parsed.key, 'sales');
      expect(parsed.name, 'Sales Register');
      expect(parsed.isCore, isTrue);
      expect(parsed.dependencies, contains('inventory'));
      expect(parsed.supportsScope('pos_desktop'), isTrue);
    });
  });

  group('ThqUserUiPreferences Personalization Tests', () {
    test('initializes with default values and proper scope', () {
      final pref = ThqUserUiPreferences.defaults('mobile_erp');
      expect(pref.appScope, 'client_mobile');
      expect(pref.isDefault, isTrue);
      expect(pref.favorites, isEmpty);
      expect(pref.hiddenNodes, isEmpty);
      expect(pref.tableDensity, 'compact');
    });

    test('toggles favorites and hidden nodes immutably', () {
      final initial = ThqUserUiPreferences.defaults('client');
      expect(initial.isFavorite('aggregate_yard'), isFalse);

      final added = initial.toggleFavorite('aggregate_yard');
      expect(added.isFavorite('aggregate_yard'), isTrue);
      expect(added.isDefault, isFalse);
      expect(initial.isFavorite('aggregate_yard'), isFalse); // Immutable

      final removed = added.toggleFavorite('aggregate_yard');
      expect(removed.isFavorite('aggregate_yard'), isFalse);

      final hidden = initial.toggleHidden('backup');
      expect(hidden.isHidden('backup'), isTrue);
      expect(initial.isHidden('backup'), isFalse);
    });

    test('serializes and deserializes cleanly', () {
      final pref = const ThqUserUiPreferences(
        appScope: 'client_mobile',
        favorites: {'sales', 'aggregate_yard'},
        hiddenNodes: {'support'},
        sortOrder: {'sales': 1, 'aggregate_yard': 2},
        quickActions: {'new_sale', 'new_load'},
        tableDensity: 'compact',
        defaultLandingModule: 'aggregate_yard',
        dashboardWidgets: ['revenue', 'loads_summary'],
        isDefault: false,
      );

      final map = pref.toMap();
      final restored = ThqUserUiPreferences.fromMap(map);

      expect(restored.appScope, 'client_mobile');
      expect(restored.favorites, containsAll(['sales', 'aggregate_yard']));
      expect(restored.hiddenNodes, contains('support'));
      expect(restored.sortOrder['sales'], 1);
      expect(restored.defaultLandingModule, 'aggregate_yard');
      expect(restored.dashboardWidgets, contains('loads_summary'));
    });
  });

  group('ThqNavigationNode Tests', () {
    test('supports groups and module nodes', () {
      const groupNode = ThqNavigationNode(
        id: 'g-1',
        nodeKey: 'operations',
        nodeType: 'group',
        label: 'Operations',
      );
      expect(groupNode.isGroup, isTrue);
      expect(groupNode.isModule, isFalse);

      const moduleNode = ThqNavigationNode(
        id: 'm-1',
        nodeKey: 'sales',
        nodeType: 'module',
        moduleKey: 'sales',
        parentId: 'g-1',
        label: 'Sales Billing',
      );
      expect(moduleNode.isModule, isTrue);
      expect(moduleNode.isGroup, isFalse);
      expect(moduleNode.parentId, 'g-1');
    });
  });
}
