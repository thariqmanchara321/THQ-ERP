import 'dart:math' as math;
import '../operations_intelligence_collector.dart';
import '../operations_intelligence_models.dart';
import '../operations_intelligence_repository.dart';

/// Statistical forecasting models and accuracy evaluators.
class PredictiveModels {
  /// Simple Moving Average (SMA)
  static double simpleMovingAverage(List<double> values, int window) {
    if (values.isEmpty || window <= 0) return 0.0;
    final count = math.min(values.length, window);
    final slice = values.sublist(values.length - count);
    final sum = slice.reduce((a, b) => a + b);
    return sum / count;
  }

  /// Exponential Moving Average (EMA): $EMA_t = \alpha \cdot Y_t + (1 - \alpha) \cdot EMA_{t-1}$
  static double exponentialMovingAverage(List<double> values, {double alpha = 0.3}) {
    if (values.isEmpty) return 0.0;
    double ema = values.first;
    for (int i = 1; i < values.length; i++) {
      ema = (alpha * values[i]) + ((1.0 - alpha) * ema);
    }
    return ema;
  }

  /// Linear Regression: $y = mx + b$
  /// Returns `[slope, intercept, rSquared]`
  static List<double> linearRegression(List<double> values) {
    final n = values.length;
    if (n < 2) return [0.0, values.isNotEmpty ? values.first : 0.0, 1.0];

    double sumX = 0.0;
    double sumY = 0.0;
    double sumXY = 0.0;
    double sumXX = 0.0;
    double sumYY = 0.0;

    for (int i = 0; i < n; i++) {
      final x = i.toDouble();
      final y = values[i];
      sumX += x;
      sumY += y;
      sumXY += (x * y);
      sumXX += (x * x);
      sumYY += (y * y);
    }

    final denominator = (n * sumXX) - (sumX * sumX);
    if (denominator == 0) return [0.0, sumY / n, 0.0];

    final slope = ((n * sumXY) - (sumX * sumY)) / denominator;
    final intercept = (sumY - (slope * sumX)) / n;

    // R-squared
    final ssTot = sumYY - ((sumY * sumY) / n);
    final ssRes = sumYY - (intercept * sumY) - (slope * sumXY);
    final rSquared = ssTot != 0 ? math.max(0.0, 1.0 - (ssRes / ssTot)) : 1.0;

    return [slope, intercept, rSquared];
  }

  /// Forecast next step using linear regression
  static double forecastNextLinear(List<double> values, int stepAhead) {
    final reg = linearRegression(values);
    final slope = reg[0];
    final intercept = reg[1];
    final nextX = values.length - 1 + stepAhead;
    return math.max(0.0, (slope * nextX) + intercept);
  }

  /// Mean Absolute Error (MAE)
  static double calculateMae(List<double> actual, List<double> predicted) {
    if (actual.isEmpty || actual.length != predicted.length) return 0.0;
    double errorSum = 0.0;
    for (int i = 0; i < actual.length; i++) {
      errorSum += (actual[i] - predicted[i]).abs();
    }
    return errorSum / actual.length;
  }

  /// Mean Absolute Percentage Error (MAPE)
  static double calculateMape(List<double> actual, List<double> predicted) {
    if (actual.isEmpty || actual.length != predicted.length) return 0.0;
    double errorSum = 0.0;
    int validCount = 0;
    for (int i = 0; i < actual.length; i++) {
      if (actual[i] != 0) {
        errorSum += ((actual[i] - predicted[i]).abs() / actual[i].abs()) * 100.0;
        validCount++;
      }
    }
    return validCount > 0 ? (errorSum / validCount) : 0.0;
  }

  /// Stockout Date Projection
  /// Returns days until stockout: `available / avgDailySales`
  static double projectStockoutDays(double availableStock, double avgDailySales) {
    if (availableStock <= 0) return 0.0;
    if (avgDailySales <= 0) return 999.0;
    return availableStock / avgDailySales;
  }
}

class PredictiveIntelligenceEngine implements IntelligenceCollector {
  @override
  IntelligenceEngineType get engineType => IntelligenceEngineType.predictive;

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

    final inventory = await repository.getInventoryIntelligence(
      tenantId: context.tenantId,
      locationId: context.locationId,
      days: context.periodDays,
      limit: 1000,
    );

    final insights = <InsightRecord>[];

