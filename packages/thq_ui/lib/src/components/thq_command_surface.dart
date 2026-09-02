import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../foundations/thq_tokens.dart';

/// Dense responsive wrapping layout used by dashboards and command centres.
class ThqResponsiveWrap extends StatelessWidget {
  const ThqResponsiveWrap({
    required this.children,
    this.minItemWidth = 220,
    this.maxColumns = 4,
    this.spacing = ThqTokens.space12,
    this.runSpacing = ThqTokens.space12,
    super.key,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (children.isEmpty) return const SizedBox.shrink();
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : minItemWidth;
        final possible = math.max(
          1,
          ((available + spacing) / (minItemWidth + spacing)).floor(),
        ).toInt();
        final columns = math.min(maxColumns, possible).toInt();
        final width = math.max(
          0.0,
          (available - ((columns - 1) * spacing)) / columns,
        ).toDouble();

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

class ThqMetricCard extends StatelessWidget {
  const ThqMetricCard({
    required this.label,
    required this.value,
    this.icon,
    this.caption,
    super.key,
  });

  final String label;
  final String value;
  final IconData? icon;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ThqTokens.space12),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: ThqTokens.controlStandard,
                height: ThqTokens.controlStandard,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(ThqTokens.radiusSmall),
                ),
                child: Icon(
                  icon,
                  size: ThqTokens.iconMedium,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: ThqTokens.space10),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: ThqTokens.space2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge,
                  ),
                  if (caption != null && caption!.trim().isNotEmpty)
                    Text(
                      caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ThqCommandCard extends StatelessWidget {
  const ThqCommandCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
      child: InkWell(
        borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 106),
          padding: const EdgeInsets.all(ThqTokens.space12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: ThqTokens.controlTouch,
                height: ThqTokens.controlTouch,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
                ),
                child: Icon(
                  icon,
                  size: ThqTokens.iconLarge,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: ThqTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: ThqTokens.space4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ThqTokens.space8),
              trailing ??
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: ThqTokens.iconSmall,
                    color: scheme.onSurfaceVariant,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class ThqSectionHeader extends StatelessWidget {
  const ThqSectionHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: ThqTokens.space2),
                Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: ThqTokens.space12),
          trailing!,
        ],
      ],
    );
  }
}
