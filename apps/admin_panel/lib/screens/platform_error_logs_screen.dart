import 'package:flutter/material.dart';
import '../services/platform_config_service.dart';

class PlatformErrorLogsScreen extends StatefulWidget {
  const PlatformErrorLogsScreen({super.key});
  @override
  State<PlatformErrorLogsScreen> createState() =>
      _PlatformErrorLogsScreenState();
}

class _PlatformErrorLogsScreenState extends State<PlatformErrorLogsScreen> {
  final _s = PlatformConfigService();
  late Future<List<Map<String, dynamic>>> _f;
  @override
  void initState() {
    super.initState();
    _f = _s.getAppErrorLogs();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F7FA),
    appBar: AppBar(title: const Text('Application Error Logs')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) return Center(child: Text(s.error.toString()));
        final rows = s.data ?? [];
        return ListView.separated(
          padding: const EdgeInsets.all(28),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final x = rows[i];
            return Card(
              child: ExpansionTile(
                title: Text(x['message']?.toString() ?? ''),
                subtitle: Text(
                  '${x['app_key']} • ${x['severity']} • ${x['created_at']}',
                ),
                children: [
                  if ((x['stack_trace']?.toString() ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(x['stack_trace'].toString()),
                    ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}
