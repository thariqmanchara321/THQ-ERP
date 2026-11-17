import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';

/// Clean, compact, futuristic KPI Metric Card for Operations Intelligence.
class ThqIntelligenceMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final double? deltaPercent;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  const ThqIntelligenceMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.deltaPercent,
    this.icon,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = color ?? (isDark ? Colors.cyanAccent : Colors.teal.shade700);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E222B) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? const Color(0xFF2E3440) : Colors.grey.shade200,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              // ignore: deprecated_member_use
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (icon != null)
                  Icon(icon, size: 16, color: primaryColor),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtitle != null || deltaPercent != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  if (deltaPercent != null) ...[
                    Icon(
                      deltaPercent! >= 0 ? Icons.trending_up : Icons.trending_down,
                      size: 13,
                      color: deltaPercent! >= 0 ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${deltaPercent! >= 0 ? '+' : ''}${deltaPercent!.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: deltaPercent! >= 0 ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (subtitle != null)
                    Expanded(
                      child: Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Actionable Insight Card with severity indicator and resolution actions.
class ThqInsightCard extends StatelessWidget {
  final InsightRecord insight;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onResolve;
  final VoidCallback? onProposeAction;

  const ThqInsightCard({
    super.key,
    required this.insight,
    this.onAcknowledge,
    this.onResolve,
    this.onProposeAction,
  });

  Color _severityColor(InsightSeverity severity) {
    switch (severity) {
      case InsightSeverity.critical:
        return Colors.red.shade600;
      case InsightSeverity.warning:
        return Colors.orange.shade700;
      case InsightSeverity.opportunity:
        return Colors.teal.shade600;
      case InsightSeverity.info:
        return Colors.blue.shade600;
    }
  }

  IconData _severityIcon(InsightSeverity severity) {
    switch (severity) {
      case InsightSeverity.critical:
        return Icons.error_outline;
      case InsightSeverity.warning:
        return Icons.warning_amber_rounded;
      case InsightSeverity.opportunity:
        return Icons.lightbulb_outline;
      case InsightSeverity.info:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = _severityColor(insight.severity);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E222B) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF2E3440) : Colors.grey.shade200,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left severity indicator bar
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_severityIcon(insight.severity), size: 16, color: color),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            // ignore: deprecated_member_use
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            insight.severity.name.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            insight.engine.name.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          insight.status.code.replaceAll('_', ' '),
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      insight.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      insight.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (insight.status == InsightStatus.newInsight && onAcknowledge != null) ...[
                          OutlinedButton(
                            onPressed: onAcknowledge,
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            ),
                            child: const Text('Acknowledge', style: TextStyle(fontSize: 11)),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (onProposeAction != null) ...[
                          ElevatedButton.icon(
                            onPressed: onProposeAction,
                            icon: const Icon(Icons.bolt, size: 14),
                            label: const Text('Create Action', style: TextStyle(fontSize: 11)),
                            style: ElevatedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (insight.status != InsightStatus.resolved && onResolve != null)
                          TextButton(
                            onPressed: onResolve,
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            ),
                            child: const Text('Mark Resolved', style: TextStyle(fontSize: 11)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Interactive simulation slider for what-if scenarios.
class ThqSimulationSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String suffix;
  final ValueChanged<double> onChanged;

  const ThqSimulationSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.suffix = '',
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text(
              '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}$suffix',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Read-only AI Assistant dialog or bottom sheet.
class ThqAiAssistantSheet extends StatefulWidget {
  final ReadOnlyAiBusinessAssistant assistant;
  final String tenantId;
  final String? locationId;

  const ThqAiAssistantSheet({
    super.key,
    required this.assistant,
    required this.tenantId,
    this.locationId,
  });

  @override
  State<ThqAiAssistantSheet> createState() => _ThqAiAssistantSheetState();
}

class _ThqAiAssistantSheetState extends State<ThqAiAssistantSheet> {
  final TextEditingController _prompt = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _loading = false;

  final List<String> _quickPrompts = const [
    'What is our overall business health?',
    'Summarize our top sales and revenue drivers',
    'Which products are at critical stockout risk?',
    'What is our customer credit and collection risk?',
  ];

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _send(String query) async {
    final text = query.trim();
    if (text.isEmpty) return;
    _prompt.clear();

    setState(() {
      _messages.add({'sender': 'user', 'text': text});
      _loading = true;
    });

    try {
      final answer = await widget.assistant.ask(
        question: text,
        tenantId: widget.tenantId,
        locationId: widget.locationId,
      );
      if (mounted) {
        setState(() {
          _messages.add({'sender': 'ai', 'text': answer});
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add({'sender': 'ai', 'text': 'Unable to retrieve answer: $e'});
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 520,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF191C24) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology, color: Colors.teal),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Operations Intelligence Assistant (Read-Only)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Secure read-only business insights. Cannot modify accounting or live inventory records.',
            style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
          ),
          const Divider(height: 20),
          // Quick prompt chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickPrompts.map((p) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(p, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    onPressed: _loading ? null : () => _send(p),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'Ask questions regarding revenue, margins, inventory risk, or cashflow.',
                      style: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey.shade600, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final m = _messages[index];
                      final isUser = m['sender'] == 'user';
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          constraints: const BoxConstraints(maxWidth: 380),
                          decoration: BoxDecoration(
                            color: isUser
                                ? (isDark ? Colors.teal.shade900 : Colors.teal.shade50)
                                : (isDark ? const Color(0xFF282D37) : Colors.grey.shade100),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isUser
                                  // ignore: deprecated_member_use
                                  ? Colors.teal.withOpacity(0.3)
                                  : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                            ),
                          ),
                          child: Text(
                            m['text'] ?? '',
                            style: TextStyle(fontSize: 12, height: 1.3),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_loading) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _prompt,
                  onSubmitted: _send,
                  decoration: const InputDecoration(
                    hintText: 'Ask a business intelligence question...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _loading ? null : () => _send(_prompt.text),
                icon: const Icon(Icons.send, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
