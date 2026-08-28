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
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final title = TextEditingController();
    final description = TextEditingController();
    String priority = 'normal';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Task'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Task'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Details'),
                ),
                const SizedBox(height: 12),
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
                      setDialogState(() => priority = value ?? 'normal'),
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
              child: const Text('Create'),
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
    try {
      await _service.save(
        tenantId: widget.session.business.id,
        locationId: LocationScopeService.selectedLocationId.value,
        title: taskTitle,
        description: taskDescription,
        priority: priority,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _complete(Map<String, dynamic> row) async {
    await _service.save(
      tenantId: widget.session.business.id,
      taskId: row['id']?.toString(),
      locationId: row['location_id']?.toString(),
      title: row['title']?.toString() ?? '',
      description: row['description']?.toString() ?? '',
      priority: row['priority']?.toString() ?? 'normal',
      status: 'done',
      assignedTo: row['assigned_to']?.toString(),
      dueAt: DateTime.tryParse(row['due_at']?.toString() ?? ''),
      entityType: row['entity_type']?.toString(),
      entityId: row['entity_id']?.toString(),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tasks & Follow-ups',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Internal reminders, customer follow-ups and business actions.',
                    ),
                  ],
                ),
                if (widget.session.hasPermission('tasks.manage') ||
                    widget.session.hasRole('owner'))
                  FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add_task),
                    label: const Text('New Task'),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              children: ['open', 'in_progress', 'done', 'all']
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
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _rows.isEmpty
                  ? const Center(child: Text('No tasks in this view.'))
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              row['status'] == 'done'
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                            ),
                            title: Text(row['title']?.toString() ?? ''),
                            subtitle: Text(
                              [
                                    row['priority']?.toString().toUpperCase(),
                                    row['location_code']?.toString(),
                                    row['assigned_username']?.toString(),
                                    row['description']?.toString(),
                                  ]
                                  .where(
                                    (value) =>
                                        value != null &&
                                        value.trim().isNotEmpty,
                                  )
                                  .join(' • '),
                            ),
                            trailing:
                                row['status'] == 'done' ||
                                    !(widget.session.hasPermission(
                                          'tasks.manage',
                                        ) ||
                                        widget.session.hasRole('owner'))
                                ? null
                                : IconButton(
                                    tooltip: 'Mark done',
                                    onPressed: () => _complete(row),
                                    icon: const Icon(Icons.done),
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
