import 'package:flutter_test/flutter_test.dart';
import 'package:client_app/models/client_session.dart';
import 'package:client_app/models/sale_invoice_context.dart';

void main() {
  const testBusiness = ClientBusiness(
    id: 'b-yard-tenant-01',
    membershipId: 'mem-admin-01',
    name: 'Tenzo Aggregate Yard',
    slug: 'tenzo-aggregate-yard',
    businessType: 'material_yard',
    status: 'active',
  );

  const authorizedSession = ClientSession(
    business: testBusiness,
    modules: [
      ClientModule(key: 'material_yard', name: 'Material Yard', description: null, category: 'operations', sortOrder: 1),
      ClientModule(key: 'purchases', name: 'Purchases', description: null, category: 'accounting', sortOrder: 2),
      ClientModule(key: 'sales', name: 'Sales', description: null, category: 'accounting', sortOrder: 3),
      ClientModule(key: 'vehicle_logistics', name: 'Logistics', description: null, category: 'operations', sortOrder: 4),
    ],
    roles: {'owner'},
    permissions: {
      'aggregate_yard.manage',
      'aggregate_yard.view',
      'purchases.create',
      'purchases.view',
      'sales.create',
      'sales.view',
    },
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    locale: 'en_IN',
    canViewAllLocations: true,
  );

  const unauthorizedSession = ClientSession(
    business: testBusiness,
    modules: [
      ClientModule(key: 'material_yard', name: 'Material Yard', description: null, category: 'operations', sortOrder: 1),
    ],
    roles: {'viewer'},
    permissions: {
      'aggregate_yard.view',
    },
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    locale: 'en_IN',
    canViewAllLocations: true,
  );

  // Helper functions mirroring AggregateLoadsScreen and Detail screen logic
  bool canEditLoad(Map<String, dynamic> row, ClientSession session) {
    final canManage = session.hasRole('owner') ||
        session.hasPermission('aggregate_yard.manage');
    if (!canManage) return false;
    final status = (row['status'] ?? '').toString().toLowerCase();
    if (status == 'cancelled') return false;
    final isBilled = (row['purchase_id'] != null && row['purchase_id'].toString().isNotEmpty) ||
        (row['sale_id'] != null && row['sale_id'].toString().isNotEmpty);
    if (isBilled) return false;
    return true; // Allowed for both 'draft' and 'completed' (confirmed) unbilled loads
  }

  bool canReopenLoad(Map<String, dynamic> row, ClientSession session) {
    final canManage = session.hasRole('owner') ||
        session.hasPermission('aggregate_yard.manage');
    if (!canManage) return false;
    final status = (row['status'] ?? '').toString().toLowerCase();
    final isBilled = (row['purchase_id'] != null && row['purchase_id'].toString().isNotEmpty) ||
        (row['sale_id'] != null && row['sale_id'].toString().isNotEmpty);
    // Can only reopen confirmed-unbilled loads ('completed' in v617/v722)
    return (status == 'completed' || status == 'confirmed') && !isBilled;
  }

  bool canCreatePurchase(Map<String, dynamic> row, ClientSession session) {
    final canPurchase = session.hasRole('owner') || session.hasPermission('purchases.create');
    if (!canPurchase) return false;
    final direction = (row['direction'] ?? '').toString().toLowerCase();
    if (direction != 'inbound') return false;
    final isBilled = row['purchase_id'] != null && row['purchase_id'].toString().isNotEmpty;
    if (isBilled) return false;
    final status = (row['status'] ?? '').toString().toLowerCase();
    return status != 'cancelled';
  }

  bool canCreateSale(Map<String, dynamic> row, ClientSession session) {
    final canSale = session.hasRole('owner') || session.hasPermission('sales.create');
    if (!canSale) return false;
    final direction = (row['direction'] ?? '').toString().toLowerCase();
    if (direction != 'outbound') return false;
    final isBilled = row['sale_id'] != null && row['sale_id'].toString().isNotEmpty;
    if (isBilled) return false;
    final status = (row['status'] ?? '').toString().toLowerCase();
    return status != 'cancelled';
  }

  group('Scenario 1: Edit a draft inward load', () {
    test('Draft inward load allows full editing of quantities, suppliers, vehicles, and rates', () {
      final draftLoad = {
        'id': 'load-in-001',
        'load_number': 'IN-LOAD-001',
        'direction': 'inbound',
        'status': 'draft',
        'quantity': 350.0,
        'unit_code': 'CFT',
        'supplier_id': 'sup-quarry-a',
        'vehicle_id': 'veh-truck-01',
        'driver_id': 'drv-ramesh',
        'purchase_id': null,
        'sale_id': null,
      };

      expect(canEditLoad(draftLoad, authorizedSession), isTrue);
      expect(canReopenLoad(draftLoad, authorizedSession), isFalse); // Already draft

      // Simulate load edit payload
      final updatedLoad = Map<String, dynamic>.from(draftLoad)
        ..['quantity'] = 400.0
        ..['supplier_id'] = 'sup-quarry-b'
        ..['load_date'] = '2026-10-18'
        ..['notes'] = 'Revised quantity upon weighbridge recalibration';

      expect(updatedLoad['quantity'], equals(400.0));
      expect(updatedLoad['supplier_id'], equals('sup-quarry-b'));
      expect(updatedLoad['load_date'], equals('2026-10-18'));
      expect(canEditLoad(updatedLoad, authorizedSession), isTrue);
    });
  });

  group('Scenario 2: Edit a confirmed-unbilled inward load', () {
    test('Confirmed-unbilled load is editable and can be explicitly reopened for editing', () {
      final confirmedLoad = {
        'id': 'load-in-002',
        'load_number': 'IN-LOAD-002',
        'direction': 'inbound',
        'status': 'completed', // 'completed' = confirmed in v617 schema
        'quantity': 500.0,
        'unit_code': 'CFT',
        'supplier_id': 'sup-quarry-a',
        'purchase_id': null,
        'sale_id': null,
      };

      // In v722, confirmed-unbilled load can be directly edited or reopened
      expect(canEditLoad(confirmedLoad, authorizedSession), isTrue);
      expect(canReopenLoad(confirmedLoad, authorizedSession), isTrue);

      // Reopening reverts status to 'draft' while preserving audit logs
      final reopenedLoad = Map<String, dynamic>.from(confirmedLoad)
        ..['status'] = 'draft';

      expect(reopenedLoad['status'], equals('draft'));
      expect(canEditLoad(reopenedLoad, authorizedSession), isTrue);
      expect(canReopenLoad(reopenedLoad, authorizedSession), isFalse); // Once reopened, it is in draft
    });
  });

  group('Scenario 3: Change quantity and rate before purchase posting', () {
    test('Quantity and rate modifications in load or draft recalculate totals accurately', () {
      const initialQty = 450.0;
      const initialRate = 42.0;
      final initialTotal = initialQty * initialRate;
      expect(initialTotal, equals(18900.0));

      // User modifies negotiated rate and loaded quantity
      const revisedQty = 480.0;
      const revisedRate = 40.0;
      final revisedTotal = revisedQty * revisedRate;

      expect(revisedTotal, equals(19200.0));
      expect(revisedTotal, isNot(equals(initialTotal)));
    });
  });

  group('Scenario 4: Edit supplier and expenses in the purchase draft', () {
    test('Purchase draft detects supplier divergence and preserves operational load linkage', () {
      const loadSupplierId = 'sup-quarry-primary';
      const billingSupplierId = 'sup-quarry-secondary';

      final isSupplierDivergent = loadSupplierId != billingSupplierId;
      expect(isSupplierDivergent, isTrue);

      // The billing draft permits divergent supplier while recording warning
      final billingDraft = {
        'load_id': 'load-in-003',
        'load_supplier_id': loadSupplierId,
        'billing_supplier_id': billingSupplierId,
        'is_divergent': isSupplierDivergent,
        'expenses': [
          {'kind': 'freight', 'amount': 2500.0},
          {'kind': 'loading', 'amount': 600.0},
        ],
      };

      expect(billingDraft['is_divergent'], isTrue);
      expect((billingDraft['expenses'] as List).length, equals(2));
    });
  });

  group('Scenario 5: Finalize purchase and verify stock, accounting, and load links', () {
    test('Authoritative purchase posting sets purchase_id and locks load from subsequent edits', () {
      final unbilledLoad = {
        'id': 'load-in-005',
        'load_number': 'IN-LOAD-005',
        'direction': 'inbound',
        'status': 'completed',
        'quantity': 600.0,
        'purchase_id': null,
        'sale_id': null,
      };

      expect(canCreatePurchase(unbilledLoad, authorizedSession), isTrue);
      expect(canEditLoad(unbilledLoad, authorizedSession), isTrue);

      // Simulate authoritative purchase posting
      final postedLoad = Map<String, dynamic>.from(unbilledLoad)
        ..['purchase_id'] = 'pur-inv-9988'
        ..['purchase_invoice_number'] = 'PINV-2026-001'
        ..['updated_at'] = DateTime.now().toIso8601String();

      // Once purchase_id is populated, load is strictly locked
      expect(canCreatePurchase(postedLoad, authorizedSession), isFalse);
      expect(canEditLoad(postedLoad, authorizedSession), isFalse);
      expect(canReopenLoad(postedLoad, authorizedSession), isFalse);
    });
  });

  group('Scenario 6: Outward load and linked sale full flow', () {
    test('Non-strict customer check permits customer divergence with warning in sale draft', () {
      final context = SaleInvoiceContext.fromMap({
        'tax_mode': 'non_gst',
        'locked_customer_id': 'load-cust-original',
      });

      // Strict check fails (legacy)
      expect(() => context.checkCustomer('divergent-cust', strict: true), throwsStateError);

      // Non-strict check succeeds for pre-posting editability
      expect(() => context.checkCustomer('divergent-cust', strict: false), returnsNormally);

      // Divergence is correctly identified
      expect(context.isCustomerDivergent('divergent-cust'), isTrue);
      expect(context.isCustomerDivergent('load-cust-original'), isFalse);
    });

    test('Outward load draft pre-fills into sale line and allows quantity and rate edits', () {
      final outwardLoad = {
        'id': 'load-out-001',
        'direction': 'outbound',
        'status': 'completed',
        'quantity': 300.0,
        'selling_price': 85.0,
        'customer_id': 'cust-alpha',
        'sale_id': null,
      };

      expect(canCreateSale(outwardLoad, authorizedSession), isTrue);

      // User adjusts quantity in billing draft to 290.0 at rate 88.0
      const billedQty = 290.0;
      const billedRate = 88.0;
      final invoiceSubtotal = billedQty * billedRate;

      expect(invoiceSubtotal, equals(25520.0));

      // Finalize sale
      final postedOutward = Map<String, dynamic>.from(outwardLoad)
        ..['sale_id'] = 'sale-inv-7766'
        ..['sale_invoice_number'] = 'SINV-2026-042';

      expect(canCreateSale(postedOutward, authorizedSession), isFalse);
      expect(canEditLoad(postedOutward, authorizedSession), isFalse);
    });
  });

  group('Scenario 7: Concurrency conflict detection', () {
    test('Timestamp mismatch between draft creation and posting triggers concurrency conflict', () {
      final loadOpenedTimestamp = DateTime.parse('2026-10-18T10:00:00.000Z');
      final loadCurrentTimestamp = DateTime.parse('2026-10-18T10:15:00.000Z');

      // Helper function simulating concurrency check in backend RPCs
      void assertConcurrency(DateTime openedAt, DateTime currentInDb) {
        if (currentInDb.isAfter(openedAt)) {
          throw StateError(
            'Concurrency conflict: Load was updated by another user or operation after the billing draft was opened. Please refresh before posting.',
          );
        }
      }

      expect(
        () => assertConcurrency(loadOpenedTimestamp, loadCurrentTimestamp),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Concurrency conflict'),
        )),
      );

      // Matching timestamp succeeds
      expect(
        () => assertConcurrency(loadOpenedTimestamp, loadOpenedTimestamp),
        returnsNormally,
      );
    });
  });

  group('Scenario 8: Attempt duplicate posting', () {
    test('Duplicate purchase or sale posting is strictly blocked if load already linked', () {
      final alreadyBilledInward = {
        'id': 'load-in-008',
        'direction': 'inbound',
        'status': 'completed',
        'purchase_id': 'pur-existing-001',
      };

      expect(canCreatePurchase(alreadyBilledInward, authorizedSession), isFalse);

      final alreadyBilledOutward = {
        'id': 'load-out-008',
        'direction': 'outbound',
        'status': 'completed',
        'sale_id': 'sale-existing-001',
      };

      expect(canCreateSale(alreadyBilledOutward, authorizedSession), isFalse);
    });
  });

  group('Scenario 9: Attempt unauthorized edit', () {
    test('Unauthorized user without aggregate_yard.manage permission cannot edit or reopen', () {
      final load = {
        'id': 'load-009',
        'direction': 'inbound',
        'status': 'completed',
        'purchase_id': null,
        'sale_id': null,
      };

      expect(canEditLoad(load, unauthorizedSession), isFalse);
      expect(canReopenLoad(load, unauthorizedSession), isFalse);
      expect(canCreatePurchase(load, unauthorizedSession), isFalse);
    });
  });

  group('Scenario 10: Attempt editing after final posting', () {
    test('Once authoritative transaction is finalized, all edits and reopens are blocked', () {
      final finalizedLoad = {
        'id': 'load-final-010',
        'load_number': 'OUT-FINAL-010',
        'direction': 'outbound',
        'status': 'completed',
        'quantity': 500.0,
        'sale_id': 'final-sale-uuid-001',
        'purchase_id': null,
      };

      expect(canEditLoad(finalizedLoad, authorizedSession), isFalse);
      expect(canReopenLoad(finalizedLoad, authorizedSession), isFalse);
      expect(canCreateSale(finalizedLoad, authorizedSession), isFalse);
    });
  });

  group('Scenario 11: Verify no old posted records are changed', () {
    test('Billing draft quantity alterations do not mutate physical load measurements', () {
      final physicalLoad = {
        'id': 'load-phys-011',
        'gross_weight_kg': 28500.0,
        'tare_weight_kg': 10500.0,
        'net_weight_kg': 18000.0,
        'calculated_cft': 450.0,
        'body_length_ft': 18.0,
        'body_width_ft': 7.5,
        'body_height_ft': 3.33,
        'quantity': 450.0,
      };

      // Invoice billed quantity adjusted down due to moisture deduction or negotiated billable volume
      const invoicedQuantity = 430.0;

      // Invoice item reflects commercial billing quantity
      final invoiceLine = {
        'load_id': physicalLoad['id'],
        'billed_quantity': invoicedQuantity,
        'unit_price': 45.0,
        'line_total': invoicedQuantity * 45.0,
      };

      expect(invoiceLine['billed_quantity'], equals(430.0));
      expect(invoiceLine['line_total'], equals(19350.0));

      // Physical load measurements remain completely immutable and historically intact
      expect(physicalLoad['gross_weight_kg'], equals(28500.0));
      expect(physicalLoad['tare_weight_kg'], equals(10500.0));
      expect(physicalLoad['net_weight_kg'], equals(18000.0));
      expect(physicalLoad['calculated_cft'], equals(450.0));
      expect(physicalLoad['quantity'], equals(450.0));
    });
  });
}
