import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

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
        ThqNotify.showSnackBar(
          context,
          const SnackBar(content: Text('Issue added to the system log.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  String _date(DateTime? date) => date == null ? '-' : '${date.toLocal()}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 25,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'System Logs',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            BusinessActivityScreen(session: widget.session),
                      ),
                    );
                  },
                  icon: const Icon(Icons.history, size: 14),
                  label: const Text('Activity'),
                ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            TrackingLookupScreen(session: widget.session),
                      ),
                    );
                  },
                  icon: const Icon(Icons.qr_code_2, size: 14),
                  label: const Text('Track ID'),
                ),
                const SizedBox(width: 4),
                FilledButton.tonalIcon(
                  onPressed: _reportIssue,
                  icon: const Icon(Icons.add_comment_outlined, size: 14),
                  label: const Text('Report Issue'),
                ),
                const SizedBox(width: 2),
                IconButton(
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
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

                return Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final item = rows[index];
                        final isIssue = item.severity == 'issue';

                        return ExpansionTile(
                          dense: true,
                          leading: Icon(
                            isIssue
                                ? Icons.report_problem_outlined
                                : item.severity == 'fatal'
                                ? Icons.dangerous_outlined
                                : Icons.error_outline,
                            size: 16,
                          ),
                          title: Text(
                            item.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            '${item.appKey.toUpperCase()} | '
                            '${item.severity.toUpperCase()} | '
                            '${_date(item.createdAt)}',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          children: [
                            if ((item.stackTrace ?? '').isNotEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: .35),
                                child: SelectableText(
                                  item.stackTrace!,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
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
