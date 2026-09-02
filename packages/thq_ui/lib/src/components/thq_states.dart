import 'package:flutter/material.dart';

import '../foundations/thq_tokens.dart';
import 'thq_buttons.dart';

class ThqLoadingState extends StatelessWidget {
  const ThqLoadingState({this.label = 'Loading…', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return _ThqCenteredState(
      icon: const SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      title: label,
    );
  }
}

class ThqEmptyState extends StatelessWidget {
  const ThqEmptyState({
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    super.key,
  });

  final String title;
  final String? message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _ThqCenteredState(icon: Icon(icon), title: title, message: message);
  }
}

class ThqErrorState extends StatelessWidget {
  const ThqErrorState({
    required this.title,
    this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
    super.key,
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return _ThqCenteredState(
      icon: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
      title: title,
      message: message,
      action: onRetry == null
          ? null
          : ThqSecondaryButton(label: retryLabel, onPressed: onRetry),
    );
  }
}

class _ThqCenteredState extends StatelessWidget {
  const _ThqCenteredState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final Widget icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(ThqTokens.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(height: ThqTokens.space12),
              Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
              if (message != null && message!.trim().isNotEmpty) ...[
                const SizedBox(height: ThqTokens.space8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: ThqTokens.space16),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
