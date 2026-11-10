import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';
import '../services/accounting_workspace_service.dart';
import '../services/location_scope_service.dart';
import 'accounting_controls_screen.dart';
import 'daily_accounts_report_view.dart';
import 'sale_detail_screen.dart';
import 'purchase_detail_screen.dart';
import '../features/audit_intelligence/audit_intelligence_service.dart';
import '../features/audit_intelligence/transaction_story_dialog.dart';

enum AccountingWorkspaceTab {
  workspace,
  dailyAccounts,
  controls,
}

class AccountingScreen extends StatefulWidget {
  final ClientSession session;
  final AccountingWorkspaceTab initialTab;

  const AccountingScreen({
    super.key,
    required this.session,
    this.initialTab = AccountingWorkspaceTab.workspace,
  });

  @override
  State<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends State<AccountingScreen> {
  late AccountingWorkspaceTab _currentTab;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
  }

  Future<void> _source(BuildContext context, Map<String, dynamic> row) async {
    final id = row['document_id']?.toString();
    final type = row['document_type'];
    if (id == null) return;
    Widget? screen;
    if (type == 'sale') {
      screen = SaleDetailScreen(session: widget.session, saleId: id);
    }
    if (type == 'purchase') {
      screen = PurchaseDetailScreen(session: widget.session, purchaseId: id);
    }
    if (screen != null) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen!));
    } else if (type == 'purchase_invoice_v484') {
      final response = await Supabase.instance.client.rpc(
        'purchase_invoice_detail_v484',
        params: {
          'p_tenant_id': widget.session.business.id,
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ValueListenableBuilder<String?>(
      valueListenable: LocationScopeService.selectedLocationId,
      builder: (context, location, _) {
        final effective = LocationScopeService.currentForRead(widget.session);
        final service = AccountingWorkspaceService(
          widget.session.business.id,
          effective,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Navigation Tabs
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Row(
                children: [
                  SegmentedButton<AccountingWorkspaceTab>(
                    segments: const [
                      ButtonSegment(
                        value: AccountingWorkspaceTab.workspace,
                        label: Text('Financial Workspace'),
                        icon: Icon(Icons.account_balance, size: 15),
                      ),
                      ButtonSegment(
                        value: AccountingWorkspaceTab.dailyAccounts,
                        label: Text('Daily Accounts Report'),
                        icon: Icon(Icons.today, size: 15),
                      ),
                      ButtonSegment(
                        value: AccountingWorkspaceTab.controls,
                        label: Text('Accounting Controls'),
                        icon: Icon(Icons.verified_user_outlined, size: 15),
                      ),
                    ],
                    selected: {_currentTab},
                    onSelectionChanged: (set) => setState(() => _currentTab = set.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),

            // Tab View Body
            Expanded(
              child: switch (_currentTab) {
                AccountingWorkspaceTab.workspace => ThqAccountingWorkspace(
                    businessId: widget.session.business.id,
                    scopeKey: effective ?? 'permitted',
                    scopeLabel: LocationScopeService.scopeLabel(widget.session),
                    currency: widget.session.currencyCode,
                    load: service.load,
                    export: (query, format) => service.export(
                      query,
                      format,
                      widget.session.business.name,
                      widget.session.currencyCode,
                    ),
                    openSource: (row) => _source(context, row),
                    openHistory: (row) => showTransactionStoryDialog(
                      context: context,
                      service: AuditIntelligenceService(),
                      tenantId: widget.session.business.id,
                      entityType: row['journal_id'] != null
                          ? 'journal_entry'
                          : row['source_type'].toString(),
                      entityId: (row['journal_id'] ?? row['source_id']).toString(),
                      session: widget.session,
                      locationId: effective,
                    ),
                    openControls: () => setState(() => _currentTab = AccountingWorkspaceTab.controls),
                  ),
                AccountingWorkspaceTab.dailyAccounts => DailyDetailedAccountsView(
                    session: widget.session,
                  ),
                AccountingWorkspaceTab.controls => AccountingControlsScreen(
                    session: widget.session,
                  ),
              },
            ),
          ],
        );
      },
    );
  }
}
