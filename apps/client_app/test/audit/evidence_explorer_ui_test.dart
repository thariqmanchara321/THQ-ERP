import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client_app/features/audit_intelligence/audit_intelligence_screen.dart';
import 'package:client_app/features/audit_intelligence/audit_intelligence_service.dart';
import 'package:client_app/features/audit_intelligence/models/audit_evidence_models.dart';
import 'package:client_app/models/client_session.dart';

const _testSession = ClientSession(
  business: ClientBusiness(
    id: 'test_tenant',
    membershipId: 'mem_1',
    name: 'THQ Test Enterprise',
    slug: 'thq-test',
    businessType: null,
    status: 'active',
  ),
  modules: [],
  roles: {'owner'},
  permissions: {'audit_center.view', 'audit_history.view_sensitive', 'audit_center.export'},
  currencyCode: 'INR',
  timezone: 'UTC',
  locale: 'en',
  canViewAllLocations: true,
);

class FakeAuditExplorerService extends AuditIntelligenceService {
  String? queriedSearch;
  int? queriedOffset;
  String? queriedRecordId;
  String? queriedRelatedField;

  @override
  Future<List<AuditCatalogItem>> evidenceCatalog({
    required String tenantId,
    String? locationId,
  }) async {
    return const [
      AuditCatalogItem(
        key: 'sales',
        label: 'Sales invoices',
        group: 'Sales',
        entity: 'sale',
        dateColumn: 'sale_date',
        dateType: 'date',
        isMaster: false,
      ),
      AuditCatalogItem(
        key: 'customers',
        label: 'Customers',
        group: 'Customers',
        entity: 'customer',
        dateColumn: 'created_at',
        dateType: 'timestamp with time zone',
        isMaster: true,
      ),
      AuditCatalogItem(
        key: 'sale_items',
        label: 'Sale items',
        group: 'Sales',
        entity: 'sale_item',
        dateColumn: 'created_at',
        dateType: 'timestamp with time zone',
        isMaster: false,
      ),
    ];
  }

