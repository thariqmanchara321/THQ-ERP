import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/app_log_service.dart';

class BusinessActivityScreen extends StatefulWidget {
  final ClientSession session;

  const BusinessActivityScreen({super.key, required this.session});

  @override
  State<BusinessActivityScreen> createState() => _BusinessActivityScreenState();
}

class _BusinessActivityScreenState extends State<BusinessActivityScreen> {
  final AppLogService _service = AppLogService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _service.auditList(tenantId: widget.session.business.id);
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  String _pretty(dynamic value) {
    if (value == null) {
      return '-';
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Business Activity Log'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }

          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const Center(child: Text('No audited changes yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = rows[index];
              final action = row['action']?.toString() ?? 'activity';
              final type = row['entity_type']?.toString() ?? 'entity';
              final ref = row['entity_reference']?.toString();
              final createdAt = row['created_at']?.toString() ?? '';

              return Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.history),
                  title: Text(
                    '${action.replaceAll('_', ' ').toUpperCase()} • '
                    '${type.replaceAll('_', ' ')}',
                  ),
                  subtitle: Text(
                    '${ref == null || ref.isEmpty ? '' : '$ref • '}$createdAt',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _AuditDataBox(
                              title: 'Before',
                              value: _pretty(row['before_data']),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _AuditDataBox(
                              title: 'After',
                              value: _pretty(row['after_data']),
                            ),
                          ),
                        ],
                      ),
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
}

class _AuditDataBox extends StatelessWidget {
  final String title;
  final String value;

  const _AuditDataBox({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}