    // 1. Next 30-Day Sales Run-Rate Projection
    if (summary.netSales > 0 && context.periodDays > 0) {
      final dailyRunRate = summary.netSales / context.periodDays;
      final projected30Day = dailyRunRate * 30.0;
      final projectedGrossProfit = summary.grossMarginPct > 0
          ? projected30Day * (summary.grossMarginPct / 100.0)
          : 0.0;

      insights.add(
        InsightRecord(
          id: 'ins-pred-sales-projection-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'sales_projection',
          severity: InsightSeverity.opportunity,
          priority: InsightPriority.medium,
          title: '30-Day Revenue Projection: ${projected30Day.toStringAsFixed(2)}',
          description:
              'Based on current velocity of ${dailyRunRate.toStringAsFixed(2)}/day, estimated next 30-day net sales are ${projected30Day.toStringAsFixed(2)} with projected gross profit of ${projectedGrossProfit.toStringAsFixed(2)}.',
          evidence: InsightEvidence(
            currentValue: projected30Day,
            metricUnit: 'INR',
            breakdown: {
              'daily_velocity': dailyRunRate,
              'margin_pct': summary.grossMarginPct,
              'projected_gross_profit': projectedGrossProfit,
            },
          ),
          dataFreshness: context.now,
          status: InsightStatus.newInsight,
          createdAt: context.now,
          updatedAt: context.now,
        ),
      );
    }

    // 2. Imminent Stockout Projections (< 5 days)
    final imminentStockouts = <Map<String, dynamic>>[];
    for (final item in inventory) {
      final available = (item['available'] as num?)?.toDouble() ?? 0.0;
      final avgDaily = (item['avg_daily_sales'] as num?)?.toDouble() ?? 0.0;
      final days = PredictiveModels.projectStockoutDays(available, avgDaily);
      if (days < 5.0 && days > 0.0) {
        imminentStockouts.add({
          'product_name': item['product_name'],
          'sku': item['sku'],
          'available': available,
          'daily_sales': avgDaily,
          'days_remaining': days,
        });
      }
    }

    if (imminentStockouts.isNotEmpty) {
      imminentStockouts.sort((a, b) => (a['days_remaining'] as double).compareTo(b['days_remaining'] as double));
      final names = imminentStockouts.take(3).map((i) => '${i['product_name']} (${(i['days_remaining'] as double).toStringAsFixed(1)}d)').join(', ');

      insights.add(
        InsightRecord(
          id: 'ins-pred-stockouts-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'projected_stockout',
          severity: InsightSeverity.critical,
          priority: InsightPriority.urgent,
          title: 'Predictive Alert: ${imminentStockouts.length} SKUs facing stockout within 5 days',
          description:
              'Dynamic run-rate models project stockout before next delivery cycle: $names. Expedite procurement orders to prevent stock exhaustion.',
          evidence: InsightEvidence(
            sampleCount: imminentStockouts.length,
            metricUnit: 'SKUs',
            breakdown: {
              'imminent_stockouts': imminentStockouts.take(5).toList(),
            },
          ),
          dataFreshness: context.now,
          status: InsightStatus.newInsight,
          createdAt: context.now,
          updatedAt: context.now,
        ),
      );
    }

    // 3. Projected Cash Flow Runway
    // Cash collection runway = (Current Cash & Receivables) / Daily Operating Expenses
    if (summary.expenses > 0 && context.periodDays > 0) {
      final dailyExpenses = summary.expenses / context.periodDays;
      final cashAndRecv = summary.receivables; // Liquid inflow pool
      if (dailyExpenses > 0) {
        final runwayDays = cashAndRecv / dailyExpenses;
        if (runwayDays < 20.0) {
          insights.add(
            InsightRecord(
              id: 'ins-pred-cashflow-runway-${context.tenantId}',
              tenantId: context.tenantId,
              locationId: context.locationId,
              engine: engineType,
              category: 'cashflow_runway',
              severity: InsightSeverity.warning,
              priority: InsightPriority.high,
              title: 'Cashflow Advisory: ${runwayDays.toStringAsFixed(0)} days operational runway',
              description:
                  'Current trade receivables (${summary.receivables.toStringAsFixed(2)}) provide approximately ${runwayDays.toStringAsFixed(0)} days of operating expense coverage at ${dailyExpenses.toStringAsFixed(2)}/day burn rate.',
              evidence: InsightEvidence(
                currentValue: runwayDays,
                threshold: 30.0,
                metricUnit: 'days',
                breakdown: {
                  'daily_burn': dailyExpenses,
                  'receivables_pool': summary.receivables,
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

    return insights;
  }
}
