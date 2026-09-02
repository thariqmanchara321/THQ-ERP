import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lightweight POS-side v6.0 transaction history.
///
/// This file is deliberately independent of POS sale writers. It only reads
/// the immutable v6 audit/explanation APIs and therefore cannot alter billing.
class PosAuditHistoryScreen extends StatefulWidget {
  const PosAuditHistoryScreen({
    super.key,
    required this.tenantId,
    this.locationId,
  });

  final String tenantId;
  final String? locationId;

  @override
  State<PosAuditHistoryScreen> createState() => _PosAuditHistoryScreenState();
}

class _PosAuditHistoryScreenState extends State<PosAuditHistoryScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final raw = await _client.rpc(
      'audit_normal_transactions_v600',
      params: {
        'p_tenant_id': widget.tenantId,
        'p_from': from.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String(),
        'p_location_id': widget.locationId,
        'p_limit': 150,
      },
    );
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) {
          return row.map((key, value) => MapEntry(key.toString(), value));
        })
        .toList(growable: false);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _openStory(Map<String, dynamic> row) async {
    final entityType = row['entity_type']?.toString() ?? '';
    final entityId = row['entity_id']?.toString() ?? '';
    if (entityType.isEmpty || entityId.isEmpty) return;
    final raw = await _client.rpc(
      'transaction_explain_v600',
      params: {
        'p_tenant_id': widget.tenantId,
        'p_entity_type': entityType,
        'p_entity_id': entityId,
        'p_event_limit': 100,
      },
    );
    if (!mounted) return;
    final data = raw is Map
        ? raw.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    final entity = data['entity'] is Map
        ? (data['entity'] as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : <String, dynamic>{};
    final why = data['why'] is Map
        ? (data['why'] as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : <String, dynamic>{};

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${entity['number'] ?? entityType} • Why / History'),
        content: SizedBox(
          width: 620,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(entity['history_note']?.toString() ?? ''),
              const SizedBox(height: 10),
              _line('What', why['what']),
              _line('Who', why['who']),
              _line('When', why['when']),
              _line('Where', why['where']),
              _line('Why', why['why']),
              _line('Approval', why['approval']),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$label: $text'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today • Transaction History'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load transaction history.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const Center(child: Text('No transaction history today.'));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                return ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: Text(
                    row['entity_number']?.toString() ??
                        row['entity_type']?.toString() ??
                        'Transaction',
                  ),
                  subtitle: Text(
                    [
                          row['action'],
                          row['event_time'],
                          row['user_name'],
                          row['device_name'],
                        ]
                        .where((value) => value != null)
                        .map((value) => value.toString())
                        .join(' • '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openStory(row),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
