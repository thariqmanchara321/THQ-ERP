import 'dart:convert';
import 'dart:io';

import 'package:client_app/models/report_document.dart';
import 'package:client_app/widgets/inventory_report_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final definitions =
    (jsonDecode(
              File(
                'test/fixtures/inventory_report_definitions_v635.json',
              ).readAsStringSync(),
            )
            as List)
        .map(reportMap)
        .toList();

ReportDocument document(Map<String, dynamic> definition) =>
    ReportDocument.fromMap({
      'definition': definition,
      'columns': definition['columns'],
      'rows': [
        {
          for (final column in reportMaps(definition['columns']))
            column['key'].toString(): switch (column['type']) {
              'number' => 10.25,
              'money' => 125000.50,
              'date' => '2026-10-05',
              'datetime' => '2026-10-05T10:42:00Z',
              _ => column['label'].toString(),
            },
          'product_name': 'M Sand — premium grade',
          'sku': 'M-SAND',
          'location_name': 'Main Store',
          'unit_code': 'CFT',
          'status': 'healthy',
          'activity_status': 'non_moving',
          'tracking_mode': 'batch',
          'batch_number': 'BATCH-2026-001',
          'serial_number': 'SER-2026-001',
          'reference_number': 'GRN-0123',
          'transfer_number': 'TRF-001',
          'count_number': 'COUNT-001',
          'sale_number': 'INV-001',
          'customer_name': 'Walk-in customer',
          'event_type': 'tracking_opening',
          'from_location': 'Main Store',
          'to_location': 'Yard Store',
          'from_mode': 'quantity',
          'to_mode': 'batch',
          'trace_only': true,
          'reason': 'Enable batch tracking for stock already on hand.',
          'id': '12345678-1234-1234-1234-123456789012',
          'note': 'Saved evidence remains available in details and exports.',
        },
      ],
      'context': {'currency': 'INR'},
      'total_rows': 1,
      'offset': 0,
      'complete': true,
    });

Future<void> open(
  WidgetTester tester,
  ReportDocument report,
  Size size,
  ScrollController controller, {
  double scale = 1,
  bool showStore = true,
  ValueChanged<Map<String, dynamic>>? onOpen,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: InventoryReportTable(
            report: report,
            controller: controller,
            showStore: showStore,
            onSort: (_) {},
            onOpen: onOpen ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final definition in definitions) {
    testWidgets(
      '${definition['title']} keeps product and critical fields in bounds without sideways scrolling',
      (tester) async {
        final report = document(definition);
        final controller = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final size in [
          const Size(1366, 768),
          const Size(1030, 650),
          const Size(760, 480),
          const Size(360, 700),
        ]) {
          await open(tester, report, size, controller);
          expect(
            tester.takeException(),
            isNull,
            reason: '${definition['key']} at $size',
          );
          expect(find.text('M Sand — premium grade'), findsOneWidget);
          expect(find.textContaining('M-SAND'), findsOneWidget);
          expect(find.textContaining('12345678-1234'), findsNothing);
          for (final scrollable in tester.widgetList<Scrollable>(
            find.byType(Scrollable),
          )) {
            expect(
              scrollable.axisDirection,
              anyOf(AxisDirection.down, AxisDirection.up),
            );
          }
          final record = tester.getRect(
            find.byKey(const ValueKey('inventory-record-0')),
          );
          expect(record.left, greaterThanOrEqualTo(0));
          expect(record.right, lessThanOrEqualTo(size.width + .01));
          for (final header in tester.widgetList<SizedBox>(
            find.byWidgetPredicate(
              (w) =>
                  w is SizedBox &&
                  w.key.toString().contains('inventory-header-'),
            ),
          )) {
            final field = (header.key as ValueKey<String>).value.replaceFirst(
              'inventory-header-',
              '',
            );
            final h = tester.getRect(find.byKey(header.key!));
            final c = tester.getRect(
              find.byKey(ValueKey('inventory-cell-0-$field')),
            );
            expect(h.left, closeTo(c.left, .01));
            expect(h.width, closeTo(c.width, .01));
            expect(h.right, lessThanOrEqualTo(size.width + .01));
            if (report.columns
                .firstWhere((column) => column.key == field)
                .numeric) {
              final heading = find.descendant(
                of: find.byKey(header.key!),
                matching: find.byType(Text),
              );
              final value = find.descendant(
                of: find.byKey(ValueKey('inventory-cell-0-$field')),
                matching: find.byType(Text),
              );
              expect(tester.widget<Text>(heading).textAlign, TextAlign.right);
              expect(tester.widget<Text>(value).textAlign, TextAlign.right);
              expect(
                tester.getRect(heading).right,
                closeTo(tester.getRect(value).right, .01),
              );
            }
          }
          if (size.width == 360) {
            for (final column in report.columns.where(
              (c) => const {
                'quantity',
                'available',
                'closing_quantity',
                'variance',
                'quantity_in',
                'quantity_out',
                'balance_after',
                'in_transit_quantity',
                'ledger_variance',
                'tracking_variance',
                'suggested_reorder',
              }.contains(c.key),
            )) {
              expect(
                find.text('10.25 CFT'),
                findsWidgets,
                reason: '${column.key} retains its unit',
              );
            }
          }
        }
        await open(
          tester,
          report,
          const Size(360, 800),
          controller,
          scale: 1.5,
        );
        expect(tester.takeException(), isNull, reason: '150% text');
      },
    );
  }

  testWidgets(
    'secondary columns stay out of the list and full row evidence is retained',
    (tester) async {
      final report = document(definitions.first);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? opened;
      await open(
        tester,
        report,
        const Size(1030, 650),
        controller,
        onOpen: (row) => opened = row,
      );
      expect(
        find.byKey(const ValueKey('inventory-header-reserved')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('inventory-header-damaged')),
        findsNothing,
      );
      await tester.tap(find.text('M Sand — premium grade'));
      expect(opened?['reserved'], 10.25);
      expect(opened?['note'], contains('Saved evidence'));
      expect(report.columns.any((c) => c.key == 'reserved'), isTrue);
      expect(report.rows.single['damaged'], 10.25);
    },
  );

  testWidgets('single-store scope reclaims the store column', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(
      tester,
      document(definitions.first),
      const Size(1030, 650),
      controller,
      showStore: false,
    );
    expect(
      find.byKey(const ValueKey('inventory-header-location_name')),
      findsNothing,
    );
    expect(find.text('CFT'), findsOneWidget);
    expect(find.text('M-SAND'), findsOneWidget);
  });

  testWidgets(
    'batch warranties and events keep batch identity when no serial exists',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final key in ['warranties', 'tracking_events']) {
        final report = document(definitions.firstWhere((d) => d['key'] == key));
        report.rows.single['serial_number'] = null;
        await open(tester, report, const Size(1030, 650), controller);
        expect(find.text('BATCH-2026-001'), findsOneWidget);
        if (key == 'tracking_events') {
          expect(find.text('Trace only'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
}
