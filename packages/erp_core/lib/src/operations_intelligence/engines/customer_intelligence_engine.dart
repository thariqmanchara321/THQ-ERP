import '../operations_intelligence_collector.dart';
import '../operations_intelligence_models.dart';
import '../operations_intelligence_repository.dart';

class CustomerIntelligenceEngine implements IntelligenceCollector {
  @override
  IntelligenceEngineType get engineType => IntelligenceEngineType.customer;

  @override
  Future<List<InsightRecord>> collect(
    OperationsIntelligenceContext context,
    OperationsIntelligenceRepository repository,
  ) async {
    final customers = await repository.getCustomerCreditIntelligence(
      tenantId: context.tenantId,
      locationId: context.locationId,
      limit: 1000,
    );

    final insights = <InsightRecord>[];

    // 1. Critical Overdue Debt (> 90 days)
    final criticalOverdue = customers.where((c) {
      final a4 = (c['days_90_plus'] as num?)?.toDouble() ?? 0.0;
      return a4 > 0.005;
    }).toList();

    if (criticalOverdue.isNotEmpty) {
      double totalOverdue90 = 0.0;
      for (final c in criticalOverdue) {
        totalOverdue90 += (c['days_90_plus'] as num?)?.toDouble() ?? 0.0;
      }
      final names = criticalOverdue.take(3).map((c) => c['customer_name']).join(', ');

      insights.add(
        InsightRecord(
          id: 'ins-cust-overdue-90-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'credit_overdue_severe',
          severity: InsightSeverity.critical,
          priority: InsightPriority.urgent,
          title: 'Severe Overdue Credit: ${criticalOverdue.length} customers past 90 days (${totalOverdue90.toStringAsFixed(2)})',
          description:
              'Accounts past 90 days due include: $names. High risk of bad debt. Consider immediate billing freeze and legal payment reminders.',
          evidence: InsightEvidence(
            currentValue: totalOverdue90,
            sampleCount: criticalOverdue.length,
            metricUnit: 'INR',
            breakdown: {
              'top_overdue_customers': criticalOverdue.take(5).toList(),
            },
          ),
          sourceReferences: criticalOverdue.take(5).map((c) => InsightSourceReference(
            entityType: 'customer',
            entityId: c['customer_id']?.toString() ?? '',
            entityNumber: c['customer_name']?.toString(),
          )).toList(),
          dataFreshness: context.now,
          status: InsightStatus.newInsight,
          createdAt: context.now,
          updatedAt: context.now,
        ),
      );
    }

    // 2. Over Credit Limit
    final overLimit = customers.where((c) {
      final outstanding = (c['total_outstanding'] as num?)?.toDouble() ?? 0.0;
      final limit = (c['credit_limit'] as num?)?.toDouble() ?? 0.0;
      return limit > 0 && outstanding > limit;
    }).toList();

    if (overLimit.isNotEmpty) {
      final names = overLimit.take(3).map((c) => c['customer_name']).join(', ');
      insights.add(
        InsightRecord(
          id: 'ins-cust-over-limit-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'credit_limit_breach',
          severity: InsightSeverity.warning,
          priority: InsightPriority.high,
          title: 'Credit Limit Breached: ${overLimit.length} accounts over limit ($names)',
          description:
              'Customers have exceeded their assigned credit limits. Require payment receipt or manager approval before dispatching further credit orders.',
          evidence: InsightEvidence(
            sampleCount: overLimit.length,
            metricUnit: 'Accounts',
            breakdown: {
              'breached_customers': overLimit.take(5).toList(),
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
