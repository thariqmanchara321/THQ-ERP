import 'package:flutter/material.dart';

import '../foundations/thq_tokens.dart';

class ThqTableColumn {
  const ThqTableColumn({
    required this.label,
    this.width = 140,
    this.alignment = Alignment.centerLeft,
  });

  final String label;
  final double width;
  final Alignment alignment;
}

class ThqTableRow {
  const ThqTableRow({
    required this.cells,
    this.onTap,
    this.selected = false,
    this.semanticLabel,
  });

  final List<Widget> cells;
  final VoidCallback? onTap;
  final bool selected;
  final String? semanticLabel;
}

/// Fixed-header, internally scrolling table for dense ERP workspaces.
class ThqDenseTable extends StatelessWidget {
  const ThqDenseTable({
    required this.columns,
    required this.rows,
    this.empty,
    this.rowHeight = ThqTokens.tableRowCompact,
    this.headerHeight = ThqTokens.tableHeader,
    this.horizontalController,
    this.verticalController,
    super.key,
  });

  final List<ThqTableColumn> columns;
  final List<ThqTableRow> rows;
  final Widget? empty;
  final double rowHeight;
  final double headerHeight;
  final ScrollController? horizontalController;
  final ScrollController? verticalController;

  double get _tableWidth => columns.fold<double>(0, (sum, item) => sum + item.width);

  @override
  Widget build(BuildContext context) {
    assert(columns.isNotEmpty, 'ThqDenseTable requires at least one column.');
    assert(
      rows.every((row) => row.cells.length == columns.length),
      'Every THQ table row must contain one cell per column.',
    );

    final border = Theme.of(context).dividerColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
        child: Scrollbar(
          controller: horizontalController,
          thumbVisibility: false,
          child: SingleChildScrollView(
            controller: horizontalController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _tableWidth,
              child: Column(
                children: [
                  _TableHeader(columns: columns, height: headerHeight),
                  Divider(height: 1, color: border),
                  Expanded(
                    child: rows.isEmpty
                        ? Center(child: empty ?? const Text('No records'))
                        : Scrollbar(
                            controller: verticalController,
                            child: ListView.separated(
                              controller: verticalController,
                              itemCount: rows.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: border),
                              itemBuilder: (context, index) => _DataRow(
                                columns: columns,
                                row: rows[index],
                                height: rowHeight,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.columns, required this.height});

  final List<ThqTableColumn> columns;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (final column in columns)
              SizedBox(
                width: column.width,
                child: Align(
                  alignment: column.alignment,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ThqTokens.space10,
                    ),
                    child: Text(
                      column.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.columns,
    required this.row,
    required this.height,
  });

  final List<ThqTableColumn> columns;
  final ThqTableRow row;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = SizedBox(
      height: height,
      child: Row(
        children: [
          for (var index = 0; index < columns.length; index++)
            SizedBox(
              width: columns[index].width,
              child: Align(
                alignment: columns[index].alignment,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ThqTokens.space10,
                  ),
                  child: row.cells[index],
                ),
              ),
            ),
        ],
      ),
    );

    final interactive = row.onTap == null
        ? content
        : InkWell(onTap: row.onTap, child: content);
    final decorated = ColoredBox(
      color: row.selected
          ? scheme.primaryContainer.withValues(alpha: 0.28)
          : Colors.transparent,
      child: interactive,
    );

    if (row.semanticLabel == null) return decorated;
    return Semantics(label: row.semanticLabel, child: decorated);
  }
}
