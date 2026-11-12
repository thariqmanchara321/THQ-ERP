import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_core/erp_core.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  group('ThqCatalogueComparisonView Widget Tests', () {
    testWidgets('renders candidate header, conflict banner, and protected fields', (tester) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final candidate = ExternalProductCandidate(
        providerId: 'gs1_registry',
        sourceName: 'Verified by GS1',
        barcode: '8901030383748',
        format: SmartBarcodeFormat.ean13,
        productName: 'Bru Gold Instant Coffee 100g',
        brand: 'Bru',
        manufacturer: 'Hindustan Unilever Limited',
        category: 'Instant Coffee',
        description: 'Pure granulated coffee',
        specifications: const {
          'Country of Origin': 'India',
          'Net Content': '100g',
        },
        matchConfidence: 1.0,
        isGs1Verified: true,
        fetchedAt: DateTime(2026, 11, 12),
      );

      final existingProduct = {
        'id': 'prod-001',
        'name': 'Bru Coffee 100g Jar', // Conflict
        'barcode': '8901030383748',
        'brand': 'Bru',
        'category': null, // Non-conflicting, empty in THQ
        'cost_price': 150.0,
        'selling_price': 200.0,
        'quantity': 50,
      };

      final comparison = CatalogueComparison.build(
        existingProduct: existingProduct,
        candidate: candidate,
      );

      Map<String, String?>? enrichedPayload;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThqCatalogueComparisonView(
              comparison: comparison,
              onApplyEnrichment: (payload) {
                enrichedPayload = payload;
              },
            ),
          ),
        ),
      );

      // Verify header details
      expect(find.text('Bru Gold Instant Coffee 100g'), findsWidgets);
      expect(find.textContaining('8901030383748'), findsWidgets);
      expect(find.text('Verified by GS1'), findsOneWidget);
      expect(find.text('100% Match'), findsOneWidget);

      // Verify conflict banner
      expect(find.textContaining('conflicting field(s) detected'), findsOneWidget);

      // Verify protected invariant message
      expect(find.textContaining('Protected Accounting Invariant'), findsOneWidget);

      // Verify protected field rows show "PROTECTED" badges and lock icons
      expect(find.text('PROTECTED'), findsWidgets);
      expect(find.byIcon(Icons.lock_outline), findsWidgets);

      // Verify conflict badge for product name
      expect(find.text('CONFLICT'), findsOneWidget);

      // Verify specifications
      expect(find.text('Country of Origin: India'), findsOneWidget);

      // Verify clicking "Clear All"
      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();
      expect(comparison.acceptedFieldsCount, equals(0));

      // Verify clicking "Accept Non-Conflicting"
      await tester.tap(find.text('Accept Non-Conflicting'));
      await tester.pumpAndSettle();

      // Category and manufacturer should be accepted (were null in THQ), productName should still NOT be accepted (was a conflict)
      expect(comparison.isFieldAccepted('category'), isTrue);
      expect(comparison.isFieldAccepted('manufacturer'), isTrue);
      expect(comparison.isFieldAccepted('productName'), isFalse);

      // Verify apply button is enabled and taps cleanly
      final acceptedCount = comparison.acceptedFieldsCount;
      final applyButton = find.widgetWithText(ThqPrimaryButton, 'Enrich Product ($acceptedCount Selected)');
      expect(applyButton, findsOneWidget);
      await tester.ensureVisible(applyButton);
      await tester.tap(applyButton);
      await tester.pumpAndSettle();

      expect(enrichedPayload, isNotNull);
      expect(enrichedPayload!['category'], equals('Instant Coffee'));
      expect(enrichedPayload!.containsKey('costPrice'), isFalse);
      expect(enrichedPayload!.containsKey('sellingPrice'), isFalse);
    });

    testWidgets('allows manual approval of conflicting field', (tester) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final candidate = ExternalProductCandidate(
        providerId: 'open_product_facts',
        sourceName: 'Open Food Facts',
        barcode: '8901234567890',
        format: SmartBarcodeFormat.ean13,
        productName: 'UltraTech Super Cement 50kg Bag',
        brand: 'UltraTech',
        matchConfidence: 0.9,
        isGs1Verified: false,
        fetchedAt: DateTime(2026, 11, 12),
      );

      final existingProduct = {
        'id': 'prod-002',
        'name': 'UltraTech Cement', // Conflict
        'barcode': '8901234567890',
      };

      final comparison = CatalogueComparison.build(
        existingProduct: existingProduct,
        candidate: candidate,
      );

      Map<String, String?>? enrichedPayload;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThqCatalogueComparisonView(
              comparison: comparison,
              onApplyEnrichment: (payload) {
                enrichedPayload = payload;
              },
            ),
          ),
        ),
      );

      // Tap Clear All first
      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();
      expect(comparison.acceptedFieldsCount, equals(0));

      // Tap on the checkbox for the conflicting product name
      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsWidgets);

      // Tap first non-protected checkbox (productName)
      await tester.tap(checkboxes.first);
      await tester.pumpAndSettle();

      expect(comparison.isFieldAccepted('productName'), isTrue);

      final applyButton = find.widgetWithText(ThqPrimaryButton, 'Enrich Product (1 Selected)');
      expect(applyButton, findsOneWidget);
      await tester.ensureVisible(applyButton);
      await tester.tap(applyButton);
      await tester.pumpAndSettle();

      expect(enrichedPayload, isNotNull);
      expect(enrichedPayload!['productName'], equals('UltraTech Super Cement 50kg Bag'));
    });
  });
}
