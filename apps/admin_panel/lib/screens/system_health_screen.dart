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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 42,
        title: Text(
          '${widget.businessName} | System Health',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            visualDensity: VisualDensity.compact,
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, size: 17),
          ),
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
                padding: const EdgeInsets.all(16),
                child: Text(
                  snapshot.error.toString(),
                  textAlign: TextAlign.center,
                ),
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

          final metrics = <Widget>[
            _Metric(
              label: 'Critical',
              value: '$critical',
              icon: Icons.error_outline,
            ),
            _Metric(
              label: 'Warnings',
              value: '$warning',
              icon: Icons.warning_amber_outlined,
            ),
            _Metric(
              label: 'Schema',
              value: schema['schema_version']?.toString() ?? '?',
              icon: Icons.storage_outlined,
            ),
            _Metric(
              label: 'Migration',
              value: schema['migration_no']?.toString() ?? '?',
              icon: Icons.upgrade_outlined,
            ),
            _Metric(
              label: 'THQ API',
              value: api['api_version']?.toString() ?? '?',
              icon: Icons.api_outlined,
            ),
            _Metric(
              label: 'API Adapter',
              value: api['adapter']?.toString() ?? '?',
              icon: Icons.hub_outlined,
            ),
            _Metric(
              label: 'Config Sync',
              value: sync['configuration']?.toString() ?? '?',
              icon: Icons.sync_outlined,
            ),
            _Metric(
              label: 'Catalogue Sync',
              value: sync['catalogue']?.toString() ?? '?',
              icon: Icons.inventory_2_outlined,
            ),
          ];

          return Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1000
                        ? 8
                        : constraints.maxWidth >= 760
                        ? 4
                        : 2;
                    const gap = 5.0;
                    final width =
                        (constraints.maxWidth - ((columns - 1) * gap)) /
                        columns;

                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: metrics
                          .map(
                            (metric) => SizedBox(width: width, child: metric),
                          )
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 5),
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: critical == 0
                        ? scheme.primaryContainer.withValues(alpha: .12)
                        : scheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        critical == 0
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 15,
                        color: critical == 0 ? scheme.primary : scheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          critical == 0
                              ? 'No critical integrity errors detected.'
                              : 'Critical integrity issues require attention before release.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 8.2),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Expanded(
                  child: data.issues.isEmpty
                      ? Container(
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: const Center(
                            child: Text('Integrity scan is clean.'),
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: data.issues.length,
                            itemBuilder: (context, index) {
                              final issue = data.issues[index];
                              final count =
                                  (issue['issue_count'] as num?)?.toInt() ?? 0;
                              final severity =
                                  issue['severity']?.toString() ?? 'warning';

                              return Container(
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      severity == 'critical'
                                          ? Icons.error_outline
                                          : Icons.warning_amber_outlined,
                                      size: 15,
                                      color: severity == 'critical'
                                          ? scheme.error
                                          : scheme.tertiary,
                                    ),
                                    const SizedBox(width: 7),
                                    SizedBox(
                                      width: 150,
                                      child: Text(
                                        '${issue['code']} | $count',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        issue['description']?.toString() ?? '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 7.8),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
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

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _Metric({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: scheme.primary),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 8.8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 6.8,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
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
