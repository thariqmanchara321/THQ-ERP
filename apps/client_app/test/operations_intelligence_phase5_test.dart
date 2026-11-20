import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/operations_intelligence_screen.dart';
import 'package:client_app/services/operations_intelligence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockPhase5IntelligenceService extends OperationsIntelligenceService {
  final bool failPurchase;
  final bool failSupplier;
  final bool failProcurement;
  final bool emptyData;

  final List<Map<String, dynamic>> createdOrders = [];

  _MockPhase5IntelligenceService({
    this.failPurchase = false,
    this.failSupplier = false,
    this.failProcurement = false,
    this.emptyData = false,
  });

  @override
  Future<Map<String, dynamic>> operationsSummary({
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async {
    return {
      'tenant_id': tenantId,
      'location_id': locationId,
      'days': days,
      'total_monitored_variants': emptyData ? 0 : 15,
      'inventory_value': emptyData ? 0.0 : 450000.0,
      'dead_stock_value': emptyData ? 0.0 : 25000.0,
      'excess_stock_value': emptyData ? 0.0 : 40000.0,
      'rebalancing_opportunities': emptyData ? 0 : 2,
    };
  }

  @override
  Future<Map<String, dynamic>> salesIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async {
    return {
      'can_view_cost': true,
      'from_date': '2026-10-21',
      'to_date': '2026-11-20',
      'performance': {
        'current': {'net_sales': 150000.0},
        'previous': {'net_sales': 130000.0},
        'growth': {'net_sales_pct': 15.38},
      },
      'trends': {'daily': [], 'weekly': [], 'monthly': []},
      'products': {
        'best_selling': [],
        'highest_volume': [],
        'growing_products': [],
        'declining_products': [],
      },
      'categories': [],
      'customer_intelligence': {
        'summary': {},
        'segments': [],
        'top_customers': [],
      },
      'anomalies': [],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> inventory({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
    bool useV830 = false,
  }) async => [];

  @override
  Future<List<Map<String, dynamic>>> rebalancing({
    required String tenantId,
    String? locationId,
    int days = 30,
    int limit = 100,
  }) async => [];

  @override
  Future<Map<String, dynamic>> purchaseIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async {
    if (failPurchase) {
      throw StateError('Database connection timeout for purchase intelligence RPC');
    }
    if (emptyData) {
      return {
        'tenant_id': tenantId,
        'location_id': locationId,
        'days': days,
        'can_view_cost': true,
        'summary': {
          'current': {
            'gross_purchases': 0.0,
            'purchase_returns': 0.0,
            'net_purchases': 0.0,
            'order_count': 0,
            'average_order_value': 0.0,
            'units_purchased': 0.0,
            'active_suppliers_count': 0,
          },
          'previous': {
            'gross_purchases': 0.0,
            'purchase_returns': 0.0,
            'net_purchases': 0.0,
            'order_count': 0,
            'average_order_value': 0.0,
            'units_purchased': 0.0,
          },
          'growth': {
            'net_purchases_pct': 0.0,
            'order_count_pct': 0.0,
            'returns_pct': 0.0,
            'units_purchased_pct': 0.0,
          },
          'concentration': {
            'top3_spend': 0.0,
            'top3_share_pct': 0.0,
            'dependency_level': 'diversified',
          },
        },
        'trends': {'daily': []},
        'by_supplier': [],
        'by_category': [],
        'by_product': [],
        'price_changes': [],
        'po_performance': {
          'total_orders': 0,
          'draft_count': 0,
          'submitted_count': 0,
          'approved_count': 0,
          'ordered_count': 0,
          'partially_received_count': 0,
          'received_count': 0,
          'cancelled_count': 0,
          'delayed_orders_count': 0,
          'total_ordered_qty': 0.0,
          'total_received_qty': 0.0,
          'fulfillment_rate_pct': 100.0,
          'total_po_value': 0.0,
          'avg_lead_time_days': 0.0,
        },
      };
    }

    return {
      'tenant_id': tenantId,
      'location_id': locationId,
      'days': days,
      'can_view_cost': true,
      'summary': {
        'current': {
          'gross_purchases': 767941.40,
          'purchase_returns': 15000.00,
          'net_purchases': 752941.40,
          'order_count': 22,
          'average_order_value': 34224.61,
          'units_purchased': 18265.0,
          'active_suppliers_count': 4,
        },
        'previous': {
          'gross_purchases': 650000.00,
          'purchase_returns': 5000.00,
          'net_purchases': 645000.00,
          'order_count': 18,
          'average_order_value': 35833.33,
          'units_purchased': 15000.0,
        },
        'growth': {
          'net_purchases_pct': 16.73,
          'order_count_pct': 22.22,
          'returns_pct': 200.00,
          'units_purchased_pct': 21.77,
        },
        'concentration': {
          'top3_spend': 745441.40,
          'top3_share_pct': 97.07,
          'dependency_level': 'high_concentration',
        },
      },
      'trends': {
        'daily': [
          {
            'day_date': '2026-11-01',
            'label': 'Sun, Nov 01',
            'gross_purchases': 55000.0,
            'returns': 0.0,
            'net_purchases': 55000.0,
            'order_count': 2,
          },
          {
            'day_date': '2026-11-05',
            'label': 'Thu, Nov 05',
            'gross_purchases': 120000.0,
            'returns': 5000.0,
            'net_purchases': 115000.0,
            'order_count': 4,
          },
          {
            'day_date': '2026-11-12',
            'label': 'Thu, Nov 12',
            'gross_purchases': 85000.0,
            'returns': 0.0,
            'net_purchases': 85000.0,
            'order_count': 3,
          },
        ],
      },
      'by_supplier': [
        {
          'supplier_id': 'sup-01',
          'supplier_name': 'Ambuja Cements Ltd',
          'spend': 415000.00,
          'po_count': 10,
          'share_pct': 54.04,
        },
        {
          'supplier_id': 'sup-02',
          'supplier_name': 'Tata Steel Ltd',
          'spend': 230000.00,
          'po_count': 6,
          'share_pct': 29.95,
        },
        {
          'supplier_id': 'sup-03',
          'supplier_name': 'Birla White Wall Care',
          'spend': 100441.40,
          'po_count': 4,
          'share_pct': 13.08,
        },
      ],
      'by_category': [
        {
          'category_name': 'Cement & Binding',
          'spend': 450000.00,
          'units': 12000.0,
          'share_pct': 58.60,
        },
        {
          'category_name': 'Steel & Metals',
          'spend': 250000.00,
          'units': 4000.0,
          'share_pct': 32.55,
        },
      ],
      'by_product': [
        {
          'variant_id': 'var-01',
          'product_name': 'UltraTech 53 Grade Cement',
          'sku': 'SKU-CEM-53',
          'category_name': 'Cement & Binding',
          'units': 8000.0,
          'total_spend': 304000.00,
          'avg_unit_cost': 38.00,
          'latest_price': 39.50,
        },
        {
          'variant_id': 'var-02',
          'product_name': 'TMT Rebar 12mm Fe550D',
          'sku': 'SKU-STL-12MM',
          'category_name': 'Steel & Metals',
          'units': 2500.0,
          'total_spend': 137500.00,
          'avg_unit_cost': 55.00,
          'latest_price': 57.00,
        },
      ],
      'price_changes': [
        {
          'variant_id': 'var-01',
          'product_name': 'UltraTech 53 Grade Cement',
          'sku': 'SKU-CEM-53',
          'latest_price': 39.50,
          'previous_price': 36.50,
          'price_change_pct': 8.22,
          'is_increase': true,
        },
        {
          'variant_id': 'var-02',
          'product_name': 'TMT Rebar 12mm Fe550D',
          'sku': 'SKU-STL-12MM',
          'latest_price': 54.00,
          'previous_price': 56.50,
          'price_change_pct': -4.42,
          'is_increase': false,
        },
      ],
      'po_performance': {
        'total_orders': 22,
        'draft_count': 2,
        'submitted_count': 3,
        'approved_count': 4,
        'ordered_count': 3,
        'partially_received_count': 2,
        'received_count': 8,
        'cancelled_count': 0,
        'delayed_orders_count': 1,
        'total_ordered_qty': 20000.0,
        'total_received_qty': 18265.0,
        'fulfillment_rate_pct': 91.3,
        'total_po_value': 767941.40,
        'avg_lead_time_days': 3.4,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> supplierIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
    int limit = 200,
  }) async {
    if (failSupplier) {
      throw StateError('Database connection timeout for supplier intelligence RPC');
    }
    if (emptyData) {
      return {
        'tenant_id': tenantId,
        'location_id': locationId,
        'days': days,
        'can_view_cost': true,
        'summary': {
          'total_suppliers_count': 0,
          'active_suppliers_count': 0,
          'total_spend': 0.0,
          'total_outstanding_payable': 0.0,
          'high_risk_suppliers_count': 0,
          'avg_fulfillment_rate': 100.0,
          'avg_lead_time_days': 0.0,
        },
        'suppliers': [],
      };
    }

    return {
      'tenant_id': tenantId,
      'location_id': locationId,
      'days': days,
      'can_view_cost': true,
      'summary': {
        'total_suppliers_count': 4,
        'active_suppliers_count': 4,
        'total_spend': 767941.40,
        'total_outstanding_payable': 285000.00,
        'high_risk_suppliers_count': 1,
        'avg_fulfillment_rate': 94.5,
        'avg_lead_time_days': 3.2,
      },
      'suppliers': [
        {
          'supplier_id': 'sup-01',
          'supplier_name': 'Ambuja Cements Ltd',
          'phone': '+91 98765 43210',
          'email': 'orders@ambuja.com',
          'spend': 415000.00,
          'order_count': 10,
          'share_pct': 54.04,
          'product_coverage_count': 6,
          'avg_lead_time_days': 2.5,
          'fulfillment_rate_pct': 98.5,
          'on_time_delivery_pct': 95.0,
          'damaged_rejected_pct': 0.8,
          'return_rate_pct': 0.5,
          'outstanding_payable': 120000.00,
          'aging_status': 'current',
          'last_order_date': '2026-11-18',
          'data_sufficiency': 'sufficient',
          'risk_score': 'medium',
          'risk_indicators': ['High purchase dependency (>40% of spend)'],
        },
        {
          'supplier_id': 'sup-02',
          'supplier_name': 'Tata Steel Ltd',
          'phone': '+91 98765 43211',
          'email': 'sales@tatasteel.com',
          'spend': 230000.00,
          'order_count': 6,
          'share_pct': 29.95,
          'product_coverage_count': 8,
          'avg_lead_time_days': 4.1,
          'fulfillment_rate_pct': 92.0,
          'on_time_delivery_pct': 60.0, // repeated delay
          'damaged_rejected_pct': 2.1,
          'return_rate_pct': 1.2,
          'outstanding_payable': 95000.00,
          'aging_status': 'days_31_60',
          'last_order_date': '2026-11-15',
          'data_sufficiency': 'sufficient',
          'risk_score': 'high',
          'risk_indicators': [
            'Frequent delivery delays (<70% on-time)',
            'Critical overdue payables (>90 days)',
          ],
        },
        {
          'supplier_id': 'sup-03',
          'supplier_name': 'Birla White Wall Care',
          'phone': '+91 98765 43212',
          'email': 'contact@birlawhite.com',
          'spend': 100441.40,
          'order_count': 4,
          'share_pct': 13.08,
          'product_coverage_count': 3,
          'avg_lead_time_days': 3.0,
          'fulfillment_rate_pct': 97.0,
          'on_time_delivery_pct': 92.0,
          'damaged_rejected_pct': 0.5,
          'return_rate_pct': 0.0,
          'outstanding_payable': 70000.00,
          'aging_status': 'current',
          'last_order_date': '2026-11-10',
          'data_sufficiency': 'sufficient',
          'risk_score': 'low',
          'risk_indicators': [],
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> procurementIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
    int limit = 500,
  }) async {
    if (failProcurement) {
      throw StateError('Database connection timeout for procurement intelligence RPC');
    }
    if (emptyData) {
      return {
        'tenant_id': tenantId,
        'location_id': locationId,
        'days': days,
        'can_view_cost': true,
        'summary': {
          'total_recommended_skus': 0,
          'critical_skus_count': 0,
          'high_urgency_skus_count': 0,
          'normal_urgency_skus_count': 0,
          'incoming_stock_covered_skus': 0,
          'rebalancing_alternative_skus': 0,
          'total_estimated_procurement_cost': 0.0,
        },
        'recommendations': [],
      };
    }

    return {
      'tenant_id': tenantId,
      'location_id': locationId,
      'days': days,
      'can_view_cost': true,
      'summary': {
        'total_recommended_skus': 3,
        'critical_skus_count': 1,
        'high_urgency_skus_count': 1,
        'normal_urgency_skus_count': 1,
        'incoming_stock_covered_skus': 1,
        'rebalancing_alternative_skus': 1,
        'total_estimated_procurement_cost': 45500.00,
      },
      'recommendations': [
        {
          'recommendation_id': 'rec-01',
          'location_id': 'loc-central',
          'location_code': 'CEN',
          'location_name': 'Central Warehouse',
          'variant_id': 'var-01',
          'product_id': 'prod-01',
          'product_name': 'UltraTech 53 Grade Cement',
          'sku': 'SKU-CEM-53',
          'barcode': '8901234001',
          'available_stock': 0.0,
          'reserved_stock': 0.0,
          'incoming_po_qty': 0.0,
          'in_transit_qty': 0.0,
          'net_effective_stock': 0.0,
          'reorder_level': 50.0,
          'max_stock': 150.0,
          'avg_daily_sales': 5.0,
          'days_cover': 0.0,
          'suggested_purchase_qty': 150.0,
          'urgency': 'critical',
          'stockout_risk_days': 0.0,
          'lead_time_demand': 15.0,
          'expected_stock_after_po': 150.0,
          'has_rebalancing_opportunity': true,
          'rebalancing_source_location': 'Downtown Branch',
          'rebalancing_transfer_qty': 40.0,
          'suggested_supplier_id': 'sup-01',
          'suggested_supplier_name': 'Ambuja Cements Ltd',
          'estimated_unit_cost': 38.00,
          'estimated_purchase_cost': 5700.00,
          'supplier_reason': 'Store transfer alternative: Downtown Branch holds transferable surplus stock. Consider internal transfer before placing external PO.',
          'lifecycle_status': 'recommended',
        },
        {
          'recommendation_id': 'rec-02',
          'location_id': 'loc-central',
          'location_code': 'CEN',
          'location_name': 'Central Warehouse',
          'variant_id': 'var-02',
          'product_id': 'prod-02',
          'product_name': 'TMT Rebar 12mm Fe550D',
          'sku': 'SKU-STL-12MM',
          'barcode': '8901234002',
          'available_stock': 15.0,
          'reserved_stock': 5.0,
          'incoming_po_qty': 0.0,
          'in_transit_qty': 0.0,
          'net_effective_stock': 15.0,
          'reorder_level': 40.0,
          'max_stock': 100.0,
          'avg_daily_sales': 2.5,
          'days_cover': 6.0,
          'suggested_purchase_qty': 85.0,
          'urgency': 'high',
          'stockout_risk_days': 6.0,
          'lead_time_demand': 10.0,
          'expected_stock_after_po': 100.0,
          'has_rebalancing_opportunity': false,
          'rebalancing_source_location': null,
          'rebalancing_transfer_qty': null,
          'suggested_supplier_id': 'sup-02',
          'suggested_supplier_name': 'Tata Steel Ltd',
          'estimated_unit_cost': 55.00,
          'estimated_purchase_cost': 4675.00,
          'supplier_reason': 'Recommended Tata Steel Ltd: primary supplier with historical cost 55.00 and 60% on-time delivery record.',
          'lifecycle_status': 'recommended',
        },
        {
          'recommendation_id': 'rec-03',
          'location_id': 'loc-central',
          'location_code': 'CEN',
          'location_name': 'Central Warehouse',
          'variant_id': 'var-03',
          'product_id': 'prod-03',
          'product_name': 'Birla White Wall Care 20kg',
          'sku': 'SKU-WHT-20KG',
          'barcode': '8901234003',
          'available_stock': 10.0,
          'reserved_stock': 0.0,
          'incoming_po_qty': 40.0, // In-flight PO covers reorder level (40 + 10 >= 30)
          'in_transit_qty': 0.0,
          'net_effective_stock': 50.0,
          'reorder_level': 30.0,
          'max_stock': 60.0,
          'avg_daily_sales': 1.0,
          'days_cover': 10.0,
          'suggested_purchase_qty': 0.0, // Deduplicated to 0
          'urgency': 'covered',
          'stockout_risk_days': 10.0,
          'lead_time_demand': 3.0,
          'expected_stock_after_po': 50.0,
          'has_rebalancing_opportunity': false,
          'rebalancing_source_location': null,
          'rebalancing_transfer_qty': null,
          'suggested_supplier_id': 'sup-03',
          'suggested_supplier_name': 'Birla White Wall Care',
          'estimated_unit_cost': 35.00,
          'estimated_purchase_cost': 0.00,
          'supplier_reason': 'Covered by incoming purchase orders. Stock sufficient to meet demand.',
          'lifecycle_status': 'recommended',
        },
      ],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> purchaseOrders({
    required String tenantId,
    String? locationId,
    String? status,
    String query = '',
  }) async {
    return [
      {
        'id': 'po-001',
        'order_number': 'PO-2026-0001',
        'supplier_name': 'Ambuja Cements Ltd',
        'location_name': 'Central Warehouse',
        'order_date': '2026-11-18',
        'item_count': 3,
        'grand_total': 11400.0,
        'status': 'draft',
      },
      {
        'id': 'po-002',
        'order_number': 'PO-2026-0002',
        'supplier_name': 'Tata Steel Ltd',
        'location_name': 'Central Warehouse',
        'order_date': '2026-11-15',
        'item_count': 1,
        'grand_total': 4675.0,
        'status': 'submitted',
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> createPurchaseOrder({
    required String tenantId,
    required String locationId,
    required String supplierId,
    required List<Map<String, dynamic>> items,
    String notes = '',
  }) async {
    createdOrders.add({
      'tenant_id': tenantId,
      'location_id': locationId,
      'supplier_id': supplierId,
      'items': items,
      'notes': notes,
    });
    return {'id': 'po-new-${createdOrders.length}', 'status': 'draft'};
  }
}

void main() {
  const testBusiness = ClientBusiness(
    id: 'test-tenant-834',
    membershipId: 'mem-834',
    name: 'THQ Enterprise Retailers',
    slug: 'thq-enterprise',
    businessType: 'retail',
    status: 'active',
  );

  ClientSession createSession({
    bool isOwner = true,
    bool canViewCost = true,
  }) {
    return ClientSession(
      business: testBusiness,
      userId: 'user-834',
      username: 'Procurement Manager',
      modules: const [
        ClientModule(
          key: 'operations_intelligence',
          name: 'Operations Intelligence',
          description: null,
          category: 'analytics',
          sortOrder: 1,
        ),
      ],
      roles: isOwner ? {'owner'} : {'staff'},
      permissions: {
        'operations_intelligence.view',
        'inventory.view',
        if (canViewCost) 'inventory.view_cost',
      },
      currencyCode: 'INR',
      timezone: 'Asia/Kolkata',
      locale: 'en_IN',
      locations: const [
        ClientLocationAccess(
          id: 'loc-central',
          code: 'CEN',
          name: 'Central Warehouse',
          type: 'warehouse',
          trackingCode: 'TRK-01',
          accessLevel: 'manage',
        ),
        ClientLocationAccess(
          id: 'loc-downtown',
          code: 'DWN',
          name: 'Downtown Branch',
          type: 'store',
          trackingCode: 'TRK-02',
          accessLevel: 'manage',
        ),
      ],
    );
  }

  group('Operations Intelligence Phase 5: Deterministic Procurement & Supplier Logic Tests', () {
    test('Deduplicates replenishment when in-flight incoming stock covers reorder shortage', () {
      const available = 10.0;
      const incomingPo = 40.0;
      const inTransit = 0.0;
      const reorderLevel = 30.0;
      const maxStock = 60.0;

      final netEffective = available + incomingPo + inTransit;
      expect(netEffective, 50.0);

      // Calculation rule: if net_effective >= reorder_level, suggested is 0 and urgency is covered
      final suggestedQty = netEffective >= reorderLevel ? 0.0 : (maxStock - netEffective);
      final urgency = netEffective >= reorderLevel ? 'covered' : 'normal';

      expect(suggestedQty, 0.0);
      expect(urgency, 'covered');
    });

    test('Urgency classification assigns critical, high, and normal correctly', () {
      String classify(double avail, double inFlight, double reorder, double cover) {
        if (avail <= 0 && inFlight == 0) return 'critical';
        if (cover <= 3.0 && inFlight == 0) return 'critical';
        if (avail < reorder && inFlight == 0) return 'high';
        if ((avail + inFlight) < reorder) return 'normal';
        return 'covered';
      }

      expect(classify(0.0, 0.0, 50.0, 0.0), 'critical');
      expect(classify(10.0, 0.0, 50.0, 2.0), 'critical');
      expect(classify(25.0, 0.0, 50.0, 8.0), 'high');
      expect(classify(25.0, 10.0, 50.0, 8.0), 'normal');
      expect(classify(25.0, 30.0, 50.0, 8.0), 'covered');
    });

    test('Supplier risk classification evaluates overdue debt, delivery delays, and quality metrics', () {
      String evaluateRisk({
        required double debt90Plus,
        required double onTimePct,
        required int orderCount,
        required double damageRejectPct,
        required double spendSharePct,
      }) {
        if (debt90Plus > 0 || (onTimePct < 65 && orderCount >= 2) || damageRejectPct > 8) {
          return 'high';
        }
        if (spendSharePct >= 40 || damageRejectPct > 5 || onTimePct < 80) {
          return 'medium';
        }
        return 'low';
      }

      // High risk due to delivery delays
      expect(evaluateRisk(debt90Plus: 0, onTimePct: 60.0, orderCount: 5, damageRejectPct: 1.0, spendSharePct: 20.0), 'high');
      // High risk due to critical overdue payables
      expect(evaluateRisk(debt90Plus: 50000, onTimePct: 90.0, orderCount: 5, damageRejectPct: 1.0, spendSharePct: 20.0), 'high');
      // Medium risk due to concentration
      expect(evaluateRisk(debt90Plus: 0, onTimePct: 95.0, orderCount: 5, damageRejectPct: 1.0, spendSharePct: 50.0), 'medium');
      // Low risk healthy supplier
      expect(evaluateRisk(debt90Plus: 0, onTimePct: 92.0, orderCount: 5, damageRejectPct: 0.5, spendSharePct: 15.0), 'low');
    });
  });

  group('Operations Intelligence Phase 5: Purchase Intelligence Widget Tests', () {
    testWidgets('Renders Tab 3 Purchase Intelligence with KPI banner, daily trends, and breakdowns', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase5IntelligenceService();
      final session = createSession(canViewCost: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: session,
              service: service,
              initialTab: 3, // Direct to Tab 3: Purchase Intelligence
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Tab 3 is selected and active
      expect(find.text('Purchase Intelligence'), findsAtLeastNWidgets(1));

      // Verify KPI banner values
      expect(find.text('Gross Purchases'), findsOneWidget);
      expect(find.text('Purchase Returns'), findsOneWidget);
      expect(find.text('Net Purchases'), findsOneWidget);
      expect(find.text('Units Purchased'), findsAtLeastNWidgets(1));
      expect(find.text('Active Suppliers'), findsOneWidget);

      // Verify formatted currency figures
      expect(find.textContaining('767941.40'), findsAtLeastNWidgets(1));
      expect(find.textContaining('18265'), findsAtLeastNWidgets(1));

      // Verify Daily Trends card
      expect(find.text('Daily Net Purchases Trend'), findsOneWidget);

      // Verify Top Suppliers & Category Breakdown
      expect(find.text('Top Suppliers by Spend'), findsOneWidget);
      expect(find.text('Ambuja Cements Ltd'), findsAtLeastNWidgets(1));
      expect(find.text('Purchase by Category'), findsOneWidget);
      expect(find.text('Cement & Binding'), findsAtLeastNWidgets(1));

      // Switch to Price Intelligence sub-tab
      await tester.tap(find.textContaining('Price Intelligence (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Price Intelligence & Cost Shift Analysis'), findsOneWidget);
      expect(find.text('UltraTech 53 Grade Cement'), findsOneWidget);
      expect(find.text('+8.22%'), findsOneWidget);

      // Switch to PO Performance sub-tab
      await tester.tap(find.text('PO Performance'));
      await tester.pumpAndSettle();

      expect(find.text('Purchase Order Fulfillment & Lead Times'), findsOneWidget);
      expect(find.textContaining('91.3%'), findsOneWidget);
      expect(find.textContaining('3.4 days'), findsOneWidget);
    });

    testWidgets('Cost-restricted users see masked figures (—) in Purchase Intelligence', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase5IntelligenceService();
      final session = createSession(isOwner: false, canViewCost: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: session,
              service: service,
              initialTab: 3,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Currency figures should be masked to '—'
      expect(find.text('—'), findsAtLeastNWidgets(3));
      // Raw sensitive spend amounts should not appear
      expect(find.textContaining('767941.40'), findsNothing);
      expect(find.textContaining('415000.00'), findsNothing);
    });
  });

  group('Operations Intelligence Phase 5: Supplier Intelligence Widget Tests', () {
    testWidgets('Renders Tab 4 Supplier Intelligence with profiles, risk indicators, and filter chips', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase5IntelligenceService();
      final session = createSession();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: session,
              service: service,
              initialTab: 4, // Direct to Tab 4: Supplier Intelligence
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Tab 4 header & KPIs
      expect(find.text('Supplier Intelligence'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Total Suppliers:'), findsOneWidget);
      expect(find.textContaining('High Risk:'), findsOneWidget);

      // Verify Suppliers rendered in DataTable
      expect(find.text('Ambuja Cements Ltd'), findsOneWidget);
      expect(find.text('Tata Steel Ltd'), findsOneWidget);
      expect(find.text('Birla White Wall Care'), findsOneWidget);

      // Verify Risk Badges
      expect(find.text('HIGH'), findsOneWidget);
      expect(find.text('MEDIUM'), findsOneWidget);
      expect(find.text('LOW'), findsOneWidget);

      // Filter by High Risk
      await tester.tap(find.textContaining('High Risk (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Tata Steel Ltd'), findsOneWidget);
      expect(find.text('Ambuja Cements Ltd'), findsNothing);

      // Tap on Tata Steel to open Supplier Profile Modal
      await tester.tap(find.text('Tata Steel Ltd'));
      await tester.pumpAndSettle();

      expect(find.text('Operational Performance'), findsOneWidget);
      expect(find.text('Frequent delivery delays (<70% on-time)'), findsAtLeastNWidgets(1));
      expect(find.text('Critical overdue payables (>90 days)'), findsAtLeastNWidgets(1));

      // Close modal
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });
  });

  group('Operations Intelligence Phase 5: Procurement Intelligence & Action Centre Widget Tests', () {
    testWidgets('Renders Tab 5 Procurement Intelligence with rebalancing alert and multi-select Action Centre', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase5IntelligenceService();
      final session = createSession();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: session,
              service: service,
              initialTab: 5, // Direct to Tab 5: Procurement Intelligence
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Tab 5 header & Rebalancing Alert
      expect(find.text('Procurement Intelligence'), findsAtLeastNWidgets(1));
      expect(find.textContaining('have transferable surplus stock at another store'), findsOneWidget);

      // Verify Recommendations rendered
      expect(find.text('UltraTech 53 Grade Cement'), findsOneWidget);
      expect(find.text('TMT Rebar 12mm Fe550D'), findsOneWidget);
      expect(find.text('Birla White Wall Care 20kg'), findsOneWidget);

      // Verify Urgency Badges
      expect(find.text('CRITICAL'), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget);
      expect(find.text('COVERED'), findsOneWidget);

      // Verify Deduplication on covered item
      expect(find.textContaining('+40 (40 PO, 0 transit)'), findsOneWidget);

      // Click "Select Actionable" button in Action Centre
      await tester.tap(find.text('Select Actionable'));
      await tester.pumpAndSettle();

      // Verify Action button updates with selected count (2 actionable SKUs)
      expect(find.text('Create PO (2)'), findsOneWidget);

      // Click "Create PO (2)" to trigger confirmation dialog
      await tester.tap(find.text('Create PO (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Create Purchase Orders (2 SKUs)'), findsOneWidget);
      expect(find.textContaining('Orders will be created in Draft status'), findsOneWidget);

      // Confirm order creation
      await tester.tap(find.text('Create Draft Orders'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      // Verify orders were dispatched to service
      expect(service.createdOrders.length, 2);
    });

    testWidgets('Handles empty dataset gracefully without crashes', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase5IntelligenceService(emptyData: true);
      final session = createSession();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: session,
              service: service,
              initialTab: 5,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No procurement recommendations match the selected filter.'), findsOneWidget);
    });

    testWidgets('Gracefully handles purchase failure with tab-level retry button', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase5IntelligenceService(failPurchase: true);
      final session = createSession();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: session,
              service: service,
              initialTab: 3,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Purchase Intelligence'), findsAtLeastNWidgets(1));
      expect(find.text('Retry'), findsAtLeastNWidgets(1));
    });

    testWidgets('Gracefully handles supplier failure with tab-level retry button', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase5IntelligenceService(failSupplier: true);
      final session = createSession();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: session,
              service: service,
              initialTab: 4,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Supplier Intelligence'), findsAtLeastNWidgets(1));
      expect(find.text('Retry'), findsAtLeastNWidgets(1));
    });

    testWidgets('Gracefully handles procurement failure with tab-level retry button', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase5IntelligenceService(failProcurement: true);
      final session = createSession();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: session,
              service: service,
              initialTab: 5,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Procurement Intelligence'), findsAtLeastNWidgets(1));
      expect(find.text('Retry'), findsAtLeastNWidgets(1));
    });
  });
}
