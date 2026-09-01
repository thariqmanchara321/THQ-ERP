import 'package:flutter/material.dart';

class SearchableSelectOption<T> {
  final T value;
  final String label;
  final String searchText;
  final String? subtitle;

  const SearchableSelectOption({
    required this.value,
    required this.label,
    String? searchText,
    this.subtitle,
  }) : searchText = searchText ?? label;
}

class SearchableSelect<T> extends StatelessWidget {
  final T? value;
  final List<SearchableSelectOption<T>> options;
  final ValueChanged<T?>? onChanged;
  final String labelText;
  final String? hintText;
  final bool isRequired;
  final bool enabled;
  final bool allowClear;
  final IconData prefixIcon;
  final String? Function(T?)? validator;

  const SearchableSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.labelText,
    this.hintText,
    this.isRequired = false,
    this.enabled = true,
    this.allowClear = false,
    this.prefixIcon = Icons.search,
    this.validator,
  });

  SearchableSelectOption<T>? get _selected {
    for (final option in options) {
      if (option.value == value) return option;
    }
    return null;
  }

  Future<void> _pick(BuildContext context) async {
    if (!enabled || onChanged == null) return;
    final result = await showDialog<_SearchResult<T>>(
      context: context,
      builder: (_) => _SearchableSelectDialog<T>(
        title: labelText.replaceAll(' *', ''),
        options: options,
        selected: value,
        allowClear: allowClear,
        hintText: hintText,
      ),
    );
    if (result == null) return;
    onChanged?.call(result.cleared ? null : result.value);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final effectiveLabel = isRequired && !labelText.endsWith('*')
        ? '$labelText *'
        : labelText;
    final error = validator?.call(value);
    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        isEmpty: selected == null,
        decoration: InputDecoration(
          labelText: effectiveLabel,
          hintText: hintText ?? 'Search and select',
          border: const OutlineInputBorder(),
          prefixIcon: Icon(prefixIcon),
          suffixIcon: Icon(
            Icons.search,
            color: enabled
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).disabledColor,
          ),
          enabled: enabled,
          errorText: error,
        ),
        child: selected == null
            ? Text(
                hintText ?? 'Search and select',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).hintColor),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selected.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((selected.subtitle ?? '').trim().isNotEmpty)
                    Text(
                      selected.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
      ),
    );
  }
}

class _SearchResult<T> {
  final T? value;
  final bool cleared;
  const _SearchResult.value(this.value) : cleared = false;
  const _SearchResult.clear() : value = null, cleared = true;
}

class _SearchableSelectDialog<T> extends StatefulWidget {
  final String title;
  final List<SearchableSelectOption<T>> options;
  final T? selected;
  final bool allowClear;
  final String? hintText;

  const _SearchableSelectDialog({
    required this.title,
    required this.options,
    required this.selected,
    required this.allowClear,
    this.hintText,
  });

  @override
  State<_SearchableSelectDialog<T>> createState() =>
      _SearchableSelectDialogState<T>();
}

class _SearchableSelectDialogState<T>
    extends State<_SearchableSelectDialog<T>> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SearchableSelectOption<T>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.options.take(100).toList();
    final starts = <SearchableSelectOption<T>>[];
    final contains = <SearchableSelectOption<T>>[];
    for (final option in widget.options) {
      final haystack = '${option.label} ${option.subtitle ?? ''} ${option.searchText}'
          .toLowerCase();
      final tokens = haystack.split(RegExp(r'\s+'));
      if (haystack.startsWith(q) || tokens.any((token) => token.startsWith(q))) {
        starts.add(option);
      } else if (haystack.contains(q)) {
        contains.add(option);
      }
      if (starts.length + contains.length >= 150) break;
    }
    return [...starts, ...contains];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      title: Text(widget.title),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                labelText: 'Search',
                hintText: widget.hintText ??
                    'Type name, code, phone, barcode, SKU or reference',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('No matching items.'))
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final option = rows[index];
                        return ListTile(
                          dense: true,
                          selected: option.value == widget.selected,
                          leading: option.value == widget.selected
                              ? const Icon(Icons.check_circle)
                              : const Icon(Icons.search_outlined),
                          title: Text(option.label),
                          subtitle: (option.subtitle ?? '').trim().isEmpty
                              ? null
                              : Text(option.subtitle!),
                          onTap: () => Navigator.pop(
                            context,
                            _SearchResult<T>.value(option.value),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.allowClear)
          TextButton.icon(
            onPressed: () => Navigator.pop(
              context,
              _SearchResult<T>.clear(),
            ),
            icon: const Icon(Icons.clear),
            label: const Text('Clear selection'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
