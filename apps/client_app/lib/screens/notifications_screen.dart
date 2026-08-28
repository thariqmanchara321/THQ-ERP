import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  final ClientSession session;
  const NotificationsScreen({super.key, required this.session});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _service = NotificationService();
  late Future<List<Map<String, dynamic>>> _future;
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
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
                      'Notifications',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text('Stock, payment, approval and system alerts'),
                  ],
                ),
              ),
              IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 16),
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
                final rows = snapshot.data ?? const [];
                if (rows.isEmpty) {
                  return const Center(child: Text('You are all caught up.'));
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final unread = row['read_at'] == null;
                      final severity = row['severity']?.toString() ?? 'info';
                      final icon = severity == 'critical'
                          ? Icons.error_outline
                          : severity == 'warning'
                          ? Icons.warning_amber_outlined
                          : Icons.notifications_none;
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Icon(icon)),
                          title: Text(
                            row['title']?.toString() ?? '',
                            style: TextStyle(
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${row['message'] ?? ''}\n${row['created_at'] ?? ''}',
                          ),
                          isThreeLine: true,
                          trailing: unread
                              ? TextButton(
                                  onPressed: () async {
                                    await _service.markRead(
                                      widget.session.business.id,
                                      row['id'].toString(),
                                    );
                                    _refresh();
                                  },
                                  child: const Text('Mark read'),
                                )
                              : const Icon(Icons.done, size: 18),
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
