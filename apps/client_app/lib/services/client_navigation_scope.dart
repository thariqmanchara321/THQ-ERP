import 'package:flutter/widgets.dart';

/// Provides unified in-shell navigation across THQ Client App modules.
///
/// Any child screen can call [ClientNavigationScope.navigate] to switch to
/// another module (e.g., 'smart_inventory', 'operations_intelligence', 'inventory')
/// and optionally specify an internal tab index or arguments, without pushing
/// a separate full-screen route that hides the global sidebar and header.
class ClientNavigationScope extends InheritedWidget {
  final void Function(String moduleKey, {int? tabIndex, dynamic args})
      navigateTo;
  final String? currentModuleKey;

  const ClientNavigationScope({
    super.key,
    required this.navigateTo,
    this.currentModuleKey,
    required super.child,
  });

  static ClientNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ClientNavigationScope>();

  static ClientNavigationScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'No ClientNavigationScope found in context');
    return scope!;
  }

  /// Attempts to navigate inside the unified application shell.
  ///
  /// Returns `true` if handled by [ClientNavigationScope], or `false` if no
  /// scope exists (e.g., in standalone widget tests), allowing caller fallback.
  static bool navigate(
    BuildContext context,
    String moduleKey, {
    int? tabIndex,
    dynamic args,
  }) {
    final scope = maybeOf(context);
    if (scope != null) {
      scope.navigateTo(moduleKey, tabIndex: tabIndex, args: args);
      return true;
    }
    return false;
  }

  @override
  bool updateShouldNotify(ClientNavigationScope oldWidget) =>
      oldWidget.currentModuleKey != currentModuleKey;
}
