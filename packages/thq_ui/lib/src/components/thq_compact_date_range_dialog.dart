import 'package:flutter/material.dart';

import '../foundations/thq_tokens.dart';
import 'thq_date_range_selector.dart';

/// Shows a compact, modal calendar date-range picker dialog.
///
/// Designed to replace full-screen modal pickers with a clean,
/// responsive, data-dense popup suitable for desktop and mobile viewports.
Future<DateTimeRange?> showThqCompactDateRangePicker({
  required BuildContext context,
  required DateTimeRange initialRange,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = 'Select Date Range',
}) {
  return showDialog<DateTimeRange>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => ThqCompactDateRangeDialog(
      initialRange: initialRange,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
    ),
  );
}

/// Compact date range picker dialog with quick presets and responsive calendar.
class ThqCompactDateRangeDialog extends StatefulWidget {
  const ThqCompactDateRangeDialog({
    required this.initialRange,
    this.firstDate,
    this.lastDate,
    this.title = 'Select Date Range',
    super.key,
  });

  final DateTimeRange initialRange;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String title;

  @override
  State<ThqCompactDateRangeDialog> createState() =>
      _ThqCompactDateRangeDialogState();
}

class _ThqCompactDateRangeDialogState extends State<ThqCompactDateRangeDialog> {
  late DateTime _viewMonth;
  late DateTime _start;
  DateTime? _end;
  ThqDatePreset? _selectedPreset;

  DateTime get _minDate => widget.firstDate ?? DateTime(2020, 1, 1);
  DateTime get _maxDate =>
      widget.lastDate ??
      DateTime.now().add(const Duration(days: 365));

  @override
  void initState() {
    super.initState();
    _start = DateTime(
      widget.initialRange.start.year,
      widget.initialRange.start.month,
      widget.initialRange.start.day,
    );
    _end = DateTime(
      widget.initialRange.end.year,
      widget.initialRange.end.month,
      widget.initialRange.end.day,
    );
    _viewMonth = DateTime(_start.year, _start.month, 1);
    _matchActivePreset();
  }

  void _matchActivePreset() {
    if (_end == null) {
      _selectedPreset = ThqDatePreset.custom;
      return;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final preset in [
      ThqDatePreset.today,
      ThqDatePreset.yesterday,
      ThqDatePreset.days7,
      ThqDatePreset.days30,
      ThqDatePreset.thisMonth,
    ]) {
      final r = preset.toRange(today);
      final rStart = DateTime(r.start.year, r.start.month, r.start.day);
      final rEnd = DateTime(r.end.year, r.end.month, r.end.day);
      if (_start == rStart && _end == rEnd) {
        _selectedPreset = preset;
        return;
      }
    }
    _selectedPreset = ThqDatePreset.custom;
  }

  void _applyPreset(ThqDatePreset preset) {
    final range = preset.toRange();
    setState(() {
      _selectedPreset = preset;
      _start = DateTime(range.start.year, range.start.month, range.start.day);
      _end = DateTime(range.end.year, range.end.month, range.end.day);
      _viewMonth = DateTime(_start.year, _start.month, 1);
    });
  }

  void _onDayTapped(DateTime day) {
    setState(() {
      _selectedPreset = ThqDatePreset.custom;
      if (_end != null) {
        // Reset and select new start
        _start = day;
        _end = null;
      } else {
        // We have start, now pick end
        if (day.isBefore(_start)) {
          _end = _start;
          _start = day;
        } else {
          _end = day;
        }
      }
    });
  }

  void _prevMonth() {
    final prev = DateTime(_viewMonth.year, _viewMonth.month - 1, 1);
    if (!prev.isBefore(DateTime(_minDate.year, _minDate.month, 1))) {
      setState(() => _viewMonth = prev);
    }
  }

