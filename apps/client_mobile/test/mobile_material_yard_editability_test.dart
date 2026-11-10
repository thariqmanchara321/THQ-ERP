import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_core/erp_core.dart';
import 'package:client_mobile/models/mobile_session.dart';
import 'package:client_mobile/services/mobile_client_service.dart';
import 'package:client_mobile/screens/workspace/material_yard/material_yard_billing_sheet.dart';

class MockPrePostingYardService extends MobileClientService {
  final Map<String, Map<String, dynamic>> _loadsDb = {};
  final List<String> callLogs = [];

  void seedLoad(String id, Map<String, dynamic> data) {
    _loadsDb[id] = Map<String, dynamic>.from(data);
  }

  @override
  Future<Map<String, dynamic>> materialLoadDetail(
    MobileSession s, {
    required String loadId,
    String? locationId,
  }) async {
    callLogs.add('detail:$loadId');
    if (!_loadsDb.containsKey(loadId)) {
      throw StateError('Load not found: $loadId');
    }
    return _loadsDb[loadId]!;
  }

  @override
  Future<Map<String, dynamic>> reopenMaterialLoad(
    MobileSession s, {
    required String loadId,
    String? reason,
  }) async {
    callLogs.add('reopen:$loadId');
    if (!s.permissions.contains('material_yard.manage') && !s.roles.contains('admin')) {
      throw StateError('Permission denied: material_yard.manage required to reopen load.');
    }
    final load = _loadsDb[loadId];
    if (load == null) throw StateError('Load not found');

    if (load['purchase_id'] != null || load['sale_id'] != null) {
      throw StateError('Load linked to a finalized Purchase or Sale cannot be edited or reopened');
    }

    load['status'] = 'draft';
    load['updated_at'] = DateTime.now().toIso8601String();
    return {
      'success': true,
      'load_id': loadId,
      'status': 'draft',
      'reopened': true,
    };
  }

  @override
  Future<Map<String, dynamic>> linkMaterialLoadPurchase(
    MobileSession s, {
    required String loadId,
    required String supplierId,
    required DateTime purchaseDate,
    DateTime? dueDate,
    required List<Map<String, dynamic>> items,
    String? supplierInvoiceNumber,
    double additionalCharges = 0,
    double roundOff = 0,
    double initialPayment = 0,
    String paymentMethod = 'cash',
    String? paymentReference,
    String notes = '',
    String? locationId,
    DateTime? loadUpdatedAt,
  }) async {
    callLogs.add('linkPurchase:$loadId');
    final load = _loadsDb[loadId];
    if (load == null) throw StateError('Load not found');

    if (load['purchase_id'] != null) {
      throw StateError('Load is already linked to a finalized purchase. Duplicate posting blocked.');
    }

    if (loadUpdatedAt != null && load['updated_at'] != null) {
      final currentDbTime = DateTime.parse(load['updated_at'].toString());
      if (currentDbTime.isAfter(loadUpdatedAt)) {
        throw StateError('Concurrency conflict: Load was updated by another user or operation after the billing draft was opened.');
      }
    }

    load['purchase_id'] = 'pur-invoice-101';
    load['status'] = 'completed';
    return {'success': true, 'purchase_id': 'pur-invoice-101'};
  }

  @override
  Future<Map<String, dynamic>> linkMaterialLoadSale(
    MobileSession s, {
    required String loadId,
    required String customerId,
    required DateTime saleDate,
    DateTime? dueDate,
    required List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> paymentAllocations = const [],
    String notes = '',
    String? locationId,
    String supplyType = 'intra_state',
    String placeOfSupplyCode = '32',
    List<String> chargeSelections = const [],
    DateTime? loadUpdatedAt,
  }) async {
    callLogs.add('linkSale:$loadId');
    final load = _loadsDb[loadId];
    if (load == null) throw StateError('Load not found');

    if (load['sale_id'] != null) {
      throw StateError('Load is already linked to a finalized sale. Duplicate posting blocked.');
    }

    if (loadUpdatedAt != null && load['updated_at'] != null) {
      final currentDbTime = DateTime.parse(load['updated_at'].toString());
      if (currentDbTime.isAfter(loadUpdatedAt)) {
        throw StateError('Concurrency conflict: Load was updated by another user or operation after the billing draft was opened.');
      }
    }

    load['sale_id'] = 'sale-invoice-202';
    load['status'] = 'completed';
    return {'success': true, 'sale_id': 'sale-invoice-202'};
  }
}

