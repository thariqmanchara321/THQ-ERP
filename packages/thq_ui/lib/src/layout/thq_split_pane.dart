import 'package:flutter/material.dart';

import '../foundations/thq_breakpoints.dart';
import '../foundations/thq_tokens.dart';

/// Master-detail workspace that avoids whole-page scrolling on desktop.
class ThqSplitPane extends StatelessWidget {
  const ThqSplitPane({
    required this.primary,
    required this.secondary,
    this.primaryFlex = 5,
    this.secondaryFlex = 7,
    this.gap = ThqTokens.space12,
    this.collapseBelow = ThqBreakpoints.desktop,
    this.compactBuilder,
    super.key,
  });

  final Widget primary;
  final Widget secondary;
  final int primaryFlex;
  final int secondaryFlex;
  final double gap;
  final double collapseBelow;
  final Widget Function(BuildContext context, Widget primary, Widget secondary)?
      compactBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < collapseBelow) {
          final builder = compactBuilder;
          if (builder != null) return builder(context, primary, secondary);
          return Column(
            children: [
              Expanded(child: primary),
              SizedBox(height: gap),
              Expanded(child: secondary),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: primaryFlex, child: primary),
            SizedBox(width: gap),
            Expanded(flex: secondaryFlex, child: secondary),
          ],
        );
      },
    );
  }
}

/// Bordered pane intended for internally scrollable sections.
class ThqWorkspacePane extends StatelessWidget {
  const ThqWorkspacePane({
    required this.child,
    this.header,
    this.footer,
    this.padding = const EdgeInsets.all(ThqTokens.space12),
    this.clipBehavior = Clip.antiAlias,
    super.key,
  });

  final Widget? header;
  final Widget child;
  final Widget? footer;
  final EdgeInsets padding;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
        clipBehavior: clipBehavior,
        child: Column(
          children: [
            if (header != null) header!,
            Expanded(child: Padding(padding: padding, child: child)),
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }
}
