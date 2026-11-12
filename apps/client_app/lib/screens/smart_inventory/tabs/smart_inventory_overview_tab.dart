import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../../models/client_session.dart';
import '../../../services/client_smart_inventory_service.dart';

class SmartInventoryOverviewTab extends StatelessWidget {
  final ClientSession session;
  final ValueChanged<int> onSelectTab;

  const SmartInventoryOverviewTab({
    super.key,
    required this.session,
    required this.onSelectTab,
  });

  @override
  Widget build(BuildContext context) {
    final service = ClientSmartInventoryService.instance;
    final activity = service.recentActivity;

    final totalScans = activity.length;
    final successfulScans =
        activity.where((e) => e.status == ProductIdentificationStatus.exactMatch).length;
    final unresolvedScans =
        activity.where((e) => e.status != ProductIdentificationStatus.exactMatch).length;
    final activeBulk = service.activeBulkSession;

    final colors = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          ThqCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.qr_code_scanner, color: colors.primary, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'THQ Smart Inventory',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Unified hardware wedge scanning, camera barcode recognition, and instant multi-identifier product lookup.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Metric Stat Tiles
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;
              final tiles = [
                _StatTile(
                  label: 'Session Scans',
                  value: totalScans.toString(),
                  icon: Icons.barcode_reader,
                  color: colors.primary,
                ),
                _StatTile(
                  label: 'Identified Products',
                  value: successfulScans.toString(),
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                ),
                _StatTile(
                  label: 'Unresolved / Misses',
                  value: unresolvedScans.toString(),
                  icon: Icons.help_outline,
                  color: unresolvedScans > 0 ? Colors.orange : colors.onSurfaceVariant,
                ),
                _StatTile(
                  label: 'Bulk Session',
                  value: activeBulk != null ? '${activeBulk.totalDistinctProducts} items' : 'Idle',
                  icon: Icons.format_list_numbered,
                  color: activeBulk != null ? Colors.blue : colors.onSurfaceVariant,
                ),
              ];

              if (isWide) {
                return Row(
                  children: tiles
                      .map((t) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: t,
                            ),
                          ))
                      .toList(),
                );
              }
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: tiles
                    .map((t) => SizedBox(
                          width: (constraints.maxWidth - 12) / 2,
                          child: t,
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 24),

          // Action Launchers
          Text(
            'Quick Workspaces',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                _ActionCard(
                  title: 'Scan Center',
                  subtitle:
                      'Point camera or use USB/Bluetooth barcode gun to immediately identify single products.',
                  icon: Icons.camera_alt_outlined,
                  buttonText: 'Open Scan Center',
                  onTap: () => onSelectTab(1),
                ),
                _ActionCard(
                  title: 'Product Lookup',
                  subtitle:
                      'Search by name, SKU, manufacturer code, supplier part number or alternate identifiers.',
                  icon: Icons.search,
                  buttonText: 'Search Catalog',
                  onTap: () => onSelectTab(2),
                ),
                _ActionCard(
                  title: 'Bulk Scanning',
                  subtitle:
                      'Continuously scan crates or shipments into a temporary audit list without altering stock.',
                  icon: Icons.playlist_add_check,
                  buttonText: 'Start Bulk Scan',
                  onTap: () => onSelectTab(3),
                ),
                _ActionCard(
                  title: 'Product Import',
                  subtitle:
                      'Batch import product catalogues from Excel (.xlsx) or CSV with intelligent auto-mapping.',
                  icon: Icons.upload_file_outlined,
                  buttonText: 'Import Products',
                  onTap: () => onSelectTab(5),
                ),
                _ActionCard(
                  title: 'Barcode Studio',
                  subtitle:
                      'Design, generate, and print thermal barcode labels and A4 multi-label sheets with GS1 check digits.',
                  icon: Icons.print_outlined,
                  buttonText: 'Open Barcode Studio',
                  onTap: () => onSelectTab(6),
                ),
                _ActionCard(
                  title: 'Stock Counting',
                  subtitle:
                      'Perform physical stock audits, reconcile shortages or excess, and post approved count adjustments.',
                  icon: Icons.inventory_2_outlined,
                  buttonText: 'Start Stock Count',
                  onTap: () => onSelectTab(7),
                ),
                _ActionCard(
                  title: 'Purchase Receiving',
                  subtitle:
                      'Inward supplier deliveries against purchase orders or direct receipts, verify quantities, and post goods receipts.',
                  icon: Icons.call_received,
                  buttonText: 'Receive Goods',
                  onTap: () => onSelectTab(8),
                ),
                _ActionCard(
                  title: 'Product Intelligence',
                  subtitle:
                      'Lookup products against GS1 Registry and open catalogues, resolve conflicts side-by-side, and enrich catalogue data.',
                  icon: Icons.auto_awesome,
                  buttonText: 'Lookup Intelligence',
                  onTap: () => onSelectTab(9),
                ),
              ];

              final width = constraints.maxWidth;
              final crossAxisCount = width > 1100 ? 3 : (width > 650 ? 2 : 1);
              if (crossAxisCount > 1) {
                final cardWidth = (width - ((crossAxisCount - 1) * 12)) / crossAxisCount;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: cards
                      .map((c) => SizedBox(
                            width: cardWidth,
                            child: c,
                          ))
                      .toList(),
                );
              }
              return Column(
                children: cards
                    .map((c) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: c,
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 28),

          // Recent Activity Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Scan Activity',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (activity.isNotEmpty)
                Text(
                  '${activity.length} recorded',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (activity.isEmpty)
            ThqCard(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.barcode_reader, size: 40, color: colors.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(
                      'No scans performed yet in this session',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Connect a USB barcode gun, click Scan Center, or search catalog to begin.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ThqCard(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: activity.length > 8 ? 8 : activity.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = activity[index];
                  final isSuccess = item.isSuccess;
                  final timeStr = DateFormat('HH:mm:ss').format(item.timestamp);

                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: isSuccess
                          ? Colors.green.withValues(alpha: 0.12)
                          : Colors.orange.withValues(alpha: 0.12),
                      child: Icon(
                        isSuccess ? Icons.check : Icons.help_outline,
                        size: 16,
                        color: isSuccess ? Colors.green : Colors.orange,
                      ),
                    ),
                    title: Text(
                      isSuccess ? item.productName ?? 'Product Found' : 'Unresolved Code',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    subtitle: Text(
                      'Code: ${item.rawCode}${item.sku != null ? ' • SKU: ${item.sku}' : ''}',
                      style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ThqStatusBadge(
                          status: isSuccess ? ThqStatus.completed : ThqStatus.pending,
                          label: item.status.name,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          timeStr,
                          style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                        ),
                      ],
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

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ThqCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String buttonText;
  final VoidCallback onTap;

  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.buttonText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ThqCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colors.primary, size: 26),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurfaceVariant,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ThqSecondaryButton(
                label: buttonText,
                onPressed: onTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
