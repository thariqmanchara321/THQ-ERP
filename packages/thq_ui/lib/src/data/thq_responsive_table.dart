import 'package:flutter/material.dart';

import '../foundations/thq_tokens.dart';

/// Column specification for [ThqResponsiveTable].
class ThqResponsiveColumn {
  const ThqResponsiveColumn({
    required this.title,
    this.flex = 2,
    this.alignment = Alignment.centerLeft,
    this.isNumeric = false,
  });

  final String title;
  final int flex;
  final Alignment alignment;
  final bool isNumeric;
}

/// Row specification for [ThqResponsiveTable].
class ThqResponsiveRow {
  const ThqResponsiveRow({
    required this.cells,
    this.cardTitle,
    this.cardBadge,
    this.cardFields = const [],
    this.onTap,
    this.onViewDetails,
    this.detailsBuilder,
  });

  /// Cells matching the columns for desktop table rendering.
  final List<Widget> cells;

  /// Primary title for mobile card rendering (e.g. Product or Party Name).
  final Widget? cardTitle;

  /// Status badge or pill for mobile card rendering.
  final Widget? cardBadge;

  /// Key-value pairs for mobile card view (e.g. [('Available', '140'), ('Reorder', '50')]).
  final List<(String, String)> cardFields;

  final VoidCallback? onTap;
  final VoidCallback? onViewDetails;
  final WidgetBuilder? detailsBuilder;
}

/// Fully responsive, zero-horizontal-scroll table for THQ ERP reports and workspaces.
///
/// Automatically fits desktop viewports using proportional flex columns, and converts
/// to compact stacked record cards on mobile/narrow viewports.
class ThqResponsiveTable extends StatelessWidget {
  const ThqResponsiveTable({
    required this.columns,
    required this.rows,
    this.emptyMessage = 'No records found',
    this.mobileBreakpoint = 720,
    this.headerHeight = 38,
    this.rowHeight = 44,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final List<ThqResponsiveColumn> columns;
  final List<ThqResponsiveRow> rows;
  final String emptyMessage;
  final double mobileBreakpoint;
  final double headerHeight;
  final double rowHeight;
  final EdgeInsetsGeometry padding;

  void _showRecordDetails(BuildContext context, ThqResponsiveRow row) {
    if (row.detailsBuilder != null) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 650),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Record Details',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const Divider(),
                  Flexible(
                    child: SingleChildScrollView(
                      child: row.detailsBuilder!(ctx),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else if (row.onViewDetails != null) {
      row.onViewDetails!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dividerColor = theme.dividerColor;

    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Text(
          emptyMessage,
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < mobileBreakpoint;

        // Mobile View: Stacked record cards
        if (isMobile) {
          return ListView.separated(
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            padding: padding,
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = rows[index];
              return Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
                  side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: InkWell(
                  onTap: row.onTap ?? (row.detailsBuilder != null || row.onViewDetails != null
                      ? () => _showRecordDetails(context, row)
                      : null),
                  borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Card Header
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: row.cardTitle ??
                                  (row.cells.isNotEmpty ? row.cells.first : const SizedBox.shrink()),
                            ),
                            if (row.cardBadge != null) ...[
                              const SizedBox(width: 8),
                              row.cardBadge!,
                            ],
                          ],
                        ),

                        // Card Key-Value fields
                        if (row.cardFields.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            children: row.cardFields.map((field) {
                              return SizedBox(
                                width: (constraints.maxWidth - 48) / 2 > 130
                                    ? (constraints.maxWidth - 48) / 2
                                    : constraints.maxWidth - 36,
                                child: Row(
                                  children: [
                                    Text(
                                      '${field.$1}: ',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        field.$2,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],

                        // Actions
                        if (row.detailsBuilder != null || row.onViewDetails != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () => _showRecordDetails(context, row),
                                icon: const Icon(Icons.info_outline, size: 14),
                                label: const Text('View Details', style: TextStyle(fontSize: 11.5)),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }

        // Desktop View: Proportional flex columns table (Fits 100% width, no horizontal scroll)
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Row
                Container(
                  height: headerHeight,
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      for (final col in columns)
                        Expanded(
                          flex: col.flex,
                          child: Align(
                            alignment: col.alignment,
                            child: Text(
                              col.title,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: dividerColor),

                // Data Rows
                ListView.separated(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: dividerColor),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return InkWell(
                      onTap: row.onTap ?? (row.detailsBuilder != null || row.onViewDetails != null
                          ? () => _showRecordDetails(context, row)
                          : null),
                      child: Container(
                        height: rowHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            for (var colIdx = 0; colIdx < columns.length; colIdx++)
                              Expanded(
                                flex: columns[colIdx].flex,
                                child: Align(
                                  alignment: columns[colIdx].alignment,
                                  child: colIdx < row.cells.length
                                      ? row.cells[colIdx]
                                      : const SizedBox.shrink(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
