import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_core/erp_core.dart';
import 'package:client_mobile/models/mobile_session.dart';
import 'package:client_mobile/services/mobile_client_service.dart';
import 'package:client_mobile/screens/workspace/mobile_material_yard_page.dart';
import 'package:client_mobile/screens/workspace/material_yard/material_yard_types.dart';

class MockYardClientService extends MobileClientService {
  @override
  Future<Map<String, dynamic>> materialYardDashboard(
    MobileSession s, {
    String? locationId,
    DateTime? day,
  }) async {
    return {
      'today_inward_loads': 5,
      'today_outward_loads': 8,
      'today_inward_qty_cft': 1450.5,
      'today_outward_qty_cft': 2890.0,
      'today_purchase_value': 87030.0,
      'today_sales_value': 216750.0,
      'available_stock_cft': 15400.0,
      'pending_confirmation_loads': 2,
      'unbilled_inward_loads': 3,
      'unbilled_outward_loads': 4,
      'receivables_amount': 450000.0,
      'payables_amount': 180000.0,
      'recent_loads': [
        {
          'id': 'load-101',
          'load_number': 'IN-2026-001',
          'direction': 'inbound',
          'variant_name': 'Tenzo 20mm Aggregate',
          'party_name': 'Blackstone Quarry Corp',
          'vehicle_registration': 'MH 12 QW 9988',
          'driver_name': 'Ramesh Kumar',
          'quantity': 350.0,
          'unit_code': 'CFT',
          'status': 'confirmed',
          'created_at': DateTime.now().toIso8601String(),
        },
        {
          'id': 'load-102',
          'load_number': 'OUT-2026-001',
          'direction': 'outbound',
          'variant_name': 'Tenzo M-Sand',
          'party_name': 'Skyline Builders & Developers',
          'vehicle_registration': 'MH 14 TR 4411',
          'driver_name': 'Suresh Patil',
          'quantity': 420.0,
          'unit_code': 'CFT',
          'status': 'invoiced',
          'invoice_number': 'INV-2026-889',
          'created_at': DateTime.now().toIso8601String(),
        },
      ],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> materialLoads(
    MobileSession s, {
    String? locationId,
    String? status,
    String? direction,
    String? query,
    int limit = 300,
  }) async {
    final list = [
      {
        'id': 'load-101',
        'load_number': 'IN-2026-001',
        'direction': 'inbound',
        'variant_name': 'Tenzo 20mm Aggregate',
        'party_name': 'Blackstone Quarry Corp',
        'vehicle_registration': 'MH 12 QW 9988',
        'driver_name': 'Ramesh Kumar',
        'quantity': 350.0,
        'unit_code': 'CFT',
        'status': 'confirmed',
        'created_at': DateTime.now().toIso8601String(),
      },
      {
        'id': 'load-102',
        'load_number': 'OUT-2026-001',
        'direction': 'outbound',
        'variant_name': 'Tenzo M-Sand',
        'party_name': 'Skyline Builders & Developers',
        'vehicle_registration': 'MH 14 TR 4411',
        'driver_name': 'Suresh Patil',
        'quantity': 420.0,
        'unit_code': 'CFT',
        'status': 'invoiced',
        'invoice_number': 'INV-2026-889',
        'created_at': DateTime.now().toIso8601String(),
      },
    ];
    if (direction == null || direction.isEmpty) return list;
    return list.where((x) => x['direction'] == direction).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> materialYardStock(
    MobileSession s, {
    String? locationId,
    String? query,
    int limit = 300,
  }) async {
    return [
      {
        'variant_id': 'var-1',
        'material_name': 'Blue Metal 20mm',
        'quality_grade': 'Standard Grade A',
        'available_qty': 4500.0,
        'unit_code': 'CFT',
        'avg_cost_price': 38.5,
        'selling_price': 52.0,
      },
      {
        'variant_id': 'var-2',
        'material_name': 'Manufactured Sand (M-Sand)',
        'quality_grade': 'Washed Premium',
        'available_qty': 10900.0,
        'unit_code': 'CFT',
        'avg_cost_price': 44.0,
        'selling_price': 60.0,
      },
    ];
  }
}

void main() {
  group('MaterialMeasurementEngine — Unit Tests', () {
    test('Calculates volume correctly from dimensions in inches: CFT = (L × W × H) / 1728', () {
      // 120 in (10 ft) * 72 in (6 ft) * 48 in (4 ft) = 414,720 cu in / 1728 = 240.0 CFT
      final cft = MaterialMeasurementEngine.calculateFromInches(
        lengthIn: 120.0,
        widthIn: 72.0,
        heightIn: 48.0,
      );
      expect(cft, closeTo(240.0, 0.001));
    });

    test('Calculates volume correctly from dimensions in feet: CFT = L × W × H', () {
      final cft = MaterialMeasurementEngine.calculateFromFeet(
        lengthFt: 10.0,
        widthFt: 6.0,
        heightFt: 4.0,
      );
      expect(cft, closeTo(240.0, 0.001));
    });

    test('Calculates volume from composite Feet and Inches identically', () {
      final cft = MaterialMeasurementEngine.calculateFromFeetAndInches(
        lengthFt: 10.0,
        lengthIn: 0.0,
        widthFt: 6.0,
        widthIn: 0.0,
        heightFt: 4.0,
        heightIn: 0.0,
      );
      expect(cft, closeTo(240.0, 0.001));

      // With inches component: 10ft 6in (126 in), 6ft 0in (72 in), 4ft 0in (48 in)
      // 126 * 72 * 48 / 1728 = 252.0 CFT
      final cftWithInches = MaterialMeasurementEngine.calculateFromFeetAndInches(
        lengthFt: 10.0,
        lengthIn: 6.0,
        widthFt: 6.0,
        heightFt: 4.0,
      );
      expect(cftWithInches, closeTo(252.0, 0.001));
    });

    test('Calculates volume from metric metres: CFT = (L × W × H) × 35.3146667', () {
      final cft = MaterialMeasurementEngine.calculateFromMetres(
        lengthM: 2.0,
        widthM: 2.0,
        heightM: 2.0,
      );
      // 8 m^3 * 35.3146667 = 282.517 CFT
      expect(cft, closeTo(282.517, 0.01));
    });

    test('calculateDimensionsVolume delegates across all dimension units accurately', () {
      final cftInches = MaterialMeasurementEngine.calculateDimensionsVolume(
        length: 120.0,
        width: 72.0,
        height: 48.0,
        unit: DimensionUnit.inches,
      );
      expect(cftInches, closeTo(240.0, 0.001));

      final cftFeet = MaterialMeasurementEngine.calculateDimensionsVolume(
        length: 10.0,
        width: 6.0,
        height: 4.0,
        unit: DimensionUnit.feet,
      );
      expect(cftFeet, closeTo(240.0, 0.001));
    });

    test('Weighbridge Net weight: Gross - Tare', () {
      final net = MaterialMeasurementEngine.calculateNetWeight(
        grossWeight: 25400.0,
        tareWeight: 9800.0,
      );
      expect(net, closeTo(15600.0, 0.001));
    });

    test('Truck capacity validation correctly detects overload and requires override reason', () {
      // 1. Within capacity: valid
      final ok = MaterialMeasurementEngine.validateTruckCapacity(
        loadQtyCft: 300.0,
        nominalCapacityCft: 350.0,
        allowOverride: false,
      );
      expect(ok, isNull);

      // 2. Over capacity without override: rejected
      final rejected = MaterialMeasurementEngine.validateTruckCapacity(
        loadQtyCft: 400.0,
        nominalCapacityCft: 350.0,
        allowOverride: false,
      );
      expect(rejected, isNotNull);
      expect(rejected, contains('exceeds truck capacity'));

      // 3. Over capacity with override but missing reason: rejected
      final missingReason = MaterialMeasurementEngine.validateTruckCapacity(
        loadQtyCft: 400.0,
        nominalCapacityCft: 350.0,
        allowOverride: true,
        overrideReason: '   ',
      );
      expect(missingReason, isNotNull);
      expect(missingReason, contains('override reason is required'));

      // 4. Over capacity with override and valid reason: accepted
      final acceptedOverride = MaterialMeasurementEngine.validateTruckCapacity(
        loadQtyCft: 400.0,
        nominalCapacityCft: 350.0,
        allowOverride: true,
        overrideReason: 'Authorized heap density check by supervisor',
      );
      expect(acceptedOverride, isNull);
    });

    test('MeasurementResult includes heap adjustment in billable quantity', () {
      final result = MaterialMeasurementEngine.process(
        method: MaterialMeasurementMethod.dimensions,
        unit: DimensionUnit.feet,
        length: 10.0,
        width: 6.0,
        height: 4.0,
        heapAdjustmentCft: 15.0,
      );
      expect(result.geometricCft, closeTo(240.0, 0.001));
      expect(result.approvedBillableQuantity, closeTo(255.0, 0.001));
    });
  });

  group('MaterialYardFormat — Formatters & Presentation Tests', () {
    test('Formats currency amounts with symbol and comma separators', () {
      expect(MaterialYardFormat.money(1500000.5, currency: 'INR'), '₹1500000.50');
      expect(MaterialYardFormat.money(0, currency: 'USD'), 'USD 0.00');
    });

    test('Formats CFT volume with units', () {
      expect(MaterialYardFormat.cft(1450.75), '1,450.75 CFT');
      expect(MaterialYardFormat.cft(null), '0.00 CFT');
    });

    test('Formats custom quantity with unit', () {
      expect(MaterialYardFormat.quantity(25.5, 'TON'), '25.50 TON');
      expect(MaterialYardFormat.quantity(100.0, 'CFT'), '100 CFT');
    });

    test('Resolves correct load status labels and theme colors', () {
      expect(MaterialYardFormat.statusLabel('draft'), 'DRAFT');
      expect(MaterialYardFormat.statusColor('draft'), const Color(0xFFFF9900));

      expect(MaterialYardFormat.statusLabel('confirmed'), 'CONFIRMED');
      expect(MaterialYardFormat.statusColor('confirmed'), const Color(0xFF0052CC));

      expect(MaterialYardFormat.statusLabel('invoiced'), 'INVOICED');
      expect(MaterialYardFormat.statusColor('invoiced'), const Color(0xFF00875A));
    });
  });

  group('MobileMaterialYardPage — Widget & Navigation Flow Tests', () {
    late MobileSession dummySession;
    late MockYardClientService mockService;

    setUp(() {
      dummySession = const MobileSession(
        tenantId: 'ten-1',
        businessName: 'Tenzo Traders Material Yard',
        deviceId: 'dev-1',
        deviceCode: 'DEV-01',
        deviceName: 'Android Device',
        locationId: 'loc-yard-1',
        locationCode: 'YARD-01',
        locationName: 'Main Crushing Yard',
        currencyCode: 'INR',
        username: 'admin',
        canViewAllLocations: true,
        canApprove: true,
        canReceiveCustomerPayment: true,
        canViewNotifications: true,
        canViewAudit: true,
        canViewTraceability: true,
        canViewWarranty: true,
        locations: const [
          MobileLocation(id: 'loc-yard-1', name: 'Main Crushing Yard', code: 'YARD-01', accessLevel: 'full'),
        ],
        release: const ThqMobileReleaseStatus.unknown(),
        roles: {'admin'},
        permissions: {'material_yard.manage', 'purchases.create', 'sales.create'},
        enabledModules: {'material_yard', 'purchases', 'sales'},
      );
      mockService = MockYardClientService();
    });

    testWidgets('Renders Material Yard with 5 navigation tabs and action buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MobileMaterialYardPage(
            session: dummySession,
            service: mockService,
          ),
        ),
      );

      // Allow async initial load to resolve
      await tester.pumpAndSettle();

      // Verify Header Title
      expect(find.text('Material Yard & Quarry'), findsOneWidget);

      // Verify 5 Navigation Tabs
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Inward'), findsOneWidget);
      expect(find.text('Outward'), findsOneWidget);
      expect(find.text('Stock'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);

      // Verify Quick Action Buttons
      expect(find.text('+ New Inward'), findsOneWidget);
      expect(find.text('+ New Outward'), findsOneWidget);

      // Verify Dashboard KPI Cards
      expect(find.text("Today's Inward"), findsOneWidget);
      expect(find.text("Today's Outward"), findsOneWidget);
      expect(find.text('Available Bulk Stock'), findsOneWidget);
    });

    testWidgets('Switches tabs to Inward, Outward, Stock, and More without error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MobileMaterialYardPage(
            session: dummySession,
            service: mockService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Switch to Inward tab
      await tester.tap(find.text('Inward'));
      await tester.pumpAndSettle();
      expect(find.text('IN-2026-001'), findsOneWidget);
      expect(find.textContaining('Blackstone Quarry Corp'), findsOneWidget);

      // 2. Switch to Outward tab
      await tester.tap(find.text('Outward'));
      await tester.pumpAndSettle();
      expect(find.text('OUT-2026-001'), findsOneWidget);
      expect(find.textContaining('Skyline Builders'), findsOneWidget);

      // 3. Switch to Stock tab
      await tester.tap(find.text('Stock'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Blue Metal 20mm'), findsOneWidget);
      expect(find.textContaining('Manufactured Sand'), findsOneWidget);

      // 4. Switch to More tab
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Daily Rate Board'), findsOneWidget);
      expect(find.text('Yard Trucks & Fleet Master'), findsOneWidget);
      expect(find.text('Yard Driver Master'), findsOneWidget);
      expect(find.text('Customer Bulk Orders'), findsOneWidget);
      expect(find.text('Freight & Logistics Settlement'), findsOneWidget);
    });
  });
}
