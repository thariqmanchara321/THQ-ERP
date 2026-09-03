import 'package:flutter/material.dart';
import '../widgets/admin_home_button.dart';

import '../models/platform_models.dart';
import '../services/platform_config_service.dart';

class PlatformAuditScreen extends StatefulWidget {
  const PlatformAuditScreen({super.key});
  @override
  State<PlatformAuditScreen> createState() => _PlatformAuditScreenState();
}

class _PlatformAuditScreenState extends State<PlatformAuditScreen> {
  final _service = PlatformConfigService();
  late Future<List<PlatformAuditEvent>> _future;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _service.getAuditEvents();
  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  String _date(DateTime? d) => d == null
      ? '-'
      : d.toLocal().toString().replaceFirst(RegExp(r'\.\d+$'), '');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 42,
        title: const Text('Platform Audit Log'),
        actions: const [AdminHomeButton()],
      ),
      body: FutureBuilder<List<PlatformAuditEvent>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final rows = snapshot.data ?? const [];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(6),
              children: [
                const Text(
                  'Platform Audit Log',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Security-sensitive platform configuration changes are recorded by backend RPCs.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 6),
                ...rows.map(
                  (e) => Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.history_outlined),
                      title: Text(
                        '${e.action} • ${e.entityType}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${e.actorEmail}  •  ${_date(e.createdAt)}${e.tenantName == null ? '' : '  •  ${e.tenantName}'}',
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(e.details.toString()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
