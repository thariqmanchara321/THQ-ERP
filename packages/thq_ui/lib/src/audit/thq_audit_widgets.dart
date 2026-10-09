import 'package:flutter/material.dart';

Map<String, dynamic> auditMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Map<String, dynamic>> auditRows(dynamic value) =>
    value is List ? value.whereType<Map>().map(auditMap).toList() : [];
num auditNumber(dynamic value) =>
    value is num ? value : num.tryParse('$value') ?? 0;
String auditText(dynamic value, {String fallback = '—'}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String auditLabel(String value) {
  const labels = {
    'high_risk': 'High risk',
    'needs_review': 'Needs review',
    'under_review': 'Under review',
    'cogs': 'Cost of goods sold',
    'net_sales_change': 'Sales change',
    'cogs_change': 'Cost change',
    'discount_rate': 'Discount rate',
    'return_rate': 'Return rate',
    'impact_on_profit': 'Profit impact',
    'current_pct': 'Current %',
    'previous_pct': 'Previous %',
    'gst': 'GST',
    'sku': 'SKU',
    'enhanced_v600': 'Recorded history',
    'historical_reconstructed_baseline': 'Historical baseline',
  };
  if (labels.containsKey(value)) return labels[value]!;
  final text = value.replaceAll('_', ' ');
  return text.isEmpty ? '—' : '${text[0].toUpperCase()}${text.substring(1)}';
}

String auditMoney(dynamic value, [String currency = 'INR']) {
  if (value == null) return '—';
  final n = auditNumber(value);
  final parts = n.abs().toStringAsFixed(2).split('.');
  final digits = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return '${n < 0 ? '−' : ''}${currency == 'INR' ? '₹' : '$currency '}$digits.${parts[1]}';
}

String auditDate(dynamic value) {
  final d = DateTime.tryParse(auditText(value));
  if (d == null) return auditText(value);
  final local = d.isUtc ? d.toLocal() : d;
  final day =
      '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  return value.toString().contains('T')
      ? '$day ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}'
      : day;
}

class AuditBadge extends StatelessWidget {
  final String value;
  const AuditBadge(this.value, {super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bad = ['high_risk', 'Unbalanced', 'escalated'].contains(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bad ? scheme.errorContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        auditLabel(value),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: bad ? scheme.onErrorContainer : scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class AuditColumn {
  final String key, label;
  final int flex;
  final bool numeric;
  final bool compact;
  final String format;
  const AuditColumn(
    this.key,
    this.label, {
    this.flex = 2,
    this.numeric = false,
    this.compact = true,
    this.format = 'money',
  });
}

/// Flex widths avoid horizontal scrolling. Narrow layouts retain key fields;
/// opening a row exposes its complete evidence.
class AuditTable extends StatelessWidget {
  final List<AuditColumn> columns;
  final List<Map<String, dynamic>> rows;
  final void Function(Map<String, dynamic>)? onOpen;
  final String currency, empty;
  final bool shrinkWrap;
  const AuditTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onOpen,
    this.currency = 'INR',
    this.empty = 'No matching records.',
    this.shrinkWrap = false,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final narrow = bounds.maxWidth < 720;
      final selected = narrow
          ? columns.where((c) => c.compact).toList()
          : columns;
      Widget cells(Map<String, dynamic> row, bool header) => Row(
        children: [
          for (final c in selected)
            Expanded(
              flex: c.flex,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
                child: header
                    ? Text(
                        c.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: c.numeric ? TextAlign.right : TextAlign.left,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      )
                    : ['severity', 'status', 'balance_status'].contains(c.key)
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: AuditBadge(auditText(row[c.key])),
                      )
                    : Text(
                        c.numeric
                            ? c.format == 'percent'
                                  ? row[c.key] == null
                                        ? '—'
                                        : '${auditNumber(row[c.key]).toStringAsFixed(2)}%'
                                  : auditMoney(row[c.key], currency)
                            : ['date', 'last_posted'].contains(c.key)
                            ? auditDate(row[c.key])
                            : auditText(row[c.key]),
                        textAlign: c.numeric ? TextAlign.right : TextAlign.left,
                        maxLines: narrow ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
              ),
            ),
          if (onOpen != null)
            SizedBox(
              width: 28,
              child: header
                  ? const SizedBox.shrink()
                  : const Icon(Icons.chevron_right, size: 18),
            ),
        ],
      );
      final list = ListView.separated(
        shrinkWrap: shrinkWrap,
        physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) => Material(
          color: i.isEven
              ? Theme.of(context).colorScheme.surface
              : Theme.of(context).colorScheme.surfaceContainerLowest,
          child: InkWell(
            onTap: onOpen == null ? null : () => onOpen!(rows[i]),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 39),
              child: cells(rows[i], false),
            ),
          ),
        ),
      );
      return Column(
        mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
        children: [
          ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: cells({}, true),
          ),
          const Divider(height: 1),
          if (rows.isEmpty)
            Padding(padding: const EdgeInsets.all(24), child: Text(empty))
          else if (shrinkWrap)
            list
          else
            Expanded(child: list),
        ],
      );
    },
  );
}

