import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/record_presentation.dart';
import '../models/report_document.dart';

/// A screen projection only. The full document remains intact for exports.
class InventoryReportTable extends StatelessWidget {
  final ReportDocument report;
  final ScrollController controller;
  final String? sortKey;
  final bool descending, disabled, showStore;
  final ValueChanged<String> onSort;
  final ValueChanged<Map<String, dynamic>> onOpen;
  const InventoryReportTable({
    super.key,
    required this.report,
    required this.controller,
    required this.onSort,
    required this.onOpen,
    this.sortKey,
    this.descending = false,
    this.disabled = false,
    this.showStore = true,
  });

  static const _fields = <String, List<String>>{
    'stock_snapshot': [
      'product_name',
      'location_name',
      'unit_code',
      'quantity',
      'available',
      'tracking_mode',
      'status',
    ],
    'valuation': [
      'product_name',
      'location_name',
      'unit_code',
      'quantity',
      'average_cost',
      'stock_value',
    ],
    'stock_statement': [
      'product_name',
      'location_name',
      'unit_code',
      'opening_quantity',
      'receipts',
      'issues',
      'closing_quantity',
      'status',
    ],
    'movements': [
      'product_name',
      'created_at',
      'reference_number',
      'movement_type',
      'quantity_in',
      'quantity_out',
      'balance_after',
    ],
    'reorder': [
      'product_name',
      'location_name',
      'unit_code',
      'available',
      'reorder_level',
      'days_cover',
      'suggested_reorder',
      'status',
    ],
    'activity': [
      'product_name',
      'location_name',
      'unit_code',
      'quantity',
      'net_sold_quantity',
      'days_since_sale',
      'activity_status',
    ],
    'batches': [
      'product_name',
      'batch_number',
      'location_name',
      'unit_code',
      'quantity',
      'available',
      'expiry_on',
      'status',
    ],
    'expiry': [
      'product_name',
      'batch_number',
      'location_name',
      'quantity',
      'expiry_on',
      'days_to_expiry',
      'status',
    ],
    'serials': [
      'product_name',
      'serial_number',
      'location_name',
      'status',
      'sale_number',
      'received_at',
    ],
    'warranties': [
      'product_name',
      'serial_number',
      'customer_name',
      'sale_number',
      'warranty_expiry',
      'quantity',
      'status',
    ],
    'transfers': [
      'product_name',
      'transfer_number',
      'from_location',
      'to_location',
      'quantity',
      'in_transit_quantity',
      'status',
    ],
    'stock_counts': [
      'product_name',
      'count_number',
      'location_name',
      'system_quantity',
      'counted_quantity',
      'variance',
      'status',
    ],
    'reconciliation': [
      'product_name',
      'location_name',
      'unit_code',
      'quantity',
      'ledger_variance',
      'tracking_variance',
      'status',
    ],
    'tracking_events': [
      'product_name',
      'created_at',
      'serial_number',
      'event_type',
      'reference_number',
      'quantity',
    ],
    'tracking_changes': [
      'product_name',
      'created_at',
      'from_mode',
      'to_mode',
      'revision',
      'reason',
    ],
  };
  static const _labels = {
    'product_name': 'Product / SKU',
    'location_name': 'Store',
    'unit_code': 'Unit',
    'opening_quantity': 'Opening',
    'closing_quantity': 'Closing',
    'receipts': 'In',
    'issues': 'Out',
    'quantity_in': 'In',
    'quantity_out': 'Out',
    'balance_after': 'Balance',
    'average_cost': 'Avg. cost',
    'stock_value': 'Stock value',
    'net_sold_quantity': 'Sold',
    'days_since_sale': 'Since sale',
    'suggested_reorder': 'Reorder qty',
    'reorder_level': 'Reorder level',
    'expiry_on': 'Expiry',
    'warranty_expiry': 'Expiry',
    'days_to_expiry': 'Days left',
    'serial_number': 'Serial / batch',
    'batch_number': 'Batch',
    'sale_number': 'Invoice',
    'customer_name': 'Customer',
    'transfer_number': 'Transfer',
    'count_number': 'Count',
    'system_quantity': 'System',
    'counted_quantity': 'Counted',
    'in_transit_quantity': 'In transit',
    'ledger_variance': 'Ledger gap',
    'tracking_variance': 'Tracking gap',
    'created_at': 'Posted',
    'received_at': 'Received',
    'reference_number': 'Reference',
    'movement_type': 'Type',
    'event_type': 'Event',
    'activity_status': 'Activity',
    'from_location': 'From',
    'to_location': 'To',
    'from_mode': 'From',
    'to_mode': 'To',
  };
  static const _quantities = {
    'quantity',
    'available',
    'opening_quantity',
    'closing_quantity',
    'receipts',
    'issues',
    'quantity_in',
    'quantity_out',
    'balance_after',
    'net_sold_quantity',
    'suggested_reorder',
    'reorder_level',
    'system_quantity',
    'counted_quantity',
    'variance',
    'in_transit_quantity',
    'ledger_variance',
    'tracking_variance',
  };
  static const _states = {
    'status',
    'activity_status',
    'tracking_mode',
    'from_mode',
    'to_mode',
  };

