import 'dart:async';
import 'dart:convert';

import 'package:client_app/models/client_session.dart';
import 'package:client_app/models/inventory_report.dart';
import 'package:client_app/models/report_document.dart';
import 'package:client_app/screens/inventory_reports_screen.dart';
import 'package:client_app/services/inventory_report_service.dart';
import 'package:client_app/services/location_scope_service.dart';
import 'package:client_app/services/report_file_builder.dart';
import 'package:client_app/widgets/inventory_report_table.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ClientSession session({bool reports = true, bool owner = true}) =>
    ClientSession(
      business: const ClientBusiness(
        id: 'tenant',
        membershipId: 'member',
        name: 'THQ Material Yard',
        slug: 'yard',
        businessType: 'material_yard',
        status: 'active',
      ),
      modules: [
        const ClientModule(
          key: 'inventory',
          name: 'Inventory',
          description: '',
          category: 'Stock',
          sortOrder: 1,
        ),
        if (reports)
          const ClientModule(
            key: 'reports',
            name: 'Reports',
            description: '',
            category: 'Reports',
            sortOrder: 2,
          ),
      ],
      roles: owner ? {'owner'} : {},
      permissions: {},
      currencyCode: 'INR',
      timezone: 'Asia/Kolkata',
      locale: 'en_IN',
      canViewAllLocations: true,
      locations: const [
        ClientLocationAccess(
          id: 'yard',
          code: 'YARD',
          name: 'Material Yard',
          type: 'store',
          trackingCode: null,
          accessLevel: 'manage',
        ),
      ],
    );

Map<String, dynamic> fixture({
  String sku = 'M-SAND',
  int count = 1,
  int offset = 0,
  int? total,
}) => {
  'definition': {
    'key': 'stock_snapshot',
    'title': 'Stock overview',
    'category': 'Stock',
    'description': 'Current physical and available stock.',
    'basis': 'current',
    'columns': [
      {'key': 'sku', 'label': 'SKU', 'type': 'text', 'width': 140},
      {'key': 'product_name', 'label': 'Product', 'type': 'text', 'width': 240},
      {
        'key': 'quantity',
        'label': 'Physical stock',
        'type': 'number',
        'width': 150,
      },
      {'key': 'unit_code', 'label': 'Unit', 'type': 'text', 'width': 90},
    ],
  },
  'columns': [
    {'key': 'sku', 'label': 'SKU', 'type': 'text', 'width': 140},
    {'key': 'product_name', 'label': 'Product', 'type': 'text', 'width': 240},
    {
      'key': 'quantity',
      'label': 'Physical stock',
      'type': 'number',
      'width': 150,
    },
    {'key': 'unit_code', 'label': 'Unit', 'type': 'text', 'width': 90},
  ],
  'rows': [
    for (var i = 0; i < count; i++)
      {
        'id': '12345678-1234-1234-1234-123456789012',
        'variant_id': 'variant',
        'sku': count == 1 ? sku : 'SAND-${offset + i}',
        'product_name': 'M Sand',
        'quantity': i + 10.25,
        'unit_code': 'CFT',
        'reference_number': 'GRN-0123',
        'evidence': {
          'created_by': '12345678-1234-1234-1234-123456789012',
          'notes': 'Saved stock note',
        },
      },
  ],
  'context': {
    'company': 'THQ Material Yard',
    'currency': 'INR',
    'location': 'All authorized stores',
    'from': '2026-10-01',
    'to': '2026-10-05',
    'quantity_basis': 'Quantities grouped by base unit.',
    'stock_basis': 'Posted store balances.',
    'lookback_days': 30,
    'expiry_days': 30,
  },
  'summary': [
    {
      'key': 'records',
      'label': 'Matching records',
      'value': total ?? count,
      'type': 'number',
    },
  ],
  'unit_totals': [
    {'unit_code': 'CFT', 'quantity': 10.25, 'available': 8.25},
    {'unit_code': 'NOS', 'quantity': 4},
  ],
  'total_rows': total ?? count,
  'offset': offset,
  'complete': offset == 0 && (total ?? count) == count,
};

