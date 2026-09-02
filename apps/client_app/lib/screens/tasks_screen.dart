import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/location_scope_service.dart';
import '../services/task_service.dart';

class TasksScreen extends StatefulWidget {
  final ClientSession session;
  const TasksScreen({super.key, required this.session});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final TaskService _service = TaskService();
  bool _loading = true;
  String? _error;
  String _status = 'open';
  List<Map<String, dynamic>> _rows = const [];

  bool get _canManage =>
      widget.session.hasPermission('tasks.manage') ||
      widget.session.hasRole('owner');

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
        locationId: LocationScopeService.selectedLocationId.value,
        status: _status == 'all' ? null : _status,
      );
      if (mounted) setState(() => _rows = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime? _parse(dynamic value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toLocal();

  String _dateTime(DateTime? value) {
    if (value == null) return 'Not set';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} ${two(value.hour)}:${two(value.minute)}';
  }

  Future<DateTime?> _pickDateTime(
    DateTime? current, {
    required String title,
  }) async {
    final now = DateTime.now();
    final base = current ?? now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      helpText: title,
      initialDate: base,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      helpText: title,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null) {
      return DateTime(date.year, date.month, date.day, base.hour, base.minute);
    }
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    if (!_canManage) return;
    final title = TextEditingController(text: row?['title']?.toString() ?? '');
    final description = TextEditingController(
      text: row?['description']?.toString() ?? '',
    );
    String priority = row?['priority']?.toString() ?? 'normal';
    String status = row?['status']?.toString() ?? 'open';
    final assignedTo = row == null
        ? ''
        : (row['assigned_to']?.toString() ?? '');
    bool assignToMe = assignedTo.isEmpty || assignedTo == widget.session.userId;
    DateTime? dueAt = _parse(row?['due_at']);
    DateTime? reminderAt = _parse(row?['reminder_at']);

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(row == null ? 'New Task' : 'Edit Task'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    autofocus: row == null,
                    decoration: const InputDecoration(
                      labelText: 'Task *',
                      prefixIcon: Icon(Icons.task_alt),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Details'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: priority,
                          decoration: const InputDecoration(
                            labelText: 'Priority',
                          ),
                          items: const [
                            DropdownMenuItem(value: 'low', child: Text('Low')),
                            DropdownMenuItem(
                              value: 'normal',
                              child: Text('Normal'),
                            ),
                            DropdownMenuItem(
                              value: 'high',
                              child: Text('High'),
                            ),
                            DropdownMenuItem(
                              value: 'urgent',
                              child: Text('Urgent'),
                            ),
                          ],
                          onChanged: (value) => setDialogState(
                            () => priority = value ?? 'normal',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: status,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'open',
                              child: Text('Open'),
                            ),
                            DropdownMenuItem(
                              value: 'in_progress',
                              child: Text('In progress'),
                            ),
                            DropdownMenuItem(
                              value: 'done',
                              child: Text('Done'),
                            ),
                            DropdownMenuItem(
                              value: 'cancelled',
                              child: Text('Cancelled'),
                            ),
                          ],
                          onChanged: (value) =>
                              setDialogState(() => status = value ?? 'open'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Assign to me'),
                    subtitle: const Text(
                      'Turn off to keep this task unassigned.',
                    ),
                    value: assignToMe,
                    onChanged: (value) =>
                        setDialogState(() => assignToMe = value),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('Due date & time'),
                    subtitle: Text(_dateTime(dueAt)),
                    trailing: Wrap(
                      spacing: 2,
                      children: [
                        if (dueAt != null)
                          IconButton(
                            onPressed: () => setDialogState(() => dueAt = null),
                            icon: const Icon(Icons.clear),
                          ),
                        IconButton(
                          onPressed: () async {
                            final value = await _pickDateTime(
                              dueAt,
                              title: 'Task due',
                            );
                            if (value != null) {
                              setDialogState(() => dueAt = value);
                            }
                          },
                          icon: const Icon(Icons.edit_calendar_outlined),
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.alarm_outlined),
                    title: const Text('Reminder'),
                    subtitle: Text(_dateTime(reminderAt)),
                    trailing: Wrap(
                      spacing: 2,
                      children: [
                        if (reminderAt != null)
                          IconButton(
                            onPressed: () =>
                                setDialogState(() => reminderAt = null),
                            icon: const Icon(Icons.clear),
                          ),
                        IconButton(
                          onPressed: () async {
                            final value = await _pickDateTime(
                              reminderAt ?? dueAt,
                              title: 'Task reminder',
                            );
                            if (value != null) {
                              setDialogState(() => reminderAt = value);
                            }
                          },
                          icon: const Icon(Icons.add_alarm_outlined),
                        ),
                      ],
                    ),
                  ),
                  if (row?['source_notification_id'] != null)
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.notifications_active_outlined),
                      title: Text('Created from notification'),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(row == null ? 'Create' : 'Save'),
            ),
          ],
        ),
      ),
    );

    final taskTitle = title.text.trim();
    final taskDescription = description.text.trim();
    title.dispose();
    description.dispose();
    if (ok != true || taskTitle.isEmpty) return;
    if (reminderAt != null && dueAt != null && reminderAt!.isAfter(dueAt!)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder cannot be after the due time.'),
          ),
        );
      }
      return;
    }
    try {
      await _service.save(
        tenantId: widget.session.business.id,
        taskId: row?['id']?.toString(),
        locationId:
            row?['location_id']?.toString() ??
            LocationScopeService.selectedLocationId.value,
        title: taskTitle,
        description: taskDescription,
        priority: priority,
        status: status,
        assignedTo: assignToMe ? widget.session.userId : null,
        dueAt: dueAt,
        reminderAt: reminderAt,
        entityType: row?['entity_type']?.toString(),
        entityId: row?['entity_id']?.toString(),
        sourceNotificationId: row?['source_notification_id']?.toString(),
        metadata: row?['metadata'] is Map
            ? Map<String, dynamic>.from(row!['metadata'] as Map)
            : const {},
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _setStatus(Map<String, dynamic> row, String status) async {
    try {
      await _service.save(
        tenantId: widget.session.business.id,
        taskId: row['id']?.toString(),
        locationId: row['location_id']?.toString(),
        title: row['title']?.toString() ?? '',
        description: row['description']?.toString() ?? '',
        priority: row['priority']?.toString() ?? 'normal',
        status: status,
        assignedTo: row['assigned_to']?.toString(),
        dueAt: _parse(row['due_at']),
        reminderAt: _parse(row['reminder_at']),
        entityType: row['entity_type']?.toString(),
        entityId: row['entity_id']?.toString(),
        sourceNotificationId: row['source_notification_id']?.toString(),
        metadata: row['metadata'] is Map
            ? Map<String, dynamic>.from(row['metadata'] as Map)
            : const {},
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _timeline(Map<String, dynamic> row) async {
    final taskId = row['id']?.toString();
    if (taskId == null) {
      return;
    }

    final comment = TextEditingController();
    try {
      var data = await _service.timeline(
        tenantId: widget.session.business.id,
        taskId: taskId,
      );
      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final history = data['history'] is List
                ? data['history'] as List
                : const [];
            final comments = data['comments'] is List
                ? data['comments'] as List
                : const [];

            return AlertDialog(
              title: Text('Task history • ${row['title'] ?? ''}'),
              content: SizedBox(
                width: 680,
                height: 500,
                child: Column(
                  children: [
                    if (row['escalation_at'] != null)
                      ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.notification_important_outlined,
                        ),
                        title: Text(
                          'Escalates ${_dateTime(_parse(row['escalation_at']))}',
                        ),
                        subtitle: Text(
                          row['escalated_at'] == null
                              ? 'Pending escalation'
                              : 'Escalated ${_dateTime(_parse(row['escalated_at']))}',
                        ),
                      ),
                    Expanded(
                      child: ListView(
                        children: [
                          ...history.whereType<Map>().map(
                            (item) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.history),
                              title: Text(
                                item['note']?.toString() ??
                                    item['event_type']?.toString() ??
                                    'Update',
                              ),
                              subtitle: Text(
                                _dateTime(_parse(item['changed_at'])),
                              ),
                            ),
                          ),
                          ...comments.whereType<Map>().map(
                            (item) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.comment_outlined),
                              title: Text(item['comment']?.toString() ?? ''),
                              subtitle: Text(
                                _dateTime(_parse(item['created_at'])),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_canManage)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: comment,
                              decoration: const InputDecoration(
                                labelText: 'Add comment',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () async {
                              final text = comment.text.trim();
                              if (text.isEmpty) {
                                return;
                              }
                              await _service.addComment(
                                tenantId: widget.session.business.id,
                                taskId: taskId,
                                comment: text,
                              );
                              comment.clear();
                              data = await _service.timeline(
                                tenantId: widget.session.business.id,
                                taskId: taskId,
                              );
                              if (dialogContext.mounted) {
                                setDialogState(() {});
                              }
                            },
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              actions: [
                if (_canManage)
                  TextButton(
                    onPressed: () async {
                      final when = await _pickDateTime(
                        _parse(row['escalation_at']),
                        title: 'Escalation time',
                      );
                      if (when == null) {
                        return;
                      }
                      await _service.setEscalation(
                        tenantId: widget.session.business.id,
                        taskId: taskId,
                        escalationAt: when,
                        escalationUserId: widget.session.userId,
                      );
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                      await _load();
                    },
                    child: const Text('Set escalation'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      comment.dispose();
    }
  }

  Color _priorityColor(String priority) => switch (priority) {
    'urgent' => Colors.red,
    'high' => Colors.orange,
    'low' => Colors.blueGrey,
    _ => Colors.blue,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Tasks & Follow-ups',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  onPressed: _loading ? null : _load,
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                ),
                if (_canManage)
                  FilledButton.icon(
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add_task),
                    label: const Text('New Task'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: ['open', 'in_progress', 'done', 'cancelled', 'all']
                  .map(
                    (status) => ChoiceChip(
                      label: Text(status.replaceAll('_', ' ').toUpperCase()),
                      selected: _status == status,
                      onSelected: (_) {
                        setState(() => _status = status);
                        _load();
                      },
                    ),
                  )
                  .toList(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                  ? const Center(child: Text('No tasks in this view.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final row = _rows[index];
                          final status = row['status']?.toString() ?? 'open';
                          final priority =
                              row['priority']?.toString() ?? 'normal';
                          final due = _parse(row['due_at']);
                          final overdue =
                              due != null &&
                              due.isBefore(DateTime.now()) &&
                              !const ['done', 'cancelled'].contains(status);
                          return Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              onTap: _canManage ? () => _edit(row) : null,
                              dense: true,
                              leading: CircleAvatar(
                                backgroundColor: _priorityColor(
                                  priority,
                                ).withValues(alpha: .12),
                                child: Icon(
                                  status == 'done'
                                      ? Icons.check
                                      : overdue
                                      ? Icons.priority_high
                                      : Icons.task_alt_outlined,
                                  color: _priorityColor(priority),
                                ),
                              ),
                              title: Text(
                                row['title']?.toString() ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  priority.toUpperCase(),
                                  status.replaceAll('_', ' ').toUpperCase(),
                                  if (due != null)
                                    '${overdue ? 'OVERDUE' : 'Due'} ${_dateTime(due)}',
                                  if ((row['assigned_username']?.toString() ??
                                          '')
                                      .isNotEmpty)
                                    row['assigned_username'].toString(),
                                  if ((row['location_code']?.toString() ?? '')
                                      .isNotEmpty)
                                    row['location_code'].toString(),
                                  if (row['escalation_at'] != null)
                                    'Escalates ${_dateTime(_parse(row['escalation_at']))}',
                                  if ((row['description']?.toString() ?? '')
                                      .isNotEmpty)
                                    row['description'].toString(),
                                ].join(' • '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: !_canManage
                                  ? null
                                  : PopupMenuButton<String>(
                                      tooltip: 'Task actions',
                                      onSelected: (value) {
                                        if (value == 'edit') _edit(row);
                                        if (value == 'timeline') _timeline(row);
                                        if (value == 'open' ||
                                            value == 'in_progress' ||
                                            value == 'done' ||
                                            value == 'cancelled') {
                                          _setStatus(row, value);
                                        }
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit'),
                                        ),
                                        PopupMenuItem(
                                          value: 'timeline',
                                          child: Text(
                                            'History / comments / escalation',
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'open',
                                          child: Text('Mark open'),
                                        ),
                                        PopupMenuItem(
                                          value: 'in_progress',
                                          child: Text('Start / in progress'),
                                        ),
                                        PopupMenuItem(
                                          value: 'done',
                                          child: Text('Mark done'),
                                        ),
                                        PopupMenuItem(
                                          value: 'cancelled',
                                          child: Text('Cancel'),
                                        ),
                                      ],
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
