import 'package:flutter/material.dart';

import '../foundations/thq_tokens.dart';
import '../status/thq_status.dart';
import '../theme/thq_semantic_colors.dart';

class ThqStatusBadge extends StatelessWidget {
  const ThqStatusBadge({
    required this.status,
    this.label,
    this.compact = true,
    super.key,
  });

  final ThqStatus status;
  final String? label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.thqSemanticColors;
    final foreground = status.tone.foreground(colors);
    final background = status.tone.background(colors);
    return Semantics(
      label: label ?? status.label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(ThqTokens.radiusPill),
          border: Border.all(color: foreground.withAlpha(110)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? ThqTokens.space8 : ThqTokens.space12,
            vertical: compact ? ThqTokens.space4 : ThqTokens.space8,
          ),
          child: Text(
            label ?? status.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ),
    );
  }
}
