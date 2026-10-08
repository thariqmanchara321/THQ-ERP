import 'package:thq_ui/thq_ui.dart';
import 'package:flutter/material.dart';

class OperationalField {
  final String key;
  final String label;
  final bool required;
  final bool number;
  final bool date;
  final int lines;
  final Map<String, String>? options;
  final String? help;
  const OperationalField(
    this.key,
    this.label, {
    this.required = false,
    this.number = false,
    this.date = false,
    this.lines = 1,
    this.options,
    this.help,
  });
}

Future<bool?> showOperationalForm(
  BuildContext context, {
  required String title,
  required List<OperationalField> fields,
  required Future<void> Function(Map<String, dynamic>) onSave,
  Map<String, dynamic> initial = const {},
  String saveLabel = 'Save',
  String Function(Map<String, dynamic>)? preview,
}) {
  return showThqDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OperationalFormDialog(
      title: title,
      fields: fields,
      onSave: onSave,
      initial: initial,
      saveLabel: saveLabel,
      preview: preview,
    ),
  );
}

class _OperationalFormDialog extends StatefulWidget {
  final String title;
  final List<OperationalField> fields;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final Map<String, dynamic> initial;
  final String saveLabel;
  final String Function(Map<String, dynamic>)? preview;

  const _OperationalFormDialog({
    required this.title,
    required this.fields,
    required this.onSave,
    required this.initial,
    required this.saveLabel,
    required this.preview,
  });

  @override
  State<_OperationalFormDialog> createState() => _OperationalFormDialogState();
}

class _OperationalFormDialogState extends State<_OperationalFormDialog> {
  final key = GlobalKey<FormState>();
  late final Map<String, TextEditingController> controllers;
  late final Map<String, String> selected;
  var busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    controllers = {
      for (final field in widget.fields)
        field.key: TextEditingController(
          text: widget.initial[field.key]?.toString() ?? '',
        ),
    };
    selected = {
      for (final field in widget.fields.where((f) => f.options != null))
        field.key:
            field.options!.containsKey(widget.initial[field.key]?.toString())
            ? widget.initial[field.key].toString()
            : field.options!.keys.first,
    };
  }

  @override
  void dispose() {
    // A dialog's result completes before its closing animation removes it.
    // Keep controllers alive until the form widgets have been unmounted.
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> values() => {
    ...widget.initial,
    for (final field in widget.fields)
      field.key: field.options != null
          ? selected[field.key]
          : field.number
          ? double.tryParse(controllers[field.key]!.text.trim())
          : controllers[field.key]!.text.trim().isEmpty
          ? null
          : controllers[field.key]!.text.trim(),
  };

  Future<void> save() async {
    if (busy || key.currentState?.validate() != true) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSave(values());
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Form(
              key: key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 14,
                    children: widget.fields
                        .map(
                          (field) => SizedBox(
                            width: field.lines > 1
                                ? (MediaQuery.sizeOf(context).width - 144)
                                      .clamp(80.0, 720.0)
                                : (MediaQuery.sizeOf(context).width - 144)
                                      .clamp(80.0, 350.0),
                            child: field.options != null
                                ? DropdownButtonFormField<String>(
                                    initialValue: selected[field.key],
                                    decoration: InputDecoration(
                                      labelText: field.label,
                                      helperText: field.help,
                                    ),
                                    isExpanded: true,
                                    items: field.options!.entries
                                        .map(
                                          (e) => DropdownMenuItem(
                                            value: e.key,
                                            child: Text(
                                              e.value,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: busy
                                        ? null
                                        : (v) => setState(
                                            () => selected[field.key] = v!,
                                          ),
                                  )
                                : TextFormField(
                                    controller: controllers[field.key],
                                    enabled: !busy,
                                    minLines: field.lines,
                                    maxLines: field.lines,
                                    keyboardType: field.number
                                        ? const TextInputType.numberWithOptions(
                                            decimal: true,
                                          )
                                        : field.date
                                        ? TextInputType.datetime
                                        : TextInputType.text,
                                    decoration: InputDecoration(
                                      labelText: field.label,
                                      helperText: field.date
                                          ? 'YYYY-MM-DD'
                                          : field.help,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                    validator: (raw) {
                                      final text = raw?.trim() ?? '';
                                      if (field.required && text.isEmpty) {
                                        return '${field.label} is required';
                                      }
                                      if (text.isEmpty) return null;
                                      if (field.number &&
                                          (double.tryParse(text)?.isFinite !=
                                                  true ||
                                              double.parse(text) < 0)) {
                                        return 'Enter a finite, non-negative number';
                                      }
                                      if (field.date) {
                                        final day = DateTime.tryParse(text);
                                        if (day == null ||
                                            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}' !=
                                                text) {
                                          return 'Enter a valid date as YYYY-MM-DD';
                                        }
                                      }
                                      return null;
                                    },
                                  ),
                          ),
                        )
                        .toList(),
                  ),
                  if (widget.preview != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        widget.preview!(values()),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Saving…' : widget.saveLabel),
          ),
        ],
      ),
    );
  }
}