  @override
  Future<AuditEvidencePage> evidence({
    required String tenantId,
    required String dataset,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async {
    queriedSearch = query;
    queriedOffset = offset;

    if (query == 'NOT_FOUND') {
      return AuditEvidencePage(
        dataset: 'Sales invoices',
        rows: const [],
        totalRows: 0,
      );
    }

    return AuditEvidencePage(
      dataset: 'Sales invoices',
      totalRows: 1,
      periodBasis: 'Selected period, using sale_date',
      sensitiveValuesVisible: true,
      rows: const [
        AuditEvidenceRecord(
          id: 'sale-uuid-123',
          dataset: 'sales',
          reference: 'SAL-000049',
          date: '2026-10-03',
          status: 'posted',
          party: 'Apex Logistics',
          amount: 83.00,
          quantity: 1,
          location: 'BFLY01',
          actor: 'sadik',
          journalCount: 1,
          record: {
            'id': 'sale-uuid-123',
            'sale_number': 'SAL-000049',
            'grand_total': 83,
            'status': 'posted',
          },
        ),
      ],
    );
  }

  @override
  Future<AuditEvidenceDetail> evidenceDetail({
    required String tenantId,
    required String dataset,
    required String recordId,
    String? locationId,
  }) async {
    queriedRecordId = recordId;
    return const AuditEvidenceDetail(
      dataset: 'Sales invoices',
      sensitiveValuesVisible: true,
      record: {
        'id': 'sale-uuid-123',
        'sale_number': 'SAL-000049',
        'grand_total': 83,
        'taxable_total': 70,
        'tax_total': 13,
      },
      events: [
        AuditCapturedEvent(
          dataset: 'transaction_story_events_v600',
          label: 'sale_created',
          recordId: 'ev-1',
          date: '2026-10-03T10:00:00Z',
          actor: 'sadik',
          quality: 'Recorded event',
        ),
      ],
      journals: [
        AuditLinkedJournal(
          id: 'jrn-1',
          entryNumber: 'JRN-00000250',
          date: '2026-10-03',
          status: 'posted',
          sourceType: 'sale',
        ),
      ],
      links: [
        AuditRecordLink(
          dataset: 'sale_items',
          label: 'Sale items',
          relation: 'Related records',
          matchKey: 'sale_id',
          matchValue: 'sale-uuid-123',
          count: 1,
        ),
      ],
      warnings: ['Historical transaction verified against posted ledgers.'],
    );
  }

  @override
  Future<AuditEvidencePage> relatedEvidence({
    required String tenantId,
    required String dataset,
    required String matchField,
    required String matchValue,
    String? locationId,
    int offset = 0,
    int limit = 50,
  }) async {
    queriedRelatedField = matchField;
    return const AuditEvidencePage(
      dataset: 'Sale items',
      totalRows: 1,
      rows: [
        AuditEvidenceRecord(
          id: 'item-uuid-1',
          dataset: 'sale_items',
          reference: 'Sale items',
          status: 'Recorded',
          party: '2 Pin Connector',
          amount: 83.00,
          quantity: 1,
          record: {
            'id': 'item-uuid-1',
            'product_name': '2 Pin Connector',
            'quantity': 1,
          },
        ),
      ],
    );
  }

  @override
  Future<Map<String, dynamic>> workspace({
    required String tenantId,
    required String view,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String query = '',
    String severity = '',
    String status = '',
    String sort = 'date',
    bool descending = true,
    int offset = 0,
    String sourceType = '',
  }) async {
    return {
      'rows': [],
      'total_rows': 0,
      'summary': {},
      'checks': {},
    };
  }
}

Widget testApp(AuditIntelligenceService service) {
  return MaterialApp(
    home: Scaffold(
      body: AuditIntelligenceScreen(
        session: _testSession,
        service: service,
      ),
    ),
  );
}

void main() {
  testWidgets('Selecting Evidence Explorer loads dynamic catalogue and records', (tester) async {
    final service = FakeAuditExplorerService();
    await tester.pumpWidget(testApp(service));
    await tester.pumpAndSettle();

    // Verify Audit section dropdown exists and select Evidence Explorer
    expect(find.text('Audit section'), findsOneWidget);
    await tester.tap(find.text('Findings'));
    await tester.pumpAndSettle();

    expect(find.text('Evidence explorer'), findsWidgets);
    await tester.tap(find.text('Evidence explorer').last);
    await tester.pumpAndSettle();

    // Verify Evidence Explorer view loaded with Business Area and Dataset
    expect(find.text('Business Area'), findsOneWidget);
    expect(find.text('Evidence Dataset'), findsOneWidget);
    expect(find.text('Sales (2)'), findsOneWidget);
    expect(find.text('Sales invoices'), findsOneWidget);

    // Verify record table displayed SAL-000049
    expect(find.text('SAL-000049'), findsOneWidget);
    expect(find.text('Apex Logistics'), findsOneWidget);
    expect(find.text('Posted'), findsOneWidget);

    // Tap on the record to open Evidence Detail dialog
    await tester.tap(find.text('SAL-000049'));
    await tester.pumpAndSettle();

    // Verify Detail dialog contents
    expect(find.text('Evidence Detail · sale-uuid-123'), findsOneWidget);
    expect(find.text('Authorized Sensitive View'), findsOneWidget);
    expect(find.text('Historical transaction verified against posted ledgers.'), findsOneWidget);
    expect(find.text('Captured Audit History'), findsOneWidget);
    expect(find.text('Sale created'), findsOneWidget);
    expect(find.text('Recorded event'), findsOneWidget);
    expect(find.text('JRN-00000250'), findsOneWidget);

    // Scroll until related child link is visible
    final linkFinder = find.text('Sale items (1)');
    await tester.scrollUntilVisible(
      linkFinder,
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(linkFinder, findsOneWidget);

    // Tap on the related child link 'Sale items (1)'
    await tester.tap(linkFinder);
    await tester.pumpAndSettle();

    // Verify Related records modal opens
    expect(find.text('Related Records · Sale items'), findsOneWidget);
    expect(find.text('Matching sale_id = sale-uuid-123'), findsOneWidget);
    expect(find.textContaining('2 Pin Connector'), findsOneWidget);
    expect(service.queriedRelatedField, 'sale_id');
  });

  testWidgets('Evidence Explorer search triggers debounced query', (tester) async {
    final service = FakeAuditExplorerService();
    await tester.pumpWidget(testApp(service));
    await tester.pumpAndSettle();

    // Switch to Evidence explorer
    await tester.tap(find.text('Findings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Evidence explorer').last);
    await tester.pumpAndSettle();

    // Enter search term
    await tester.enterText(find.byType(TextField).first, 'Apex');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(service.queriedSearch, 'Apex');
  });

  testWidgets('Empty evidence results render helpful guidance', (tester) async {
    final service = FakeAuditExplorerService();
    await tester.pumpWidget(testApp(service));
    await tester.pumpAndSettle();

    // Switch to Evidence explorer
    await tester.tap(find.text('Findings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Evidence explorer').last);
    await tester.pumpAndSettle();

    // Search for NOT_FOUND
    await tester.enterText(find.byType(TextField).first, 'NOT_FOUND');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('No evidence records found for Sales invoices.'), findsOneWidget);
    expect(find.text('Try selecting a wider date range or clearing your search filter.'), findsOneWidget);
  });
}
