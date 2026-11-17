import '../operations_intelligence_collector.dart';
import '../operations_intelligence_models.dart';
import '../operations_intelligence_repository.dart';

class InventoryIntelligenceEngine implements IntelligenceCollector {
  @override
  IntelligenceEngineType get engineType => IntelligenceEngineType.inventory;

  @override
  Future<List<InsightRecord>> collect(
    OperationsIntelligenceContext context,
    OperationsIntelligenceRepository repository,
  ) async {
    final items = await repository.getInventoryIntelligence(
      tenantId: context.tenantId,
      locationId: context.locationId,
      days: context.periodDays,
      limit: 1000,
    );

    final insights = <InsightRecord>[];

    // 1. Stockout & Low Stock Alerts
    final outOfStockItems = items.where((i) => i['status'] == 'out_of_stock').toList();
    if (outOfStockItems.isNotEmpty) {
      final names = outOfStockItems.take(3).map((i) => i['product_name']).join(', ');
      insights.add(
        InsightRecord(
          id: 'ins-inv-out-of-stock-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'stockout_critical',
          severity: InsightSeverity.critical,
          priority: InsightPriority.urgent,
          title: 'Stockout Alert: ${outOfStockItems.length} SKUs completely out of stock',
          description:
              'Active products with zero available stock include: $names. Immediate purchase order or inter-branch transfer required to prevent sales loss.',
          evidence: InsightEvidence(
            sampleCount: outOfStockItems.length,
            metricUnit: 'SKUs',
            breakdown: {
              'sample_products': outOfStockItems.take(5).toList(),
            },
          ),
          sourceReferences: outOfStockItems.take(5).map((i) => InsightSourceReference(
            entityType: 'product_variant',
            entityId: i['variant_id']?.toString() ?? '',
            entityNumber: i['sku']?.toString(),
          )).toList(),
          dataFreshness: context.now,
          status: InsightStatus.newInsight,
          createdAt: context.now,
          updatedAt: context.now,
        ),
      );
    }

    // 2. Dead Stock Capital Lockup
    final deadStockItems = items.where((i) => i['status'] == 'dead_stock').toList();
    if (deadStockItems.isNotEmpty) {
      double totalLockedValue = 0.0;
      for (final d in deadStockItems) {
        totalLockedValue += (d['stock_value'] as num?)?.toDouble() ?? 0.0;
      }
      insights.add(
        InsightRecord(
          id: 'ins-inv-dead-stock-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'dead_stock_lockup',
          severity: InsightSeverity.warning,
          priority: InsightPriority.medium,
          title: 'Dead Stock: ${deadStockItems.length} SKUs locking up ${totalLockedValue.toStringAsFixed(2)}',
          description:
              'Identified ${deadStockItems.length} product variants with positive stock balances that have recorded zero sales in the past 90+ days. Consider discounting, vendor return, or clearance promotions.',
          evidence: InsightEvidence(
            currentValue: totalLockedValue,
            sampleCount: deadStockItems.length,
            metricUnit: 'INR',
          ),
          dataFreshness: context.now,
          status: InsightStatus.newInsight,
          createdAt: context.now,
          updatedAt: context.now,
        ),
      );
    }

    // 3. Fast Moving ABC Class A Under-Stocked
    final fastMovingAtRisk = items.where((i) {
      final isClassA = i['abc_class'] == 'A';
      final coverDays = (i['days_cover'] as num?)?.toDouble() ?? 999.0;
      return isClassA && coverDays < 3.0 && coverDays > 0.0;
    }).toList();

    if (fastMovingAtRisk.isNotEmpty) {
      final names = fastMovingAtRisk.take(3).map((i) => i['product_name']).join(', ');
      insights.add(
        InsightRecord(
          id: 'ins-inv-class-a-depletion-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'abc_class_a_risk',
          severity: InsightSeverity.critical,
          priority: InsightPriority.high,
          title: 'Rapid Depletion on Class A Products: $names',
          description:
              'Top-selling revenue drivers (Class A Pareto items) have under 3 days of stock cover remaining. Place expedited replenishment orders.',
          evidence: InsightEvidence(
            sampleCount: fastMovingAtRisk.length,
            metricUnit: 'SKUs',
            breakdown: {
              'at_risk_products': fastMovingAtRisk.take(5).toList(),
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
