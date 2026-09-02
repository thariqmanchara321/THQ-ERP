import 'package:flutter/material.dart';

import '../foundations/thq_tokens.dart';

/// Compact desktop top bar. Application-specific selectors and actions are slots.
class ThqTopBar extends StatelessWidget implements PreferredSizeWidget {
  const ThqTopBar({
    required this.title,
    this.subtitle,
    this.leading,
    this.scope,
    this.actions = const <Widget>[],
    this.height = 56,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? scope;
  final List<Widget> actions;
  final double height;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: ThqTokens.space12),
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: ThqTokens.space8),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        if (subtitle != null && subtitle!.trim().isNotEmpty)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  if (scope != null) ...[
                    const SizedBox(width: ThqTokens.space12),
                    Flexible(child: scope!),
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(width: ThqTokens.space8),
                    ...actions,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