  List<ReportColumn> get _important {
    final available = {for (final c in report.columns) c.key: c};
    final selected = [
      for (final key
          in _fields[report.definition.key] ?? available.keys.toList())
        if (available.containsKey(key) && !RecordPresentation.internal(key))
          available[key]!,
    ];
    if (selected.isEmpty) {
      return report.columns
          .where((c) => !RecordPresentation.internal(c.key))
          .take(6)
          .toList();
    }
    return selected;
  }

  String _label(ReportColumn c) => c.key == 'quantity'
      ? report.definition.key == 'transfers'
            ? 'Requested'
            : const {
                'stock_snapshot',
                'valuation',
                'activity',
                'batches',
                'reconciliation',
              }.contains(report.definition.key)
            ? 'On hand'
            : 'Quantity'
      : _labels[c.key] ?? c.label;
  double _minimum(ReportColumn c) {
    if (c.key == 'product_name') return 210;
    if (c.key == 'unit_code') return 54;
    if (_states.contains(c.key)) return 104;
    if (c.type == 'datetime') return 130;
    if (c.type == 'date') return 104;
    if (c.type == 'money') return 118;
    if (c.numeric) {
      return c.key == 'suggested_reorder' || c.key.endsWith('_variance')
          ? 106
          : 88;
    }
    return c.key == 'reason' ? 180 : 128;
  }

  double _weight(ReportColumn c) => c.key == 'product_name'
      ? 3
      : c.key == 'reason'
      ? 2
      : c.numeric || c.key == 'unit_code'
      ? .65
      : 1.3;
  int _priority(ReportColumn c) => switch (c.key) {
    'product_name' => 0,
    'status' ||
    'activity_status' ||
    'stock_value' ||
    'quantity' ||
    'available' ||
    'closing_quantity' ||
    'suggested_reorder' ||
    'ledger_variance' ||
    'tracking_variance' ||
    'variance' ||
    'serial_number' ||
    'expiry_on' ||
    'warranty_expiry' ||
    'in_transit_quantity' ||
    'event_type' ||
    'batch_number' => 1,
    'tracking_mode' || 'received_at' || 'reason' => 5,
    'location_name' || 'from_location' || 'to_location' => 4,
    'unit_code' || 'sale_number' || 'customer_name' || 'reference_number' => 3,
    _ => 2,
  };

  String _value(
    Map<String, dynamic> row,
    ReportColumn c, {
    bool withUnit = false,
  }) {
    if (c.key == 'serial_number' && (row[c.key] == null || row[c.key] == '')) {
      return row['batch_number']?.toString() ?? '—';
    }
    var text = report.cell(row, c);
    if ((_states.contains(c.key) || c.key == 'event_type') &&
        row[c.key] is String) {
      text = (row[c.key] as String)
          .split('_')
          .map(
            (part) => part.isEmpty
                ? ''
                : '${part[0].toUpperCase()}${part.substring(1)}',
          )
          .join(' ');
    }
    return withUnit &&
            row['unit_code'] != null &&
            row[c.key] != null &&
            _quantities.contains(c.key)
        ? '$text ${row['unit_code']}'
        : text;
  }

  String _subtitle(Map<String, dynamic> row, Set<String> visible) => [
    if (row['sku'] != null) row['sku'].toString(),
    if (showStore &&
        !visible.contains('location_name') &&
        row['location_name'] != null)
      row['location_name'].toString(),
    for (final key in const [
      'transfer_number',
      'count_number',
      'reference_number',
      'sale_number',
    ])
      if (!visible.contains(key) &&
          row[key] != null &&
          report.columns.any((c) => c.key == key))
        row[key].toString(),
    if (report.definition.key == 'transfers' &&
        (!visible.contains('from_location') ||
            !visible.contains('to_location')))
      '${row['from_location'] ?? '—'} → ${row['to_location'] ?? '—'}',
    if (report.definition.key == 'tracking_changes' &&
        !visible.contains('reason') &&
        row['reason'] != null)
      row['reason'].toString(),
  ].join(' · ');

