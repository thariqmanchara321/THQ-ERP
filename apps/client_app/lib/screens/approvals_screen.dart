import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/approval_service.dart';

class ApprovalsScreen extends StatefulWidget {
  final ClientSession session;
  const ApprovalsScreen({super.key, required this.session});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  final ApprovalService _service = ApprovalService();
  bool _loading = true;
  String? _error;
  String _status = 'pending';
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.list(
        tenantId: widget.session.business.id,
        status: _status == 'all' ? '' : _status,
      );
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(Map<String, dynamic> row, bool approve) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Approve Request' : 'Reject Request'),
        content: TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Decision note'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    final text = note.text;
    note.dispose();
    if (ok != true) return;
    await _service.decide(
      tenantId: widget.session.business.id,
      requestId: row['id'].toString(),
      approve: approve,
      note: text,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final canDecide =
        widget.session.hasRole('owner') ||
        widget.session.hasPermission('approvals.approve');
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Approvals',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
            ),
            const Text(
              'Review sensitive business actions before they are finalized.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: ['pending', 'approved', 'rejected', 'all']
                  .map(
                    (s) => ChoiceChip(
                      label: Text(s.toUpperCase()),
                      selected: _status == s,
                      onSelected: (_) {
                        setState(() => _status = s);
                        _load();
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _rows.isEmpty
                  ? const Center(child: Text('No approval requests.'))
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Icon(Icons.approval_outlined),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${row['module_key']} • ${row['action_key']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        [
                                              row['requested_username']
                                                  ?.toString(),
                                              row['reason']?.toString(),
                                              row['amount'] == null
                                                  ? null
                                                  : 'Amount ${row['amount']}',
                                            ]
                                            .where(
                                              (v) =>
                                                  v != null &&
                                                  v.trim().isNotEmpty,
                                            )
                                            .join(' • '),
                                      ),
                                    ],
                                  ),
                                ),
                                if (canDecide &&
                                    row['status'] == 'pending') ...[
                                  OutlinedButton(
                                    onPressed: () => _decide(row, false),
                                    child: const Text('Reject'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: () => _decide(row, true),
                                    child: const Text('Approve'),
                                  ),
                                ] else
                                  Chip(
                                    label: Text(
                                      row['status']?.toString().toUpperCase() ??
                                          '',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
