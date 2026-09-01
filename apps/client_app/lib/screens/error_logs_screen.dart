import 'package:flutter/material.dart';

import 'business_activity_screen.dart';
import 'tracking_lookup_screen.dart';

import '../models/app_error_log.dart';
import '../models/client_session.dart';
import '../services/app_log_service.dart';

class ErrorLogsScreen extends StatefulWidget {
  final ClientSession session;
  final String reportAppKey;

  const ErrorLogsScreen({
    super.key,
    required this.session,
    this.reportAppKey = 'client',
  });

  @override
  State<ErrorLogsScreen> createState() => _ErrorLogsScreenState();
}

class _ErrorLogsScreenState extends State<ErrorLogsScreen> {
  final AppLogService _service = AppLogService();
  late Future<List<AppErrorLog>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _service.list(tenantId: widget.session.business.id);
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  Future<void> _reportIssue() async {
    final result = await showDialog<_IssueReport>(
      context: context,
      builder: (_) => const _ReportIssueDialog(),
    );

    if (result == null || !mounted) {
      return;
    }

    try {
      await _service.reportIssue(
        tenantId: widget.session.business.id,
        appKey: widget.reportAppKey,
        message: result.message,
        details: result.details,
      );
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Issue added to the system log.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  String _date(DateTime? date) => date == null ? '-' : '${date.toLocal()}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System Logs',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text('Client, POS and recorded issues for this business'),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          BusinessActivityScreen(session: widget.session),
                    ),
                  );
                },
                icon: const Icon(Icons.history),
                label: const Text('Activity Log'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          TrackingLookupScreen(session: widget.session),
                    ),
                  );
                },
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Track ID'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _reportIssue,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Report Issue'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: FutureBuilder<List<AppErrorLog>>(
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
                  return const Center(
                    child: Text('No errors or issues logged.'),
                  );
                }

                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = rows[index];
                    final isIssue = item.severity == 'issue';
                    return Card(
                      child: ExpansionTile(
                        leading: Icon(
                          isIssue
                              ? Icons.report_problem_outlined
                              : item.severity == 'fatal'
                              ? Icons.dangerous_outlined
                              : Icons.error_outline,
                        ),
                        title: Text(
                          item.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${item.appKey.toUpperCase()} • '
                          '${item.severity.toUpperCase()} • '
                          '${_date(item.createdAt)}',
                        ),
                        children: [
                          if ((item.stackTrace ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: SelectableText(item.stackTrace!),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _IssueReport {
  final String message;
  final String details;

  const _IssueReport(this.message, this.details);
}

class _ReportIssueDialog extends StatefulWidget {
  const _ReportIssueDialog();

  @override
  State<_ReportIssueDialog> createState() => _ReportIssueDialogState();
}

class _ReportIssueDialogState extends State<_ReportIssueDialog> {
  final TextEditingController _message = TextEditingController();
  final TextEditingController _details = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report an Issue'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _message,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'What went wrong? *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _details,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Details / steps to reproduce',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final message = _message.text.trim();
            if (message.isEmpty) {
              return;
            }
            Navigator.pop(context, _IssueReport(message, _details.text.trim()));
          },
          child: const Text('Add to Log'),
        ),
      ],
    );
  }
}
