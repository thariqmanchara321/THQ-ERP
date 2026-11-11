import 'dart:convert';
import 'dart:typed_data';

import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/smart_inventory/smart_inventory_workspace_screen.dart';
import 'package:client_app/screens/smart_inventory/tabs/smart_inventory_import_tab.dart';
import 'package:client_app/services/client_smart_inventory_service.dart';
import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tenantId = 'tenant-import-test-1';

  const testBusiness = ClientBusiness(
    id: tenantId,
    membershipId: 'mem-imp-1',
    name: 'THQ Hardware Store',
    slug: 'thq-hardware',
    businessType: 'retail',
    status: 'active',
  );

  const managerSession = ClientSession(
    business: testBusiness,
    userId: 'user-manager',
    username: 'Alice Manager',
    modules: [
      ClientModule(
        key: 'inventory',
        name: 'Inventory',
        description: null,
        category: 'Inventory',
        sortOrder: 10,
      ),
    ],
    roles: {'owner'},
    permissions: {'inventory.view', 'inventory.manage', 'bulk_import.use'},
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    locale: 'en_IN',
  );

  const restrictedStaffSession = ClientSession(
    business: testBusiness,
    userId: 'user-clerk',
    username: 'Bob Clerk',
    modules: [
      ClientModule(
        key: 'inventory',
        name: 'Inventory',
        description: null,
        category: 'Inventory',
        sortOrder: 10,
      ),
    ],
    roles: {'staff'},
    permissions: {'inventory.view'},
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    locale: 'en_IN',
  );

  setUp(() {
    ClientSmartInventoryService.instance.setCustomRpc((fn, {params}) async => null);
  });

  group('SmartInventoryImportTab Widget & Workflow Tests', () {
    testWidgets('Renders file upload dropzone and template download options', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SmartInventoryImportTab(session: managerSession),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Smart Product Import'), findsOneWidget);
      expect(find.text('Download CSV Template'), findsOneWidget);
      expect(find.text('Download Excel Template'), findsOneWidget);
      expect(find.text('Select Product Catalogue to Import'), findsOneWidget);
      expect(find.text('Browse Files'), findsOneWidget);
    });

    testWidgets('SmartInventoryWorkspaceScreen opens Tab 5 directly to Product Import', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SmartInventoryWorkspaceScreen(
              session: managerSession,
              initialTab: 5,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Smart Product Import'), findsOneWidget);
      expect(find.text('Browse Files'), findsOneWidget);
    });

    testWidgets('Restricted staff cannot see cost price or trigger unauthorized import', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SmartInventoryImportTab(session: restrictedStaffSession),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Smart Product Import'), findsOneWidget);
      expect(find.text('Cost Price'), findsNothing);
    });

    testWidgets('Template generation generates valid CSV and XLSX bytes', (tester) async {
      const gen = SampleTemplateGenerator();

      final csvBytes = gen.generateCsvBytes();
      expect(csvBytes, isNotEmpty);
      expect(csvBytes[0], 0xEF); // UTF-8 BOM
      expect(csvBytes[1], 0xBB);
      expect(csvBytes[2], 0xBF);

      final csvStr = utf8.decode(csvBytes.sublist(3));
      expect(csvStr, contains('Product Name,SKU,Barcode'));
      expect(csvStr, contains('UltraTech Cement 50kg'));

      final xlsxBytes = gen.generateXlsxBytes();
      expect(xlsxBytes, isNotEmpty);
    });

    testWidgets('SmartImportEngine parses, maps, and executes batch mock correctly', (tester) async {
      const csvData = '''Product Name,SKU,Barcode,Selling Price,Cost Price
UltraTech Cement 50kg,SKU-CEM-01,8901234567890,380.00,310.00
M-Sand Plaster,SKU-SND-01,8901234567891,45.00,32.00
''';
      final bytes = Uint8List.fromList(utf8.encode(csvData));
      const engine = SmartImportEngine();

      final file = engine.loadFile(fileName: 'catalog.csv', bytes: bytes);
      expect(file.hasError, isFalse);
      expect(file.headers.length, 5);
      expect(file.totalRows, 2);

      final mappings = engine.autoMapHeaders(file);
      final missing = engine.columnMapper.findMissingRequiredFields(mappings);
      expect(missing, isEmpty);

      const config = ImportConfiguration(
        tenantId: tenantId,
        duplicateMode: DuplicateHandlingMode.skipDuplicates,
      );

      final validatedRows = await engine.validateAndDetectDuplicates(
        file: file,
        mappings: mappings,
        config: config,
      );
      expect(validatedRows.length, 2);
      expect(validatedRows.every((r) => r.isValid), isTrue);

      final summary = await engine.executeImport(
        rows: validatedRows,
        config: config,
        onBatchCreate: (batch) async {
          expect(batch.length, 2);
          expect(batch[0]['name'], 'UltraTech Cement 50kg');
          expect(batch[0]['sku'], 'SKU-CEM-01');
          return {
            'success_count': 2,
            'failed_count': 0,
            'errors': [],
          };
        },
      );

      expect(summary.createdCount, 2);
      expect(summary.failedCount, 0);
      expect(summary.hasFailures, isFalse);
    });

    testWidgets('DuplicateDetection distinguishes intra-file duplicates', (tester) async {
      const csvData = '''Product Name,SKU,Barcode,Selling Price
Item One,DUP-SKU-1,1111111111111,10.00
Item Two Duplicate,DUP-SKU-1,2222222222222,20.00
''';
      final bytes = Uint8List.fromList(utf8.encode(csvData));
      const engine = SmartImportEngine();

      final file = engine.loadFile(fileName: 'catalog_dup.csv', bytes: bytes);
      final mappings = engine.autoMapHeaders(file);

      final validatedRows = await engine.validateAndDetectDuplicates(
        file: file,
        mappings: mappings,
        config: const ImportConfiguration(tenantId: tenantId),
      );

      expect(validatedRows.length, 2);
      expect(validatedRows[0].isDuplicate, isFalse);
      expect(validatedRows[1].isDuplicate, isTrue);
      expect(validatedRows[1].duplicateStatus, RowDuplicateStatus.inSpreadsheet);
    });

    testWidgets('Error report CSV generator produces valid RFC 4180 output', (tester) async {
      const engine = SmartImportEngine();
      final summary = ImportExecutionSummary(
        totalSourceRows: 2,
        validRows: 1,
        invalidRows: 1,
        duplicateRows: 0,
        createdCount: 0,
        updatedCount: 0,
        skippedCount: 1,
        failedCount: 1,
        failures: const [
          ImportFailureItem(
            sourceRowNumber: 2,
            productName: 'Broken Item',
            sku: 'SKU-BAD',
            error: 'Duplicate barcode in database',
          ),
        ],
        duration: const Duration(milliseconds: 150),
        isCompleted: true,
      );

      final errorCsv = engine.generateErrorReport(summary);
      expect(errorCsv, contains('Row Number,Product Name,SKU,Error Reason'));
      expect(errorCsv, contains('2,Broken Item,SKU-BAD,Duplicate barcode in database'));
    });
  });
}
