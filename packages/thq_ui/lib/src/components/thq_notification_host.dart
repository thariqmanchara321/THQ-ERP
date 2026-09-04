import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import 'thq_notification_toast.dart';

@immutable
class _ThqNotification {
  const _ThqNotification({
    required this.id,
    required this.kind,
    required this.duration,
    this.title,
    this.message,
    this.content,
    this.actionLabel,
    this.onAction,
    this.dismissible = false,
  }) : assert(title != null || content != null);

  final int id;
  final ThqNotificationKind kind;
  final String? title;
  final String? message;
  final Widget? content;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final bool dismissible;

  bool get isImportant =>
      kind == ThqNotificationKind.warning || kind == ThqNotificationKind.error;

  bool sameAs(_ThqNotification other) =>
      kind == other.kind &&
      title == other.title &&
      message == other.message &&
      actionLabel == other.actionLabel &&
      content.runtimeType == other.content.runtimeType;
}

class _ThqMessageParts {
  const _ThqMessageParts(this.title, this.message);

  final String title;
  final String? message;
}

/// One notification entry point for THQ.
///
/// New code should call [success], [info], [warning] or [error].
/// Existing SnackBar call sites are migrated through [showSnackBar], which
/// preserves their message/action while rendering them with the THQ toast UI.
class ThqNotify {
  ThqNotify._();

  static final ValueNotifier<_ThqNotification?> _current =
      ValueNotifier<_ThqNotification?>(null);
  static final ListQueue<_ThqNotification> _importantQueue =
      ListQueue<_ThqNotification>();

  static Timer? _timer;
  static int _nextId = 1;

  static void success(
    BuildContext context,
    String title, {
    String? message,
    Duration? duration,
  }) {
    _show(
      context,
      kind: ThqNotificationKind.success,
      title: title,
      message: message,
      duration: duration ?? const Duration(milliseconds: 2800),
    );
  }

  static void info(
    BuildContext context,
    String title, {
    String? message,
    Duration? duration,
  }) {
    _show(
      context,
      kind: ThqNotificationKind.info,
      title: title,
      message: message,
      duration: duration ?? const Duration(milliseconds: 3200),
    );
  }

  static void warning(
    BuildContext context,
    String title, {
    String? message,
    Duration? duration,
  }) {
    _show(
      context,
      kind: ThqNotificationKind.warning,
      title: title,
      message: message,
      duration: duration ?? const Duration(milliseconds: 5000),
      dismissible: true,
    );
  }

  static void error(
    BuildContext context,
    String title, {
    String? message,
    Duration? duration,
  }) {
    _show(
      context,
      kind: ThqNotificationKind.error,
      title: title,
      message: message,
      duration: duration ?? const Duration(milliseconds: 6500),
      dismissible: true,
    );
  }

  /// Compatibility bridge used while removing every legacy ScaffoldMessenger
  /// SnackBar call from THQ apps.
  ///
  /// The SnackBar is never shown by ScaffoldMessenger. Its content/action are
  /// adapted into the THQ compact notification host.
  static void showSnackBar(BuildContext context, SnackBar snackBar) {
    if (!context.mounted) return;

    final rawText = _textFromWidget(snackBar.content);
    final kind = _inferKind(context, snackBar, rawText);
    final sourceAction = snackBar.action;
    final actionLabel = sourceAction?.label;

    VoidCallback? onAction;
    if (sourceAction != null) {
      onAction = () {
        dismiss();
        sourceAction.onPressed();
      };
    }

    if (rawText != null && rawText.trim().isNotEmpty) {
      final parts = _messageParts(rawText.trim(), kind);
      _show(
        context,
        kind: kind,
        title: parts.title,
        message: parts.message,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: _durationFor(kind, hasAction: sourceAction != null),
        dismissible:
            kind == ThqNotificationKind.warning ||
            kind == ThqNotificationKind.error ||
            snackBar.showCloseIcon == true ||
            sourceAction != null,
      );
      return;
    }

    _show(
      context,
      kind: kind,
      title: _defaultTitle(kind),
      content: snackBar.content,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: _durationFor(kind, hasAction: sourceAction != null),
      dismissible:
          kind == ThqNotificationKind.warning ||
          kind == ThqNotificationKind.error ||
          snackBar.showCloseIcon == true ||
          sourceAction != null,
    );
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;

    if (_importantQueue.isNotEmpty) {
      _activate(_importantQueue.removeFirst());
      return;
    }

    _current.value = null;
  }

  static void dismissAll() {
    _timer?.cancel();
    _timer = null;
    _importantQueue.clear();
    _current.value = null;
  }

  static String? _textFromWidget(Widget widget) {
    if (widget is Text) {
      final data = widget.data;
      if (data != null) return data;
      final span = widget.textSpan;
      if (span != null) return span.toPlainText();
    }
    return null;
  }

