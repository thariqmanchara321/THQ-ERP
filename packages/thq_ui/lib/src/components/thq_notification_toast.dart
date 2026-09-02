import 'package:flutter/material.dart';

import '../foundations/thq_tokens.dart';
import '../status/thq_status.dart';
import '../theme/thq_semantic_colors.dart';

enum ThqNotificationKind { success, warning, error, info }

class ThqNotificationToast extends StatelessWidget {
  const ThqNotificationToast({
    required this.kind,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    super.key,
  });

  final ThqNotificationKind kind;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  ThqStatusTone get _tone => switch (kind) {
        ThqNotificationKind.success => ThqStatusTone.success,
        ThqNotificationKind.warning => ThqStatusTone.warning,
        ThqNotificationKind.error => ThqStatusTone.critical,
        ThqNotificationKind.info => ThqStatusTone.info,
      };

  IconData get _icon => switch (kind) {
        ThqNotificationKind.success => Icons.check_circle_outline,
        ThqNotificationKind.warning => Icons.warning_amber_rounded,
        ThqNotificationKind.error => Icons.error_outline,
        ThqNotificationKind.info => Icons.info_outline,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.thqSemanticColors;
    final foreground = _tone.foreground(semantic);
    final background = _tone.background(semantic);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Material(
        color: background,
        elevation: 6,
        borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(ThqTokens.space12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon, color: foreground, size: ThqTokens.iconMedium),
              const SizedBox(width: ThqTokens.space10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: foreground,
                      ),
                    ),
                    if (message != null && message!.trim().isNotEmpty) ...[
                      const SizedBox(height: ThqTokens.space4),
                      Text(message!, style: theme.textTheme.bodySmall),
                    ],
                    if (actionLabel != null && onAction != null) ...[
                      const SizedBox(height: ThqTokens.space4),
                      TextButton(onPressed: onAction, child: Text(actionLabel!)),
                    ],
                  ],
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close, size: ThqTokens.iconSmall),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
