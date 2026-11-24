import 'package:flutter/material.dart';

import '../foundations/thq_tokens.dart';

/// Predefined standard date range presets across THQ ERP.
enum ThqDatePreset {
  today('Today'),
  yesterday('Yesterday'),
  days7('7 Days'),
  days30('30 Days'),
  days90('90 Days'),
  thisMonth('This Month'),
  custom('Custom Range');

  final String label;
  const ThqDatePreset(this.label);

  DateTimeRange toRange([DateTime? referenceDate]) {
    final now = referenceDate ?? DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    switch (this) {
      case ThqDatePreset.today:
        return DateTimeRange(start: todayStart, end: todayEnd);
      case ThqDatePreset.yesterday:
        final yStart = todayStart.subtract(const Duration(days: 1));
        final yEnd = DateTime(yStart.year, yStart.month, yStart.day, 23, 59, 59, 999);
        return DateTimeRange(start: yStart, end: yEnd);
      case ThqDatePreset.days7:
        final start = todayStart.subtract(const Duration(days: 6));
        return DateTimeRange(start: start, end: todayEnd);
      case ThqDatePreset.days30:
        final start = todayStart.subtract(const Duration(days: 29));
        return DateTimeRange(start: start, end: todayEnd);
      case ThqDatePreset.days90:
        final start = todayStart.subtract(const Duration(days: 89));
        return DateTimeRange(start: start, end: todayEnd);
      case ThqDatePreset.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        return DateTimeRange(start: start, end: todayEnd);
      case ThqDatePreset.custom:
        return DateTimeRange(start: todayStart.subtract(const Duration(days: 29)), end: todayEnd);
    }
  }
}

/// Standardized, responsive calendar-enabled date range selector for THQ ERP.
class ThqDateRangeSelector extends StatelessWidget {
  const ThqDateRangeSelector({
    required this.selectedRange,
    required this.onRangeChanged,
    this.activePreset,
    this.onPresetChanged,
    this.supportedPresets = const [
      ThqDatePreset.today,
      ThqDatePreset.days7,
      ThqDatePreset.days30,
      ThqDatePreset.days90,
      ThqDatePreset.custom,
    ],
    this.firstDate,
    this.lastDate,
    this.compact = false,
    super.key,
  });

  final DateTimeRange selectedRange;
  final ValueChanged<DateTimeRange> onRangeChanged;
  final ThqDatePreset? activePreset;
  final ValueChanged<ThqDatePreset>? onPresetChanged;
  final List<ThqDatePreset> supportedPresets;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool compact;

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String get _rangeLabel {
    final startStr = _formatDate(selectedRange.start);
    final endStr = _formatDate(selectedRange.end);
    final diffDays = selectedRange.end.difference(selectedRange.start).inDays + 1;
    if (selectedRange.start.year == selectedRange.end.year &&
        selectedRange.start.month == selectedRange.end.month &&
        selectedRange.start.day == selectedRange.end.day) {
      return startStr;
    }
    return '$startStr – $endStr ($diffDays d)';
  }

  Future<void> _pickCustomRange(BuildContext context) async {
    final now = DateTime.now();
    final earliest = firstDate ?? DateTime(2020, 1, 1);
    final latest = lastDate ?? DateTime(now.year + 5, 12, 31);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: earliest,
      lastDate: latest,
      initialDateRange: selectedRange,
      helpText: 'Select Custom Date Range',
      cancelText: 'Cancel',
      confirmText: 'Apply',
    );

    if (picked != null) {
      // Validate start <= end
      final cleanStart = DateTime(picked.start.year, picked.start.month, picked.start.day);
      final cleanEnd = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999);
      if (!cleanEnd.isBefore(cleanStart)) {
        final validated = DateTimeRange(start: cleanStart, end: cleanEnd);
        onPresetChanged?.call(ThqDatePreset.custom);
        onRangeChanged(validated);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = compact || constraints.maxWidth < 580;

        if (isNarrow) {
          return Wrap(
            spacing: ThqTokens.space8,
            runSpacing: ThqTokens.space4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Presets Dropdown
              DropdownButtonHideUnderline(
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                  ),
                  child: DropdownButton<ThqDatePreset>(
                    value: activePreset ?? ThqDatePreset.custom,
                    isDense: true,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    items: supportedPresets.map((p) {
                      return DropdownMenuItem<ThqDatePreset>(
                        value: p,
                        child: Text(p.label),
                      );
                    }).toList(),
                    onChanged: (newPreset) {
                      if (newPreset == null) return;
                      if (newPreset == ThqDatePreset.custom) {
                        _pickCustomRange(context);
                      } else {
                        onPresetChanged?.call(newPreset);
                        onRangeChanged(newPreset.toRange());
                      }
                    },
                  ),
                ),
              ),

              // Calendar Picker Button
              OutlinedButton.icon(
                onPressed: () => _pickCustomRange(context),
                icon: const Icon(Icons.calendar_month_outlined, size: 16),
                label: Text(
                  _rangeLabel,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                ),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
                  ),
                ),
              ),
            ],
          );
        }

        // Desktop / Wide layout
        return Wrap(
          spacing: ThqTokens.space8,
          runSpacing: ThqTokens.space4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Preset Segmented Chips / Buttons
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              padding: const EdgeInsets.all(2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: supportedPresets.where((p) => p != ThqDatePreset.custom).map((p) {
                  final isSelected = activePreset == p;
                  return InkWell(
                    onTap: () {
                      onPresetChanged?.call(p);
                      onRangeChanged(p.toRange());
                    },
                    borderRadius: BorderRadius.circular(ThqTokens.radiusSmall),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: isSelected ? colorScheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(ThqTokens.radiusSmall),
                      ),
                      child: Text(
                        p.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // Calendar Range Picker Button
            OutlinedButton.icon(
              onPressed: () => _pickCustomRange(context),
              icon: Icon(
                Icons.calendar_month,
                size: 15,
                color: activePreset == ThqDatePreset.custom ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              label: Text(
                _rangeLabel,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: activePreset == ThqDatePreset.custom ? FontWeight.w600 : FontWeight.w500,
                  color: activePreset == ThqDatePreset.custom ? colorScheme.primary : colorScheme.onSurface,
                ),
              ),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                side: BorderSide(
                  color: activePreset == ThqDatePreset.custom
                      ? colorScheme.primary
                      : colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
