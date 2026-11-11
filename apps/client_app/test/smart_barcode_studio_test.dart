import 'package:client_app/models/client_session.dart';
import 'package:client_app/models/inventory_product.dart';
import 'package:client_app/screens/smart_inventory/tabs/smart_barcode_studio_tab.dart';
import 'package:client_app/services/label_printing_service.dart';
import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testBusiness = ClientBusiness(
    id: 'tenant-barcode-test',
    membershipId: 'mem-b-1',
    name: 'THQ Megastore',
    slug: 'thq-megastore',
    businessType: 'retail',
    status: 'active',
  );

  const managerSession = ClientSession(
    business: testBusiness,
    userId: 'user-mgr',
    username: 'Manager Dave',
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
    permissions: {'inventory.view', 'inventory.manage'},
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    locale: 'en_IN',
  );

  final List<InventoryProduct> sampleProducts = [
    InventoryProduct(
      productId: 'p-1',
      variantId: 'v-1',
      productName: 'Drill Bit 10mm',
      variantName: 'High Speed Steel',
      itemType: 'product',
      sku: 'SKU-DRL-10',
      barcode: '280000000018',
      unitCode: 'PCS',
      unitName: 'Pieces',
      baseUnitCode: 'PCS',
      baseUnitName: 'Pieces',
      allowFractional: false,
      quantityStep: 1.0,
      saleUnits: const [],
      purchaseUnits: const [],
      identifiers: const [],
      searchCodes: 'SKU-DRL-10 280000000018',
      costPrice: 80.0,
      sellingPrice: 150.0,
      listPrice: 160.0,
      taxRate: 18.0,
      reorderLevel: 10.0,
      stockQuantity: 45.0,
      trackingMode: 'standard',
      trackingRevision: 1,
      trackedStockQuantity: 45.0,
      productStatus: 'active',
      variantStatus: 'active',
      updatedAt: DateTime(2026, 1, 1),
      partNumber: 'DRL-10-HSS',
      brandName: 'Bosch',
      categoryName: 'Hardware',
    ),
    InventoryProduct(
      productId: 'p-2',
      variantId: 'v-2',
      productName: 'Safety Goggles Pro',
      variantName: 'Clear Lens',
      itemType: 'product',
      sku: 'SKU-GGL-01',
      barcode: '', // Missing barcode test
      unitCode: 'PCS',
      unitName: 'Pieces',
      baseUnitCode: 'PCS',
      baseUnitName: 'Pieces',
      allowFractional: false,
      quantityStep: 1.0,
      saleUnits: const [],
      purchaseUnits: const [],
      identifiers: const [],
      searchCodes: 'SKU-GGL-01',
      costPrice: 120.0,
      sellingPrice: 220.0,
      listPrice: 240.0,
      taxRate: 18.0,
      reorderLevel: 5.0,
      stockQuantity: 12.0,
      trackingMode: 'standard',
      trackingRevision: 1,
      trackedStockQuantity: 12.0,
      productStatus: 'active',
      variantStatus: 'active',
      updatedAt: DateTime(2026, 1, 1),
      partNumber: 'GGL-CLR',
      brandName: '3M',
      categoryName: 'Safety',
    ),
  ];

  group('LabelPrintingService Batch Document Tests', () {
    final printingService = LabelPrintingService();

    test('buildPdfDocument creates thermal roll pages for batch items', () {
      final items = [
        const LabelPrintItem(
          productId: 'p-1',
          variantId: 'v-1',
          productName: 'Drill Bit 10mm',
          sku: 'SKU-DRL-10',
          code: '280000000018',
          format: LabelBarcodeFormat.ean13,
          sellingPrice: 150.0,
          copies: 3,
        ),
      ];

      final doc = printingService.buildPdfDocument(
        template: LabelTemplate.standardThermal,
        items: items,
        businessName: 'THQ Megastore',
      );

      // Thermal roll generates 1 page per copy = 3 pages
      expect(doc.document.pdfPageList.pages.length, 3);
    });

    test('buildPdfDocument creates A4 multi-label pages', () {
      final items = [
        const LabelPrintItem(
          productId: 'p-1',
          variantId: 'v-1',
          productName: 'Drill Bit 10mm',
          sku: 'SKU-DRL-10',
          code: '280000000018',
          format: LabelBarcodeFormat.code128,
          sellingPrice: 150.0,
          copies: 25, // Exceeds 24 labels on a single A4 3x8 sheet
        ),
      ];

      final doc = printingService.buildPdfDocument(
        template: LabelTemplate.a4Sheet24,
        items: items,
        businessName: 'THQ Megastore',
      );

      // 25 labels on 24-label sheet = 2 pages
      expect(doc.document.pdfPageList.pages.length, 2);
    });

    test('generatePdfBytes produces non-empty PDF document bytes', () async {
      final items = [
        const LabelPrintItem(
          productId: 'p-1',
          variantId: 'v-1',
          productName: 'Drill Bit 10mm',
          sku: 'SKU-DRL-10',
          code: '280000000018',
          format: LabelBarcodeFormat.code128,
          sellingPrice: 150.0,
          copies: 1,
        ),
      ];

      final bytes = await printingService.generatePdfBytes(
        template: LabelTemplate.standardThermal,
        items: items,
        businessName: 'THQ Megastore',
      );

      expect(bytes.isNotEmpty, isTrue);
      // PDF magic header %PDF
      expect(bytes[0], 0x25); // %
      expect(bytes[1], 0x50); // P
      expect(bytes[2], 0x44); // D
      expect(bytes[3], 0x46); // F
    });
  });

  group('SmartBarcodeStudioTab Widget Tests', () {
    testWidgets('Renders studio interface, presets, and live preview', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartBarcodeStudioTab(
              session: managerSession,
              initialProducts: sampleProducts,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Header & designer
      expect(find.text('Label Designer'), findsOneWidget);
      expect(find.text('Live Preview'), findsOneWidget);
      expect(find.text('Print Labels'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);

      // Catalogue products are rendered
      expect(find.text('Drill Bit 10mm'), findsWidgets);
      expect(find.text('Safety Goggles Pro'), findsOneWidget);

      // Non-destructive operation disclaimer is visible
      expect(
        find.textContaining('Catalogue and printing operation only'),
        findsOneWidget,
      );
    });

    testWidgets('Filter chips filter products by missing barcode and selection', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartBarcodeStudioTab(
              session: managerSession,
              initialProducts: sampleProducts,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Missing Barcode (1)" filter chip
      await tester.tap(find.text('Missing Barcode (1)'));
      await tester.pumpAndSettle();

      // Safety Goggles Pro is missing barcode, so it should be visible in the catalog list
      final catalogList = find.byType(ListView);
      expect(
        find.descendant(of: catalogList, matching: find.text('Safety Goggles Pro')),
        findsOneWidget,
      );
      // Drill Bit 10mm has a barcode, so it should not appear in this filtered catalog list
      expect(
        find.descendant(of: catalogList, matching: find.text('Drill Bit 10mm')),
        findsNothing,
      );

      // Tap "All (2)" filter chip to restore
      await tester.tap(find.text('All (2)'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: catalogList, matching: find.text('Drill Bit 10mm')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: catalogList, matching: find.text('Safety Goggles Pro')),
        findsOneWidget,
      );
    });

    testWidgets('Generate button creates an in-store barcode for product missing one', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartBarcodeStudioTab(
              session: managerSession,
              initialProducts: sampleProducts,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find Generate button for Safety Goggles Pro
      final generateBtn = find.widgetWithText(TextButton, 'Generate');
      expect(generateBtn, findsOneWidget);

      await tester.tap(generateBtn);
      await tester.pump();
      await tester.pumpAndSettle(const Duration(seconds: 4));

      // Generate button is now replaced with the generated barcode
      expect(find.widgetWithText(TextButton, 'Generate'), findsNothing);
    });
  });
}