class AuditMetrics extends StatelessWidget {
  final Map<String, String> values;
  const AuditMetrics(this.values, {super.key});
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 5,
    children: [
      for (final entry in values.entries)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.key, style: Theme.of(context).textTheme.labelSmall),
              Text(
                entry.value,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Human-readable evidence, retaining business values without raw JSON dumps.
class AuditEvidence extends StatelessWidget {
  final String title, currency;
  final dynamic value;
  final void Function(String)? openAccount;
  final void Function(Map<String, dynamic>)? openJournal;
  final bool expanded;
  const AuditEvidence({
    super.key,
    required this.title,
    required this.value,
    this.currency = 'INR',
    this.openAccount,
    this.openJournal,
    this.expanded = false,
  });
  static bool hidden(String key) =>
      key == 'id' ||
      key.endsWith('_id') ||
      key.contains('hash') ||
      key == 'correlation_id' ||
      [
        'source_function',
        'metadata',
        'key',
        'diagnostic',
        'integrity',
      ].contains(key);
  static bool empty(dynamic v) =>
      v == null || v is Map && v.isEmpty || v is List && v.isEmpty;

  Widget _body(BuildContext context, dynamic item) {
    if (item is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < item.length; i++) ...[
            if (i > 0) const Divider(height: 14),
            _body(context, item[i]),
          ],
        ],
      );
    }
    if (item is Map) {
      final map = auditMap(item);
      final name = auditText(
        map['label'] ??
            map['account_name'] ??
            map['name'] ??
            map['driver'] ??
            map['reference'],
        fallback: '',
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (name.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    auditLabel(name),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (map['account_id'] != null && openAccount != null)
                  TextButton(
                    onPressed: () => openAccount!('${map['account_id']}'),
                    child: const Text('Account ledger'),
                  ),
                if ((map['journal_id'] ?? map['entry_number']) != null &&
                    openJournal != null)
                  TextButton(
                    onPressed: () => openJournal!(map),
                    child: const Text('Journal'),
                  ),
              ],
            ),
          for (final e in map.entries)
            if (!hidden(e.key) &&
                !empty(e.value) &&
                !['label', 'name', 'account_name', 'driver'].contains(e.key))
              if (e.value is Map || e.value is List)
                AuditEvidence(
                  title: auditLabel(e.key),
                  value: e.value,
                  currency: currency,
                  openAccount: openAccount,
                  openJournal: openJournal,
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 132,
                        child: Text(
                          auditLabel(e.key),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Expanded(child: SelectableText(_display(e.key, e.value))),
                    ],
                  ),
                ),
        ],
      );
    }
    return SelectableText(auditText(item));
  }

  String _display(String key, dynamic v) {
    if (v == null) return 'Not recorded';
    if (key.endsWith('_at') || key.endsWith('_date') || key == 'event_time') {
      return auditDate(v);
    }
    if (v is bool) return v ? 'Yes' : 'No';
    if (v is num &&
        (key.contains('amount') ||
            key.contains('value') ||
            key.contains('impact') ||
            [
              'current',
              'previous',
              'change',
              'recognized_cogs',
              'net_sales',
            ].contains(key) ||
            key.contains('profit') ||
            key.contains('sales') ||
            [
              'debit',
              'credit',
              'cost',
              'balance',
              'contribution',
              'total',
              'paid',
              'due',
              'net_cogs',
            ].contains(key))) {
      return auditMoney(v, currency);
    }
    if (v is num && (key.contains('pct') || key.contains('percent'))) {
      return '${v.toStringAsFixed(2)}%';
    }
    if ([
      'severity',
      'status',
      'action',
      'source_type',
      'account_type',
      'evidence_quality',
    ].contains(key)) {
      return auditLabel('$v');
    }
    if (RegExp(r'^[a-fA-F0-9]{8}-[a-fA-F0-9-]{27}$').hasMatch('$v')) {
      return 'Recorded link';
    }
    return auditText(v);
  }

  @override
  Widget build(BuildContext context) {
    if (empty(value)) return const SizedBox.shrink();
    return ExpansionTile(
      initiallyExpanded: expanded,
      dense: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      children: [_body(context, value)],
    );
  }
}
