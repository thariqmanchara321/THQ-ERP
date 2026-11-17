import '../operations_intelligence_collector.dart';
import '../operations_intelligence_models.dart';
import '../operations_intelligence_repository.dart';

class OperationalEfficiencyEngine implements IntelligenceCollector {
  @override
  IntelligenceEngineType get engineType => IntelligenceEngineType.operationalEfficiency;

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
    final pipeline = summary.pipeline;

    // 1. Offline POS Sync Conflicts
    final conflicts = (pipeline['offline_pos_conflicts'] as num?)?.toInt() ?? 0;
    if (conflicts > 0) {
      insights.add(
        InsightRecord(
          id: 'ins-ops-pos-conflicts-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'pos_sync_conflicts',
          severity: InsightSeverity.critical,
          priority: InsightPriority.urgent,
          title: 'POS Sync Attention: $conflicts offline transaction conflicts',
          description:
              '$conflicts offline billing invoices encountered server validation conflicts during upload. Resolve conflicts in POS Sync Manager to ensure ledger and GST compliance.',
          evidence: InsightEvidence(
            currentValue: conflicts.toDouble(),
            metricUnit: 'transactions',
          ),
          dataFreshness: context.now,
          status: InsightStatus.newInsight,
          createdAt: context.now,
          updatedAt: context.now,
        ),
      );
    }

    // 2. Draft Goods Receipts Unposted
    final draftGrns = (pipeline['draft_grns'] as num?)?.toInt() ?? 0;
    if (draftGrns > 5) {
      insights.add(
        InsightRecord(
          id: 'ins-ops-draft-grns-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'receiving_bottleneck',
          severity: InsightSeverity.warning,
          priority: InsightPriority.medium,
          title: 'Goods Inward Bottleneck: $draftGrns draft GRNs awaiting posting',
          description:
              'Multiple goods receipts have been scanned or created but not posted to the authoritative inventory ledger. Post GRNs to update live warehouse stock balances.',
          evidence: InsightEvidence(
            currentValue: draftGrns.toDouble(),
            threshold: 5.0,
            metricUnit: 'GRNs',
          ),
          dataFreshness: context.now,
          status: InsightStatus.newInsight,
          createdAt: context.now,
          updatedAt: context.now,
        ),
      );
    }

    // 3. Stock Transfers In Transit
    final inTransit = (pipeline['transfers_in_transit'] as num?)?.toInt() ?? 0;
    if (inTransit > 3) {
      insights.add(
        InsightRecord(
          id: 'ins-ops-transfers-transit-${context.tenantId}',
          tenantId: context.tenantId,
          locationId: context.locationId,
          engine: engineType,
          category: 'stock_transfer_transit',
          severity: InsightSeverity.info,
          priority: InsightPriority.low,
          title: 'Inter-Branch Logistics: $inTransit stock transfers in transit',
          description:
              'Multiple inventory shipments are currently en-route between business locations. Verify physical arrival and process inward delivery acknowledgements.',
          evidence: InsightEvidence(
            currentValue: inTransit.toDouble(),
            metricUnit: 'transfers',
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