  static ThqNotificationKind _inferKind(
    BuildContext context,
    SnackBar snackBar,
    String? text,
  ) {
    final background = snackBar.backgroundColor;
    final scheme = Theme.of(context).colorScheme;

    if (background != null && background == scheme.error) {
      return ThqNotificationKind.error;
    }

    final value = (text ?? '').trim().toLowerCase();

    const errorWords = <String>[
      'error',
      'failed',
      'failure',
      'exception',
      'could not',
      'unable to',
      'denied',
      'fatal',
    ];
    if (errorWords.any(value.contains)) {
      return ThqNotificationKind.error;
    }

    const warningWords = <String>[
      'required',
      'select ',
      'choose ',
      'missing',
      'not available',
      'unavailable',
      'not activated',
      'already ',
      'insufficient',
      'conflict',
      'outstanding',
      'cannot ',
      "can't ",
      'must ',
      'warning',
      'offline stock',
    ];
    if (value.startsWith('no ') || warningWords.any(value.contains)) {
      return ThqNotificationKind.warning;
    }

    const successWords = <String>[
      'success',
      'saved',
      'created',
      'updated',
      'completed',
      'recorded',
      'posted',
      'approved',
      'paid',
      'received',
      'restored',
      'activated',
      'reconciled',
      'synced',
      'added',
    ];
    if (successWords.any(value.contains)) {
      return ThqNotificationKind.success;
    }

    return ThqNotificationKind.info;
  }

  static Duration _durationFor(
    ThqNotificationKind kind, {
    required bool hasAction,
  }) {
    final base = switch (kind) {
      ThqNotificationKind.success => const Duration(milliseconds: 2800),
      ThqNotificationKind.info => const Duration(milliseconds: 3200),
      ThqNotificationKind.warning => const Duration(milliseconds: 5000),
      ThqNotificationKind.error => const Duration(milliseconds: 6500),
    };
    if (!hasAction) return base;

    return base < const Duration(seconds: 6)
        ? const Duration(seconds: 6)
        : base;
  }

  static _ThqMessageParts _messageParts(String text, ThqNotificationKind kind) {
    if (text.length <= 72) {
      return _ThqMessageParts(text, null);
    }

    final firstSentence = text.indexOf('. ');
    if (firstSentence >= 18 && firstSentence <= 78) {
      return _ThqMessageParts(
        text.substring(0, firstSentence + 1),
        text.substring(firstSentence + 2).trim(),
      );
    }

    return _ThqMessageParts(_defaultTitle(kind), text);
  }

  static String _defaultTitle(ThqNotificationKind kind) => switch (kind) {
    ThqNotificationKind.success => 'Completed',
    ThqNotificationKind.warning => 'Attention required',
    ThqNotificationKind.error => 'Action failed',
    ThqNotificationKind.info => 'Notice',
  };

  static void _show(
    BuildContext context, {
    required ThqNotificationKind kind,
    required Duration duration,
    String? title,
    String? message,
    Widget? content,
    String? actionLabel,
    VoidCallback? onAction,
    bool dismissible = false,
  }) {
    if (!context.mounted) return;

    final cleanTitle = title?.trim();
    final cleanMessage = message?.trim();
    if ((cleanTitle == null || cleanTitle.isEmpty) && content == null) return;

    final incoming = _ThqNotification(
      id: _nextId++,
      kind: kind,
      title: cleanTitle == null || cleanTitle.isEmpty ? null : cleanTitle,
      message: cleanMessage == null || cleanMessage.isEmpty
          ? null
          : cleanMessage,
      content: content,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
      dismissible: dismissible,
    );

    final active = _current.value;
    if (active != null && active.sameAs(incoming)) {
      _activate(incoming);
      return;
    }

    if (active == null) {
      _activate(incoming);
      return;
    }

    if (!incoming.isImportant && active.isImportant) {
      return;
    }

    if (incoming.isImportant && active.isImportant) {
      final duplicateQueued = _importantQueue.any(
        (item) => item.sameAs(incoming),
      );
      if (!duplicateQueued) {
        if (_importantQueue.length >= 2) {
          _importantQueue.removeFirst();
        }
        _importantQueue.addLast(incoming);
      }
      return;
    }

    _activate(incoming);
  }

  static void _activate(_ThqNotification notification) {
    _timer?.cancel();
    _current.value = notification;
    _timer = Timer(notification.duration, dismiss);
  }
}

/// Install once in MaterialApp.builder.
///
/// Desktop notifications sit below the application header at the top-right.
/// Compact/mobile layouts use safe horizontal margins.
class ThqNotificationHost extends StatelessWidget {
  const ThqNotificationHost({
    required this.child,
    this.desktopTopOffset = 78,
    this.desktopRight = 28,
    this.compactTopOffset = 70,
    this.compactHorizontal = 16,
    super.key,
  });

  final Widget child;
  final double desktopTopOffset;
  final double desktopRight;
  final double compactTopOffset;
  final double compactHorizontal;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.width < 720;
    final top =
        media.padding.top + (compact ? compactTopOffset : desktopTopOffset);

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          top: top,
          right: compact ? compactHorizontal : desktopRight,
          left: compact ? compactHorizontal : null,
          child: ValueListenableBuilder<_ThqNotification?>(
            valueListenable: ThqNotify._current,
            builder: (context, notification, _) {
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 170),
                reverseDuration: const Duration(milliseconds: 130),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final slide = Tween<Offset>(
                    begin: const Offset(0, -0.16),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: slide, child: child),
                  );
                },
                child: notification == null
                    ? const SizedBox.shrink(key: ValueKey('thq-toast-empty'))
                    : ThqNotificationToast(
                        key: ValueKey(notification.id),
                        kind: notification.kind,
                        title: notification.title,
                        message: notification.message,
                        content: notification.content,
                        actionLabel: notification.actionLabel,
                        onAction: notification.onAction,
                        onDismiss:
                            notification.dismissible || notification.isImportant
                            ? ThqNotify.dismiss
                            : null,
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}
