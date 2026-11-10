import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  final sampleNodes = [
    const ThqNavigationNode(
      id: 'node-1',
      nodeKey: 'dashboard',
      nodeType: 'module',
      moduleKey: 'dashboard',
      label: 'Dashboard',
      iconKey: 'space_dashboard',
      sortOrder: 10,
    ),
    const ThqNavigationNode(
      id: 'node-2',
      nodeKey: 'sales',
      nodeType: 'module',
      moduleKey: 'sales',
      label: 'Sales',
      iconKey: 'receipt_long',
      sortOrder: 20,
    ),
    const ThqNavigationNode(
      id: 'node-3',
      nodeKey: 'purchases',
      nodeType: 'module',
      moduleKey: 'purchases',
      label: 'Purchases',
      iconKey: 'shopping_cart',
      sortOrder: 30,
    ),
    const ThqNavigationNode(
      id: 'node-4',
      nodeKey: 'accounting',
      nodeType: 'module',
      moduleKey: 'accounting',
      label: 'Accounting & GST',
      iconKey: 'account_balance',
      sortOrder: 40,
    ),
    const ThqNavigationNode(
      id: 'node-5',
      nodeKey: 'aggregate_yard',
      nodeType: 'module',
      moduleKey: 'aggregate_yard',
      label: 'Material Yard',
      iconKey: 'landscape',
      sortOrder: 50,
    ),
  ];

  group('ThqWorkspaceCustomizationController', () {
    test('initializes with default preferences and computes initial order', () {
      final controller = ThqWorkspaceCustomizationController(
        appScope: 'client',
        allNodes: sampleNodes,
        initialPreferences: ThqUserUiPreferences.defaults('client'),
      );

      expect(controller.appScope, 'client');
      expect(controller.allNodes.length, 5);
      expect(controller.filteredNodes.length, 5);
      expect(controller.hasUnsavedChanges, isFalse);
      expect(controller.favoritesCount, 0);
      expect(controller.hiddenCount, 0);
      expect(controller.preferences.tableDensity, 'compact');
    });

    test('search filters nodes by label and nodeKey', () {
      final controller = ThqWorkspaceCustomizationController(
        appScope: 'client',
        allNodes: sampleNodes,
        initialPreferences: ThqUserUiPreferences.defaults('client'),
      );

      controller.setSearch('dash');
      expect(controller.filteredNodes.length, 1);
      expect(controller.filteredNodes.first.nodeKey, 'dashboard');

      controller.setSearch('sale');
      expect(controller.filteredNodes.length, 1);
      expect(controller.filteredNodes.first.nodeKey, 'sales');

      controller.setSearch('');
      expect(controller.filteredNodes.length, 5);
    });

    test('toggling favorite and visibility marks dirty and updates preferences', () {
      final controller = ThqWorkspaceCustomizationController(
        appScope: 'client_mobile',
        allNodes: sampleNodes,
        initialPreferences: ThqUserUiPreferences.defaults('client_mobile'),
      );

      expect(controller.hasUnsavedChanges, isFalse);

      controller.toggleFavorite('sales');
      expect(controller.preferences.isFavorite('sales'), isTrue);
      expect(controller.favoritesCount, 1);
      expect(controller.hasUnsavedChanges, isTrue);

      controller.toggleVisibility('accounting');
      expect(controller.preferences.isHidden('accounting'), isTrue);
      expect(controller.hiddenCount, 1);

      controller.toggleFavoritesFilter();
      expect(controller.showOnlyFavorites, isTrue);
      expect(controller.filteredNodes.length, 1);
      expect(controller.filteredNodes.first.nodeKey, 'sales');
    });

    test('applies role presets accurately', () {
      final controller = ThqWorkspaceCustomizationController(
        appScope: 'pos',
        allNodes: sampleNodes,
        initialPreferences: ThqUserUiPreferences.defaults('pos'),
      );

      controller.applyPreset(ThqWorkspacePreset.cashier);
      expect(controller.preferences.defaultLandingModule, 'pos');
      expect(controller.preferences.isFavorite('sales'), isTrue);
      expect(controller.preferences.isHidden('accounting'), isTrue);
      expect(controller.hasUnsavedChanges, isTrue);

      controller.applyPreset(ThqWorkspacePreset.yardOperator);
      expect(controller.preferences.defaultLandingModule, 'aggregate_yard');
      expect(controller.preferences.isFavorite('aggregate_yard'), isTrue);
    });

    test('reorders nodes and updates sort order map', () {
      final controller = ThqWorkspaceCustomizationController(
        appScope: 'client',
        allNodes: sampleNodes,
        initialPreferences: ThqUserUiPreferences.defaults('client'),
      );

      // Move last item ('aggregate_yard') to top
      controller.reorderNodes(4, 0);
      expect(controller.filteredNodes.first.nodeKey, 'aggregate_yard');
      expect(controller.hasUnsavedChanges, isTrue);
    });

    test('save calls onSave callback with updated preferences', () async {
      final controller = ThqWorkspaceCustomizationController(
        appScope: 'client',
        allNodes: sampleNodes,
        initialPreferences: ThqUserUiPreferences.defaults('client'),
      );

      controller.setTableDensity('dense');
      controller.toggleFavorite('dashboard');

      ThqUserUiPreferences? saved;
      final ok = await controller.save((prefs) async {
        saved = prefs;
      });

      expect(ok, isTrue);
      expect(saved, isNotNull);
      expect(saved!.tableDensity, 'dense');
      expect(saved!.isFavorite('dashboard'), isTrue);
    });
  });

  group('ThqWorkspaceCustomizationView widget tests', () {
    testWidgets('renders controls, list of nodes, and reacts to toggles', (tester) async {
      final controller = ThqWorkspaceCustomizationController(
        appScope: 'client',
        allNodes: sampleNodes,
        initialPreferences: ThqUserUiPreferences.defaults('client'),
      );

      ThqUserUiPreferences? savedPrefs;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThqTheme.light(),
          home: ThqWorkspaceCustomizationView(
            controller: controller,
            onSave: (p) async {
              savedPrefs = p;
            },
          ),
        ),
      );

      // Verify title & badges
      expect(find.text('Workspace & Module Customization'), findsOneWidget);
      expect(find.text('THQ Business (Desktop)'), findsOneWidget);
      expect(find.text('5 items shown'), findsOneWidget);

      // Verify node labels rendered
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Sales'), findsOneWidget);
      expect(find.widgetWithText(ReorderableListView, 'Purchases'), findsOneWidget);
      expect(find.text('Accounting & GST'), findsOneWidget);
      expect(find.text('Material Yard'), findsOneWidget);

      // Toggle favorite on Dashboard
      final starButtons = find.byTooltip('Pin to Favorites');
      expect(starButtons, findsWidgets);
      await tester.tap(starButtons.first);
      await tester.pump();

      expect(controller.preferences.isFavorite('dashboard'), isTrue);
      expect(find.text('•  1 pinned to favorites'), findsOneWidget);

      // Toggle visibility on second item
      final visibilityButtons = find.byTooltip('Hide from navigation');
      expect(visibilityButtons, findsWidgets);
      await tester.tap(visibilityButtons.at(1));
      await tester.pump();

      expect(controller.preferences.isHidden('sales'), isTrue);
      expect(find.text('•  1 hidden from menu'), findsOneWidget);

      // Tap Save Workspace
      await tester.tap(find.text('Save Workspace'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      ThqNotify.dismissAll();

      expect(savedPrefs, isNotNull);
      expect(savedPrefs!.isFavorite('dashboard'), isTrue);
      expect(savedPrefs!.isHidden('sales'), isTrue);
    });
  });
}
