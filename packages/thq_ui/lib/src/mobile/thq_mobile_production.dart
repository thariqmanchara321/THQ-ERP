import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared production wrapper for THQ mobile applications.
///
/// Keeps accessibility text scaling usable up to 200%, aligns the Android
/// navigation bar with the active theme and provides predictable focus order.
class ThqMobileProductionFrame extends StatelessWidget {
  final Widget child;
  final double maxTextScale;

  const ThqMobileProductionFrame({
    super.key,
    required this.child,
    this.maxTextScale = 2.0,
  }) : assert(maxTextScale > 0);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final requestedScale = media.textScaler.scale(1.0);
    final safeScale = requestedScale.isFinite && requestedScale > maxTextScale
        ? maxTextScale
        : requestedScale.isFinite && requestedScale > 0
        ? requestedScale
        : 1.0;
    final scheme = Theme.of(context).colorScheme;
    final navigationBrightness =
        ThemeData.estimateBrightnessForColor(scheme.surface) == Brightness.dark
        ? Brightness.light
        : Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: scheme.surface,
        systemNavigationBarDividerColor: scheme.outlineVariant,
        systemNavigationBarIconBrightness: navigationBrightness,
      ),
      child: MediaQuery(
        data: media.copyWith(textScaler: TextScaler.linear(safeScale)),
        child: FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: child,
        ),
      ),
    );
  }
}

/// Compact, non-blocking release notice used when a newer optional build is
/// available. Mandatory updates remain handled by each app's entry screen.
class ThqMobileReleaseBanner extends StatelessWidget {
  final String currentVersion;
  final String latestVersion;
  final String notes;

  const ThqMobileReleaseBanner({
    super.key,
    required this.currentVersion,
    required this.latestVersion,
    this.notes = '',
  });

  @override
  Widget build(BuildContext context) {
    final current = currentVersion.trim().replaceFirst(RegExp(r'^v'), '');
    final latest = latestVersion.trim().replaceFirst(RegExp(r'^v'), '');
    if (latest.isEmpty || latest == current) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label: 'THQ update available. Version $latest.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.14)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.system_update_alt_rounded,
              size: 19,
              color: scheme.primary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Update available: v$latest',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      notes.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.78,
                        ),
                        fontSize: 10.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
