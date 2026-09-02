import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ThqTextField extends StatelessWidget {
  const ThqTextField({
    this.controller,
    this.label,
    this.hint,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
    this.keyboardType,
    this.inputFormatters,
    this.prefixIcon,
    this.suffixIcon,
    this.maxLines = 1,
    super.key,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool autofocus;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class ThqNumberField extends StatelessWidget {
  const ThqNumberField({
    this.controller,
    this.label,
    this.hint,
    this.focusNode,
    this.onChanged,
    this.enabled = true,
    this.allowDecimal = true,
    this.allowNegative = false,
    super.key,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool allowDecimal;
  final bool allowNegative;

  @override
  Widget build(BuildContext context) {
    final sign = allowNegative ? r'-?' : '';
    final body = allowDecimal ? r'\d*(?:\.\d*)?' : r'\d*';
    final expression = RegExp('^$sign$body\$');
    final numberFormatter = TextInputFormatter.withFunction((oldValue, newValue) {
      return expression.hasMatch(newValue.text) ? newValue : oldValue;
    });
    return ThqTextField(
      controller: controller,
      label: label,
      hint: hint,
      focusNode: focusNode,
      onChanged: onChanged,
      enabled: enabled,
      keyboardType: TextInputType.numberWithOptions(
        decimal: allowDecimal,
        signed: allowNegative,
      ),
      inputFormatters: [numberFormatter],
    );
  }
}

class ThqSearchField extends StatelessWidget {
  const ThqSearchField({
    this.controller,
    this.hint = 'Search',
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    super.key,
  });

  final TextEditingController? controller;
  final String hint;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return ThqTextField(
      controller: controller,
      hint: hint,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
      prefixIcon: const Icon(Icons.search),
    );
  }
}
