import '../operations_intelligence_collector.dart';
import '../operations_intelligence_models.dart';
import '../operations_intelligence_repository.dart';

class SalesIntelligenceEngine implements IntelligenceCollector {
  @override
  IntelligenceEngineType get engineType => IntelligenceEngineType.sales;

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

    // High Return Rate Warning
    if (summary.grossSales > 0 && (summary.salesReturns / summary.grossSales) > 0.08) {
      final retPct = (summary.salesReturns / summary.grossSales) * 100.0;
      insights.add(
        InsightRecord(
          id: 'ins-sales-returns-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'sales_returns',
          severity: InsightSeverity.warning,
          priority: InsightPriority.high,
          title: 'Elevated Sales Return Rate: ${retPct.toStringAsFixed(1)}%',
          description:
              'Sales returns of ${summary.salesReturns.toStringAsFixed(2)} represent ${retPct.toStringAsFixed(1)}% of gross sales (${summary.grossSales.toStringAsFixed(2)}). Investigate product quality or cashier billing errors.',
          evidence: InsightEvidence(
            currentValue: retPct,
            threshold: 5.0,
            metricUnit: '%',
            breakdown: {
              'gross_sales': summary.grossSales,
              'returns': summary.salesReturns,
            },
          ),
          dataFreshness: context.now,
          status: InsightStatus.newInsight,
          createdAt: context.now,
          updatedAt: context.now,
        ),
      );
    }

    // Top Selling Concentration
    if (summary.topProducts.isNotEmpty && summary.netSales > 0) {
      final top1 = summary.topProducts.first;
      final top1Rev = (top1['revenue'] as num?)?.toDouble() ?? 0.0;
      final top1Share = (top1Rev / summary.netSales) * 100.0;
      if (top1Share > 35.0) {
        insights.add(
          InsightRecord(
            id: 'ins-sales-top-conc-${context.tenantId}',
            tenantId: context.tenantId,
            locationId: context.locationId,
            engine: engineType,
            category: 'revenue_concentration',
            severity: InsightSeverity.info,
            priority: InsightPriority.medium,
            title: 'High Product Revenue Concentration: ${top1['product_name']}',
            description:
                'Single SKU ${top1['product_name']} accounts for ${top1Share.toStringAsFixed(1)}% of total net sales (${top1Rev.toStringAsFixed(2)}). Ensure supply continuity to avoid major revenue disruption.',
            evidence: InsightEvidence(
              currentValue: top1Share,
              threshold: 30.0,
              metricUnit: '%',
              breakdown: {
                'product_name': top1['product_name'],
                'sku': top1['sku'],
                'revenue': top1Rev,
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

    // Peak Hour Opportunity Detection
    if (summary.hourlyDistribution.isNotEmpty) {
      Map<String, dynamic>? peakHour;
      double maxRev = 0.0;
      for (final h in summary.hourlyDistribution) {
        final r = (h['revenue'] as num?)?.toDouble() ?? 0.0;
        if (r > maxRev) {
          maxRev = r;
          peakHour = h;
        }
      }
      if (peakHour != null && maxRev > 0) {
        final hr = (peakHour['hour'] as num?)?.toInt() ?? 0;
        final hrFormatted = '${hr.toString().padLeft(2, '0')}:00 - ${(hr + 1).toString().padLeft(2, '0')}:00';
        insights.add(
          InsightRecord(
            id: 'ins-sales-peak-hour-${context.tenantId}',
            tenantId: context.tenantId,
            locationId: context.locationId,
            engine: engineType,
            category: 'peak_traffic',
            severity: InsightSeverity.opportunity,
            priority: InsightPriority.low,
            title: 'Peak Sales Window: $hrFormatted',
            description:
                'Store registers peak transaction volume and revenue (${maxRev.toStringAsFixed(2)}) between $hrFormatted. Ensure full cashier lane coverage and express checkouts during this window.',
            evidence: InsightEvidence(
              currentValue: maxRev,
              metricUnit: 'INR',
              breakdown: peakHour,
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
