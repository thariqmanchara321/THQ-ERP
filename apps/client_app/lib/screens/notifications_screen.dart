import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../services/notification_service.dart';
import '../services/task_service.dart';

class NotificationsScreen extends StatefulWidget {
  final ClientSession session;
  const NotificationsScreen({super.key, required this.session});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _service = NotificationService();
  final TaskService _tasks = TaskService();
  late Future<List<Map<String, dynamic>>> _future;
  bool _unreadOnly = false;
  bool _busy = false;

  bool get _canManageTasks =>
      widget.session.hasPermission('tasks.manage') ||
      widget.session.hasRole('owner');

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = _service.list(widget.session.business.id);

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  Future<void> _markAllRead() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final count = await _service.markAllRead(widget.session.business.id);
      await _refresh();
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text('$count notification(s) marked read.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createTask(Map<String, dynamic> row) async {
    if (!_canManageTasks || _busy) return;
    final severity = row['severity']?.toString() ?? 'info';
    final defaultPriority = severity == 'critical'
        ? 'urgent'
        : severity == 'warning'
        ? 'high'
        : 'normal';
    String priority = defaultPriority;
    DateTime due = DateTime.now().add(
      Duration(
        hours: severity == 'critical'
            ? 4
            : severity == 'warning'
            ? 24
            : 72,
      ),
    );
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Task from Notification'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['title']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(row['message']?.toString() ?? ''),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => priority = value ?? defaultPriority),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Due date'),
                  subtitle: Text(
                    '${due.day.toString().padLeft(2, '0')}/${due.month.toString().padLeft(2, '0')}/${due.year}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_calendar_outlined),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: due,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(
                          const Duration(days: 3650),
                        ),
                      );
                      if (picked != null) {
                        setDialogState(
                          () => due = DateTime(
                            picked.year,
                            picked.month,
                            picked.day,
                            17,
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Create Task'),
            ),
          ],
        ),
      ),
    );
    if (proceed != true) return;
    setState(() => _busy = true);
    try {
      await _tasks.createFromNotification(
        tenantId: widget.session.business.id,
        notificationId: row['id'].toString(),
        assignedTo: widget.session.userId,
        dueAt: due,
        priority: priority,
      );
      await _service.markRead(widget.session.business.id, row['id'].toString());
      await _refresh();
      if (mounted) {
        ThqNotify.success(
          context,
          'Task created and linked to this notification.',
        );
      }
    } catch (error) {
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  IconData _icon(String severity) => switch (severity) {
    'critical' => Icons.error_outline,
    'warning' => Icons.warning_amber_outlined,
    'success' => Icons.check_circle_outline,
    _ => Icons.notifications_none,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Notifications',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              FilterChip(
                label: const Text('Unread only'),
                selected: _unreadOnly,
                onSelected: (value) => setState(() => _unreadOnly = value),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: _busy ? null : _markAllRead,
                icon: const Icon(Icons.done_all),
                label: const Text('Mark all read'),
              ),
              IconButton(
                onPressed: _busy ? null : _refresh,
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(snapshot.error.toString()));
                }
                final source = snapshot.data ?? const <Map<String, dynamic>>[];
                final rows = _unreadOnly
                    ? source.where((row) => row['read_at'] == null).toList()
                    : source;
                if (rows.isEmpty) {
                  return const Center(child: Text('You are all caught up.'));
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final unread = row['read_at'] == null;
                      final severity = row['severity']?.toString() ?? 'info';
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(child: Icon(_icon(severity))),
                          title: Text(
                            row['title']?.toString() ?? '',
                            style: TextStyle(
                              fontWeight: unread
                                  ? FontWeight.w900
                                  : FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${row['message'] ?? ''}\n${row['created_at'] ?? ''}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                          trailing: Wrap(
                            spacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (_canManageTasks &&
                                  row['entity_type']?.toString() != 'task')
                                IconButton(
                                  tooltip: 'Create linked task',
                                  onPressed: _busy
                                      ? null
                                      : () => _createTask(row),
                                  icon: const Icon(Icons.add_task_outlined),
                                ),
                              if (unread)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          await _service.markRead(
                                            widget.session.business.id,
                                            row['id'].toString(),
                                          );
                                          await _refresh();
                                        },
                                  child: const Text('Read'),
                                )
                              else
                                const Icon(Icons.done, size: 18),
                            ],
                          ),
                        ),
                      );
                    },
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
