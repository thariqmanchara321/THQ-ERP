import 'package:flutter/material.dart';

import '../status/thq_status.dart';
import '../theme/thq_semantic_colors.dart';

enum ThqNotificationKind { success, warning, error, info }

class ThqNotificationToast extends StatelessWidget {
  const ThqNotificationToast({
    required this.kind,
    this.title,
    this.message,
    this.content,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    super.key,
  }) : assert(title != null || content != null);

  final ThqNotificationKind kind;
  final String? title;
  final String? message;
  final Widget? content;
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
    ThqNotificationKind.success => Icons.check_circle_rounded,
    ThqNotificationKind.warning => Icons.warning_amber_rounded,
    ThqNotificationKind.error => Icons.error_outline_rounded,
    ThqNotificationKind.info => Icons.info_outline_rounded,
  };

  bool get _important =>
      kind == ThqNotificationKind.warning || kind == ThqNotificationKind.error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.thqSemanticColors;
    final accent = _tone.foreground(semantic);
    final hasMessage = message != null && message!.trim().isNotEmpty;
    final hasAction = actionLabel != null && onAction != null;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: MediaQuery.sizeOf(context).width < 720 ? 0 : 280,
        maxWidth: 340,
        minHeight: 46,
      ),
      child: Material(
        color: scheme.surface,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              hasMessage || content != null ? 9 : 8,
              onDismiss == null ? 12 : 6,
              hasMessage || content != null ? 9 : 8,
            ),
            child: Row(
              crossAxisAlignment: hasMessage || content != null
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    top: hasMessage || content != null ? 1 : 0,
                  ),
                  child: Icon(_icon, color: accent, size: 18),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null && title!.trim().isNotEmpty)
                        Text(
                          title!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        ),
                      if (hasMessage) ...[
                        const SizedBox(height: 3),
                        Text(
                          message!,
                          maxLines: _important ? 4 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.25,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (content != null) ...[
                        if (title != null && title!.trim().isNotEmpty)
                          const SizedBox(height: 3),
                        DefaultTextStyle.merge(
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.25,
                            color: scheme.onSurface,
                          ),
                          child: content!,
                        ),
                      ],
                      if (hasAction) ...[
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: onAction,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: const Size(0, 30),
                          ),
                          child: Text(actionLabel!),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onDismiss != null)
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: onDismiss,
                      icon: const Icon(Icons.close_rounded, size: 16),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
