import 'package:flutter/material.dart';

import '../foundations/thq_breakpoints.dart';
import '../foundations/thq_tokens.dart';

class ThqNavDestination {
  const ThqNavDestination({
    required this.keyName,
    required this.label,
    required this.icon,
    this.badge,
  });

  final String keyName;
  final String label;
  final IconData icon;
  final String? badge;
}

/// Standard THQ desktop shell with a fixed collapsible sidebar.
///
/// It is deliberately presentation-only: authentication, permissions,
/// navigation state and business logic remain owned by each application.
class ThqDesktopShell extends StatelessWidget {
  const ThqDesktopShell({
    required this.destinations,
    required this.selectedKey,
    required this.onDestinationSelected,
    required this.body,
    this.brand,
    this.topBar,
    this.sidebarFooter,
    this.collapsed = false,
    this.onCollapsedChanged,
    this.sidebarWidth = 224,
    this.collapsedWidth = 64,
    this.mobileDrawerHeader,
    super.key,
  });

  final List<ThqNavDestination> destinations;
  final String selectedKey;
  final ValueChanged<String> onDestinationSelected;
  final Widget body;
  final Widget? brand;
  final Widget? topBar;
  final Widget? sidebarFooter;
  final bool collapsed;
  final ValueChanged<bool>? onCollapsedChanged;
  final double sidebarWidth;
  final double collapsedWidth;
  final Widget? mobileDrawerHeader;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < ThqBreakpoints.compact) {
          return _MobileShell(
            destinations: destinations,
            selectedKey: selectedKey,
            onDestinationSelected: onDestinationSelected,
            body: body,
            brand: mobileDrawerHeader ?? brand,
            topBar: topBar,
            footer: sidebarFooter,
          );
        }

        return Scaffold(
          body: Row(
            children: [
              AnimatedContainer(
                duration: ThqTokens.motionStandard,
                curve: Curves.easeOut,
                width: collapsed ? collapsedWidth : sidebarWidth,
                child: _Sidebar(
                  destinations: destinations,
                  selectedKey: selectedKey,
                  onDestinationSelected: onDestinationSelected,
                  brand: brand,
                  footer: sidebarFooter,
                  collapsed: collapsed,
                  onCollapsedChanged: onCollapsedChanged,
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    if (topBar != null) topBar!,
                    Expanded(child: body),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.destinations,
    required this.selectedKey,
    required this.onDestinationSelected,
    required this.brand,
    required this.footer,
    required this.collapsed,
    required this.onCollapsedChanged,
  });

  final List<ThqNavDestination> destinations;
  final String selectedKey;
  final ValueChanged<String> onDestinationSelected;
  final Widget? brand;
  final Widget? footer;
  final bool collapsed;
  final ValueChanged<bool>? onCollapsedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (brand != null)
              Padding(
                padding: const EdgeInsets.all(ThqTokens.space10),
                child: brand!,
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: ThqTokens.space8,
                  vertical: ThqTokens.space4,
                ),
                itemCount: destinations.length,
                itemBuilder: (context, index) {
                  final item = destinations[index];
                  final selected = item.keyName == selectedKey;
                  return _DestinationTile(
                    destination: item,
                    selected: selected,
                    collapsed: collapsed,
                    onTap: () => onDestinationSelected(item.keyName),
                  );
                },
              ),
            ),
            if (footer != null) footer!,
            if (onCollapsedChanged != null) ...[
              const Divider(height: 1),
              _SidebarAction(
                collapsed: collapsed,
                icon: collapsed
                    ? Icons.keyboard_double_arrow_right
                    : Icons.keyboard_double_arrow_left,
                label: collapsed ? 'Expand' : 'Collapse',
                onTap: () => onCollapsedChanged!(!collapsed),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.destination,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final ThqNavDestination destination;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onSecondaryContainer : null;
    final tile = Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(ThqTokens.radiusSmall),
      child: InkWell(
        borderRadius: BorderRadius.circular(ThqTokens.radiusSmall),
        onTap: onTap,
        child: SizedBox(
          height: ThqTokens.controlStandard,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : ThqTokens.space10,
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  destination.icon,
                  size: ThqTokens.iconMedium,
                  color: foreground,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: ThqTokens.space10),
                  Expanded(
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: foreground),
                    ),
                  ),
                  if (destination.badge != null)
                    _NavBadge(label: destination.badge!),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (!collapsed) return Padding(
      padding: const EdgeInsets.only(bottom: ThqTokens.space2),
      child: tile,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: ThqTokens.space2),
      child: Tooltip(message: destination.label, child: tile),
    );
  }
}

class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(
        horizontal: ThqTokens.space4,
        vertical: ThqTokens.space2,
      ),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(ThqTokens.radiusPill),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _SidebarAction extends StatelessWidget {
  const _SidebarAction({
    required this.collapsed,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool collapsed;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final child = ListTile(
      dense: true,
      minTileHeight: ThqTokens.controlStandard,
      leading: Icon(icon, size: ThqTokens.iconMedium),
      title: collapsed ? null : Text(label),
      onTap: onTap,
    );
    return collapsed ? Tooltip(message: label, child: child) : child;
  }
}

class _MobileShell extends StatelessWidget {
  const _MobileShell({
    required this.destinations,
    required this.selectedKey,
    required this.onDestinationSelected,
    required this.body,
    required this.brand,
    required this.topBar,
    required this.footer,
  });

  final List<ThqNavDestination> destinations;
  final String selectedKey;
  final ValueChanged<String> onDestinationSelected;
  final Widget body;
  final Widget? brand;
  final Widget? topBar;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: topBar == null ? null : PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: topBar!,
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              if (brand != null)
                Padding(
                  padding: const EdgeInsets.all(ThqTokens.space12),
                  child: brand!,
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(ThqTokens.space8),
                  itemCount: destinations.length,
                  itemBuilder: (context, index) {
                    final item = destinations[index];
                    return _DestinationTile(
                      destination: item,
                      selected: item.keyName == selectedKey,
                      collapsed: false,
                      onTap: () {
                        Navigator.of(context).pop();
                        onDestinationSelected(item.keyName);
                      },
                    );
                  },
                ),
              ),
              if (footer != null) footer!,
            ],
          ),
        ),
      ),
      body: body,
    );
  }
}
