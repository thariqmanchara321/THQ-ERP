import 'package:flutter/material.dart';

import '../foundations/thq_tokens.dart';

class ThqPrimaryButton extends StatelessWidget {
  const ThqPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.busyLabel,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final String? busyLabel;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: _ThqButtonContent(
        label: busy ? (busyLabel ?? label) : label,
        icon: icon,
        busy: busy,
      ),
    );
  }
}

class ThqSecondaryButton extends StatelessWidget {
  const ThqSecondaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: busy ? null : onPressed,
      child: _ThqButtonContent(label: label, icon: icon, busy: busy),
    );
  }
}

class ThqDangerButton extends StatelessWidget {
  const ThqDangerButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.error,
        foregroundColor: scheme.onError,
      ),
      onPressed: busy ? null : onPressed,
      child: _ThqButtonContent(label: label, icon: icon, busy: busy),
    );
  }
}

class ThqIconButton extends StatelessWidget {
  const ThqIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox.square(
              dimension: ThqTokens.iconMedium,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: ThqTokens.iconMedium),
    );
  }
}

class _ThqButtonContent extends StatelessWidget {
  const _ThqButtonContent({
    required this.label,
    required this.icon,
    required this.busy,
  });

  final String label;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final leading = busy
        ? const SizedBox.square(
            dimension: ThqTokens.iconSmall,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : icon == null
            ? null
            : Icon(icon, size: ThqTokens.iconSmall);
    if (leading == null) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        leading,
        const SizedBox(width: ThqTokens.space8),
        Text(label),
      ],
    );
  }
}
