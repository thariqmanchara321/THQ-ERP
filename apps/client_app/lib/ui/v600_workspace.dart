import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

/// Client-specific composition helpers for the v6 UI migration.
///
/// These wrappers own presentation only. Screens keep their existing services,
/// validation, permissions and transaction writers.
class ClientV600Workspace extends StatelessWidget {
  const ClientV600Workspace({
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const <Widget>[],
    this.toolbar,
    this.footer,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? toolbar;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return ThqPageFrame(
      title: title,
      subtitle: subtitle,
      actions: actions,
      toolbar: toolbar,
      footer: footer,
      child: child,
    );
  }
}

class ClientV600ListDetail extends StatelessWidget {
  const ClientV600ListDetail({
    required this.list,
    required this.detail,
    this.listFlex = 5,
    this.detailFlex = 7,
    super.key,
  });

  final Widget list;
  final Widget detail;
  final int listFlex;
  final int detailFlex;

  @override
  Widget build(BuildContext context) {
    return ThqSplitPane(
      primary: list,
      secondary: detail,
      primaryFlex: listFlex,
      secondaryFlex: detailFlex,
    );
  }
}

/// Standard transaction footer used while Sales/Purchase screens are migrated.
///
/// [onConfirm] and [onPrintAndConfirm] remain owned by the existing screen so
/// this component cannot bypass business validation or writer selection.
class ClientV600TransactionActions extends StatelessWidget {
  const ClientV600TransactionActions({
    required this.onConfirm,
    this.onPrintAndConfirm,
    this.busy = false,
    this.confirmLabel = 'Confirm',
    this.printAndConfirmLabel = 'Print & Confirm',
    this.leading = const <Widget>[],
    super.key,
  });

  final VoidCallback? onConfirm;
  final VoidCallback? onPrintAndConfirm;
  final bool busy;
  final String confirmLabel;
  final String printAndConfirmLabel;
  final List<Widget> leading;

  @override
  Widget build(BuildContext context) {
    return ThqStickyActionBar(
      secondaryActions: leading,
      primaryActions: [
        if (onPrintAndConfirm != null)
          ThqSecondaryButton(
            label: printAndConfirmLabel,
            busy: busy,
            onPressed: busy ? null : onPrintAndConfirm,
          ),
        ThqPrimaryButton(
          label: confirmLabel,
          busy: busy,
          onPressed: busy ? null : onConfirm,
        ),
      ],
    );
  }
}