  void _nextMonth() {
    final next = DateTime(_viewMonth.year, _viewMonth.month + 1, 1);
    if (!next.isAfter(DateTime(_maxDate.year, _maxDate.month, 1))) {
      setState(() => _viewMonth = next);
    }
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _formatMonthYear(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveEnd = _end ?? _start;
    final diffDays = effectiveEnd.difference(_start).inDays + 1;

    final rangeText = _end == null
        ? '${_formatDate(_start)} – Select end date'
        : '${_formatDate(_start)} – ${_formatDate(_end!)} ($diffDays day${diffDays > 1 ? 's' : ''})';

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 380,
          maxHeight: 520,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header & Range Summary
              Row(
                children: [
                  Icon(Icons.calendar_month, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(ThqTokens.radiusSmall),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  rangeText,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 10),

              // Quick Presets Row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final preset in const [
                      ThqDatePreset.today,
                      ThqDatePreset.yesterday,
                      ThqDatePreset.days7,
                      ThqDatePreset.days30,
                      ThqDatePreset.thisMonth,
                    ]) ...[
                      _presetChip(preset, colorScheme),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Month Navigation Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: _prevMonth,
                  ),
                  Text(
                    _formatMonthYear(_viewMonth),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: _nextMonth,
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Calendar Days of Week
              Row(
                children: const [
                  _DayHeader('M'),
                  _DayHeader('T'),
                  _DayHeader('W'),
                  _DayHeader('T'),
                  _DayHeader('F'),
                  _DayHeader('S'),
                  _DayHeader('S'),
                ],
              ),
              const Divider(height: 8),

              // Calendar Month Grid
              Flexible(
                child: _buildMonthGrid(colorScheme),
              ),
              const SizedBox(height: 10),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final cleanStart = DateTime(
                        _start.year,
                        _start.month,
                        _start.day,
                      );
                      final endDay = _end ?? _start;
                      final cleanEnd = DateTime(
                        endDay.year,
                        endDay.month,
                        endDay.day,
                        23,
                        59,
                        59,
                        999,
                      );
                      Navigator.of(context).pop(
                        DateTimeRange(start: cleanStart, end: cleanEnd),
                      );
                    },
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: const Text('Apply', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetChip(ThqDatePreset preset, ColorScheme colorScheme) {
    final isSelected = _selectedPreset == preset;
    return InkWell(
      onTap: () => _applyPreset(preset),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Text(
          preset.label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildMonthGrid(ColorScheme colorScheme) {
    final firstDayOfMonth = DateTime(_viewMonth.year, _viewMonth.month, 1);
    final daysInMonth =
        DateTime(_viewMonth.year, _viewMonth.month + 1, 0).day;

    // Monday is 1, Sunday is 7 in Dart
    final leadingSpaces = (firstDayOfMonth.weekday - 1);
    final totalCells = ((leadingSpaces + daysInMonth + 6) ~/ 7) * 7;

    final effectiveEnd = _end ?? _start;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: totalCells,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 1.25,
      ),
      itemBuilder: (context, index) {
        if (index < leadingSpaces || index >= leadingSpaces + daysInMonth) {
          return const SizedBox.shrink();
        }

        final dayNumber = index - leadingSpaces + 1;
        final cellDate = DateTime(_viewMonth.year, _viewMonth.month, dayNumber);

        final isDisabled =
            cellDate.isBefore(DateTime(_minDate.year, _minDate.month, _minDate.day)) ||
            cellDate.isAfter(DateTime(_maxDate.year, _maxDate.month, _maxDate.day));

        final isStart = cellDate == _start;
        final isEnd = cellDate == effectiveEnd;
        final isInRange =
            cellDate.isAfter(_start) && cellDate.isBefore(effectiveEnd);

        Color? bgColor;
        Color textColor = colorScheme.onSurface;
        FontWeight fontWeight = FontWeight.normal;

        if (isStart || isEnd) {
          bgColor = colorScheme.primary;
          textColor = colorScheme.onPrimary;
          fontWeight = FontWeight.bold;
        } else if (isInRange) {
          bgColor = colorScheme.primaryContainer.withValues(alpha: 0.45);
          textColor = colorScheme.primary;
          fontWeight = FontWeight.w600;
        }

        if (isDisabled) {
          textColor = colorScheme.onSurface.withValues(alpha: 0.3);
        }

        return InkWell(
          onTap: isDisabled ? null : () => _onDayTapped(cellDate),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              '$dayNumber',
              style: TextStyle(
                fontSize: 11,
                color: textColor,
                fontWeight: fontWeight,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}
