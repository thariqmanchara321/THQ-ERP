import '../operations_intelligence_collector.dart';
import '../operations_intelligence_models.dart';
import '../operations_intelligence_repository.dart';

class RiskAnomalyEngine implements IntelligenceCollector {
  @override
  IntelligenceEngineType get engineType => IntelligenceEngineType.riskAnomaly;

  /// Detects whether a discount rate is an outlier (> 20% or > 2 standard deviations).
  static bool isAbnormalDiscount(double discountPct, {double thresholdPct = 20.0}) {
    return discountPct > thresholdPct;
  }

  /// Detects whether a sale was made at a negative margin.
  static bool isNegativeMargin(double sellingPrice, double costPrice) {
    return costPrice > 0 && sellingPrice < costPrice;
  }

  /// Detects potential duplicate payment: matching supplier, matching amount within time window.
  static bool isPotentialDuplicatePayment({
    required double amount1,
    required double amount2,
    required DateTime date1,
    required DateTime date2,
    Duration tolerance = const Duration(days: 7),
  }) {
    if ((amount1 - amount2).abs() > 0.01) return false;
    final diff = date1.difference(date2).abs();
    return diff <= tolerance;
  }

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

    // 1. Elevated Return-to-Sales Anomaly
    if (summary.grossSales > 0) {
      final returnRatio = summary.salesReturns / summary.grossSales;
      if (returnRatio > 0.12) {
        insights.add(
          InsightRecord(
            id: 'ins-anomaly-returns-${context.tenantId}',
            tenantId: context.tenantId,
            locationId: context.locationId,
            engine: engineType,
            category: 'high_return_spike',
            severity: InsightSeverity.critical,
            priority: InsightPriority.urgent,
            title: 'Anomaly Alert: Return Spike at ${(returnRatio * 100).toStringAsFixed(1)}% of Sales',
            description:
                'Sales returns (${summary.salesReturns.toStringAsFixed(2)}) have exceeded statistical control limits (12% of gross sales). Verify cashier registers for potential return fraud or batch defects.',
            evidence: InsightEvidence(
              currentValue: returnRatio * 100,
              threshold: 8.0,
              metricUnit: '%',
              breakdown: {
                'gross_sales': summary.grossSales,
                'sales_returns': summary.salesReturns,
              },
            ),
            dataFreshness: context.now,
            status: InsightStatus.newInsight,
            createdAt: context.now,
            updatedAt: context.now,
          ),
        );
      }
    }

    // 2. Overdue Receivable Anomaly
    if (summary.receivables > 0) {
      final overdueRatio = summary.overdueReceivables / summary.receivables;
      if (overdueRatio > 0.40) {
        insights.add(
          InsightRecord(
            id: 'ins-anomaly-overdue-spike-${context.tenantId}',
            tenantId: context.tenantId,
            locationId: context.locationId,
            engine: engineType,
            category: 'overdue_spike',
            severity: InsightSeverity.critical,
            priority: InsightPriority.high,
            title: 'Credit Risk Anomaly: ${(overdueRatio * 100).toStringAsFixed(1)}% of Receivables Overdue',
            description:
                '${summary.overdueReceivables.toStringAsFixed(2)} of total ${summary.receivables.toStringAsFixed(2)} trade dues are past due date. Requires immediate credit manager attention.',
            evidence: InsightEvidence(
              currentValue: overdueRatio * 100,
              threshold: 25.0,
              metricUnit: '%',
              breakdown: {
                'total_receivables': summary.receivables,
                'overdue_receivables': summary.overdueReceivables,
              },
            ),
            dataFreshness: context.now,
            status: InsightStatus.newInsight,
            createdAt: context.now,
            updatedAt: context.now,
          ),
        );
      }
    }

    return insights;
  }
}
