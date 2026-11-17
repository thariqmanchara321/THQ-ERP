import '../operations_intelligence_collector.dart';
import '../operations_intelligence_models.dart';
import '../operations_intelligence_repository.dart';

class ExecutiveHealthEngine implements IntelligenceCollector {
  @override
  IntelligenceEngineType get engineType => IntelligenceEngineType.executiveHealth;

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

    // Health Score Insight
    final score = summary.compositeHealthScore;
    if (score < 60.0) {
      insights.add(
        InsightRecord(
          id: 'ins-exec-health-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'health_alert',
          severity: InsightSeverity.critical,
          priority: InsightPriority.urgent,
          title: 'Executive Alert: Business Health Index at ${score.toStringAsFixed(1)}/100',
          description:
              'Composite business health has dropped below threshold. Contributing factors include low gross margin (${summary.grossMarginPct.toStringAsFixed(1)}%), overdue receivables (${summary.overdueReceivables.toStringAsFixed(2)}), or elevated stockout risks (${summary.outOfStockCount} SKUs).',
          evidence: InsightEvidence(
            currentValue: score,
            threshold: 75.0,
            metricUnit: 'score',
            breakdown: {
              'gross_margin_pct': summary.grossMarginPct,
              'out_of_stock_count': summary.outOfStockCount,
              'overdue_receivables': summary.overdueReceivables,
              'expenses': summary.expenses,
            },
          ),
          dataFreshness: context.now,
          status: InsightStatus.newInsight,
          createdAt: context.now,
          updatedAt: context.now,
        ),
      );
    } else if (score >= 85.0) {
      insights.add(
        InsightRecord(
          id: 'ins-exec-strong-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'health_status',
          severity: InsightSeverity.opportunity,
          priority: InsightPriority.low,
          title: 'Strong Executive Health: Index at ${score.toStringAsFixed(1)}/100',
          description:
              'Operational metrics are robust across sales growth, healthy gross margins (${summary.grossMarginPct.toStringAsFixed(1)}%), controlled expenses, and minimal stockout risks.',
          evidence: InsightEvidence(
            currentValue: score,
            threshold: 80.0,
            metricUnit: 'score',
          ),
          dataFreshness: context.now,
          status: InsightStatus.newInsight,
          createdAt: context.now,
          updatedAt: context.now,
        ),
      );
    }

    // Expense Ratio Check
    if (summary.netSales > 0 && (summary.expenses / summary.netSales) > 0.35) {
      final expRatio = (summary.expenses / summary.netSales) * 100.0;
      insights.add(
        InsightRecord(
          id: 'ins-exec-exp-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'operating_expense_ratio',
          severity: InsightSeverity.warning,
          priority: InsightPriority.high,
          title: 'High Operating Expense Ratio: ${expRatio.toStringAsFixed(1)}% of Revenue',
          description:
              'Operating expenses of ${summary.expenses.toStringAsFixed(2)} consume ${expRatio.toStringAsFixed(1)}% of net sales (${summary.netSales.toStringAsFixed(2)}). Typical benchmark is below 25-30%.',
          evidence: InsightEvidence(
            currentValue: expRatio,
            threshold: 30.0,
            metricUnit: '%',
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
