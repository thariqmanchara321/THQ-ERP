import 'package:flutter/material.dart';

import '../foundations/thq_breakpoints.dart';
import '../foundations/thq_tokens.dart';

class ThqFormSection extends StatelessWidget {
  const ThqFormSection({
    required this.title,
    required this.child,
    this.description,
    this.trailing,
    this.padding = const EdgeInsets.all(ThqTokens.space12),
    super.key,
  });

  final String title;
  final String? description;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      if (description != null && description!.trim().isNotEmpty) ...[
                        const SizedBox(height: ThqTokens.space2),
                        Text(description!, style: theme.textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: ThqTokens.space12),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: ThqTokens.space12),
            child,
          ],
        ),
      ),
    );
  }
}

class ThqFormGrid extends StatelessWidget {
  const ThqFormGrid({
    required this.children,
    this.desktopColumns = 3,
    this.compactColumns = 2,
    this.minFieldWidth = 220,
    this.spacing = ThqTokens.space12,
    this.runSpacing = ThqTokens.space12,
    super.key,
  });

  final List<Widget> children;
  final int desktopColumns;
  final int compactColumns;
  final double minFieldWidth;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = ThqBreakpoints.classify(constraints.maxWidth);
        var columns = switch (layout) {
          ThqLayoutClass.mobile => 1,
          ThqLayoutClass.compact => compactColumns,
          ThqLayoutClass.desktop || ThqLayoutClass.wide => desktopColumns,
        };
        columns = columns.clamp(1, children.isEmpty ? 1 : children.length).toInt();
        while (columns > 1) {
          final candidate =
              (constraints.maxWidth - ((columns - 1) * spacing)) / columns;
          if (candidate >= minFieldWidth) break;
          columns--;
        }
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - ((columns - 1) * spacing)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class ThqStickyActionBar extends StatelessWidget {
  const ThqStickyActionBar({
    required this.primaryActions,
    this.secondaryActions = const <Widget>[],
    this.message,
    this.padding = const EdgeInsets.symmetric(
      horizontal: ThqTokens.space16,
      vertical: ThqTokens.space10,
    ),
    super.key,
  });

  final List<Widget> primaryActions;
  final List<Widget> secondaryActions;
  final Widget? message;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < ThqBreakpoints.compact;
              final actions = Wrap(
                alignment: WrapAlignment.end,
                spacing: ThqTokens.space8,
                runSpacing: ThqTokens.space8,
                children: [...secondaryActions, ...primaryActions],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (message != null) ...[
                      message!,
                      const SizedBox(height: ThqTokens.space8),
                    ],
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                );
              }
              return Row(
                children: [
                  if (message != null) Expanded(child: message!) else const Spacer(),
                  const SizedBox(width: ThqTokens.space12),
                  actions,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
