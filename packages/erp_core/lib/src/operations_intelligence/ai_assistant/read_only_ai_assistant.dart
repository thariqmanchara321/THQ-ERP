import 'dart:async';
import '../operations_intelligence_repository.dart';

/// Provider interface for optional conversational AI.
abstract class AiIntelligenceProvider {
  String get providerName;
  Future<String> answerQuery({
    required String prompt,
    required Map<String, dynamic> authorizedContext,
  });
}

/// Fallback / Hermetic deterministic AI provider.
/// Works 100% offline without any external API keys or cloud dependencies.
class MockAiIntelligenceProvider implements AiIntelligenceProvider {
  @override
  String get providerName => 'Local Deterministic Intelligence Engine';

  @override
  Future<String> answerQuery({
    required String prompt,
    required Map<String, dynamic> authorizedContext,
  }) async {
    final lower = prompt.toLowerCase();
    final summary = authorizedContext['summary'] as Map<String, dynamic>? ?? {};
    final netSales = (summary['net_sales'] as num?)?.toDouble() ?? 0.0;
    final margin = (summary['gross_margin_pct'] as num?)?.toDouble() ?? 0.0;
    final lowStock = (summary['low_stock_count'] as num?)?.toInt() ?? 0;
    final outOfStock = (summary['out_of_stock_count'] as num?)?.toInt() ?? 0;
    final receivables = (summary['receivables'] as num?)?.toDouble() ?? 0.0;
    final overdueRecv = (summary['overdue_receivables'] as num?)?.toDouble() ?? 0.0;
    final score = (summary['composite_health_score'] as num?)?.toDouble() ?? 80.0;

    if (lower.contains('health') || lower.contains('score') || lower.contains('overall')) {
      return 'The business is currently operating at a Composite Health Score of ${score.toStringAsFixed(1)}/100. Net sales over the period are INR ${netSales.toStringAsFixed(2)} with a gross margin of ${margin.toStringAsFixed(1)}%. Key attention areas: $outOfStock SKUs are out of stock and INR ${overdueRecv.toStringAsFixed(2)} in customer receivables are overdue.';
    }

    if (lower.contains('sale') || lower.contains('revenue') || lower.contains('growth')) {
      return 'Net sales across the selected period stand at INR ${netSales.toStringAsFixed(2)} across ${summary['order_count']} transactions with an Average Order Value (AOV) of INR ${summary['average_order_value']}. Top revenue drivers include: ${(authorizedContext['top_products'] as List? ?? []).take(3).map((p) => p['product_name']).join(', ')}.';
    }

    if (lower.contains('stock') || lower.contains('inventory') || lower.contains('reorder')) {
      return 'Inventory health summary: Total inventory valuation is INR ${summary['inventory_value']}. There are $outOfStock out-of-stock items and $lowStock low-stock items approaching their reorder threshold. Replenishment proposals are available in the Action Centre.';
    }

    if (lower.contains('credit') || lower.contains('customer') || lower.contains('receivable')) {
      return 'Customer credit exposure: Total trade receivables are INR ${receivables.toStringAsFixed(2)}, of which INR ${overdueRecv.toStringAsFixed(2)} (${receivables > 0 ? ((overdueRecv / receivables) * 100).toStringAsFixed(1) : 0}%) is overdue past standard payment terms. Immediate collection follow-ups are advised.';
    }

    if (lower.contains('risk') || lower.contains('issue') || lower.contains('problem')) {
      final critCount = (summary['critical_insights_count'] as num?)?.toInt() ?? 0;
      return 'Identified $critCount critical operations risks requiring executive review. Top concerns include out-of-stock Pareto items and overdue customer credit balances. Check the Risk & Anomaly Watchdog tab for document-level evidence.';
    }

    return 'Operations Intelligence Summary: Net revenue is INR ${netSales.toStringAsFixed(2)} (gross margin ${margin.toStringAsFixed(1)}%). Inventory holds $outOfStock stockouts and $lowStock low-stock warnings. Total trade receivables are INR ${receivables.toStringAsFixed(2)} with INR ${overdueRecv.toStringAsFixed(2)} overdue.';
  }
}

/// Controlled, read-only AI Business Assistant service.
/// GUARANTEE: Never exposes database write access or credentials.
class ReadOnlyAiBusinessAssistant {
  final OperationsIntelligenceRepository repository;
  final AiIntelligenceProvider provider;

  ReadOnlyAiBusinessAssistant({
    required this.repository,
    AiIntelligenceProvider? provider,
  }) : provider = provider ?? MockAiIntelligenceProvider();

  Future<String> ask({
    required String question,
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async {
    // Build sanitized read-only context
    final summary = await repository.getExecutiveSummary(
      tenantId: tenantId,
      locationId: locationId,
      days: days,
    );

    final insights = await repository.getInsights(
      tenantId: tenantId,
      locationId: locationId,
      limit: 10,
    );

    final authorizedContext = {
      'summary': summary.toMap(),
      'insights': insights.map((i) => {
        'title': i.title,
        'severity': i.severity.code,
        'category': i.category,
      }).toList(),
      'top_products': summary.topProducts,
    };

    return await provider.answerQuery(
      prompt: question,
      authorizedContext: authorizedContext,
    );
  }

  Future<String> explainMetric({
    required String metricKey,
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async {
    return ask(
      question: 'Explain our $metricKey performance and provide actionable business advice.',
      tenantId: tenantId,
      locationId: locationId,
      days: days,
    );
  }
}
