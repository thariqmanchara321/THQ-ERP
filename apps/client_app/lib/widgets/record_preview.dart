import 'dart:convert';

import 'package:flutter/material.dart';

/// A complete, selectable preview of saved operational evidence.
class RecordPreview extends StatelessWidget {
  final Map<String, dynamic> record;
  const RecordPreview({super.key, required this.record});

  static String label(String key) => key.replaceAll('_', ' ');
  static String value(dynamic value) => value is Map || value is List
      ? const JsonEncoder.withIndent('  ').convert(value)
      : value?.toString() ?? '—';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: record.entries
        .map(
          (entry) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: entry.value is Map || entry.value is List
                ? ExpansionTile(
                    title: Text(label(entry.key)),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(value(entry.value)),
                        ),
                      ),
                    ],
                  )
                : Wrap(
                    spacing: 12,
                    children: [
                      Text(
                        '${label(entry.key)}:',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SelectableText(value(entry.value)),
                    ],
                  ),
          ),
        )
        .toList(),
  );

  static Future<void> show(
    BuildContext context, {
    required String title,
    required Map<String, dynamic> record,
  }) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 800,
        child: SingleChildScrollView(child: RecordPreview(record: record)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
