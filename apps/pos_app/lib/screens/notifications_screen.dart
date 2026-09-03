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
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Notifications',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Stock, payment, approval and system alerts',
                        style: TextStyle(
                          fontSize: 8.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
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
                        final row = rows[index];
                        final unread = row['read_at'] == null;
                        final severity = row['severity']?.toString() ?? 'info';
                        final icon = severity == 'critical'
                            ? Icons.error_outline
                            : severity == 'warning'
                            ? Icons.warning_amber_outlined
                            : Icons.notifications_none;

                        return Container(
                          constraints: const BoxConstraints(minHeight: 52),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: unread
                                ? scheme.primaryContainer.withValues(alpha: .08)
                                : Colors.transparent,
                            border: Border(
                              bottom: BorderSide(color: scheme.outlineVariant),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                icon,
                                size: 16,
                                color: severity == 'critical'
                                    ? scheme.error
                                    : severity == 'warning'
                                    ? scheme.tertiary
                                    : scheme.primary,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      row['title']?.toString() ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 8.8,
                                        fontWeight: unread
                                            ? FontWeight.w900
                                            : FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      row['message']?.toString() ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 7.5,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      row['created_at']?.toString() ?? '',
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 6.8,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (unread)
                                TextButton(
                                  onPressed: () async {
                                    await _service.markRead(
                                      widget.session.business.id,
                                      row['id'].toString(),
                                    );
                                    _refresh();
                                  },
                                  child: const Text('Mark read'),
                                )
                              else
                                const SizedBox(
                                  width: 34,
                                  child: Icon(Icons.done, size: 15),
                                ),
                            ],
                          ),
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
