import '../operations_intelligence_collector.dart';
import '../operations_intelligence_models.dart';
import '../operations_intelligence_repository.dart';

class SupplierIntelligenceEngine implements IntelligenceCollector {
  @override
  IntelligenceEngineType get engineType => IntelligenceEngineType.supplier;

  @override
  Future<List<InsightRecord>> collect(
    OperationsIntelligenceContext context,
    OperationsIntelligenceRepository repository,
  ) async {
    final suppliers = await repository.getSupplierPayablesIntelligence(
      tenantId: context.tenantId,
      locationId: context.locationId,
      limit: 1000,
    );

    final insights = <InsightRecord>[];

    // 1. Critical Overdue Payables (> 60 days)
    final overdueSuppliers = suppliers.where((s) {
      final a3 = (s['days_61_90'] as num?)?.toDouble() ?? 0.0;
      final a4 = (s['days_90_plus'] as num?)?.toDouble() ?? 0.0;
      return (a3 + a4) > 0.005;
    }).toList();

    if (overdueSuppliers.isNotEmpty) {
      double totalOverdue = 0.0;
      for (final s in overdueSuppliers) {
        totalOverdue += ((s['days_61_90'] as num?)?.toDouble() ?? 0.0) +
            ((s['days_90_plus'] as num?)?.toDouble() ?? 0.0);
      }
      final names = overdueSuppliers.take(3).map((s) => s['supplier_name']).join(', ');

      insights.add(
        InsightRecord(
          id: 'ins-sup-overdue-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'payables_overdue',
          severity: InsightSeverity.warning,
          priority: InsightPriority.high,
          title: 'Overdue Supplier Invoices: ${totalOverdue.toStringAsFixed(2)} pending past 60 days ($names)',
          description:
              'Overdue vendor balances risk credit holds, shipment delays, and late penalty charges. Prioritize vendor settlement schedule.',
          evidence: InsightEvidence(
            currentValue: totalOverdue,
            sampleCount: overdueSuppliers.length,
            metricUnit: 'INR',
            breakdown: {
              'overdue_suppliers': overdueSuppliers.take(5).toList(),
            },
          ),
          sourceReferences: overdueSuppliers.take(5).map((s) => InsightSourceReference(
            entityType: 'supplier',
            entityId: s['supplier_id']?.toString() ?? '',
            entityNumber: s['supplier_name']?.toString(),
          )).toList(),
          dataFreshness: context.now,
          status: InsightStatus.newInsight,
          createdAt: context.now,
          updatedAt: context.now,
        ),
      );
    }

    // 2. Supplier Concentration Risk
    if (suppliers.length > 1) {
      double totalPayables = 0.0;
      for (final s in suppliers) {
        totalPayables += (s['total_outstanding'] as num?)?.toDouble() ?? 0.0;
      }
      if (totalPayables > 0) {
        final topSupplier = suppliers.first;
        final topOut = (topSupplier['total_outstanding'] as num?)?.toDouble() ?? 0.0;
        final share = (topOut / totalPayables) * 100.0;
        if (share > 50.0) {
          insights.add(
            InsightRecord(
              id: 'ins-sup-conc-${context.tenantId}',
              tenantId: context.tenantId,
              locationId: context.locationId,
              engine: engineType,
              category: 'supplier_concentration',
              severity: InsightSeverity.info,
              priority: InsightPriority.medium,
              title: 'High Vendor Exposure: ${topSupplier['supplier_name']} (${share.toStringAsFixed(1)}% of Payables)',
              description:
                  'A single vendor accounts for over half of total company trade payables (${topOut.toStringAsFixed(2)}). Cultivate secondary vendor relationships to mitigate supply interruption risks.',
              evidence: InsightEvidence(
                currentValue: share,
                threshold: 40.0,
                metricUnit: '%',
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
