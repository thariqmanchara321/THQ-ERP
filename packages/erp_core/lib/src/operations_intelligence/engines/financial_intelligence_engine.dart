import '../operations_intelligence_collector.dart';
import '../operations_intelligence_models.dart';
import '../operations_intelligence_repository.dart';

class FinancialIntelligenceEngine implements IntelligenceCollector {
  @override
  IntelligenceEngineType get engineType => IntelligenceEngineType.financial;

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

    // 1. Working Capital Liquidity Cushion
    final currentAssets = summary.receivables + summary.inventoryValue;
    final currentLiabilities = summary.payables;
    if (currentLiabilities > 0) {
      final currentRatio = currentAssets / currentLiabilities;
      if (currentRatio < 1.2) {
        insights.add(
          InsightRecord(
            id: 'ins-fin-liquidity-${context.tenantId}',
            tenantId: context.tenantId,
            locationId: context.locationId,
            engine: engineType,
            category: 'liquidity_warning',
            severity: InsightSeverity.warning,
            priority: InsightPriority.high,
            title: 'Tight Working Capital: Ratio at ${currentRatio.toStringAsFixed(2)}x',
            description:
                'Short-term obligations (payables ${summary.payables.toStringAsFixed(2)}) are close to total liquid assets (receivables + inventory ${currentAssets.toStringAsFixed(2)}). Accelerate customer collections to maintain safety margin.',
            evidence: InsightEvidence(
              currentValue: currentRatio,
              threshold: 1.5,
              metricUnit: 'ratio',
              breakdown: {
                'current_assets': currentAssets,
                'payables': summary.payables,
                'receivables': summary.receivables,
                'inventory_value': summary.inventoryValue,
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

    // 2. Cash Conversion Cycle (CCC) Estimate
    // DSO = (Receivables / Net Sales) * days
    // DPO = (Payables / (COGS or Purchases)) * days
    // DIO = (Inventory / COGS) * days
    if (summary.netSales > 0 && summary.grossProfit > 0) {
      final cogs = summary.netSales - summary.grossProfit;
      if (cogs > 0) {
        final dso = (summary.receivables / summary.netSales) * context.periodDays;
        final dio = (summary.inventoryValue / cogs) * context.periodDays;
        final dpo = (summary.payables / cogs) * context.periodDays;
        final ccc = dio + dso - dpo;

        if (ccc > 60.0) {
          insights.add(
            InsightRecord(
              id: 'ins-fin-ccc-${context.tenantId}',
              tenantId: context.tenantId,
              locationId: context.locationId,
              engine: engineType,
              category: 'cash_conversion_cycle',
              severity: InsightSeverity.info,
              priority: InsightPriority.medium,
              title: 'Extended Cash Conversion Cycle: ${ccc.toStringAsFixed(0)} days',
              description:
                  'It takes an estimated ${ccc.toStringAsFixed(0)} days to convert inventory investments into realized cash flows (DIO: ${dio.toStringAsFixed(0)}d, DSO: ${dso.toStringAsFixed(0)}d, DPO: ${dpo.toStringAsFixed(0)}d). Tightening credit days or increasing stock turns will free cash.',
              evidence: InsightEvidence(
                currentValue: ccc,
                threshold: 45.0,
                metricUnit: 'days',
                breakdown: {
                  'dio_days': dio,
                  'dso_days': dso,
                  'dpo_days': dpo,
                  'ccc_days': ccc,
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
    }

    // 3. Margin Compression Alert
    if (summary.netSales > 0 && summary.grossMarginPct < 15.0) {
      insights.add(
        InsightRecord(
          id: 'ins-fin-low-margin-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'margin_compression',
          severity: InsightSeverity.warning,
          priority: InsightPriority.high,
          title: 'Low Gross Margin: ${summary.grossMarginPct.toStringAsFixed(1)}%',
          description:
              'Gross profit margin (${summary.grossProfit.toStringAsFixed(2)}) is below the recommended 15% threshold. Review price lists, supplier purchase costs, or discount concession policies.',
          evidence: InsightEvidence(
            currentValue: summary.grossMarginPct,
            threshold: 15.0,
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
