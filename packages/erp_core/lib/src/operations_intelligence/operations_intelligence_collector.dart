import 'dart:async';
import 'operations_intelligence_models.dart';
import 'operations_intelligence_repository.dart';

class OperationsIntelligenceContext {
  final String tenantId;
  final String? locationId;
  final int periodDays;
  final DateTime now;

  const OperationsIntelligenceContext({
    required this.tenantId,
    this.locationId,
    this.periodDays = 30,
    required this.now,
  });
}

abstract class IntelligenceCollector {
  IntelligenceEngineType get engineType;

  Future<List<InsightRecord>> collect(
    OperationsIntelligenceContext context,
    OperationsIntelligenceRepository repository,
  );
}

/// Central orchestrator coordinating independent collectors with isolated failure handling.
class OperationsIntelligenceCore {
  final OperationsIntelligenceRepository repository;
  final List<IntelligenceCollector> _collectors = [];
  final Duration suppressionWindow;

  OperationsIntelligenceCore({
    required this.repository,
    this.suppressionWindow = const Duration(hours: 24),
  });

  void registerCollector(IntelligenceCollector collector) {
    _collectors.add(collector);
  }

  void registerCollectors(List<IntelligenceCollector> collectors) {
    _collectors.addAll(collectors);
  }

  List<IntelligenceCollector> get collectors => List.unmodifiable(_collectors);

  /// Executes all registered collectors with fault-isolated concurrency.
  Future<List<InsightRecord>> runCollection(
    OperationsIntelligenceContext context, {
    bool persist = true,
  }) async {
    final futures = _collectors.map((collector) async {
      try {
        return await collector.collect(context, repository);
      } catch (e, st) {
        // Fail-safe: A broken collector must NEVER take down the intelligence platform
        return [
          InsightRecord(
            id: 'err-${collector.engineType.code}-${DateTime.now().millisecondsSinceEpoch}',
            tenantId: context.tenantId,
            locationId: context.locationId,
            engine: collector.engineType,
            category: 'system_collector_error',
            severity: InsightSeverity.warning,
            priority: InsightPriority.low,
            title: 'Diagnostic: ${collector.engineType.name} collector issue',
            description: 'Collector experienced a non-fatal execution warning: $e',
            evidence: InsightEvidence(
              breakdown: {
                'error': e.toString(),
                'stack': st.toString().split('\n').take(3).join(' • '),
              },
            ),
            dataFreshness: DateTime.now(),
            status: InsightStatus.newInsight,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          )
        ];
      }
    });

    final nestedResults = await Future.wait(futures);
    final allInsights = nestedResults.expand((list) => list).toList();

    if (persist) {
      for (final insight in allInsights) {
        // Skip technical diagnostic messages from persistence if desired
        if (insight.category == 'system_collector_error') continue;

        final dedupKey = '${context.tenantId}:${insight.engine.code}:${insight.category}:${insight.title}';
        try {
          await repository.saveInsight(insight, dedupKey: dedupKey);
        } catch (_) {
          // Ignore persistence errors in transient runs
        }
      }
    }

    return allInsights;
  }
}
