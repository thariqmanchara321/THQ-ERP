import 'package:flutter/material.dart';

import '../components/thq_fields.dart';
import '../foundations/thq_breakpoints.dart';
import '../foundations/thq_tokens.dart';

/// Dense search/filter/action strip used above THQ data workspaces.
class ThqFilterBar extends StatelessWidget {
  const ThqFilterBar({
    this.searchController,
    this.searchHint = 'Search',
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.filters = const <Widget>[],
    this.actions = const <Widget>[],
    this.activeFilterCount = 0,
    this.onClearFilters,
    super.key,
  });

  final TextEditingController? searchController;
  final String searchHint;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;
  final List<Widget> filters;
  final List<Widget> actions;
  final int activeFilterCount;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < ThqBreakpoints.desktop;
        final search = SizedBox(
          width: compact ? double.infinity : 280,
          child: ThqSearchField(
            controller: searchController,
            hint: searchHint,
            onChanged: onSearchChanged,
            onSubmitted: onSearchSubmitted,
          ),
        );
        final clear = activeFilterCount > 0 && onClearFilters != null
            ? TextButton.icon(
                onPressed: onClearFilters,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: Text('Clear ($activeFilterCount)'),
              )
            : null;

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              if (filters.isNotEmpty || clear != null) ...[
                const SizedBox(height: ThqTokens.space8),
                Wrap(
                  spacing: ThqTokens.space8,
                  runSpacing: ThqTokens.space8,
                  children: [
                    ...filters,
                    if (clear != null) clear,
                  ],
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: ThqTokens.space8),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: ThqTokens.space8,
                  runSpacing: ThqTokens.space8,
                  children: actions,
                ),
              ],
            ],
          );
        }

        return Row(
          children: [
            search,
            if (filters.isNotEmpty) ...[
              const SizedBox(width: ThqTokens.space8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var index = 0; index < filters.length; index++) ...[
                        if (index > 0)
                          const SizedBox(width: ThqTokens.space8),
                        filters[index],
                      ],
                      if (clear != null) ...[
                        const SizedBox(width: ThqTokens.space8),
                        clear,
                      ],
                    ],
                  ),
                ),
              ),
            ] else
              const Spacer(),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: ThqTokens.space12),
              Wrap(
                spacing: ThqTokens.space8,
                runSpacing: ThqTokens.space8,
                children: actions,
              ),
            ],
          ],
        );
      },
    );
  }
}

class ThqFilterChip extends StatelessWidget {
  const ThqFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    super.key,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      onSelected: onSelected,
      avatar: icon == null ? null : Icon(icon, size: ThqTokens.iconSmall),
      label: Text(label),
    );
  }
}
