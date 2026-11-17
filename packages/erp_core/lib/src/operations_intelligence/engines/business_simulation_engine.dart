import 'dart:math' as math;
import '../operations_intelligence_collector.dart';
import '../operations_intelligence_models.dart';
import '../operations_intelligence_repository.dart';

/// In-memory simulation models for executive decision support.
/// INVARIANT: Never writes to or mutates live accounting ledgers.
class BusinessSimulationEngine implements IntelligenceCollector {
  @override
  IntelligenceEngineType get engineType => IntelligenceEngineType.simulation;

  /// Pricing change simulation:
  /// Evaluates revenue, volume, and profit under price elasticity of demand:
  /// $E_d = \frac{\% \Delta Q}{\% \Delta P}$
  /// $\% \Delta Q = E_d \cdot \% \Delta P$
  static Map<String, dynamic> simulatePricingChange({
    required double baseSellingPrice,
    required double baseCostPrice,
    required double baseVolume,
    required double priceChangePercent, // e.g. +5% or -10%
    double priceElasticity = -1.2, // standard moderately elastic demand
  }) {
    if (baseSellingPrice <= 0 || baseVolume <= 0) {
      return {'error': 'Invalid baseline pricing parameters'};
    }

    final newSellingPrice = baseSellingPrice * (1.0 + (priceChangePercent / 100.0));
    final volumeChangePercent = priceElasticity * priceChangePercent;
    final newVolume = math.max(0.0, baseVolume * (1.0 + (volumeChangePercent / 100.0)));

    final baseRevenue = baseSellingPrice * baseVolume;
    final baseCost = baseCostPrice * baseVolume;
    final baseProfit = baseRevenue - baseCost;
    final baseMarginPct = baseRevenue > 0 ? (baseProfit / baseRevenue) * 100.0 : 0.0;

    final newRevenue = newSellingPrice * newVolume;
    final newCost = baseCostPrice * newVolume;
    final newProfit = newRevenue - newCost;
    final newMarginPct = newRevenue > 0 ? (newProfit / newRevenue) * 100.0 : 0.0;

    return {
      'base_price': baseSellingPrice,
      'new_price': newSellingPrice,
      'price_change_pct': priceChangePercent,
      'base_volume': baseVolume,
      'new_volume': newVolume,
      'volume_change_pct': volumeChangePercent,
      'base_revenue': baseRevenue,
      'new_revenue': newRevenue,
      'revenue_delta': newRevenue - baseRevenue,
      'base_profit': baseProfit,
      'new_profit': newProfit,
      'profit_delta': newProfit - baseProfit,
      'base_margin_pct': baseMarginPct,
      'new_margin_pct': newMarginPct,
      'is_profitable_change': newProfit > baseProfit,
    };
  }

  /// Bulk Purchase vs Carrying Cost Trade-Off Simulation:
  /// Compares savings from supplier bulk discount against additional annual inventory holding costs.
  static Map<String, dynamic> simulateBulkPurchase({
    required double standardUnitCost,
    required double bulkUnitCost,
    required double orderQuantity,
    required double annualHoldingCostRate, // e.g. 0.18 (18% per year)
    required double estimatedMonthsToSell,
  }) {
    final discountSavings = (standardUnitCost - bulkUnitCost) * orderQuantity;
    final averageInventoryValue = (bulkUnitCost * orderQuantity) / 2.0;
    final annualHoldingCost = averageInventoryValue * annualHoldingCostRate;
    final periodHoldingCost = annualHoldingCost * (estimatedMonthsToSell / 12.0);
    final netBenefit = discountSavings - periodHoldingCost;

    return {
      'standard_cost': standardUnitCost,
      'bulk_cost': bulkUnitCost,
      'order_quantity': orderQuantity,
      'discount_savings': discountSavings,
      'carrying_cost': periodHoldingCost,
      'net_benefit': netBenefit,
      'is_economically_viable': netBenefit > 0,
    };
  }

  /// Credit Policy Adjustment Simulation:
  /// Evaluates impact of tightening or loosening credit payment terms (days).
  static Map<String, dynamic> simulateCreditPolicy({
    required double currentAnnualCreditSales,
    required double currentAverageCollectionDays,
    required double proposedAverageCollectionDays,
    double badDebtRate = 0.02, // 2%
    double costOfCapitalRate = 0.12, // 12% annual cost of debt/working capital
  }) {
    final currentReceivables = (currentAnnualCreditSales / 365.0) * currentAverageCollectionDays;
    final proposedReceivables = (currentAnnualCreditSales / 365.0) * proposedAverageCollectionDays;
    final workingCapitalReleased = currentReceivables - proposedReceivables;
    final annualCapitalCostSavings = workingCapitalReleased * costOfCapitalRate;

    return {
      'current_dso': currentAverageCollectionDays,
      'proposed_dso': proposedAverageCollectionDays,
      'current_receivables': currentReceivables,
      'proposed_receivables': proposedReceivables,
      'working_capital_released': workingCapitalReleased,
      'annual_capital_savings': annualCapitalCostSavings,
    };
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

    // Simulate 3% price optimization scenario if net sales exist
    if (summary.netSales > 0 && summary.grossProfit > 0) {
      final sim = simulatePricingChange(
        baseSellingPrice: 100.0,
        baseCostPrice: 100.0 * (1.0 - (summary.grossMarginPct / 100.0)),
        baseVolume: summary.netSales / 100.0,
        priceChangePercent: 3.0,
        priceElasticity: -0.8, // inelastic retail elasticity
      );

      final profitDelta = sim['profit_delta'] as double? ?? 0.0;
      if (profitDelta > 0) {
        insights.add(
          InsightRecord(
            id: 'ins-sim-pricing-opt-${context.tenantId}',
            tenantId: context.tenantId,
            locationId: context.locationId,
            engine: engineType,
            category: 'pricing_simulation',
            severity: InsightSeverity.opportunity,
            priority: InsightPriority.medium,
            title: 'Pricing Simulation: +3% Price Adjustment could yield +${profitDelta.toStringAsFixed(2)} profit',
            description:
                'Decision simulation shows that a modest 3% price adjustment across top non-commodity products could generate ${profitDelta.toStringAsFixed(2)} in additional gross margin, accounting for estimated volume elasticity.',
            evidence: InsightEvidence(
              currentValue: profitDelta,
              metricUnit: 'INR',
              breakdown: sim,
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
