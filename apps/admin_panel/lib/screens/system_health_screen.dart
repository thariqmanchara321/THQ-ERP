import 'package:flutter/material.dart';

import '../services/system_health_service.dart';

class SystemHealthScreen extends StatefulWidget {
  final String tenantId;
  final String businessName;

  const SystemHealthScreen({
    super.key,
    required this.tenantId,
    required this.businessName,
  });

  @override
  State<SystemHealthScreen> createState() => _SystemHealthScreenState();
}

class _SystemHealthScreenState extends State<SystemHealthScreen> {
  final SystemHealthService _service = SystemHealthService();
  late Future<_HealthData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HealthData> _load() async {
    final summary = await _service.summary(widget.tenantId);
    final issues = await _service.scan(widget.tenantId);
    final connectivity = await _service.connectivity(widget.tenantId);
    return _HealthData(summary, issues, connectivity);
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.businessName} • System Health'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<_HealthData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(snapshot.error.toString(), textAlign: TextAlign.center),
              ),
            );
          }
          final data = snapshot.data!;
          final critical = (data.summary['critical'] as num?)?.toInt() ?? 0;
          final warning = (data.summary['warning'] as num?)?.toInt() ?? 0;
          final schema = data.summary['schema'] is Map
              ? Map<String, dynamic>.from(data.summary['schema'] as Map)
              : <String, dynamic>{};
          final api = data.connectivity['api'] is Map
              ? Map<String, dynamic>.from(data.connectivity['api'] as Map)
              : <String, dynamic>{};
          final sync = data.connectivity['sync'] is Map
              ? Map<String, dynamic>.from(data.connectivity['sync'] as Map)
              : <String, dynamic>{};
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _Metric(label: 'Critical', value: '$critical', icon: Icons.error_outline),
                  _Metric(label: 'Warnings', value: '$warning', icon: Icons.warning_amber_outlined),
                  _Metric(label: 'Schema', value: schema['schema_version']?.toString() ?? '?', icon: Icons.storage_outlined),
                  _Metric(label: 'Migration', value: schema['migration_no']?.toString() ?? '?', icon: Icons.upgrade_outlined),
                  _Metric(label: 'THQ API', value: api['api_version']?.toString() ?? '?', icon: Icons.api_outlined),
                  _Metric(label: 'API Adapter', value: api['adapter']?.toString() ?? '?', icon: Icons.hub_outlined),
                  _Metric(label: 'Config Sync', value: sync['configuration']?.toString() ?? '?', icon: Icons.sync_outlined),
                  _Metric(label: 'Catalogue Sync', value: sync['catalogue']?.toString() ?? '?', icon: Icons.inventory_2_outlined),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                critical == 0 ? 'No critical integrity errors detected.' : 'Critical integrity issues require attention before release.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (data.issues.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('Integrity scan is clean.')))
              else
                ...data.issues.map((issue) {
                  final count = (issue['issue_count'] as num?)?.toInt() ?? 0;
                  final severity = issue['severity']?.toString() ?? 'warning';
                  return Card(
                    child: ListTile(
                      leading: Icon(severity == 'critical' ? Icons.error_outline : Icons.warning_amber_outlined),
                      title: Text('${issue['code']} • $count'),
                      subtitle: Text(issue['description']?.toString() ?? ''),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _Metric({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: Theme.of(context).textTheme.headlineSmall), Text(label)])),
            ],
          ),
        ),
      ),
    );
  }
}

class _HealthData {
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> issues;
  final Map<String, dynamic> connectivity;
  const _HealthData(this.summary, this.issues, this.connectivity);
}
