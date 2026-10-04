import 'package:flutter/material.dart';
import '../models/record_presentation.dart';

/// A complete, selectable preview of saved operational evidence.
class RecordPreview extends StatelessWidget {
  final Map<String, dynamic> record;
  final String currency;
  const RecordPreview({super.key, required this.record, this.currency = ''});

  static String label(String key) => RecordPresentation.label(key);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: RecordPresentation.report(record).entries
        .map(
          (entry) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: entry.value is Map || entry.value is List
                ? ExpansionTile(
                    title: Text(label(entry.key)),
                    children: [
                      if (entry.value is Map)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: RecordPreview(
                            record: Map<String, dynamic>.from(entry.value),
                            currency: currency,
                          ),
                        )
                      else if ((entry.value as List).isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('No records.'),
                        )
                      else
                        for (final item in entry.value as List)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: item is Map
                                ? Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: RecordPreview(
                                        record: Map<String, dynamic>.from(item),
                                        currency: currency,
                                      ),
                                    ),
                                  )
                                : SelectableText('$item'),
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
                      SelectableText(
                        RecordPresentation.value(
                          entry.key,
                          entry.value,
                          currency: currency,
                        ),
                      ),
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
    String currency = '',
  }) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 800,
        child: SingleChildScrollView(
          child: RecordPreview(record: record, currency: currency),
        ),
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
