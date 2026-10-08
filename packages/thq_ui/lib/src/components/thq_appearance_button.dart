import 'package:flutter/material.dart';

import '../theme/thq_appearance.dart';
import 'thq_notification_host.dart';

abstract final class ThqAppearanceActions {
  static Future<void> select(
    BuildContext context,
    ThqAppearance appearance,
  ) async {
    final controller = ThqAppearanceScope.maybeOf(context);
    if (controller == null) return;
    final saved = await controller.select(appearance);
    if (!saved &&
        controller.value == appearance &&
        controller.saveFailed &&
        context.mounted) {
      ThqNotify.showSnackBar(
        context,
        const SnackBar(
          content: Text(
            'UI changed. Could not save your choice on this device. Try again.',
          ),
        ),
      );
    }
  }

  static List<PopupMenuEntry<String>> menuItems(BuildContext context) {
    final selected = ThqAppearanceScope.modeOf(context);
    return [
      for (final mode in ThqAppearance.values)
        PopupMenuItem<String>(
          value: 'ui_${mode.name}',
          child: Row(
            children: [
              Icon(
                mode == selected ? Icons.check_rounded : Icons.palette_outlined,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text('${mode.label} UI'),
            ],
          ),
        ),
    ];
  }

  static ThqAppearance? fromAction(String value) => switch (value) {
    'ui_classic' => ThqAppearance.classic,
    'ui_v7' => ThqAppearance.v7,
    _ => null,
  };
}

/// Compact header control. Existing POS menus use the same two choices.
class ThqAppearanceButton extends StatelessWidget {
  const ThqAppearanceButton({super.key, this.foregroundColor});

  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final controller = ThqAppearanceScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'UI: ${controller.value.label} · Change appearance',
      icon: Icon(Icons.palette_outlined, size: 19, color: foregroundColor),
      onSelected: (value) {
        final mode = ThqAppearanceActions.fromAction(value);
        if (mode != null) ThqAppearanceActions.select(context, mode);
      },
      itemBuilder: ThqAppearanceActions.menuItems,
    );
  }
}
