import 'package:flutter/material.dart';

import '../foundations/thq_breakpoints.dart';
import '../foundations/thq_tokens.dart';

/// Compact page frame for THQ desktop workspaces.
///
/// The header and action bar remain fixed while [child] owns its scrolling.
class ThqPageFrame extends StatelessWidget {
  const ThqPageFrame({
    required this.title,
    required this.child,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
    this.toolbar,
    this.footer,
    this.padding,
    this.compactHeader = true,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? toolbar;
  final Widget child;
  final Widget? footer;
  final EdgeInsets? padding;
  final bool compactHeader;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = ThqBreakpoints.classify(constraints.maxWidth);
        final mobile = layout == ThqLayoutClass.mobile;
        final effectivePadding = padding ??
            EdgeInsets.symmetric(
              horizontal: mobile ? ThqTokens.space12 : ThqTokens.space16,
              vertical: mobile ? ThqTokens.space10 : ThqTokens.space12,
            );

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                effectivePadding.left,
                effectivePadding.top,
                effectivePadding.right,
                compactHeader ? ThqTokens.space8 : ThqTokens.space12,
              ),
              child: _PageHeader(
                title: title,
                subtitle: subtitle,
                leading: leading,
                actions: actions,
                mobile: mobile,
              ),
            ),
            if (toolbar != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  effectivePadding.left,
                  0,
                  effectivePadding.right,
                  ThqTokens.space8,
                ),
                child: toolbar!,
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  effectivePadding.left,
                  0,
                  effectivePadding.right,
                  footer == null ? effectivePadding.bottom : 0,
                ),
                child: child,
              ),
            ),
            if (footer != null) footer!,
          ],
        );
      },
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.actions,
    required this.mobile,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Row(
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: ThqTokens.space10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: ThqTokens.space2),
                Text(
                  subtitle!,
                  maxLines: mobile ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ],
    );

    if (actions.isEmpty) return titleBlock;
    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleBlock,
          const SizedBox(height: ThqTokens.space8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: ThqTokens.space8,
            runSpacing: ThqTokens.space8,
            children: actions,
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: titleBlock),
        const SizedBox(width: ThqTokens.space12),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: ThqTokens.space8,
          runSpacing: ThqTokens.space8,
          children: actions,
        ),
      ],
    );
  }
}
