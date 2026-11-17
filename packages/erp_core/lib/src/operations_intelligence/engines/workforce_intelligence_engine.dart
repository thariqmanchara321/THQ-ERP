import '../operations_intelligence_collector.dart';
import '../operations_intelligence_models.dart';
import '../operations_intelligence_repository.dart';

class WorkforceIntelligenceEngine implements IntelligenceCollector {
  @override
  IntelligenceEngineType get engineType => IntelligenceEngineType.workforce;

  @override
  Future<List<InsightRecord>> collect(
    OperationsIntelligenceContext context,
    OperationsIntelligenceRepository repository,
  ) async {
    final summary = await repository.getExecutiveSummary(
      tenantId: context.tenantId,
      locationId: context.locationId,
      days: context.periodDays,
    );

    final insights = <InsightRecord>[];

    // Transaction Throughput Efficiency
    if (summary.orderCount > 0 && context.periodDays > 0) {
      final avgOrdersPerDay = summary.orderCount / context.periodDays;
      insights.add(
        InsightRecord(
          id: 'ins-wf-throughput-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'cashier_throughput',
          severity: InsightSeverity.info,
          priority: InsightPriority.low,
          title: 'Workforce Velocity: ${avgOrdersPerDay.toStringAsFixed(1)} daily transactions',
          description:
              'Store staff processed ${summary.orderCount} total customer checkouts across the period with an average basket value of ${summary.averageOrderValue.toStringAsFixed(2)}.',
          evidence: InsightEvidence(
            currentValue: avgOrdersPerDay,
            sampleCount: summary.orderCount,
            metricUnit: 'orders/day',
            breakdown: {
              'total_orders': summary.orderCount,
              'average_basket_value': summary.averageOrderValue,
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
