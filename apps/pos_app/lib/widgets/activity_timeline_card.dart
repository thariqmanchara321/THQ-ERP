import 'package:flutter/material.dart';

class ActivityTimelineCard extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> future;
  const ActivityTimelineCard({super.key, required this.future});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.history_outlined),
        title: const Text('Activity & Audit'),
        subtitle: const Text('Who changed, corrected or printed this record'),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(snapshot.error.toString()),
                );
              }
              final rows = snapshot.data ?? const [];
              if (rows.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No audit activity recorded yet.'),
                );
              }
              return Column(
                children: rows.map((row) {
                  final when = DateTime.tryParse(
                    row['activity_time']?.toString() ?? '',
                  );
                  final time = when == null
                      ? ''
                      : '${when.toLocal().year}-${when.toLocal().month.toString().padLeft(2, '0')}-${when.toLocal().day.toString().padLeft(2, '0')} '
                            '${when.toLocal().hour.toString().padLeft(2, '0')}:${when.toLocal().minute.toString().padLeft(2, '0')}';
                  final contextBits = [
                    row['user_name']?.toString(),
                    row['location_code']?.toString(),
                    row['device_code']?.toString(),
                    time,
                  ].where((e) => e != null && e.trim().isNotEmpty).join(' • ');
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Icon(
                        _icon(row['activity_type']?.toString() ?? ''),
                      ),
                    ),
                    title: Text(
                      row['title']?.toString().replaceAll('_', ' ') ??
                          'Activity',
                    ),
                    subtitle: Text(
                      [
                        row['description']?.toString() ?? '',
                        contextBits,
                      ].where((e) => e.trim().isNotEmpty).join('\n'),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  IconData _icon(String type) => switch (type) {
    'print' => Icons.print_outlined,
    'correction' => Icons.rule_outlined,
    _ => Icons.history_outlined,
  };
}