  Color _stateColor(BuildContext context, String value) {
    final colors = Theme.of(context).colorScheme;
    if (const {
      'out_of_stock',
      'expired',
      'review_required',
      'ledger_gap',
      'damaged',
      'quarantine',
      'cancelled',
      'lost',
    }.contains(value)) {
      return colors.error;
    }
    if (const {
      'low_stock',
      'expiring_soon',
      'slow_moving',
      'non_moving',
      'reserved',
      'in_transit',
      'dispatched',
    }.contains(value)) {
      return Theme.of(context).brightness == Brightness.dark
          ? const Color(0xffffcd78)
          : const Color(0xff926100);
    }
    if (const {
      'healthy',
      'reconciled',
      'active',
      'in_stock',
      'received',
      'posted',
    }.contains(value)) {
      return Theme.of(context).brightness == Brightness.dark
          ? const Color(0xff8fdfb2)
          : const Color(0xff187447);
    }
    return colors.primary;
  }

  Widget _cell(
    BuildContext context,
    Map<String, dynamic> row,
    ReportColumn c,
    Set<String> visible,
  ) {
    final color = Theme.of(context).colorScheme;
    final text = _value(row, c, withUnit: !visible.contains('unit_code'));
    final style = TextStyle(
      fontSize: 12,
      color: color.onSurface,
      fontFeatures: c.numeric ? const [FontFeature.tabularFigures()] : null,
    );
    Widget child;
    if (c.key == 'product_name') {
      final subtitle = _subtitle(row, visible);
      child = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(fontWeight: FontWeight.w600),
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: color.onSurfaceVariant),
            ),
        ],
      );
    } else if (c.type == 'datetime' &&
        DateTime.tryParse(row[c.key]?.toString() ?? '') != null) {
      final date = DateTime.parse(row[c.key].toString());
      child = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('dd MMM yyyy').format(date),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
          Text(
            '${DateFormat('HH:mm').format(date)}${date.isUtc ? ' UTC' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: color.onSurfaceVariant),
          ),
        ],
      );
    } else if (_states.contains(c.key)) {
      final state = _stateColor(context, row[c.key]?.toString() ?? '');
      child = Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: state.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: state,
            ),
          ),
        ),
      );
    } else {
      final gap =
          const {
            'variance',
            'ledger_variance',
            'tracking_variance',
          }.contains(c.key) &&
          row[c.key] is num &&
          (row[c.key] as num).abs() > .0001;
      child = Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: c.numeric ? TextAlign.right : TextAlign.left,
        style: style.copyWith(color: gap ? color.error : null),
      );
      if (c.key == 'event_type' && row['trace_only'] == true) {
        child = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            child,
            Text(
              'Trace only',
              style: TextStyle(fontSize: 10, color: color.primary),
            ),
          ],
        );
      }
    }
    return Tooltip(
      message: c.key == 'product_name'
          ? '$text\n${_subtitle(row, visible)}'
          : text,
      child: child,
    );
  }

  Widget _cards(BuildContext context, List<ReportColumn> fields, double scale) {
    final colors = Theme.of(context).colorScheme;
    final primary = fields.first;
    final details = fields
        .where(
          (c) =>
              c.key != primary.key &&
              c.key != 'status' &&
              c.key != 'activity_status' &&
              c.key != 'unit_code' &&
              c.key != 'location_name' &&
              c.key != 'from_location' &&
              c.key != 'to_location',
        )
        .toList();
    final states = fields
        .where((c) => c.key == 'status' || c.key == 'activity_status')
        .toList();
    return Column(
      children: [
        Container(
          height: 34 * scale,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${report.totalRows} matching records',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Sort records',
                enabled: !disabled,
                onSelected: onSort,
                itemBuilder: (_) => fields
                    .map(
                      (c) => PopupMenuItem(
                        value: c.key,
                        child: Text(
                          '${_label(c)}${sortKey == c.key
                              ? descending
                                    ? ' ↓'
                                    : ' ↑'
                              : ''}',
                        ),
                      ),
                    )
                    .toList(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.sort, size: 16, color: colors.primary),
                      const SizedBox(width: 4),
                      const Text('Sort', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: controller,
            thumbVisibility: true,
            child: ListView.builder(
              controller: controller,
              padding: EdgeInsets.zero,
              itemCount: report.rows.length,
              itemBuilder: (_, i) {
                final row = report.rows[i];
                return Material(
                  color: i.isEven ? colors.surface : colors.surfaceContainerLow,
                  child: InkWell(
                    key: ValueKey('inventory-record-$i'),
                    onTap: () => onOpen(row),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: colors.outlineVariant.withValues(alpha: .55),
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _cell(context, row, primary, {
                                  primary.key,
                                  ...fields
                                      .map((c) => c.key)
                                      .where(
                                        (key) =>
                                            key != 'location_name' &&
                                            key != 'from_location' &&
                                            key != 'to_location',
                                      ),
                                }),
                              ),
                              Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: colors.onSurfaceVariant,
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 16,
                            runSpacing: 6,
                            children: [
                              for (final c in details)
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.sizeOf(context).width - 44,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _label(c),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                      Text(
                                        _value(row, c, withUnit: true),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          fontFeatures: [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (states.isNotEmpty)
                                _cell(context, row, states.first, {}),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, space) {
      final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
      final all = _important;
      if (all.isEmpty) {
        return const Center(child: Text('Open a record to view details.'));
      }
      if (space.maxWidth < 650 * scale.clamp(1, 1.5)) {
        return _cards(context, all, scale);
      }
      final colors = Theme.of(context).colorScheme;
      final fields = all
          .where((c) => showStore || c.key != 'location_name')
          .toList();
      final numberWidth = space.maxWidth >= 1000 ? 30.0 : 0.0;
      const openWidth = 28.0;
      final budget = space.maxWidth - numberWidth - openWidth;
      double minimum() =>
          fields.fold(0, (s, c) => s + _minimum(c) * scale.clamp(1, 1.6));
      while (fields.length > 2 && minimum() > budget) {
        var remove = 1;
        for (var i = 2; i < fields.length; i++) {
          if (_priority(fields[i]) >= _priority(fields[remove])) remove = i;
        }
        fields.removeAt(remove);
      }
      if (minimum() > budget) return _cards(context, all, scale);
      final weight = fields.fold<double>(0, (s, c) => s + _weight(c));
      final extra = budget - minimum();
      final widths = [
        for (final c in fields)
          _minimum(c) * scale.clamp(1, 1.6) + extra * _weight(c) / weight,
      ];
      final visible = fields.map((c) => c.key).toSet();
      Widget rowCells(Map<String, dynamic> row, int index) => Row(
        children: [
          if (numberWidth > 0)
            SizedBox(
              width: numberWidth,
              child: Text(
                '${report.offset + index + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
              ),
            ),
          for (var i = 0; i < fields.length; i++)
            SizedBox(
              key: ValueKey('inventory-cell-$index-${fields[i].key}'),
              width: widths[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                child: _cell(context, row, fields[i], visible),
              ),
            ),
          SizedBox(
            width: openWidth,
            child: Tooltip(
              message: 'View record details',
              child: Icon(
                Icons.chevron_right,
                size: 17,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
      return Column(
        children: [
          Container(
            height: 35 * scale.clamp(1, 1.8),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            child: Row(
              children: [
                if (numberWidth > 0)
                  SizedBox(
                    width: numberWidth,
                    child: Text(
                      '#',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                for (var i = 0; i < fields.length; i++)
                  SizedBox(
                    key: ValueKey('inventory-header-${fields[i].key}'),
                    width: widths[i],
                    child: InkWell(
                      onTap: disabled ? null : () => onSort(fields[i].key),
                      child: Tooltip(
                        message: 'Sort by ${fields[i].label}',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          child: Row(
                            children: [
                              if (fields[i].numeric)
                                SizedBox(
                                  width: 13,
                                  child: sortKey == fields[i].key
                                      ? Icon(
                                          descending
                                              ? Icons.arrow_downward
                                              : Icons.arrow_upward,
                                          size: 12,
                                        )
                                      : null,
                                ),
                              Expanded(
                                child: Text(
                                  _label(fields[i]),
                                  textAlign: fields[i].numeric
                                      ? TextAlign.right
                                      : TextAlign.left,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (!fields[i].numeric)
                                SizedBox(
                                  width: 13,
                                  child: sortKey == fields[i].key
                                      ? Icon(
                                          descending
                                              ? Icons.arrow_downward
                                              : Icons.arrow_upward,
                                          size: 12,
                                        )
                                      : null,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: openWidth),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: controller,
              thumbVisibility: true,
              child: ListView.builder(
                controller: controller,
                padding: EdgeInsets.zero,
                itemCount: report.rows.length,
                itemExtent: 47 * scale.clamp(1, 1.8),
                itemBuilder: (_, i) => Material(
                  color: i.isEven ? colors.surface : colors.surfaceContainerLow,
                  child: InkWell(
                    key: ValueKey('inventory-record-$i'),
                    onTap: () => onOpen(report.rows[i]),
                    hoverColor: colors.primary.withValues(alpha: .055),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: colors.outlineVariant.withValues(alpha: .35),
                            width: .7,
                          ),
                        ),
                      ),
                      child: rowCells(report.rows[i], i),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
