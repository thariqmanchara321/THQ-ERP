import 'dart:math' as math;
import '../operations_intelligence_collector.dart';
import '../operations_intelligence_models.dart';
import '../operations_intelligence_repository.dart';

class ProcurementIntelligenceEngine implements IntelligenceCollector {
  @override
  IntelligenceEngineType get engineType => IntelligenceEngineType.procurement;

  /// Calculates Economic Order Quantity (EOQ): sqrt((2 * annualDemand * orderCost) / holdingCost)
  static double calculateEoq({
    required double annualDemand,
    double fixedOrderCost = 500.0,
    double holdingCostPerUnitPerYear = 50.0,
  }) {
    if (annualDemand <= 0 || fixedOrderCost <= 0 || holdingCostPerUnitPerYear <= 0) {
      return 0.0;
    }
    return math.sqrt((2.0 * annualDemand * fixedOrderCost) / holdingCostPerUnitPerYear);
  }

  @override
  Future<List<InsightRecord>> collect(
    OperationsIntelligenceContext context,
    OperationsIntelligenceRepository repository,
  ) async {
    final inventory = await repository.getInventoryIntelligence(
      tenantId: context.tenantId,
      locationId: context.locationId,
      days: context.periodDays,
      limit: 1000,
    );

    final insights = <InsightRecord>[];

    // Identify items needing reorder
    final reorderItems = inventory.where((i) {
      final status = i['status']?.toString();
      final reorderQty = (i['suggested_reorder'] as num?)?.toDouble() ?? 0.0;
      return (status == 'low_stock' || status == 'out_of_stock') && reorderQty > 0;
    }).toList();

    if (reorderItems.isNotEmpty) {
      final names = reorderItems.take(3).map((i) => i['product_name']).join(', ');
      insights.add(
        InsightRecord(
          id: 'ins-proc-reorder-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'reorder_recommendation',
          severity: InsightSeverity.opportunity,
          priority: InsightPriority.high,
          title: 'Replenishment Required: ${reorderItems.length} SKUs ready for PO ($names)',
          description:
              'Automated reorder models calculated replenishment needs for ${reorderItems.length} SKUs to prevent stockout and maintain safety buffers. Generate Purchase Orders directly from Action Centre.',
          evidence: InsightEvidence(
            sampleCount: reorderItems.length,
            metricUnit: 'SKUs',
            breakdown: {
              'sample_reorders': reorderItems.take(5).map((i) {
                final netSold = (i['net_sold_qty'] as num?)?.toDouble() ?? 0.0;
                final annualDemand = (netSold / context.periodDays) * 365.0;
                final eoq = calculateEoq(annualDemand: annualDemand);
                return {
                  'variant_id': i['variant_id'],
                  'product_name': i['product_name'],
                  'suggested_reorder': i['suggested_reorder'],
                  'eoq_estimate': eoq.round(),
                };
              }).toList(),
            },
          ),
          dataFreshness: context.now,
          status: InsightStatus.newInsight,
          createdAt: context.now,
          updatedAt: context.now,
        ),
      );
    }

    return insights;
  }
}
