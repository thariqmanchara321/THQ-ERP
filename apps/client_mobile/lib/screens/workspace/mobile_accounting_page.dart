import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../models/mobile_session.dart';
import '../../services/mobile_client_service.dart';

class MobileAccountingPage extends StatelessWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobileAccountingPage({
    super.key,
    required this.session,
    required this.service,
    this.locationId,
  });

  String get _scopeLabel {
    if (locationId == null) return 'Entire business';
    for (final loc in session.locations) {
      if (loc.id == locationId) return loc.name;
    }
    return session.locationName;
  }

  Future<ThqAccountingResult> _load(ThqAccountingQuery query) async {
    final response = await Supabase.instance.client.rpc(
      'accounting_workspace_v702',
      params: query.parameters(session.tenantId, locationId),
    );
    return ThqAccountingResult(accountingMap(response));
  }

  Future<void> _export(
    BuildContext context,
    ThqAccountingQuery query,
    String format,
  ) async {
    ThqNotify.info(
      context,
      'Accounting Export',
      message: 'Exporting ${query.report} in $format format is prepared.',
    );
  }

  Future<void> _openSource(BuildContext context, Map<String, dynamic> row) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        minChildSize: 0.35,
        expand: false,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_rounded),
                const SizedBox(width: 8),
                Text(
                  row['source_reference']?.toString() ??
                      row['entry_number']?.toString() ??
                      'Transaction Details',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 20),
            ...row.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(
                          e.key,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e.value?.toString() ?? '—',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Financial & Accounting'),
            Text(
              _scopeLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
      body: ThqAccountingWorkspace(
        businessId: session.tenantId,
        scopeKey: locationId ?? 'permitted',
        scopeLabel: _scopeLabel,
        currency: session.currency,
        load: _load,
        export: (query, format) => _export(context, query, format),
        openSource: (row) => _openSource(context, row),
      ),
    );
  }
}