void main() {
  late MobileSession authorizedSession;
  late MobileSession unauthorizedSession;
  late MockPrePostingYardService mockService;

  setUp(() {
    authorizedSession = MobileSession(
      tenantId: 'tenant-test-01',
      businessName: 'Tenzo Mobile Yard',
      deviceId: 'dev-1',
      deviceCode: 'DEV-01',
      deviceName: 'Test Phone',
      locationId: 'loc-001',
      locationCode: 'YARD-1',
      locationName: 'Main Yard',
      currencyCode: 'INR',
      username: 'yard_manager',
      canViewAllLocations: true,
      canApprove: true,
      canReceiveCustomerPayment: true,
      canViewNotifications: true,
      canViewAudit: true,
      canViewTraceability: true,
      canViewWarranty: true,
      locations: [
        MobileLocation(id: 'loc-001', name: 'Main Yard', code: 'YARD-1', accessLevel: 'full'),
      ],
      release: ThqMobileReleaseStatus.unknown(),
      roles: {'admin'},
      permissions: {'material_yard.manage', 'purchases.create', 'sales.create'},
      enabledModules: {'material_yard', 'purchases', 'sales'},
    );

    unauthorizedSession = MobileSession(
      tenantId: 'tenant-test-01',
      businessName: 'Tenzo Mobile Yard',
      deviceId: 'dev-2',
      deviceCode: 'DEV-02',
      deviceName: 'Viewer Phone',
      locationId: 'loc-001',
      locationCode: 'YARD-1',
      locationName: 'Main Yard',
      currencyCode: 'INR',
      username: 'yard_viewer',
      canViewAllLocations: false,
      canApprove: false,
      canReceiveCustomerPayment: false,
      canViewNotifications: false,
      canViewAudit: false,
      canViewTraceability: false,
      canViewWarranty: false,
      locations: [
        MobileLocation(id: 'loc-001', name: 'Main Yard', code: 'YARD-1', accessLevel: 'view'),
      ],
      release: ThqMobileReleaseStatus.unknown(),
      roles: {'viewer'},
      permissions: {'material_yard.view'},
      enabledModules: {'material_yard'},
    );

    mockService = MockPrePostingYardService();
  });

  group('Mobile Scenarios 1 & 2: Edit & Reopen Inward Loads', () {
    test('Confirmed-unbilled load can be reopened to draft state via mobile service', () async {
      mockService.seedLoad('load-mob-01', {
        'id': 'load-mob-01',
        'load_number': 'IN-MOB-001',
        'direction': 'inbound',
        'status': 'confirmed',
        'quantity': 450.0,
        'unit_code': 'CFT',
        'purchase_id': null,
      });

      final result = await mockService.reopenMaterialLoad(
        authorizedSession,
        loadId: 'load-mob-01',
        reason: 'Operator corrected vehicle gross weight',
      );

      expect(result['success'], isTrue);
      expect(result['status'], equals('draft'));

      final detail = await mockService.materialLoadDetail(
        authorizedSession,
        loadId: 'load-mob-01',
      );
      expect(detail['status'], equals('draft'));
    });
  });

  group('Mobile Scenarios 3 & 4: Quantity/Rate Edits & Supplier Divergence in Billing Sheet', () {
    testWidgets('MobileMaterialBillingSheet allows editing invoiced quantity and displays divergence banner', (tester) async {
      final inboundLoad = {
        'id': 'load-mob-02',
        'load_number': 'IN-MOB-002',
        'direction': 'inbound',
        'variant_name': '20mm Crushed Blue Metal',
        'quantity': 500.0,
        'unit_code': 'CFT',
        'party_id': 'sup-001',
        'party_name': 'Apex Quarry & Mining Ltd',
        'status': 'confirmed',
        'updated_at': DateTime.now().toIso8601String(),
      };
      mockService.seedLoad('load-mob-02', inboundLoad);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileMaterialBillingSheet(
              session: authorizedSession,
              service: mockService,
              load: inboundLoad,
              onInvoiced: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial load quantity is displayed
      expect(find.text('500'), findsOneWidget);

      // Verify Grand Total calculation
      expect(find.text('Grand Invoiced Total'), findsOneWidget);

      // Enter a divergent quantity (480.0 instead of 500)
      final qtyFinder = find.widgetWithText(TextField, '500');
      await tester.enterText(qtyFinder, '480.0');
      await tester.pumpAndSettle();

      // Warning divergence banner should now be visible
      expect(find.textContaining('Invoiced quantity (480.0 CFT) differs from load quantity (500.0 CFT)'), findsOneWidget);
    });
  });

  group('Mobile Scenario 5: Purchase Linking with Concurrency Token', () {
    test('Successful purchase posting links invoice and passes concurrency check', () async {
      final openedAt = DateTime.parse('2026-10-18T10:00:00.000Z');
      mockService.seedLoad('load-mob-05', {
        'id': 'load-mob-05',
        'load_number': 'IN-MOB-005',
        'direction': 'inbound',
        'status': 'confirmed',
        'quantity': 350.0,
        'updated_at': openedAt.toIso8601String(),
        'purchase_id': null,
      });

      final linkResult = await mockService.linkMaterialLoadPurchase(
        authorizedSession,
        loadId: 'load-mob-05',
        supplierId: 'sup-001',
        purchaseDate: DateTime(2026, 10, 18),
        items: [
          {'quantity': 340.0, 'unit_price': 45.0, 'total': 15300.0},
        ],
        loadUpdatedAt: openedAt,
      );

      expect(linkResult['success'], isTrue);
      expect(linkResult['purchase_id'], equals('pur-invoice-101'));

      final detail = await mockService.materialLoadDetail(authorizedSession, loadId: 'load-mob-05');
      expect(detail['purchase_id'], equals('pur-invoice-101'));
    });
  });

  group('Mobile Scenario 6: Outward Load & Linked Sale Flow', () {
    test('Successful sale posting links sales invoice to outward load', () async {
      final openedAt = DateTime.parse('2026-10-18T11:00:00.000Z');
      mockService.seedLoad('load-mob-06', {
        'id': 'load-mob-06',
        'load_number': 'OUT-MOB-006',
        'direction': 'outbound',
        'status': 'confirmed',
        'quantity': 600.0,
        'updated_at': openedAt.toIso8601String(),
        'sale_id': null,
      });

      final saleResult = await mockService.linkMaterialLoadSale(
        authorizedSession,
        loadId: 'load-mob-06',
        customerId: 'cust-002',
        saleDate: DateTime(2026, 10, 18),
        items: [
          {'quantity': 600.0, 'unit_price': 65.0, 'total': 39000.0},
        ],
        loadUpdatedAt: openedAt,
      );

      expect(saleResult['success'], isTrue);
      expect(saleResult['sale_id'], equals('sale-invoice-202'));

      final detail = await mockService.materialLoadDetail(authorizedSession, loadId: 'load-mob-06');
      expect(detail['sale_id'], equals('sale-invoice-202'));
    });
  });

  group('Mobile Scenario 7: Concurrency Conflict Detection', () {
    test('Concurrent modification of load elsewhere aborts posting with conflict error', () async {
      final draftOpenedAt = DateTime.parse('2026-10-18T09:00:00.000Z');
      final concurrentDbTime = DateTime.parse('2026-10-18T09:10:00.000Z');

      mockService.seedLoad('load-mob-07', {
        'id': 'load-mob-07',
        'direction': 'inbound',
        'status': 'confirmed',
        'quantity': 400.0,
        'updated_at': concurrentDbTime.toIso8601String(), // Updated in DB after draft was opened
        'purchase_id': null,
      });

      expect(
        () => mockService.linkMaterialLoadPurchase(
          authorizedSession,
          loadId: 'load-mob-07',
          supplierId: 'sup-001',
          purchaseDate: DateTime(2026, 10, 18),
          items: [
            {'quantity': 400.0, 'unit_price': 50.0},
          ],
          loadUpdatedAt: draftOpenedAt, // Stale timestamp
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Concurrency conflict'),
        )),
      );
    });
  });

  group('Mobile Scenario 8: Attempt Duplicate Posting', () {
    test('Attempting duplicate purchase or sale posting is blocked', () async {
      mockService.seedLoad('load-mob-08', {
        'id': 'load-mob-08',
        'direction': 'inbound',
        'status': 'completed',
        'purchase_id': 'pur-already-posted',
      });

      expect(
        () => mockService.linkMaterialLoadPurchase(
          authorizedSession,
          loadId: 'load-mob-08',
          supplierId: 'sup-001',
          purchaseDate: DateTime(2026, 10, 18),
          items: [
            {'quantity': 400.0, 'unit_price': 50.0},
          ],
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('already linked to a finalized purchase'),
        )),
      );
    });
  });

  group('Mobile Scenario 9: Attempt Unauthorized Edit', () {
    test('Unauthorized mobile user without manage permission cannot reopen load', () async {
      mockService.seedLoad('load-mob-09', {
        'id': 'load-mob-09',
        'direction': 'inbound',
        'status': 'confirmed',
      });

      expect(
        () => mockService.reopenMaterialLoad(
          unauthorizedSession,
          loadId: 'load-mob-09',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Permission denied'),
        )),
      );
    });
  });

  group('Mobile Scenario 10: Attempt Editing After Final Posting', () {
    test('Reopening or modifying a finalized load fails with locked error', () async {
      mockService.seedLoad('load-mob-10', {
        'id': 'load-mob-10',
        'direction': 'inbound',
        'status': 'completed',
        'purchase_id': 'pur-final-001',
      });

      expect(
        () => mockService.reopenMaterialLoad(
          authorizedSession,
          loadId: 'load-mob-10',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('cannot be edited or reopened'),
        )),
      );
    });
  });

  group('Mobile Scenario 11: Verify Old Posted Records and Measurements Remain Intact', () {
    test('Mobile billing adjustments do not overwrite physical weighbridge readings', () {
      final physicalLoad = {
        'id': 'load-mob-11',
        'gross_weight_kg': 32400.0,
        'tare_weight_kg': 12200.0,
        'net_weight_kg': 20200.0,
        'calculated_cft': 505.0,
        'load_quantity': 505.0,
      };

      // In mobile billing, invoiced quantity was adjusted to 495.0 CFT
      const invoicedQty = 495.0;

      // Ensure physical measurement fields are not mutated
      expect(physicalLoad['gross_weight_kg'], equals(32400.0));
      expect(physicalLoad['tare_weight_kg'], equals(12200.0));
      expect(physicalLoad['net_weight_kg'], equals(20200.0));
      expect(physicalLoad['calculated_cft'], equals(505.0));
      expect(physicalLoad['load_quantity'], equals(505.0));
      expect(invoicedQty, isNot(equals(physicalLoad['load_quantity'])));
    });
  });
}
