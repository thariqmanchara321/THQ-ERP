import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/inventory_service.dart';

class ProductClassificationPicker extends StatefulWidget {
  const ProductClassificationPicker({
    super.key,
    required this.session,
    this.initialCategory,
    this.initialBrand,
    this.enabled = true,
    required this.onCategoryChanged,
    required this.onBrandChanged,
  });

  final ClientSession session;
  final String? initialCategory;
  final String? initialBrand;
  final bool enabled;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onBrandChanged;

  @override
  State<ProductClassificationPicker> createState() =>
      _ProductClassificationPickerState();
}

class _ProductClassificationPickerState
    extends State<ProductClassificationPicker> {
  final InventoryService _service = InventoryService();

  bool _loading = true;
  String? _error;
  List<String> _categories = const [];
  List<String> _brands = const [];
  late String _category;
  late String _brand;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory?.trim() ?? '';
    _brand = widget.initialBrand?.trim() ?? '';
    _load();
  }

  Future<void> _load({String? selectKind, String? selectName}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final raw = await _service.productClassifications(
        tenantId: widget.session.business.id,
      );

      List<String> names(dynamic value) => (value as List? ?? const [])
          .whereType<Map>()
          .map((row) => row['name']?.toString().trim() ?? '')
          .where((name) => name.isNotEmpty)
          .toList(growable: false);

      final categories = names(raw['categories']);
      final brands = names(raw['brands']);

      if (!mounted) return;

      setState(() {
        _categories = categories;
        _brands = brands;

        if (selectKind == 'category' && selectName != null) {
          _category = selectName;
        } else if (_category.isNotEmpty &&
            !categories.any(
              (name) => name.toLowerCase() == _category.toLowerCase(),
            )) {
          _category = '';
        }

        if (selectKind == 'brand' && selectName != null) {
          _brand = selectName;
        } else if (_brand.isNotEmpty &&
            !brands.any((name) => name.toLowerCase() == _brand.toLowerCase())) {
          _brand = '';
        }
      });

      widget.onCategoryChanged(_category);
      widget.onBrandChanged(_brand);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add(String kind) async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(kind == 'category' ? 'Add Category' : 'Add Brand'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: kind == 'category' ? 'Category name' : 'Brand name',
            hintText: kind == 'category'
                ? 'Example: Starter Motor'
                : 'Example: Bosch',
          ),
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) Navigator.pop(dialogContext, trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;

    try {
      final saved = await _service.addProductClassification(
        tenantId: widget.session.business.id,
        kind: kind,
        name: name,
      );
      final savedName = saved['name']?.toString().trim() ?? name.trim();
      await _load(selectKind: kind, selectName: savedName);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Widget _picker({
    required String kind,
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final label = kind == 'category' ? 'Category' : 'Brand';

    final normalizedValue = value.isNotEmpty && items.contains(value)
        ? value
        : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('$kind-$normalizedValue-${items.length}'),
            initialValue: normalizedValue,
            isExpanded: true,
            dropdownColor: scheme.surface,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              labelText: label,
              helperText: 'Choose only from the saved $label list.',
            ),
            items: [
              DropdownMenuItem<String>(
                value: '',
                child: Text(
                  'No $label',
                  style: TextStyle(color: scheme.onSurface),
                ),
              ),
              ...items.map(
                (name) => DropdownMenuItem<String>(
                  value: name,
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurface),
                  ),
                ),
              ),
            ],
            onChanged: !widget.enabled
                ? null
                : (next) {
                    final selected = next ?? '';
                    setState(() {
                      if (kind == 'category') {
                        _category = selected;
                      } else {
                        _brand = selected;
                      }
                    });
                    onChanged(selected);
                  },
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: IconButton.filledTonal(
            tooltip: 'Add $label',
            onPressed: widget.enabled ? () => _add(kind) : null,
            icon: const Icon(Icons.add, size: 18),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LinearProgressIndicator();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final category = _picker(
              kind: 'category',
              value: _category,
              items: _categories,
              onChanged: widget.onCategoryChanged,
            );
            final brand = _picker(
              kind: 'brand',
              value: _brand,
              items: _brands,
              onChanged: widget.onBrandChanged,
            );

            if (constraints.maxWidth >= 650) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: category),
                  const SizedBox(width: 12),
                  Expanded(child: brand),
                ],
              );
            }

            return Column(
              children: [category, const SizedBox(height: 10), brand],
            );
          },
        ),
      ],
    );
  }
}
