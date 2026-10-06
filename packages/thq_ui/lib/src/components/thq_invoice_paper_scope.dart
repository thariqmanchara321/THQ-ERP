import 'package:flutter/material.dart';
import '../theme/thq_theme.dart';

/// Printed paper must establish its own foreground as well as a light theme.
/// Theme alone would inherit the dark scaffold's DefaultTextStyle.
class ThqInvoicePaperScope extends StatelessWidget {
  const ThqInvoicePaperScope({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final paper = ThqTheme.light();
    return Theme(
      data: paper,
      child: DefaultTextStyle(style: paper.textTheme.bodyMedium!, child: child),
    );
  }
}
