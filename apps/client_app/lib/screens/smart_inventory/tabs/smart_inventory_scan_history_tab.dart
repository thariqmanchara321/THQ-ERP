import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../../models/client_session.dart';
import '../../../models/smart_inventory_session_models.dart';
import '../../../services/client_smart_inventory_service.dart';

class SmartInventoryScanHistoryTab extends StatefulWidget {
  final ClientSession session;

  const SmartInventoryScanHistoryTab({super.key, required this.session});

  @override
  State<SmartInventoryScanHistoryTab> createState() =>
      _SmartInventoryScanHistoryTabState();
}

class _SmartInventoryScanHistoryTabState
    extends State<SmartInventoryScanHistoryTab> {
  final ClientSmartInventoryService _service =
      ClientSmartInventoryService.instance;

  void _inspectSession(SmartScanSession scanSession) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(scanSession.title),
        content: SizedBox(
          width: 550,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Completed: ${DateFormat("yyyy-MM-dd HH:mm:ss").format(scanSession.completedAt ?? scanSession.createdAt)} • Operator: ${scanSession.operatorName}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const Text('Items Recorded:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              if (scanSession.items.isEmpty)
                const Text('No identified items were added in this session.')
              else
                SizedBox(
                  height: 220,
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: scanSession.items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = scanSession.items[index];
                      return ListTile(
                        dense: true,
                        title: Text(item.productName,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('SKU: ${item.sku}', style: const TextStyle(fontSize: 11)),
                        trailing: Text(
                          '${item.quantity.toStringAsFixed(0)} ${item.unitCode}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          ThqPrimaryButton(
            label: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final completed = _service.completedSessions;
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card with Persistence Disclaimer
          ThqCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scan Session Records (Local Runtime)',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Sessions completed during this application run are tracked below. Permanent server audit history is scheduled for the Phase 8 database hardening.',
                          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Content Area
          Expanded(
            child: completed.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history, size: 48, color: colors.onSurfaceVariant),
                        const SizedBox(height: 12),
                        const Text(
                          'No Completed Scan Sessions Yet',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Completed bulk scanning sessions will appear here for inspection and audit.',
                          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ThqCard(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: completed.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final session = completed[index];
                        final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(session.createdAt);

                        return ListTile(
                          onTap: () => _inspectSession(session),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: colors.primary.withValues(alpha: 0.1),
                            child: Icon(Icons.inventory, size: 18, color: colors.primary),
                          ),
                          title: Row(
                            children: [
                              Text(session.title,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(width: 8),
                              const ThqStatusBadge(
                                status: ThqStatus.completed,
                                label: 'Completed',
                              ),
                            ],
                          ),
                          subtitle: Text(
                            'Recorded $dateStr • ${session.totalDistinctProducts} products (${session.totalQuantity.toStringAsFixed(0)} units total) • Operator: ${session.operatorName}',
                            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 20),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