class FakeInventoryReports extends InventoryReportService {
  final requests = <InventoryReportRequest>[];
  int catalogs = 0;
  Future<InventoryReportResult> Function(InventoryReportRequest)? handler;
  @override
  Future<List<ReportDefinition>> catalog(String tenantId) async {
    catalogs++;
    return [ReportDefinition.fromMap(reportMap(fixture()['definition']))];
  }

  @override
  Future<InventoryReportResult> run(InventoryReportRequest request) async {
    requests.add(request);
    return handler == null
        ? InventoryReportResult(fixture())
        : handler!(request);
  }
}

Future<void> open(
  WidgetTester t,
  FakeInventoryReports service,
  Size size, {
  double scale = 1,
  ClientSession? access,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  LocationScopeService.selectedLocationId.value = null;
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: InventoryReportsScreen(
          session: access ?? session(),
          service: service,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  for (final size in [
    const Size(1366, 768),
    const Size(640, 480),
    const Size(320, 700),
  ]) {
    testWidgets('stock workspace and row details fit $size', (t) async {
      await open(t, FakeInventoryReports(), size);
      expect(t.takeException(), isNull);
      expect(find.text('M-SAND'), findsOneWidget);
      await t.tap(find.text('M-SAND'));
      await t.pumpAndSettle();
      expect(find.text('GRN-0123'), findsOneWidget);
      expect(find.textContaining('12345678-1234'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('the compact desktop gives most workspace height to the table', (
    t,
  ) async {
    await open(t, FakeInventoryReports(), const Size(1030, 650));
    final table = t.getRect(find.byType(InventoryReportTable));
    expect(table.height, greaterThan(650 * .65));
    expect(find.text('Inventory Reports'), findsNothing);
    expect(t.takeException(), isNull);
    await t.tap(find.byTooltip('Hide totals · more table space'));
    await t.pumpAndSettle();
    expect(
      t.getRect(find.byType(InventoryReportTable)).height,
      greaterThan(table.height),
    );
    expect(find.text('M-SAND'), findsOneWidget);
  });
  testWidgets('large text remains usable in a narrow window', (t) async {
    await open(t, FakeInventoryReports(), const Size(360, 800), scale: 1.5);
    expect(t.takeException(), isNull);
  });
  testWidgets('missing module or permissions prevents server requests', (
    t,
  ) async {
    final service = FakeInventoryReports();
    await open(
      t,
      service,
      const Size(1366, 768),
      access: session(reports: false),
    );
    expect(service.catalogs, 0);
    expect(service.requests, isEmpty);
    expect(
      find.text('Inventory and Reports view access is required.'),
      findsOneWidget,
    );
    expect(canOpenInventoryReports(session(owner: false)), isFalse);
  });
  testWidgets(
    'stale searches cannot replace the latest report or enable export',
    (t) async {
      final service = FakeInventoryReports();
      await open(t, service, const Size(1366, 768));
      final first = Completer<InventoryReportResult>(),
          latest = Completer<InventoryReportResult>();
      service.handler = (r) =>
          r.query == 'first' ? first.future : latest.future;
      final search = find.byType(TextField).first;
      await t.enterText(search, 'first');
      await t.pump(const Duration(milliseconds: 400));
      expect(
        t
            .widget<PopupMenuButton<String>>(
              find.byType(PopupMenuButton<String>),
            )
            .enabled,
        isFalse,
      );
      await t.enterText(search, 'latest');
      await t.pump(const Duration(milliseconds: 400));
      latest.complete(InventoryReportResult(fixture(sku: 'LATEST')));
      await t.pumpAndSettle();
      first.complete(InventoryReportResult(fixture(sku: 'OLD')));
      await t.pumpAndSettle();
      expect(find.text('LATEST'), findsOneWidget);
      expect(find.text('OLD'), findsNothing);
    },
  );
  testWidgets('shared store scope reloads and listener is removed on close', (
    t,
  ) async {
    final service = FakeInventoryReports();
    await open(t, service, const Size(1366, 768));
    LocationScopeService.selectedLocationId.value = 'yard';
    await t.pumpAndSettle();
    expect(service.requests.last.locationId, 'yard');
    await t.pumpWidget(const SizedBox());
    LocationScopeService.selectedLocationId.value = null;
    expect(t.takeException(), isNull);
  });
  testWidgets('sorting and pagination are server requests', (t) async {
    final service = FakeInventoryReports();
    service.handler = (r) async =>
        InventoryReportResult(fixture(count: 50, offset: r.offset, total: 125));
    await open(t, service, const Size(1366, 768));
    await t.tap(find.byKey(const ValueKey('inventory-header-product_name')));
    await t.pumpAndSettle();
    expect(service.requests.last.sortKey, 'product_name');
    expect(service.requests.last.sortDescending, isFalse);
    await t.tap(find.byKey(const ValueKey('inventory-header-product_name')));
    await t.pumpAndSettle();
    expect(service.requests.last.sortDescending, isTrue);
    await t.tap(find.byTooltip('Next page'));
    await t.pumpAndSettle();
    expect(service.requests.last.offset, 50);
    expect(find.text('51–100 of 125 records'), findsOneWidget);
  });
  test('full export keeps filters and ordering while resetting pagination', () {
    final r = InventoryReportRequest(
      tenantId: 'tenant',
      key: 'movements',
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 10, 5),
      locationId: 'yard',
      query: 'sand',
      offset: 100,
      limit: 50,
      days: 90,
      expiryDays: 60,
      sortKey: 'created_at',
      sortDescending: true,
      filters: {'unit_code': 'CFT'},
    ).forExport();
    final p = reportMap(r.parameters['p_request']);
    expect(p['limit'], 0);
    expect(p['offset'], 0);
    expect(p['location_id'], 'yard');
    expect(p['sort_key'], 'created_at');
    expect(p['sort_desc'], true);
    expect(p['query'], 'sand');
    expect(p['filters'], {'unit_code': 'CFT'});
    expect(p['days'], 90);
    expect(p['expiry_days'], 60);
    expect(p['from'], '2026-09-01');
    expect(p['to'], '2026-10-05');
  });
  test(
    'complete export includes every row, readable references and separate unit totals',
    () {
      final report = InventoryReportResult(fixture(count: 5007)).presentation;
      final data =
          jsonDecode(utf8.decode(ReportFileBuilder.json(report))) as Map;
      expect((data['rows'] as List).length, 5007);
      expect(jsonEncode(data), isNot(contains('12345678-1234')));
      expect(data['rows'][0]['reference_number'], 'GRN-0123');
      expect(report.summary.any((s) => s['label'] == 'CFT quantity'), isTrue);
      expect(report.summary.any((s) => s['label'] == 'NOS quantity'), isTrue);
      final workbook = Excel.decodeBytes(ReportFileBuilder.excel(report));
      final rows = workbook['Report'].rows;
      final header = rows.indexWhere(
        (r) => r.any((c) => c?.value.toString() == 'SKU'),
      );
      expect(rows.length - header - 1, 5007);
      expect(rows[header + 1][2]?.value, isA<DoubleCellValue>());
    },
  );
  test('inconsistent and incomplete reports are rejected before export', () {
    final invalid = fixture(count: 1, total: 100)..['complete'] = true;
    expect(() => InventoryReportResult(invalid), throwsStateError);
    final partial = InventoryReportResult(
      fixture(count: 50, total: 100),
    ).presentation;
    expect(() => ReportFileBuilder.excel(partial), throwsStateError);
    expect(() => ReportFileBuilder.json(partial), throwsStateError);
  });
}
