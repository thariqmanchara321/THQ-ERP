import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';
import '../services/accounting_workspace_service.dart';
import '../services/location_scope_service.dart';
import 'accounting_controls_screen.dart';
import 'sale_detail_screen.dart';
import 'purchase_detail_screen.dart';

class AccountingScreen extends StatelessWidget {
  final ClientSession session;
  const AccountingScreen({super.key, required this.session});
  Future<void> _source(BuildContext context, Map<String, dynamic> row) async {
    final id = row['document_id']?.toString();
    final type = row['document_type'];
    if (id == null) return;
    Widget? screen;
    if (type == 'sale') {
      screen = SaleDetailScreen(session: session, saleId: id);
    }
    if (type == 'purchase') {
      screen = PurchaseDetailScreen(session: session, purchaseId: id);
    }
    if (screen != null) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => screen!));
    } else if (type == 'purchase_invoice_v484') {
      final response = await Supabase.instance.client.rpc(
        'purchase_invoice_detail_v484',
        params: {
          'p_tenant_id': session.business.id,
          'p_purchase_invoice_id': id,
        },
      );
      if (!context.mounted) return;
      final data = accountingMap(response);
      final invoice = accountingMap(data['invoice']);
      final items = accountingMaps(data['items']);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Supplier bill ${row['reference'] ?? ''}'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final key in [
                    'supplier_invoice_number',
                    'invoice_date',
                    'due_date',
                    'status',
                    'subtotal',
                    'additional_charges',
                    'round_off',
                    'grand_total',
                    'paid_amount',
                    'outstanding_amount',
                    'notes',
                  ])
                    if (invoice[key] != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${key.replaceAll('_', ' ')}: ${invoice[key]}',
                        ),
                      ),
                  for (final item in items)
                    ListTile(
                      title: Text(
                        '${item['product_name'] ?? item['description'] ?? 'Item'}',
                      ),
                      subtitle: Text(
                        'Quantity ${item['quantity'] ?? ''} · Rate ${item['unit_price'] ?? item['rate'] ?? ''} · Total ${item['line_total'] ?? item['total'] ?? ''}',
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: LocationScopeService.selectedLocationId,
    builder: (context, location, _) {
      final effective = LocationScopeService.currentForRead(session);
      final service = AccountingWorkspaceService(
        session.business.id,
        effective,
      );
      return ThqAccountingWorkspace(
        businessId: session.business.id,
        scopeKey: effective ?? 'permitted',
        scopeLabel: LocationScopeService.scopeLabel(session),
        currency: session.currencyCode,
        load: service.load,
        export: (query, format) => service.export(
          query,
          format,
          session.business.name,
          session.currencyCode,
        ),
        openSource: (row) => _source(context, row),
        openControls: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Accounting controls')),
              body: AccountingControlsScreen(session: session),
            ),
          ),
        ),
      );
    },
  );
}
