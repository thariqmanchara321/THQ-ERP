import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// App-wide UX helper: when a numeric field containing only zero receives
/// focus, select the whole value so typing replaces 0/0.00 immediately.
class NumericZeroAutoSelect extends StatefulWidget {
  final Widget child;
  const NumericZeroAutoSelect({super.key, required this.child});

  @override
  State<NumericZeroAutoSelect> createState() => _NumericZeroAutoSelectState();
}

class _NumericZeroAutoSelectState extends State<NumericZeroAutoSelect> {
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_focusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    super.dispose();
  }

  void _focusChanged() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return;
    final editable = context.widget is EditableText
        ? context.widget as EditableText
        : context.findAncestorWidgetOfExactType<EditableText>();
    if (editable == null) return;
    final type = editable.keyboardType;
    final numeric =
        type == TextInputType.number ||
        type == const TextInputType.numberWithOptions(decimal: true) ||
        type == const TextInputType.numberWithOptions(decimal: false) ||
        type == const TextInputType.numberWithOptions(signed: true) ||
        type ==
            const TextInputType.numberWithOptions(decimal: true, signed: true);
    if (!numeric) return;
    final text = editable.controller.text.trim();
    if (!RegExp(r'^[-+]?0+(?:\.0+)?$').hasMatch(text)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (editable.controller.text.trim() == text) {
        editable.controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: editable.controller.text.length,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
