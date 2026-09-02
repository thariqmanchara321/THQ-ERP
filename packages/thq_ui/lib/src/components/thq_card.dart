import 'package:flutter/material.dart';

import '../foundations/thq_tokens.dart';

class ThqCard extends StatelessWidget {
  const ThqCard({
    required this.child,
    this.padding = const EdgeInsets.all(ThqTokens.space16),
    this.margin = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin,
      child: Padding(padding: padding, child: child),
    );
  }
}

class ThqSummaryCard extends StatelessWidget {
  const ThqSummaryCard({
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    super.key,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ThqCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: ThqTokens.iconLarge),
            const SizedBox(width: ThqTokens.space12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: theme.textTheme.labelMedium),
                const SizedBox(height: ThqTokens.space4),
                Text(value, style: theme.textTheme.titleLarge),
                if (caption != null) ...[
                  const SizedBox(height: ThqTokens.space4),
                  Text(caption!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
